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
