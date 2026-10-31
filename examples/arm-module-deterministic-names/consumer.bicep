param location string
param accountName string
param generatedGuid string

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: accountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {}
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: guid(accountName)
  location: location
  tags: {
    moduleGuid: generatedGuid
    moduleName: accountName
  }
}
