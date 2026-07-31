---
name: azv-azure-to-diagram
description: Reverse-engineer a live Azure scope (resource group or filtered subscription) into a professional Draw.io architecture diagram following established AzVerify conventions. Use when the user wants to visualize or document existing Azure infrastructure as a diagram.
license: MIT
compatibility: Prefers PowerShell 7 (pwsh) and Azure CLI (az); falls back to the Azure MCP server and inline procedures when unavailable. Requires an authenticated Azure session (CLI, Az PowerShell, or Azure MCP).
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
2. **Minimize inline tables.** Never print full resource tables with more than 10 rows in the response. Instead, print a count summary and write the full table to the `original-request.md` file at the end.

   **Output thresholds** (apply at every step where a list or table is displayed):

   | Item count | Chat response | File output |
   |------------|---------------|-------------|
   | ≤10 items | Inline table | Optional |
   | 11–20 items | Count summary only | Save full list to file |
   | >20 items | Count summary only + warn user | Save full list to file |

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

Run `pwsh .github/skills/shared/scripts/Test-AzureAuth.ps1` — see `.github/skills/shared/procedures/azure-authentication.md` for the script contract. The script writes a JSON status object to stdout and exits non-zero when no Azure session is found. A **non-zero exit code is a HARD GATE**: present the authentication instructions from the contract doc and stop. *(If pwsh or the script is unavailable, follow the MCP auth probe fallback defined in the azure-authentication.md contract before stopping.)*

### 2. Accept Inputs

Identify the Azure scope to discover resources from.

#### 2a. Identify the Azure Scope

**If the user specifies a resource group name:**
- Use that resource group as the discovery scope
- Verify the resource group exists: run `az group show --name <name>` — if this fails, report an error and stop
- After `az group show` succeeds, confirm the returned `subscriptionId` matches the authenticated session (`az account show --query id -o tsv`). If they differ, display both IDs and ask the user to confirm before proceeding.

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

If the CLI command returns a non-zero exit code or the JSON output contains an error object, report the error message to the user and stop. If the command succeeds but the result count is zero and the resource group was confirmed to exist in Step 2a, warn the user that the authenticated identity may lack Reader permissions.

Display a single progress line:
```
Found **N resources** in `<rg-name>` — now filtering and enriching.
```

**3b. Subscription scope**

Use `az resource list --subscription <sub-id> -o json` to discover resources across the subscription. Apply any user-specified resource type filters.

For each discovered resource, extract:
- `id` — full ARM resource ID
- `name` — resource name
- `type` — Azure resource type (e.g., `Microsoft.Compute/virtualMachines`)
- `location` — Azure region
- `tags` — resource tags (used for filtering)

If the CLI command returns a non-zero exit code or the JSON output contains an error object, report the error message to the user and stop. If the command succeeds but the result count is zero, warn the user that the authenticated identity may lack Reader permissions on this subscription.

Display a single progress line:
```
Found **N resources** in subscription `<sub-id>` — now filtering and enriching.
```

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

**3d. Create Solution Folder**

Create the solution folder now, before any intermediate files are written.

- Name the folder using the scope name in kebab-case:
  - Resource group `MyAppRG` → folder `my-app-rg/`
  - If a folder with that name already exists, increment a numeric suffix until a unique name is found (e.g., `my-app-rg-2/`, `my-app-rg-3/`, …). If more than 5 collisions are detected, ask the user to confirm the output folder name.
- Use this folder for all intermediate files and final deliverables throughout the skill.

### 4. Filter Infrastructure-Only Resources

Apply the filtering rules from `.github/skills/shared/procedures/resource-filtering.md` using the **"Exclude for Diagrams"** column.

> **Key difference from Bicep skills**: Diagrams exclude monitoring/identity infrastructure (Application Insights, Log Analytics, action groups, user-assigned identities, diagnostic settings). See the "Exclude for Diagrams" column.

**If all resources are filtered out**, report "No Diagram-Worthy Resources" and stop execution.

**Display the filtered resource list (concise):** Follow Output Budget Rules. For inline tables, use columns #, Resource, Type, Location.

Write the temporary resource model JSON to the solution folder created in Step 3d. It is an intermediate artifact only and must be deleted before the skill finishes.

### 5. Check for Large Scope

If the filtered resource count exceeds **20**, warn and offer:
1. **Filter by type** — present unique resource types with counts, let user select
2. **Generate full diagram** — proceed with all resources

Re-filter if the user selects option 1, then continue.

If the user's response does not map to option 1 or option 2, re-present the two options with the instruction: "Please reply with 1 to filter by type or 2 to generate the full diagram." If after two re-prompts no valid choice is received, default to option 2 and note this in the completion summary.

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

**Co-located Resource Inference**

After completing explicit relationship detection using the table above, check for implicit co-location connections using this numbered checklist:

1. Count the filtered resources — proceed only if ≤15 resources remain (small, focused resource groups imply intentional co-location).
2. Identify all Key Vault and Storage Account resources that have no explicit reference detected (no app settings, connection strings, or Key Vault reference patterns among resources in this resource group pointing to them).
3. Identify all Web App and Function App resources.
4. For each unmatched pair (Key Vault/Storage ↔ Web App/Function App), add an inferred `connects` edge (strokeColor=#0078D4) and label it `(inferred)` in the relationship output so the user can verify.

Resources with no relationships are placed directly inside their resource group container.

**Output (concise):** Follow Output Budget Rules for display format. Example count summary:
```
Inferred **N relationships** (saved to a temporary resource model file). Key: 3 subnet placements, 2 PEs, 4 data connections.
```

### 8. Generate Draw.io Diagram

Build the Draw.io diagram XML from the resource model and inferred relationships following the shared conventions in `.github/skills/shared/drawio-diagram-conventions.md`.

Follow all diagram construction rules: canvas format, stencil mapping lookup, resource shapes and icon paths, container hierarchy (Resource Group → VNet → Subnet), edge rules, VNet Integration special case, and layout patterns (left-to-right flow, 2×2 zone grid, hub-and-spoke, semantic proximity, sizing).

If a resource type has no entry in `azure-stencil-mapping.json`, use the generic Azure resource stencil `mxgraph.azure2.general` and append a warning to the completion summary listing unmapped types so the user can update the mapping file.

**Multi-page diagrams**: When the resource group includes networking subnets or monitoring resources that survived filtering, generate additional pages alongside "Architecture Overview":
- **Network Topology page**: Generated when the filtered resources include VNets with subnets. Follow the network topology layout rules in `.github/skills/shared/drawio-diagram-conventions.md` section 7e. Use a 3-column × N-row subnet grid grouped by function tier. Place supporting resources (ASPs, Managed Identities, WAF) inside their parent subnets — never in a scattered row at the bottom of the VNet. Add per-subnet route table icons instead of radiating edges from a central icon. Target `pageWidth="1800" pageHeight="1600"` — the page MUST NOT require horizontal scrolling on a 1920px display.
- **Monitoring page**: Generated only when alert rules or action groups survive filtering (i.e., the user's filter explicitly included them). Do not generate a Monitoring page if all monitoring resources were excluded in Step 4. Layout: single flat row of alert rules linked to their telemetry resources. `pageWidth="1800"` is sufficient.

**8f. Generate the diagram**

Use the Draw.io MCP tool (`mcp_drawio_create_diagram` or `mcp_draw_io_create_diagram`) to create the `.drawio` file with the assembled XML.
**Output discipline for diagram generation:**
- Do NOT echo or print the Draw.io XML in the response — it is passed directly to the MCP tool
- After the diagram is created, confirm with a single line: `Diagram created with N resource cells and M edges.`

If the Draw.io MCP tool is unavailable or returns an error, write the assembled XML string to `<folder-name>.drawio` directly using the file system tool and note in the completion summary that the file was written without MCP validation.

### 9. Create Solution Folder Output

Create a solution folder containing the generated diagram and metadata.

**9a. Confirm the solution folder**

The solution folder was created in Step 3d. Save the diagram file here now (see Step 9b).

**9b. Save the diagram**

- Save the `.drawio` file inside the solution folder
- Name it using the folder name: `<folder-name>.drawio`

**9c. Create original-request.md**

Document the discovery in `original-request.md` with: source scope, subscription, discovery date, resource counts, full resource table (Resource, Type, Location), full relationship table (Source, Relationship, Target), and notes pointing to related skills (azv-bicep-diagram-sync, azv-diagram-to-bicep). **Full tables go here, not in the chat response.** Do not transcribe raw enrichment JSON properties — only the structured resource and relationship tables are required.

**9d. Clean up intermediate files**

Delete all intermediate files from the solution folder before you finish — only final deliverables should remain. This includes the temporary resource model JSON file, `resource-list-raw.json`, and any `extract-*.json` files written during discovery. The raw JSON properties from enrichment do not need to be transcribed to `original-request.md`; only the structured tables from Step 9c are required there.

**9e. Present completion (concise)**

Show: folder path, diagram file with resource count, `original-request.md`, resource/relationship/excluded counts, and next steps pointing to azv-diagram-to-bicep and azv-diagram-azure-sync.