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
