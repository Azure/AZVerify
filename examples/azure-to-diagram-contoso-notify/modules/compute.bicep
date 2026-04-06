@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Resource ID of the user-assigned managed identity.')
param uamiId string

@description('Client ID of the user-assigned managed identity (used for storage auth and App Insights AAD auth).')
param uamiClientId string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Storage account blob service endpoint.')
param storageAccountBlobEndpoint string

@description('Storage account queue service endpoint.')
param storageAccountQueueEndpoint string

@description('Storage account table service endpoint.')
param storageAccountTableEndpoint string

@description('Key Vault name for KV reference app settings.')
param keyVaultName string

@description('Notification email address.')
param notificationEmail string

@description('Azure AI Foundry endpoint URL.')
param azureAIFoundryEndpoint string

@description('OpenAI model deployment name.')
param openAIModel string

@description('Enable Contoso-Notify premium features.')
param usePremiumFeatures string

@description('Email sender address.')
param senderEmail string

var functionAppName = 'contoso-notify'

// Flex Consumption App Service Plan — scale-to-zero with per-instance billing.
resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: 'asp-contoso-notify-fc1'
  location: location
  kind: 'functionapp'
  tags: tags
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    reserved: true
    publicNetworkAccess: 'Enabled'
    // KV references resolved using system-assigned identity.
    // System-assigned identity needs 'Key Vault Secrets User' role on the vault — see dependencies/README.md.
    keyVaultReferenceIdentity: 'SystemAssigned'
    clientAffinityEnabled: false
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobcontainer'
          // Container 'app-package-contoso-notify' must exist in the storage account (created by data.bicep).
          value: '${storageAccountBlobEndpoint}app-package-${functionAppName}'
          authentication: {
            type: 'userassignedidentity'
            userAssignedIdentityResourceId: uamiId
          }
        }
      }
      runtime: {
        name: 'dotnet-isolated'
        // .NET 10 (LTS, supported until Nov 2028).
        // Alternatives: '9.0' (STS), '8.0' (LTS, supported until Nov 2026).
        version: '10.0'
      }
      scaleAndConcurrency: {
        // 2048 MB per instance — handles moderate workloads.
        // Options: 512, 1024, 2048, 4096 MB.
        instanceMemoryMB: 2048
        // Maximum concurrent instances. Reduce for cost control.
        maximumInstanceCount: 100
      }
    }
    siteConfig: {
      ftpsState: 'FtpsOnly'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          // AAD-based App Insights auth using UAMI; requires DisableLocalAuth=true on App Insights.
          name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING'
          value: 'ClientId=${uamiClientId};Authorization=AAD'
        }
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: storageAccountBlobEndpoint
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: storageAccountQueueEndpoint
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: storageAccountTableEndpoint
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: uamiClientId
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'NotificationEmail'
          value: notificationEmail
        }
        {
          name: 'OpenAIModel'
          value: openAIModel
        }
        {
          name: 'SenderEmail'
          value: senderEmail
        }
        {
          name: 'UsePremiumFeatures'
          value: usePremiumFeatures
        }
        {
          name: 'AzureAIFoundryEndpoint'
          value: azureAIFoundryEndpoint
        }
        {
          // Secret read via Key Vault reference using Function App system-assigned identity.
          name: 'AcsConnectionString'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/AcsConnectionString)'
        }
        {
          // Secret read via Key Vault reference using Function App system-assigned identity.
          name: 'ExternalApiToken'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/ExternalApiToken)'
        }
      ]
    }
  }
}

output functionAppId string = functionApp.id
output functionAppHostname string = functionApp.properties.defaultHostName
output functionAppPrincipalId string = functionApp.identity.principalId
