# easy_access_control — shared RBAC gem design

Date: 2026-08-01
Status: draft, pending user review

## Context

Mascomida and Gaviota each carry a hand-rolled RBAC system. Both are custom
(no authorization gems), Rails 8.1, with a `permissions` catalog, closed role
sets, role→permission templates, an admin bypass, a catalog sync rake task,
and a route-coverage test. They diverge on everything else:

| | Gaviota | Mascomida |
|---|---|---|
| Key format | `controller#action` (derived) | `module.action` (explicit) |
| Runtime resolution | Materialized `employee_permissions` rows; role is a one-time creation template | Live chain: admin → global grant → per-store override → role default |
| Scoping | Global, single org | Per `Warehouse` (`role_assignments`, `permission_overrides`) plus a global tier (`config`/`audit` modules) |
| Enforcement | Universal `before_action` + hand-maintained `PermissionRegistry` | Explicit `authorize!` per action + fail-closed `after_action` |
| Superuser | `admin` value of the role enum | `employees.is_administrator` boolean |
| Catalog | Hand-written registry hash | Regex scan of controllers/views |

Maintaining two systems is the problem. The gem replaces both.

## Decisions (agreed 2026-08-01)

1. **Resolution model: Mascomida's runtime chain**, generalized so the scope
   is optional. Gaviota migrates off its materialized-rows model.
2. **Enforcement: explicit per-action** with `module.action` string keys.
   Gaviota migrates off the registry model.
3. **Scope: core only, no admin UI.** Each app keeps its own permission-admin
   UI; the gem exposes the resolution presenter those UIs consume.
4. **Distribution: new private GitHub repo** (`almoramx/easy_access_control`),
   consumed via `gem "easy_access_control", git: ..., tag: "vX.Y.Z"`.
5. **Base: wrapper around Pundit**, not CanCanCan/Rolify and not fully
   custom. Rationale: Pundit's `verify_authorized` replaces Mascomida's
   hand-rolled fail-closed enforcer verbatim; Pundit `Scope` gives the
   field/record-visibility cases (Gaviota price lists, Mascomida price
   viewing) a real home instead of pseudo-action keys and stray `admin?`
   branches. Everything Pundit lacks — the toggleable DB permission catalog,
   per-store role assignments, grant/deny overrides — is the gem's own layer.

Gem name: `easy_access_control`, module `EasyAccessControl`.

## Architecture

Rails engine depending on `pundit`. Four layers:

```
app policies / app admin UI
        │ consume
┌───────┴──────────────────────────────────┐
│ Pundit bridge   EasyAccessControl::Policy │  method → key convention
├───────────────────────────────────────────┤
│ Resolution      can?(key, scope:)         │  admin → global → override → role
├───────────────────────────────────────────┤
│ Data            permissions, roles,       │  migrations shipped by the engine
│                 role_permissions,         │
│                 role_assignments,         │
│                 permission_overrides,     │
│                 global_permissions        │
└───────────────────────────────────────────┘
```

### Data layer

Mascomida's tables, generalized. All shipped as engine migrations.

| Table | Columns (essence) | Notes |
|---|---|---|
| `permissions` | `key` (unique, `module.action`), `module_name` | catalog |
| `roles` | `name` | closed set enforced by app config, not DB |
| `role_permissions` | `role_id`, `permission_id` | role template, runtime-consulted |
| `role_assignments` | `subject_id`, `role_id`, `scope_id` (nullable) | unique on `[subject_id, scope_id]` — one role per subject per scope |
| `permission_overrides` | `subject_id`, `permission_id`, `scope_id` (nullable), `effect` enum `grant/deny` | unique on `[subject_id, permission_id, scope_id]` |
| `global_permissions` | `subject_id`, `permission_id` | scope-independent grants for global modules |

Configuration (initializer per app):

```ruby
EasyAccessControl.configure do |c|
  c.subject_class = "Employee"          # who holds permissions
  c.scope_class   = "Warehouse"         # nil in Gaviota → everything global
  c.admin_method  = :is_administrator?  # superuser bypass predicate
  c.global_modules = %w[config audit]   # modules resolved without a scope
  c.role_names    = %w[admin veterinarian groomer receptionist warehouse custom]
end
```

The subject gains the API via a mixin: `include EasyAccessControl::Subject`
provides associations plus `can?`, `role_at(scope)`, `toggle_override!`.

### Resolution

`Employee#can?(key, scope: nil)`, unchanged from Mascomida:

1. `admin_method` true → `true` (unconditional bypass, no rows consulted)
2. key belongs to a global module → check `global_permissions`
3. resolve target scope (argument, else the app's current-scope provider);
   with `scope_class` unset, resolution proceeds scope-less (single global
   "scope"); with `scope_class` set and no scope resolvable → `false`
4. `permission_overrides` row for (subject, permission, scope) → its effect
5. role default: `role_at(scope)` template includes the key
6. `false`

The current scope comes from a configurable provider,
`c.current_scope = -> { Current.warehouse }`, so the gem never touches
`Current` directly.

### Pundit bridge

`EasyAccessControl::Policy`, a Pundit-convention base class, with one rule:
**policy method name → permission key**. `OrdersPolicy#refund_approve?`
resolves `can?("orders.refund_approve")`. The module segment derives from the
policy class name; override with `permission_module "sap_invoices"` when the
class name doesn't match the desired key.

- Policy methods need no body: `permits :list, :create, :refund_approve`
  defines the query methods. A hand-written method wins when domain logic
  must compose (e.g. status checks around the permission).
- Per-store context uses Pundit's standard pattern: `pundit_user` returns
  `EasyAccessControl::Context.new(subject, scope)`; the base policy unwraps it.
- Headless policies (`authorize :orders, :list?`) supported for module-level
  actions with no record.
- `Scope` base class provided; concrete scopes ("seller sees own clients")
  stay in the apps — they are domain rules.

### Enforcement

- Pundit `authorize` / `policy_scope` in controllers, `verify_authorized` as
  the fail-closed check (replaces Mascomida's `enforce_authorization_invoked!`
  and Gaviota's registry `before_action`).
- Transitional shim: `authorize!("orders.refund_approve")` — same resolution,
  string key, marks the action as authorized for `verify_authorized`. Lets
  Mascomida's 199 call sites migrate incrementally.
- Denials raise `Pundit::NotAuthorizedError`; apps keep their own `rescue_from`
  (both currently redirect with a Spanish alert).

### Catalog sync and toggles

- `rake easy_access_control:sync` derives the catalog from policy classes
  (every `permits`/query method is a permission) plus `authorize!` string-key
  call sites during the transition. Additive and idempotent; `:check` variant
  exits 1 on drift (CI gate); `:prune` removes orphans. Human descriptions
  stay in each app's `config/permissions.yml`.
- `toggle_override!(permission:, scope:)` flips relative to the role default
  (the caller never chooses grant vs deny), preserving Mascomida's semantics.
- `EasyAccessControl::ResolvedAccess` presenter: for a subject × scope,
  yields per-permission state `(permission, on, source)` with source in
  `role/grant/deny/global/admin` — the API both admin UIs render from.

## What stays in each app

- Admin UI (controllers, views, Turbo streams) — consumes `ResolvedAccess`
  and `toggle_override!`.
- Concrete Pundit `Scope` classes and record-visibility rules.
- Role templates / seeds (`role_permissions` contents), permission
  descriptions YAML, Spanish module labels.
- Route-coverage tests (the gem ships a shared assertion helper that walks
  routes and fails on actions lacking authorization, with a per-app exemption
  list).

## Migration paths

**Mascomida** (near-zero DB churn):
1. Tables already match structurally; one migration renames `employee_id` →
   `subject_id` and `warehouse_id` → `scope_id` on the three join tables.
   Rename over per-app column configuration: one migration beats permanent
   config surface in the gem.
2. Adopt gem, delete `app/controllers/concerns/authorization.rb` and
   `app/services/permissions/sync.rb`.
3. Call sites keep working through the `authorize!` shim; convert to policies
   module by module (price-visibility keys first — they gain `Scope` homes).

**Gaviota** (model change, agreed):
1. Add gem tables + `employees.is_administrator` (backfill from `role: admin`).
2. Re-key `controller#action` → `module.action`; write policies for its ~25
   controllers, replacing `PermissionRegistry` and `role_authorization.rb`.
3. Migrate materialized `employee_permissions` rows into
   `permission_overrides` (grant) where they differ from the role template;
   drop `employee_permissions`.
4. Price-list pseudo-permissions (`products#list1_price` …) become
   `ProductsPolicy` methods and real catalog keys.

## Testing

- Gem: full unit coverage of the resolution chain (bypass, global tier,
  override precedence, role default, scope-less mode), the policy
  method→key convention, the sync task, and the toggle semantics. Dummy Rails
  app for the engine, RSpec.
- Shipped helpers: route-coverage assertion; shared examples asserting a role
  at scope A is denied at scope B.
- Apps keep their integration suites; they should pass unchanged through the
  shim phase.

## Out of scope (deliberate)

- Admin UI in the gem.
- Multi-role per subject per scope (both apps enforce exactly one).
- Role inheritance/hierarchies.
- Dynamic role creation (closed sets remain; Mascomida's `custom` role is
  just another configured name).
- Publishing to a gem server.
