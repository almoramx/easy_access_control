require "pundit"
require "easy_access_control/version"
require "easy_access_control/configuration"
require "easy_access_control/subject"

module EasyAccessControl
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_config!
      @config = Configuration.new
    end

    def global_key?(key)
      config.global_modules.include?(key.to_s.split(".").first)
    end

    def scoped?
      !config.scope_class.nil?
    end

    def current_scope
      config.current_scope.call
    end
  end
end

require "easy_access_control/engine" if defined?(Rails::Engine)
