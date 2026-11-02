targetScope = 'resourceGroup'

@description('Azure region for the resources in the current AzVerify1 configuration.')
param location string = 'swedencentral'

@description('Name of the baseline storage account.')
param baselineStorageAccountName string = 'azvtest9bd9cf0b'
@description('Name of the expanded storage account.')
param storageAccountName string = 'azvft19bd9cf0b'
@description('Name of the Key Vault.')
param keyVaultName string = 'azvft1-kv-9bd9cf0b'
@description('Name of the user-assigned managed identity.')
param identityName string = 'azvft1-identity'
@description('Name of the network security group.')
param networkSecurityGroupName string = 'azvft1-nsg'
@description('Name of the virtual network.')
param virtualNetworkName string = 'azvft1-vnet'
@description('Name of the route table attached to all three subnets.')
param routeTableName string = 'azvft1-routes'
@description('Name of the first unattached test route table.')
param summaryRouteTableName1 string = 'azvft1-summary-routes-1'
@description('Name of the second unattached test route table.')
param summaryRouteTableName2 string = 'azvft1-summary-routes-2'
@description('Name of the first network interface.')
param networkInterfaceName0 string = 'azvft1-nic-0'
@description('Name of the second network interface.')
param networkInterfaceName1 string = 'azvft1-nic-1'
@description('Name of the Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'azvft1-logs'
@description('Name of the Application Insights component.')
param applicationInsightsName string = 'azvft1-insights'
@description('Name of the action group.')
param actionGroupName string = 'azvft1-actions'

module identity 'modules/identity.bicep' = {
  params: {
    location: location
    identityName: identityName
  }
}

module networking 'modules/networking.bicep' = {
  params: {
    location: location
    networkSecurityGroupName: networkSecurityGroupName
    virtualNetworkName: virtualNetworkName
    routeTableName: routeTableName
    summaryRouteTableName1: summaryRouteTableName1
    summaryRouteTableName2: summaryRouteTableName2
    networkInterfaceName0: networkInterfaceName0
    networkInterfaceName1: networkInterfaceName1
  }
}

module data 'modules/data.bicep' = {
  params: {
    location: location
    baselineStorageAccountName: baselineStorageAccountName
    storageAccountName: storageAccountName
    keyVaultName: keyVaultName
    identityId: identity.outputs.identityId
  }
}

module monitoring 'modules/monitoring.bicep' = {
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    applicationInsightsName: applicationInsightsName
    actionGroupName: actionGroupName
  }
}

output virtualNetworkId string = networking.outputs.virtualNetworkId
output identityId string = identity.outputs.identityId
output baselineStorageAccountId string = data.outputs.baselineStorageAccountId
output storageAccountId string = data.outputs.storageAccountId
output keyVaultId string = data.outputs.keyVaultId
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
output applicationInsightsId string = monitoring.outputs.applicationInsightsId
output actionGroupId string = monitoring.outputs.actionGroupId
