module EasyAccessControl
  module Testing
    class << self
      def unverified_routes(exempt: [])
        Rails.application.routes.routes.filter_map do |route|
          controller = route.defaults[:controller]
          action = route.defaults[:action]
          next unless controller && action
          key = "#{controller}##{action}"
          next if exempt.include?(key)
          klass = "#{controller.camelize}Controller".safe_constantize
          next unless klass
          key unless verified?(klass)
        end.uniq.sort
      end

      private

      def verified?(klass)
        klass._process_action_callbacks.any? do |callback|
          callback.kind == :after && callback.filter == :verify_authorized
        end
      end
    end
  end
end
