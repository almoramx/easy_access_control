RSpec.shared_examples "scope-isolated permissions" do
  it "denies at another scope what the role grants at the assigned scope" do
    expect(subject_with_role.can?(granted_key, scope: assigned_scope)).to be true
    expect(subject_with_role.can?(granted_key, scope: other_scope)).to be false
  end
end
