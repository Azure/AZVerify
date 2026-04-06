@description('Azure region for all resources.')
param location string

@description('Name of the Storage Account.')
param storageAccountName string

@description('SKU name for the Storage Account.')
param storageAccountSkuName string

@description('Name of the Key Vault.')
param keyVaultName string

@description('Soft delete retention in days for Key Vault.')
param keyVaultSoftDeleteRetentionDays int

@description('Name of the EventGrid System Topic for storage account events.')
param eventGridTopicName string

@description('Resource tags.')
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  tags: tags
  sku: {
    name: storageAccountSkuName
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    // publicNetworkAccess is Enabled (current). For production, consider restricting with
    // private endpoints: set 'Disabled' and add Microsoft.Network/privateEndpoints.
    publicNetworkAccess: 'Enabled'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: keyVaultSoftDeleteRetentionDays
    // publicNetworkAccess is Enabled (current). For production, consider disabling:
    // set 'Disabled' and add a Microsoft.Network/privateEndpoints to protect secrets.
    publicNetworkAccess: 'Enabled'
    // enablePurgeProtection was not enabled in Azure — consider enabling for production
    // to prevent permanent deletion during retention period
  }
}

resource eventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    source: storageAccount.id
    topicType: 'microsoft.storage.storageaccounts'
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output eventGridTopicId string = eventGridSystemTopic.id
