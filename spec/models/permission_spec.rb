require "rails_helper"

RSpec.describe EasyAccessControl::Permission do
  it "requires a valid module.action key and backfills module_name" do
    permission = described_class.create!(key: "orders.refund_approve")
    expect(permission.module_name).to eq("orders")
    expect(described_class.new(key: "orders").valid?).to be false
    expect(described_class.new(key: "Orders.List").valid?).to be false
    expect(described_class.new(key: "products.list1_price").valid?).to be true
  end

  it "rejects duplicate keys" do
    described_class.create!(key: "orders.list")
    expect { described_class.create!(key: "orders.list") }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "splits global and non_global tiers by configured modules" do
    global = described_class.create!(key: "config.edit")
    scoped = described_class.create!(key: "orders.list")
    expect(described_class.global).to contain_exactly(global)
    expect(described_class.non_global).to contain_exactly(scoped)
    expect(global.global?).to be true
    expect(scoped.global?).to be false
  end
end
