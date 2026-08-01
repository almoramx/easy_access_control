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
