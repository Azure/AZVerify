---
name: azv-azure-to-bicep
description: Reverse-engineer a live Azure scope (resource group or filtered subscription) into deployment-ready, modular Bicep templates with parameter files. Use when the user wants to bring existing Azure infrastructure under Bicep/IaC management.
license: MIT
compatibility:Requires an authenticated Azure session (CLI, Az PowerShell, or Azure MCP).
---

Discover resources in a live Azure scope, extract their full configuration, and generate deployment-ready Bicep templates with modular structure, user-editable parameter files, and dependency documentation for external resources.

**Input**: An Azure scope — a resource group name (primary) or a subscription ID with optional resource type filter. Optionally, a target environment hint (dev/prod) to influence default sizing in the parameter file.

**Tools used**: File system tools (read/write files), Terminal (for running `az` CLI commands and PowerShell 7 / `pwsh` shared scripts), Azure MCP server tools (`mcp_azure_group_resource_list`, `mcp_azure_compute`, `mcp_azure_storage`, `mcp_azure_subscription_list`, etc.), Bicep MCP server (for best-practice validation via `get_bicep_best_practices` and `get_az_resource_type_schema`)


## Output Budget Rules

**This skill frequently handles 20-40+ resources. To avoid hitting the LLM response length limit, follow these rules strictly:**

1. **Save data to files, don't print it.** After discovery (Step 3) and property extraction (Step 6), you may write the resource model to a temporary JSON file. Reference the temporary file in subsequent steps.
2. **Minimize inline tables.** Never print full resource tables with more than 10 rows. Print a count summary and write full tables to `original-request.md`.
3. **No per-resource progress messages.** During extraction, print a single summary after the batch (e.g., "Extracted 34 resources (3 partial)").
4. **Batch CLI calls.** Use `az resource list` with `--query` for bulk discovery rather than per-resource MCP calls.
5. **Build Bicep files directly.** Write generated code to files. Do NOT echo full Bicep/bicepparam content in the response — show only file paths and a summary of what was generated.
6. **Delete intermediate files.** Intermediate extraction files (`extract-*.json`, `resource-list-raw.json`, and the temporary resource model JSON file) are never deliverables. Keep them available until Step 11 has written the README (it needs the resource counts and extraction stats), then delete them all in Step 12. Never leave the resource model JSON behind after the skill completes.

## Fallback: pwsh Unavailable

If `pwsh`/`powershell.exe` or a shared script cannot be executed, use the fallback that matches the step you are on, then continue the workflow normally:

| Step | Fallback source |
|------|-----------------|
| 1 — Auth check | MCP auth probe fallback in `.github/skills/shared/procedures/azure-authentication.md` |
| 3 — Discovery | "Script/pwsh Unavailable — MCP Fallback" in `.github/skills/shared/azure-resource-configs.md` |
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
Which Azure resource group should I generate Bicep templates from?

If you want subscription-level discovery, provide a subscription ID instead.
```
- Wait for user input

#### 2b. Identify Optional Parameters

**Target environment hint:**
If the user specifies a target environment (e.g., "generate for dev" or "this will be production"):
- Use this to influence default sizing in the `.bicepparam` comments (e.g., note the current size and suggest dev/prod alternatives)
- If not specified, default to documenting the **current** Azure configuration as-is

**Resource type filters:**
If the user provides a resource type filter (e.g., "only compute and networking resources"):
- Map the filter to Azure resource type prefixes (e.g., `Microsoft.Compute/*`, `Microsoft.Network/*`)
- Apply these filters during discovery

**Resource exclusions:**
If the user wants to exclude specific resources or types:
- Accept a list of resource names or type patterns to skip
- Apply exclusions during the filtering step

### 3. Discover Azure Resources

Enumerate all resources in the specified Azure scope.

**3a. Resource group scope**

Run the shared discovery script and write the resource model to a temporary JSON file in the output folder:

```
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -ResourceGroup <rg-name> -OutFile <output-folder>/resource-model.json
```

The script emits the shared resource model contract (`id`, `name`, `type`, `location`, `tags`, `sku`) documented in `.github/skills/shared/azure-resource-model.md`. Treat the emitted JSON as the source of truth for Steps 4-7. Do not print the model contents.

Display progress:
```
⏳ Discovering resources in resource group `<rg-name>`...
```

**3b. Subscription scope**

Run the same script with `-SubscriptionId <sub-id>` instead of `-ResourceGroup`. Pass user-specified resource type filters from Step 2b as a `-ResourceTypeFilter` parameter to the script if supported; otherwise filter the emitted JSON before writing to the temporary model file. These user filters are distinct from the Step 4 standard exclusion rules applied by `-Mode bicep`, which never handles user filters.

**3c. Script/pwsh unavailable — MCP fallback**

If `pwsh`/`powershell.exe` or the script cannot be executed, build the same resource model through Azure MCP as described in "Fallback: pwsh Unavailable" (list resources with `mcp_azure_group_resource_list`, then assemble the model shape by hand).

**3d. Handle empty results**

If no resources are found after discovery:
```
## No Resources Found

No resources were found in `<scope-name>`.

If you expected resources here, verify:
- The resource group name is spelled correctly
- You're connected to the correct subscription (`az account show`)
- Resources have been deployed to this scope
- The authenticated identity has read permissions on this resource group
```



- Stop execution

### 4. Filter Non-Deployable Resources

Run `pwsh .github/skills/shared/scripts/Select-AzureResources.ps1 -InputFile <resource-model.json> -Mode bicep` — see `.github/skills/shared/procedures/resource-filtering.md` for the script contract. The script applies the shared exclusion rules, writes the filtered resource model JSON to stdout, and should be treated as the source of truth for the remaining steps. *(If pwsh or the script is unavailable, see "Fallback: pwsh Unavailable".)*

If the script exits non-zero or produces unparseable output, report the error message to the user and stop. Do not proceed with an empty or partial resource list.

Also apply any user-specified exclusion filters from Step 2b.

If the filtered resource list is empty after all exclusion rules have been applied, stop and present:
```
All discovered resources were excluded by filtering rules. No Bicep templates can be generated.
Review the exclusion rules in `.github/skills/shared/procedures/resource-filtering.md` or adjust your resource type filter.
```

Display the filtered resource list:
- If the filtered count is **10 or fewer**: display the full table inline with columns: #, Resource, Type, Location, SKU.
- If the filtered count **exceeds 10**: print only the count and a resource-type breakdown summary in the chat response. Create `original-request.md` in the output folder (recording the original user request and scope details at the top), then append the full resource table to it. Reference the file in the chat response.

### 5. Check for Large Scope

If the filtered resource count exceeds **30**, print a warning that lists unique resource types with counts, then automatically proceed to generate all resources. Templates will be split into modules by category. Do not pause for user confirmation.

### 6. Deep Property Extraction

For each discovered resource, extract the **full** resource configuration from Azure.

**6a. Extraction method**

Prefer running the shared script over manual per-resource extraction:

```
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -ResourceGroup <rg> -Enrich -Mode bicep -StripReadOnly -OutFile <path>
```

`-Enrich` fetches full resource detail (`az resource show` per resource) and extracts per-resource-type properties using the mappings in `.github/skills/shared/data/azure-property-paths.json` (`mcpTool` preferred, `fallback` CLI command per resource type, plus `armJsonPath`/composite rules for individual properties). `-Mode bicep` also applies the Step 4 filtering rules automatically.

If `pwsh` or the script is unavailable, see "Fallback: pwsh Unavailable" to enrich and extract properties by hand.

After all resources are extracted, print a single batch summary (e.g., `✅ Extracted 34 resources (3 partial, 2 skipped)`). Do not print per-resource progress lines.

**6b. Property filtering and secrets detection**

The `-StripReadOnly` switch in the Step 6a command removes read-only, computed, and ARM-internal properties (`provisioningState`, `resourceGuid`, `etag`, timestamps, property-level `id`/`name`/`type`, `identity.principalId`, `privateEndpointConnections`, …) and flags secret-bearing properties. The rules live in `.github/skills/shared/data/arm-readonly-properties.json`.

If `pwsh` or the script is unavailable, apply the same rules by hand: strip the `alwaysRemoveAnyDepth` names at any depth and the `alwaysRemoveAtRoot` names at the root of each `properties` bag, apply `removePaths`, and never strip `keepPaths` (`identity.type`, `identity.userAssignedIdentities`) or the deployable `sku`, `kind`, `location`, and `tags`.

**6c. Handling flagged secrets**

The script writes an optional `secrets` array of dotted property paths on each affected resource (see `.github/skills/shared/azure-resource-model.md`). For every flagged path:
- Generate a `@secure()` parameter whose `.bicepparam` value uses `readEnvironmentVariable()` — see `.github/skills/shared/bicep-best-practices.md`
- Add it to the output summary as a "requires manual configuration" item

**6d. Graceful fallback**

If a resource-specific tool fails or is unavailable:
- Log a note: `⚠️ Could not fully extract <resource-name> (<resource-type>) — using list-level information`
- Use the properties available from the initial discovery (Step 3)
- Mark the resource as "partially extracted" in the output
- Do **not** stop execution due to extraction failures

### 7. Analyze Dependencies

Analyze extracted properties to identify relationships between resources — both within the scope and to external resources.

**7a. Internal relationships (resources within the scope)**

Use the `relationships` array already present on each resource in the model produced by `Get-AzureResourceModel.ps1` (`contains`, `connects`, `depends`, `secures` — see `.github/skills/shared/azure-resource-model.md`). These determine module structure and resource ordering in Bicep. *(If pwsh or the script was unavailable in Step 6, see "Fallback: pwsh Unavailable" to detect relationships and their Bicep implications by hand.)*

**7b. External dependencies (resources OUTSIDE the scope)**

These are resources that the in-scope resources depend on but that live in other resource groups, subscriptions, or tenants. They **cannot** be deployed by the generated Bicep — they need separate coordination.

Detect them using the detection patterns and record them in the field shape defined in the "External Dependency Detection" section of `.github/skills/shared/azure-resource-model.md`. The `type` values recorded there drive the dependency templates generated in Step 9.

**7c. Present relationship summary**

Show two tables:
- **Internal Dependencies (N relationships)**: columns Source, Relationship, Target
- **External Dependencies (M dependencies)**: columns External Resource, Type, Required Action, Depended On By

If external dependencies exist, warn: "⚠️ M external dependencies require out-of-scope changes. See `dependencies/README.md` after generation."

### 8. Generate Bicep Templates and Bicepparam File

Generate **all** Bicep files and the `.bicepparam` file in a single pass. Do not wait for user confirmation.

**Before writing any files:**
- Sanitize the scope name for use as a folder name: replace spaces with hyphens, remove characters not in `[a-zA-Z0-9_\-.]`, and truncate to 64 characters. Use the sanitized name as the output folder name and record the original scope name in the README.
- Write all output files to `./<sanitized-scope-name>/` relative to the workspace root.
- If a directory with that name already exists, warn the user and ask whether to overwrite or choose an alternate folder name before writing any files. This overwrite check is the only user confirmation pause permitted during generation. All other steps proceed without confirmation.

Use `.github/skills/shared/azure-resource-configs.md` for per-resource defaults and `.github/skills/shared/bicep-best-practices.md` for generation rules.

**Output structure:**
```
<scope-name>/
├── README.md                     # Summary: verification results, file list, deploy commands, next steps
├── main.bicep                    # Entry point — orchestrates all modules
├── <scope-name>.bicepparam       # User-editable parameter values with comments
├── modules/
│   ├── networking.bicep          # VNets, subnets, NSGs, private endpoints, NICs
│   ├── compute.bicep             # VMs, App Services, Container Apps, Function Apps
│   ├── data.bicep                # SQL, Cosmos DB, Storage Accounts, Key Vault, Redis
│   ├── identity.bicep            # User-assigned managed identities
│   ├── monitoring.bicep          # Log Analytics, Application Insights, action groups
│   └── other.bicep               # Resources not mapping to any above category (generated only if needed)
└── dependencies/
    ├── README.md                 # Summary of all external dependencies
    ├── <dependency-type>.bicep   # Deployable Bicep for each external dependency
    └── <dependency-type>.bicepparam
```

**Bicep generation rules:**

Follow the **Template Structure** and **Bicepparam Comment Guidelines** sections of `.github/skills/shared/bicep-best-practices.md` for `main.bicep`, module, and `.bicepparam` structure. The following rules are specific to reverse-engineering a live environment and override the shared defaults:

| Area | Rule |
|------|------|
| Defaults | Match **current Azure values** — the goal is to reproduce the existing environment, not to apply cost-effective sizing. Still enable secure defaults (HTTPS, TLS 1.2, deny public access with PEs) and note any insecure current value with an upgrade comment |
| `.bicepparam` comments | Extend the shared comment block with the **current Azure value** for the parameter, alongside 2–3 sizing or tier alternatives with relative cost notes. No hard line limit |
| ARM-to-Bicep | Camel-case property names; ARM arrays to Bicep array syntax; `"true"`/`"false"` strings to booleans; inline resource IDs to symbolic refs |

### 9. Generate Out-of-Scope Dependency Bicep Templates

For each external dependency from Step 7b, generate a deployable `.bicep` + `.bicepparam` pair in `dependencies/` and document in `dependencies/README.md`.

**`dependencies/README.md`**: Summary table (External Resource, Resource Group, Dependency Type, Required Action, Depended On By), links to `.bicep`/`.bicepparam`, per-dependency description with deploy/verify commands, and deployment order instructions.

**Per-dependency templates:**

| Dependency Type | Bicep Resources | Key Params |
|-----------------|----------------|------------|
| VNet Peering | Two `virtualNetworkPeerings` resources with `existing` parent VNets | Local/remote VNet names, remote VNet resource ID |
| Private DNS Zone | A record + VNet link with `existing` DNS zone | Zone name, record name, IP, VNet resource ID |
| Log Analytics | RBAC role assignment on workspace | Workspace name, principal ID, role definition ID |
| Key Vault Access | RBAC role assignment on vault | Vault name, principal ID, role definition ID |
| External Subnet | Subnet with `existing` parent VNet | VNet name, subnet name, address prefix, delegations |
| Container Registry | AcrPull role assignment | Registry name, principal ID |
| RBAC Assignment | `Microsoft.Authorization/roleAssignments` | Target resource ID, principal ID, role definition ID |
| DNS Zone | `existing` DNS zone with CNAME or A record | Zone name, record name, value, TTL, record type |
| Hub Route Table | `existing` route table with routes | Route table name, route name, address prefix, next-hop IP/type |
| Any other type | Stub `.bicep` with a comment block explaining the required manual action; no deployable resources | See comment in stub file |

Each template: `targetScope = 'resourceGroup'`, top-of-file comment explaining the dependency, `existing` blocks for parents, follows all Bicep best practices, outputs key resource ID. Only generate templates for detected dependencies.

### 10. Validate Generated Bicep

Run the **full verification ruleset** from `.github/skills/shared/azure-deployment-verification.md`. This is mandatory — do not skip. Check all rule categories: SKU dependencies, resource compatibility, networking, security, regional availability, version currency, Bicep best practices, missing dependencies, and parameter completeness. Present results using the shared verification output format. Auto-fix errors where possible. Do not present code with known errors.

If errors remain after auto-fix attempts, halt delivery of the affected files, present the specific errors to the user with remediation suggestions, and ask whether to proceed with the warnings-only files or stop entirely.

### 11. Write README and Present Output Summary

Write a `README.md` to the output root directory (alongside `main.bicep`) containing:
- **Source** (resource group, subscription)
- **Generated date**
- **Pre-deployment verification results** (pass/warning/error counts and details)
- **Generated Files** table (file path + description for every generated file)
- **Resource counts** (full/partial extraction, excluded)
- **External dependency count** and secret count
- **Deployment commands** (`az deployment group create` and `New-AzResourceGroupDeployment` examples)
- **Next Steps** section pointing to `dependencies/README.md`, post-deploy RBAC steps, DNS verification, and related skills (azv-bicep-whatif, azv-azure-to-diagram, azv-bicep-policy-check)

After writing the README, present the same summary in the chat response.

### 12. Clean Up Intermediate Files

Delete all intermediate extraction files from the output folder. These were used during discovery and property extraction but are not deliverables:

- `extract-*.json` — per-resource CLI output
- `resource-list-raw.json` — initial resource list
- Temporary resource model JSON file — structured resource model used during generation only; delete it before finishing because its content is captured in the Bicep templates and README

Only final deliverables should remain: `main.bicep`, `.bicepparam`, `modules/`, `dependencies/`, `README.md`, and `original-request.md`.

## Important Notes

- This skill operates **independently** — no diagram or prior AzVerify output required
- `.bicepparam` defaults to **current Azure values** — deploying recreates the same resources
- External dependencies are standalone `.bicep`/`.bicepparam` pairs in `dependencies/`
- All files generated in a **single pass** — no intermediate confirmation
