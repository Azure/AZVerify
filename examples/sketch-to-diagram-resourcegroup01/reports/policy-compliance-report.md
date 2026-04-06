# Policy Compliance Check — resourcegroup01-drawing (claude-Opus-4.6)

| # | Resource | Type | Status |
|---|----------|------|--------|
| 1 | rg-azv-resourcegroup01-opus46 | Microsoft.Resources/subscriptions/resourceGroups | ✅ Compliant |
| 2 | VNET-01 | Microsoft.Network/virtualNetworks | ✅ Compliant |
| 3 | NIC-01 | Microsoft.Network/networkInterfaces | ✅ Compliant |
| 4 | VM01 | Microsoft.Compute/virtualMachines | ✅ Compliant |
| 5 | App-Service-Plan | Microsoft.Web/serverfarms | ✅ Compliant |
| 6 | webapp-rg01-opus46-001 | Microsoft.Web/sites | ✅ Compliant |
| 7 | pe-webapp | Microsoft.Network/privateEndpoints | ✅ Compliant |
| 8 | privatelink.azurewebsites.net | Microsoft.Network/privateDnsZones | ✅ Compliant |
| 9 | VNET-01-link | Microsoft.Network/privateDnsZones/virtualNetworkLinks | ✅ Compliant |

**Scope**: rg-azv-resourcegroup01-opus46 (Subscription: Azure subscription 1 — `<SUBSCRIPTION_ID>`)
**Policies evaluated**: 9 policy assignments (server-side via `checkPolicyRestrictions` API)
**Result**: 9 compliant, 0 non-compliant, 0 need review

## Details

All 9 resources passed policy compliance checks. No `fieldRestrictions` or `contentEvaluationResult.policyEvaluations` violations were returned by the Azure Policy engine.

### Resources checked

| Resource | API Scope | API Exit Code |
|----------|-----------|---------------|
| Resource Group | Subscription-level | 0 |
| Virtual Network | Resource Group-level | 0 |
| Network Interface | Resource Group-level | 0 |
| Virtual Machine | Resource Group-level | 0 |
| App Service Plan | Resource Group-level | 0 |
| Web App | Resource Group-level | 0 |
| Private Endpoint | Resource Group-level | 0 |
| Private DNS Zone | Resource Group-level | 0 |
| Private DNS Zone VNet Link | Resource Group-level | 0 |

### Bicep source files

- `main.bicep` — orchestrator (private endpoint, DNS zone, DNS zone link, DNS zone group)
- `modules/networking.bicep` — VNet, Subnet-01, Subnet-02
- `modules/compute.bicep` — NIC, VM, App Service Plan, Web App
- `resourcegroup01-drawing.bicepparam` — parameter values

### Notes

- The `adminPassword` parameter is read from environment variable `VM_ADMIN_PASSWORD` at deployment time and was excluded from the policy check payload (passwords are not policy-evaluated).
- The `webAppName` resolves to `webapp-rg01-opus46-001` using the default deployment suffix.
- The resource group already exists at location `eastus` with no tags.
