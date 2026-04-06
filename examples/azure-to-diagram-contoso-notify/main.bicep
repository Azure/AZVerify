targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = 'swedencentral'

@description('Resource tags applied to all resources.')
param tags object = {}

@description('Resource ID of the Log Analytics workspace used by Application Insights. Lives in DefaultResourceGroup-SEC.')
param logAnalyticsWorkspaceId string

@description('Notification email address where the function app sends task completion emails.')
param notificationEmail string = 'example@example.com'

@description('Azure AI Foundry endpoint URL for OpenAI Responses API.')
param azureAIFoundryEndpoint string = 'https://<AI_ENDPOINT>/openai/responses?api-version=2025-04-01-preview'

@description('OpenAI model deployment name.')
param openAIModel string = 'gpt-5-mini'

@description('Enable Contoso-Notify premium features. Accepts "true" or "false".')
param usePremiumFeatures string = 'true'

@description('Sender email address. Update after custom domain verification — see dependencies/README.md.')
param senderEmail string = 'donotreply@<AZURE_MANAGED_DOMAIN>.azurecomm.net'

module identity 'modules/identity.bicep' = {
  params: {
    location: location
    tags: tags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  params: {
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

module data 'modules/data.bicep' = {
  params: {
    location: location
    tags: tags
  }
}

module communication 'modules/communication.bicep' = {
  params: {
    tags: tags
  }
}

module compute 'modules/compute.bicep' = {
  params: {
    location: location
    tags: tags
    uamiId: identity.outputs.uamiId
    uamiClientId: identity.outputs.uamiClientId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    storageAccountBlobEndpoint: data.outputs.storageAccountBlobEndpoint
    storageAccountQueueEndpoint: data.outputs.storageAccountQueueEndpoint
    storageAccountTableEndpoint: data.outputs.storageAccountTableEndpoint
    keyVaultName: data.outputs.keyVaultName
    notificationEmail: notificationEmail
    azureAIFoundryEndpoint: azureAIFoundryEndpoint
    openAIModel: openAIModel
    usePremiumFeatures: usePremiumFeatures
    senderEmail: senderEmail
  }
}

output functionAppHostname string = compute.outputs.functionAppHostname
output keyVaultUri string = data.outputs.keyVaultUri
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
output storageAccountBlobEndpoint string = data.outputs.storageAccountBlobEndpoint
