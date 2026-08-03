module EasyAccessControl
  class Role < ActiveRecord::Base
    has_many :role_permissions, class_name: "EasyAccessControl::RolePermission", dependent: :destroy
    has_many :permissions, through: :role_permissions

    validates :name, presence: true, uniqueness: true
    validates :name,
              inclusion: { in: ->(_) { EasyAccessControl.config.role_names } },
              if: -> { EasyAccessControl.config.role_names.any? }
  end
end
