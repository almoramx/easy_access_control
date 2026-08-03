module EasyAccessControl
  class RoleAssignment < ActiveRecord::Base
    belongs_to :role, class_name: "EasyAccessControl::Role"

    validates :subject_id, presence: true
    validates :subject_id, uniqueness: { scope: :scope_id }
  end
end
