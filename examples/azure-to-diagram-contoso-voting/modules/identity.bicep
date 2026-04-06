@description('Azure region for all resources.')
param location string

@description('Name of the user-assigned managed identity.')
param managedIdentityName string

@description('Name of the App Service the identity has Website Contributor role on.')
param appServiceName string

@description('Resource tags.')
param tags object = {}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Role Assignment: Website Contributor on the App Service
// The deploy-uami identity has the Website Contributor role on the contoso-voting App Service.
// This role assignment is recreated here scoped to the App Service resource.
resource appService 'Microsoft.Web/sites@2024-04-01' existing = {
  name: appServiceName
}

resource websiteContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, appService.id, 'de139f84-1756-47ae-9be6-808fbbe84772')
  scope: appService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'de139f84-1756-47ae-9be6-808fbbe84772')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output managedIdentityId string = managedIdentity.id
output principalId string = managedIdentity.properties.principalId
output clientId string = managedIdentity.properties.clientId
