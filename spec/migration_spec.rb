require "rails_helper"

RSpec.describe "install migration" do
  it "creates every gem table on a bare database" do
    path = EasyAccessControl::Engine.root.join(
      "db/migrate/20260801000001_create_easy_access_control_tables.rb"
    )
    expect(File.exist?(path)).to be true
    require path
    connection = ActiveRecord::Base.connection
    tables = %w[permissions roles role_permissions role_assignments permission_overrides global_permissions]
      .map { |t| "#{EasyAccessControl.table_name_prefix}#{t}" }
    tables.each { |table| connection.drop_table(table, if_exists: true) }
    CreateEasyAccessControlTables.new.migrate(:up)
    tables.each do |table|
      expect(connection.table_exists?(table)).to be(true), "missing #{table}"
    end
  end
end
