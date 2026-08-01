module EasyAccessControl
  class Engine < ::Rails::Engine
    rake_tasks do
      load File.expand_path("../tasks/easy_access_control.rake", __dir__)
    end
  end
end
