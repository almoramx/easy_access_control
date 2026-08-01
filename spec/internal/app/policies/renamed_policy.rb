class RenamedPolicy < EasyAccessControl::Policy
  permission_module "sap_invoices"
  permits :list
end
