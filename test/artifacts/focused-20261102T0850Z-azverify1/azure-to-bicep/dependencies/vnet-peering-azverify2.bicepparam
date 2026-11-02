using 'vnet-peering-azverify2.bicep'

// Reciprocal existing VNet peering in the dedicated test subscription.
param localVnetName = 'azvft2-vnet'
param remoteResourceGroupName = 'AzVerify1'
param remoteVnetName = 'azvft1-vnet'
param peeringName = 'to-other-test-group'
