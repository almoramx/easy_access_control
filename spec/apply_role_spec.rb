require "rails_helper"

RSpec.describe "Subject#apply_role!" do
  let(:employee) { Employee.create!(name: "Ana") }
  let(:store) { Warehouse.create!(name: "A") }
  let(:other_store) { Warehouse.create!(name: "B") }
  let(:seller) { EasyAccessControl::Role.create!(name: "seller") }
  let(:list) { EasyAccessControl::Permission.create!(key: "orders.list") }
  let(:create_perm) { EasyAccessControl::Permission.create!(key: "orders.create") }
  let(:config_edit) { EasyAccessControl::Permission.create!(key: "config.edit") }

  it "stamps the role's scoped permissions as grant overrides at the scope" do
    EasyAccessControl::RolePermission.create!(role: seller, permission: list)
    employee.apply_role!(seller, scope: store)

    expect(employee.can?("orders.list", scope: store)).to be true
    expect(employee.permission_overrides.sole).to have_attributes(
      permission_id: list.id, scope_id: store.id, effect: "grant"
    )
  end

  it "replaces whatever the subject had at that scope" do
    employee.permission_overrides.create!(permission: create_perm, scope_id: store.id, effect: :grant)
    EasyAccessControl::RolePermission.create!(role: seller, permission: list)

    employee.apply_role!(seller, scope: store)

    expect(employee.can?("orders.create", scope: store)).to be false
    expect(employee.can?("orders.list", scope: store)).to be true
  end

  it "removes a live role assignment at that scope so the stamp is absolute" do
    admin = EasyAccessControl::Role.create!(name: "admin")
    EasyAccessControl::RolePermission.create!(role: admin, permission: create_perm)
    EasyAccessControl::RoleAssignment.create!(subject_id: employee.id, role: admin, scope_id: store.id)

    employee.apply_role!(seller, scope: store)

    expect(employee.role_at(store)).to be_nil
    expect(employee.can?("orders.create", scope: store)).to be false
  end

  it "replaces global permissions with the role's global ones" do
    other_global = EasyAccessControl::Permission.create!(key: "config.reset")
    employee.global_permissions.create!(permission: other_global)
    EasyAccessControl::RolePermission.create!(role: seller, permission: config_edit)

    employee.apply_role!(seller, scope: store)

    expect(employee.can?("config.edit")).to be true
    expect(employee.can?("config.reset")).to be false
  end

  it "leaves other scopes untouched" do
    employee.permission_overrides.create!(permission: create_perm, scope_id: other_store.id, effect: :grant)
    EasyAccessControl::RoleAssignment.create!(subject_id: employee.id, role: seller, scope_id: other_store.id)

    employee.apply_role!(seller, scope: store)

    expect(employee.can?("orders.create", scope: other_store)).to be true
    expect(employee.role_at(other_store)).to eq(seller)
  end

  it "raises when scope is nil and EasyAccessControl.scoped? is true" do
    expect { employee.apply_role!(seller) }.to raise_error(ArgumentError)
  end

  it "stamps without scope in unscoped mode" do
    EasyAccessControl.configure { |c| c.scope_class = nil }
    EasyAccessControl::RolePermission.create!(role: seller, permission: list)

    employee.apply_role!(seller)

    expect(employee.can?("orders.list")).to be true
    expect(employee.permission_overrides.sole.scope_id).to be_nil
  end
end
