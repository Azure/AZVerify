# Deep Sync Report — Contoso-Notify

**Skill**: `azv-diagram-azure-sync-deep`  
**Date**: 2026-04-06  
**Model**: Claude Sonnet 4.6  

## Inputs

| Parameter | Value |
|-----------|-------|
| Diagram | `results/contoso-notify/claude-Opus-4.6/Contoso-Notify.drawio` |
| Bicep root | `results/contoso-notify/claude-Opus-4.6/artifacts/` |
| Resource group | `rg-azv-contoso-notify-opus46` |
| Subscription | Azure subscription 1 (`<SUBSCRIPTION_ID>`) |

---

## Step 3 — Parsed Diagram Resource Model

| # | Resource (Diagram Label) | Type | Container |
|---|--------------------------|------|-----------|
| 1 | asp-contoso-notify-fc1 | `Microsoft.Web/serverFarms` | Contoso-Notify (RG) |
| 2 | contoso-notify | `Microsoft.Web/sites` (Function App, linux) | Contoso-Notify (RG) |
| 3 | contosonotify | `Microsoft.KeyVault/vaults` | Contoso-Notify (RG) |
| 4 | contoso-notify-uami | `Microsoft.ManagedIdentity/userAssignedIdentities` | Contoso-Notify (RG) |
| 5 | contosonotify | `Microsoft.Storage/storageAccounts` | Contoso-Notify (RG) |
| 6 | Contoso-notify-ACS | `Microsoft.Communication/communicationServices` | Contoso-Notify (RG) |
| 7 | contoso-email-service | `Microsoft.Communication/emailServices` | Contoso-Notify (RG) |
| 8 | <DOMAIN> | `Microsoft.Communication/emailServices/domains` | Contoso-Notify (RG) |
| 9 | AzureManagedDomain | `Microsoft.Communication/emailServices/domains` | Contoso-Notify (RG) |

---

## Step 4 — Azure Resource Model (after filtering)

| # | Azure Resource Name | Type | Location |
|---|---------------------|------|----------|
| 1 | asp-contoso-notify-opus46-fc1 | `Microsoft.Web/serverFarms` | swedencentral |
| 2 | contoso-notify-opus46-001 | `Microsoft.Web/sites` (functionapp,linux) | swedencentral |
| 3 | kv-contoso-notify-opus46-001 | `Microsoft.KeyVault/vaults` | swedencentral |
| 4 | contoso-notify-opus46-uami | `Microsoft.ManagedIdentity/userAssignedIdentities` | swedencentral |
| 5 | <STORAGE_ACCOUNT> | `Microsoft.Storage/storageAccounts` | swedencentral |
| 6 | contoso-notify-acs-opus46-001 | `Microsoft.Communication/CommunicationServices` | global |
| 7 | contoso-email-opus46-001 | `Microsoft.Communication/EmailServices` | global |
| 8 | <DOMAIN> | `Microsoft.Communication/EmailServices/Domains` | global |
| 9 | AzureManagedDomain | `Microsoft.Communication/EmailServices/Domains` | global |

**Excluded from comparison (filtering rules):**
- `contoso-notify-opus46` — `Microsoft.Insights/components` (excluded for diagrams)
- `Failure Anomalies - contoso-notify-opus46` — `microsoft.alertsmanagement/smartDetectorAlertRules` (auto-created)

---

## Step 5 — Existence Matching

| # | Diagram Resource | Azure Resource | Existence Status |
|---|------------------|----------------|-----------------|
| 1 | asp-contoso-notify-fc1 | asp-contoso-notify-opus46-fc1 | ✅ In Sync (name differs) |
| 2 | contoso-notify | contoso-notify-opus46-001 | ✅ In Sync (name differs) |
| 3 | contosonotify | kv-contoso-notify-opus46-001 | ✅ In Sync (name differs) |
| 4 | contoso-notify-uami | contoso-notify-opus46-uami | ✅ In Sync (name differs) |
| 5 | contosonotify | <STORAGE_ACCOUNT> | ✅ In Sync (name differs) |
| 6 | Contoso-notify-ACS | contoso-notify-acs-opus46-001 | ✅ In Sync (name differs) |
| 7 | contoso-email-service | contoso-email-opus46-001 | ✅ In Sync (name differs) |
| 8 | <DOMAIN> | <DOMAIN> | ✅ In Sync |
| 9 | AzureManagedDomain | AzureManagedDomain | ✅ In Sync |

Diagram Only: **none**  
Azure Only (after filtering): **none**

---

## Step 6 — Property-Level Drift

### App Service Plan — `asp-contoso-notify-opus46-fc1`

| Property | Expected | Source | Actual | Status |
|----------|----------|--------|--------|--------|
| skuName | FC1 | Bicep | FC1 | ✅ In Sync |
| skuTier | FlexConsumption | Bicep | FlexConsumption | ✅ In Sync |
| kind | functionapp | Bicep | functionapp | ✅ In Sync |
| reserved | true | Bicep | true | ✅ In Sync |
| capacity | 0 | default | 0 | ✅ In Sync |

### Function App — `contoso-notify-opus46-001`

| Property | Expected | Source | Actual | Status |
|----------|----------|--------|--------|--------|
| runtimeStack | `""` (FlexConsumption — uses `functionAppConfig`) | default | `""` | ✅ In Sync |
| httpsOnly | true | Bicep | true | ✅ In Sync |
| minTlsVersion | 1.2 | Bicep | 1.2 | ✅ In Sync |
| alwaysOn | false | default (N/A — FlexConsumption) | false | ✅ In Sync |
| http20Enabled | false | default | false | ✅ In Sync |
| ftpsState | FtpsOnly | Bicep | FtpsOnly | ✅ In Sync |
| publicNetworkAccess | Enabled | Bicep | Enabled | ✅ In Sync |
| vnetIntegrationSubnet | null | default | null | ✅ In Sync |

> **Note**: For Flex Consumption function apps (`FC1` tier), the `siteConfig.linuxFxVersion` is always empty. The actual runtime (`dotnet-isolated 10.0`) is configured in `functionAppConfig.runtime`, which is not tracked via the `runtimeStack` path. This is expected Azure behavior.

### Key Vault — `kv-contoso-notify-opus46-001`

| Property | Expected | Source | Actual | Status |
|----------|----------|--------|--------|--------|
| skuName | standard | Bicep | standard | ✅ In Sync |
| enableRbacAuthorization | true | Bicep | true | ✅ In Sync |
| enableSoftDelete | true | Bicep | true | ✅ In Sync |
| softDeleteRetentionInDays | 7 | Bicep (dev/test value) | 7 | ✅ In Sync |
| publicNetworkAccess | Enabled | Bicep | Enabled | ✅ In Sync |
| enablePurgeProtection | null | Bicep (not set) | null | ✅ In Sync |

### Storage Account — `<STORAGE_ACCOUNT>`

| Property | Expected | Source | Actual | Status |
|----------|----------|--------|--------|--------|
| skuName | Standard_LRS | Bicep | Standard_LRS | ✅ In Sync |
| kind | Storage | Bicep | Storage | ✅ In Sync |
| accessTier | null | default (N/A for Storage kind) | null | ✅ In Sync |
| minimumTlsVersion | TLS1_2 | Bicep | TLS1_2 | ✅ In Sync |
| supportsHttpsTrafficOnly | true | Bicep | true | ✅ In Sync |
| allowBlobPublicAccess | false | Bicep | false | ✅ In Sync |
| publicNetworkAccess | Enabled | Bicep | Enabled | ✅ In Sync |
| enableHierarchicalNamespace | null | default | null | ✅ In Sync |

### Resources Without Tracked Properties

The following resource types have no entries in `azure-resource-configs.md` — property comparison not applicable:

| Resource | Type |
|----------|------|
| contoso-notify-opus46-uami | `Microsoft.ManagedIdentity/userAssignedIdentities` |
| contoso-notify-acs-opus46-001 | `Microsoft.Communication/CommunicationServices` |
| contoso-email-opus46-001 | `Microsoft.Communication/EmailServices` |
| <DOMAIN> | `Microsoft.Communication/EmailServices/Domains` |
| AzureManagedDomain | `Microsoft.Communication/EmailServices/Domains` |

---

## Overall Result

## ✅ Fully In Sync

Zero existence drift. Zero property drift on all tracked resources.

### Tier 1 Summary

| Resource | Type | Existence | Critical | Warning | Info |
|----------|------|-----------|----------|---------|------|
| asp-contoso-notify-fc1 / asp-contoso-notify-opus46-fc1 | App Service Plan | ✅ In Sync (name differs) | 0 | 0 | 0 |
| contoso-notify / contoso-notify-opus46-001 | Function App | ✅ In Sync (name differs) | 0 | 0 | 0 |
| contosonotify / kv-contoso-notify-opus46-001 | Key Vault | ✅ In Sync (name differs) | 0 | 0 | 0 |
| contoso-notify-uami / contoso-notify-opus46-uami | Managed Identity | ✅ In Sync (name differs) | — | — | — |
| contosonotify / contosonotify001 | Storage Account | ✅ In Sync (name differs) | 0 | 0 | 0 |
| Contoso-notify-ACS / contoso-notify-acs-opus46-001 | Communication Services | ✅ In Sync (name differs) | — | — | — |
| contoso-email-service / contoso-email-opus46-001 | Email Services | ✅ In Sync (name differs) | — | — | — |
| <DOMAIN> | Email Domain | ✅ In Sync | — | — | — |
| AzureManagedDomain | Email Domain | ✅ In Sync | — | — | — |

---

## Informational Notes

1. **Name divergence pattern (expected)**: 7 of 9 resources have names that differ between diagram labels and Azure deployment names. The Azure names follow the pattern `<resource>-opus46-<suffix>`, while diagram labels are generic logical names. This is expected — diagram labels represent the architecture intent, not the deployment-specific names generated by the Bicep template.

2. **Email domain DNS not verified**: `<DOMAIN>` — all DNS verification records (Domain, SPF, DKIM, DKIM2, DMARC) are in **NotStarted** state. Before this custom domain can be used to send email, the following DNS records must be configured at the registrar:
   - **Domain TXT**: `<DOMAIN>` → `ms-domain-verification=<DOMAIN_VERIFICATION_TOKEN>`
   - **SPF TXT**: `<DOMAIN>` → `v=spf1 include:spf.protection.outlook.com -all`
   - **DKIM CNAME**: `selector1-azurecomm-prod-net._domainkey` → `selector1-azurecomm-prod-net._domainkey.azurecomm.net`
   - **DKIM2 CNAME**: `selector2-azurecomm-prod-net._domainkey` → `selector2-azurecomm-prod-net._domainkey.azurecomm.net`
   
   This is an operational action required, not a configuration drift.

3. **Application Insights deployed (excluded from diagram)**: `contoso-notify-opus46` (`Microsoft.Insights/components`) exists in Azure and is deployed linked to the Function App via `applicationInsightsConnectionString`. It is excluded from the diagram per filtering rules (`Microsoft.Insights/components` → "Excluded for Diagrams"). The deployment is consistent with the Bicep template.

4. **AzureManagedDomain verified**: The `AzureManagedDomain` email domain has all verification records in **Verified** state and can be used for email sending immediately.

5. **Function App runtime (FlexConsumption note)**: The deployed runtime is `dotnet-isolated 10.0`, as specified in the Bicep `functionAppConfig.runtime`. On FlexConsumption plans, `siteConfig.linuxFxVersion` is intentionally empty — the runtime tracking path in `azure-resource-configs.md` for this property does not apply to FlexConsumption apps.
