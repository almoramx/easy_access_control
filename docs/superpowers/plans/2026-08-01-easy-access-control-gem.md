# easy_access_control Gem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `easy_access_control` Rails engine: a Pundit wrapper adding a toggleable DB permission catalog, per-scope role assignments, and grant/deny overrides, per the spec at `docs/superpowers/specs/2026-08-01-easy-access-control-design.md`.

**Architecture:** Rails engine depending on Pundit. Four layers: unprefixed DB tables (permissions, roles, role_permissions, role_assignments, permission_overrides, global_permissions), a `Subject` mixin providing the `can?` resolution chain (admin → global → override → role default), a `Policy` base class bridging policy-method names to permission keys, and services (catalog sync, resolved-access presenter, route-coverage test helper).

**Tech Stack:** Ruby >= 3.4, Rails >= 8.0, Pundit ~> 2.3, RSpec + Combustion + SQLite for tests.

## Global Constraints

- `required_ruby_version = ">= 3.4"`; gem deps: `rails >= 8.0`, `pundit ~> 2.3`.
- Table names are UNPREFIXED (`permissions`, not `easy_access_control_permissions`) — Mascomida already owns these tables. Every model sets `self.table_name` explicitly.
- NO comments in code, ever (user rule). Known ceilings are documented in README, not inline.
- Models are namespaced `EasyAccessControl::*`. No `belongs_to :subject` / `belongs_to :scope` associations on join models — the gem only reads `scope&.id`; apps add associations if their UI needs them.
- Uniqueness on nullable `scope_id` columns is NOT enforceable by SQLite unique indexes when scope_id IS NULL (NULLs compare distinct) — model validations are the real guard; indexes are best-effort.
- Working directory: `/home/ax/workspace/EasyAccessControl`. Commit after every task with conventional-commit messages.
- Run tests with `bundle exec rspec <path> --format progress`.

---

### Task 1: Gem skeleton + Configuration

**Files:**
- Create: `easy_access_control.gemspec`, `Gemfile`, `.gitignore`, `lib/easy_access_control.rb`, `lib/easy_access_control/version.rb`, `lib/easy_access_control/configuration.rb`, `lib/easy_access_control/engine.rb`
- Test: `spec/configuration_spec.rb`, `spec/spec_helper.rb`

**Interfaces:**
- Produces: `EasyAccessControl.config` (memoized `Configuration`), `EasyAccessControl.configure { |c| }`, `EasyAccessControl.reset_config!`, `EasyAccessControl.global_key?(key) -> bool`, `EasyAccessControl.scoped? -> bool`, `EasyAccessControl.current_scope -> Object|nil`. `Configuration` attrs: `subject_class` (String), `scope_class` (String|nil), `admin_method` (Symbol, default `:is_administrator?`), `global_modules` ([String], default []), `role_names` ([String], default []), `current_scope` (Proc, default `-> { nil }`).

- [ ] **Step 1: Write scaffolding files**

`easy_access_control.gemspec`:
```ruby
require_relative "lib/easy_access_control/version"

Gem::Specification.new do |spec|
  spec.name = "easy_access_control"
  spec.version = EasyAccessControl::VERSION
  spec.authors = ["Almora"]
  spec.summary = "Toggleable, optionally scope-aware RBAC on top of Pundit"
  spec.homepage = "https://github.com/almoramx/easy_access_control"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.files = Dir["lib/**/*", "app/**/*", "db/**/*", "README.md"]
  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "pundit", "~> 2.3"
end
```

`Gemfile`:
```ruby
source "https://rubygems.org"

gemspec

gem "combustion", "~> 1.5"
gem "rspec-rails", "~> 8.0"
gem "sqlite3", ">= 2.1"
```

`.gitignore`:
```
Gemfile.lock
spec/internal/db/*.sqlite
spec/internal/log/*.log
spec/internal/tmp/
```

`lib/easy_access_control/version.rb`:
```ruby
module EasyAccessControl
  VERSION = "0.1.0"
end
```

`lib/easy_access_control/engine.rb`:
```ruby
module EasyAccessControl
  class Engine < ::Rails::Engine
    rake_tasks do
      load File.expand_path("../tasks/easy_access_control.rake", __dir__)
    end
  end
end
```

`lib/easy_access_control/configuration.rb`:
```ruby
module EasyAccessControl
  class Configuration
    attr_accessor :subject_class, :scope_class, :admin_method, :global_modules,
                  :role_names, :current_scope

    def initialize
      @subject_class = nil
      @scope_class = nil
      @admin_method = :is_administrator?
      @global_modules = []
      @role_names = []
      @current_scope = -> { nil }
    end
  end
end
```

`lib/easy_access_control.rb`:
```ruby
require "pundit"
require "easy_access_control/version"
require "easy_access_control/configuration"

module EasyAccessControl
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_config!
      @config = Configuration.new
    end

    def global_key?(key)
      config.global_modules.include?(key.to_s.split(".").first)
    end

    def scoped?
      !config.scope_class.nil?
    end

    def current_scope
      config.current_scope.call
    end
  end
end

require "easy_access_control/engine" if defined?(Rails::Engine)
```

Create an empty placeholder so the engine's rake_tasks load succeeds — `lib/tasks/easy_access_control.rake`:
```ruby
```
(empty file; Task 8 fills it.)

- [ ] **Step 2: Write the failing spec**

`spec/spec_helper.rb`:
```ruby
require "easy_access_control"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.before { EasyAccessControl.reset_config! }
end
```

`spec/configuration_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe EasyAccessControl do
  it "defaults admin_method, global_modules, role_names, current_scope" do
    config = described_class.config
    expect(config.admin_method).to eq(:is_administrator?)
    expect(config.global_modules).to eq([])
    expect(config.role_names).to eq([])
    expect(config.current_scope.call).to be_nil
  end

  it "yields the config and memoizes it" do
    described_class.configure { |c| c.subject_class = "Employee" }
    expect(described_class.config.subject_class).to eq("Employee")
  end

  it "resets" do
    described_class.configure { |c| c.subject_class = "Employee" }
    described_class.reset_config!
    expect(described_class.config.subject_class).to be_nil
  end

  it "classifies global keys by module prefix" do
    described_class.configure { |c| c.global_modules = %w[config audit] }
    expect(described_class.global_key?("config.edit")).to be true
    expect(described_class.global_key?("orders.list")).to be false
  end

  it "reports scoped? from scope_class presence" do
    expect(described_class.scoped?).to be false
    described_class.configure { |c| c.scope_class = "Warehouse" }
    expect(described_class.scoped?).to be true
  end
end
```

- [ ] **Step 3: Run `bundle install`, then `bundle exec rspec spec/configuration_spec.rb`** — all 5 examples must PASS (implementation was written in Step 1; if any fail, fix `lib/` until green).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: gem skeleton with configuration"
```

---

### Task 2: Combustion harness + data models

**Files:**
- Create: `spec/rails_helper.rb`, `spec/internal/db/schema.rb`, `spec/internal/config/routes.rb`, `spec/internal/app/models/employee.rb`, `spec/internal/app/models/warehouse.rb`, `spec/internal/config/initializers/easy_access_control.rb`, `app/models/easy_access_control/permission.rb`, `app/models/easy_access_control/role.rb`, `app/models/easy_access_control/role_permission.rb`, `app/models/easy_access_control/role_assignment.rb`, `app/models/easy_access_control/permission_override.rb`, `app/models/easy_access_control/global_permission.rb`
- Test: `spec/models/permission_spec.rb`, `spec/models/role_spec.rb`, `spec/models/join_models_spec.rb`

**Interfaces:**
- Consumes: Task 1 configuration API.
- Produces: `EasyAccessControl::Permission` (`key`, `module_name`, `#global?`, scopes `.global`/`.non_global`, has_many role_permissions/permission_overrides/global_permissions all `dependent: :destroy`); `EasyAccessControl::Role` (`name`, `has_many :permissions, through: :role_permissions`); `EasyAccessControl::RolePermission`; `EasyAccessControl::RoleAssignment` (`subject_id`, `role_id`, `scope_id` nullable); `EasyAccessControl::PermissionOverride` (`subject_id`, `permission_id`, `scope_id` nullable, `enum :effect, { grant: 0, deny: 1 }`); `EasyAccessControl::GlobalPermission` (`subject_id`, `permission_id`). Test app: `Employee` (`name`, `is_administrator` boolean) including `EasyAccessControl::Subject` (mixin arrives Task 3 — for now plain model), `Warehouse` (`name`).

- [ ] **Step 1: Write the harness**

`spec/rails_helper.rb`:
```ruby
ENV["RAILS_ENV"] ||= "test"
require "combustion"

Combustion.initialize! :active_record, :action_controller

require "rspec/rails"
require "spec_helper"

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.before do
    EasyAccessControl.configure do |c|
      c.subject_class = "Employee"
      c.scope_class = "Warehouse"
      c.global_modules = %w[config]
      c.role_names = %w[admin seller]
    end
  end
end
```

Hook order note: `spec_helper`'s `before` (reset) is registered when `require "spec_helper"` runs, BEFORE this file's `before` (configure) — RSpec runs before-hooks in registration order, so every example starts reset-then-configured. Examples that need scope-less mode mutate `EasyAccessControl.config` inline.

```ruby
```

`spec/internal/config/initializers/easy_access_control.rb`:
```ruby
EasyAccessControl.configure do |c|
  c.subject_class = "Employee"
  c.scope_class = "Warehouse"
  c.global_modules = %w[config]
  c.role_names = %w[admin seller]
end
```

`spec/internal/config/routes.rb`:
```ruby
Rails.application.routes.draw do
end
```

`spec/internal/db/schema.rb`:
```ruby
ActiveRecord::Schema.define do
  create_table :employees, force: true do |t|
    t.string :name
    t.boolean :is_administrator, null: false, default: false
  end

  create_table :warehouses, force: true do |t|
    t.string :name
  end

  create_table :permissions, force: true do |t|
    t.string :key, null: false
    t.string :module_name, null: false
    t.timestamps
  end
  add_index :permissions, :key, unique: true

  create_table :roles, force: true do |t|
    t.string :name, null: false
    t.timestamps
  end
  add_index :roles, :name, unique: true

  create_table :role_permissions, force: true do |t|
    t.references :role, null: false
    t.references :permission, null: false
  end
  add_index :role_permissions, [:role_id, :permission_id], unique: true

  create_table :role_assignments, force: true do |t|
    t.bigint :subject_id, null: false
    t.references :role, null: false
    t.bigint :scope_id
    t.timestamps
  end
  add_index :role_assignments, [:subject_id, :scope_id], unique: true

  create_table :permission_overrides, force: true do |t|
    t.bigint :subject_id, null: false
    t.references :permission, null: false
    t.bigint :scope_id
    t.integer :effect, null: false
    t.timestamps
  end
  add_index :permission_overrides, [:subject_id, :permission_id, :scope_id], unique: true

  create_table :global_permissions, force: true do |t|
    t.bigint :subject_id, null: false
    t.references :permission, null: false
  end
  add_index :global_permissions, [:subject_id, :permission_id], unique: true
end
```

`spec/internal/app/models/employee.rb`:
```ruby
class Employee < ActiveRecord::Base
end
```

`spec/internal/app/models/warehouse.rb`:
```ruby
class Warehouse < ActiveRecord::Base
end
```

- [ ] **Step 2: Write the failing model specs**

`spec/models/permission_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe EasyAccessControl::Permission do
  it "requires a valid module.action key and backfills module_name" do
    permission = described_class.create!(key: "orders.refund_approve")
    expect(permission.module_name).to eq("orders")
    expect(described_class.new(key: "orders").valid?).to be false
    expect(described_class.new(key: "Orders.List").valid?).to be false
    expect(described_class.new(key: "products.list1_price").valid?).to be true
  end

  it "rejects duplicate keys" do
    described_class.create!(key: "orders.list")
    expect { described_class.create!(key: "orders.list") }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "splits global and non_global tiers by configured modules" do
    global = described_class.create!(key: "config.edit")
    scoped = described_class.create!(key: "orders.list")
    expect(described_class.global).to contain_exactly(global)
    expect(described_class.non_global).to contain_exactly(scoped)
    expect(global.global?).to be true
    expect(scoped.global?).to be false
  end
end
```

`spec/models/role_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe EasyAccessControl::Role do
  it "enforces configured role names when the list is present" do
    expect(described_class.create!(name: "seller")).to be_persisted
    expect(described_class.new(name: "intruder").valid?).to be false
  end

  it "allows any name when role_names is empty" do
    EasyAccessControl.config.role_names = []
    expect(described_class.new(name: "whatever").valid?).to be true
  end

  it "exposes permissions through role_permissions" do
    role = described_class.create!(name: "seller")
    permission = EasyAccessControl::Permission.create!(key: "orders.list")
    EasyAccessControl::RolePermission.create!(role:, permission:)
    expect(role.permissions).to contain_exactly(permission)
  end
end
```

`spec/models/join_models_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "join models" do
  let(:employee) { Employee.create!(name: "Ana") }
  let(:role) { EasyAccessControl::Role.create!(name: "seller") }
  let(:permission) { EasyAccessControl::Permission.create!(key: "orders.list") }

  it "enforces one role per subject per scope including the null scope" do
    EasyAccessControl::RoleAssignment.create!(subject_id: employee.id, role:, scope_id: nil)
    duplicate = EasyAccessControl::RoleAssignment.new(subject_id: employee.id, role:, scope_id: nil)
    expect(duplicate.valid?).to be false
  end

  it "enforces one override per subject per permission per scope including the null scope" do
    EasyAccessControl::PermissionOverride.create!(
      subject_id: employee.id, permission:, scope_id: nil, effect: :grant
    )
    duplicate = EasyAccessControl::PermissionOverride.new(
      subject_id: employee.id, permission:, scope_id: nil, effect: :deny
    )
    expect(duplicate.valid?).to be false
  end

  it "enforces one global grant per subject per permission" do
    EasyAccessControl::GlobalPermission.create!(subject_id: employee.id, permission:)
    duplicate = EasyAccessControl::GlobalPermission.new(subject_id: employee.id, permission:)
    expect(duplicate.valid?).to be false
  end

  it "destroys dependents when a permission is destroyed" do
    EasyAccessControl::RolePermission.create!(role:, permission:)
    EasyAccessControl::GlobalPermission.create!(subject_id: employee.id, permission:)
    permission.destroy!
    expect(EasyAccessControl::RolePermission.count).to eq(0)
    expect(EasyAccessControl::GlobalPermission.count).to eq(0)
  end
end
```

- [ ] **Step 3: Run `bundle exec rspec spec/models` — expect FAIL** (uninitialized constant `EasyAccessControl::Permission`).

- [ ] **Step 4: Implement the models**

`app/models/easy_access_control/permission.rb`:
```ruby
module EasyAccessControl
  class Permission < ActiveRecord::Base
    self.table_name = "permissions"

    KEY_FORMAT = /\A[a-z0-9_]+\.[a-z0-9_]+\z/

    has_many :role_permissions, class_name: "EasyAccessControl::RolePermission", dependent: :destroy
    has_many :permission_overrides, class_name: "EasyAccessControl::PermissionOverride", dependent: :destroy
    has_many :global_permissions, class_name: "EasyAccessControl::GlobalPermission", dependent: :destroy

    before_validation { self.module_name ||= key.to_s.split(".").first }

    validates :key, presence: true, uniqueness: true, format: { with: KEY_FORMAT }
    validates :module_name, presence: true

    scope :global, -> { where(module_name: EasyAccessControl.config.global_modules) }
    scope :non_global, -> { where.not(module_name: EasyAccessControl.config.global_modules) }

    def global?
      EasyAccessControl.global_key?(key)
    end
  end
end
```

`app/models/easy_access_control/role.rb`:
```ruby
module EasyAccessControl
  class Role < ActiveRecord::Base
    self.table_name = "roles"

    has_many :role_permissions, class_name: "EasyAccessControl::RolePermission", dependent: :destroy
    has_many :permissions, through: :role_permissions

    validates :name, presence: true, uniqueness: true
    validates :name,
              inclusion: { in: ->(_) { EasyAccessControl.config.role_names } },
              if: -> { EasyAccessControl.config.role_names.any? }
  end
end
```

`app/models/easy_access_control/role_permission.rb`:
```ruby
module EasyAccessControl
  class RolePermission < ActiveRecord::Base
    self.table_name = "role_permissions"

    belongs_to :role, class_name: "EasyAccessControl::Role"
    belongs_to :permission, class_name: "EasyAccessControl::Permission"

    validates :permission_id, uniqueness: { scope: :role_id }
  end
end
```

`app/models/easy_access_control/role_assignment.rb`:
```ruby
module EasyAccessControl
  class RoleAssignment < ActiveRecord::Base
    self.table_name = "role_assignments"

    belongs_to :role, class_name: "EasyAccessControl::Role"

    validates :subject_id, presence: true
    validates :subject_id, uniqueness: { scope: :scope_id }
  end
end
```

`app/models/easy_access_control/permission_override.rb`:
```ruby
module EasyAccessControl
  class PermissionOverride < ActiveRecord::Base
    self.table_name = "permission_overrides"

    belongs_to :permission, class_name: "EasyAccessControl::Permission"

    enum :effect, { grant: 0, deny: 1 }

    validates :subject_id, presence: true
    validates :permission_id, uniqueness: { scope: [:subject_id, :scope_id] }
  end
end
```

`app/models/easy_access_control/global_permission.rb`:
```ruby
module EasyAccessControl
  class GlobalPermission < ActiveRecord::Base
    self.table_name = "global_permissions"

    belongs_to :permission, class_name: "EasyAccessControl::Permission"

    validates :subject_id, presence: true
    validates :permission_id, uniqueness: { scope: :subject_id }
  end
end
```

- [ ] **Step 5: Run `bundle exec rspec spec/models` — expect all PASS.** Run `bundle exec rspec` — configuration_spec must still pass (it must not require rails_helper).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: data models and combustion test harness"
```

---

### Task 3: Subject mixin — can? resolution chain

**Files:**
- Create: `lib/easy_access_control/subject.rb`
- Modify: `lib/easy_access_control.rb` (add `require "easy_access_control/subject"` after configuration require), `spec/internal/app/models/employee.rb` (include the mixin)
- Test: `spec/subject_can_spec.rb`

**Interfaces:**
- Consumes: Task 2 models; `EasyAccessControl.global_key?/scoped?/current_scope`.
- Produces: `EasyAccessControl::Subject` mixin — `#can?(key, scope: nil) -> bool`, `#role_at(scope) -> Role|nil`, `#access_admin? -> bool`, has_many `role_assignments`/`permission_overrides`/`global_permissions` (foreign_key `:subject_id`, `dependent: :destroy`).

- [ ] **Step 1: Update Employee**

`spec/internal/app/models/employee.rb`:
```ruby
class Employee < ActiveRecord::Base
  include EasyAccessControl::Subject
end
```

- [ ] **Step 2: Write the failing spec**

`spec/subject_can_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe EasyAccessControl::Subject do
  let(:employee) { Employee.create!(name: "Ana") }
  let(:admin) { Employee.create!(name: "Root", is_administrator: true) }
  let(:store_a) { Warehouse.create!(name: "A") }
  let(:store_b) { Warehouse.create!(name: "B") }
  let(:seller) { EasyAccessControl::Role.create!(name: "seller") }
  let(:orders_list) { EasyAccessControl::Permission.create!(key: "orders.list") }
  let(:config_edit) { EasyAccessControl::Permission.create!(key: "config.edit") }

  def assign(subject, role, scope)
    EasyAccessControl::RoleAssignment.create!(subject_id: subject.id, role:, scope_id: scope&.id)
  end

  it "bypasses everything for admins" do
    expect(admin.can?("orders.list", scope: store_a)).to be true
    expect(admin.can?("config.edit")).to be true
  end

  it "resolves global-module keys through global_permissions ignoring scope" do
    expect(employee.can?("config.edit")).to be false
    EasyAccessControl::GlobalPermission.create!(subject_id: employee.id, permission: config_edit)
    expect(employee.can?("config.edit")).to be true
    expect(employee.can?("config.edit", scope: store_a)).to be true
  end

  it "denies scoped keys when scoped mode is on and no scope resolves" do
    expect(employee.can?("orders.list")).to be false
  end

  it "grants via role default at the assigned scope only" do
    EasyAccessControl::RolePermission.create!(role: seller, permission: orders_list)
    assign(employee, seller, store_a)
    expect(employee.can?("orders.list", scope: store_a)).to be true
    expect(employee.can?("orders.list", scope: store_b)).to be false
  end

  it "lets a deny override beat the role default" do
    EasyAccessControl::RolePermission.create!(role: seller, permission: orders_list)
    assign(employee, seller, store_a)
    EasyAccessControl::PermissionOverride.create!(
      subject_id: employee.id, permission: orders_list, scope_id: store_a.id, effect: :deny
    )
    expect(employee.can?("orders.list", scope: store_a)).to be false
  end

  it "lets a grant override beat a missing role default" do
    assign(employee, seller, store_a)
    EasyAccessControl::PermissionOverride.create!(
      subject_id: employee.id, permission: orders_list, scope_id: store_a.id, effect: :grant
    )
    expect(employee.can?("orders.list", scope: store_a)).to be true
  end

  it "falls back to the configured current_scope provider" do
    EasyAccessControl::RolePermission.create!(role: seller, permission: orders_list)
    assign(employee, seller, store_a)
    EasyAccessControl.config.current_scope = -> { store_a }
    expect(employee.can?("orders.list")).to be true
  end

  it "resolves scope-less when scope_class is nil" do
    EasyAccessControl.config.scope_class = nil
    EasyAccessControl::RolePermission.create!(role: seller, permission: orders_list)
    assign(employee, seller, nil)
    expect(employee.can?("orders.list")).to be true
    expect(employee.can?("orders.missing")).to be false
  end

  it "returns the role at a scope via role_at" do
    assign(employee, seller, store_a)
    expect(employee.role_at(store_a)).to eq(seller)
    expect(employee.role_at(store_b)).to be_nil
  end
end
```

- [ ] **Step 3: Run `bundle exec rspec spec/subject_can_spec.rb` — expect FAIL** (uninitialized constant `EasyAccessControl::Subject`).

- [ ] **Step 4: Implement**

`lib/easy_access_control/subject.rb`:
```ruby
module EasyAccessControl
  module Subject
    extend ActiveSupport::Concern

    included do
      has_many :role_assignments, class_name: "EasyAccessControl::RoleAssignment",
                                  foreign_key: :subject_id, dependent: :destroy
      has_many :permission_overrides, class_name: "EasyAccessControl::PermissionOverride",
                                      foreign_key: :subject_id, dependent: :destroy
      has_many :global_permissions, class_name: "EasyAccessControl::GlobalPermission",
                                    foreign_key: :subject_id, dependent: :destroy
    end

    def access_admin?
      !!public_send(EasyAccessControl.config.admin_method)
    end

    def can?(key, scope: nil)
      return true if access_admin?
      key = key.to_s
      return global_grant?(key) if EasyAccessControl.global_key?(key)
      target = scope || EasyAccessControl.current_scope
      return false if EasyAccessControl.scoped? && target.nil?
      override = permission_overrides.joins(:permission)
                                     .find_by(permissions: { key: key }, scope_id: target&.id)
      return override.grant? if override
      role = role_at(target)
      return false unless role
      role.permissions.exists?(key: key)
    end

    def role_at(scope)
      role_assignments.find_by(scope_id: scope&.id)&.role
    end

    private

    def global_grant?(key)
      global_permissions.joins(:permission).exists?(permissions: { key: key })
    end
  end
end
```

In `lib/easy_access_control.rb`, after `require "easy_access_control/configuration"` add:
```ruby
require "easy_access_control/subject"
```
Note: `subject.rb` references `ActiveSupport::Concern`, available because Rails loads before the gem in apps and combustion loads it in tests.

- [ ] **Step 5: Run `bundle exec rspec` — expect all PASS.**

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: subject mixin with can? resolution chain"
```

---

### Task 4: toggle_override!

**Files:**
- Modify: `lib/easy_access_control/subject.rb`
- Test: `spec/toggle_override_spec.rb`

**Interfaces:**
- Consumes: Task 3 `Subject`.
- Produces: `Subject#toggle_override!(permission:, scope: nil) -> PermissionOverride|nil`. Accepts a `Permission` record or a key String. Semantics: existing override → destroy it, return nil (back to role default); no override → create one with the effect opposite to the role default (role grants → `deny`, role silent → `grant`).

- [ ] **Step 1: Write the failing spec**

`spec/toggle_override_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Subject#toggle_override!" do
  let(:employee) { Employee.create!(name: "Ana") }
  let(:store) { Warehouse.create!(name: "A") }
  let(:seller) { EasyAccessControl::Role.create!(name: "seller") }
  let(:permission) { EasyAccessControl::Permission.create!(key: "orders.list") }

  before do
    EasyAccessControl::RoleAssignment.create!(subject_id: employee.id, role: seller, scope_id: store.id)
  end

  it "creates a deny when the role default grants" do
    EasyAccessControl::RolePermission.create!(role: seller, permission:)
    override = employee.toggle_override!(permission:, scope: store)
    expect(override).to be_deny
    expect(employee.can?("orders.list", scope: store)).to be false
  end

  it "creates a grant when the role default is silent" do
    override = employee.toggle_override!(permission:, scope: store)
    expect(override).to be_grant
    expect(employee.can?("orders.list", scope: store)).to be true
  end

  it "destroys an existing override, returning to the role default" do
    employee.toggle_override!(permission:, scope: store)
    result = employee.toggle_override!(permission:, scope: store)
    expect(result).to be_nil
    expect(employee.permission_overrides.count).to eq(0)
  end

  it "accepts a permission key string" do
    override = employee.toggle_override!(permission: "orders.list", scope: store)
    expect(override.permission).to eq(permission)
  end

  it "raises on an unknown key" do
    expect { employee.toggle_override!(permission: "nope.nope", scope: store) }
      .to raise_error(ActiveRecord::RecordNotFound)
  end
end
```

- [ ] **Step 2: Run `bundle exec rspec spec/toggle_override_spec.rb` — expect FAIL** (NoMethodError `toggle_override!`). Note: `permission` is a `let`, so `create!(key:)` must run before use — the `accepts a key string` example references `permission` in the expectation, forcing creation; in `raises on unknown key`, reference `permission` first if the lookup errors for the wrong reason.

- [ ] **Step 3: Implement** — add to `EasyAccessControl::Subject` (public section, after `role_at`):

```ruby
    def toggle_override!(permission:, scope: nil)
      unless permission.is_a?(EasyAccessControl::Permission)
        permission = EasyAccessControl::Permission.find_by!(key: permission.to_s)
      end
      existing = permission_overrides.find_by(permission_id: permission.id, scope_id: scope&.id)
      if existing
        existing.destroy!
        return nil
      end
      default_on = role_at(scope)&.permissions&.exists?(id: permission.id) || false
      permission_overrides.create!(
        permission_id: permission.id, scope_id: scope&.id, effect: default_on ? :deny : :grant
      )
    end
```

- [ ] **Step 4: Run `bundle exec rspec` — expect all PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: toggle_override! flips relative to role default"
```

---

### Task 5: Context + Policy base + Scope

**Files:**
- Create: `lib/easy_access_control/context.rb`, `lib/easy_access_control/policy.rb`, `spec/internal/app/policies/widgets_policy.rb`, `spec/internal/app/policies/renamed_policy.rb`
- Modify: `lib/easy_access_control.rb` (requires after subject: `require "easy_access_control/context"`, `require "easy_access_control/policy"`)
- Test: `spec/policy_spec.rb`

**Interfaces:**
- Consumes: Task 3 `Subject#can?`.
- Produces: `EasyAccessControl::Context = Data.define(:subject, :scope)` with `Context.unwrap(user) -> [subject, scope]`; `EasyAccessControl::Policy` — `.new(user_or_context, record)`, readers `subject`/`context_scope`/`record`, `.permits(*actions)` defining `action?` query methods, `.permission_module(name = nil)` (defaults to class name minus `Policy`, underscored), `#can?(action)`; nested `Policy::Scope` — `.new(user_or_context, relation)`, readers `subject`/`context_scope`/`relation`, `#resolve -> relation`.

- [ ] **Step 1: Write the fixture policies and the failing spec**

Fixture policies live in the internal app (NOT inline in the spec) so Task 8's sync discovery finds them deterministically.

`spec/internal/app/policies/widgets_policy.rb`:
```ruby
class WidgetsPolicy < EasyAccessControl::Policy
  permits :list, :create

  def export?
    can?(:list) && record == :exportable
  end
end
```

`spec/internal/app/policies/renamed_policy.rb`:
```ruby
class RenamedPolicy < EasyAccessControl::Policy
  permission_module "sap_invoices"
  permits :list
end
```

`spec/policy_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe EasyAccessControl::Policy do
  let(:employee) { Employee.create!(name: "Ana") }
  let(:store) { Warehouse.create!(name: "A") }
  let(:seller) { EasyAccessControl::Role.create!(name: "seller") }

  def grant(key)
    permission = EasyAccessControl::Permission.create!(key:)
    EasyAccessControl::RolePermission.create!(role: seller, permission:)
    EasyAccessControl::RoleAssignment.find_or_create_by!(
      subject_id: employee.id, scope_id: store.id
    ) { |a| a.role = seller }
  end

  it "derives the permission module from the class name" do
    expect(WidgetsPolicy.permission_module).to eq("widgets")
    expect(RenamedPolicy.permission_module).to eq("sap_invoices")
  end

  it "maps permits-defined query methods to permission keys" do
    grant("widgets.list")
    context = EasyAccessControl::Context.new(subject: employee, scope: store)
    policy = WidgetsPolicy.new(context, nil)
    expect(policy.list?).to be true
    expect(policy.create?).to be false
  end

  it "supports hand-written methods composing can? with domain logic" do
    grant("widgets.list")
    context = EasyAccessControl::Context.new(subject: employee, scope: store)
    expect(WidgetsPolicy.new(context, :exportable).export?).to be true
    expect(WidgetsPolicy.new(context, :other).export?).to be false
  end

  it "accepts a bare subject instead of a context" do
    EasyAccessControl.config.scope_class = nil
    permission = EasyAccessControl::Permission.create!(key: "widgets.list")
    EasyAccessControl::RolePermission.create!(role: seller, permission:)
    EasyAccessControl::RoleAssignment.create!(subject_id: employee.id, role: seller, scope_id: nil)
    expect(WidgetsPolicy.new(employee, nil).list?).to be true
  end

  it "denies everything for a nil subject" do
    expect(WidgetsPolicy.new(nil, nil).list?).to be false
  end

  it "resolves the relation unchanged in the base Scope" do
    scope = EasyAccessControl::Policy::Scope.new(employee, Employee.all)
    expect(scope.resolve).to eq(Employee.all)
    expect(scope.subject).to eq(employee)
  end
end
```

- [ ] **Step 2: Run `bundle exec rspec spec/policy_spec.rb` — expect FAIL** (uninitialized constant `EasyAccessControl::Policy`).

- [ ] **Step 3: Implement**

`lib/easy_access_control/context.rb`:
```ruby
module EasyAccessControl
  Context = Data.define(:subject, :scope) do
    def self.unwrap(user)
      user.is_a?(self) ? [user.subject, user.scope] : [user, nil]
    end
  end
end
```

`lib/easy_access_control/policy.rb`:
```ruby
module EasyAccessControl
  class Policy
    attr_reader :subject, :context_scope, :record

    def initialize(user, record)
      @subject, @context_scope = Context.unwrap(user)
      @record = record
    end

    class << self
      def permission_module(name = nil)
        @permission_module = name.to_s if name
        @permission_module ||= self.name.demodulize.delete_suffix("Policy").underscore
      end

      def permits(*actions)
        actions.each do |action|
          define_method(:"#{action}?") { can?(action) }
        end
      end
    end

    def can?(action)
      return false unless subject
      key = "#{self.class.permission_module}.#{action.to_s.delete_suffix("?")}"
      subject.can?(key, scope: context_scope)
    end

    class Scope
      attr_reader :subject, :context_scope, :relation

      def initialize(user, relation)
        @subject, @context_scope = Context.unwrap(user)
        @relation = relation
      end

      def resolve
        relation
      end
    end
  end
end
```

- [ ] **Step 4: Run `bundle exec rspec` — expect all PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: pundit policy base with method-to-key convention"
```

---

### Task 6: Controller concern — authorize! shim + Pundit wiring

**Files:**
- Create: `lib/easy_access_control/controller.rb`, `spec/internal/app/controllers/widgets_controller.rb`, `spec/internal/app/policies/gadgets_policy.rb`
- Modify: `lib/easy_access_control.rb` (add `require "easy_access_control/controller"`), `spec/internal/config/routes.rb`
- Test: `spec/requests/authorization_spec.rb`

**Interfaces:**
- Consumes: Task 3 `Subject#can?`, Task 5 `Context`/`Policy`.
- Produces: `EasyAccessControl::Controller` concern — includes `Pundit::Authorization`; adds `#authorize!(key, scope: nil)` which raises `Pundit::NotAuthorizedError` on denial and marks the action authorized (satisfies `verify_authorized`) on success, returning true. Apps get `authorize`, `policy_scope`, `verify_authorized` straight from Pundit.

- [ ] **Step 1: Write the internal-app fixtures**

`spec/internal/app/controllers/widgets_controller.rb`:
```ruby
class WidgetsController < ActionController::Base
  include EasyAccessControl::Controller

  after_action :verify_authorized

  rescue_from Pundit::NotAuthorizedError do
    head :forbidden
  end

  cattr_accessor :test_subject, :test_scope

  def index
    authorize!("widgets.list")
    head :ok
  end

  def show
    authorize :gadgets, :list?
    head :ok
  end

  def bare
    head :ok
  end

  private

  def pundit_user
    EasyAccessControl::Context.new(subject: self.class.test_subject, scope: self.class.test_scope)
  end
end
```

`spec/internal/app/policies/gadgets_policy.rb`:
```ruby
class GadgetsPolicy < EasyAccessControl::Policy
  permits :list
end
```

`spec/internal/config/routes.rb`:
```ruby
Rails.application.routes.draw do
  get "widgets" => "widgets#index"
  get "widgets/bare" => "widgets#bare"
  get "widgets/policy" => "widgets#show"
end
```

- [ ] **Step 2: Write the failing request spec**

`spec/requests/authorization_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "controller authorization", type: :request do
  let(:employee) { Employee.create!(name: "Ana") }
  let(:store) { Warehouse.create!(name: "A") }
  let(:seller) { EasyAccessControl::Role.create!(name: "seller") }

  before do
    WidgetsController.test_subject = employee
    WidgetsController.test_scope = store
    EasyAccessControl::RoleAssignment.create!(subject_id: employee.id, role: seller, scope_id: store.id)
  end

  def grant(key)
    permission = EasyAccessControl::Permission.create!(key:)
    EasyAccessControl::RolePermission.create!(role: seller, permission:)
  end

  it "allows the string-key shim when the permission resolves" do
    grant("widgets.list")
    get "/widgets"
    expect(response).to have_http_status(:ok)
  end

  it "forbids the string-key shim when it does not" do
    get "/widgets"
    expect(response).to have_http_status(:forbidden)
  end

  it "supports headless pundit authorize through the policy bridge" do
    grant("gadgets.list")
    get "/widgets/policy"
    expect(response).to have_http_status(:ok)
  end

  it "fails closed on actions that never authorize" do
    expect { get "/widgets/bare" }.to raise_error(Pundit::AuthorizationNotPerformedError)
  end
end
```

- [ ] **Step 3: Run `bundle exec rspec spec/requests` — expect FAIL** (uninitialized constant `EasyAccessControl::Controller`).

- [ ] **Step 4: Implement**

`lib/easy_access_control/controller.rb`:
```ruby
module EasyAccessControl
  module Controller
    extend ActiveSupport::Concern
    include Pundit::Authorization

    def authorize!(key, scope: nil)
      subject, context_scope = Context.unwrap(pundit_user)
      unless subject&.can?(key, scope: scope || context_scope)
        raise Pundit::NotAuthorizedError, query: key
      end
      skip_authorization
      true
    end
  end
end
```

- [ ] **Step 5: Run `bundle exec rspec` — expect all PASS.** If the fail-closed example fails because the test environment swallows exceptions, set `config.action_dispatch.show_exceptions = :none` in `spec/internal/config/environments/test.rb` (create the file if combustion did not).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: controller concern with authorize! shim over pundit"
```

---

### Task 7: ResolvedAccess presenter

**Files:**
- Create: `lib/easy_access_control/resolved_access.rb`
- Modify: `lib/easy_access_control.rb` (add `require "easy_access_control/resolved_access"`)
- Test: `spec/resolved_access_spec.rb`

**Interfaces:**
- Consumes: Task 2 models, Task 3 `Subject`.
- Produces: `EasyAccessControl::ResolvedAccess` — `.new(subject, scope: nil)`, `#states -> [PermState]` ordered by `module_name, key` covering every catalog permission; `ResolvedAccess::PermState = Data.define(:permission, :on, :source)` with source in `:admin/:global/:grant/:deny/:role`. Preloads overrides, global grants, and role permission ids (no per-permission queries).

- [ ] **Step 1: Write the failing spec**

`spec/resolved_access_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe EasyAccessControl::ResolvedAccess do
  let(:employee) { Employee.create!(name: "Ana") }
  let(:store) { Warehouse.create!(name: "A") }
  let(:seller) { EasyAccessControl::Role.create!(name: "seller") }
  let!(:orders_list) { EasyAccessControl::Permission.create!(key: "orders.list") }
  let!(:orders_create) { EasyAccessControl::Permission.create!(key: "orders.create") }
  let!(:config_edit) { EasyAccessControl::Permission.create!(key: "config.edit") }

  before do
    EasyAccessControl::RoleAssignment.create!(subject_id: employee.id, role: seller, scope_id: store.id)
    EasyAccessControl::RolePermission.create!(role: seller, permission: orders_list)
  end

  def state_for(states, permission)
    states.find { |s| s.permission == permission }
  end

  it "resolves each permission with its source" do
    EasyAccessControl::PermissionOverride.create!(
      subject_id: employee.id, permission: orders_create, scope_id: store.id, effect: :grant
    )
    EasyAccessControl::GlobalPermission.create!(subject_id: employee.id, permission: config_edit)

    states = described_class.new(employee, scope: store).states
    expect(states.size).to eq(3)
    expect(state_for(states, orders_list)).to have_attributes(on: true, source: :role)
    expect(state_for(states, orders_create)).to have_attributes(on: true, source: :grant)
    expect(state_for(states, config_edit)).to have_attributes(on: true, source: :global)
  end

  it "shows deny overrides and role-silent permissions as off" do
    EasyAccessControl::PermissionOverride.create!(
      subject_id: employee.id, permission: orders_list, scope_id: store.id, effect: :deny
    )
    states = described_class.new(employee, scope: store).states
    expect(state_for(states, orders_list)).to have_attributes(on: false, source: :deny)
    expect(state_for(states, orders_create)).to have_attributes(on: false, source: :role)
  end

  it "marks everything on with source admin for administrators" do
    admin = Employee.create!(name: "Root", is_administrator: true)
    states = described_class.new(admin, scope: store).states
    expect(states).to all(have_attributes(on: true, source: :admin))
  end

  it "runs a bounded number of queries" do
    states = nil
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      states = described_class.new(employee, scope: store).states
    end
    expect(states.size).to eq(3)
    expect(queries).to be <= 6
  end
end
```

- [ ] **Step 2: Run `bundle exec rspec spec/resolved_access_spec.rb` — expect FAIL** (uninitialized constant).

- [ ] **Step 3: Implement**

`lib/easy_access_control/resolved_access.rb`:
```ruby
module EasyAccessControl
  class ResolvedAccess
    PermState = Data.define(:permission, :on, :source)

    def initialize(subject, scope: nil)
      @subject = subject
      @scope = scope
    end

    def states
      permissions.map { |permission| state_for(permission) }
    end

    private

    def permissions
      Permission.order(:module_name, :key).to_a
    end

    def state_for(permission)
      return PermState.new(permission:, on: true, source: :admin) if @subject.access_admin?
      if permission.global?
        return PermState.new(permission:, on: global_ids.include?(permission.id), source: :global)
      end
      override = overrides[permission.id]
      if override
        return PermState.new(permission:, on: override.grant?, source: override.effect.to_sym)
      end
      PermState.new(permission:, on: role_permission_ids.include?(permission.id), source: :role)
    end

    def overrides
      @overrides ||= @subject.permission_overrides.where(scope_id: @scope&.id).index_by(&:permission_id)
    end

    def global_ids
      @global_ids ||= @subject.global_permissions.pluck(:permission_id).to_set
    end

    def role_permission_ids
      @role_permission_ids ||= (@subject.role_at(@scope)&.permission_ids).to_a.to_set
    end
  end
end
```

- [ ] **Step 4: Run `bundle exec rspec` — expect all PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: resolved access presenter for admin UIs"
```

---

### Task 8: Catalog sync + rake tasks

**Files:**
- Create: `lib/easy_access_control/sync.rb`
- Modify: `lib/easy_access_control.rb` (add `require "easy_access_control/sync"`), `lib/tasks/easy_access_control.rake` (fill the empty placeholder)
- Test: `spec/sync_spec.rb`

**Interfaces:**
- Consumes: Task 2 `Permission`, Task 5 `Policy` (descendants + `permission_module`).
- Produces: `EasyAccessControl::Sync` class methods — `.expected_keys(root: Rails.root) -> [String] sorted unique`, `.run!(root:)` (upsert missing permissions, never deletes), `.drift(root:) -> { missing: [...], orphaned: [...] }`, `.prune!(root:)` (destroys orphaned permissions). Rake tasks `easy_access_control:sync`, `:check` (exit 1 on drift), `:prune`.

- [ ] **Step 1: Write the failing spec**

`spec/sync_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe EasyAccessControl::Sync do
  it "derives keys from policy classes" do
    keys = described_class.policy_keys
    expect(keys).to include("gadgets.list", "widgets.list", "widgets.create", "widgets.export")
  end

  it "scans authorize! string keys under the given root" do
    keys = described_class.scanned_keys(Rails.root)
    expect(keys).to include("widgets.list")
  end

  it "creates missing permissions on run! without deleting extras" do
    orphan = EasyAccessControl::Permission.create!(key: "legacy.thing")
    described_class.run!
    expect(EasyAccessControl::Permission.find_by(key: "widgets.create")).to be_present
    expect(EasyAccessControl::Permission.exists?(orphan.id)).to be true
  end

  it "reports drift in both directions" do
    EasyAccessControl::Permission.create!(key: "legacy.thing")
    drift = described_class.drift
    expect(drift[:missing]).to include("widgets.create")
    expect(drift[:orphaned]).to eq(["legacy.thing"])
  end

  it "prunes only orphans" do
    described_class.run!
    EasyAccessControl::Permission.create!(key: "legacy.thing")
    described_class.prune!
    expect(EasyAccessControl::Permission.find_by(key: "legacy.thing")).to be_nil
    expect(EasyAccessControl::Permission.find_by(key: "widgets.list")).to be_present
  end

  it "is idempotent" do
    described_class.run!
    expect { described_class.run! }.not_to change(EasyAccessControl::Permission, :count)
  end
end
```

- [ ] **Step 2: Run `bundle exec rspec spec/sync_spec.rb` — expect FAIL** (uninitialized constant `EasyAccessControl::Sync`). Discovery is deterministic because all fixture policies (`WidgetsPolicy`, `RenamedPolicy` from Task 5; `GadgetsPolicy` from Task 6) live in `spec/internal/app/policies/` and `Sync.policy_keys` calls `Rails.application.eager_load!`. `widgets.export` comes from the hand-written `export?` method.

- [ ] **Step 3: Implement**

`lib/easy_access_control/sync.rb`:
```ruby
module EasyAccessControl
  class Sync
    AUTHORIZE_PATTERN = /\bauthorize!\s*\(\s*["']([a-z0-9_.]+)["']/

    class << self
      def expected_keys(root: Rails.root)
        (policy_keys + scanned_keys(root)).uniq.sort
      end

      def run!(root: Rails.root)
        expected_keys(root:).each do |key|
          Permission.find_or_create_by!(key:)
        end
      end

      def drift(root: Rails.root)
        expected = expected_keys(root:)
        existing = Permission.pluck(:key)
        { missing: expected - existing, orphaned: (existing - expected).sort }
      end

      def prune!(root: Rails.root)
        Permission.where(key: drift(root:)[:orphaned]).destroy_all
      end

      def policy_keys
        Rails.application.eager_load!
        Policy.descendants.flat_map do |klass|
          next [] unless klass.name
          mod = klass.permission_module
          klass.public_instance_methods(false).grep(/\?\z/).map do |m|
            "#{mod}.#{m.to_s.delete_suffix("?")}"
          end
        end
      end

      def scanned_keys(root)
        Dir.glob(File.join(root, "app/**/*.{rb,erb}")).flat_map do |file|
          File.read(file).scan(AUTHORIZE_PATTERN).flatten
        end
      end
    end
  end
end
```

`lib/tasks/easy_access_control.rake`:
```ruby
namespace :easy_access_control do
  desc "Sync the permission catalog from policies and authorize! call sites"
  task sync: :environment do
    EasyAccessControl::Sync.run!
    puts "Synced. #{EasyAccessControl::Permission.count} permissions."
  end

  desc "Fail when the catalog drifts from code"
  task check: :environment do
    drift = EasyAccessControl::Sync.drift
    if drift.values.any?(&:any?)
      puts "missing: #{drift[:missing].join(", ")}"
      puts "orphaned: #{drift[:orphaned].join(", ")}"
      exit 1
    end
    puts "Catalog in sync."
  end

  desc "Remove orphaned permissions"
  task prune: :environment do
    EasyAccessControl::Sync.prune!
  end
end
```

- [ ] **Step 4: Run `bundle exec rspec` — expect all PASS** (full suite: sync's eager_load must not break other specs).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: catalog sync derived from policies plus authorize! scan"
```

---

### Task 9: Testing helpers — route coverage + shared example

**Files:**
- Create: `lib/easy_access_control/testing.rb`, `lib/easy_access_control/testing/shared_examples.rb`
- Test: `spec/testing_helpers_spec.rb`

**Interfaces:**
- Consumes: Task 6 controller wiring.
- Produces: `EasyAccessControl::Testing.unverified_routes(exempt: []) -> [String]` — routed `controller#action` pairs whose controller lacks a `verify_authorized` after_action; requiring `easy_access_control/testing/shared_examples` registers RSpec shared example `"scope-isolated permissions"` expecting lets `subject_with_role`, `granted_key`, `assigned_scope`, `other_scope`. Neither file is auto-required by the gem — test-only, apps require them from their spec helpers.

- [ ] **Step 1: Write the failing spec**

`spec/testing_helpers_spec.rb`:
```ruby
require "rails_helper"
require "easy_access_control/testing"
require "easy_access_control/testing/shared_examples"

RSpec.describe EasyAccessControl::Testing do
  it "flags routed actions on controllers without verify_authorized" do
    unverified = described_class.unverified_routes
    expect(unverified).to eq([])
  end

  it "honors the exemption list against a controller lacking the callback" do
    stub_const("NakedController", Class.new(ActionController::Base) { def ping = head(:ok) })
    Rails.application.routes.draw do
      get "widgets" => "widgets#index"
      get "widgets/bare" => "widgets#bare"
      get "widgets/policy" => "widgets#show"
      get "ping" => "naked#ping"
    end
    expect(described_class.unverified_routes).to eq(["naked#ping"])
    expect(described_class.unverified_routes(exempt: ["naked#ping"])).to eq([])
  ensure
    Rails.application.reload_routes!
  end
end

RSpec.describe "scope-isolated permissions shared example" do
  let(:employee) { Employee.create!(name: "Ana") }
  let(:assigned_scope) { Warehouse.create!(name: "A") }
  let(:other_scope) { Warehouse.create!(name: "B") }
  let(:granted_key) { "orders.list" }
  let(:subject_with_role) do
    role = EasyAccessControl::Role.create!(name: "seller")
    permission = EasyAccessControl::Permission.create!(key: granted_key)
    EasyAccessControl::RolePermission.create!(role:, permission:)
    EasyAccessControl::RoleAssignment.create!(
      subject_id: employee.id, role:, scope_id: assigned_scope.id
    )
    employee
  end

  include_examples "scope-isolated permissions"
end
```

- [ ] **Step 2: Run `bundle exec rspec spec/testing_helpers_spec.rb` — expect FAIL** (LoadError for `easy_access_control/testing`).

- [ ] **Step 3: Implement**

`lib/easy_access_control/testing.rb`:
```ruby
module EasyAccessControl
  module Testing
    class << self
      def unverified_routes(exempt: [])
        Rails.application.routes.routes.filter_map do |route|
          controller = route.defaults[:controller]
          action = route.defaults[:action]
          next unless controller && action
          key = "#{controller}##{action}"
          next if exempt.include?(key)
          klass = "#{controller.camelize}Controller".safe_constantize
          next unless klass
          key unless verified?(klass)
        end.uniq.sort
      end

      private

      def verified?(klass)
        klass._process_action_callbacks.any? do |callback|
          callback.kind == :after && callback.filter == :verify_authorized
        end
      end
    end
  end
end
```

`lib/easy_access_control/testing/shared_examples.rb`:
```ruby
RSpec.shared_examples "scope-isolated permissions" do
  it "denies at another scope what the role grants at the assigned scope" do
    expect(subject_with_role.can?(granted_key, scope: assigned_scope)).to be true
    expect(subject_with_role.can?(granted_key, scope: other_scope)).to be false
  end
end
```

- [ ] **Step 4: Run `bundle exec rspec` — expect all PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: route coverage helper and scope-isolation shared example"
```

---

### Task 10: Install migration, README, version tag

**Files:**
- Create: `db/migrate/20260801000001_create_easy_access_control_tables.rb`, `README.md`
- Test: `spec/migration_spec.rb`

**Interfaces:**
- Consumes: everything prior.
- Produces: engine migration installable into apps via `bin/rails easy_access_control:install:migrations`; README documenting install, configuration, every public API from Tasks 1–9, and known ceilings.

- [ ] **Step 1: Write the failing migration spec**

`spec/migration_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "install migration" do
  it "creates every gem table on a bare database" do
    path = EasyAccessControl::Engine.root.join(
      "db/migrate/20260801000001_create_easy_access_control_tables.rb"
    )
    expect(File.exist?(path)).to be true
    require path
    connection = ActiveRecord::Base.connection
    %w[permissions roles role_permissions role_assignments permission_overrides global_permissions].each do |table|
      connection.drop_table(table, if_exists: true)
    end
    CreateEasyAccessControlTables.new.migrate(:up)
    %w[permissions roles role_permissions role_assignments permission_overrides global_permissions].each do |table|
      expect(connection.table_exists?(table)).to be(true), "missing #{table}"
    end
  end
end
```

Note: this spec mutates the schema — combustion rebuilds it from `spec/internal/db/schema.rb` on the next boot, and within this run the recreated tables match the dropped ones, so ordering is safe. Keep the column definitions identical to the schema.

- [ ] **Step 2: Run `bundle exec rspec spec/migration_spec.rb` — expect FAIL** (file does not exist).

- [ ] **Step 3: Implement**

`db/migrate/20260801000001_create_easy_access_control_tables.rb`:
```ruby
class CreateEasyAccessControlTables < ActiveRecord::Migration[8.0]
  def change
    create_table :permissions do |t|
      t.string :key, null: false
      t.string :module_name, null: false
      t.timestamps
    end
    add_index :permissions, :key, unique: true

    create_table :roles do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :roles, :name, unique: true

    create_table :role_permissions do |t|
      t.references :role, null: false
      t.references :permission, null: false
    end
    add_index :role_permissions, [:role_id, :permission_id], unique: true

    create_table :role_assignments do |t|
      t.bigint :subject_id, null: false
      t.references :role, null: false
      t.bigint :scope_id
      t.timestamps
    end
    add_index :role_assignments, [:subject_id, :scope_id], unique: true

    create_table :permission_overrides do |t|
      t.bigint :subject_id, null: false
      t.references :permission, null: false
      t.bigint :scope_id
      t.integer :effect, null: false
      t.timestamps
    end
    add_index :permission_overrides, [:subject_id, :permission_id, :scope_id], unique: true

    create_table :global_permissions do |t|
      t.bigint :subject_id, null: false
      t.references :permission, null: false
    end
    add_index :global_permissions, [:subject_id, :permission_id], unique: true
  end
end
```

`README.md` — must document, with a code example each: installation (Gemfile git source + `easy_access_control:install:migrations`), the initializer (all six config options, what `scope_class = nil` means), `include EasyAccessControl::Subject`, `can?`/`role_at`/`toggle_override!`, `include EasyAccessControl::Controller` + `pundit_user` returning a `Context` + `verify_authorized` + the `authorize!` transitional shim, writing policies (`permits`, `permission_module`, hand-written methods, `Scope`), `ResolvedAccess` for admin UIs, the three rake tasks, the two testing helpers, and a "Known ceilings" section stating: (1) unique indexes do not fire for NULL scope_id — model validations are the guard, so always create/toggle through the models; (2) `Testing.unverified_routes` checks callback presence per controller, not per-action skips; (3) the admin bypass is unconditional and cannot be attenuated; (4) `Sync.policy_keys` treats every `?`-suffixed public policy method as a permission key, including pure-domain methods that never consult `can?`.

- [ ] **Step 4: Run `bundle exec rspec` — full suite must PASS.**

- [ ] **Step 5: Commit and tag**

```bash
git add -A
git commit -m "feat: install migration and README"
git tag v0.1.0
```
