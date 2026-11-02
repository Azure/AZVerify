targetScope = 'resourceGroup'

@description('VNet in AzVerify1 that owns the local peering.')
param localVnetName string
@description('Resource group containing the remote VNet.')
param remoteResourceGroupName string
@description('Remote VNet name.')
param remoteVnetName string
@description('Peering name used by the existing fixture.')
param peeringName string

resource localVnet 'Microsoft.Network/virtualNetworks@2026-01-01' existing = {
  name: localVnetName
}

resource remoteVnet 'Microsoft.Network/virtualNetworks@2026-01-01' existing = {
  scope: resourceGroup(remoteResourceGroupName)
  name: remoteVnetName
}

resource localPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-01-01' = {
  parent: localVnet
  name: peeringName
  properties: {
    remoteVirtualNetwork: {
      id: remoteVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

output peeringId string = localPeering.id
