module EasyAccessControl
  class Configuration
    attr_accessor :subject_class, :scope_class, :admin_method, :global_modules,
                  :role_names, :current_scope, :table_prefix, :debug_ui

    def initialize
      @table_prefix = "easy_access_control_"
      @subject_class = nil
      @scope_class = nil
      @admin_method = :is_administrator?
      @global_modules = []
      @role_names = []
      @current_scope = -> { nil }
      @debug_ui = ->(_controller) { false }
    end
  end
end
