using 'main.bicep'

param prefix = 'azvft2'
param nameSuffix = readEnvironmentVariable('AZVERIFY_NAME_SUFFIX')
param addressPrefix = '10.92.0.0/16'
param subnetPrefixes = [
  '10.92.1.0/24'
  '10.92.2.0/24'
  '10.92.3.0/24'
]
param includeMonitoring = false
