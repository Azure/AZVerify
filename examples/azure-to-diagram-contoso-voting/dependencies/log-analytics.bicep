// External dependency for Contoso-Voting/Application Insights
// This template deploys the Log Analytics workspace that Application Insights
// in the Contoso-Voting resource group uses for log ingestion.
// Target resource group: DefaultResourceGroup-NEU
//
// Deploy with:
//   az deployment group create --resource-group DefaultResourceGroup-NEU \
//     --template-file log-analytics.bicep --parameters @log-analytics.bicepparam

targetScope = 'resourceGroup'

@description('Azure region for the workspace.')
param location string = 'northeurope'

@description('Name of the Log Analytics workspace.')
param workspaceName string = 'DefaultWorkspace-<SUBSCRIPTION_ID>-NEU'

@description('Retention period in days for log data.')
param retentionInDays int = 30

@description('SKU for the Log Analytics workspace.')
@allowed(['PerGB2018', 'Free', 'CapacityReservation'])
param skuName string = 'PerGB2018'

@description('Resource tags.')
param tags object = {}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: skuName
    }
    retentionInDays: retentionInDays
  }
}

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
