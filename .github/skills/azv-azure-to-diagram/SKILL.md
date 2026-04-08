---
name: azv-azure-to-diagram
description: Reverse-engineer a live Azure scope (resource group or filtered subscription) into a professional Draw.io architecture diagram. Discovers resources via Azure MCP, infers relationships from resource properties, filters infrastructure-only resources, and generates a diagram following established AzVerify conventions.
license: MIT
metadata:
  author: AzVerify
  version: "1.0"
  project: AzVerify
---

Discover resources in a live Azure scope and generate a Draw.io architecture diagram with proper container hierarchy, verified icons, and inferred relationships.

**Input**: An Azure scope — a resource group name (primary) or a subscription ID with optional resource type filter. The user can specify the scope or the skill will prompt for it.

**Tools required**: File system tools (read/write files), Terminal (for running `az` CLI commands), Azure MCP server tools (`mcp_azure_group_resource_list`, `mcp_azure_compute`, `mcp_azure_storage`, `mcp_azure_subscription_list`, etc.), Draw.io MCP (`mcp_drawio_create_diagram` or `mcp_draw_io_create_diagram`)


---

## Output Budget Rules (CRITICAL)

**This skill frequently handles 20-40+ resources. To avoid hitting the LLM response length limit, follow these rules strictly:**

1. **Save data to files, don't print it.** After discovery (Step 3) and enrichment (Step 6), you may write the resource model to a temporary JSON file in the solution folder while the skill is running. Reference the temporary file in subsequent steps instead of keeping all data in the response.
2. **Minimize inline tables.** Never print full resource tables with more than 10 rows in the response. Instead, print a count summary (e.g., "Found 34 resources — saved to a temporary resource model file") and write the full table to the `original-request.md` file at the end.
3. **No per-resource progress messages.** During enrichment, do NOT print a line per resource. Print a single summary after the batch completes (e.g., "Enriched 34 resources (3 warnings)").
4. **Batch CLI calls.** Use a single `az resource list` with `--query` to get all resources, rather than per-resource MCP calls where possible.
5. **Build diagram XML in a file.** Write the XML to a temporary file or build it as a string internally. Do NOT echo the XML in the response.

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-stencil-mapping.json` — Azure resource type to Draw.io stencil mapping (includes non-obvious icon paths and naming exceptions)
- `.github/skills/shared/azure-resource-configs.md` — Per-resource-type configuration schemas with defaults

**Shared procedures** (MUST follow):
- `.github/skills/shared/procedures/azure-authentication.md` — Azure session check procedure
- `.github/skills/shared/procedures/resource-filtering.md` — Resource exclusion lists (use "Exclude for Diagrams" column)

---

## Steps

### 1. Check Azure Authentication

Follow the procedure in `.github/skills/shared/procedures/azure-authentication.md`. **HARD GATE** — stop if not authenticated.

### 2. Accept Inputs

Identify the Azure scope to discover resources from.

#### 2a. Identify the Azure Scope

**If the user specifies a resource group name:**
- Use that resource group as the discovery scope
- Verify the resource group exists: run `az group show --name <name>` — if this fails, report an error and stop

**If the user specifies a subscription ID:**
- Use that subscription as the discovery scope
- Note: subscription-level discovery can produce many resources — the skill will apply filtering and warnings (see Step 4)

**If no scope is specified:**
- Ask the user:
```
Which Azure resource group should I generate a diagram from?

If you want subscription-level discovery, provide a subscription ID instead.
```
- Wait for user input

#### 2b. Identify Optional Filters

If the user provides a resource type filter (e.g., "only compute and networking resources"):
- Map the filter to Azure resource type prefixes (e.g., `Microsoft.Compute/*`, `Microsoft.Network/*`)
- Apply these filters during discovery

### 3. Discover Azure Resources

Enumerate all resources in the specified Azure scope.

**3a. Resource group scope**

Use `az resource list --resource-group <rg-name> -o json` to enumerate all resources. This single CLI call retrieves all resources with their properties in one batch — prefer this over multiple MCP calls.

Alternatively, use `mcp_azure_group_resource_list` if the CLI is unavailable.

For each discovered resource, extract:
- `id` — full ARM resource ID
- `name` — resource name
- `type` — Azure resource type (e.g., `Microsoft.Compute/virtualMachines`)
- `location` — Azure region
- `tags` — resource tags (used for filtering)

Display a single progress line:
```
Found **N resources** in `<rg-name>` — now filtering and enriching.
```

**3b. Subscription scope**

Use Azure MCP tools or `az resource list --subscription <sub-id>` to discover resources across the subscription. Apply any user-specified resource type filters.

**3c. Handle empty results**

If no resources are found (or none remain after filtering):
```
## No Resources Found

No resources were found in `<scope-name>`.

If you expected resources here, verify:
- The resource group name is spelled correctly
- You're connected to the correct subscription (`az account show`)
- Resources have been deployed to this scope
```
- Stop execution

### 4. Filter Infrastructure-Only Resources

Apply the filtering rules from `.github/skills/shared/procedures/resource-filtering.md` using the **"Exclude for Diagrams"** column.

> **Key difference from Bicep skills**: Diagrams exclude monitoring/identity infrastructure (Application Insights, Log Analytics, action groups, user-assigned identities, diagnostic settings). See the "Exclude for Diagrams" column.

**If all resources are filtered out**, report "No Diagram-Worthy Resources" and stop execution.

**Display the filtered resource list (concise):**
- ≤10 resources: show inline table with columns #, Resource, Type, Location
- >10 resources: show type summary counts only; save the full list to a temporary resource model file

Write the temporary resource model JSON to the solution folder (create early — see Step 9a). It is an intermediate artifact only and must be deleted before the skill finishes.

### 5. Check for Large Scope

If the filtered resource count exceeds **20**, warn and offer:
1. **Filter by type** — present unique resource types with counts, let user select
2. **Generate full diagram** — proceed with all resources

Re-filter if the user selects option 1, then continue.

### 6. Enrich Resource Properties

Use resource-type-specific Azure MCP tools to retrieve detailed properties for relationship inference.

**Enrichment targets** (by resource type):

| Resource Type | MCP Tool | Properties to Extract |
|---------------|----------|----------------------|
| `Microsoft.Compute/virtualMachines` | `mcp_azure_compute` | `networkProfile.networkInterfaces`, `storageProfile.osDisk`, VM size |
| `Microsoft.Network/virtualNetworks` | Azure MCP | `subnets` (list of subnet names and address prefixes) |
| `Microsoft.Network/networkInterfaces` | Azure MCP | `ipConfigurations[].subnet.id`, `networkSecurityGroup.id` |
| `Microsoft.Network/privateEndpoints` | Azure MCP | `privateLinkServiceConnections[].privateLinkServiceId` |
| `Microsoft.Web/sites` | Azure MCP | `virtualNetworkSubnetId`, `serverFarmId` |
| `Microsoft.Web/sites` (app settings) | `az webapp config appsettings list` | `APPLICATIONINSIGHTS_CONNECTION_STRING`, `APPINSIGHTS_INSTRUMENTATIONKEY`, connection strings referencing other resources (SQL, Cosmos DB, Storage, etc.) |
| `Microsoft.Web/sites` (connection strings) | `az webapp config connection-string list` | Named connection strings referencing databases, storage, or other resources |
| `Microsoft.Web/sites` (identity) | `az webapp identity show` | `userAssignedIdentities` — keys are ARM resource IDs of user-assigned managed identities |
| `Microsoft.Storage/storageAccounts` | `mcp_azure_storage` | `networkRuleSet`, `privateEndpointConnections` |
| `Microsoft.KeyVault/vaults` | Azure MCP | `networkAcls`, `privateEndpointConnections` |
| `Microsoft.ManagedIdentity/userAssignedIdentities` | `az role assignment list --assignee <principalId> --all` | Role assignments — each `scope` references a target resource |

**Enrichment process:**

**Prefer batch CLI enrichment over per-resource MCP calls** to reduce output volume:

1. **Batch approach (preferred):** Run a single `az resource list --resource-group <rg> -o json` with `--query` to get all resources with their full properties in one call. Parse the JSON output to extract relationship-relevant properties.
2. **Targeted MCP calls:** Only use per-resource MCP calls for resource types that need specific APIs not available in the batch output (e.g., `az webapp config appsettings list` for App Service app settings).
3. Store enriched properties alongside the base resource information in the temporary resource model file.

**Output discipline during enrichment:**
- Do NOT print a status line per resource
- Print a single summary after all enrichment is complete:
  ```
  Enriched N resources (K via batch query, J via targeted API calls, W warnings).
  ```
- If any resources could not be enriched, list only the warnings (not successes)

**Graceful fallback:**
If a resource-type-specific MCP tool fails or is unavailable:
- Track the warning internally
- Continue with the base resource information from the list operation
- Do **not** stop execution due to enrichment failures
- Report all warnings in the single summary line above

### 7. Infer Relationships

Analyze enriched resource properties to discover relationships. Apply these patterns:

| Pattern | Detection | Relationship | Edge Style |
|---------|-----------|-------------|------------|
| VNet/Subnet containment | VNet has `subnets` property | Container nesting | — |
| NIC→VM→Subnet | VM `networkProfile.networkInterfaces` → NIC `ipConfigurations[].subnet.id` | `connects`, place VM in subnet | strokeColor=#0078D4 |
| Private Endpoint | PE `privateLinkServiceConnections[].privateLinkServiceId` references target | `secures` | strokeColor=#E81123 |
| Diagnostic Settings | Resource targets Log Analytics/Storage | `depends` | strokeColor=#999999, dashed |
| Key Vault References | Config contains `@Microsoft.KeyVault(SecretUri=...)` | `secures` | strokeColor=#E81123 |
| App Service Plan | Web App `serverFarmId` references ASP | `depends` | strokeColor=#999999, dashed |
| App Insights | App settings contain `APPLICATIONINSIGHTS_CONNECTION_STRING` matching AI resource | `connects` | strokeColor=#0078D4 |
| Connection Strings | App settings contain SQL/Cosmos/Storage/Redis server names matching discovered resources | `connects` | strokeColor=#0078D4 |
| Named Connection Strings | `az webapp config connection-string list` entries reference database or storage resources in the same RG | `connects` | strokeColor=#0078D4 |
| User-Assigned Identity | Web App `userAssignedIdentities` keys contain ARM ID of a discovered managed identity | `secures` | strokeColor=#E81123 |
| RBAC Role Assignment | Managed identity has role assignments whose `scope` matches a discovered resource's ARM ID | `secures` | strokeColor=#E81123 |
| Co-located Resource Inference | When a Key Vault or Storage Account exists in the same RG as a Web App/Function App and no other consumer is found, infer a `connects` relationship (apps commonly use co-located KV and Storage even when the link isn't visible in app settings) | `connects` | strokeColor=#0078D4 |

**Co-located resource inference rules:**
- Only apply when the RG contains ≤15 resources (small, focused resource groups imply intentional co-location)
- Only infer connections to Key Vault and Storage Account — these are the most commonly implicitly consumed resources
- If explicit connections (app settings, connection strings, Key Vault references) are already detected for a resource, do NOT add a co-located inference for the same pair
- Mark co-located inferences with `(inferred)` in the relationship output so the user can verify

Resources with no relationships are placed directly inside their resource group container.

**Output (concise):** ≤10 relationships → inline table. >10 → count summary + save to the temporary resource model file:
```
Inferred **N relationships** (saved to a temporary resource model file). Key: 3 subnet placements, 2 PEs, 4 data connections.
```

### 8. Generate Draw.io Diagram

Build the Draw.io diagram XML from the resource model and inferred relationships following the shared conventions in `.github/skills/shared/drawio-diagram-conventions.md`.

Follow all diagram construction rules: canvas format, stencil mapping lookup, resource shapes and icon paths, container hierarchy (Resource Group → VNet → Subnet), edge rules, VNet Integration special case, and layout patterns (left-to-right flow, 2×2 zone grid, hub-and-spoke, semantic proximity, sizing).

**Multi-page diagrams**: When the resource group includes networking subnets or monitoring resources, generate additional pages alongside "Architecture Overview":
- **Network Topology page**: Follow the network topology layout rules in `.github/skills/shared/drawio-diagram-conventions.md` section 7e. Use a 3-column × N-row subnet grid grouped by function tier. Place supporting resources (ASPs, Managed Identities, WAF) inside their parent subnets — never in a scattered row at the bottom of the VNet. Add per-subnet route table icons instead of radiating edges from a central icon. Target `pageWidth="1800" pageHeight="1600"` — the page MUST NOT require horizontal scrolling on a 1920px display.
- **Monitoring page**: single flat row of alert rules linked to their telemetry resources. `pageWidth="1800"` is sufficient.

**8f. Generate the diagram**

Use the Draw.io MCP tool (`mcp_drawio_create_diagram` or `mcp_draw_io_create_diagram`) to create the `.drawio` file with the assembled XML.
**Output discipline for diagram generation:**
- Do NOT echo or print the Draw.io XML in the response — it is passed directly to the MCP tool
- After the diagram is created, confirm with a single line: `Diagram created with N resource cells and M edges.`

### 9. Create Solution Folder Output

Create a solution folder containing the generated diagram and metadata.

**9a. Create the folder (do this early — at the start of Step 4)**

Create the solution folder as soon as the scope is confirmed, so intermediate files (including a temporary resource model JSON file) can be written to it during discovery and enrichment.

- Name the folder using the scope name in kebab-case:
  - Resource group `MyAppRG` → folder `my-app-rg/`
  - If a folder with that name already exists, append a numeric suffix: `my-app-rg-2/`

**9b. Save the diagram**

- Save the `.drawio` file inside the solution folder
- Name it using the folder name: `<folder-name>.drawio`

**9c. Create original-request.md**

Document the discovery in `original-request.md` with: source scope, subscription, discovery date, resource counts, full resource table (Resource, Type, Location), full relationship table (Source, Relationship, Target), and notes pointing to related skills (azv-bicep-diagram-sync, azv-diagram-to-bicep). **Full tables go here, not in the chat response.**

**9d. Clean up intermediate files**

Delete all intermediate files from the solution folder before you finish — only final deliverables should remain. This includes the temporary resource model JSON file, `resource-list-raw.json`, and any `extract-*.json` files written during discovery. Never leave the resource model JSON in the repository or output folder after the skill completes; its content must be incorporated into `original-request.md` and the diagram.

**9e. Present completion (concise)**

Show: folder path, diagram file with resource count, `original-request.md`, resource/relationship/excluded counts, and next steps pointing to azv-diagram-to-bicep and azv-diagram-azure-sync.