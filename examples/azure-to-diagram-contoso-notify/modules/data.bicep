@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

// Storage Account — used for Function App deployment packages and WebJobs storage.
// Configured for managed identity access only (allowSharedKeyAccess: false).
resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: 'contosonotify'
  location: location
  kind: 'Storage'
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
}

// Blob container for Flex Consumption function app deployment packages.
resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: 'app-package-contoso-notify'
  properties: {
    publicAccess: 'None'
  }
}

// Key Vault — stores ACS connection string and Contoso-Notify API token.
// Uses RBAC authorization (no access policies).
// Note: Function App system-assigned identity needs 'Key Vault Secrets User' role — see dependencies/README.md.
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'contosonotify'
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    // Minimum retention; increase to 90 days for production workloads.
    softDeleteRetentionInDays: 7
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'None'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

output storageAccountId string = storageAccount.id
output storageAccountBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output storageAccountQueueEndpoint string = storageAccount.properties.primaryEndpoints.queue
output storageAccountTableEndpoint string = storageAccount.properties.primaryEndpoints.table
output deploymentContainerName string = deploymentContainer.name
output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
