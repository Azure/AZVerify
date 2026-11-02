targetScope = 'resourceGroup'

@description('Azure region for the networking resources.')
param location string
@description('Network security group name.')
param networkSecurityGroupName string
@description('Virtual network name.')
param virtualNetworkName string
@description('Route table attached to the VNet subnets.')
param routeTableName string
@description('Name of the first unattached route table.')
param summaryRouteTableName1 string
@description('Name of the second unattached route table.')
param summaryRouteTableName2 string
@description('First network interface name.')
param networkInterfaceName0 string
@description('Second network interface name.')
param networkInterfaceName1 string

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2026-01-01' = {
  name: networkSecurityGroupName
  location: location
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
  properties: {
    securityRules: []
  }
}

resource routeTable 'Microsoft.Network/routeTables@2026-01-01' = {
  name: routeTableName
  location: location
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
  properties: {
    disableBgpRoutePropagation: false
    routes: []
  }
}

resource summaryRouteTable1 'Microsoft.Network/routeTables@2026-01-01' = {
  name: summaryRouteTableName1
  location: location
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
    azverifyRun: 'run-20261101-02'
  }
  properties: {
    disableBgpRoutePropagation: false
    routes: []
  }
}

resource summaryRouteTable2 'Microsoft.Network/routeTables@2026-01-01' = {
  name: summaryRouteTableName2
  location: location
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
    azverifyRun: 'run-20261101-02'
  }
  properties: {
    disableBgpRoutePropagation: false
    routes: []
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2026-01-01' = {
  name: virtualNetworkName
  location: location
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.91.0.0/16'
      ]
    }
    enableDdosProtection: false
  }
}

resource applicationSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-01-01' = {
  parent: virtualNetwork
  name: 'application'
  properties: {
    addressPrefix: '10.91.2.0/24'
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    routeTable: {
      id: routeTable.id
    }
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource ingressSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-01-01' = {
  parent: virtualNetwork
  name: 'ingress'
  properties: {
    addressPrefix: '10.91.1.0/24'
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    routeTable: {
      id: routeTable.id
    }
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource dataSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-01-01' = {
  parent: virtualNetwork
  name: 'data'
  properties: {
    addressPrefix: '10.91.3.0/24'
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    routeTable: {
      id: routeTable.id
    }
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource networkInterface0 'Microsoft.Network/networkInterfaces@2026-01-01' = {
  name: networkInterfaceName0
  location: location
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
  properties: {
    enableAcceleratedNetworking: false
    enableIPForwarding: false
    dnsSettings: {
      dnsServers: []
    }
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    ipConfigurations: [
      {
        name: 'primary'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          primary: true
          subnet: {
            id: applicationSubnet.id
          }
        }
      }
    ]
  }
}

resource networkInterface1 'Microsoft.Network/networkInterfaces@2026-01-01' = {
  name: networkInterfaceName1
  location: location
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
  properties: {
    enableAcceleratedNetworking: false
    enableIPForwarding: false
    dnsSettings: {
      dnsServers: []
    }
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    ipConfigurations: [
      {
        name: 'primary'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          primary: true
          subnet: {
            id: applicationSubnet.id
          }
        }
      }
    ]
  }
}

output virtualNetworkId string = virtualNetwork.id
output networkSecurityGroupId string = networkSecurityGroup.id
output applicationSubnetId string = applicationSubnet.id
