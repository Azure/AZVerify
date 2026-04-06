targetScope = 'resourceGroup'

// === Common Parameters ===

@description('Azure region for all resources')
param location string = 'eastus'

// === Networking Parameters ===

@description('Name of the virtual network')
param vnetName string = 'vnet-secure'

@description('Address prefixes for the VNet')
param vnetAddressPrefixes string[] = ['10.0.0.0/16']

@description('Name of the Application Gateway subnet')
param snetAppGwName string = 'snet-appgw'

@description('Address prefix for the Application Gateway subnet')
param snetAppGwAddressPrefix string = '10.0.0.0/24'

@description('Name of the VNet integration subnet')
param snetIntegrationName string = 'snet-integration'

@description('Address prefix for the VNet integration subnet')
param snetIntegrationAddressPrefix string = '10.0.1.0/26'

@description('Name of the private link subnet')
param snetPrivateLinkName string = 'snet-privatelink'

@description('Address prefix for the private link subnet')
param snetPrivateLinkAddressPrefix string = '10.0.2.0/24'

@description('Name of the public IP address for Application Gateway')
param publicIpName string = 'pip-appgw'

@description('Domain name for the public DNS zone')
param dnsZoneName string = 'secure-webapp.example.com'

@description('Name of the Application Gateway')
param appGwName string = 'appgw-waf'

@description('SKU tier of the Application Gateway')
@allowed([
  'Standard_v2'
  'WAF_v2'
])
param appGwSkuTier string = 'WAF_v2'

@description('Capacity (instance count) of the Application Gateway')
@minValue(1)
@maxValue(125)
param appGwCapacity int = 2

@description('Name of the WAF policy')
param wafPolicyName string = 'waf-policy-appgw'

@description('WAF mode — Detection logs threats, Prevention blocks them')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Prevention'

// === Compute Parameters ===

@description('Name of the App Service Plan')
param appServicePlanName string = 'asp-webapp'

@description('SKU name for the App Service Plan')
param appServicePlanSkuName string = 'S1'

@description('Name of the App Service — must be globally unique')
param appServiceName string = 'app-webapp'

@description('Runtime stack for the App Service')
param appServiceRuntimeStack string = 'DOTNET|8.0'

// === Data Parameters ===

@description('Name of the SQL Server — must be globally unique')
param sqlServerName string = 'sql-secure'

@description('SQL Server administrator login')
param sqlAdminLogin string = 'sqladmin'

@secure()
@description('SQL Server administrator password')
param sqlAdminPassword string

@description('Name of the SQL Database')
param sqlDatabaseName string = 'sqldb-webapp'

@description('SKU name for the SQL Database')
param sqlDatabaseSkuName string = 'Basic'

@description('Name of the Key Vault — must be globally unique (3-24 chars)')
param keyVaultName string = 'kv-secure'

@description('Name of the private endpoint for SQL Server')
param privateEndpointName string = 'pe-sql'

// === Monitoring Parameters ===

@description('Name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string = 'log-secure-webapp'

@description('Name of Application Insights')
param appInsightsName string = 'appi-webapp'

// === Modules ===

module networking 'modules/networking.bicep' = {
  params: {
    location: location
    vnetName: vnetName
    vnetAddressPrefixes: vnetAddressPrefixes
    snetAppGwName: snetAppGwName
    snetAppGwAddressPrefix: snetAppGwAddressPrefix
    snetIntegrationName: snetIntegrationName
    snetIntegrationAddressPrefix: snetIntegrationAddressPrefix
    snetPrivateLinkName: snetPrivateLinkName
    snetPrivateLinkAddressPrefix: snetPrivateLinkAddressPrefix
    publicIpName: publicIpName
    dnsZoneName: dnsZoneName
    appGwName: appGwName
    appGwSkuTier: appGwSkuTier
    appGwCapacity: appGwCapacity
    wafPolicyName: wafPolicyName
    wafMode: wafMode
    appServiceFqdn: '${appServiceName}.azurewebsites.net'
  }
}

module monitoring 'modules/monitoring.bicep' = {
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    appInsightsName: appInsightsName
  }
}

module compute 'modules/compute.bicep' = {
  params: {
    location: location
    appServicePlanName: appServicePlanName
    appServicePlanSkuName: appServicePlanSkuName
    appServiceName: appServiceName
    appServiceRuntimeStack: appServiceRuntimeStack
    snetIntegrationId: networking.outputs.snetIntegrationId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

module data 'modules/data.bicep' = {
  params: {
    location: location
    sqlServerName: sqlServerName
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    sqlDatabaseName: sqlDatabaseName
    sqlDatabaseSkuName: sqlDatabaseSkuName
    keyVaultName: keyVaultName
    snetPrivateLinkId: networking.outputs.snetPrivateLinkId
    vnetId: networking.outputs.vnetId
    privateEndpointName: privateEndpointName
  }
}

// === Outputs ===

@description('App Service default hostname')
output appServiceHostname string = compute.outputs.appServiceDefaultHostname

@description('SQL Server FQDN')
output sqlServerFqdn string = data.outputs.sqlServerFqdn

@description('Key Vault URI')
output keyVaultUri string = data.outputs.keyVaultUri

@description('Application Insights connection string')
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
