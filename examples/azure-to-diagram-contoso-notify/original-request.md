# Contoso-Notify — Azure to Diagram

## Discovery Metadata

| Field | Value |
|---|---|
| Source Scope | Resource Group: `Contoso-Notify` |
| Subscription | Azure subscription 1 (`<SUBSCRIPTION_ID>`) |
| Discovery Date | 2026-04-05 |
| Skill | `azv-azure-to-diagram` |
| Model | Claude Sonnet 4.6 |
| Total Resources Discovered | 11 |
| Resources in Diagram | 9 |
| Resources Excluded | 2 |

---

## Resource Table (All Discovered)

| # | Resource | Type | Location | Diagram |
|---|---|---|---|---|
| 1 | Contoso-notify-ACS | Microsoft.Communication/CommunicationServices | global | ✅ |
| 2 | contosonotify | Microsoft.Storage/storageAccounts | swedencentral | ✅ |
| 3 | contoso-notify-uami | Microsoft.ManagedIdentity/userAssignedIdentities | swedencentral | ✅ |
| 4 | asp-contoso-notify-fc1 | Microsoft.Web/serverFarms | swedencentral | ✅ |
| 5 | contoso-notify | microsoft.insights/components | swedencentral | ❌ Excluded — Application Insights (excluded for diagrams) |
| 6 | contoso-notify | Microsoft.Web/sites (functionapp,linux) | swedencentral | ✅ |
| 7 | Failure Anomalies - contoso-notify | microsoft.alertsmanagement/smartDetectorAlertRules | global | ❌ Excluded — auto-created |
| 8 | contoso-email-service | Microsoft.Communication/EmailServices | global | ✅ |
| 9 | contoso-email-service/<DOMAIN> | Microsoft.Communication/EmailServices/Domains | global | ✅ |
| 10 | contoso-email-service/AzureManagedDomain | Microsoft.Communication/EmailServices/Domains | global | ✅ |
| 11 | contosonotify | Microsoft.KeyVault/vaults | swedencentral | ✅ |

---

## Relationship Table

| Source | Relationship | Target | Evidence | Edge Style |
|---|---|---|---|---|
| contoso-notify (Function App) | hosted on | asp-contoso-notify-fc1 | `serverFarmId` reference | dashed gray |
| contoso-notify (Function App) | reads secrets | contosonotify (Key Vault) | `@Microsoft.KeyVault(SecretUri=...)` in app settings (`AcsConnectionString`, `ExternalApiToken`); system-assigned identity has `Key Vault Secrets User` RBAC role | red |
| contoso-notify (Function App) | host storage | contosonotify (Storage Account) | `AzureWebJobsStorage__blobServiceUri`, `queueServiceUri`, `tableServiceUri` app settings | blue |
| contoso-notify (Function App) | uses identity | contoso-notify-uami | `userAssignedIdentities` in Function App identity config | red |
| contoso-notify (Function App) | ACS endpoint | Contoso-notify-ACS | `AcsConnectionString` in Key Vault, `SenderEmail` uses `azurecomm.net` domain | blue |
| contoso-notify (Function App) | AI Foundry | contoso-openai (external) | `AzureAIFoundryEndpoint` app setting; system identity has `Cognitive Services OpenAI User` on `contoso-openai` in `External-AI-RG` RG | blue (external) |
| contoso-notify-uami | Storage Blob Data Owner | contosonotify (Storage Account) | RBAC role assignment (`Storage Blob Data Owner`) on storage account; UAMI clientId matches `AzureWebJobsStorage__clientId` | red |
| Contoso-notify-ACS | linked domain | contoso-email-service | ACS Email capability linked to Email Services resource | blue |
| contoso-email-service | child domain | <DOMAIN> | `Microsoft.Communication/EmailServices/Domains` child resource | dashed gray |
| contoso-email-service | child domain | AzureManagedDomain | `Microsoft.Communication/EmailServices/Domains` child resource | dashed gray |

---

## Enrichment Details

### Function App: `contoso-notify`
- **Kind**: `functionapp,linux`  
- **Identity**: `SystemAssigned` + `UserAssigned` (contoso-notify-uami)
- **Key app settings**:
  - `APPLICATIONINSIGHTS_CONNECTION_STRING` — Application Insights (excluded)
  - `APPLICATIONINSIGHTS_AUTHENTICATION_STRING` — uses UAMI clientId (`2d0d8c5f-...`) for AAD auth to App Insights
  - `AzureWebJobsStorage__blobServiceUri/queueServiceUri/tableServiceUri` — Storage Account (contosonotify), uses UAMI (`managedidentity`)
  - `AcsConnectionString` — `@Microsoft.KeyVault(SecretUri=https://<KV_NAME>.vault.azure.net/secrets/AcsConnectionString)`
  - `ExternalApiToken` — `@Microsoft.KeyVault(SecretUri=https://<KV_NAME>.vault.azure.net/secrets/ExternalApiToken)`
  - `AzureAIFoundryEndpoint` — `https://<AI_ENDPOINT>/openai/responses?api-version=2025-04-01-preview`
  - `SenderEmail` — `donotreply@<AZURE_MANAGED_DOMAIN>.azurecomm.net` (Azure Managed Domain)
  - `NotificationEmail` — `example@example.com` (external recipient)
  - `OpenAIModel` — `gpt-5-mini`

### User-Assigned Managed Identity: `contoso-notify-uami`
- **RBAC role assignments**:
  - `Storage Blob Data Owner` on `contosonotify` storage account
  - `Storage Blob Data Contributor` on blob container `app-package-contoso-notify-0cb3f79` in `contosonotify`
  - `Monitoring Metrics Publisher` on `contoso-notify` Application Insights (excluded resource)

### Function App System-Assigned Identity
- **RBAC role assignments**:
  - `Key Vault Secrets User` on `contosonotify` Key Vault
  - `Cognitive Services OpenAI User` on `contoso-openai` in `External-AI-RG` RG (external dependency)

---

## External Dependencies

| Resource | RG | Type | Used For |
|---|---|---|---|
| contoso-openai | External-AI-RG | Microsoft.CognitiveServices/accounts | Azure OpenAI (`gpt-5-mini` model) — referenced via `AzureAIFoundryEndpoint` app setting |

---

## Diagram Output

- **File**: `Contoso-Notify.drawio`
- **Pages**: 1 (Architecture Overview)
- **Resources in diagram**: 9
- **Relationships / edges**: 10
- **External resources annotated**: 1 (contoso-openai in dashed external RG box)

---

## Next Steps

- **Generate Bicep from this diagram**: `/azv-diagram-to-bicep run diagram \`Results/contoso-notify/claude-Sonnet-4.6/artifacts/Contoso-Notify.drawio\``
- **Compare diagram against live Azure**: `/azv-diagram-azure-sync run diagram \`Results/contoso-notify/claude-Sonnet-4.6/artifacts/Contoso-Notify.drawio\``
- **Sync with a Bicep deployment**: `/azv-bicep-diagram-sync run diagram \`Results/contoso-notify/claude-Sonnet-4.6/artifacts/Contoso-Notify.drawio\``, bicep root \`Results/contoso-notify/claude-Sonnet-4.6/artifacts/\``
