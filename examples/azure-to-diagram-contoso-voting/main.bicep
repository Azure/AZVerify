targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = 'northeurope'

@description('Name of the App Service Plan.')
param appServicePlanName string = 'asp-contoso-voting-linux'

@description('SKU name for the App Service Plan.')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'P1v3', 'P2v3'])
param appServicePlanSkuName string = 'B1'

@description('Name of the App Service (Web App).')
param appServiceName string = 'contoso-voting'

@description('Runtime stack for the App Service.')
param appServiceRuntimeStack string = 'DOTNETCORE|10.0'

@description('Name of the Storage Account.')
param storageAccountName string = 'contoso-voting'

@description('SKU name for the Storage Account.')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS', 'Premium_LRS'])
param storageAccountSkuName string = 'Standard_LRS'

@description('Name of the Key Vault.')
param keyVaultName string = 'kv-contoso-voting'

@description('Soft delete retention period in days for Key Vault.')
param keyVaultSoftDeleteRetentionDays int = 7

@description('Name of the Application Insights component.')
param appInsightsName string = 'contoso-voting'

@description('Resource ID of the Log Analytics workspace for Application Insights (external dependency).')
param logAnalyticsWorkspaceId string

@description('Name of the EventGrid System Topic.')
param eventGridTopicName string = 'contoso-voting-eventgrid'

@description('Name of the user-assigned managed identity.')
param managedIdentityName string = 'deploy-uami'

@description('Application Insights connection string.')
@secure()
param appInsightsConnectionString string = ''

@description('Resource tags applied to all resources.')
param tags object = {}

module monitoring 'modules/monitoring.bicep' = {
  params: {
    location: location
    appInsightsName: appInsightsName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    tags: tags
  }
}

module data 'modules/data.bicep' = {
  params: {
    location: location
    storageAccountName: storageAccountName
    storageAccountSkuName: storageAccountSkuName
    keyVaultName: keyVaultName
    keyVaultSoftDeleteRetentionDays: keyVaultSoftDeleteRetentionDays
    eventGridTopicName: eventGridTopicName
    tags: tags
  }
}

module compute 'modules/compute.bicep' = {
  params: {
    location: location
    appServicePlanName: appServicePlanName
    appServicePlanSkuName: appServicePlanSkuName
    appServiceName: appServiceName
    appServiceRuntimeStack: appServiceRuntimeStack
    appInsightsConnectionString: appInsightsConnectionString
    tags: tags
  }
  dependsOn: [monitoring]
}

// Identity module must deploy after compute so the App Service exists for the role assignment
module identity 'modules/identity.bicep' = {
  params: {
    location: location
    managedIdentityName: managedIdentityName
    appServiceName: appServiceName
    tags: tags
  }
  dependsOn: [compute]
}

output appServiceId string = compute.outputs.appServiceId
output appServiceDefaultHostName string = compute.outputs.appServiceDefaultHostName
output keyVaultUri string = data.outputs.keyVaultUri
output storageAccountId string = data.outputs.storageAccountId
output appInsightsConnectionStringOutput string = monitoring.outputs.appInsightsConnectionString
output managedIdentityClientId string = identity.outputs.clientId
