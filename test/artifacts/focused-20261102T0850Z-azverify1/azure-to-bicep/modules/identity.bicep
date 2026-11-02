targetScope = 'resourceGroup'

@description('Azure region for the identity.')
param location string
@description('User-assigned identity name.')
param identityName string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: identityName
  location: location
  tags: {
    azverifyFunctionalTest: 'expanded-v1'
  }
}

output identityId string = identity.id
