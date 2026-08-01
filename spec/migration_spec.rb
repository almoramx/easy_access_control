require "rails_helper"

RSpec.describe "install migration" do
  it "creates every gem table on a bare database" do
    path = EasyAccessControl::Engine.root.join(
      "db/migrate/20260801000001_create_easy_access_control_tables.rb"
    )
    expect(File.exist?(path)).to be true
    require path
    connection = ActiveRecord::Base.connection
    %w[permissions roles role_permissions role_assignments permission_overrides global_permissions].each do |table|
      connection.drop_table(table, if_exists: true)
    end
    CreateEasyAccessControlTables.new.migrate(:up)
    %w[permissions roles role_permissions role_assignments permission_overrides global_permissions].each do |table|
      expect(connection.table_exists?(table)).to be(true), "missing #{table}"
    end
  end
end
