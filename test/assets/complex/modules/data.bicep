@description('Azure location.')
param location string

@description('Reserved test resource prefix.')
param prefix string

@description('Subscription-derived globally unique suffix.')
param nameSuffix string

var tags = { azverifyFunctionalTest: 'expanded-v1' }

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: '${prefix}-identity'
  location: location
  tags: tags
}

resource storage 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: '${prefix}${nameSuffix}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
  }
}

resource vault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: '${prefix}-kv-${nameSuffix}'
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
    accessPolicies: []
  }
}

output storageName string = storage.name
