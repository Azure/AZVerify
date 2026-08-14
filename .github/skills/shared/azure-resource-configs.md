# Azure Resource Configuration Reference

Per-resource-type property retrieval mappings and topology-driven auto-detection rules used by AzVerify skills for drift detection and Bicep generation.

For per-resource defaults such as SKUs, sizes, and service settings, derive values from Bicep Schema MCP (`azure-bicepschema` / `bicepschema_get`), or current Microsoft documentation. Do not hardcode defaults in this file.

---

## Property Mapping Source of Truth

The full Azure Property Retrieval Mapping now lives in [`shared/data/azure-property-paths.json`](data/azure-property-paths.json).

Use that JSON file, not this markdown file, when a skill or script needs to:

- identify the primary MCP tool for a resource type
- fall back to the correct `az` CLI command
- extract tracked properties via ARM JSON paths
- apply global SKU extraction rules
- assemble composite properties such as VM `osImage`
- read per-resource severity metadata for drift reporting

### What the JSON contains

- `resourceTypes[]` entries for every tracked Azure resource type
- `mcpTool` and `fallback` query instructions per type
- `properties[]` mappings from logical property names to ARM JSON paths
- `globalSkuRules[]` for shared SKU extraction behavior
- `compositeRules[]` for values built from multiple ARM paths

### How to consume it

- Use `pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1` to retrieve Azure resources and populate tracked properties from the JSON mapping.
- Use the emitted resource model for deep drift comparison.
- When generating reports, treat `shared/data/azure-property-paths.json` as the authoritative source for tracked property names, extraction paths, and severity metadata.

If you need script usage details, refer to the script contracts under `.github/skills/shared/procedures/` and the script implementations in `.github/skills/shared/scripts/`.

### Script/pwsh Unavailable — MCP Fallback

If `pwsh`/`powershell.exe` or `Get-AzureResourceModel.ps1` cannot be executed (tool unavailable, binary not on PATH, or any invocation error), build the resource model directly through Azure MCP instead of stopping:

1. **List resources** — call `mcp_azure_group_resource_list` (scoped to the target resource group or subscription) to enumerate resources. This substitutes for the script's `az resource list` discovery.
2. **Enrich each resource** — for every resource, load its `resourceTypes[]` entry from `shared/data/azure-property-paths.json`. Prefer the entry's `mcpTool` to fetch the resource; if none is available, use the resource-type-specific Azure MCP tool (for example `mcp_azure_storage`, `mcp_azure_keyvault`, `mcp_azure_sql`) or fall back to `az resource show`.
3. **Extract tracked properties** — apply the ARM JSON paths in each `properties[]` mapping, plus `globalSkuRules[]` and `compositeRules[]`, to populate the tracked values by hand. This mirrors exactly what the script's `-Enrich` mode does.
4. **Assemble the model** — emit the same resource model shape the script produces, then continue with deep drift comparison as usual.
5. **If Azure MCP is also unavailable** — report the prerequisite message below and stop:

```text
## Prerequisites Required

This step requires either:
- PowerShell 5.1 (powershell.exe) or higher (`pwsh`) with Azure CLI (az) on PATH, OR
- The Azure MCP server available and connected

Neither was available. Please install one of the above and try again.
```

> **Note**: The MCP fallback yields the same resource model as the script because both draw tracked property names, extraction paths, and severity metadata from `shared/data/azure-property-paths.json`. Only the retrieval mechanism differs.

---

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

## Notes for Deep Comparison Skills

- Deep comparison steps should load tracked property definitions from `shared/data/azure-property-paths.json` through the shared scripts.
- This markdown file intentionally no longer duplicates the large mapping table, to reduce prompt size and keep the JSON contract as the single source of truth.
