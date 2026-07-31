---
name: azv-bicep-diagram-sync
description: Compare Bicep templates against a Draw.io Azure architecture diagram to detect resource-level divergence. Reports differences and offers resolution — update Bicep to match the diagram, update the diagram to match Bicep, or selectively resolve per resource.
license: MIT
compatibility: Prefers PowerShell 7 (pwsh) and Azure CLI (az) with Bicep CLI support; falls back to inline parsing and the Draw.io MCP when unavailable. No live Azure session required.
metadata:
  author: AzVerify
  version: "1.0"
  project: AzVerify
---

Compare Bicep templates in a solution folder against their source Draw.io diagram and resolve divergence.

**Input**: A solution folder containing Bicep templates (`main.bicep`, `modules/*.bicep`) and a Draw.io diagram file (`.drawio` or `.drawio.xml`). The user can specify the folder and diagram file, or the skill will auto-discover them.

**Tools required**: File system tools (read/write files), Draw.io MCP — attempt `mcp_drawio_create_diagram` first; if the tool is not found, fall back to `mcp_draw_io_create_diagram`. If neither is available, report: "Draw.io MCP tool not found. Ensure the MCP server is running and retry." and stop. Bicep MCP server (for best-practice validation when regenerating Bicep)

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-stencil-mapping.json` — Azure resource type to Draw.io stencil mapping (used for reverse-lookup and diagram generation)
- `.github/skills/shared/azure-resource-configs.md` — Per-resource-type configuration schemas with defaults
- `.github/skills/shared/azure-deployment-verification.md` — **Pre-deployment verification rules (MUST run before generating Bicep updates)**
- `.github/skills/shared/bicep-best-practices.md` — Bicep authoring rules (MUST read before generating any resource block)

**Shared procedures** (MUST follow):
- `.github/skills/shared/procedures/diagram-parsing.md` — Diagram-to-resource-model parsing procedure
- `.github/skills/shared/procedures/bicep-parsing.md` — Bicep template parsing procedure
- `.github/skills/shared/procedures/resource-matching.md` — Resource matching algorithm

---

## Steps

### 1. Accept Inputs

Identify the solution folder, the Bicep templates, and the Draw.io diagram to compare.

#### 1a. Identify the Solution Folder

**If the user specifies a folder path:**
- Verify the folder exists
- Use it as the solution folder

**If no folder is specified:**
- Use the current workspace directory
- Search immediate subdirectories of the workspace root (depth = 1) for folders containing both a `.drawio` file and a `main.bicep` file. Do not recurse deeper than one level.
- If exactly one such folder is found, use it (announce which folder)
- If multiple are found, present the list and ask the user to select one
- If none are found, ask the user to provide a solution folder

#### 1b. Identify the Draw.io Diagram

**If the user specifies a diagram file:**
- Verify the file exists and is a `.drawio` or `.drawio.xml` file
- Read the file contents

**If no diagram file is specified:**
- Search the solution folder for `.drawio` files
- If exactly one is found, use it (announce which file)
- If multiple are found, present the list and ask the user to select one
- If none are found, report an error:
```
## No Diagram Found

No `.drawio` files found in the solution folder `<folder-path>`.
This skill requires a Draw.io diagram to compare against the Bicep templates.
```
- Stop execution

#### 1c. Identify the Bicep Templates

- Search the solution folder for `main.bicep`
- If found, also scan for `modules/*.bicep` files
- If `main.bicep` is not found, report an error:
```
## No Bicep Templates Found

No `main.bicep` file found in the solution folder `<folder-path>`.
This skill requires Bicep templates to compare against the diagram.
```
- Stop execution

### 2. Parse Diagram into Resource Model

Run `pwsh .github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1 -DiagramPath <diagram-file>` — see `.github/skills/shared/procedures/diagram-parsing.md` for the script contract. Capture the JSON output and use it as the diagram resource model for the remaining steps. *(If pwsh or the script is unavailable, follow the inline fallback in the procedure doc above.)* If the script exits with a non-zero code or produces output that is not valid JSON, display the raw script output and stop with: "Script execution failed. Review the output above and re-run once the issue is resolved."

Display the parsed resource model as a table with columns: #, Resource, Type, Container.

### 3. Parse Bicep Templates into Resource Model

**Identify the parameter file:** Search the solution folder for `*.bicepparam` files. If exactly one is found, use it as `<selected-param-file>`. If multiple are found, present the list and ask the user to select one. If none are found, omit the `-ParamFile` argument from the script call.

Run `pwsh .github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1 -BicepFile <solution-folder>/main.bicep -ParamFile <selected-param-file> -Depth standard` — see `.github/skills/shared/procedures/bicep-parsing.md` for the script contract. Capture the JSON output and use it as the Bicep resource model for the remaining steps. *(If pwsh or the script is unavailable, follow the inline fallback in the procedure doc above.)* If the script exits with a non-zero code or produces output that is not valid JSON, display the raw script output and stop with: "Script execution failed. Review the output above and re-run once the issue is resolved."

Display the parsed Bicep resource model as a table with columns: #, Resource, Type, Source File, Notes.

### 4. Compare Resource Models

Run `pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <diagram-model.json> -ModelB <bicep-model.json> -LabelA Diagram -LabelB Bicep` — see `.github/skills/shared/procedures/resource-matching.md` for the script contract. Use the emitted match report JSON as the authoritative comparison result. *(If pwsh or the script is unavailable, follow the inline fallback in the procedure doc above.)*

**Additional classifications for this skill:**
- **In Sync (name differs)** — single-instance type match with name mismatch
- **Bicep Only** — exists in Bicep templates but not in the diagram
- **Diagram Only** — exists in the diagram but not in the Bicep templates

**Bicep-specific rules:**
- **Container resources**: VNet containers in diagram should match `Microsoft.Network/virtualNetworks` in Bicep
- **Conditional resources**: Resources with `if` conditions are classified normally but noted as "conditional"

### 5. Present Drift Report

Display a clear drift report summarizing all differences.

**Report format:**

```
## Bicep-Diagram Sync Report: <diagram-name>

### Summary
- **In Sync:** N resources
- **Bicep Only:** N resources (in Bicep, not in diagram)
- **Diagram Only:** N resources (in diagram, not in Bicep)

### Details

| Resource | Type | Status | Notes |
|----------|------|--------|-------|
| my-vnet | VNet | ✅ In Sync | |
| my-vm | Virtual Machine | ✅ In Sync | |
| redis-cache | Redis Cache | ⬜ Bicep Only | In modules/data.bicep |
| cosmos-db | Cosmos DB | 🔷 Diagram Only | Not in Bicep templates |
| my-subnet | Subnet | ✅ In Sync (name differs) | Diagram: "default", Bicep: "snet-default" |
```

**If fully in sync:**
```
## Bicep-Diagram Sync Report: <diagram-name>

✅ **Fully in sync!** All N resources in the diagram match the Bicep templates.

No action needed.
```

**If drift is detected, proceed to Step 6.**

### 6. Offer Resolution Options

When drift is detected, present resolution options to the user.

```
### Resolution Options

Drift detected — how would you like to resolve it?

1. **Update Bicep** — Add diagram-only resources to Bicep templates, remove Bicep-only resources
2. **Update Diagram** — Add Bicep-only resources to diagram, remove diagram-only resources
3. **Selective** — Choose per-resource which direction to resolve
4. **No action** — Keep the report for reference, don't change anything

Which option? (1/2/3/4)
```

Wait for the user's choice before proceeding.

### 7. Resolution: Update Bicep

If the user chooses to update Bicep to match the diagram:

**7a. Confirm changes**

```
## Confirm Bicep Changes

The following changes will be made to the Bicep templates:

**Add to Bicep** (Diagram-only resources):
- cosmos-db (Microsoft.DocumentDB/databaseAccounts)

**Remove from Bicep** (Bicep-only resources):
- redis-cache (Microsoft.Cache/redis) — in modules/data.bicep

⚠️ Removing resources from Bicep templates means they will no longer be part of deployments.

Proceed? (yes/no)
```

Wait for explicit confirmation. If the user says no, return to Step 6. Alternatively, if the user says "no" and explains they want to exclude specific resources, treat this as a Selective resolution (Step 9) pre-filtered to only the resources from the bulk list.

**7b. Run deployment verification**

Before generating Bicep, read and run the verification rules from `.github/skills/shared/azure-deployment-verification.md`:

1. **SKU dependency rules** — verify companion resources exist
2. **Resource compatibility rules** — verify backend protocols, DNS zones
3. **Networking rules** — verify subnet sizing, no overlaps
4. **Security rules** — verify TLS 1.2+, HTTPS, `@secure()` decorators
5. **Version currency rules** — verify runtime stacks and API versions are current

**7c. Apply Bicep changes**

For **Diagram-only resources** (add to Bicep):
1. Determine the appropriate module file based on resource type:
   - Networking resources → `modules/networking.bicep`
   - Compute resources → `modules/compute.bicep`
   - Data/storage resources → `modules/data.bicep`
   - If no matching module exists, create one
2. Read `.github/skills/shared/bicep-best-practices.md` and generate the resource block following those rules
3. Use configuration defaults from `.github/skills/shared/azure-resource-configs.md`
4. Add parameters to `main.bicep` and the `.bicepparam` file with descriptive comments
5. Follow Bicep best practices: `parent:` for child resources, `@secure()`, `@description()`, symbolic references

For **Bicep-only resources** (remove from Bicep):
1. Scan all remaining Bicep files for symbolic references to the resource being removed. If any are found, halt removal of that resource and report: "Cannot remove <resource-name>: it is referenced by <dependent-resource> in <file>. Resolve the dependency first or use Selective mode to skip this resource."
2. Remove the `resource` block from the module file
3. Remove associated parameters from `main.bicep` and the `.bicepparam` file
4. Remove module references in `main.bicep` if the module file is now empty
5. Remove empty module files

**7d. Present result**

```
## Bicep Updated ✓

**Added:** 1 resource (cosmos-db)
**Removed:** 1 resource (redis-cache)

The Bicep templates now match the diagram.

| File | Changes |
|------|---------|
| main.bicep | Added cosmos-db module reference; removed redis-cache reference |
| modules/data.bicep | Added Cosmos DB resource; removed Redis Cache resource |
| <name>.bicepparam | Added cosmos-db parameters; removed redis-cache parameters |

⚠️ Review the updated `.bicepparam` file — new parameters use defaults that you may want to customize.
```

### 8. Resolution: Update Diagram

If the user chooses to update the diagram to match Bicep:

**8a. Confirm changes**

```
## Confirm Diagram Changes

The following changes will be made to the diagram:

**Add to diagram** (Bicep-only resources):
- redis-cache (Redis Cache)

**Remove from diagram** (Diagram-only resources):
- cosmos-db (Cosmos DB)

⚠️ Removing resources from the diagram is irreversible unless you have a backup.

Proceed? (yes/no)
```

Wait for explicit confirmation. If the user says no, return to Step 6. Alternatively, if the user says "no" and explains they want to exclude specific resources, treat this as a Selective resolution (Step 9) pre-filtered to only the resources from the bulk list.

**8b. Generate updated diagram**

1. Load the existing diagram XML
2. For **Bicep-only resources** (add to diagram):
   - Look up each resource type in `.github/skills/shared/azure-stencil-mapping.json` for the correct icon and style
   - Add new `mxCell` elements with proper Azure icons
   - Place new resources using the following priority: (1) if the resource has an explicit `parent:` reference in Bicep, place it inside that parent's container cell; (2) otherwise, place it in the top-level diagram page. If neither condition yields a valid target, place the resource in the top-level page and add a note in the result summary.
   - For container resources (VNets, Subnets), create both the container cell and its icon child cell using the dual icon pattern
3. For **Diagram-only resources** (remove from diagram):
   - Remove the corresponding `mxCell` elements from the XML
   - Also remove any associated icon cells (cells with `id` ending in `-icon`)
   - Remove any edges connected to removed cells. If a removed cell has edges connecting two cells that both remain in the diagram, also remove those edges and add a note in the result summary: "Warning: edge between <A> and <B> was removed because it passed through the deleted resource <X>. Review connectivity in the diagram."
4. Expand the parent container's bounding box to fit any newly added child cells. Do not reposition existing cells unless they overlap a newly added cell; in that case, shift the new cell to the nearest open space within the container.
5. Save the updated diagram via the Draw.io MCP tool. If the Draw.io MCP tool returns an error, do not report the diagram as updated. Instead display: "Diagram save failed: <error message>. No changes were written to disk. Retry or save the XML manually to `<diagram-path>`." Then stop Step 8 without presenting the success message.

**8c. Present result**

```
## Diagram Updated ✓

**Added:** 1 resource (redis-cache)
**Removed:** 1 resource (cosmos-db)

The diagram now matches the Bicep templates.
Saved to `<diagram-path>`.
```

### 9. Resolution: Selective

If the user chooses selective resolution:

For each drifted resource, present the options:

```
### Resource: cosmos-db (Cosmos DB) — Diagram Only

This resource exists in the diagram but not in the Bicep templates.

1. **Add to Bicep** — Generate a Cosmos DB resource block in modules/data.bicep
2. **Remove from Diagram** — Remove this resource from the diagram
3. **Skip** — Leave this resource unresolved

Choice? (1/2/3)
```

Apply the user's choice for each resource following the same logic as Steps 7 and 8. In selective mode, skip the bulk confirmation steps (7a / 8a). Apply each resource's chosen action immediately after the user responds. Batch all file writes and diagram changes; do not write files until all per-resource choices have been collected. Then apply all changes at once and present the summary table.

After all resources are resolved, present a summary:

```
## Selective Resolution Complete ✓

| Resource | Type | Action |
|----------|------|--------|
| cosmos-db | Cosmos DB | Added to Bicep |
| redis-cache | Redis Cache | Removed from Bicep |
| old-function | Function App | Skipped |

Remaining drift: 1 resource (old-function)
```
