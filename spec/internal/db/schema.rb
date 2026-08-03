ActiveRecord::Schema.define do
  create_table :employees, force: true do |t|
    t.string :name
    t.boolean :is_administrator, null: false, default: false
  end

  create_table :warehouses, force: true do |t|
    t.string :name
  end

  create_table :easy_access_control_permissions, force: true do |t|
    t.string :key, null: false
    t.string :module_name, null: false
    t.timestamps
  end
  add_index :easy_access_control_permissions, :key, unique: true, name: "eac_permissions_key_uniq"

  create_table :easy_access_control_roles, force: true do |t|
    t.string :name, null: false
    t.timestamps
  end
  add_index :easy_access_control_roles, :name, unique: true, name: "eac_roles_name_uniq"

  create_table :easy_access_control_role_permissions, force: true do |t|
    t.references :role, null: false, index: { name: "eac_role_permissions_role" }
    t.references :permission, null: false, index: { name: "eac_role_permissions_permission" }
  end
  add_index :easy_access_control_role_permissions, [:role_id, :permission_id], unique: true, name: "eac_role_permissions_uniq"

  create_table :easy_access_control_role_assignments, force: true do |t|
    t.bigint :subject_id, null: false
    t.references :role, null: false, index: { name: "eac_role_assignments_role" }
    t.bigint :scope_id
    t.timestamps
  end
  add_index :easy_access_control_role_assignments, [:subject_id, :scope_id], unique: true, name: "eac_role_assignments_uniq"

  create_table :easy_access_control_permission_overrides, force: true do |t|
    t.bigint :subject_id, null: false
    t.references :permission, null: false, index: { name: "eac_permission_overrides_permission" }
    t.bigint :scope_id
    t.integer :effect, null: false
    t.timestamps
  end
  add_index :easy_access_control_permission_overrides, [:subject_id, :permission_id, :scope_id], unique: true, name: "eac_permission_overrides_uniq"

  create_table :easy_access_control_global_permissions, force: true do |t|
    t.bigint :subject_id, null: false
    t.references :permission, null: false, index: { name: "eac_global_permissions_permission" }
  end
  add_index :easy_access_control_global_permissions, [:subject_id, :permission_id], unique: true, name: "eac_global_permissions_uniq"
end
