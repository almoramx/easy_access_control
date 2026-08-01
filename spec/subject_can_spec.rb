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
