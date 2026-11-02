targetScope = 'resourceGroup'

@description('Azure region for storage and Key Vault.')
param location string
@description('Baseline storage account name.')
param baselineStorageAccountName string
@description('Expanded storage account name.')
param storageAccountName string
@description('Key Vault name.')
param keyVaultName string
@description('User-assigned identity ID for the expanded storage account.')
param identityId string

resource baselineStorage 'Microsoft.Storage/storageAccounts@2026-06-01' = {
  name: baselineStorageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  tags: {
    azverifyFunctionalTest: 'true'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Allow'
      ipRules: []
      ipv6Rules: []
      virtualNetworkRules: []
      resourceAccessRules: [
        {
          resourceId: subscriptionResourceId('Microsoft.Security/dataScanners', 'storageDataScanner')
          tenantId: tenant().tenantId
        }
      ]
    }
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
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2026-06-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Allow'
      ipRules: []
      ipv6Rules: []
      virtualNetworkRules: []
      resourceAccessRules: [
        {
          resourceId: subscriptionResourceId('Microsoft.Security/dataScanners', 'storageDataScanner')
          tenantId: tenant().tenantId
        }
      ]
    }
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
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2026-05-15' = {
  name: keyVaultName
  location: location
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

output baselineStorageAccountId string = baselineStorage.id
output storageAccountId string = storage.id
output keyVaultId string = keyVault.id
