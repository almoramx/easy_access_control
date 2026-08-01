namespace :easy_access_control do
  desc "Sync the permission catalog from policies and authorize! call sites"
  task sync: :environment do
    EasyAccessControl::Sync.run!
    puts "Synced. #{EasyAccessControl::Permission.count} permissions."
  end

  desc "Fail when the catalog drifts from code"
  task check: :environment do
    drift = EasyAccessControl::Sync.drift
    if drift.values.any?(&:any?)
      puts "missing: #{drift[:missing].join(", ")}"
      puts "orphaned: #{drift[:orphaned].join(", ")}"
      exit 1
    end
    puts "Catalog in sync."
  end

  desc "Remove orphaned permissions"
  task prune: :environment do
    EasyAccessControl::Sync.prune!
  end
end
