@description('Azure region for all resources.')
param location string

@description('Name of the App Service Plan.')
param appServicePlanName string

@description('SKU name for the App Service Plan.')
param appServicePlanSkuName string

@description('Name of the App Service (Web App).')
param appServiceName string

@description('Runtime stack for the App Service (e.g., DOTNETCORE|10.0).')
param appServiceRuntimeStack string

@description('Application Insights connection string.')
@secure()
param appInsightsConnectionString string

@description('Resource tags.')
param tags object = {}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  tags: tags
  sku: {
    name: appServicePlanSkuName
  }
  properties: {
    // reserved: true is required for Linux App Service Plans
    reserved: true
  }
}

resource appService 'Microsoft.Web/sites@2024-04-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      linuxFxVersion: appServiceRuntimeStack
      minTlsVersion: '1.2'
      http20Enabled: true
      // ftpsState: FtpsOnly (current). Consider 'Disabled' for stricter security.
      ftpsState: 'FtpsOnly'
      // alwaysOn is false on B1 SKU — upgrade to S1+ to enable
      alwaysOn: false
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~2'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'default'
        }
        {
          name: 'WEBSITE_HTTPLOGGING_RETENTION_DAYS'
          value: '3'
        }
      ]
    }
  }
}

output appServiceId string = appService.id
output appServiceDefaultHostName string = appService.properties.defaultHostName
output appServicePlanId string = appServicePlan.id
output appServicePrincipalId string = appService.identity.principalId
