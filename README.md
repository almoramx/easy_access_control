# EasyAccessControl

Toggleable, optionally scope-aware RBAC on top of [Pundit](https://github.com/varvet/pundit).

Subjects (your user model) get roles, and roles grant permissions. Permissions are
`module.action` strings (e.g. `"orders.list"`). Roles — and therefore permissions — can be
assigned per scope (e.g. per warehouse, per tenant) or globally, per-subject overrides can flip
any permission on or off, and a subject-level admin flag bypasses all of it.

## Installation

```ruby
# Gemfile
gem "easy_access_control", git: "https://github.com/almoramx/easy_access_control"
```

```
$ bundle install
$ bin/rails easy_access_control:install:migrations
$ bin/rails db:migrate
```

The install task copies `create_easy_access_control_tables` into your app's `db/migrate`,
creating `easy_access_control_permissions`, `easy_access_control_roles`,
`easy_access_control_role_permissions`, `easy_access_control_role_assignments`,
`easy_access_control_permission_overrides`, and `easy_access_control_global_permissions`.

All gem tables share the `table_prefix` configured below (default `"easy_access_control_"`),
so they never collide with your app's own `permissions` or `roles` tables. Set the prefix
*before* running the install migration — it reads the config.

### Existing tables (brownfield)

If your app already has the gem's tables *without* the prefix (installs prior to v0.2.0), set

```ruby
config.table_prefix = ""
```

and skip `easy_access_control:install:migrations` — nothing else changes.

If your app has its own home-grown `permissions`/`roles` tables you want the gem to take over,
write your own migration that renames your existing subject/scope columns on
`role_assignments`, `permission_overrides`, and `global_permissions` to `subject_id`/`scope_id`
(e.g. `employee_id` → `subject_id`, `warehouse_id` → `scope_id`), since the gem's models query
those column names unconditionally. Then diff your schema against the gem's
`db/migrate/20260801000001_create_easy_access_control_tables.rb`, in particular the `permissions`
table's `module_name` column and the unique indexes on `role_permissions`, `role_assignments`,
`permission_overrides`, and `global_permissions`, and add whatever is missing.

## Configuration

```ruby
# config/initializers/easy_access_control.rb
EasyAccessControl.configure do |config|
  config.subject_class = "User"
  config.scope_class = "Warehouse"
  config.admin_method = :is_administrator?
  config.global_modules = %w[config]
  config.role_names = %w[admin manager seller]
  config.current_scope = -> { Current.warehouse }
end
```

- `subject_class` — the model that includes `EasyAccessControl::Subject` (documentation only;
  the gem does not read this back).
- `scope_class` — the model permissions and roles can be scoped to (e.g. `"Warehouse"`). Set it
  to `nil` (the default) to run in unscoped mode: every `role_assignment`, `permission_override`,
  and `can?` check ignores scope, and a missing scope is never treated as a denial.
- `admin_method` — the method called on a subject to decide unconditional bypass. Defaults to
  `:is_administrator?`.
- `global_modules` — module names (the part of a key before the dot) whose permissions are
  granted per-subject via `global_permissions` instead of through roles/scopes.
- `role_names` — when non-empty, `EasyAccessControl::Role#name` is validated to be one of these.
  Leave empty to allow any role name.
- `current_scope` — a zero-arg lambda used as the fallback scope wherever a scope isn't passed
  explicitly (`Subject#can?`, `ResolvedAccess.new`). Defaults to `-> { nil }`.
- `table_prefix` — prefix for every gem table name. Defaults to `"easy_access_control_"`.
  Set it to `""` for pre-v0.2.0 installs whose tables are unprefixed. Must be set before any
  gem model is loaded (an initializer is early enough).

## Subject

```ruby
class User < ApplicationRecord
  include EasyAccessControl::Subject
end
```

This adds `role_assignments`, `permission_overrides`, and `global_permissions` associations,
plus:

```ruby
user.can?("orders.list")                       # uses EasyAccessControl.current_scope
user.can?("orders.list", scope: warehouse)      # explicit scope
user.access_admin?                              # true if admin_method returns truthy

user.role_at(warehouse)                         # => the Role assigned at that scope, or nil
user.role_at(nil)                                # => the unscoped/global role assignment

permission = EasyAccessControl::Permission.find_by!(key: "orders.list")
user.toggle_override!(permission: permission, scope: warehouse)
user.toggle_override!(permission: "orders.list", scope: warehouse)
```

`can?` resolves in this order: admin bypass, then global-module grant, then per-scope override,
then the role assigned at that scope. In scoped mode (`scope_class` set), a `nil` target scope
denies non-global permissions outright.

`toggle_override!` flips relative to what the role would otherwise grant: if the subject has no
override yet, it creates one with the opposite effect of the role's default (`grant` if the role
doesn't already grant it, `deny` if it does); calling it again removes the override. It accepts
either a `Permission` record or a key string, and returns the created override (or `nil` when it
just destroyed one).

It raises `ArgumentError` for two inputs `can?` would never consult, so admin UIs don't persist
dead rows that look like they toggled something: a global-module permission (`can?` resolves
those via `global_permissions`, never overrides), and `scope: nil` while
`EasyAccessControl.scoped?` is true (the deny gate in `can?` makes nil-scope overrides
unreachable in scoped mode).

### Role stamping

```ruby
user.apply_role!(role, scope: warehouse)
```

`apply_role!` is the template alternative to live role assignment: it makes the subject's
access match the role **exactly, once**, with no ongoing link — editing the role later changes
nobody already stamped. At the given scope it removes any `role_assignment` and every
`permission_override`, then grants the role's scoped permissions as `grant` overrides; the
subject's `global_permissions` are replaced by the role's global-module permissions (note:
globals are subject-wide, so the last stamp wins across scopes). Like `toggle_override!`, it
raises `ArgumentError` when `scope` is nil in scoped mode. Roles can hold global-module
permissions for exactly this purpose; the live `can?` role path simply never consults them.

## Controller integration

```ruby
class ApplicationController < ActionController::Base
  include EasyAccessControl::Controller

  after_action :verify_authorized

  rescue_from Pundit::NotAuthorizedError do
    head :forbidden
  end

  private

  def pundit_user
    EasyAccessControl::Context.new(subject: current_user, scope: current_warehouse)
  end
end
```

`EasyAccessControl::Controller` includes `Pundit::Authorization`, so ordinary Pundit flows
(`authorize record, :list?`, policy-backed `Scope`s) work as-is against policies whose `initialize`
understands `Context`. `pundit_user` can return either a `Context` (subject + scope) or a bare
subject.

On top of that it adds a transitional shim for callers that only have a permission key, not a
record:

```ruby
class OrdersController < ApplicationController
  def index
    authorize!("orders.list")
    @orders = Order.all
  end
end
```

`authorize!(key, scope: nil)` raises `Pundit::NotAuthorizedError` when `subject.can?` is false,
and calls `skip_authorization` so `verify_authorized` is satisfied either way. `after_action
:verify_authorized` still fails the request if an action calls neither `authorize`/`authorize!`
nor `skip_authorization`.

`can?(key, scope: nil)` is also available (and exposed as a helper method): a boolean, scope
defaulting to the `Context`'s, memoized per request so a view can ask per row without re-querying.

## View gates and debug UI

Markup that depends on a permission goes through `permitted`, never a bare `if can?`:

```erb
<%= permitted("orders.create", scope: @warehouse) do %>
  <%= link_to "New order", new_order_path %>
<% end %>
```

It renders the block only when the subject holds the key. Turn on debug mode and every gate is
boxed with its key (`orders.create · Central`), denied ones in red with just the tag (the block
is not rendered — it usually depends on data the action never loaded), and `eac_debug_toolbar`
prints the keys the action demanded through `authorize!`:

```ruby
# config/initializers/easy_access_control.rb
config.debug_ui = ->(controller) { Rails.env.development? && controller.session[:permissions_debug] }
```

```erb
<%# app/views/layouts/application.html.erb %>
<%= eac_debug_toolbar %>
```

Where a wrapping `<div>` is impossible — a permission-gated table column — make the gate the
element itself with `as:`; extra attributes pass through and, in debug, the cell gets the key as a
corner label and `title` tooltip instead of a wrapper:

```erb
<%= permitted("orders.costs", scope: @warehouse, as: :th, class: "text-right") { "Cost" } %>
<%= permitted("orders.costs", scope: @warehouse, as: :td, class: "text-right") { money(line.cost) } %>
```

The toolbar carries its own `<style>`; nothing to add to the asset pipeline. Keep a `can?`
boolean only where the result feeds a component argument (a `colspan`, an empty-state subtitle).

## Writing policies

```ruby
class OrdersPolicy < EasyAccessControl::Policy
  permits :list, :create

  def export?
    can?(:list) && record.exportable?
  end

  class Scope < EasyAccessControl::Policy::Scope
    def resolve
      EasyAccessControl.scoped? ? relation.where(warehouse_id: context_scope&.id) : relation
    end
  end
end
```

- `permission_module(name = nil)` — get or set the module prefix used to build keys. Defaults to
  the class name, demodulized, with the `Policy` suffix stripped and underscored (so
  `OrdersPolicy` → `"orders"`; call `permission_module "sap_invoices"` to override it).
- `permits(*actions)` — defines `action?` methods that each call `can?(action)`.
- `can?(action)` — builds the key `"#{permission_module}.#{action}"` and asks
  `subject.can?(key, scope: context_scope)`; always `false` for a `nil` subject.
- Hand-written methods can compose `can?` with domain logic, as `export?` does above.
- `EasyAccessControl::Policy::Scope` is Pundit's `Scope` pattern: `subject`/`context_scope` come
  from unwrapping the same `Context`, and the base `resolve` returns the relation unchanged —
  override it as shown to add scope filtering.

`Policy.new(user, record)` accepts either a `Context` or a bare subject via
`EasyAccessControl::Context.unwrap`.

## ResolvedAccess

For admin UIs that need to render every permission's current state:

```ruby
EasyAccessControl::ResolvedAccess.new(user, scope: warehouse).states
# => [#<data PermState permission=#<Permission key="orders.list">, on=true, source=:role>, ...]
```

`states` returns one `EasyAccessControl::ResolvedAccess::PermState` (a `Data` with `permission`,
`on`, `source`) per `Permission`, ordered by module then key. `source` is one of `:admin`,
`:global`, `:role`, `:grant`, or `:deny`. `scope:` defaults to `EasyAccessControl.current_scope`
when omitted.

## Rake tasks

```
$ bin/rails easy_access_control:sync    # create any Permission rows missing from policies/authorize! call sites
$ bin/rails easy_access_control:check   # exit 1 if the catalog has drifted (missing or orphaned keys)
$ bin/rails easy_access_control:prune   # delete Permission rows no longer referenced anywhere
```

The expected key set is the union of every `permits`/hand-written `?`-suffixed public method on
`EasyAccessControl::Policy` subclasses, plus every literal `"module.action"` string passed to
`authorize!` under `app/**/*.{rb,erb}`.

## Testing helpers

```ruby
require "easy_access_control/testing"
require "easy_access_control/testing/shared_examples"

RSpec.describe "authorization coverage" do
  it "authorizes every route" do
    expect(EasyAccessControl::Testing.unverified_routes(exempt: ["health#show"])).to eq([])
  end
end

RSpec.describe SellerPolicy do
  let(:subject_with_role) { seller_with_role_at(assigned_scope) }
  let(:assigned_scope) { warehouses(:a) }
  let(:other_scope) { warehouses(:b) }
  let(:granted_key) { "orders.list" }

  include_examples "scope-isolated permissions"
end
```

`EasyAccessControl::Testing.unverified_routes(exempt: [])` lists every routed
`"controller#action"` whose controller class doesn't declare an `after_action :verify_authorized`
callback (skip entries you've deliberately exempted).

The `"scope-isolated permissions"` shared example asserts that a role granted at one scope does
not carry over to another; it expects `subject_with_role`, `granted_key`, `assigned_scope`, and
`other_scope` to be defined in the including group.

## Known ceilings

1. Unique indexes do not fire for `NULL` `scope_id` (most databases treat every `NULL` as
   distinct), so the schema's uniqueness constraints on `role_assignments`,
   `permission_overrides`, and `global_permissions` don't stop duplicate unscoped rows at the
   database level. The model validations are the actual guard — always create and toggle these
   through `Subject`/the models, never with raw inserts.
2. `Testing.unverified_routes` checks callback presence per controller, not per action:
   `verified?` walks the whole controller's `_process_action_callbacks` for `verify_authorized`,
   so a controller with `after_action :verify_authorized` plus a per-action
   `skip_after_action :verify_authorized, only: :some_action` still reads as fully verified, and
   that carve-out won't show up as a gap.
3. The admin bypass (`access_admin?`) is unconditional: once `admin_method` returns truthy,
   every `can?` check for that subject returns `true`. It cannot be attenuated to "admin for some
   modules" or overridden by a `permission_override`.
4. `Sync.policy_keys` treats every `?`-suffixed public policy method as a permission key,
   including pure-domain methods that never consult `can?` at all, and regardless of which key
   (if any) the method's own `can?` calls actually use. `export?` above still produces an
   `orders.export` permission row, even though it calls `can?(:list)`, not `can?(:export)`.
5. `Sync::AUTHORIZE_PATTERN` only matches `authorize!` calls with a single-dot literal string key,
   parens optional (`authorize!("orders.list")` and `authorize! "orders.list"` both match).
   Dynamic or interpolated keys (`authorize!("orders.#{action}")`, a key built from a constant or
   variable) are invisible to `sync`/`check`/`prune`.
6. `permitted` without `as:` wraps its block in a block-level `<div>`: browsers foster-parent a
   `<div>` placed directly inside `<table>`/`<tr>`, so gated cells must use `as: :th`/`as: :td`.
   Slot calls (`component.with_x do … end`) can't be boxed either — put `permitted` inside the
   slot block, not around the slot.
