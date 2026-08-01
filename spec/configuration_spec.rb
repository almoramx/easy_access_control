require "spec_helper"

RSpec.describe EasyAccessControl do
  it "defaults admin_method, global_modules, role_names, current_scope" do
    config = described_class.config
    expect(config.admin_method).to eq(:is_administrator?)
    expect(config.global_modules).to eq([])
    expect(config.role_names).to eq([])
    expect(config.current_scope.call).to be_nil
  end

  it "yields the config and memoizes it" do
    described_class.configure { |c| c.subject_class = "Employee" }
    expect(described_class.config.subject_class).to eq("Employee")
  end

  it "resets" do
    described_class.configure { |c| c.subject_class = "Employee" }
    described_class.reset_config!
    expect(described_class.config.subject_class).to be_nil
  end

  it "classifies global keys by module prefix" do
    described_class.configure { |c| c.global_modules = %w[config audit] }
    expect(described_class.global_key?("config.edit")).to be true
    expect(described_class.global_key?("orders.list")).to be false
  end

  it "reports scoped? from scope_class presence" do
    expect(described_class.scoped?).to be false
    described_class.configure { |c| c.scope_class = "Warehouse" }
    expect(described_class.scoped?).to be true
  end
end
