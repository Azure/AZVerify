@description('Azure location.')
param location string

@description('Reserved test resource prefix.')
param prefix string

@description('VNet CIDR range.')
param addressPrefix string

@description('Three subnet CIDR ranges for ingress, application and data tiers.')
@minLength(3)
@maxLength(3)
param subnetPrefixes string[]

var tags = { azverifyFunctionalTest: 'expanded-v1' }
var subnetNames = ['ingress', 'application', 'data']

resource nsg 'Microsoft.Network/networkSecurityGroups@2025-01-01' = {
  name: '${prefix}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource routes 'Microsoft.Network/routeTables@2025-01-01' = {
  name: '${prefix}-routes'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2025-01-01' = {
  name: '${prefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressPrefix] }
  }
}

@batchSize(1)
resource subnets 'Microsoft.Network/virtualNetworks/subnets@2025-01-01' = [for (subnetName, index) in subnetNames: {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetPrefixes[index]
    networkSecurityGroup: { id: nsg.id }
    routeTable: { id: routes.id }
  }
}]

@batchSize(1)
resource interfaces 'Microsoft.Network/networkInterfaces@2025-01-01' = [for index in range(0, 2): {
  name: '${prefix}-nic-${index}'
  location: location
  tags: tags
  dependsOn: [
    subnets
  ]
  properties: {
    networkSecurityGroup: { id: nsg.id }
    ipConfigurations: [{
      name: 'primary'
      properties: {
        privateIPAllocationMethod: 'Dynamic'
        subnet: { id: subnets[1].id }
      }
    }]
  }
}]

output vnetId string = vnet.id
