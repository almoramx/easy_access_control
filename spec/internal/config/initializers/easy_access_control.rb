EasyAccessControl.configure do |c|
  c.subject_class = "Employee"
  c.scope_class = "Warehouse"
  c.global_modules = %w[config]
  c.role_names = %w[admin seller]
end
