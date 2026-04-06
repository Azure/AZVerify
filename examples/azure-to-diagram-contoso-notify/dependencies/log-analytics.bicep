targetScope = 'resourceGroup'

// Ensures the Log Analytics workspace exists in DefaultResourceGroup-SEC.
// Application Insights in Contoso-Notify connects to this workspace.
// Deploy to DefaultResourceGroup-SEC — not the Contoso-Notify resource group.

@description('Azure region for the Log Analytics workspace.')
param location string = 'swedencentral'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'DefaultWorkspace-<SUBSCRIPTION_ID>-SEC'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    // 30-day retention for the default workspace. Increase for longer audit trails.
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
