# Azure Resource Configuration Reference

Per-resource-type property retrieval mapping and auto-detection rules used by AzVerify skills for drift detection and Bicep generation.

For per-resource defaults (SKUs, sizes, settings), derive from Bicep MCP `get_az_resource_type_schema`, Azure Verified Modules, or Microsoft documentation. Do not hardcode defaults — verify at generation time.

---

## Azure Property Retrieval Mapping

This section documents how to retrieve each tracked property from Azure for drift detection. For each resource type:
- **MCP Tool**: The primary Azure MCP tool to query (if available)
- **Fallback**: `az resource show --ids <resourceId> -o json` for types without a dedicated MCP tool
- **Field Paths**: JSON paths in the ARM response that map to each tracked property name

### SKU Extraction Rules (Global)

For all resource types with `skuName` / `skuTier` properties, extract from the top-level `sku` object:
- `sku.name` → `skuName`
- `sku.tier` → `skuTier`

### Composite Property Rules

| Resource Type | Property | Assembled From |
|---------------|----------|----------------|
| `Microsoft.Compute/virtualMachines` | `osImage` | `properties.storageProfile.imageReference.publisher` + `:` + `properties.storageProfile.imageReference.offer` + `:` + `properties.storageProfile.imageReference.sku` + `:` + `properties.storageProfile.imageReference.version` |

### Microsoft.Compute/virtualMachines

**MCP Tool**: `mcp_azure_compute`
**Fallback**: `az vm show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| vmSize | `properties.hardwareProfile.vmSize` | |
| osType | `properties.storageProfile.osDisk.osType` | |
| osImage | *(composite — see above)* | |
| osDiskType | `properties.storageProfile.osDisk.managedDisk.storageAccountType` | |
| osDiskSizeGB | `properties.storageProfile.osDisk.diskSizeGB` | |
| dataDisks | `properties.storageProfile.dataDisks` | Array |
| adminUsername | `properties.osProfile.adminUsername` | |
| authenticationType | `properties.osProfile.linuxConfiguration.disablePasswordAuthentication` | `true` → `sshPublicKey`, `false` → `password` |
| enableBootDiagnostics | `properties.diagnosticsProfile.bootDiagnostics.enabled` | |
| availabilityZone | `zones[0]` | Top-level `zones` array |
| enableAcceleratedNetworking | *(from NIC resource)* | Query linked NIC via `properties.networkProfile.networkInterfaces[0].id` |

### Microsoft.Compute/virtualMachineScaleSets

**MCP Tool**: `mcp_azure_compute`
**Fallback**: `az vmss show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| vmSize | `sku.name` | In `sku` not `properties` |
| capacity | `sku.capacity` | |
| osImage | *(composite from `properties.virtualMachineProfile.storageProfile.imageReference`)* | |
| upgradePolicy | `properties.upgradePolicy.mode` | |

### Microsoft.Web/serverfarms

**MCP Tool**: `mcp_azure_appservice`
**Fallback**: `az appservice plan show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `sku.name` | |
| skuTier | `sku.tier` | |
| kind | `kind` | Top-level field |
| reserved | `properties.reserved` | |
| capacity | `sku.capacity` | |

### Microsoft.Web/sites

**MCP Tool**: `mcp_azure_appservice`
**Fallback**: `az webapp show --ids <resourceId> -o json` + `az webapp config show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| runtimeStack | `properties.siteConfig.linuxFxVersion` or `properties.siteConfig.windowsFxVersion` | Format: `RUNTIME\|VERSION` |
| httpsOnly | `properties.httpsOnly` | |
| minTlsVersion | `properties.siteConfig.minTlsVersion` | Requires config sub-call |
| alwaysOn | `properties.siteConfig.alwaysOn` | Requires config sub-call |
| http20Enabled | `properties.siteConfig.http20Enabled` | Requires config sub-call |
| ftpsState | `properties.siteConfig.ftpsState` | Requires config sub-call |
| publicNetworkAccess | `properties.publicNetworkAccess` | |
| vnetIntegrationSubnet | `properties.virtualNetworkSubnetId` | |

### Microsoft.Web/sites/functions

**MCP Tool**: `mcp_azure_appservice`
**Fallback**: `az functionapp show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| runtimeStack | `properties.siteConfig.linuxFxVersion` | |
| hostingPlan | *(derived from linked serverfarm SKU)* | |
| httpsOnly | `properties.httpsOnly` | |
| minTlsVersion | `properties.siteConfig.minTlsVersion` | |

### Microsoft.Storage/storageAccounts

**MCP Tool**: `mcp_azure_storage`
**Fallback**: `az storage account show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `sku.name` | |
| kind | `kind` | Top-level field |
| accessTier | `properties.accessTier` | |
| minimumTlsVersion | `properties.minimumTlsVersion` | |
| supportsHttpsTrafficOnly | `properties.supportsHttpsTrafficOnly` | |
| allowBlobPublicAccess | `properties.allowBlobPublicAccess` | |
| publicNetworkAccess | `properties.publicNetworkAccess` | |
| enableHierarchicalNamespace | `properties.isHnsEnabled` | |

### Microsoft.Sql/servers

**MCP Tool**: `mcp_azure_sql`
**Fallback**: `az sql server show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| administratorLogin | `properties.administratorLogin` | |
| minimalTlsVersion | `properties.minimalTlsVersion` | |
| publicNetworkAccess | `properties.publicNetworkAccess` | |

### Microsoft.Sql/servers/databases

**MCP Tool**: `mcp_azure_sql`
**Fallback**: `az sql db show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `sku.name` | |
| skuTier | `sku.tier` | |
| maxSizeBytes | `properties.maxSizeBytes` | |
| zoneRedundant | `properties.zoneRedundant` | |
| readScale | `properties.readScale` | |
| backupRedundancy | `properties.requestedBackupStorageRedundancy` | |

### Microsoft.DocumentDB/databaseAccounts

**MCP Tool**: `mcp_azure_cosmos`
**Fallback**: `az cosmosdb show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| kind | `kind` | Top-level field |
| consistencyLevel | `properties.consistencyPolicy.defaultConsistencyLevel` | |
| capacityMode | `properties.capacityMode` | |
| enableFreeTier | `properties.enableFreeTier` | |
| enableAutomaticFailover | `properties.enableAutomaticFailover` | |
| publicNetworkAccess | `properties.publicNetworkAccess` | |
| backupPolicy | `properties.backupPolicy.type` | |

### Microsoft.Cache/redis

**MCP Tool**: `mcp_azure_redis`
**Fallback**: `az redis show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `properties.sku.name` | Nested under `properties.sku` |
| capacity | `properties.sku.capacity` | Nested under `properties.sku` |
| enableNonSslPort | `properties.enableNonSslPort` | |
| minimumTlsVersion | `properties.minimumTlsVersion` | |
| publicNetworkAccess | `properties.publicNetworkAccess` | |

### Microsoft.Network/virtualNetworks

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network vnet show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| addressPrefixes | `properties.addressSpace.addressPrefixes` | Array |
| enableDdosProtection | `properties.enableDdosProtection` | |

### Microsoft.Network/virtualNetworks/subnets

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network vnet subnet show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| addressPrefix | `properties.addressPrefix` | |
| serviceEndpoints | `properties.serviceEndpoints` | Array of objects; compare `service` values |
| delegations | `properties.delegations` | Array of objects; compare `serviceName` values |
| privateEndpointNetworkPolicies | `properties.privateEndpointNetworkPolicies` | |

### Microsoft.Network/networkSecurityGroups

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network nsg show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| securityRules | `properties.securityRules` | Array; compare rule names and key attributes |

### Microsoft.Network/loadBalancers

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network lb show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `sku.name` | |
| type | *(derived)* | Has `properties.frontendIPConfigurations[0].properties.publicIPAddress` → `Public`, else `Internal` |
| frontendPort | `properties.loadBalancingRules[0].properties.frontendPort` | |
| backendPort | `properties.loadBalancingRules[0].properties.backendPort` | |
| protocol | `properties.loadBalancingRules[0].properties.protocol` | |
| enableFloatingIP | `properties.loadBalancingRules[0].properties.enableFloatingIP` | |

### Microsoft.Network/applicationGateways

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network application-gateway show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `properties.sku.name` | Nested under `properties.sku` |
| tier | `properties.sku.tier` | Nested under `properties.sku` |
| capacity | `properties.sku.capacity` | Nested under `properties.sku` |
| enableHttp2 | `properties.enableHttp2` | |
| frontendPort | `properties.frontendPorts[0].properties.port` | |

### Microsoft.Network/publicIPAddresses

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network public-ip show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `sku.name` | |
| allocationMethod | `properties.publicIPAllocationMethod` | |
| availabilityZone | `zones` | Array; `Zone-redundant` if multiple zones listed |

### Microsoft.Network/networkInterfaces

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network nic show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| enableAcceleratedNetworking | `properties.enableAcceleratedNetworking` | |
| enableIPForwarding | `properties.enableIPForwarding` | |
| privateIPAllocationMethod | `properties.ipConfigurations[0].properties.privateIPAllocationMethod` | |

### Microsoft.Network/privateEndpoints

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network private-endpoint show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| groupIds | `properties.privateLinkServiceConnections[0].properties.groupIds` | Array |
| privateDnsZoneGroup | `properties.privateDnsZoneGroups` | `true` if array is non-empty |

### Microsoft.Network/virtualNetworkGateways

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network vnet-gateway show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `properties.sku.name` | Nested under `properties.sku` |
| gatewayType | `properties.gatewayType` | |
| vpnType | `properties.vpnType` | |
| enableBgp | `properties.enableBgp` | |

### Microsoft.Network/azureFirewalls

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network firewall show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuTier | `properties.sku.tier` | Nested under `properties.sku` |
| threatIntelMode | `properties.threatIntelMode` | |

### Microsoft.Network/bastionHosts

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network bastion show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `sku.name` | |

### Microsoft.KeyVault/vaults

**MCP Tool**: `mcp_azure_keyvault`
**Fallback**: `az keyvault show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `properties.sku.name` | Nested under `properties.sku` |
| enableRbacAuthorization | `properties.enableRbacAuthorization` | |
| enableSoftDelete | `properties.enableSoftDelete` | |
| softDeleteRetentionInDays | `properties.softDeleteRetentionInDays` | |
| publicNetworkAccess | `properties.publicNetworkAccess` | |
| enablePurgeProtection | `properties.enablePurgeProtection` | |

### Microsoft.ContainerService/managedClusters

**MCP Tool**: `mcp_azure_aks`
**Fallback**: `az aks show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| kubernetesVersion | `properties.kubernetesVersion` | |
| defaultNodePoolVmSize | `properties.agentPoolProfiles[0].vmSize` | First pool |
| defaultNodePoolCount | `properties.agentPoolProfiles[0].count` | First pool |
| networkPlugin | `properties.networkProfile.networkPlugin` | |
| networkPolicy | `properties.networkProfile.networkPolicy` | |
| enableRBAC | `properties.enableRBAC` | |
| enableManagedIdentity | *(derived)* | `true` if `identity.type` contains `SystemAssigned` or `UserAssigned` |

### Microsoft.App/managedEnvironments

**MCP Tool**: `mcp_azure_containerapps`
**Fallback**: `az containerapp env show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| workloadProfileType | `properties.workloadProfiles[0].workloadProfileType` | |
| zoneRedundant | `properties.zoneRedundant` | |

### Microsoft.App/containerApps

**MCP Tool**: `mcp_azure_containerapps`
**Fallback**: `az containerapp show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| containerImage | `properties.template.containers[0].image` | First container |
| cpuCores | `properties.template.containers[0].resources.cpu` | |
| memoryGi | `properties.template.containers[0].resources.memory` | Strip `Gi` suffix |
| minReplicas | `properties.template.scale.minReplicas` | |
| maxReplicas | `properties.template.scale.maxReplicas` | |
| targetPort | `properties.configuration.ingress.targetPort` | |
| external | `properties.configuration.ingress.external` | |

### Microsoft.ContainerRegistry/registries

**MCP Tool**: `mcp_azure_acr`
**Fallback**: `az acr show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `sku.name` | |
| adminUserEnabled | `properties.adminUserEnabled` | |
| publicNetworkAccess | `properties.publicNetworkAccess` | |

### Microsoft.Insights/components

**MCP Tool**: `mcp_azure_applicationinsights`
**Fallback**: `az monitor app-insights component show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| applicationType | `properties.Application_Type` | |
| retentionInDays | `properties.RetentionInDays` | |
| ingestionMode | `properties.IngestionMode` | |

### Microsoft.OperationalInsights/workspaces

**MCP Tool**: `mcp_azure_monitor`
**Fallback**: `az monitor log-analytics workspace show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `properties.sku.name` | Nested under `properties.sku` |
| retentionInDays | `properties.retentionInDays` | |

### Microsoft.ServiceBus/namespaces

**MCP Tool**: `mcp_azure_servicebus`
**Fallback**: `az servicebus namespace show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `sku.name` | |
| capacity | `sku.capacity` | |
| zoneRedundant | `properties.zoneRedundant` | |

### Microsoft.EventHub/namespaces

**MCP Tool**: `mcp_azure_eventhubs`
**Fallback**: `az eventhubs namespace show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `sku.name` | |
| capacity | `sku.capacity` | |
| isAutoInflateEnabled | `properties.isAutoInflateEnabled` | |

### Microsoft.ApiManagement/service

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az apim show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| skuName | `sku.name` | |
| capacity | `sku.capacity` | |
| publisherEmail | `properties.publisherEmail` | |
| publisherName | `properties.publisherName` | |

### Microsoft.Network/privateDnsZones

**MCP Tool**: *(none — use fallback)*
**Fallback**: `az network private-dns zone show --ids <resourceId> -o json`

| Property | ARM JSON Path | Notes |
|----------|---------------|-------|
| zoneName | `name` | Top-level `name` field |

## Auto-Detection Rules

The following settings are automatically adjusted based on diagram topology:

| Condition | Auto-Setting |
|-----------|-------------|
| Resource has a Private Endpoint connection | Set `publicNetworkAccess: "Disabled"` on the target resource |
| App Service connected to a Subnet | Set `vnetIntegrationSubnet` to the subnet reference |
| Private Endpoint connected to SQL Server | Set `groupIds: ["sqlServer"]` |
| Private Endpoint connected to Storage Account | Set `groupIds: ["blob"]` |
| Private Endpoint connected to App Service | Set `groupIds: ["sites"]` |
| Private Endpoint connected to Key Vault | Set `groupIds: ["vault"]` |
| Private Endpoint connected to Cosmos DB | Set `groupIds: ["Sql"]` |
| Private Endpoint exists in a subnet | Set `privateEndpointNetworkPolicies: "Disabled"` on that subnet |
| VM exists without NIC in diagram | Auto-add NIC resource |
| App Service exists without App Service Plan | Auto-add App Service Plan |
| Subnet index N | Set `addressPrefix: "10.0.N.0/24"` (auto-increment) |
