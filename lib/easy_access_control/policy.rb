module EasyAccessControl
  class Policy
    attr_reader :subject, :context_scope, :record

    def initialize(user, record)
      @subject, @context_scope = Context.unwrap(user)
      @record = record
    end

    class << self
      def permission_module(name = nil)
        @permission_module = name.to_s if name
        @permission_module ||= self.name.demodulize.delete_suffix("Policy").underscore
      end

      def permits(*actions)
        actions.each do |action|
          define_method(:"#{action}?") { can?(action) }
        end
      end
    end

    def can?(action)
      return false unless subject
      key = "#{self.class.permission_module}.#{action.to_s.delete_suffix("?")}"
      subject.can?(key, scope: context_scope)
    end

    class Scope
      attr_reader :subject, :context_scope, :relation

      def initialize(user, relation)
        @subject, @context_scope = Context.unwrap(user)
        @relation = relation
      end

      def resolve
        relation
      end
    end
  end
end
