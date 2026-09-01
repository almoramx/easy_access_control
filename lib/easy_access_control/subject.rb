module EasyAccessControl
  module Subject
    extend ActiveSupport::Concern

    included do
      has_many :role_assignments, class_name: "EasyAccessControl::RoleAssignment",
                                  foreign_key: :subject_id, dependent: :destroy
      has_many :permission_overrides, class_name: "EasyAccessControl::PermissionOverride",
                                      foreign_key: :subject_id, dependent: :destroy
      has_many :global_permissions, class_name: "EasyAccessControl::GlobalPermission",
                                    foreign_key: :subject_id, dependent: :destroy
    end

    def access_admin?
      !!public_send(EasyAccessControl.config.admin_method)
    end

    def can?(key, scope: nil)
      return true if access_admin?
      key = key.to_s
      return global_grant?(key) if EasyAccessControl.global_key?(key)
      target = scope || EasyAccessControl.current_scope
      return false if EasyAccessControl.scoped? && target.nil?
      override = permission_overrides.joins(:permission)
                                     .merge(EasyAccessControl::Permission.where(key: key))
                                     .find_by(scope_id: target&.id)
      return override.grant? if override
      role = role_at(target)
      return false unless role
      role.permissions.exists?(key: key)
    end

    def role_at(scope)
      role_assignments.find_by(scope_id: scope&.id)&.role
    end

    def toggle_override!(permission:, scope: nil)
      unless permission.is_a?(EasyAccessControl::Permission)
        permission = EasyAccessControl::Permission.find_by!(key: permission.to_s)
      end
      raise ArgumentError, "#{permission.key} is a global permission" if permission.global?
      raise ArgumentError, "scope is required when scoped" if scope.nil? && EasyAccessControl.scoped?
      existing = permission_overrides.find_by(permission_id: permission.id, scope_id: scope&.id)
      if existing
        existing.destroy!
        return nil
      end
      default_on = role_at(scope)&.permissions&.exists?(id: permission.id) || false
      permission_overrides.create!(
        permission_id: permission.id, scope_id: scope&.id, effect: default_on ? :deny : :grant
      )
    end

    # Stamp mode: makes the subject's access match the role exactly, with no
    # live link — editing the role later changes nobody already stamped.
    # At the given scope it clears any role assignment and every override,
    # then grants the role's scoped permissions as overrides; the subject's
    # global permissions are replaced by the role's global ones.
    def apply_role!(role, scope: nil)
      raise ArgumentError, "scope is required when scoped" if scope.nil? && EasyAccessControl.scoped?
      scoped_perms, global_perms = role.permissions.partition { |permission| !permission.global? }
      self.class.transaction do
        role_assignments.where(scope_id: scope&.id).destroy_all
        permission_overrides.where(scope_id: scope&.id).destroy_all
        scoped_perms.each do |permission|
          permission_overrides.create!(permission_id: permission.id, scope_id: scope&.id, effect: :grant)
        end
        global_permissions.destroy_all
        global_perms.each { |permission| global_permissions.create!(permission_id: permission.id) }
      end
      self
    end

    private

    def global_grant?(key)
      global_permissions.joins(:permission)
                        .merge(EasyAccessControl::Permission.where(key: key)).exists?
    end
  end
end
