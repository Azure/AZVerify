@description('Azure region for all resources.')
param location string

@description('Name of the virtual network.')
param vnetName string

@description('Address prefixes for the virtual network.')
param vnetAddressPrefixes string[]

@description('Name of the first subnet (VM workload).')
param subnet01Name string

@description('Address prefix for the first subnet.')
param subnet01AddressPrefix string

@description('Name of the second subnet (private endpoints).')
param subnet02Name string

@description('Address prefix for the second subnet.')
param subnet02AddressPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: vnetAddressPrefixes
    }
  }
}

resource subnet01 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: subnet01Name
  properties: {
    addressPrefix: subnet01AddressPrefix
  }
}

resource subnet02 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: subnet02Name
  properties: {
    addressPrefix: subnet02AddressPrefix
  }
  dependsOn: [
    subnet01
  ]
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output subnet01Id string = subnet01.id
output subnet02Id string = subnet02.id
