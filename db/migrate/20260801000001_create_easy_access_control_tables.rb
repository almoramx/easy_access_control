class CreateEasyAccessControlTables < ActiveRecord::Migration[8.0]
  def change
    prefix = EasyAccessControl.config.table_prefix

    create_table :"#{prefix}permissions" do |t|
      t.string :key, null: false
      t.string :module_name, null: false
      t.timestamps
    end
    add_index :"#{prefix}permissions", :key, unique: true, name: "eac_permissions_key_uniq"

    create_table :"#{prefix}roles" do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :"#{prefix}roles", :name, unique: true, name: "eac_roles_name_uniq"

    create_table :"#{prefix}role_permissions" do |t|
      t.references :role, null: false, index: { name: "eac_role_permissions_role" }
      t.references :permission, null: false, index: { name: "eac_role_permissions_permission" }
    end
    add_index :"#{prefix}role_permissions", [:role_id, :permission_id], unique: true, name: "eac_role_permissions_uniq"

    create_table :"#{prefix}role_assignments" do |t|
      t.bigint :subject_id, null: false
      t.references :role, null: false, index: { name: "eac_role_assignments_role" }
      t.bigint :scope_id
      t.timestamps
    end
    add_index :"#{prefix}role_assignments", [:subject_id, :scope_id], unique: true, name: "eac_role_assignments_uniq"

    create_table :"#{prefix}permission_overrides" do |t|
      t.bigint :subject_id, null: false
      t.references :permission, null: false, index: { name: "eac_permission_overrides_permission" }
      t.bigint :scope_id
      t.integer :effect, null: false
      t.timestamps
    end
    add_index :"#{prefix}permission_overrides", [:subject_id, :permission_id, :scope_id], unique: true, name: "eac_permission_overrides_uniq"

    create_table :"#{prefix}global_permissions" do |t|
      t.bigint :subject_id, null: false
      t.references :permission, null: false, index: { name: "eac_global_permissions_permission" }
    end
    add_index :"#{prefix}global_permissions", [:subject_id, :permission_id], unique: true, name: "eac_global_permissions_uniq"
  end
end
