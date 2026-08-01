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
    permission
    override = employee.toggle_override!(permission: "orders.list", scope: store)
    expect(override.permission).to eq(permission)
  end

  it "raises on an unknown key" do
    expect { employee.toggle_override!(permission: "nope.nope", scope: store) }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it "raises when toggling a global permission" do
    global_permission = EasyAccessControl::Permission.create!(key: "config.edit")
    expect { employee.toggle_override!(permission: global_permission, scope: store) }
      .to raise_error(ArgumentError)
  end

  it "raises when scope is nil and EasyAccessControl.scoped? is true" do
    expect { employee.toggle_override!(permission:, scope: nil) }
      .to raise_error(ArgumentError)
  end
end
