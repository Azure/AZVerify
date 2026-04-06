# Azure-to-Diagram: Contoso-Voting

## Source

| Field | Value |
|-------|-------|
| Scope | Resource Group |
| Resource Group | `Contoso-Voting` |
| Subscription | Azure subscription 1 (`<SUBSCRIPTION_ID>`) |
| Discovery Date | 2026-04-05 |
| Model | claude-Opus-4.6 |

## Resource Summary

- **Total discovered**: 8
- **Included in diagram**: 6
- **Excluded**: 2 (Application Insights, Smart Detector Alert Rule)

## Full Resource Table

| # | Resource | Type | Location |
|---|----------|------|----------|
| 1 | contoso-voting | Microsoft.Web/sites | northeurope |
| 2 | asp-contoso-voting-linux | Microsoft.Web/serverFarms | northeurope |
| 3 | contoso-voting | Microsoft.Storage/storageAccounts | northeurope |
| 4 | kv-contoso-voting | Microsoft.KeyVault/vaults | northeurope |
| 5 | contoso-voting-eventgrid | Microsoft.EventGrid/systemTopics | northeurope |
| 6 | deploy-uami | Microsoft.ManagedIdentity/userAssignedIdentities | northeurope |

## Excluded Resources

| # | Resource | Type | Reason |
|---|----------|------|--------|
| 1 | contoso-voting | microsoft.insights/components | Application Insights — excluded for diagrams |
| 2 | Failure Anomalies - contoso-voting | microsoft.alertsmanagement/smartDetectorAlertRules | Auto-created alert rule |

## Relationships

| # | Source | Relationship | Target | Detection |
|---|--------|-------------|--------|-----------|
| 1 | contoso-voting (App Service) | depends | asp-contoso-voting-linux (ASP) | `appServicePlanId` reference |
| 2 | contoso-voting (Event Grid) | connects | contoso-voting (Storage) | `source` property = storage account ARM ID |
| 3 | deploy-uami (Managed Identity) | secures | contoso-voting (App Service) | RBAC: Website Contributor role assignment |
| 4 | contoso-voting (App Service) | connects | kv-contoso-voting (Key Vault) | Co-located inference (inferred) |
| 5 | contoso-voting (App Service) | connects | contoso-voting (Storage) | Co-located inference + mounted DB path (inferred) |

## Key Observations

- **App Service** uses a `SystemAssigned` managed identity and has a separate user-assigned identity (`deploy-uami`) with Website Contributor role — likely used for CI/CD (OIDC federation).
- **Storage Account** has a connection string (`PollDb`) pointing to a mounted SQLite database (`/mounts/data/polls.db`), indicating the app uses Azure Files mount with an embedded database.
- **EventGrid System Topic** monitors the Storage Account for blob events (auto-generated name).
- **No VNet integration** — all resources are publicly accessible.
- Two relationships marked `(inferred)` are based on co-location in a small resource group (≤15 resources).

## Diagram Layout

- **Pattern**: Hub-and-spoke (App Service as hub)
- **Left column**: Security/Identity (Key Vault, Managed Identity)
- **Center column**: Application (ASP above, App Service below)
- **Right column**: Data (Storage Account, EventGrid System Topic)
- **Page**: 1400×780 (compact — ≤15 resources)

## Next Steps

- **Generate Bicep from this diagram**: Use `/azv-diagram-to-bicep` with `contoso-voting.drawio`
- **Compare diagram to live Azure**: Use `/azv-diagram-azure-sync` to detect drift
