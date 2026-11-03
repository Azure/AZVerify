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

**Input**: A Bicep or ARM JSON template, optional parameter inputs (including `.bicepparam` and ARM JSON parameter files), or a solution folder, plus a comparison target — a `.drawio` diagram file or an Azure scope (resource group name or subscription ID). Identify the actual deployment entry point; it is not necessarily named `main.bicep`.

**Tools**: File system tools (read/write files), Terminal (for running PowerShell 7 / `pwsh` shared scripts and `az` CLI commands), Bicep Schema MCP (`azure-bicepschema`), Azure MCP server tools (Azure mode), Draw.io MCP — attempt `mcp_drawio_create_diagram` first; if the tool is not found, fall back to `mcp_draw_io_create_diagram`.

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-stencil-mapping.json` — Azure resource type to Draw.io stencil mapping
- `.github/skills/shared/azure-resource-configs.md` — Per-resource-type configuration schemas with defaults
- `.github/skills/shared/azure-deployment-verification.md` — Pre-deployment verification rules
- `.github/skills/shared/bicep-best-practices.md` — Bicep authoring rules (MUST read before generating any resource block)
- `.github/skills/shared/data/azure-property-paths.json` — Tracked properties, ARM JSON paths, normalization and severity classifications

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

- Keep all resource models in temporary JSON files (`bicep-model-raw.json`, `bicep-model.json`, `diagram-model.json` or `azure-model.json`, `match-report.json`) in `<work-dir>` = `<solution-folder>/.azverify-tmp/` (never outside the repository — see rule 6 of the output budget), and reference them by path between steps instead of echoing their contents.
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

### Azure Mode Fast Path (default)

For a **resource-group scope**, replace steps 2, 4, 6 and 7 with ONE read-only script call (one approval, no MCP needed, no Azure changes):

```powershell
pwsh .github/skills/azv-bicep-drift-detection/scripts/Invoke-BicepDriftDetection.ps1 `
  -BicepFile <entry-point.bicep|template.json> [-ParamFile <existing-parameter-file>] [-ParameterOverride @{ name = 'value' }] `
  [-PipelineFile <pipeline.yml>] [-DeploymentMode Incremental|Complete|Unknown] `
  [-BuildVersion <string>] [-AnalysisTimestamp <timestamp>] `
  [-ParameterSource ExplicitInput|CurrentPipeline|HistoricalFallback] `
  -ResourceGroup <rg> -SubscriptionId <id>
```

`-PipelineFile` records a pipeline reference/provenance only; it is not a YAML evaluator. Inspect deployment/workflow references to identify the template, parameter file, explicit overrides, deployment mode, and build version where available. Do not claim to evaluate YAML or macros: pass known override values through `-ParameterOverride`, which is authoritative; flag unresolved expressions as uncertain. `-DeploymentMode` accepts `Incremental`, `Complete`, or `Unknown` (default `Unknown`); `-BuildVersion` records the identified build version. `-AnalysisTimestamp` is passed to the parser for synthetic `utcNow()` handling; it is an analysis input, not proof of deployment time. `-ParameterSource` accepts `ExplicitInput`, `CurrentPipeline`, or `HistoricalFallback` (default `ExplicitInput`); historical inputs are not proof of current deployed values. The parser supports Bicep and ARM JSON templates/parameter files and preserves the existing parameter-file format.

The script checks auth, parses inputs, reads Azure inventory and targeted resource details, compares properties, and writes `.azverify-tmp/drift-report.md` plus `drift-summary.json`. A historical parameter file is only a fallback when no current deployment inputs can be established; it is not proof of the current deployment configuration. Unresolved expressions/macros must remain unresolved—never invent a default.

- This expected-aware path uses **Azure CLI only** for authentication, scope lookup, inventory and token acquisition. Sign in with `az login`; an Az PowerShell session alone is not sufficient. The legacy/manual discovery path may use either Azure CLI or Az PowerShell, as specified by its procedure.
- Ask the user for `-SubscriptionId` and `-ResourceGroup` explicitly; never infer them from folder names.
- Exit `0` = COMPLETE, `2` = INCOMPLETE (some values/reads unavailable - report is still produced and clearly marked; never present it as complete), `1` = failed (auth, scope or compile: stop and show the message).
- Present the generated report in step 8 as is. Azure-only resources are labeled "Not in template", not guaranteed deletes.
- Use the manual steps below only for subscription scope, diagram mode, or when Fast Path doesn't work.

### 2. Check Azure Authentication (Azure Mode Only)

**Diagram mode is fully offline — skip this step.**

For expected-aware Bicep-vs-Azure comparison, require Azure CLI authentication and use the explicit subscription; an Az PowerShell session alone is not sufficient. The legacy/manual Azure discovery path may use either supported backend. A failed authentication check is a **HARD GATE**: present the applicable authentication instructions and stop. *(If pwsh or the script is unavailable, see "Fallback: pwsh Unavailable".)*

### 3. Accept Deployment Inputs

Identify the solution folder, deployment entry point (Bicep or ARM JSON), parameter inputs, and any deployment mode/overrides referenced by the pipeline or deployment scripts.

#### 3a. Identify the Solution Folder

**If the user specifies a folder path:**
- Verify the folder exists and use it as the solution folder

**If the user specifies template or parameter files, but no folder path:**
- Verify every specified file exists and is a supported Bicep/ARM JSON template or parameter file.
- For `.bicepparam`, follow and verify its `using` declaration. For ARM JSON parameters, identify the matching template from deployment references or explicit user input.
- Inspect pipeline/workflow and deployment-script references for template paths, parameter files, overrides, and deployment mode. Read references; do not promise or attempt automatic evaluation of arbitrary YAML, expressions, or macros. Resolve values only when explicit and verifiable; carry known overrides as explicit `ParameterOverride` inputs.
- If exactly one deployment entry point is established, use it. If candidates remain ambiguous, show them and ask the user to choose; do not ask when references establish one unambiguous entry point.
- Use the directory containing the selected entry point as the solution folder and retain the specified parameter inputs.

**If no folder, template, or parameter file is specified:**
- Use the current workspace directory
- Inspect relevant deployment references and search the workspace for template candidates and entry-point references; a template need not be named `main.bicep`. In diagram mode, also locate the associated `.drawio` file.
- If one entry point is established, use it (announce it). If multiple candidates remain ambiguous, present them and ask the user to select one.
- If none are found, ask the user to provide a solution folder

If no deployment entry point can be resolved, report an error and stop:
```
## No Deployment Template Found

No Bicep or ARM JSON deployment template could be identified in `<folder-path>`.
This skill requires a deployment template to compare.
```

#### 3b. Identify the Parameter File

**If Step 3a retained an explicitly specified `.bicepparam` file**, use it as `<selected-param-file>`.

**If no parameter file was specified:**
- Follow deployment references to find the parameter file actually used, including ARM JSON parameter files and pipeline-supplied overrides.
- If one current input set is established, use it and record its provenance. If multiple candidates remain ambiguous, ask the user to choose.
- If no current parameter source can be established, a historical parameter file may be used only as an explicitly labeled fallback, not as evidence of current deployment values. Otherwise continue with unresolved parameter-dependent values marked uncertain. Never substitute catalog defaults for missing inputs.

When a parameter file is selected, verify that it applies to the selected template; honor `.bicepparam` `using` declarations, and report mismatches. Preserve the existing parameter file format—do not convert it to another format. Record whether each effective input came from a template default, parameter file, explicit pipeline override, or unresolved expression, and note deployment mode where ascertainable.

### 4. Parse the Deployment Template into the Expected Resource Model

#### 4a. Parse the Templates

Run the applicable command — see `.github/skills/shared/procedures/bicep-parsing.md` for the script contract:

Use the parser contract for the supported Bicep or ARM JSON entry point and parameter-file format. Pass only known, explicit pipeline overrides to the script as `-ParameterOverride`; do not claim automatic YAML evaluation.

The emitted model is the **expected** state. Include provenance for resolved values and mark uncertain values (including unresolved macros and unavailable pipeline inputs); do not infer missing values from defaults in configuration catalogs. Preserve parser `diagnostics.parameters` and `diagnostics.parameterScopes` metadata. Pass `-AnalysisTimestamp` when supplied and treat synthesized `utcNow()` values as analysis-only, not historical/current deployment evidence. Report parser/build uncertainties rather than presenting an incomplete expected model as definitive.

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

Run the shared discovery script, enriched and filtered in one call — see `.github/skills/shared/procedures/azure-discovery.md` for the script contract. Follow all inventory pages and explicitly include undeclared AMPLS `scopedResources`:

```powershell
# Resource group scope
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -ResourceGroup <rg-name> -SubscriptionId <sub-id> -ExpectedModel <work-dir>/bicep-model.json -Mode bicep -ManagementEndpoint <active-cloud-resource-manager-endpoint> -OutFile <work-dir>/azure-model.json

# Subscription scope
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -SubscriptionId <sub-id> -ExpectedModel <work-dir>/bicep-model.json -Mode bicep -ManagementEndpoint <active-cloud-resource-manager-endpoint> -OutFile <work-dir>/azure-model.json
```

Notes:
- `-ExpectedModel` uses expected-aware discovery: paginated inventory and declared child-collection enumeration followed by targeted ARM reads, with canonical `comparisonProperties`. Get the active cloud endpoint with `az cloud show --query endpoints.resourceManager -o json`; use the explicitly selected subscription for every CLI call.
- Do **not** pass `-StripReadOnly` — drift comparison needs the full property bag.
- `-Mode bicep` applies the shared exclusion rules in `.github/skills/shared/data/resource-filter-rules.json` (network watchers, smart detector alert rules, portal dashboards, deployment history, template specs, `Microsoft.Authorization/*`, and resources tagged only with `hidden-*` keys). Do not maintain a separate inline exclusion list. Resources that Azure creates implicitly alongside a declared resource — such as a VM's OS disk — are **not** filtered; Step 8 annotates them.
- Report a single summary line after enrichment (e.g. "Discovered 18 resources, enriched 18"), not one line per resource.
- Inventory enumeration failures, including failed pages or AMPLS scoped-resource enumeration, make discovery incomplete; do not describe the inventory as exhaustive. An authentication failure stops the script. An unavailable detail read is recorded in `issues`, with unknown property values and existence `Unknown` unless inventory already confirmed it. Only a confirmed resource-not-found response means `Absent`.
- If the result count is zero and the resource group was confirmed to exist, warn that the authenticated identity may lack Reader permissions, or that nothing has been deployed yet.

### 7. Compare Models and Classify Drift

Run the comparison script — see `.github/skills/shared/procedures/resource-matching.md` for the script contract. Bicep is the **expected** model (A); the diagram or Azure is the comparison model (B):

```powershell
# Diagram mode (existence-level)
pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <work-dir>/bicep-model.json -ModelB <work-dir>/diagram-model.json -LabelA Bicep -LabelB Diagram -OutFile <work-dir>/match-report.json

# Azure mode (existence + property-level)
pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <work-dir>/bicep-model.json -ModelB <work-dir>/azure-model.json -LabelA Bicep -LabelB Azure -AzureIdentity -TrackedProperties -OutFile <work-dir>/match-report.json
```

Use the emitted match report as the authoritative comparison result. Both Azure paths use exact ARM identity and the same canonical projection, including top-level SKU. Unknown/unresolved values, including `identityUnknown`, are Unverified—not confirmed differences. Provider-maintained observations (including peering and provisioning status) are reported separately and are not configuration drift. Heuristic type/name matching is only for diagrams.

**Diagram mode classifications**: **In Sync**, **In Sync (name differs)**, **Bicep Only** (in templates, not in the diagram), **Diagram Only** (in the diagram, not in the templates). Bicep-specific rules: diagram VNet containers match `Microsoft.Network/virtualNetworks`; resources declared with an `if` condition are classified normally but annotated "conditional".

**Azure mode classifications** — map the match report onto change categories:

| Category | Meaning |
|---|---|
| 🆕 **Create** | In the templates but not in Azure — will be created on deployment |
| ✏️ **Modify** | In both, but one or more explicit, comparable properties differ after defined normalization |
| **Not in template** | Present in Azure but absent from the selected template set; not a deletion decision |
| ⚠️ **Unverified** | Identity/existence unknown, or at least one expected property unavailable/unresolved |
| **No Comparable Properties** | Existence confirmed, but no expected configuration can be assessed |
| ✅ **No Change** | Existence confirmed and all specified tracked properties verified matching |

Map entries exactly as the fast path: `Bicep Only` → **Create**; `Azure Only` → **Not in template** (not a guaranteed delete); `Unresolved`/`Unverified` → **Unverified**. For identity-matched resources, `Incomplete` → **Unverified**, `No Comparable Properties` → its own category, confirmed explicit property differences → **Modify**, and only `All Properties Match` → **No Change**. Count each resource once; show any confirmed differences within an incomplete resource's Unverified details. No-comparable and unverified resources make the overall configuration report INCOMPLETE.

Azure mode assesses explicit, resolved expectations and conservatively compares additional explicitly declared properties where actual values can be read; missing configuration is not inferred from defaults. Keep confirmed differences distinct from omitted properties, values supplied only by defaults, read-only values, and unresolved/unavailable values. Normalization follows property metadata: exact strings by default, selected case-insensitive enums, canonical resource IDs, and unordered keyed sets only where metadata defines their semantics. Null, absent, empty, and default values are not universally equivalent. “In Sync” denotes identity matching, not a verified configuration result.

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

**Azure mode**: header with target scope, template/parameter paths, parameter source, build version (or **Unknown**), deployment mode (or **Unknown**), and input provenance/uncertainties. Do not infer a missing build version. The report's detail order is (1) Azure-only / **Not in template** inventory entries, (2) confirmed property and existence differences, and (3) **Unverified** items and coverage limitations. Put confidently matching resources in a collapsed section after these sections, not in the primary report. Include a mutually exclusive summary table (Create, Modify, Not in template, Unverified, No Comparable Properties, No Change).
- **🆕 Create** — table of template resources missing from Azure (columns: #, Resource, Type, Resource Group)
- **✏️ Modify** — one property diff table per resource (columns: Property, Current Azure Value, Template Value, Severity, Source)
- **Azure only / Not in template** — table of Azure resources absent from the selected template set; this is not a deletion recommendation or proof of ownership. Annotate likely implicit dependencies (e.g. private endpoint NICs or VM OS disks), resources potentially owned by another pipeline/template, and dependencies. Warn that Complete-mode deployments can delete resources not represented in this comparison, including excluded resources; never recommend Complete mode.
- **Confirmed differences** — separate existence and property differences; property tables contain only normalized, confirmed differences. State omissions, default-derived values, read-only properties, and unresolved values separately rather than presenting them as confirmed drift.
- **🆕 Create** — table of template resources confirmed absent from Azure (columns: #, Resource, Type, Resource Group)
- **✏️ Modify** — one property diff table per resource (columns: Property, Current Azure Value, Template Value, Severity, Source)
- **⚠️ Unverified** — resources whose identity, existence or configuration was not verified, with causes and any confirmed drifts
- **No Comparable Properties** — existence-only resources; configuration was not assessed
- **✅ No Change** — collapsible `<details>` section listing matched resources

> **CRITICAL**: property diff tables MUST contain **only** confirmed properties where expected ≠ actual after metadata-defined normalization. Matching properties belong in the collapsed "No Change" section, never mixed into a diff table. Report omissions, defaults, read-only values, unresolved values, and uncertain inventory separately.

**If fully in sync**: report "✅ Fully in sync — all N template resources match `<target>`" and stop.

**If drift is detected**, proceed to Step 9.

### 9. Offer Resolution Options

Present options based on the mode and the drift found.

In Azure mode, first ask whether the templates are authoritative for each affected resource/property and whether another pipeline or owner manages it. A resource name or matching identity is not authorization to change or delete it. Ask for explicit approval before any file edits; obtain per-resource and, for property resolution, per-property direction decisions. Do not assume all resources in one scope share an owner or source of truth.

**Diagram mode:**
1. **Update Bicep** — add diagram-only resources to the templates, remove Bicep-only resources
2. **Update Diagram** — add Bicep-only resources to the diagram, remove diagram-only resources
3. **Selective** — choose per-resource which direction to resolve
4. **No action** — keep the report for reference

**Azure mode:**

| Drift type | Options offered |
|---|---|
| Existence only (Create, Not in template, Name Mismatch) | Update Bicep, Update Azure, Selective, No action |
| Property only | Update Bicep (adopt Azure values), Update Azure (reset to template values), Resolve Property Drifts, No action |
| Both | Update Bicep, Update Azure, Selective, Resolve Property Drifts, No action |

In Azure mode, **Update Bicep** may bring explicitly approved resources/properties in line with observed Azure state. **Update Azure** produces deployment guidance for explicitly approved template-owned resources. Do not remove or deploy against resources merely because they are absent/present in the selected template: confirm ownership and dependencies, including private endpoint NICs, and whether another pipeline manages them.

Wait for the user's choice before proceeding.

### 10. Resolution: Update Bicep

Follow `.github/skills/shared/procedures/resolution-update-bicep.md` with `<source>` = `Diagram` (diagram mode) or `Azure` (Azure mode). That procedure covers the confirmation gate, deployment verification, module placement and generation of added resources, the dependency and empty-template halt checks on removal, the property-update flow for adopting Azure-actual values, and the result summary.

In Azure mode, handle each confirmed Name Mismatch pair as a rename, not a removal plus addition: set the template resource's name (or the parameter value that feeds it) to the Azure name, and include it in the confirmation list.

In Azure mode, never copy secret-bearing values discovered from Azure into templates — declare `@secure()` parameters instead.

### 11. Resolution: Update Diagram (Diagram Mode)

Follow `.github/skills/shared/procedures/resolution-update-diagram.md` with `<source>` = `Bicep`. That procedure covers the confirmation gate, stencil lookup and dual-icon placement, edge cleanup, and the raw-XML save fallback. Its conditional Bicep regeneration step does not apply here — Bicep is the source model, so leave the templates untouched.

### 12. Resolution: Update Azure (Azure Mode)

Follow section **A. Existence-Level Resolution** of `.github/skills/shared/procedures/resolution-update-azure.md` with `<source>` = `Bicep`. The selected templates already describe the expected state, so do **not** generate new Bicep for them. Apply the procedure with these substitutions:

1. **A1** — list the resources to be created, the property drifts to be reset to template values, and the resources to be deleted; require "confirm".
2. **A2** — run the verification ruleset against the existing templates. Report any errors and direct the user to fix the templates first (Update Bicep or a manual edit); do not produce a deployment command for templates with known errors.
3. **A3** — instead of generating Bicep, produce a deployment of the selected entry point and parameter file only after the user approves the deployment mode. Preserve the observed mode (`Incremental` or `Complete`); do not silently override it. If mode is `Unknown`, ask the user to choose before presenting a runnable command. Warn that Complete mode can delete unrepresented and excluded resources; never recommend Complete as a drift resolution default. The deployment can create 🆕 resources, create the template-named resource of each approved ⚠️ Name Mismatch, and reset ✏️ property drifts:
   ```powershell
   az deployment group create --resource-group <rg-name> --template-file <selected-entry-point> --parameters <selected-param-file> --mode <approved-mode>
   ```
   Omit `--parameters` when no parameter file was selected. Use `az deployment sub create --location <region>` instead when the template declares `targetScope = 'subscription'`. Preserve the existing parameter-file format.
4. **A4** — do **not** recommend a Complete-mode deployment: it may also delete resources not represented here, including resources excluded by filter rules. Generate a targeted command only for each explicitly approved Azure-only resource (and per Azure-side resource of a Name Mismatch the user chooses to retire): `az resource delete --ids <resource-id>`. Leave out resources annotated as likely implicit dependencies unless the user explicitly selects them after dependency review.
5. **A5** — present the commands above with the procedure's review warning.

#### Redeploying after changes made outside Bicep

Before presenting the A3 command, gather context and warn about side effects:

1. **Last deployment** — run `az deployment group list --resource-group <rg-name> --query "sort_by([].{name:name, timestamp:properties.timestamp, state:properties.provisioningState}, &timestamp)[-5:]" -o table`. Report when the template was last deployed, or that no deployment matching the entry point was found (the resources may never have been deployed from these templates). Include the known `-BuildVersion`/deployment-mode provenance where available; do not infer missing values.
2. **Who changed what** — for each ✏️ resource, query the Activity Log since that deployment: `az monitor activity-log list --resource-id <resource-id> --start-time <last-deployment-timestamp> --query "[?operationName.value && contains(operationName.value, 'write')].{time:eventTimestamp, caller:caller, op:operationName.value}" -o table`. Show the caller and time next to each drift. That way the user can spot intentional changes made directly in Azure (for example, an incident scale-up) and choose **Accept Azure** for those before redeploying. The Activity Log only keeps 90 days of history; if the last deployment is older than that, say that the change history is incomplete.
3. **Side-effect warnings** — tell the user that the redeploy:
   - resets **every** property the templates declare, including properties this report does not track, so it can change more than the report shows
   - may reset or remove configuration the templates leave out, because ARM replaces a resource's full configuration. Common cases: subnets defined inline on a virtual network (out-of-band subnets are removed, or the deployment fails if they are in use), app settings, NSG rules, and access policies
   - fails on properties that cannot change after creation (such as `location` or some SKU tiers); these need delete-and-recreate
4. **Optional separate preview** — the user may independently choose to run Azure `what-if` as an additional pre-deployment preview. It is not part of drift detection, is never invoked automatically by detection, and does not replace deployment verification or explicit review. Do not use it as a fallback for drift detection or deployment validation, and do not claim it shows every consequence with certainty.

### 13. Resolution: Property Drifts (Azure Mode)

Follow section **B. Property-Level Drift Resolution** of `.github/skills/shared/procedures/resolution-update-azure.md` with `<source>` = `Bicep`, with these substitutions:

- **Update Azure** — the templates already declare the expected value. Offer the targeted CLI command from B2 for that property, or the Step 12 deployment using the explicitly approved deployment mode. If mode is Unknown, resolve it before offering a runnable command. Warn that the deployment resets **every** drifted property of the deployed resources, including ones the user chose to Skip.
- **Accept Azure** — apply via the "Update properties" section of `.github/skills/shared/procedures/resolution-update-bicep.md`, which updates either the module value or the parameter that feeds it.

Note operational impact where relevant — for example, changing `vmSize` requires VM deallocation.

### 14. Resolution: Selective Updates

**14a.** Present per-resource choices in a table (columns: #, Resource, Type, Status, Owner/source of truth, Resolve), and for property drift a per-property decision table. Azure choices require confirmed ownership and dependency review: "Add to Bicep / Leave Azure-only / Skip" for Azure-only resources; "Remove from Bicep / Create in Azure / Skip" for template-only resources; and "Rename in Bicep / Create template-named resource in Azure / Skip" for confirmed name mismatches. Do not treat absence as deletion consent. Do not write any files while collecting choices.

**14b.** Group the approved decisions by direction and apply each bucket via the matching procedure (Steps 10–12). Per-resource choices do not replace the explicit approval gate before file edits or Azure deletion artifacts. Run deployment verification for every resource being added to Bicep before generating its block, then batch approved file writes. "Create in Azure" choices may deploy the whole template; warn that this can affect resources the user chose to Skip, so do not present that deployment as selective.

**14c.** Present a combined summary table (columns: Resource, Type, Action) plus the remaining unresolved drift count.

### 15. No Action

Confirm that the report is for reference only and no changes were made.

- If deletions were detected in Azure mode, remind the user to verify that the exclusions are intentional before running an authoritative deployment
- Suggest reviewing Critical-severity property drifts first
- To prevent recurring drift from changes made outside Bicep, suggest deploying only through a pipeline, or using [Deployment Stacks](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-stacks) with `--deny-settings-mode denyWriteAndDelete`
- Suggest related skills: **azv-diagram-drift-detection** (validate the diagram against Azure), **azv-bicep-policy-check** (check the templates against Azure Policy), **azv-diagram-to-bicep** (regenerate templates from the diagram)

---

## Important Notes

- This skill replaces **azv-bicep-diagram-sync** (diagram mode) and **azv-bicep-whatif** (Azure mode) — both are now target modes of this skill.
- **Diagram mode runs fully offline**; the authentication gate applies only in Azure mode.
- **Azure mode does not use ARM what-if.** It builds both models itself and compares them, which is why unregistered providers are reported as a warning rather than a failure.
- Azure mode is always property-aware — there is no separate quick/deep toggle. Diagram mode is existence-level only, because a diagram does not carry the tracked configuration properties.
- **Destructive operations always require explicit confirmation** — for removing resources from templates, removing diagram elements, and generating Azure deletion artifacts.
- This skill never applies changes to Azure directly; it produces deployment and CLI commands for the user to review and run.
