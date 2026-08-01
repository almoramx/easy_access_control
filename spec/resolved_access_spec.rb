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
