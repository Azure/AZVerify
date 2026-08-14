---
name: azv-azure-to-diagram
description: Reverse-engineer a live Azure scope (resource group or filtered subscription) into a professional Draw.io architecture diagram following established AzVerify conventions. Use when the user wants to visualize or document existing Azure infrastructure as a diagram.
license: MIT
compatibility: Requires an authenticated Azure session (CLI, Az PowerShell, or Azure MCP).
---

Discover resources in a live Azure scope and generate a Draw.io architecture diagram with proper container hierarchy, verified icons, and inferred relationships.

**Input**: An Azure scope — a resource group name (primary) or a subscription ID with optional resource type filter. The user can specify the scope or the skill will prompt for it.

**Tools required**: File system tools (read/write files), Terminal (for running `az` CLI commands and PowerShell 7 / `pwsh` shared scripts), Azure MCP server tools (`mcp_azure_group_resource_list`, `mcp_azure_compute`, `mcp_azure_storage`, `mcp_azure_subscription_list`, etc.), Draw.io MCP (`mcp_drawio_create_diagram` or `mcp_draw_io_create_diagram`)


---

### Tool Preflight

Before discovery, verify the capabilities used by this workflow:

1. Call `azure-get_azure_bestpractices` with `get_azure_bestpractices_get` for general code generation guidance.
2. Call `azure-bicepschema` with `bicepschema_get` for every resource type whose API version or deployable schema is uncertain.
3. Use `azure-documentation` search and fetch for current service guidance when a schema call does not answer the question.

If a capability is unavailable, continue only when the matching shared reference plus Bicep CLI validation can provide the same check; report the fallback in the verification summary.


## Output Budget Rules

Follow `.github/skills/shared/procedures/output-budget.md` strictly — this skill frequently handles 20-40+ resources and can hit the LLM response length limit. In addition to the shared rules:

- **Build the Draw.io diagram directly.** Write the assembled XML to the `.drawio` file via the Draw.io MCP tool. Do NOT echo full Draw.io XML content in the response — show only the file path and a summary of what was generated.
- **Delete intermediate files on the skill's own schedule.** Intermediate extraction files (`resource-model.json`, `extract-*.json`, and any other temporary resource model JSON) are never deliverables. Keep them available until Step 9c has written `original-request.md` (it needs the resource counts and relationship tables), then delete them all in Step 9d. Never leave the resource model JSON behind after the skill completes.

## Fallback: pwsh Unavailable

If `pwsh`/`powershell.exe` or a shared script cannot be executed, use the fallback that matches the step you are on, then continue the workflow normally:

| Step | Fallback source |
|------|-----------------|
| 1 — Auth check | MCP auth probe fallback in `.github/skills/shared/procedures/azure-authentication.md` |
| 3 — Discovery | "Script/pwsh Unavailable — MCP Fallback" in `.github/skills/shared/azure-resource-configs.md` (see Step 3c) |
| 4 — Filtering | Inline fallback in `.github/skills/shared/procedures/resource-filtering.md` |
| 6a — Property extraction | "Script/pwsh Unavailable — MCP Fallback" in `.github/skills/shared/azure-resource-configs.md` |
| 6b — Read-only stripping and secrets | Manual strip rules listed in Step 6b, using `.github/skills/shared/data/arm-readonly-properties.json` |
| 7a — Relationships | "Manual Relationship Inference — Script Unavailable Fallback" in `.github/skills/shared/azure-resource-model.md` |

Stop only if Azure MCP is also unavailable, using the prerequisite message in `.github/skills/shared/azure-resource-configs.md`.

## Steps

### 1. Check Azure Authentication

Run `pwsh .github/skills/shared/scripts/Test-AzureAuth.ps1` — see `.github/skills/shared/procedures/azure-authentication.md` for the script contract. The script writes a JSON status object to stdout and exits non-zero when no Azure session is found. A **non-zero exit code is a HARD GATE**: present the authentication instructions from the contract doc and stop. *(If pwsh or the script is unavailable, see "Fallback: pwsh Unavailable".)*

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

**Resource type filters:**
If the user provides a resource type filter (e.g., "only compute and networking resources"):
- Map the filter to Azure resource type prefixes (e.g., `Microsoft.Compute/*`, `Microsoft.Network/*`)
- Apply these filters during discovery

**Resource exclusions:**
If the user wants to exclude specific resources or types from the diagram:
- Accept a list of resource names or type patterns to skip
- Apply exclusions during the filtering step (Step 4), in addition to the standard "Exclude for Diagrams" rules

### 3. Discover Azure Resources

Enumerate all resources in the specified Azure scope.

**3a. Resource group scope**

Run the shared discovery script and write the resource model to a temporary JSON file in the output folder:

```
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -ResourceGroup <rg-name> -OutFile <output-folder>/resource-model.json
```

The script emits the shared resource model contract (`id`, `name`, `type`, `location`, `tags`, `sku`) documented in `.github/skills/shared/azure-resource-model.md`. Treat the emitted JSON as the source of truth for Steps 4-7. Do not print the model contents.

If the script exits non-zero or produces unparseable output, report the error message to the user and stop. If the result count is zero and the resource group was confirmed to exist in Step 2a, warn the user that the authenticated identity may lack Reader permissions.

Display a single progress line:
```
Found **N resources** in `<rg-name>` — now filtering and enriching.
```

**3b. Subscription scope**

Run the same script with `-SubscriptionId <sub-id>` instead of `-ResourceGroup`. If the user specified a resource type **inclusion** filter in Step 2b (e.g., "only show networking resources"), pass it as a `-ResourceTypeFilter` parameter to the script if supported; otherwise filter the emitted JSON before writing to the temporary model file. Do **not** apply user-specified **exclusions** here — those are applied exactly once, in Step 4, alongside the standard exclusion rules, to avoid filtering the same resource list twice.

If the script exits non-zero or produces unparseable output, report the error message to the user and stop. If the result count is zero, warn the user that the authenticated identity may lack Reader permissions on this subscription.

Display a single progress line:
```
Found **N resources** in subscription `<sub-id>` — now filtering and enriching.
```

**3c. Script/pwsh unavailable — MCP fallback**

If `pwsh`/`powershell.exe` or the script cannot be executed, build the same resource model through Azure MCP as described in "Fallback: pwsh Unavailable" (list resources with `mcp_azure_group_resource_list`, then assemble the model shape by hand).

**3d. Handle empty results**

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

**3e. Create Solution Folder**

Create the solution folder now, before any intermediate files are written.

- Name the folder using the scope name in kebab-case:
  - Resource group `MyAppRG` → folder `my-app-rg/`
  - If a folder with that name already exists, increment a numeric suffix until a unique name is found (e.g., `my-app-rg-2/`, `my-app-rg-3/`, …). If more than 5 collisions are detected, ask the user to confirm the output folder name.
- Use this folder for all intermediate files and final deliverables throughout the skill.

### 4. Filter Infrastructure-Only Resources

Run `pwsh .github/skills/shared/scripts/Select-AzureResources.ps1 -InputFile <resource-model.json> -Mode diagram` — see `.github/skills/shared/procedures/resource-filtering.md` for the script contract. The script applies the shared exclusion rules using the **"Exclude for Diagrams"** column, writes the filtered resource model JSON to stdout, and should be treated as the source of truth for the remaining steps. *(If pwsh or the script is unavailable, see "Fallback: pwsh Unavailable".)*

If the script exits non-zero or produces unparseable output, report the error message to the user and stop. Do not proceed with an empty or partial resource list.

Also apply any user-specified **exclusion** filters from Step 2b now — this is the only place exclusions are applied (inclusion filters, if any, were already applied in Step 3a/3b).


**If all resources are filtered out**, report "No Diagram-Worthy Resources" and stop execution.

Display the filtered resource list:
- If the filtered count is **10 or fewer**: display the full table inline with columns: #, Resource, Type, Location, SKU.
- If the filtered count **exceeds 10**: print only the count and a resource-type breakdown summary in the chat response. Write the full resource table to the temporary resource model file in the solution folder instead of echoing it.

Write the temporary resource model JSON to the solution folder created in Step 3e. It is an intermediate artifact only and must be deleted before the skill finishes.

### 5. Check for Large Scope

If the filtered resource count exceeds **20**, warn and offer:
1. **Filter by type** — present unique resource types with counts, let user select
2. **Generate full diagram** — proceed with all resources

Re-filter if the user selects option 1, then continue.

If the user's response does not map to option 1 or option 2, re-present the two options with the instruction: "Please reply with 1 to filter by type or 2 to generate the full diagram." If after two re-prompts no valid choice is received, default to option 2 and note this in the completion summary.

### 6. Enrich Resource Properties

Use resource-type-specific Azure MCP tools to retrieve detailed properties for relationship inference.

**Enrichment targets** (by resource type): look up each in-scope resource's `resourceTypes[]` entry in `.github/skills/shared/data/azure-property-paths.json` for the MCP tool (or CLI fallback) and the ARM JSON paths to extract. That mapping is the authoritative source — see "Property Mapping Source of Truth" in `.github/skills/shared/azure-resource-configs.md` for how to consume it. Do not duplicate the mapping table here.

**Enrichment process:**

**Prefer batch CLI enrichment over per-resource MCP calls** to reduce output volume:

1. **Batch approach (preferred):** Run a single `az resource list` scoped consistently with discovery: use `--resource-group <rg>` for resource-group scope or `--subscription <sub-id>` for subscription scope, with `-o json` and the required `--query`, to retrieve the resources in one call. Parse the JSON output to extract relationship-relevant properties. As each resource is enriched this way, record its enrichment source (`batch`) in a local tracking variable (e.g., a map of resource ID → `batch`/`targeted`/`failed`).
2. **Determine remaining gaps:** After the batch query, before making any MCP calls, produce a list of resource types still needing targeted calls — i.e., types whose relationship-relevant properties are not present in the batch output (per `.github/skills/shared/data/azure-property-paths.json`).
3. **Targeted MCP calls:** Only use per-resource MCP calls for the resource types identified in step 2 that need specific APIs not available in the batch output (e.g., `az webapp config appsettings list` for App Service app settings). Update the tracking variable to `targeted` for each resource enriched this way, or `failed` if the call errors or is unavailable.
4. Store enriched properties alongside the base resource information in the temporary resource model file.
5. Use the tracking variable (not re-derivation) to produce the accurate counts (K batch, J targeted, W failed/warnings) in the summary line below.

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

The discovery script (Step 3a/3b) already populates a baseline `relationships` array on each resource — parent/child `contains` links plus any relationship it detects by matching ARM resource IDs inside `properties` (see `.github/skills/shared/azure-resource-model.md`). Start from that baseline instead of re-detecting containment and direct ID references from scratch, then use the patterns below to add diagram-specific edge styles and detect relationships the generic ID matching cannot see (connection strings, Key Vault reference syntax, RBAC scope strings, co-location).

Analyze enriched resource properties to discover the remaining relationships the baseline cannot see — none of these are direct ARM ID references, so generic ID matching misses them. (Edge styling for the resulting relationship types is defined once in `drawio-diagram-conventions.md` §5 — do not re-specify colors here.)

| Pattern | Detection | Relationship |
|---------|-----------|-------------|
| Key Vault References | Config contains `@Microsoft.KeyVault(SecretUri=...)` | `secures` |
| App Insights | App settings contain `APPLICATIONINSIGHTS_CONNECTION_STRING` matching AI resource | `connects` |
| Connection Strings | App settings contain SQL/Cosmos/Storage/Redis server names matching discovered resources | `connects` |
| Named Connection Strings | `az webapp config connection-string list` entries reference database or storage resources in the same RG | `connects` |
| RBAC Role Assignment | Managed identity has role assignments whose `scope` matches a discovered resource's ARM ID | `secures` |

**Co-located Resource Inference**

After completing explicit relationship detection using the table above, check for implicit co-location connections using this numbered checklist:

1. Count the filtered resources — proceed only if ≤15 resources remain (small, focused resource groups imply intentional co-location).
2. Identify all Key Vault and Storage Account resources that have no explicit reference detected (no app settings, connection strings, or Key Vault reference patterns among resources in this resource group pointing to them).
3. Identify all Web App and Function App resources.
4. For each unmatched pair (Key Vault/Storage ↔ Web App/Function App), add an inferred `connects` edge and label it `(inferred)` in the relationship output so the user can verify.

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
- **Network Topology page**: Generated when the filtered resources include VNets with subnets. Follow the network topology layout rules in `.github/skills/shared/drawio-diagram-conventions.md` section 7e. Use a 3-column × N-row subnet grid grouped by function tier. Place resources inside subnets only when a confirmed VNet Integration or subnet delegation exists (e.g., a Managed Identity or WAF with an actual subnet association); ASPs and other resources without VNet Integration should be placed in a separate swimlane outside the VNet container — never in a scattered row at the bottom of the VNet. Add per-subnet route table icons instead of radiating edges from a central icon. Target `pageWidth="1800" pageHeight="1600"` — the page MUST NOT require horizontal scrolling on a 1920px display.
- **Monitoring page**: Generated when alert rules or action groups are present in the filtered model. Do not assume that a Step 2b inclusion filter overrides Step 4's standard exclusions. Layout: single flat row of alert rules linked to their telemetry resources. `pageWidth="1800"` is sufficient.

**8f. Generate the diagram**

Use the Draw.io MCP tool (`mcp_drawio_create_diagram` or `mcp_draw_io_create_diagram`) to create the `.drawio` file with the assembled XML.
**Output discipline for diagram generation:**
- Do NOT echo or print the Draw.io XML in the response — it is passed directly to the MCP tool
- After the diagram is created, confirm with a single line: `Diagram created with N resource cells and M edges.`

If the Draw.io MCP tool is unavailable or returns an error, write the assembled XML string to `<folder-name>.drawio` directly using the file system tool and note in the completion summary that the file was written without MCP validation. If both the Draw.io MCP tool and the file system tool are unavailable, report the failure to the user and stop without outputting the raw XML.

### 9. Create Solution Folder Output

Create a solution folder containing the generated diagram and metadata.

**9a. Confirm the solution folder**

The solution folder was created in Step 3e. Save the diagram file here now (see Step 9b).

**9b. Save the diagram**

- Save the `.drawio` file inside the solution folder
- Name it using the folder name: `<folder-name>.drawio`

**9c. Create original-request.md**

Document the discovery in `original-request.md` with: source scope, subscription, discovery date, resource counts, full resource table (Resource, Type, Location), full relationship table (Source, Relationship, Target), and notes pointing to related skills (azv-bicep-diagram-sync, azv-diagram-to-bicep). **Full tables go here, not in the chat response.** Do not transcribe raw enrichment JSON properties — only the structured resource and relationship tables are required.

**9d. Clean up intermediate files**

Delete all intermediate files from the solution folder before you finish — only final deliverables should remain. This includes `resource-model.json` (written in Step 3a/3b), any filtered copy written in Step 4, and any `extract-*.json` files written during enrichment. The raw JSON properties from enrichment do not need to be transcribed to `original-request.md`; only the structured tables from Step 9c are required there.

**9e. Present completion (concise)**

Show: folder path, diagram file with resource count, `original-request.md`, resource/relationship/excluded counts, and next steps pointing to azv-diagram-to-bicep and azv-diagram-azure-sync.