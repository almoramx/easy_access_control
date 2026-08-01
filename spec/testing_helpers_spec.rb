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
