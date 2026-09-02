class WidgetsController < ActionController::Base
  include EasyAccessControl::Controller

  after_action :verify_authorized

  rescue_from Pundit::NotAuthorizedError do
    head :forbidden
  end

  cattr_accessor :test_subject, :test_scope

  def index
    authorize!("widgets.list")
    head :ok
  end

  def show
    authorize :gadgets, :list?
    head :ok
  end

  def bare
    head :ok
  end

  def panel
    authorize!("widgets.list")
    render inline: <<~ERB
      <%= eac_debug_toolbar %>
      <%= permitted("widgets.edit") do %><button>Edit</button><% end %>
      <%= permitted("widgets.delete") do %><button>Delete</button><% end %>
    ERB
  end

  private

  def pundit_user
    EasyAccessControl::Context.new(subject: self.class.test_subject, scope: self.class.test_scope)
  end
end
