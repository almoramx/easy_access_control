ENV["RAILS_ENV"] ||= "test"
require "combustion"
require "easy_access_control/engine"

Combustion.initialize! :active_record, :action_controller

require "rspec/rails"
require "spec_helper"

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.before(file_path: %r{\A\./spec/[^/]+/}) do
    EasyAccessControl.configure do |c|
      c.subject_class = "Employee"
      c.scope_class = "Warehouse"
      c.global_modules = %w[config]
      c.role_names = %w[admin seller]
    end
  end
end
