module EasyAccessControl
  class Permission < ActiveRecord::Base
    self.table_name = "permissions"

    KEY_FORMAT = /\A[a-z0-9_]+\.[a-z0-9_]+\z/

    has_many :role_permissions, class_name: "EasyAccessControl::RolePermission", dependent: :destroy
    has_many :permission_overrides, class_name: "EasyAccessControl::PermissionOverride", dependent: :destroy
    has_many :global_permissions, class_name: "EasyAccessControl::GlobalPermission", dependent: :destroy

    before_validation { self.module_name ||= key.to_s.split(".").first }

    validates :key, presence: true, uniqueness: true, format: { with: KEY_FORMAT }
    validates :module_name, presence: true

    scope :global, -> { where(module_name: EasyAccessControl.config.global_modules) }
    scope :non_global, -> { where.not(module_name: EasyAccessControl.config.global_modules) }

    def global?
      EasyAccessControl.global_key?(key)
    end
  end
end
