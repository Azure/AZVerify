@description('Azure region for compute resources')
param location string

@description('Name of the App Service Plan')
param appServicePlanName string

@description('SKU name for the App Service Plan')
param appServicePlanSkuName string

@description('Name of the App Service')
param appServiceName string

@description('Runtime stack for the App Service (e.g., DOTNET|8.0, NODE|20-lts)')
param appServiceRuntimeStack string

@description('Resource ID of the VNet integration subnet')
param snetIntegrationId string

@description('Application Insights connection string for telemetry')
param appInsightsConnectionString string

resource asp 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: appServicePlanSkuName
  }
  properties: {
    reserved: true
  }
}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: asp.id
    httpsOnly: true
    virtualNetworkSubnetId: snetIntegrationId
    siteConfig: {
      linuxFxVersion: appServiceRuntimeStack
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      alwaysOn: true
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
      ]
    }
  }
}

@description('Default hostname of the App Service')
output appServiceDefaultHostname string = app.properties.defaultHostName

@description('Resource ID of the App Service')
output appServiceId string = app.id
