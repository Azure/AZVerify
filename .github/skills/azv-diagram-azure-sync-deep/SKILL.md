---
name: azv-diagram-azure-sync-deep
description: Deep-compare a Draw.io Azure architecture diagram against a live Azure environment — checks both resource existence AND every tracked configuration property (SKU, size, settings, etc.) against expected values. Reports existence drift and property-level drift with severity classification, and offers per-property resolution.
license: MIT
metadata:
  author: AzVerify
  version: "1.0"
  project: AzVerify
---

Deep-compare a Draw.io Azure architecture diagram against a live Azure environment — detecting both existence-level drift (missing/extra resources) and property-level drift (configuration differences on every tracked property).

> **When to use this skill vs `diagram-azure-sync`:**
> - Use `diagram-azure-sync` for a quick existence check — are the right resources deployed?
> - Use `diagram-azure-sync-deep` (this skill) when you need to verify that every configuration property (SKU, tier, size, security settings, etc.) matches expected values. This skill retrieves full resource properties from Azure and compares them against diagram values and defaults.

**Input**: A Draw.io diagram file (`.drawio` or `.drawio.xml`) and an Azure scope — a resource group name or subscription ID. The user can specify both, or the skill will prompt for missing inputs.

**Tools required**: File system tools (read/write files), Azure MCP server tools (`mcp_azure_group_resource_list`, `mcp_azure_compute`, `mcp_azure_storage`, `mcp_azure_subscription_list`, etc.), Draw.io MCP (`mcp_drawio_create_diagram` or `mcp_draw_io_create_diagram`)

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-stencil-mapping.json` — Azure resource type to Draw.io stencil mapping (used for reverse-lookup and diagram generation)
- `.github/skills/shared/azure-deployment-verification.md` — **Pre-deployment verification rules (MUST run before generating Azure update scripts)**
- `.github/skills/shared/azure-resource-configs.md` — Per-resource-type configuration schemas with defaults and auto-detection rules
- `.github/skills/shared/data/azure-property-paths.json` — Azure Property Retrieval Mapping (MCP tools, CLI fallbacks, ARM JSON paths, severity classifications)

**Shared procedures** (MUST follow):
- `.github/skills/shared/procedures/azure-authentication.md` — Azure session check procedure
- `.github/skills/shared/procedures/diagram-parsing.md` — Diagram-to-resource-model parsing procedure
- `.github/skills/shared/procedures/resource-matching.md` — Resource matching algorithm
- `.github/skills/shared/procedures/resource-filtering.md` — Resource exclusion lists (use "Exclude for Diagrams" column)

---

## Steps

### 1. Check Azure Authentication

Follow the procedure in `.github/skills/shared/procedures/azure-authentication.md`. **HARD GATE** — stop if not authenticated.

### 2. Accept Inputs

Identify the Draw.io diagram and the Azure scope to compare against.

#### 2a. Identify the Draw.io Diagram

**If the user specifies a file path:**
- Verify the file exists and is a `.drawio` or `.drawio.xml` file
- Read the file contents

**If no file is specified:**
- Search the workspace for `.drawio` files
- If exactly one is found, use it (announce which file)
- If multiple are found, present the list and ask the user to select one
- If none are found, ask the user to provide a diagram file

#### 2b. Identify the Azure Scope

**If the user specifies a resource group:**
- Use that resource group as the comparison scope
- Verify the resource group exists using Azure MCP tools

**If the user specifies a subscription:**
- Use that subscription as the comparison scope
- Note: subscription-level comparison can be noisy — warn the user

**If no scope is specified:**
- Check if the diagram contains resource group containers — if so, use those resource group names as the scope
- If the resource group name(s) can be inferred from the diagram, confirm with the user: "The diagram shows resources in resource group `<name>`. Should I compare against that resource group?"
- If the scope cannot be inferred, ask the user: "Which Azure resource group or subscription should I compare this diagram against?"

### 3. Parse Diagram into Resource Model

Follow the procedure in `.github/skills/shared/procedures/diagram-parsing.md` to parse the Draw.io XML into a structured resource model.

Display the parsed resource model as a table with columns: #, Resource, Type, Container.

### 4. Discover Azure Environment

Query the Azure scope to build a resource model of what is actually deployed.

**Discovery process:**

1. **List all resources in scope**:
   - For resource group scope: Use `mcp_azure_group_resource_list` to get all resources in the specified resource group
   - For subscription scope: Use `mcp_azure_subscription_list` to get subscriptions, then list resources across the target subscription

2. **Build the Azure resource model**: For each discovered resource, create a resource model entry:
   ```json
   {
     "id": "<resource-name-slug>",
     "type": "<Microsoft.Provider/resourceType>",
     "name": "<resource-name>",
     "resourceGroup": "<resource-group-name>",
     "location": "<region>",
     "properties": {},
     "relationships": []
   }
   ```

3. **Enrich with resource-type-specific details** where available:
   - Use `mcp_azure_compute` for VM details (size, OS, status)
   - Use `mcp_azure_storage` for Storage Account details (SKU, kind, access tier)
   - Use Azure MCP networking tools for VNet, subnet, NSG details
   - Use Azure MCP database tools for SQL, Cosmos DB details
   - Use Azure MCP web/app tools for App Service, Function App details

4. **Discover relationships**:
   - VNets → Subnets (containment from resource hierarchy)
   - Resources → Resource Groups (containment)
   - NICs → VMs (connection via NIC's `virtualMachine` property)
   - Private Endpoints → target resources (connection via `privateLinkServiceConnections`)
   - App Services → App Service Plans (dependency)
   - Subnets → NSGs (security association)

5. **Exclude infrastructure-only resources**: Apply the "Exclude for Diagrams" column from `.github/skills/shared/procedures/resource-filtering.md`.

6. **Output the Azure resource model** as a table with columns: #, Resource, Type, Location.

### 4b. Retrieve Full Resource Properties

For each resource that exists in both the diagram and Azure (identified by type + name matching), retrieve all tracked configuration properties.

**Retrieval process:**

1. **Look up the resource type** in `.github/skills/shared/data/azure-property-paths.json` (`resourceTypes[]`) to find:
   - The MCP tool to use (if one exists for this resource type)
   - The `az` CLI fallback command
   - The ARM JSON paths for each tracked property

2. **Query Azure for full properties**:
   - **Primary**: Use the listed MCP tool (e.g., `mcp_azure_compute` for VMs, `mcp_azure_storage` for storage accounts)
   - **Fallback**: If no MCP tool is listed or the MCP call fails, use the documented `az` CLI fallback command (e.g., `az vm show --ids <resourceId> -o json`)

3. **Extract property values** using the ARM JSON paths from the mapping table. For each tracked property:
   - Navigate the JSON response using the documented path (e.g., `properties.hardwareProfile.vmSize`)
   - Apply SKU extraction rules for `skuName`/`skuTier` properties (see `globalSkuRules[]` in `azure-property-paths.json`)
   - Apply composite property rules where noted (e.g., VM `osImage` assembled from `imageReference` fields)

4. **Populate the resource model**: Store all extracted property values in the resource's `properties` object in the Azure resource model. During this skill's execution, the `properties` field SHALL be fully populated with all tracked properties from `azure-property-paths.json` for matched resources.

5. **Show progress**: Display progress for each resource being queried:
   ```
   Checking properties: my-vm (1/5)...
   Checking properties: my-storage (2/5)...
   ```

6. **Handle failures**: If property retrieval fails for a resource (API error, timeout, insufficient permissions):
   - Mark all properties for that resource as `"unknown"`
   - Log the error and continue with the next resource
   - Do not abort the entire sync over a single resource failure

### Property Value Normalization Rules

Before comparing expected vs actual values, normalize both sides using these rules:

1. **Case-insensitive string comparison** for enum-like values: SKU names, tiers, regions, allocation methods, policy modes. Example: `"Standard_LRS"` matches `"standard_lrs"`.

2. **Boolean normalization**: `true`, `"true"`, `"True"`, `"TRUE"` all normalize to `true`. Same for `false` variants. Compare as booleans, not strings.

3. **Empty collection equivalence**: `[]`, `null`, and absent/undefined properties are all equivalent for array-type properties (e.g., `dataDisks`, `serviceEndpoints`, `securityRules`).

4. **Region name normalization**: Normalize to lowercase without spaces: `"West Europe"` → `"westeurope"`, `"East US 2"` → `"eastus2"`.

5. **Numeric string normalization**: `"30"` and `30` are equivalent. Compare as numbers when the schema type is numeric.

6. **Trailing-suffix normalization**: Strip known suffixes before comparison: `"1.0Gi"` → `"1.0"` for memory values, `"2"` and `"2.0"` are equivalent for CPU cores.

### 5. Compare Models and Identify Drift

Follow the matching algorithm in `.github/skills/shared/procedures/resource-matching.md` to compare diagram resources (Step 3) against Azure resources (Step 4). Use label "Diagram Only" for Model A and "Azure Only" for Model B.

**Property-level comparison (for matched resources):

After existence-level classification, perform property-level drift detection on all resources classified as "In Sync" or "In Sync (name differs)":

1. **Look up the resource type** in `.github/skills/shared/data/azure-property-paths.json` to get the full list of tracked properties with their defaults and severity levels.

2. **Determine expected values** for each property:
   - If the diagram's resource model specifies a value for the property → use the diagram value (source: `diagram`)
   - If the diagram does not specify a value → use the default from `azure-property-paths.json` (source: `default`)

3. **Compare expected vs actual** for every tracked property using the normalization rules from "Property Value Normalization Rules" above:
   - Apply case-insensitive comparison for string/enum values
   - Apply boolean normalization
   - Apply empty-collection equivalence
   - Apply numeric normalization

4. **Record property drifts**: For each property where normalized expected ≠ normalized actual, record:
   - Property name
   - Expected value (and its source: `diagram` or `default`)
   - Actual Azure value
   - Severity level (from the `severity` field in `azure-property-paths.json`)

   For each property where normalized expected **=** normalized actual, record it separately as **confirmed in sync** — these will appear in the report's "Confirmed In Sync" table, not in the drift table. **Never mix matching and drifting properties in the same table.**

5. **Handle "unknown" properties**: If a property's actual value is `"unknown"` (retrieval failed in Step 4b), mark it as `⚠️ Unknown` in the drift report — do not classify it as matching or drifting.

6. **Update resource classification**: A matched resource now has a refined status:
   - **In Sync (all properties match)** — existence match AND all tracked properties match
   - **In Sync (properties drifted)** — existence match but one or more tracked properties differ
   - **In Sync (name differs, all properties match)** — single-instance type match with name mismatch, all properties match
   - **In Sync (name differs, properties drifted)** — single-instance type match with name mismatch, properties differ

### 6. Present Drift Report

Display a clear drift report summarizing all differences — both existence-level and property-level.

**Report format (two-tier):**

**Tier 1 — Summary table** with columns: Resource, Type, Existence, Critical, Warning, Info.

**Tier 2 — Detailed property diffs** (shown for each resource with property drifts):

> **CRITICAL**: The property drift tables MUST contain **only properties where expected ≠ actual** (after normalization). Matching properties belong in a separate "Confirmed In Sync" table with columns: Property, Value (both sides).

Property drift table columns: Property, Expected, Actual, Severity, Source.

**If fully in sync** (existence AND properties): Report "Fully in sync" and stop.

**If drift is detected**, proceed to Step 7.

### 7. Offer Resolution Options

Present resolution options based on the type of drift detected:

| Drift Type | Options Offered |
|---|---|
| Existence only | Update Diagram, Update Azure, Selective, No action |
| Property only | Resolve Property Drifts, No action |
| Both | Update Diagram, Update Azure, Selective (resources), Resolve Property Drifts, No action |

Wait for the user's choice before proceeding.

### 8. Resolution: Update Diagram

Follow the same procedure as **azv-diagram-azure-sync** Step 8 — confirm destructive operations, generate updated diagram via Draw.io MCP, present result.

### 9. Resolution: Update Azure

Follow the same procedure as **azv-diagram-azure-sync** Step 9 — confirm destructive operations, run deployment verification, generate Bicep for resources to create, generate deletion scripts for resources to remove.

### 10. Resolution: Selective Updates

Follow the same procedure as **azv-diagram-azure-sync** Step 10 — present per-resource choices, apply decisions in grouped batches (diagram updates + Azure updates), present combined result.

### 11. Resolution: Property Drifts

If the user chooses to resolve property drifts:

**11a. Present per-resource property choices**

For each resource with property drifts, present a table with columns: #, Property, Expected, Actual, Severity, Action (Update Azure / Accept Azure / Skip). Wait for per-property decisions.

**11b. Generate targeted update scripts**

For "Update Azure" properties:
- Generate a **Bicep snippet** per resource using `existing` references, targeting only drifted properties
- Generate **CLI commands** as an alternative (e.g., `az vm resize`, `az storage account update`)
- When vmSize changes, note VM deallocation is required

**11c. Handle "Accept Azure" decisions**

Update the `.bicepparam` file parameter values to reflect actual Azure values. Present for confirmation before writing.

**11d. Confirmation gate**

Display summary tables of all resolutions (Update Azure, Accept Azure, Skipped) across all resources. Wait for explicit confirmation before applying.

**11e. Present output**

Show generated files and parameter updates.

### 12. No Action

Confirm no changes were made and suggest related skills (diagram-azure-sync, diagram-to-bicep, sketch-to-diagram).

---

## Important Notes

- This skill operates **independently** — it does not require sketch-to-diagram or diagram-to-bicep.
- **Destructive operations always require explicit confirmation.**
- Property-level drift compares all tracked properties from `azure-property-paths.json`, using defaults as expected values when the diagram doesn't specify a property. Properties are classified by severity (Critical/Warning/Info) and compared using normalization rules.
- Filter infrastructure resources per `.github/skills/shared/procedures/resource-filtering.md`.
- Generated update scripts include their own confirmation prompts as defense in depth.
