targetScope = 'resourceGroup'

@description('Local fixture VNet name.')
@allowed(['azvft1-vnet', 'azvft2-vnet'])
param localVnetName string

@description('Existing remote VNet resource ID in the other authorized test group.')
param remoteVnetId string

resource local 'Microsoft.Network/virtualNetworks@2025-01-01' existing = {
  name: localVnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2025-01-01' = {
  parent: local
  name: 'to-other-test-group'
  properties: {
    remoteVirtualNetwork: { id: remoteVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}
