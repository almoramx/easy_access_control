require "rails_helper"

RSpec.describe "permitted view helper", type: :request do
  let(:employee) { Employee.create!(name: "Ana") }
  let(:store) { Warehouse.create!(name: "A") }
  let(:seller) { EasyAccessControl::Role.create!(name: "seller") }

  before do
    WidgetsController.test_subject = employee
    WidgetsController.test_scope = store
    EasyAccessControl::RoleAssignment.create!(subject_id: employee.id, role: seller, scope_id: store.id)
    %w[widgets.list widgets.edit].each do |key|
      permission = EasyAccessControl::Permission.create!(key:)
      EasyAccessControl::RolePermission.create!(role: seller, permission:)
    end
    EasyAccessControl::Permission.create!(key: "widgets.delete")
  end

  it "renders only the permitted blocks with debug off" do
    get "/widgets/panel"
    expect(response.body).to include("<button>Edit</button>")
    expect(response.body).not_to include("Delete")
    expect(response.body).not_to include("eac-debug")
    expect(response.body).to include('<th class="right">Cost</th>')
    expect(response.body).not_to include("<th></th>")
  end

  it "marks `as:` cells with the key as attributes instead of a wrapper" do
    EasyAccessControl.config.debug_ui = ->(_) { true }
    get "/widgets/panel"
    expect(response.body).to include('<th class="right eac-debug-cell" title="widgets.edit · A" data-eac-key="widgets.edit">Cost</th>')
    expect(response.body).not_to include("<th></th>")
  end

  it "boxes every gate with its key and lists authorize! keys when debug is on" do
    EasyAccessControl.config.debug_ui = ->(controller) { controller.params[:debug] == "1" }
    get "/widgets/panel", params: { debug: 1 }
    expect(response.body).to include('data-eac-key="widgets.edit" data-eac-allowed="true"')
    expect(response.body).to include("<button>Edit</button>")
    expect(response.body).to include('data-eac-key="widgets.delete" data-eac-allowed="false"')
    expect(response.body).to include("widgets.delete · A ✗")
    expect(response.body).not_to include("<button>Delete</button>")
    expect(response.body).to include("<b>authorize!</b> widgets.list · A")
    expect(response.body).to include("<style>")
  end

  it "memoizes can? per key and scope within a request" do
    expect(employee).to receive(:can?).with("widgets.edit", scope: store).once.and_return(true)
    controller = WidgetsController.new
    controller.can?("widgets.edit")
    controller.can?("widgets.edit")
  end
end
