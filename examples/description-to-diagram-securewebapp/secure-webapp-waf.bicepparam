using 'main.bicep'

// Shared suffix for globally unique names.
// Use 3-6 lowercase letters/digits, for example: az1, dev1, b42.
var deploymentSuffix = readEnvironmentVariable('AZV_SUFFIX', '001')

// Azure region for all resources. Options: eastus, westeurope, westus2, northeurope
param location = 'eastus'

// === Networking ===

// VNet name
param vnetName = 'vnet-secure'

// VNet address space. /16 gives room for many subnets; /24 limits to ~251 hosts total.
param vnetAddressPrefixes = ['10.0.0.0/16']

// App Gateway subnet — requires dedicated subnet, recommended /24 (251 usable IPs)
param snetAppGwName = 'snet-appgw'
param snetAppGwAddressPrefix = '10.0.0.0/24'

// VNet integration subnet — delegated to Microsoft.Web/serverFarms, minimum /26 (64 IPs)
param snetIntegrationName = 'snet-integration'
param snetIntegrationAddressPrefix = '10.0.1.0/26'

// Private link subnet — hosts private endpoints for backend services
param snetPrivateLinkName = 'snet-privatelink'
param snetPrivateLinkAddressPrefix = '10.0.2.0/24'

// Public IP for Application Gateway — Standard SKU and Static required for v2
param publicIpName = 'pip-appgw'

// Public DNS zone — set to your actual domain. DNS delegation must be configured at registrar.
param dnsZoneName = 'secure-webapp.example.com'

// Application Gateway name
param appGwName = 'appgw-waf'

// Application Gateway SKU — WAF_v2 includes web application firewall.
//   Standard_v2 → no WAF (~$248/mo + data processing)
//   WAF_v2      → built-in WAF with OWASP rules (~$360/mo + data processing)
param appGwSkuTier = 'WAF_v2'

// App Gateway instance count — minimum 2 for high availability
param appGwCapacity = 2

// WAF policy name
param wafPolicyName = 'waf-policy-appgw-opus46'

// WAF mode — Detection logs threats without blocking, Prevention blocks them
param wafMode = 'Prevention'

// === Compute ===

// App Service Plan name
param appServicePlanName = 'asp-webapp'

// App Service Plan SKU — must be S1+ for VNet integration.
//   S1   → 1 vCPU, 1.75 GB  (~$73/mo) — minimum for VNet integration
//   P1v3 → 2 vCPU, 8 GB     (~$138/mo) — better performance
//   P2v3 → 4 vCPU, 16 GB    (~$276/mo) — production workloads
param appServicePlanSkuName = 'S1'

// App Service name — must be globally unique (becomes {name}.azurewebsites.net)
param appServiceName = 'app-webapp-opus46-${deploymentSuffix}'

// Runtime stack for the App Service.
//   DOTNET|8.0  → .NET 8 LTS (supported until Nov 2026)
//   NODE|20-lts → Node.js 20 LTS (supported until Apr 2026)
//   PYTHON|3.12 → Python 3.12 (supported until Oct 2028)
//   JAVA|21     → Java 21 LTS (supported until Sep 2028)
param appServiceRuntimeStack = 'DOTNET|8.0'

// === Data ===

// SQL Server name — must be globally unique
param sqlServerName = 'sql-secure-opus46-${deploymentSuffix}'

// SQL Server admin login
param sqlAdminLogin = 'sqladmin'

// SQL Server admin password — reads from SQLPASSWORD environment variable at deploy time
param sqlAdminPassword = readEnvironmentVariable('SQLPASSWORD', 'ChangeMe@12345')

// SQL Database name
param sqlDatabaseName = 'sqldb-webapp'

// SQL Database SKU — determines compute, storage, and cost.
//   Basic       → 5 DTU    (~$5/mo) — dev/test
//   S0          → 10 DTU   (~$15/mo) — light production
//   S1          → 20 DTU   (~$30/mo) — small production
//   GP_S_Gen5_2 → 2 vCores serverless (~$0.50/hr active) — variable workloads
param sqlDatabaseSkuName = 'Basic'

// Key Vault name — must be globally unique (3-24 chars, alphanumeric + hyphens)
param keyVaultName = 'kv-secure-opus46-${deploymentSuffix}'

// Private endpoint name for SQL Server
param privateEndpointName = 'pe-sql'

// === Monitoring ===

// Log Analytics workspace name — auto-added dependency for Application Insights
param logAnalyticsWorkspaceName = 'log-secure-webapp-opus46'

// Application Insights name
param appInsightsName = 'appi-webapp-opus46'
