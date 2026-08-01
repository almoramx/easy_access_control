class CreateEasyAccessControlTables < ActiveRecord::Migration[8.0]
  def change
    create_table :permissions do |t|
      t.string :key, null: false
      t.string :module_name, null: false
      t.timestamps
    end
    add_index :permissions, :key, unique: true

    create_table :roles do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :roles, :name, unique: true

    create_table :role_permissions do |t|
      t.references :role, null: false
      t.references :permission, null: false
    end
    add_index :role_permissions, [:role_id, :permission_id], unique: true

    create_table :role_assignments do |t|
      t.bigint :subject_id, null: false
      t.references :role, null: false
      t.bigint :scope_id
      t.timestamps
    end
    add_index :role_assignments, [:subject_id, :scope_id], unique: true

    create_table :permission_overrides do |t|
      t.bigint :subject_id, null: false
      t.references :permission, null: false
      t.bigint :scope_id
      t.integer :effect, null: false
      t.timestamps
    end
    add_index :permission_overrides, [:subject_id, :permission_id, :scope_id], unique: true

    create_table :global_permissions do |t|
      t.bigint :subject_id, null: false
      t.references :permission, null: false
    end
    add_index :global_permissions, [:subject_id, :permission_id], unique: true
  end
end
