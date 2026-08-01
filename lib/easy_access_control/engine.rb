module EasyAccessControl
  class Engine < ::Rails::Engine
    engine_name "easy_access_control"

    rake_tasks do
      load File.expand_path("../tasks/easy_access_control.rake", __dir__)
    end
  end
end
