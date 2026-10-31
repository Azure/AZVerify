targetScope = 'resourceGroup'

@description('Azure region for the storage account.')
param location string = resourceGroup().location

@description('Globally unique storage account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Storage redundancy and performance tier.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param storageSkuName string = 'Standard_LRS'

@description('Storage account kind.')
@allowed([
  'StorageV2'
])
param storageKind string = 'StorageV2'

@description('Default access tier for blob data.')
@allowed([
  'Hot'
  'Cool'
])
param storageAccessTier string = 'Hot'

@description('Minimum TLS protocol supported by the storage account.')
@allowed([
  'TLS1_2'
])
param storageMinimumTlsVersion string = 'TLS1_2'

@description('Whether anonymous public access to blob containers is allowed.')
@allowed([
  false
])
param storageAllowBlobPublicAccess bool = false

@description('Whether the storage account public endpoint is enabled.')
@allowed([
  'Disabled'
])
param storagePublicNetworkAccess string = 'Disabled'

@description('Require HTTPS for storage requests.')
@allowed([
  true
])
param storageSupportsHttpsTrafficOnly bool = true

module data 'modules/data.bicep' = {
  params: {
    location: location
    storageAccountName: storageAccountName
    storageAccessTier: storageAccessTier
    storageAllowBlobPublicAccess: storageAllowBlobPublicAccess
    storageKind: storageKind
    storageMinimumTlsVersion: storageMinimumTlsVersion
    storagePublicNetworkAccess: storagePublicNetworkAccess
    storageSkuName: storageSkuName
    storageSupportsHttpsTrafficOnly: storageSupportsHttpsTrafficOnly
  }
}

output storageAccountId string = data.outputs.storageAccountId
