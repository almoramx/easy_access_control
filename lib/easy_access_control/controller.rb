module EasyAccessControl
  module Controller
    extend ActiveSupport::Concern
    include Pundit::Authorization

    included do
      if respond_to?(:helper_method)
        helper_method :can?, :eac_debug?, :eac_required_permissions
        helper EasyAccessControl::ViewHelper
      end
    end

    def authorize!(key, scope: nil)
      scope ||= Context.unwrap(pundit_user).last
      eac_required_permissions << [key.to_s, scope]
      raise Pundit::NotAuthorizedError, query: key unless can?(key, scope: scope)
      skip_authorization
      true
    end

    # Scope defaults to the pundit_user Context's. Memoized per request:
    # views ask the same key many times (one per row).
    def can?(key, scope: nil)
      subject, context_scope = Context.unwrap(pundit_user)
      scope ||= context_scope
      cache = (@eac_can_cache ||= {})
      cache_key = [key.to_s, scope&.id]
      return cache[cache_key] if cache.key?(cache_key)
      cache[cache_key] = !!subject&.can?(key, scope: scope)
    end

    def eac_debug?
      return @eac_debug if defined?(@eac_debug)
      @eac_debug = !!EasyAccessControl.config.debug_ui.call(self)
    end

    # [key, scope] pairs demanded by authorize! during this request.
    def eac_required_permissions
      @eac_required_permissions ||= []
    end
  end
end
