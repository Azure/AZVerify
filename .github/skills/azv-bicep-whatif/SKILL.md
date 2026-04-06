---
name: azv-bicep-whatif
description: Compare Bicep templates against a live Azure environment by querying Azure directly and parsing the Bicep template. Presents categorized change results (Create, Modify, Delete, No Change) without deploying anything. Does NOT use ARM what-if.
license: MIT
metadata:
  author: AzVerify
  version: "1.0"
  project: AzVerify
---

Compare Bicep templates against a live Azure environment by querying Azure directly and parsing the Bicep template. Reports resources that will be created, modified, deleted, or left unchanged — without using ARM what-if.

> **Approach**: This skill does NOT use `az deployment group what-if`. Instead it:
> 1. Parses the Bicep template and parameter file to build an **expected resource model**
> 2. Queries Azure directly using `az resource list` and per-resource `az <service> show` commands to build an **actual resource model**
> 3. Compares both models to identify existence-level and property-level differences

**Input**: A solution folder containing Bicep templates (`main.bicep`) and a `.bicepparam` file, plus an Azure target scope (resource group name or subscription ID). The user can specify these, or the skill will auto-discover and prompt for missing inputs.

**Tools required**: File system tools (read files), Terminal (for running `az` CLI commands), Azure MCP server tools

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-resource-configs.md` — Per-resource-type configuration schemas (useful for interpreting property changes)

**Shared procedures** (MUST follow):
- `.github/skills/shared/procedures/azure-authentication.md` — Azure session check procedure
- `.github/skills/shared/procedures/bicep-parsing.md` — Bicep template parsing procedure

---

## Steps

### 1. Check Azure Authentication

Follow the procedure in `.github/skills/shared/procedures/azure-authentication.md`. **HARD GATE** — stop if not authenticated.

### 2. Accept Inputs

Identify the solution folder, the Bicep template, the parameter file, and the target scope.

#### 2a. Identify the Solution Folder

**If the user specifies a folder path:**
- Verify the folder exists
- Use it as the solution folder

**If no folder is specified:**
- Search the workspace for folders containing a `main.bicep` file
- If exactly one is found, use it (announce which folder)
- If multiple are found, present the list and ask the user to select one
- If none are found, ask the user to provide a solution folder

#### 2b. Identify the Bicep Template

- Verify `main.bicep` exists in the solution folder
- If not found, report an error:
```
## No Bicep Template Found

No `main.bicep` file found in `<folder-path>`.
This skill requires a Bicep template to run the what-if analysis.
```
- Stop execution

#### 2c. Identify the Parameter File

**If exactly one `.bicepparam` file exists in the solution folder:**
- Use it as the parameter file (announce which file)

**If multiple `.bicepparam` files exist:**
- Present the list and ask the user to select one:
```
## Multiple Parameter Files Found

Found multiple `.bicepparam` files in `<folder-path>`:
1. `app-dev.bicepparam`
2. `app-prod.bicepparam`

Which parameter file should I use? (1/2)
```
- Wait for user selection

**If no `.bicepparam` file exists:**
- Warn the user:
```
⚠️ No `.bicepparam` file found in `<folder-path>`. Default parameter values from `azure-resource-configs.md` will be used as expected values.
```
- Proceed without a parameter file

#### 2d. Identify the Target Scope

**If the user specifies a resource group name:**
- Use it as the target scope
- Verify the resource group exists: run `az group show --name <name>` — if this fails, report an error and stop

**If the user specifies a subscription ID:**
- Use it as the target scope for a subscription-level comparison

**If no scope is specified, try to infer it:**

1. **From the `.bicepparam` file**: Look for a `using` declaration or comments indicating the target resource group
2. **If a resource group name is found**, propose it:
```
The `.bicepparam` file references resource group `<name>`. Use this as the target scope? (yes/no)
```
3. **If no scope can be inferred**, ask the user:
```
Which Azure resource group should I compare the templates against?
```
- Wait for user input

### 3. Parse Templates into Expected Resource Model

Read the Bicep template and parameter file to build an **expected resource model** — what the templates declare should exist.

**3a. Read and parse the `.bicepparam` file**

Read the `.bicepparam` file and extract all parameter values. These are the user-specified values that override defaults. For each `param <name> = <value>` line, record the name and resolved value.

**3b. Read and parse `main.bicep` and all module files**

Read `main.bicep` and every Bicep module it references in `modules/`. For each resource block that is either declared inline or inside a module, extract:

- **Resource type** (e.g., `Microsoft.Web/sites`)
- **Resource name** — resolve from parameter values in the `.bicepparam` file if the name is a parameter reference (e.g., `name: appServiceName` → resolve `appServiceName` to its value)
- **Key properties** — extract any properties that map to tracked properties in `.github/skills/shared/azure-resource-configs.md` for this resource type (e.g., `sku.name`, `properties.siteConfig.linuxFxVersion`, `properties.httpsOnly`)
- **Relationships** — note explicit references between resources (e.g., App Service → App Service Plan via `serverFarmId`)

For properties that reference parameters (e.g., `linuxFxVersion: appServiceRuntimeStack`), resolve them using the `.bicepparam` values. If the parameter has no value in `.bicepparam`, use the default from `azure-resource-configs.md`.

**3c. Build the expected resource model**

Produce a structured model (as defined in `.github/skills/shared/azure-resource-model.md`) with all declared resources and their resolved property values. This is the "desired state" from the templates.

Display a summary of what was parsed:

```
## Template Resources

Parsed **N resources** from `<solution-folder>/main.bicep`:

| # | Resource | Type | Key Properties |
|---|----------|------|----------------|
| 1 | vnet-01 | Microsoft.Network/virtualNetworks | addressPrefix: 10.0.0.0/16 |
| 2 | vm-01 | Microsoft.Compute/virtualMachines | vmSize: Standard_B2s |
| 3 | webapp-azverify | Microsoft.Web/sites | runtime: DOTNET\|10.0, httpsOnly: true |
```

### 4. Check Resource Provider Registration

Before querying Azure, verify that all resource providers required by the Bicep template are registered in the active subscription. Unregistered providers will cause deployment failures.

**4a. Extract required provider namespaces**

From the expected resource model (Step 3), extract a unique list of top-level resource provider namespaces. Derive the namespace from each resource type by taking the first segment (e.g., `Microsoft.Compute/virtualMachines` → `Microsoft.Compute`, `Microsoft.Network/virtualNetworks` → `Microsoft.Network`).

**4b. Query registered providers**

Run:
```bash
az provider list --query "[?registrationState=='Registered'].namespace" -o json
```

This returns all currently registered provider namespaces in the subscription.

**4c. Compare and report**

Compare the required namespaces (4a) against the registered namespaces (4b) using case-insensitive matching.

**If all providers are registered:**
- Continue to Step 5 (no message needed)

**If one or more providers are NOT registered:**
- Display a warning with registration commands:

```
## ⚠️ Unregistered Resource Providers

The following resource providers are **required by the Bicep template** but are **not registered** in subscription `<sub-name>` (`<sub-id>`). Deployment will fail unless they are registered first.

| # | Provider Namespace | Required By |
|---|-------------------|-------------|
| 1 | Microsoft.App | my-container-app (Microsoft.App/containerApps) |
| 2 | Microsoft.Cache | my-redis (Microsoft.Cache/redis) |

**To register the missing providers, run:**
```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.Cache
```

> **Note:** Provider registration can take a few minutes. Check status with:
> ```bash
> az provider show --namespace <namespace> --query registrationState -o tsv
> ```
```

- **Continue execution** — this is a warning, not a hard gate. The what-if comparison is still valuable for planning.

### 5. Query Azure for Actual Resource Model

Query the target resource group to build an **actual resource model** — what is currently deployed in Azure.

**5a. List all resources in the target scope**

Run:
```bash
az resource list --resource-group <rg-name> -o json
```

This returns all resources currently in the resource group. Build an initial resource model from the results.

**Exclude infrastructure-only resources** that are auto-created by Azure and not declared in Bicep templates:
- `Microsoft.Compute/disks` that are OS disks (managed by VMs)
- `Microsoft.Network/networkInterfaces` that are PE-managed NICs (where `managedBy` is set to a Private Endpoint)
- `Microsoft.Network/networkWatchers` — auto-created by Azure
- `microsoft.alertsManagement/smartDetectorAlertRules` — auto-created
- `Microsoft.Portal/dashboards` — portal artifacts

**5b. Retrieve full properties for each resource**

For each resource, retrieve full properties using the most specific CLI command available:
- Use resource-specific commands where available: `az vm show`, `az webapp show`, `az appservice plan show`, `az network vnet show`, `az network vnet subnet show`, `az network nic show`, `az network private-endpoint show`, `az network private-dns zone show`, `az storage account show`, `az keyvault show`, `az redis show`, `az cosmosdb show`, `az sql server show`, `az acr show`, `az containerapp show`
- Fall back to `az resource show --ids <resourceId> -o json` for child resources or types without specific CLI commands
- All commands use `--ids <resourceId> -o json`

Show progress: `Querying Azure resources (1/N): vnet-01...`

**5c. Extract tracked properties from query results**

For each resource, extract the property values that correspond to the tracked properties in `azure-resource-configs.md` for that resource type. Use the ARM JSON paths from the config schema to navigate the JSON response.

### 6. Compare Models and Classify Changes

Compare the expected resource model (Step 3) against the actual Azure resource model (Step 5) to classify each resource.

**6a. Existence-level classification**

Match resources by type AND name (case-insensitive). Classify each resource as:
- **Create** — in the template but NOT in Azure (resource will be created when deployed)
- **Modify** — in both template and Azure, but with property differences
- **Delete** — in Azure but NOT in the template (resource would be removed if template is authoritative)
- **No Change** — in both template and Azure, with all tracked properties matching

**Matching rules:**
- Match by resource type and name (case-insensitive)
- For child resources (subnets, DNS zone links, etc.), match within their parent's context
- If only one resource of a given type exists in each model and names differ slightly, match them — report as "Modify (name differs)"

**6b. Property-level comparison (for matched resources)**

For resources matched in both models, compare each tracked property from `azure-resource-configs.md`:

1. **Expected value**: use the resolved value from the template (Step 3b); if not specified, use the default from `azure-resource-configs.md`
2. **Actual value**: the value retrieved from Azure (Step 5c)
3. Apply **normalization rules** before comparing:
   - Case-insensitive string comparison for enum-like values (SKU names, tiers, regions)
   - Boolean normalization: `true`/`"true"`/`"True"` all equal `true`
   - Empty collection equivalence: `[]`, `null`, absent → all equivalent for array properties
   - Numeric string normalization: `"30"` equals `30`
4. If normalized expected ≠ normalized actual, record as a **property difference** with:
   - Property name
   - Current value (Azure)
   - Expected value (template)
   - Severity from `azure-resource-configs.md`

**6c. Classify final change type**

After property comparison, refine the classification:
- **No Change** — resource exists in Azure and all tracked properties match the template
- **Modify** — resource exists in Azure but one or more tracked properties differ (list the diffs)
- **Create** — resource is in the template but not found in Azure
- **Delete** — resource is in Azure but not in the template

### 7. Present Change Report

Display a categorized comparison report.

**Header** (always shown): Title, target scope, template/parameters paths, summary table with counts per category (🆕 Create, ✏️ Modify, 🗑️ Delete, ✅ No Change).

**If no changes**: Show "✅ No changes — all template resources match Azure" and stop.

**Per-category sections**:
- **🆕 Create**: Table of resources in template but not in Azure (columns: #, Resource, Type, Resource Group)
- **✏️ Modify**: Per-resource property diff tables (columns: Property, Current Azure Value, Template Value, Severity). Severity levels from `azure-resource-configs.md`.
- **🗑️ Delete**: Table of resources in Azure but not in template, with warning about authoritative deployment
- **✅ No Change**: Collapsible `<details>` section listing matched resources

### 8. Offer Next Steps

If deletions detected, warn user to verify intentional exclusions and check diagram with azv-bicep-diagram-sync.

When changes exist, suggest: deploy command (`az deployment group create`), review Critical severity items, and sync check with azv-bicep-diagram-sync.
