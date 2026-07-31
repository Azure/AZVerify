---
name: azv-azure-to-bicep
description: Reverse-engineer a live Azure scope (resource group or filtered subscription) into deployment-ready, modular Bicep templates with parameter files. Use when the user wants to bring existing Azure infrastructure under Bicep/IaC management.
license: MIT
compatibility: Prefers PowerShell 7 (pwsh) and Azure CLI (az); falls back to the Azure MCP server and inline procedures when unavailable. Requires an authenticated Azure session (CLI, Az PowerShell, or Azure MCP).
---

Discover resources in a live Azure scope, extract their full configuration, and generate deployment-ready Bicep templates with modular structure, user-editable parameter files, and dependency documentation for external resources.

**Input**: An Azure scope — a resource group name (primary) or a subscription ID with optional resource type filter. Optionally, a target environment hint (dev/prod) to influence default sizing in the parameter file.

**Tools required**: File system tools (read/write files), Terminal (for running `az` CLI commands), Azure MCP server tools (`mcp_azure_group_resource_list`, `mcp_azure_compute`, `mcp_azure_storage`, `mcp_azure_subscription_list`, etc.), Bicep MCP server (for best-practice validation via `get_bicep_best_practices` and `get_az_resource_type_schema`)

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-resource-configs.md` — Per-resource-type configuration schemas with defaults
- `.github/skills/shared/azure-deployment-verification.md` — **Pre-deployment verification rules (MUST run before presenting results)**

**Shared procedures** (MUST follow):
- `.github/skills/shared/bicep-best-practices.md` — **Bicep generation rules, defaults, and security settings (MUST read before generating Bicep)**
- `.github/skills/shared/version-currency.md` — **Version verification rules (MUST verify before generating code)**
- `.github/skills/shared/procedures/azure-authentication.md` — Azure session check procedure
- `.github/skills/shared/procedures/resource-filtering.md` — Resource exclusion lists (use "Exclude for Bicep" column)
- `.github/skills/bicep/SKILL.md` — Bicep conventions for this repository
- `.github/skills/powershell/SKILL.md` — PowerShell scripting conventions

## Output Budget Rules

**This skill frequently handles 20-40+ resources. To avoid hitting the LLM response length limit, follow these rules strictly:**

1. **Save data to files, don't print it.** After discovery (Step 3) and property extraction (Step 6), you may write the resource model to a temporary JSON file. Reference the temporary file in subsequent steps.
2. **Minimize inline tables.** Never print full resource tables with more than 10 rows. Print a count summary and write full tables to `original-request.md`.
3. **No per-resource progress messages.** During extraction, print a single summary after the batch (e.g., "Extracted 34 resources (3 partial)").
4. **Batch CLI calls.** Use `az resource list` with `--query` for bulk discovery rather than per-resource MCP calls.
5. **Build Bicep files directly.** Write generated code to files. Do NOT echo full Bicep/bicepparam content in the response — show only file paths and a summary of what was generated.
6. **Delete intermediate files.** After generation is complete, delete all intermediate extraction files (`extract-*.json`, `resource-list-raw.json`, and the temporary resource model JSON file) from the output folder. Never leave the resource model JSON behind after the skill completes. Only final deliverables should remain: `main.bicep`, `.bicepparam`, `modules/`, `dependencies/`, `README.md`, and `original-request.md`.

## Steps

### 1. Check Azure Authentication

Run `pwsh .github/skills/shared/scripts/Test-AzureAuth.ps1` — see `.github/skills/shared/procedures/azure-authentication.md` for the script contract. The script writes a JSON status object to stdout and exits non-zero when no Azure session is found. A **non-zero exit code is a HARD GATE**: present the authentication instructions from the contract doc and stop. *(If pwsh or the script is unavailable, follow the MCP auth probe fallback defined in the azure-authentication.md contract before stopping.)*

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

Use `mcp_azure_group_resource_list` to enumerate all resources in the resource group. For each discovered resource, extract: `id`, `name`, `type`, `location`, `tags`, `sku` (if present).

Display progress:
```
⏳ Discovering resources in resource group `<rg-name>`...
```

**3b. Subscription scope**

Use Azure MCP tools or `az resource list --subscription <sub-id>` to discover resources across the subscription. Apply any user-specified resource type filters.

**3c. Handle empty results**

If no resources are found after discovery:
```
## No Resources Found

No resources were found in `<scope-name>`.

If you expected resources here, verify:
- The resource group name is spelled correctly
- You're connected to the correct subscription (`az account show`)
- Resources have been deployed to this scope
```

If the resource group exists but discovery returns zero results, also run:
```
az role assignment list --assignee $(az account show --query id -o tsv) --scope /subscriptions/<sub-id>/resourceGroups/<name>
```
If the authenticated identity has no Reader or higher role, warn: “The authenticated identity may lack read permissions on this resource group.”

- Stop execution

### 4. Filter Non-Deployable Resources

Run `pwsh .github/skills/shared/scripts/Select-AzureResources.ps1 -InputFile <resource-model.json> -Mode bicep` — see `.github/skills/shared/procedures/resource-filtering.md` for the script contract. The script applies the shared exclusion rules, writes the filtered resource model JSON to stdout, and should be treated as the source of truth for the remaining steps. *(If pwsh or the script is unavailable, follow the inline fallback in the procedure doc above.)*

> **Key difference from diagram skills**: Bicep keeps deployable monitoring/identity resources (Application Insights, Log Analytics, action groups, user-assigned identities, diagnostic settings). See the "Exclude for Bicep" column in the shared filtering reference.

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

For each resource, attempt the preferred tool first. If the preferred tool returns an error or is not configured in the current session, use the fallback CLI command listed in the table:

| Resource Type | Preferred Tool | Fallback |
|---------------|---------------|----------|
| `Microsoft.Compute/virtualMachines` | `mcp_azure_compute` | `az vm show --ids <id>` |
| `Microsoft.Storage/storageAccounts` | `mcp_azure_storage` | `az storage account show --ids <id>` |
| `Microsoft.Web/sites` | Azure MCP | `az webapp show --ids <id>` |
| `Microsoft.Network/virtualNetworks` | Azure MCP | `az network vnet show --ids <id>` |
| All other types | — | `az resource show --ids <id>` |

For App Services, also extract app settings separately:
- `az webapp config appsettings list --ids <id>`

After all resources are extracted, print a single batch summary (e.g., `✅ Extracted 34 resources (3 partial, 2 skipped)`). Do not print per-resource progress lines.

**6b. Property filtering — remove read-only ARM properties**

Strip properties that are read-only, computed, or ARM-internal before converting to Bicep.

**Precedence order: Always remove > Remove conditionally > Keep.** If a property matches any Always remove rule, strip it regardless of which other category it might fall under.

**Always remove:**
- `provisioningState`
- `resourceGuid`
- `etag`
- `id` (at property level — the top-level resource ID is kept for reference only)
- `name` (at property level — derived from the Bicep resource declaration)
- `type` (at property level — derived from the Bicep resource type)
- `createdDate`, `createdTime`, `lastModifiedDate`, `lastModifiedTime`, `changedTime`
- `uniqueId`
- `tenantId` (in resource properties — not in identity blocks)

**Remove conditionally:**
- `identity.principalId` and `identity.tenantId` — these are outputs of identity assignment, not inputs
- `privateEndpointConnections` — these are read-only; private endpoints are deployed as separate resources
- `networkProfile.resourceGuid`

**Keep:**
- `identity.type` and `identity.userAssignedIdentities` — these ARE inputs
- `sku`, `kind`, `location`, `tags` — all deployable
- All properties under `properties` that are not in the remove list

**6c. Secrets detection**

Scan all extracted properties for sensitive values that cannot be exported:

**Patterns indicating secrets:**
- Properties named `*password*`, `*secret*`, `*key*`, `*connectionString*`, `*accessKey*`
- Values that are masked (e.g., `"****"`, empty strings where a value is expected)
- App settings containing connection strings, instrumentation keys, or SAS tokens

For each detected secret:
- Record the property path (e.g., `properties.administratorLoginPassword`)
- Mark it for `@secure()` parameter generation with `readEnvironmentVariable()` in the `.bicepparam`
- Add to the output summary as a "requires manual configuration" item

**6d. Graceful fallback**

If a resource-specific tool fails or is unavailable:
- Log a note: `⚠️ Could not fully extract <resource-name> (<resource-type>) — using list-level information`
- Use the properties available from the initial discovery (Step 3)
- Mark the resource as "partially extracted" in the output
- Do **not** stop execution due to extraction failures

### 7. Analyze Dependencies

Analyze extracted properties to identify relationships between resources — both within the scope and to external resources.

**7a. Internal relationships (resources within the scope)**

These determine module structure and resource ordering in Bicep.

| Pattern | Detection Method | Bicep Implication |
|---------|-----------------|-------------------|
| **Subnet membership** | NIC's `ipConfigurations[].subnet.id` references a VNet/subnet in scope | Subnet declared inside VNet module; NIC references subnet via symbolic ref |
| **Private endpoint links** | PE's `privateLinkServiceConnections[].privateLinkServiceId` references a resource in scope | PE in networking module with `dependsOn` on target resource |
| **App Service Plan binding** | Web App's `serverFarmId` references an ASP in scope | ASP and Web App in same module; Web App depends on ASP |
| **NIC-to-VM binding** | VM's `networkProfile.networkInterfaces` references a NIC in scope | NIC deployed before VM; VM references NIC via symbolic ref |
| **Diagnostic settings** | Resource's diagnostic settings target a Log Analytics workspace in scope | Diagnostic setting as child resource with `parent:` |
| **Key Vault references** | App settings contain `@Microsoft.KeyVault(SecretUri=...)` referencing a vault in scope | Output Key Vault URI; Web App depends on Key Vault |
| **App Insights connection** | App settings contain `APPLICATIONINSIGHTS_CONNECTION_STRING` matching an AI resource in scope | Web App depends on Application Insights; connection string as output |
| **NSG-to-subnet binding** | Subnet's `networkSecurityGroup.id` references an NSG in scope | NSG deployed before subnet; subnet references NSG |
| **User-assigned identity** | Resource's `identity.userAssignedIdentities` references an identity in scope | Identity deployed first; resource references identity |

**7b. External dependencies (resources OUTSIDE the scope)**

These are resources that the in-scope resources depend on but that live in other resource groups, subscriptions, or tenants. They **cannot** be deployed by the generated Bicep — they need separate coordination.

**Detection patterns:**

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

When traversing a detection path, treat any null or missing intermediate node as "dependency not present" for that pattern — do not flag as an extraction error.

For each external dependency, record:
- `type` — dependency category from the table above
- `resourceId` — full ARM resource ID of the external resource
- `resourceType` — Azure resource type
- `resourceName` — display name
- `dependedOnBy` — list of in-scope resources that depend on this
- `requiredAction` — what configuration change is needed on the external resource
- `ownerHint` — infer from resource tags using this priority: `owner` > `team` > `costcenter`. If none of these tags exist, set to `null`

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
- If a directory with that name already exists, warn the user and ask whether to overwrite or choose an alternate folder name before writing any files.

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

| Area | Rule |
|------|------|
| `main.bicep` | `targetScope = 'resourceGroup'`; all params with `@description()`; `@allowed()` where fixed values apply; `@secure()` for sensitive params; module refs for each category (do not set the `name:` property inside module blocks — omit the ARM deployment name; the symbolic name before `=` is still required); outputs for key IDs/endpoints |
| Module files | Only generate modules with resources; each module receives only needed params; use `parent:` for child resources; `existing` blocks for cross-file parent refs; symbolic refs (`foo.id`); secure defaults |
| `.bicepparam` | `using 'main.bicep'`; all param values; add a comment block per param (no hard line limit) covering: (1) what it controls, (2) the current Azure value, (3) 2–3 sizing or tier alternatives with relative cost notes. For secret params, replace the value with `readEnvironmentVariable("PARAM_NAME")` and note the expected environment variable name |
| Param naming | camelCase, descriptive (e.g., `vmSize`, `appServicePlanSkuName`) |
| Defaults | Match **current Azure values** (goal: reproduce existing environment); enable secure defaults (HTTPS, TLS 1.2, deny public access with PEs); note insecure current values with upgrade comments |
| ARM-to-Bicep | Camel-case property names; arrays to Bicep syntax; `"true"`/`"false"` strings to booleans; inline resource IDs to symbolic refs |
| Module structure | If a resource does not fit the five defined module categories (networking, compute, data, identity, monitoring), place it in `modules/other.bicep`. List uncategorized resource types in the README under a "Manually Reviewed Resources" section. |

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
- Generated Bicep uses **secure defaults** — upgrades insecure settings with comments
- MUST call Bicep MCP `get_bicep_best_practices` and follow shared procedures before generating code. If the Bicep MCP server is unavailable, fall back to the rules in `.github/skills/shared/bicep-best-practices.md` and note in the README: "Bicep MCP validation was skipped — manual review recommended."
