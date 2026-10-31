@description('Azure location.')
param location string

@description('Reserved test resource prefix.')
param prefix string

var tags = { azverifyFunctionalTest: 'expanded-v1' }

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: '${prefix}-logs'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${prefix}-insights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource actions 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${prefix}-actions'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: prefix
    enabled: false
  }
}
