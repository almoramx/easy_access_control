require_relative "lib/easy_access_control/version"

Gem::Specification.new do |spec|
  spec.name = "easy_access_control"
  spec.version = EasyAccessControl::VERSION
  spec.authors = ["Almora"]
  spec.summary = "Toggleable, optionally scope-aware RBAC on top of Pundit"
  spec.homepage = "https://github.com/almoramx/easy_access_control"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.files = Dir["lib/**/*", "app/**/*", "db/**/*", "README.md"]
  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "pundit", "~> 2.3"
end
