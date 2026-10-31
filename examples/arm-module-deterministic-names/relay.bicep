param seed string

module generated './generated.bicep' = {
  name: 'generated'
  params: {
    seed: seed
  }
}

output accountName string = generated.outputs.accountName
output generatedGuid string = generated.outputs.generatedGuid
