targetScope = 'resourceGroup'

@description('Globally unique storage account name used by the AzVerify functional test.')
@minLength(3)
@maxLength(24)
@metadata({ doc: 'Lowercase letters and numbers only.' })
param storageAccountName string

resource testStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: resourceGroup().location
  tags: {
    azverifyFunctionalTest: 'true'
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
  }
}

output storageAccountId string = testStorage.id
