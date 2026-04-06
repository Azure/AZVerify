using 'main.bicep'

// Shared suffix for globally unique names.
// Use 3-6 lowercase letters/digits, for example: az1, dev1, b42.
var deploymentSuffix = readEnvironmentVariable('AZV_SUFFIX', '001')

// Azure region for all resources. Options: eastus, westeurope, westus2, northeurope
param location = 'eastus'

// ── Networking ──────────────────────────────────────────────────────

// Virtual network name.
param vnetName = 'VNET-01'

// VNet address space. /16 gives room for many subnets; /24 limits to ~251 hosts total.
param vnetAddressPrefixes = ['10.0.0.0/16']

// Subnet for VM workloads. /24 gives 251 usable IPs.
param subnet01Name = 'Subnet-01'
param subnet01AddressPrefix = '10.0.1.0/24'

// Subnet for private endpoints. /24 gives 251 usable IPs.
param subnet02Name = 'Subnet-02'
param subnet02AddressPrefix = '10.0.2.0/24'

// ── Virtual Machine ─────────────────────────────────────────────────

// NIC name for the VM.
param nicName = 'NIC-01'

// VM name. Also used as computer name (max 15 chars for Windows).
param vmName = 'VM01'

// VM size — controls CPU, memory, cost.
//   Standard_B2s    → 2 vCPU, 4 GB  (~$30/mo) — dev/test, burstable
//   Standard_D2s_v5 → 2 vCPU, 8 GB  (~$70/mo) — general workloads
//   Standard_D4s_v5 → 4 vCPU, 16 GB (~$140/mo) — heavier workloads
param vmSize = 'Standard_B2s'

// VM admin username. Cannot be 'admin' or 'administrator'.
param adminUsername = 'azureuser'

// VM admin password — reads from env var at deploy time. Must meet complexity requirements.
// Set env var VM_ADMIN_PASSWORD before deploying, or deployment will fail validation.
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')

// Windows Server image SKU.
//   2022-datacenter-azure-edition → Windows Server 2022 (LTS, mainstream support until Oct 2026)
//   2025-datacenter-azure-edition → Windows Server 2025 (latest)
param vmImageSku = '2022-datacenter-azure-edition'

// ── App Service ─────────────────────────────────────────────────────

// App Service Plan name.
param appServicePlanName = 'App-Service-Plan'

// App Service Plan SKU — controls features, scale, cost.
//   S1  → 1 core, 1.75 GB  (~$73/mo) — standard features, private endpoint support
//   P1v3 → 2 cores, 8 GB  (~$138/mo) — premium, VNet integration + PE
//   B1  → 1 core, 1.75 GB  (~$13/mo) — basic, limited features (no VNet integration)
param appServicePlanSkuName = 'S1'

// Web App name — must be globally unique (becomes <name>.azurewebsites.net).
param webAppName = 'webapp-rg01-opus46-${deploymentSuffix}'

// ── Private Link ────────────────────────────────────────────────────

// Private endpoint name for the Web App. Public access is disabled; access via PE only.
param privateEndpointName = 'pe-webapp'
