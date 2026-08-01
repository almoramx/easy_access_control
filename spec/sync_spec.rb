require "rails_helper"

RSpec.describe EasyAccessControl::Sync do
  it "derives keys from policy classes" do
    keys = described_class.policy_keys
    expect(keys).to include("gadgets.list", "widgets.list", "widgets.create", "widgets.export")
  end

  it "scans authorize! string keys under the given root" do
    keys = described_class.scanned_keys(Rails.root)
    expect(keys).to include("widgets.list")
  end

  it "creates missing permissions on run! without deleting extras" do
    orphan = EasyAccessControl::Permission.create!(key: "legacy.thing")
    described_class.run!
    expect(EasyAccessControl::Permission.find_by(key: "widgets.create")).to be_present
    expect(EasyAccessControl::Permission.exists?(orphan.id)).to be true
  end

  it "reports drift in both directions" do
    EasyAccessControl::Permission.create!(key: "legacy.thing")
    drift = described_class.drift
    expect(drift[:missing]).to include("widgets.create")
    expect(drift[:orphaned]).to eq(["legacy.thing"])
  end

  it "prunes only orphans" do
    described_class.run!
    EasyAccessControl::Permission.create!(key: "legacy.thing")
    described_class.prune!
    expect(EasyAccessControl::Permission.find_by(key: "legacy.thing")).to be_nil
    expect(EasyAccessControl::Permission.find_by(key: "widgets.list")).to be_present
  end

  it "is idempotent" do
    described_class.run!
    expect { described_class.run! }.not_to change(EasyAccessControl::Permission, :count)
  end

  it "ignores authorize! keys that do not match the module.action format" do
    dir = Rails.root.join("app", "tmp_scan")
    FileUtils.mkdir_p(dir)
    File.write(dir.join("bad_keys.rb"), 'authorize!("a.b.c") ; authorize!("orders.export")')
    keys = described_class.scanned_keys(Rails.root)
    expect(keys).to include("orders.export")
    expect(keys).not_to include("a.b.c", "b.c")
  ensure
    FileUtils.rm_rf(dir)
  end

  it "persists nothing when any expected key is invalid" do
    allow(described_class).to receive(:expected_keys).and_return(["orders.list", "bad key"])
    expect { described_class.run! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(EasyAccessControl::Permission.count).to eq(0)
  end
end
