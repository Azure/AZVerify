@description('Azure region for the storage account.')
param location string

@description('Globally unique storage account name.')
param storageAccountName string

@description('Storage redundancy and performance tier.')
param storageSkuName string

@description('Storage account kind.')
param storageKind string

@description('Default access tier for blob data.')
param storageAccessTier string

@description('Minimum TLS protocol supported by the storage account.')
param storageMinimumTlsVersion string

@description('Whether anonymous public access to blob containers is allowed.')
param storageAllowBlobPublicAccess bool

@description('Whether the storage account public endpoint is enabled.')
param storagePublicNetworkAccess string

@description('Require HTTPS for storage requests.')
param storageSupportsHttpsTrafficOnly bool

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: {
    azverifyFunctionalTest: 'true'
  }
  sku: {
    name: storageSkuName
  }
  kind: storageKind
  properties: {
    accessTier: storageAccessTier
    allowBlobPublicAccess: storageAllowBlobPublicAccess
    minimumTlsVersion: storageMinimumTlsVersion
    publicNetworkAccess: storagePublicNetworkAccess
    supportsHttpsTrafficOnly: storageSupportsHttpsTrafficOnly
  }
}

output storageAccountId string = storageAccount.id
