module EasyAccessControl
  class ResolvedAccess
    PermState = Data.define(:permission, :on, :source)

    def initialize(subject, scope: nil)
      @subject = subject
      @scope = scope
    end

    def states
      permissions.map { |permission| state_for(permission) }
    end

    private

    def permissions
      Permission.order(:module_name, :key).to_a
    end

    def state_for(permission)
      return PermState.new(permission:, on: true, source: :admin) if @subject.access_admin?
      if permission.global?
        return PermState.new(permission:, on: global_ids.include?(permission.id), source: :global)
      end
      override = overrides[permission.id]
      if override
        return PermState.new(permission:, on: override.grant?, source: override.effect.to_sym)
      end
      PermState.new(permission:, on: role_permission_ids.include?(permission.id), source: :role)
    end

    def overrides
      @overrides ||= @subject.permission_overrides.where(scope_id: @scope&.id).index_by(&:permission_id)
    end

    def global_ids
      @global_ids ||= @subject.global_permissions.pluck(:permission_id).to_set
    end

    def role_permission_ids
      @role_permission_ids ||= (@subject.role_at(@scope)&.permission_ids).to_a.to_set
    end
  end
end
