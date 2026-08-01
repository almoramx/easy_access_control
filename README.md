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
creating `permissions`, `roles`, `role_permissions`, `role_assignments`, `permission_overrides`,
and `global_permissions`.

### Existing tables (brownfield)

If your app already has tables named `permissions`, `roles`, `role_permissions`,
`role_assignments`, `permission_overrides`, or `global_permissions` — with production data —
skip `easy_access_control:install:migrations`; running it will attempt a `create_table` that
collides with what you already have.

Instead, write your own migration that renames your existing subject/scope columns on
`role_assignments`, `permission_overrides`, and `global_permissions` to `subject_id`/`scope_id`
(e.g. `employee_id` → `subject_id`, `warehouse_id` → `scope_id`), since the gem's models query
those column names unconditionally.

Then diff your schema against the gem's
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
