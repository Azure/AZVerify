---
name: azv-diagram-azure-sync
description: Compare a Draw.io Azure architecture diagram against a live Azure environment to detect drift. Supports quick mode (existence check) and deep mode (full property-level comparison). Reports differences and offers resolution — update the diagram, update Azure, or selectively resolve per resource.
license: MIT
metadata:
  author: AzVerify
  version: "1.0"
  project: AzVerify
---

Compare a Draw.io Azure architecture diagram against a live Azure environment and resolve drift. Supports two modes: **quick** (existence-level) and **deep** (existence + property-level comparison against all tracked configuration properties).

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

Identify the Draw.io diagram, the Azure scope, and the comparison depth.

#### 2a. Identify Comparison Depth

Determine the depth mode from the user's request:
- **Quick** (default): Existence-level comparison only — are the right resources deployed?
- **Deep**: Existence + property-level comparison — checks every tracked configuration property (SKU, tier, size, security settings) against expected values from `azure-property-paths.json`

If the user says "deep", "detailed", "full", "property", or "configuration" → use deep mode. Otherwise default to quick.

#### 2b. Identify the Draw.io Diagram

**If the user specifies a file path:**
- Verify the file exists and is a `.drawio` or `.drawio.xml` file
- Read the file contents

**If no file is specified:**
- Search the workspace for `.drawio` files
- If exactly one is found, use it (announce which file)
- If multiple are found, present the list and ask the user to select one
- If none are found, ask the user to provide a diagram file

#### 2c. Identify the Azure Scope

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

### 5. Compare Models and Identify Drift

Follow the matching algorithm in `.github/skills/shared/procedures/resource-matching.md` to compare diagram resources (Step 3) against Azure resources (Step 4). Use label "Diagram Only" for Model A and "Azure Only" for Model B.

#### 5b. Deep Mode Only: Retrieve and Compare Properties

**Skip this step in quick mode.**

For each resource matched in both models (In Sync or In Sync with name difference):

1. **Retrieve full properties** from Azure using the Azure Property Retrieval Mapping in `.github/skills/shared/data/azure-property-paths.json`. Use the listed MCP tool (primary) or `az` CLI command (fallback) for each resource type. Extract all tracked properties using the ARM JSON paths specified in the mapping.

2. **Determine expected values**: Use diagram-specified values if available; otherwise use defaults from `azure-property-paths.json`.

3. **Normalize before comparing**: Case-insensitive for enum values (SKUs, tiers, regions). Boolean normalization (`true`/`"true"`/`"True"` → `true`). Empty collection equivalence (`[]`/`null`/absent → equal). Numeric strings (`"30"` = `30`). Region normalization (`"West Europe"` → `"westeurope"`).

4. **Record property drifts** where normalized expected ≠ normalized actual, including property name, expected value (source: diagram/default), actual Azure value, and severity level from `azure-property-paths.json`.

5. **Refine classification**: Matched resources get sub-status: "all properties match" or "properties drifted" (with count per severity level).

### 6. Present Drift Report

Display a categorized drift report.

**Quick mode**: Summary table (In Sync / Diagram Only / Azure Only counts), details table (Resource, Type, Status, Notes). If fully in sync, show "✅ Fully in sync!" and stop.

**Deep mode**: Add property drift information:
- Summary table adds columns: Critical, Warning, Info (counts of property drifts per resource)
- For each resource with property drifts, show per-property diff table (Property, Expected, Actual, Severity, Source)
- **Only show properties where expected ≠ actual** — matching properties go in a separate "Confirmed In Sync" table

**If drift is detected, proceed to Step 7.**

### 7. Offer Resolution Options

When drift is detected, present resolution options to the user.

**Quick mode options:** Update Diagram (1), Update Azure (2), Selective (3), No action (4).

**Deep mode options** (vary by drift type):

| Drift Type | Options |
|---|---|
| Existence only | Update Diagram, Update Azure, Selective, No action |
| Property only | Resolve Property Drifts, No action |
| Both | Update Diagram, Update Azure, Selective, Resolve Property Drifts, No action |

Wait for the user's choice before proceeding.

### 8. Resolution: Update Diagram

If the user chooses to update the diagram to match Azure:

**8a. Confirm destructive operations**

List resources to add and remove from the diagram. Warn that diagram removals are irreversible without a backup. Wait for explicit "yes" confirmation; "no" returns to Step 7.

**8b. Generate updated diagram**

1. Load the existing diagram XML
2. **Azure-only resources** → add `mxCell` elements with icons from `.github/skills/shared/azure-stencil-mapping.json`, placed in correct containers. For container resources, create both container and icon cells.
3. **Diagram-only resources** → remove the `mxCell`, its `-icon` child, and any connected edges
4. Re-layout, adjust container sizes, save via Draw.io MCP tool

**8c. Update Bicep files to match the updated diagram**

If `main.bicep` + `.bicepparam` exist in the diagram's directory:
- Re-parse the updated diagram into a resource model
- Regenerate Bicep files following **azv-diagram-to-bicep** conventions (reference `azure-resource-configs.md`, `bicep-best-practices.md`)
- Run pre-deployment verification from `azure-deployment-verification.md`
- Preserve user-customized `.bicepparam` values where parameters still apply; add/remove as needed
- Update module files and `main.bicep` outputs

If no Bicep files exist, skip this step.

**8d. Present result**

Show summary: resources added/removed from diagram, path to saved file. If Bicep was regenerated, show a table of changed Bicep files with their changes.

### 9. Resolution: Update Azure

If the user chooses to update Azure to match the diagram:

**9a. Confirm destructive operations**

List resources to create and delete, warn that Azure deletions are destructive and may cause data loss. Require user to type "confirm" to proceed; any other response returns to Step 7.

**9b. Run deployment verification**

Before generating Bicep, read and run the **full verification ruleset** from `.github/skills/shared/azure-deployment-verification.md`:

1. **SKU dependency rules** — verify companion resources exist
2. **Resource compatibility rules** — verify backend protocols, DNS zones
3. **Networking rules** — verify subnet sizing, no overlaps

Present verification results. Errors must be auto-fixed where possible. Do not generate code with known errors.

**9c. Generate Bicep for resources to create**

For diagram-only resources, generate Bicep templates using `azure-resource-configs.md` and `bicep-best-practices.md`. Generate `.bicepparam` with descriptive comments. Follow diagram-to-bicep conventions (`parent:`, `@secure()`, `@description()`, secure defaults).

**9d. Generate Bicep for resources to delete**

For Azure-only resources that need to be removed, generate a Bicep template that omits those resources. Note: the user can deploy this template in Complete mode to remove them, or manually delete via the Azure portal or CLI.

**9e. Present output**

Show a summary table of generated files (create Bicep + removal notes) with deployment commands. Warn user to review all files before deploying.

### 10. Resolution: Selective Updates

If the user chooses selective resolution:

**10a. Present per-resource choices**

Show a table with columns: #, Resource, Type, Status, Resolve. For each drifted resource, offer direction-specific options (Diagram Only → "Create in Azure / Remove from diagram / Skip"; Azure Only → "Add to diagram / Delete from Azure / Skip"). Wait for user decisions.

**10b. Apply decisions**

Group into two buckets: diagram updates (follow Step 8 flow including 8c Bicep regeneration) and Azure updates (follow Step 9 flow). Apply confirmation gates per bucket separately.

**10c. Present combined result**

Show what was changed in each direction and what was skipped.

### 11. Resolution: Property Drifts (Deep Mode Only)

If the user chooses to resolve property drifts:

**11a.** Present per-resource property choices: table with columns #, Property, Expected, Actual, Severity, Action (Update Azure / Accept Azure / Skip). Wait for per-property decisions.

**11b.** For "Update Azure" properties: generate Bicep snippets using `existing` references targeting only drifted properties, plus CLI command alternatives. Note VM deallocation when vmSize changes.

**11c.** For "Accept Azure" decisions: update `.bicepparam` values to match Azure actuals. Present for confirmation before writing.

**11d.** Show summary of all resolutions and wait for explicit confirmation before applying.

### 12. No Action

If the user chooses no action, confirm the report is for reference only and suggest related skills (azv-diagram-to-bicep, azv-sketch-to-diagram).

---

## Important Notes

- This skill operates **independently** — it does not require sketch-to-diagram or diagram-to-bicep.
- **Quick mode**: Existence-level comparison only (type + name matching). **Deep mode**: Also compares all tracked properties from `azure-property-paths.json` with severity classification (Critical/Warning/Info) and normalization rules.
- **When the diagram is updated (Step 8 or selective Step 10), Bicep files are automatically regenerated** if they already exist in the diagram's directory.
- **Destructive operations always require explicit confirmation** — both for deleting Azure resources and removing diagram elements.
- Filter out infrastructure resources per `.github/skills/shared/procedures/resource-filtering.md`.
- Generated update Bicep includes deployment instructions using `az deployment group create` or `New-AzResourceGroupDeployment`.
