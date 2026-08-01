module EasyAccessControl
  class PermissionOverride < ActiveRecord::Base
    self.table_name = "permission_overrides"

    belongs_to :permission, class_name: "EasyAccessControl::Permission"

    enum :effect, { grant: 0, deny: 1 }

    validates :subject_id, presence: true
    validates :permission_id, uniqueness: { scope: [:subject_id, :scope_id] }
  end
end
