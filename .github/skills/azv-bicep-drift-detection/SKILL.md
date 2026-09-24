---
name: azv-bicep-drift-detection
description: Detect drift between Bicep templates and a target — either a Draw.io Azure architecture diagram (offline) or a live Azure environment. Reports resources that differ in existence and, against Azure, in configuration properties, then offers resolution — update Bicep, update the diagram, update Azure, or selectively resolve per resource. Replaces the former azv-bicep-diagram-sync and azv-bicep-whatif skills.
license: MIT
metadata:
  version: "2.0"
  project: AzVerify
---

Compare Bicep templates in a solution folder against either their source Draw.io diagram or a live Azure environment, and resolve the drift that is found.

> **Approach for Azure mode**: this skill does NOT use `az deployment group what-if`. It parses the Bicep templates and parameter file into an **expected** resource model, discovers the live environment into an **actual** resource model, and compares the two at both existence and property level.

**Input**: Bicep templates (`*.bicep`), optionally a `.bicepparam` file or the folder containing them, plus a comparison target — a `.drawio` diagram file or an Azure scope (resource group name or subscription ID). The user can specify these, or the skill will auto-discover them and prompt for what is missing.

**Tools**: File system tools (read/write files), Terminal (for running PowerShell 7 / `pwsh` shared scripts and `az` CLI commands), Bicep Schema MCP (`azure-bicepschema`), Azure MCP server tools (Azure mode), Draw.io MCP — attempt `mcp_drawio_create_diagram` first; if the tool is not found, fall back to `mcp_draw_io_create_diagram`.

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-stencil-mapping.json` — Azure resource type to Draw.io stencil mapping
- `.github/skills/shared/azure-resource-configs.md` — Per-resource-type configuration schemas with defaults
- `.github/skills/shared/azure-deployment-verification.md` — Pre-deployment verification rules
- `.github/skills/shared/bicep-best-practices.md` — Bicep authoring rules (MUST read before generating any resource block)
- `.github/skills/shared/data/azure-property-paths.json` — Tracked properties, ARM JSON paths, defaults, severity classifications

**Shared procedures** (MUST follow):
- `.github/skills/shared/procedures/azure-authentication.md` — Azure session check (Azure mode only)
- `.github/skills/shared/procedures/bicep-parsing.md` — Bicep-to-resource-model parsing
- `.github/skills/shared/procedures/diagram-parsing.md` — Diagram-to-resource-model parsing (diagram mode)
- `.github/skills/shared/procedures/azure-discovery.md` — Live Azure discovery and property enrichment (Azure mode)
- `.github/skills/shared/procedures/resource-filtering.md` — Resource exclusion rules (`-Mode bicep`)
- `.github/skills/shared/procedures/resource-matching.md` — Resource matching and property comparison
- `.github/skills/shared/procedures/resolution-update-bicep.md` — "Update Bicep" resolution flow
- `.github/skills/shared/procedures/resolution-update-diagram.md` — "Update Diagram" resolution flow (diagram mode)
- `.github/skills/shared/procedures/resolution-update-azure.md` — "Update Azure" and property-drift resolution flows (Azure mode)
- `.github/skills/shared/procedures/output-budget.md` — Report sizing rules

---

## Output Budget Rules

Follow `.github/skills/shared/procedures/output-budget.md` strictly. In addition:

- Keep all resource models in temporary JSON files (`bicep-model-raw.json`, `bicep-model.json`, `diagram-model.json` or `azure-model.json`, `match-report.json`) in a working directory inside the solution folder, and reference them by path between steps instead of echoing their contents.
- Never echo generated Bicep or Draw.io XML in the response — show file paths and a change summary only.
- Delete the intermediate JSON files once the drift report has been presented and any chosen resolution has been applied.

## Fallback: pwsh Unavailable

If `pwsh`/`powershell.exe` or a shared script cannot be executed, use the inline fallback in the matching procedure contract and continue the workflow:

| Step | Fallback source |
|------|-----------------|
| 2 — Auth check (Azure mode) | `.github/skills/shared/procedures/azure-authentication.md` |
| 3 — Bicep parsing | `.github/skills/shared/procedures/bicep-parsing.md` |
| 4, 6 — Filtering | `.github/skills/shared/procedures/resource-filtering.md` |
| 5 — Diagram parsing | `.github/skills/shared/procedures/diagram-parsing.md` |
| 6 — Azure discovery and enrichment | `.github/skills/shared/procedures/azure-discovery.md` |
| 7 — Comparison | `.github/skills/shared/procedures/resource-matching.md` |

Announce the fallback once: "Script execution failed. Please review the script file. Using fallback method now."

## Steps

### 1. Determine the Comparison Target

Decide what the Bicep templates are being validated against, before anything else — the target selects the mode for the rest of the workflow.

- **Diagram mode** (offline): the user names a `.drawio` file, or asks to compare against "the diagram", "the design", or "the architecture drawing"
- **Azure mode**: the user names a resource group or subscription, or asks to compare against "Azure", "the environment", "what's deployed", or asks for a "what-if"

**If the target is ambiguous:**
- If the solution folder contains exactly one `.drawio` file and no Azure scope was given, propose diagram mode: "Found `<diagram>` in the solution folder. Compare the Bicep templates against that diagram, or against a live Azure resource group instead?"
- Otherwise ask: "Should I compare the Bicep templates against a Draw.io diagram or against a live Azure environment?"

Announce the selected mode before continuing.

### 2. Check Azure Authentication (Azure Mode Only)

**Diagram mode is fully offline — skip this step.**

In Azure mode, run `pwsh .github/skills/shared/scripts/Test-AzureAuth.ps1` — see `.github/skills/shared/procedures/azure-authentication.md` for the script contract. A **non-zero exit code is a HARD GATE**: present the authentication instructions from the contract doc and stop. *(If pwsh or the script is unavailable, see "Fallback: pwsh Unavailable".)*

### 3. Accept Bicep Inputs

Identify the solution folder, the Bicep entry point, and the parameter file.

#### 3a. Identify the Solution Folder

**If the user specifies a folder path:**
- Verify the folder exists and use it as the solution folder

**If the user specifies one or more `.bicep` or `.bicepparam` files, but no folder path:**
- Verify every specified file exists and has a `.bicep` or `.bicepparam` extension
- For each `.bicepparam` file, read its `using` declaration and resolve the referenced local `.bicep` path relative to the parameter file. Verify the referenced file exists. If `using none` is declared, ask the user to specify the Bicep entry-point file
- Select the Bicep entry point in this order: the file referenced by a specified `.bicepparam` file; a specified file named `main.bicep`; the only specified `.bicep` file
- If the supplied files resolve to different entry points, or multiple `.bicep` files remain without a clear entry point, present the candidates and ask the user to select one
- Use the directory containing the selected Bicep entry point as the solution folder, and retain the explicitly specified files for Step 3b

**If no folder, `.bicep` file, or `.bicepparam` file is specified:**
- Use the current workspace directory
- Search immediate subdirectories of the workspace root (depth = 1) for folders containing a `main.bicep` file — in diagram mode, require a `.drawio` file in the same folder. Do not recurse deeper than one level
- If exactly one such folder is found, use it (announce which folder)
- If multiple are found, present the list and ask the user to select one
- If none are found, ask the user to provide a solution folder

If no Bicep entry point can be resolved, report an error and stop:
```
## No Bicep Template Found

No `main.bicep` file found in `<folder-path>`.
This skill requires Bicep templates to compare.
```

#### 3b. Identify the Parameter File

**If Step 3a retained an explicitly specified `.bicepparam` file**, use it as `<selected-param-file>`.

**If no parameter file was specified:**
- Search the solution folder for `*.bicepparam` files whose `using` declaration references `<selected-bicep-file>`
- If exactly one is found, use it (announce which file)
- If multiple are found, present the list and ask the user to select one
- If none are found, warn and continue without one: "⚠️ No `.bicepparam` file found in `<folder-path>`. Defaults from `azure-property-paths.json` will be used as expected values where parameters are unresolved."

When a parameter file is selected, verify its `using` declaration resolves to `<selected-bicep-file>`. If it targets a different template or declares `using none`, report the mismatch and ask the user to select a compatible parameter file or continue without one.

### 4. Parse Bicep Templates into the Expected Resource Model

#### 4a. Parse the Templates

Run the applicable command — see `.github/skills/shared/procedures/bicep-parsing.md` for the script contract:

```powershell
# With a selected parameter file
pwsh .github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1 -BicepFile <selected-bicep-file> -ParamFile <selected-param-file> -Depth standard -OutFile <work-dir>/bicep-model-raw.json

# Without a parameter file
pwsh .github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1 -BicepFile <selected-bicep-file> -Depth standard -OutFile <work-dir>/bicep-model-raw.json
```

The emitted model is the **expected** state: resource types, parameter-resolved names, tracked property values, and relationships across `main.bicep` and its modules. Where a tracked property resolves to a parameter with no value in the parameter file, fall back to the default in `azure-property-paths.json`.

If the script exits non-zero or produces output that is not valid JSON, use the fallback method in the contract.

#### 4b. Filter the Expected Model

The parsed model includes deployment scaffolding — module `Microsoft.Resources/deployments` entries and `Microsoft.Authorization/*` role assignments — that exists in neither a diagram nor the discovered Azure model, and would otherwise be reported as false drift. Apply the shared exclusion rules — see `.github/skills/shared/procedures/resource-filtering.md` for the script contract:

```powershell
pwsh .github/skills/shared/scripts/Select-AzureResources.ps1 -InputFile <work-dir>/bicep-model-raw.json -Mode bicep -OutFile <work-dir>/bicep-model.json
```

Use `<work-dir>/bicep-model.json` as the expected model for the rest of the workflow. Report how many resources were excluded as a single line; do not list them individually.

Report the resulting resource count. Display the model as a table (columns: #, Resource, Type, Source File, Key Properties) only when it stays within the output thresholds in `output-budget.md`.

### 5. Diagram Mode: Parse the Diagram

**Azure mode — skip to Step 6.**

#### 5a. Identify the Draw.io Diagram

**If the user specified a diagram file**, verify it exists and is a `.drawio` or `.drawio.xml` file.

**If no diagram file was specified:**
- Search the solution folder for `.drawio` files
- If exactly one is found, use it (announce which file)
- If multiple are found, present the list and ask the user to select one
- If none are found, report an error and stop:
```
## No Diagram Found

No `.drawio` files found in the solution folder `<folder-path>`.
Provide a diagram file, or compare against a live Azure environment instead.
```

#### 5b. Parse the Diagram

Run `pwsh .github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1 -DiagramPath <diagram-file> -OutFile <work-dir>/diagram-model.json` — see `.github/skills/shared/procedures/diagram-parsing.md` for the script contract. If the script exits non-zero or produces output that is not valid JSON, use the fallback method in the contract.

Report the parsed resource count. Display the model as a table (columns: #, Resource, Type, Container) only when it stays within the output thresholds.

Then continue at Step 7.

### 6. Azure Mode: Check Providers and Discover the Environment

#### 6a. Identify the Target Scope

**If the user specifies a resource group name:**
- Verify it exists: run `az group show --name <name>` — if this fails, report an error and stop

**If the user specifies a subscription ID:**
- Use it as the target scope, and warn that subscription-level comparison can be noisy

**If no scope was specified, try to infer it:**
1. Look for a target resource group named in the `.bicepparam` file or its comments
2. If found, propose it: "The `.bicepparam` file references resource group `<name>`. Use this as the target scope? (yes/no)"
3. Otherwise ask: "Which Azure resource group should I compare the templates against?"

#### 6b. Check Resource Provider Registration

Unregistered providers cause deployment failures, so check them before discovery.

1. Extract the unique provider namespaces from the expected model (first segment of each resource type, e.g. `Microsoft.Compute/virtualMachines` → `Microsoft.Compute`)
2. Run `az provider list --query "[?registrationState=='Registered'].namespace" -o json`
3. Compare case-insensitively

**If all providers are registered**, continue silently. **If any are missing**, display a warning table (columns: #, Provider Namespace, Required By) with the registration commands:

```bash
az provider register --namespace <namespace>
# check status:
az provider show --namespace <namespace> --query registrationState -o tsv
```

This is a **warning, not a hard gate** — registration takes a few minutes, and the comparison is still valuable for planning. Continue to Step 6c.

#### 6c. Discover the Azure Environment

Run the shared discovery script, enriched and filtered in one call — see `.github/skills/shared/procedures/azure-discovery.md` for the script contract:

```powershell
# Resource group scope
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -ResourceGroup <rg-name> -Enrich -Mode bicep -OutFile <work-dir>/azure-model.json

# Subscription scope
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -SubscriptionId <sub-id> -Enrich -Mode bicep -OutFile <work-dir>/azure-model.json
```

Notes:
- `-Enrich` populates each resource's `properties` bag with the tracked properties from `azure-property-paths.json`, which the property comparison in Step 7 requires.
- Do **not** pass `-StripReadOnly` — drift comparison needs the full property bag.
- `-Mode bicep` applies the shared exclusion rules for Azure-managed resources (auto-created NICs and disks, network watchers, smart detector alert rules, portal dashboards, and the rest of `resource-filter-rules.json`). Do not maintain a separate inline exclusion list.
- Report a single summary line after enrichment (e.g. "Discovered 18 resources, enriched 18"), not one line per resource.
- If a resource's properties cannot be retrieved, its tracked properties are recorded as `unknown` — continue with the remaining resources.
- If the script exits non-zero or emits unparseable output, use the inline fallback in the discovery contract.
- If the result count is zero and the resource group was confirmed to exist, warn that the authenticated identity may lack Reader permissions, or that nothing has been deployed yet.

### 7. Compare Models and Classify Drift

Run the comparison script — see `.github/skills/shared/procedures/resource-matching.md` for the script contract. Bicep is the **expected** model (A); the diagram or Azure is the comparison model (B):

```powershell
# Diagram mode (existence-level)
pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <work-dir>/bicep-model.json -ModelB <work-dir>/diagram-model.json -LabelA Bicep -LabelB Diagram -OutFile <work-dir>/match-report.json

# Azure mode (existence + property-level)
pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <work-dir>/bicep-model.json -ModelB <work-dir>/azure-model.json -LabelA Bicep -LabelB Azure -CompareProperties -OutFile <work-dir>/match-report.json
```

Use the emitted match report as the authoritative comparison result.

**Diagram mode classifications**: **In Sync**, **In Sync (name differs)**, **Bicep Only** (in templates, not in the diagram), **Diagram Only** (in the diagram, not in the templates). Bicep-specific rules: diagram VNet containers match `Microsoft.Network/virtualNetworks`; resources declared with an `if` condition are classified normally but annotated "conditional".

**Azure mode classifications** — map the match report onto change categories:

| Category | Meaning |
|---|---|
| 🆕 **Create** | In the templates but not in Azure — will be created on deployment |
| ✏️ **Modify** | In both, but one or more tracked properties differ |
| 🗑️ **Delete** | In Azure but not in the templates — would be removed by an authoritative (Complete mode) deployment |
| ✅ **No Change** | In both, with all tracked properties matching |

Azure mode is always property-aware — the `propertyComparison` object per matched resource distinguishes **Modify** from **No Change**, using the expected value from the templates (or the `azure-property-paths.json` default where the templates leave it unset) and the normalization rules documented in `resource-matching.md`. Handle two edge cases explicitly:
- A property whose actual value is `unknown` (retrieval failed in Step 6c) is reported as `⚠️ Unknown` — never counted as matching or drifting.
- A matched resource with no comparable tracked properties is reported as `No Comparable Properties`, not as No Change.

### 8. Present the Drift Report

**Diagram mode**:

```
## Bicep Drift Report: <diagram-name> (diagram mode)

### Summary
- **In Sync:** N resources
- **Bicep Only:** N resources (in Bicep, not in diagram)
- **Diagram Only:** N resources (in diagram, not in Bicep)

### Details

| Resource | Type | Status | Notes |
|----------|------|--------|-------|
| my-vnet | VNet | ✅ In Sync | |
| redis-cache | Redis Cache | ⬜ Bicep Only | In modules/data.bicep |
| cosmos-db | Cosmos DB | 🔷 Diagram Only | Not in Bicep templates |
| my-subnet | Subnet | ✅ In Sync (name differs) | Diagram: "default", Bicep: "snet-default" |
```

**Azure mode**: header with the target scope and the template/parameter paths, then a summary table with counts per category (🆕 Create, ✏️ Modify, 🗑️ Delete, ✅ No Change), then per-category sections:
- **🆕 Create** — table of template resources missing from Azure (columns: #, Resource, Type, Resource Group)
- **✏️ Modify** — one property diff table per resource (columns: Property, Current Azure Value, Template Value, Severity, Source)
- **🗑️ Delete** — table of Azure resources absent from the templates, with the authoritative-deployment warning
- **✅ No Change** — collapsible `<details>` section listing matched resources

> **CRITICAL**: property diff tables MUST contain **only** properties where expected ≠ actual after normalization. Matching properties belong in the "No Change" section, never mixed into a diff table.

**If fully in sync**: report "✅ Fully in sync — all N template resources match `<target>`" and stop.

**If drift is detected**, proceed to Step 9.

### 9. Offer Resolution Options

Present options based on the mode and the drift found.

**Diagram mode:**
1. **Update Bicep** — add diagram-only resources to the templates, remove Bicep-only resources
2. **Update Diagram** — add Bicep-only resources to the diagram, remove diagram-only resources
3. **Selective** — choose per-resource which direction to resolve
4. **No action** — keep the report for reference

**Azure mode:**

| Drift type | Options offered |
|---|---|
| Existence only | Update Bicep, Update Azure, Selective, No action |
| Property only | Update Bicep (adopt Azure values), Resolve Property Drifts, No action |
| Both | Update Bicep, Update Azure, Selective, Resolve Property Drifts, No action |

In Azure mode, **Update Bicep** brings the templates in line with what is actually deployed — adding Azure-only resources, removing template resources that do not exist in Azure, and adopting Azure-actual values for drifted properties. **Update Azure** generates deployment artifacts that bring the environment in line with the templates.

Wait for the user's choice before proceeding.

### 10. Resolution: Update Bicep

Follow `.github/skills/shared/procedures/resolution-update-bicep.md` with `<source>` = `Diagram` (diagram mode) or `Azure` (Azure mode). That procedure covers the confirmation gate, deployment verification, module placement and generation of added resources, the dependency and empty-template halt checks on removal, the property-update flow for adopting Azure-actual values, and the result summary.

In Azure mode, never copy secret-bearing values discovered from Azure into templates — declare `@secure()` parameters instead.

### 11. Resolution: Update Diagram (Diagram Mode)

Follow `.github/skills/shared/procedures/resolution-update-diagram.md` with `<source>` = `Bicep`. That procedure covers the confirmation gate, stencil lookup and dual-icon placement, edge cleanup, and the raw-XML save fallback. Its conditional Bicep regeneration step does not apply here — Bicep is the source model, so leave the templates untouched.

### 12. Resolution: Update Azure (Azure Mode)

Follow section **A. Existence-Level Resolution** of `.github/skills/shared/procedures/resolution-update-azure.md` with `<source>` = `Bicep`. That procedure covers the "confirm" gate, deployment verification, generation of create artifacts, removal artifacts for Azure-only resources, and the output summary including the deployment command.

### 13. Resolution: Property Drifts (Azure Mode)

Follow section **B. Property-Level Drift Resolution** of `.github/skills/shared/procedures/resolution-update-azure.md`. That procedure covers per-property choices (Update Azure / Accept Azure / Skip), Bicep `existing`-reference snippets and CLI alternatives, `.bicepparam` updates for accepted Azure values, and the final confirmation gate.

Note operational impact where relevant — for example, changing `vmSize` requires VM deallocation.

### 14. Resolution: Selective Updates

**14a.** Present per-resource choices in a table (columns: #, Resource, Type, Status, Resolve), with direction-specific options for each drifted resource — diagram mode: "Add to Bicep / Remove from diagram / Skip" and "Remove from Bicep / Add to diagram / Skip"; Azure mode: "Add to Bicep / Create in Azure / Skip" and "Remove from Bicep / Delete from Azure / Skip". Do not write any files while collecting choices.

**14b.** Group the decisions by direction and apply each bucket via the matching procedure (Steps 10–12). Skip the bulk confirmations inside those procedures; the per-resource choices replace them, except the "confirm" gate before generating Azure deletion artifacts, which still applies once. Run deployment verification for every resource being added to Bicep before generating its block, then batch all file writes and apply them at once.

**14c.** Present a combined summary table (columns: Resource, Type, Action) plus the remaining unresolved drift count.

### 15. No Action

Confirm that the report is for reference only and no changes were made.

- If deletions were detected in Azure mode, remind the user to verify that the exclusions are intentional before running an authoritative deployment
- Suggest reviewing Critical-severity property drifts first
- Suggest related skills: **azv-diagram-drift-detection** (validate the diagram against Azure), **azv-bicep-policy-check** (check the templates against Azure Policy), **azv-diagram-to-bicep** (regenerate templates from the diagram)

---

## Important Notes

- This skill replaces **azv-bicep-diagram-sync** (diagram mode) and **azv-bicep-whatif** (Azure mode) — both are now target modes of this skill.
- **Diagram mode runs fully offline**; the authentication gate applies only in Azure mode.
- **Azure mode does not use ARM what-if.** It builds both models itself and compares them, which is why unregistered providers are reported as a warning rather than a failure.
- Azure mode is always property-aware — there is no separate quick/deep toggle. Diagram mode is existence-level only, because a diagram does not carry the tracked configuration properties.
- **Destructive operations always require explicit confirmation** — for removing resources from templates, removing diagram elements, and generating Azure deletion artifacts.
- This skill never applies changes to Azure directly; it generates Bicep and CLI alternatives for the user to review and deploy.
