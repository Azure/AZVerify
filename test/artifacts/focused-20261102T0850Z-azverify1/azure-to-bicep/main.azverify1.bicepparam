using 'main.bicep'

// Azure region currently used by AzVerify1. Other regions may change availability and cost.
param location = 'swedencentral'

// Resource names below preserve the existing fixture. Resource names do not affect capacity or cost.
param baselineStorageAccountName = 'azvtest9bd9cf0b'
param storageAccountName = 'azvft19bd9cf0b'
param keyVaultName = 'azvft1-kv-9bd9cf0b'
param identityName = 'azvft1-identity'
param networkSecurityGroupName = 'azvft1-nsg'
param virtualNetworkName = 'azvft1-vnet'
param routeTableName = 'azvft1-routes'
param summaryRouteTableName1 = 'azvft1-summary-routes-1'
param summaryRouteTableName2 = 'azvft1-summary-routes-2'
param networkInterfaceName0 = 'azvft1-nic-0'
param networkInterfaceName1 = 'azvft1-nic-1'
param logAnalyticsWorkspaceName = 'azvft1-logs'
param applicationInsightsName = 'azvft1-insights'
param actionGroupName = 'azvft1-actions'
