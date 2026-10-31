using none

param accountName = 'st${uniqueString('azverify-module-names')}'
param generatedGuid = guid(uniqueString('azverify-module-names'))
param consumerGuid = guid('st${uniqueString('azverify-module-names')}')
