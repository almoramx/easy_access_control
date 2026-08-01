class WidgetsPolicy < EasyAccessControl::Policy
  permits :list, :create

  def export?
    can?(:list) && record == :exportable
  end
end
