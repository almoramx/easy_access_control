require "easy_access_control"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.before { EasyAccessControl.reset_config! }
end
