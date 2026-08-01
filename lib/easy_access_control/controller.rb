module EasyAccessControl
  module Controller
    extend ActiveSupport::Concern
    include Pundit::Authorization

    def authorize!(key, scope: nil)
      subject, context_scope = Context.unwrap(pundit_user)
      unless subject&.can?(key, scope: scope || context_scope)
        raise Pundit::NotAuthorizedError, query: key
      end
      skip_authorization
      true
    end
  end
end
