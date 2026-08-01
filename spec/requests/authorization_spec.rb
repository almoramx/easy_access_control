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
