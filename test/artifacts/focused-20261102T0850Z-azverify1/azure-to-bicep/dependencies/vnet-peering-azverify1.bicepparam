using 'vnet-peering-azverify1.bicep'

// Existing local VNet and external dependency in the dedicated test subscription.
param localVnetName = 'azvft1-vnet'
param remoteResourceGroupName = 'AzVerify2'
param remoteVnetName = 'azvft2-vnet'
param peeringName = 'to-other-test-group'
