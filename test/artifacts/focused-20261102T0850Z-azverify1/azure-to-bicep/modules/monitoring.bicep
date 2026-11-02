targetScope = 'resourceGroup'

@description('Azure region for the monitoring resources.')
param location string
@description('Log Analytics workspace name.')
param logAnalyticsWorkspaceName string
@description('Application Insights component name.')
param applicationInsightsName string
@description('Action group name.')
param actionGroupName string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2026-03-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
    features: {
      legacy: 0
      searchVersion: 1
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
  properties: {
    Application_Type: 'web'
    IngestionMode: 'LogAnalytics'
    RetentionInDays: 90
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
  properties: {
    groupShortName: 'azvft1'
    enabled: false
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    armRoleReceivers: []
    azureAppPushReceivers: []
    voiceReceivers: []
    azureFunctionReceivers: []
    logicAppReceivers: []
    automationRunbookReceivers: []
  }
}

output logAnalyticsWorkspaceId string = logAnalytics.id
output applicationInsightsId string = applicationInsights.id
output actionGroupId string = actionGroup.id
