# Azure Resource Metadata Model

Shared internal representation used by AzVerify skills (sketch-to-diagram, diagram-to-bicep, diagram-azure-sync).

## Schema

Each Azure environment is represented as a **resource model** — a JSON structure with the following shape:

```json
{
  "resources": [
    {
      "id": "<unique-identifier>",
      "type": "<Azure-resource-type>",
      "name": "<resource-name>",
      "resourceGroup": "<resource-group-name>",
      "location": "<azure-region>",
      "properties": {},
      "deployableProperties": {},
      "tags": {},
      "sku": {},
      "kind": "",
      "identity": {},
      "relationships": [
        {
          "targetId": "<id-of-related-resource>",
          "type": "<relationship-type>"
        }
      ],
      "secrets": ["<dotted-property-path>"]
    }
  ]
}
```

## Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique identifier within the model. Use a short slug (e.g., `vm-web-01`). |
| `type` | string | Yes | Azure resource provider type (e.g., `Microsoft.Compute/virtualMachines`). |
| `name` | string | Yes | Display name of the resource. |
| `resourceGroup` | string | No | Resource group the resource belongs to. |
| `location` | string | No | Azure region (e.g., `eastus`, `westeurope`). |
| `properties` | object | No | Resource-specific properties (SKU, tier, size, etc.). |
| `deployableProperties` | object | No | Mapped, deployable resource settings. Bicep generation must use this field instead of the raw `properties` bag. |
| `tags` | object | No | Azure resource tags as key-value pairs. |
| `sku` | object | No | Deployable top-level SKU configuration from Azure. |
| `kind` | string | No | Deployable top-level resource kind from Azure. |
| `identity` | object | No | Deployable managed identity configuration; computed IDs are removed when read-only stripping is enabled. |
| `relationships` | array | No | Connections to other resources in the model. |
| `secrets` | array | No | Dotted property paths holding secret values (e.g., `administratorLoginPassword`, `siteConfig.appSettings[APPINSIGHTS_INSTRUMENTATIONKEY]`). Detected values in `properties` are replaced with `***`; each path needs a `@secure()` parameter during generation. |

## Script I/O Conventions

Scripts under `.github/skills/shared/scripts/` use the resource model above as their shared JSON contract.

- Parameters: each script accepts `-InputFile` and `-OutFile` when it reads/writes JSON, and uses `-Mode`, `-ResourceGroup`, or equivalent flags for its algorithm-specific behavior.
- Standard output: scripts emit one JSON object to stdout (for example, `{"resources": [...]}`) and do not print extra prose on stdout.
- Standard error: diagnostics, warnings, and hard-gate messages go to stderr via `Write-Diag` so the JSON stream stays machine-readable.
- Exit codes: `0` means success; non-zero means failure or a hard gate (for example, unauthenticated Azure session or missing prerequisite).
- Default behavior: if `-OutFile` is omitted, scripts write JSON to stdout; if `-InputFile` is omitted, they read from stdin.

This contract keeps the script pipeline deterministic and chainable across the skills.


## Script I/O Conventions

Scripts under `.github/skills/shared/scripts/` use the resource model above as their shared JSON contract.

- Parameters: each script accepts `-InputFile` and `-OutFile` when it reads/writes JSON, and uses `-Mode`, `-ResourceGroup`, or equivalent flags for its algorithm-specific behavior.
- Standard output: scripts emit one JSON object to stdout (for example, `{"resources": [...]}`) and do not print extra prose on stdout.
- Standard error: diagnostics, warnings, and hard-gate messages go to stderr via `Write-Diag` so the JSON stream stays machine-readable.
- Exit codes: `0` means success; non-zero means failure or a hard gate (for example, unauthenticated Azure session or missing prerequisite).
- Default behavior: if `-OutFile` is omitted, scripts write JSON to stdout; if `-InputFile` is omitted, they read from stdin.

This contract keeps the script pipeline deterministic and chainable across the skills.

## Relationship Types

| Type | Description | Example |
|------|-------------|---------|
| `contains` | Parent contains child resource | VNet contains Subnet |
| `connects` | Network or data flow connection | VM connects to Storage Account |
| `depends` | Deployment dependency | App Service depends on App Service Plan |
| `peers` | Bidirectional peering | VNet peers with VNet |
| `secures` | Security association | NSG secures Subnet |
| `routes` | Traffic routing | Load Balancer routes to VM |

## Manual Relationship Inference — Script Unavailable Fallback

`Get-AzureResourceModel.ps1` populates each resource's `relationships` array automatically. If the script cannot run and the model was assembled by hand (MCP fallback), detect in-scope relationships using the patterns below.

| Pattern | Detection Method | Relationship Type | Bicep Implication |
|---------|-----------------|-------------------|-------------------|
| **Subnet membership** | NIC's `ipConfigurations[].subnet.id` references a VNet/subnet in scope | `connects` | Subnet declared inside VNet module; NIC references subnet via symbolic ref |
| **Private endpoint links** | PE's `privateLinkServiceConnections[].privateLinkServiceId` references a resource in scope | `depends` | PE in networking module with `dependsOn` on target resource |
| **App Service Plan binding** | Web App's `serverFarmId` references an ASP in scope | `depends` | ASP and Web App in same module; Web App depends on ASP |
| **NIC-to-VM binding** | VM's `networkProfile.networkInterfaces` references a NIC in scope | `connects` | NIC deployed before VM; VM references NIC via symbolic ref |
| **Diagnostic settings** | Resource's diagnostic settings target a Log Analytics workspace in scope | `depends` | Diagnostic setting as child resource with `parent:` |
| **Key Vault references** | App settings contain `@Microsoft.KeyVault(SecretUri=...)` referencing a vault in scope | `depends` | Output Key Vault URI; Web App depends on Key Vault |
| **App Insights connection** | App settings contain `APPLICATIONINSIGHTS_CONNECTION_STRING` matching an AI resource in scope | `depends` | Web App depends on Application Insights; connection string as output |
| **NSG-to-subnet binding** | Subnet's `networkSecurityGroup.id` references an NSG in scope | `secures` | NSG deployed before subnet; subnet references NSG |
| **User-assigned identity** | Resource's `identity.userAssignedIdentities` references an identity in scope | `depends` | Identity deployed first; resource references identity |

Treat any null or missing intermediate node in a detection path as "relationship not present" — do not flag it as an extraction error.

## External Dependency Detection

External dependencies are resources that in-scope resources depend on but that live in another resource group, subscription, or tenant. They cannot be deployed by generated Bicep for the current scope and need separate coordination.

Detect them by resolving resource ID references in the extracted properties and checking whether the target falls outside the discovery scope.

| Pattern | Detection Method | Dependency Type |
|---------|-----------------|-----------------|
| **VNet peering to external VNet** | VNet's `virtualNetworkPeerings[].remoteVirtualNetwork.id` points outside scope | `vnet-peering` — both sides must be configured |
| **Private DNS zone in another RG** | Private endpoint's `privateDnsZoneGroups[].privateDnsZones[].id` points outside scope | `private-dns-zone` — A record must be created in the external zone |
| **Log Analytics workspace in shared RG** | Diagnostic settings target a workspace outside scope | `log-analytics` — workspace must exist; may need access policy |
| **Key Vault in another RG** | App settings reference a Key Vault outside scope | `key-vault-access` — access policy or RBAC role needed on external vault |
| **Subnet in external VNet** | NIC or PE references a subnet in a VNet outside scope | `external-subnet` — subnet must exist with sufficient address space |
| **Container registry in another RG** | Container App or AKS references an ACR outside scope | `container-registry` — AcrPull role needed for the identity |
| **DNS zone in another subscription** | Custom domain configuration references external DNS | `dns-zone` — CNAME/A record must be created |
| **RBAC on external resources** | Managed identity needs roles on resources outside scope | `rbac-assignment` — role assignment on external resource |
| **Hub VNet route tables** | UDR references a firewall or NVA outside scope | `route-table` — routes in hub must point to correct next-hop |

Treat any null or missing intermediate node in a detection path as "dependency not present" — do not flag it as an extraction error.

Record each detected external dependency as:

| Field | Description |
|-------|-------------|
| `type` | Dependency category from the table above |
| `resourceId` | Full ARM resource ID of the external resource |
| `resourceType` | Azure resource type |
| `resourceName` | Display name |
| `dependedOnBy` | List of in-scope resource names that depend on this |
| `requiredAction` | Configuration change needed on the external resource |
| `ownerHint` | Inferred from resource tags with priority `owner` > `team` > `costcenter`; `null` when none of these tags exist |

## Usage by Skill

- **azure-to-bicep**: Builds a resource model from live Azure resources; generates Bicep from it.
- **azure-to-diagram**: Builds a resource model from live Azure resources; generates Draw.io XML from it.
- **bicep-diagram-sync**: Parses both Bicep and Draw.io into resource models and compares them.
- **bicep-policy-check**: Parses Bicep into a resource model to evaluate against Azure Policy.
- **bicep-whatif**: Parses Bicep into a resource model and compares it against live Azure state.
- **diagram-azure-sync**: Produces two resource models (diagram + live Azure) and compares them (quick or deep mode).
- **diagram-to-bicep**: Parses Draw.io XML into a resource model; enriches it with configuration manifest; generates Bicep.
- **sketch-to-diagram**: Produces a resource model from image analysis; generates Draw.io XML via stencil mapping.

## Common Azure Resource Types

| Resource Type | Short Name |
|---------------|------------|
| `Microsoft.Compute/virtualMachines` | VM |
| `Microsoft.Web/sites` | App Service |
| `Microsoft.Web/serverfarms` | App Service Plan |
| `Microsoft.Storage/storageAccounts` | Storage Account |
| `Microsoft.Sql/servers` | SQL Server |
| `Microsoft.Sql/servers/databases` | SQL Database |
| `Microsoft.Network/virtualNetworks` | VNet |
| `Microsoft.Network/virtualNetworks/subnets` | Subnet |
| `Microsoft.Network/networkSecurityGroups` | NSG |
| `Microsoft.Network/loadBalancers` | Load Balancer |
| `Microsoft.Network/applicationGateways` | App Gateway |
| `Microsoft.Network/publicIPAddresses` | Public IP |
| `Microsoft.Network/networkInterfaces` | NIC |
| `Microsoft.Network/privateDnsZones` | Private DNS Zone |
| `Microsoft.Network/privateEndpoints` | Private Endpoint |
| `Microsoft.Network/virtualNetworkGateways` | VPN Gateway |
| `Microsoft.KeyVault/vaults` | Key Vault |
| `Microsoft.ContainerRegistry/registries` | Container Registry |
| `Microsoft.ContainerService/managedClusters` | AKS |
| `Microsoft.App/containerApps` | Container App |
| `Microsoft.App/managedEnvironments` | Container App Environment |
| `Microsoft.DocumentDB/databaseAccounts` | Cosmos DB |
| `Microsoft.ServiceBus/namespaces` | Service Bus |
| `Microsoft.EventHub/namespaces` | Event Hub |
| `Microsoft.Cache/redis` | Redis Cache |
| `Microsoft.Insights/components` | Application Insights |
| `Microsoft.OperationalInsights/workspaces` | Log Analytics Workspace |
| `Microsoft.ApiManagement/service` | API Management |
| `Microsoft.SignalRService/signalR` | SignalR |
| `Microsoft.CognitiveServices/accounts` | Cognitive Services |
| `Microsoft.ManagedIdentity/userAssignedIdentities` | Managed Identity |
| `Microsoft.Authorization/roleAssignments` | Role Assignment |
| `Microsoft.Resources/resourceGroups` | Resource Group |
