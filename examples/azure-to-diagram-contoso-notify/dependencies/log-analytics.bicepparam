using 'log-analytics.bicep'

// Deploy to DefaultResourceGroup-SEC — NOT Contoso-Notify.
// az deployment group create \
//   --resource-group DefaultResourceGroup-SEC \
//   --template-file dependencies/log-analytics.bicep \
//   --parameters @dependencies/log-analytics.bicepparam

// Sweden Central — matches the main deployment region.
param location = 'swedencentral'
