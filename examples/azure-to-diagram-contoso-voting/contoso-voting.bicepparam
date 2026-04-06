using 'main.bicep'

// Shared suffix for globally unique names.
// Use 3-6 lowercase letters/digits, for example: az1, dev1, b42.
var deploymentSuffix = readEnvironmentVariable('AZV_SUFFIX', '001')

// Azure region for all resources.
//   northeurope  → Northern Europe (current)
//   westeurope   → Western Europe
//   eastus       → East US
param location = 'northeurope'

// App Service Plan name.
param appServicePlanName = 'asp-contoso-voting-opus46-linux'

// App Service Plan SKU — controls CPU, memory, and features.
//   B1  → 1 vCPU, 1.75 GB (~$13/mo) — Basic, no auto-scale, no VNet integration (current)
//   S1  → 1 vCPU, 1.75 GB (~$70/mo) — Standard, enables VNet integration, staging slots
//   P1v3 → 2 vCPU, 8 GB  (~$140/mo) — Premium v3, best performance
param appServicePlanSkuName = 'B1'

// App Service (Web App) name.
param appServiceName = 'contoso-voting-opus46-${deploymentSuffix}'

// Runtime stack for the App Service.
//   DOTNETCORE|10.0 → .NET 10 LTS (current, supported until Nov 2028)
//   DOTNETCORE|8.0  → .NET 8 LTS  (supported until Nov 2026)
//   NODE|22-lts      → Node.js 22 LTS (supported until Apr 2027)
param appServiceRuntimeStack = 'DOTNETCORE|10.0'

// Storage Account name (must be 3-24 lowercase alphanumeric, globally unique).
param storageAccountName = 'contoso-votingopus46${deploymentSuffix}'

// Storage Account SKU — redundancy level.
//   Standard_LRS  → Locally redundant     (~$0.018/GB) — current
//   Standard_ZRS  → Zone redundant        (~$0.023/GB) — recommended for prod
//   Standard_GRS  → Geo redundant         (~$0.036/GB) — highest durability
param storageAccountSkuName = 'Standard_LRS'

// Key Vault name (must be 3-24 alphanumeric/hyphen, globally unique).
param keyVaultName = 'kv-contoso-voting-opus46-${deploymentSuffix}'

// Soft delete retention in days for Key Vault.
//   7   → minimum (current)
//   90  → recommended for production
param keyVaultSoftDeleteRetentionDays = 7

// Application Insights component name.
param appInsightsName = 'contoso-voting-opus46'

// Resource ID of the external Log Analytics workspace Application Insights sends data to.
// This workspace lives in DefaultResourceGroup-NEU and must exist before deployment.
param logAnalyticsWorkspaceId = '/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/DefaultResourceGroup-NEU/providers/Microsoft.OperationalInsights/workspaces/DefaultWorkspace-<SUBSCRIPTION_ID>-NEU'

// EventGrid System Topic name for storage account events.
param eventGridTopicName = 'contoso-voting-opus46-eventgrid'

// User-assigned managed identity name.
param managedIdentityName = 'contoso-voting-opus46-uami'

// Application Insights connection string — reads from environment variable at deploy time.
// Set the APPINSIGHTS_CONNECTION_STRING environment variable before deploying.
// This is output by the monitoring module after deployment.
param appInsightsConnectionString = readEnvironmentVariable('APPINSIGHTS_CONNECTION_STRING', '')

// Resource tags applied to all resources.
param tags = {}
