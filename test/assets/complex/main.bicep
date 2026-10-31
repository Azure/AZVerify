targetScope = 'resourceGroup'

@description('Test location; both authorized resource groups use swedencentral.')
param location string = resourceGroup().location

@description('Stable prefix reserved for the expanded functional-test fixture.')
@allowed(['azvft1', 'azvft2'])
param prefix string

@description('Globally unique suffix derived from the authorized subscription.')
param nameSuffix string

@description('Non-overlapping VNet address space: use 10.91.0.0/16 or 10.92.0.0/16.')
param addressPrefix string

@description('Three non-overlapping subnet prefixes inside the VNet.')
param subnetPrefixes string[]

@description('Include empty monitoring resources; they receive no test data.')
param includeMonitoring bool = false

module networking 'modules/networking.bicep' = {
  params: {
    location: location
    prefix: prefix
    addressPrefix: addressPrefix
    subnetPrefixes: subnetPrefixes
  }
}

module data 'modules/data.bicep' = {
  params: {
    location: location
    prefix: prefix
    nameSuffix: nameSuffix
  }
}

module monitoring 'modules/monitoring.bicep' = if (includeMonitoring) {
  params: {
    location: location
    prefix: prefix
  }
}

output vnetId string = networking.outputs.vnetId
output storageName string = data.outputs.storageName
