module EasyAccessControl
  class RolePermission < ActiveRecord::Base
    self.table_name = "role_permissions"

    belongs_to :role, class_name: "EasyAccessControl::Role"
    belongs_to :permission, class_name: "EasyAccessControl::Permission"

    validates :permission_id, uniqueness: { scope: :role_id }
  end
end
