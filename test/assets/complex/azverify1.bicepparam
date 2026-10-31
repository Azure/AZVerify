using 'main.bicep'

param prefix = 'azvft1'
param nameSuffix = readEnvironmentVariable('AZVERIFY_NAME_SUFFIX')
param addressPrefix = '10.91.0.0/16'
param subnetPrefixes = [
  '10.91.1.0/24'
  '10.91.2.0/24'
  '10.91.3.0/24'
]
param includeMonitoring = true
