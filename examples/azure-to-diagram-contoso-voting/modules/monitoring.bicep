@description('Azure region for all resources.')
param location string

@description('Name of the Application Insights component.')
param appInsightsName string

@description('Resource ID of the Log Analytics workspace (external dependency — must exist before deployment).')
param logAnalyticsWorkspaceId string

@description('Resource tags.')
param tags object = {}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    IngestionMode: 'LogAnalytics'
    WorkspaceResourceId: logAnalyticsWorkspaceId
  }
}

output appInsightsId string = appInsights.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output instrumentationKey string = appInsights.properties.InstrumentationKey
