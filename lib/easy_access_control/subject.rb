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
                                     .find_by(permissions: { key: key }, scope_id: target&.id)
      return override.grant? if override
      role = role_at(target)
      return false unless role
      role.permissions.exists?(key: key)
    end

    def role_at(scope)
      role_assignments.find_by(scope_id: scope&.id)&.role
    end

    private

    def global_grant?(key)
      global_permissions.joins(:permission).exists?(permissions: { key: key })
    end
  end
end
