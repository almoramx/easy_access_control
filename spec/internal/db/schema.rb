ActiveRecord::Schema.define do
  create_table :employees, force: true do |t|
    t.string :name
    t.boolean :is_administrator, null: false, default: false
  end

  create_table :warehouses, force: true do |t|
    t.string :name
  end

  create_table :permissions, force: true do |t|
    t.string :key, null: false
    t.string :module_name, null: false
    t.timestamps
  end
  add_index :permissions, :key, unique: true

  create_table :roles, force: true do |t|
    t.string :name, null: false
    t.timestamps
  end
  add_index :roles, :name, unique: true

  create_table :role_permissions, force: true do |t|
    t.references :role, null: false
    t.references :permission, null: false
  end
  add_index :role_permissions, [:role_id, :permission_id], unique: true

  create_table :role_assignments, force: true do |t|
    t.bigint :subject_id, null: false
    t.references :role, null: false
    t.bigint :scope_id
    t.timestamps
  end
  add_index :role_assignments, [:subject_id, :scope_id], unique: true

  create_table :permission_overrides, force: true do |t|
    t.bigint :subject_id, null: false
    t.references :permission, null: false
    t.bigint :scope_id
    t.integer :effect, null: false
    t.timestamps
  end
  add_index :permission_overrides, [:subject_id, :permission_id, :scope_id], unique: true

  create_table :global_permissions, force: true do |t|
    t.bigint :subject_id, null: false
    t.references :permission, null: false
  end
  add_index :global_permissions, [:subject_id, :permission_id], unique: true
end
