param location string = 'westeurope'
param seed string = 'azverify-module-names'

module names './relay.bicep' = {
  name: 'names'
  params: {
    seed: seed
  }
}

module consumer './consumer.bicep' = {
  name: 'consumer'
  params: {
    location: location
    accountName: names.outputs.accountName
    generatedGuid: names.outputs.generatedGuid
  }
}
