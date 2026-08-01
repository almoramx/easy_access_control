module EasyAccessControl
  class Sync
    AUTHORIZE_PATTERN = /\bauthorize!\s*\(?\s*["']([a-z0-9_]+\.[a-z0-9_]+)["']/

    class << self
      def expected_keys(root: Rails.root)
        (policy_keys + scanned_keys(root)).uniq.sort
      end

      def run!(root: Rails.root)
        Permission.transaction do
          expected_keys(root:).each do |key|
            Permission.find_or_create_by!(key:)
          end
        end
      end

      def drift(root: Rails.root)
        expected = expected_keys(root:)
        existing = Permission.pluck(:key)
        { missing: expected - existing, orphaned: (existing - expected).sort }
      end

      def prune!(root: Rails.root)
        Permission.where(key: drift(root:)[:orphaned]).destroy_all
      end

      def policy_keys
        Rails.application.eager_load!
        Policy.descendants.flat_map do |klass|
          next [] unless klass.name
          mod = klass.permission_module
          klass.public_instance_methods(false).grep(/\?\z/).map do |m|
            "#{mod}.#{m.to_s.delete_suffix("?")}"
          end
        end
      end

      def scanned_keys(root)
        Dir.glob(File.join(root, "app/**/*.{rb,erb}")).flat_map do |file|
          File.read(file).scan(AUTHORIZE_PATTERN).flatten
        end
      end
    end
  end
end
