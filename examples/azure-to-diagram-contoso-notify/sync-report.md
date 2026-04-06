# Bicep-Diagram Sync Report: Contoso-Notify

**Diagram source:** `results/contoso-notify/claude-Opus-4.6/Contoso-Notify.drawio`  
**Bicep source:** `results/contoso-notify/claude-Opus-4.6/artifacts/`  
**Resource Group:** `rg-azv-contoso-notify-opus46`  
**Subscription:** Azure subscription 1 (`<SUBSCRIPTION_ID>`)  
**Generated:** 2026-04-06

---

## Parsed Diagram Resources

| # | Resource | Type | Container |
|---|----------|------|-----------|
| 1 | asp-contoso-notify-fc1 | `Microsoft.Web/serverFarms` | Contoso-Notify (RG) |
| 2 | contoso-notify | `Microsoft.Web/sites` (Function App) | Contoso-Notify (RG) |
| 3 | contosonotify (Key Vault) | `Microsoft.KeyVault/vaults` | Contoso-Notify (RG) |
| 4 | contoso-notify-uami | `Microsoft.ManagedIdentity/userAssignedIdentities` | Contoso-Notify (RG) |
| 5 | contosonotify (Storage) | `Microsoft.Storage/storageAccounts` | Contoso-Notify (RG) |
| 6 | Contoso-notify-ACS | `Microsoft.Communication/communicationServices` | Contoso-Notify (RG) |
| 7 | contoso-email-service (Email) | `Microsoft.Communication/emailServices` | Contoso-Notify (RG) |
| 8 | <DOMAIN> | `Microsoft.Communication/emailServices/domains` | Contoso-Notify (RG) |
| 9 | AzureManagedDomain | `Microsoft.Communication/emailServices/domains` | Contoso-Notify (RG) |

---

## Parsed Bicep Resources

| # | Resource | Type | Source File | Notes |
|---|----------|------|-------------|-------|
| 1 | contoso-notify-opus46-uami | `Microsoft.ManagedIdentity/userAssignedIdentities` | modules/identity.bicep | |
| 2 | contosonotify001 | `Microsoft.Storage/storageAccounts` | modules/data.bicep | |
| 3 | kv-contoso-notify-opus46-001 | `Microsoft.KeyVault/vaults` | modules/data.bicep | |
| 4 | contoso-notify-opus46 | `Microsoft.Insights/components` | modules/monitoring.bicep | |
| 5 | asp-contoso-notify-opus46-fc1 | `Microsoft.Web/serverfarms` | modules/compute.bicep | |
| 6 | contoso-notify-opus46-001 | `Microsoft.Web/sites` | modules/compute.bicep | kind: functionapp,linux |
| 7 | contoso-email-opus46-001 | `Microsoft.Communication/emailServices` | modules/communication.bicep | |
| 8 | AzureManagedDomain | `Microsoft.Communication/emailServices/domains` | modules/communication.bicep | parent: emailService |
| 9 | <DOMAIN> | `Microsoft.Communication/emailServices/domains` | modules/communication.bicep | parent: emailService |
| 10 | contoso-notify-acs-opus46-001 | `Microsoft.Communication/communicationServices` | modules/communication.bicep | |

---

## Summary

- **In Sync:** 9 resources
- **Bicep Only:** 1 resource (in Bicep, not in diagram)
- **Diagram Only:** 0 resources

## Details

| Resource | Type | Status | Notes |
|----------|------|--------|-------|
| App Service Plan | `Microsoft.Web/serverFarms` | ✅ In Sync (name differs) | Diagram: "asp-contoso-notify-fc1", Bicep: "asp-contoso-notify-opus46-fc1" |
| Function App | `Microsoft.Web/sites` | ✅ In Sync (name differs) | Diagram: "contoso-notify", Bicep: "contoso-notify-opus46-001" |
| Key Vault | `Microsoft.KeyVault/vaults` | ✅ In Sync (name differs) | Diagram: "contosonotify (Key Vault)", Bicep: "kv-contoso-notify-opus46-001" |
| Managed Identity | `Microsoft.ManagedIdentity/userAssignedIdentities` | ✅ In Sync (name differs) | Diagram: "contoso-notify-uami", Bicep: "contoso-notify-opus46-uami" |
| Storage Account | `Microsoft.Storage/storageAccounts` | ✅ In Sync (name differs) | Diagram: "contosonotify (Storage)", Bicep: "contosonotify001" |
| Communication Services | `Microsoft.Communication/communicationServices` | ✅ In Sync (name differs) | Diagram: "Contoso-notify-ACS", Bicep: "contoso-notify-acs-opus46-001" |
| Email Service | `Microsoft.Communication/emailServices` | ✅ In Sync (name differs) | Diagram: "contoso-email-service (Email)", Bicep: "contoso-email-opus46-001" |
| <DOMAIN> | `Microsoft.Communication/emailServices/domains` | ✅ In Sync | Exact name match |
| AzureManagedDomain | `Microsoft.Communication/emailServices/domains` | ✅ In Sync | Exact name match |
| contoso-notify-opus46 | `Microsoft.Insights/components` | ⬜ Bicep Only | In modules/monitoring.bicep; no Application Insights icon in diagram |

---

## Resolution

No action taken — report stored for reference.

The only drift is **Application Insights** (`Microsoft.Insights/components`) which exists in Bicep (`modules/monitoring.bicep`) but has no corresponding icon in the diagram. All other 9 resources are in sync (names differ due to the Opus 4.6 deployment suffix convention but types match 1:1).
