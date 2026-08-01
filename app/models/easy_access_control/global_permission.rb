module EasyAccessControl
  class GlobalPermission < ActiveRecord::Base
    self.table_name = "global_permissions"

    belongs_to :permission, class_name: "EasyAccessControl::Permission"

    validates :subject_id, presence: true
    validates :permission_id, uniqueness: { scope: :subject_id }
  end
end
