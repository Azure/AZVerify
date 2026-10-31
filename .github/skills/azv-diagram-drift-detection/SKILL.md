---
name: azv-diagram-drift-detection
description: Detect existence drift and compare explicitly expected diagram configuration against a live Azure environment. Supports quick existence-only and deep property comparison, then offers resolution — update the diagram, update Azure, resolve per property, or selectively resolve per resource. Replaces the former azv-diagram-azure-sync and azv-diagram-azure-sync-deep skills.
license: MIT
compatibility: Requires an authenticated Azure session (CLI, Az PowerShell, or Azure MCP).
metadata:
  version: "2.0"
  project: AzVerify
---

Compare a Draw.io Azure architecture diagram against a live Azure environment and resolve the drift that is found. Supports two modes: **quick** (existence only) and **deep** (existence plus comparison of explicitly expected configuration properties).

**Input**: A Draw.io diagram file (`.drawio` or `.drawio.xml`) and an Azure scope — a resource group name or subscription ID. The user can specify both, or the skill will prompt for missing inputs.

**Tools**: File system tools (read/write files), Terminal (for running PowerShell 7 / `pwsh` shared scripts and `az` CLI commands), Azure MCP server tools, Draw.io MCP — attempt `mcp_drawio_create_diagram` first; if the tool is not found, fall back to `mcp_draw_io_create_diagram`.

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-stencil-mapping.json` — Azure resource type to Draw.io stencil mapping
- `.github/skills/shared/azure-deployment-verification.md` — Pre-deployment verification rules
- `.github/skills/shared/azure-resource-configs.md` — Per-resource-type configuration schemas with defaults
- `.github/skills/shared/data/azure-property-paths.json` — Tracked properties, ARM JSON paths, defaults, severity classifications

**Shared procedures** (MUST follow):
- `.github/skills/shared/procedures/azure-authentication.md` — Azure session check
- `.github/skills/shared/procedures/diagram-parsing.md` — Diagram-to-resource-model parsing
- `.github/skills/shared/procedures/azure-discovery.md` — Live Azure discovery and property enrichment
- `.github/skills/shared/procedures/resource-filtering.md` — Resource exclusion rules (`-Mode diagram`)
- `.github/skills/shared/procedures/resource-matching.md` — Resource matching and property comparison
- `.github/skills/shared/procedures/resolution-update-diagram.md` — "Update Diagram" resolution flow
- `.github/skills/shared/procedures/resolution-update-azure.md` — "Update Azure" and property-drift resolution flows
- `.github/skills/shared/procedures/output-budget.md` — Report sizing rules

---

## Output Budget Rules

Follow `.github/skills/shared/procedures/output-budget.md` strictly. In addition:

- Keep all resource models in temporary JSON files (`diagram-model.json`, `azure-model.json`, `match-report.json`) in `<work-dir>` = `.azverify-tmp/` in the diagram's folder (never outside the repository — see rule 6 of the output budget), and reference them by path between steps instead of echoing their contents.
- Never echo Draw.io XML in the response — show the file path and a change summary only.
- Delete the intermediate JSON files once the drift report has been presented and any chosen resolution has been applied.

## Fallback: pwsh Unavailable

If `pwsh`/`powershell.exe` or a shared script cannot be executed, use the inline fallback in the matching procedure contract and continue the workflow:

| Step | Fallback source |
|------|-----------------|
| 1 — Auth check | `.github/skills/shared/procedures/azure-authentication.md` |
| 3 — Diagram parsing | `.github/skills/shared/procedures/diagram-parsing.md` |
| 4 — Azure discovery and enrichment | `.github/skills/shared/procedures/azure-discovery.md` |
| 4 — Filtering | `.github/skills/shared/procedures/resource-filtering.md` |
| 5 — Comparison | `.github/skills/shared/procedures/resource-matching.md` |

Announce the fallback once: "Script execution failed. Please review the script file. Using fallback method now."

## Steps

### 1. Check Azure Authentication

Run `pwsh .github/skills/shared/scripts/Test-AzureAuth.ps1` — see `.github/skills/shared/procedures/azure-authentication.md` for the script contract. A **non-zero exit code is a HARD GATE**: present the authentication instructions from the contract doc and stop. *(If pwsh or the script is unavailable, see "Fallback: pwsh Unavailable".)*

### 2. Accept Inputs

Identify the comparison depth, the Draw.io diagram, and the Azure scope.

#### 2a. Identify Comparison Depth

- **Quick** (default): existence-only comparison — are the right resources deployed? It does not check configuration.
- **Deep**: compare existence plus configuration values explicitly supplied as diagram annotations or by the diagram's selected baseline (see `procedures/diagram-parsing.md`). Only those expected properties are compared; `azure-property-paths.json` supplies tracked property names and Azure retrieval paths, not default expected values.

If the user says "deep", "detailed", "full", "property", or "configuration" → use deep mode. Otherwise default to quick, and mention that deep mode is available.

#### 2b. Identify the Draw.io Diagram

**If the user specifies a file path:**
- Verify the file exists and is a `.drawio` or `.drawio.xml` file

**If no file is specified:**
- Search the workspace for `.drawio` files
- If exactly one is found, use it (announce which file)
- If multiple are found, present the list and ask the user to select one
- If none are found, ask the user to provide a diagram file

#### 2c. Identify the Azure Scope

**If the user specifies a resource group:**
- Use that resource group as the comparison scope
- Verify it exists: run `az group show --name <name>` (or `Get-AzResourceGroup -Name <name>`, or `mcp_azure_group_list`) — if all available methods fail, report an error and stop

**If the user specifies a subscription:**
- Use that subscription as the comparison scope, and warn that subscription-level comparison can be noisy

**If no scope is specified:**
- Check whether the diagram contains resource group containers — if so, confirm with the user: "The diagram shows resources in resource group `<name>`. Should I compare against that resource group?"
- If the scope cannot be inferred, ask: "Which Azure resource group or subscription should I compare this diagram against?"

### 3. Parse Diagram into Resource Model

Run `pwsh .github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1 -DiagramPath <diagram-file> -OutFile <work-dir>/diagram-model.json` — see `.github/skills/shared/procedures/diagram-parsing.md` for the script contract. If the script exits non-zero or produces output that is not valid JSON, use the fallback method in the contract.

Report the parsed resource count. Display the model as a table (columns: #, Resource, Type, Container) only when it stays within the output thresholds in `output-budget.md`.
For deep mode, also report how many expected configuration properties came from annotations and the selected baseline. If none are present, state that configuration is not assessed; do not imply that quick mode checks configuration.

### 4. Discover the Azure Environment

Run the shared discovery script, enriched and filtered in one call — see `.github/skills/shared/procedures/azure-discovery.md` for the script contract:

```powershell
# Resource group scope
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -ResourceGroup <rg-name> -Enrich -Mode diagram -OutFile <work-dir>/azure-model.json

# Subscription scope
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -SubscriptionId <sub-id> -Enrich -Mode diagram -OutFile <work-dir>/azure-model.json
```

Notes:
- `-Enrich` populates each resource's `properties` bag with the tracked properties from `azure-property-paths.json` (applying SKU extraction and composite rules such as VM `osImage`). Enrichment is required for deep mode and harmless in quick mode — run it in both so a mode switch does not require re-discovery. On very large scopes, quick mode may omit `-Enrich` to save time; say so if you do.
- Do **not** pass `-StripReadOnly` — drift comparison needs the full property bag.
- `-Mode diagram` applies the "Exclude for Diagrams" rules, so no separate `Select-AzureResources.ps1` call is needed.
- Enrichment issues one detail call per resource; report a single summary line after the batch (e.g. "Discovered 24 resources, enriched 24 (1 partial)"), not one line per resource.
- If a resource's properties cannot be retrieved (API error, timeout, insufficient permissions), its tracked properties are recorded as `unknown` — continue with the remaining resources rather than aborting.
- If the script exits non-zero or emits unparseable output, use the inline fallback in the discovery contract.
- If the result count is zero and the resource group was confirmed to exist in Step 2c, warn that the authenticated identity may lack Reader permissions.

### 5. Compare Models and Identify Drift

Run the comparison script — see `.github/skills/shared/procedures/resource-matching.md` for the script contract. The diagram is the **expected** model (A), Azure is the **actual** model (B):

```powershell
# Quick mode
pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <work-dir>/diagram-model.json -ModelB <work-dir>/azure-model.json -LabelA Diagram -LabelB Azure -OutFile <work-dir>/match-report.json

# Deep mode
pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <work-dir>/diagram-model.json -ModelB <work-dir>/azure-model.json -LabelA Diagram -LabelB Azure -CompareProperties -OutFile <work-dir>/match-report.json
```

Use the emitted match report as the authoritative comparison result. Existence-level classifications: **In Sync**, **In Sync (name differs)**, **Diagram Only**, **Azure Only**.
The comparator carries `propertySources` and a `coverage` object in each property comparison. Use `coverage.notSpecifiedProperties` as the **Not specified — not assessed** list; `coverage.status` distinguishes **Complete**, **Incomplete**, and **Not Applicable** coverage. Deep mode must report `specifiedCount` of `trackedCount` and list the unassessed paths. Do not treat partial coverage as a complete configuration check.

**Deep mode additions** — the report's `propertyComparison` object per matched resource gives:
- Expected values supplied by the diagram model, and their provenance from its `propertySources` map (`annotation` or `selectedBaseline:<name>`)
- Drifted properties with expected value, actual Azure value, and severity
- Refined matched-resource status: **In Sync (all specified properties match)** or **In Sync (properties drifted)**
- `Incomplete` when any specified expectation is unknown/unresolved; this never means confirmed configuration agreement

Handle the two edge cases explicitly:
- A property whose actual value is `unknown` (retrieval failed in Step 4) is reported as `⚠️ Unknown` — never classified as matching or drifting.
- A matched resource with no comparable tracked properties is reported as `No Comparable Properties`, not as in sync.
- For each matched resource, explicitly report tracked properties with no diagram annotation or selected-baseline expectation as **Not specified — not assessed**. Do not infer defaults from the retrieval mapping or describe an existence-only report as a configuration check.
- Include the comparator's coverage status and specified/tracked counts per resource. When coverage is **Incomplete**, describe property comparison as incomplete even if all supplied expectations match.

### 6. Present the Drift Report

**Quick mode**: existence-only summary table (In Sync / Diagram Only / Azure Only counts) plus a details table (Resource, Type, Status, Notes). State that configuration was not checked.

**Deep mode**: two-tier report.
- **Tier 1 — Summary** with columns: Resource, Type, Existence, Critical, Warning, Info.
- **Tier 2 — Per-resource property diffs** with columns: Property, Expected, Actual, Severity, Source (`annotation` or `selectedBaseline:<name>`).
- Include a separate **Not specified — not assessed** list per resource for tracked properties without an expected value. This is a coverage gap, not drift. If no expected configuration values were supplied, say so plainly; deep mode still reports existence.

> **CRITICAL**: property drift tables MUST contain **only** properties where expected ≠ actual after normalization. Properties that match belong in a separate "Confirmed In Sync" table (columns: Property, Value). Never mix matching and drifting properties in the same table.

**If fully in sync**: quick mode may say "Existence matches; configuration was not checked." Deep mode may say "All specified configuration expectations match" only if every specified value was verified and at least one was compared; disclose all unassessed properties. Never call an existence-only or incomplete deep-mode result fully configuration-synchronized.

**If drift is detected**, proceed to Step 7.

### 7. Offer Resolution Options

Present resolution options based on the drift found:

| Drift type | Options offered |
|---|---|
| Existence only | Update Diagram, Update Azure, Selective, No action |
| Property only (deep mode) | Resolve Property Drifts, No action |
| Both (deep mode) | Update Diagram, Update Azure, Selective, Resolve Property Drifts, No action |

Describe each option briefly:
1. **Update Diagram** — add Azure-only resources to the diagram, remove diagram-only resources
2. **Update Azure** — generate Bicep to create diagram-only resources and remove Azure-only resources
3. **Selective** — choose per-resource which direction to resolve
4. **Resolve Property Drifts** — decide per property whether to update Azure or accept the Azure value
5. **No action** — keep the report for reference

Wait for the user's choice before proceeding.

### 8. Resolution: Update Diagram

Follow `.github/skills/shared/procedures/resolution-update-diagram.md` with `<source>` = `Azure`. That procedure covers the confirmation gate, stencil lookup and dual-icon placement, edge cleanup, the raw-XML save fallback, conditional Bicep regeneration when `main.bicep` and a `.bicepparam` exist next to the diagram, and the result summary.

### 9. Resolution: Update Azure

Follow section **A. Existence-Level Resolution** of `.github/skills/shared/procedures/resolution-update-azure.md` with `<source>` = `Diagram`. That procedure covers the "confirm" gate, deployment verification, Bicep generation for creates, removal artifacts for deletes, and the output summary.

### 10. Resolution: Selective Updates

**10a.** Present per-resource choices in a table (columns: #, Resource, Type, Status, Resolve). Offer direction-specific options: Diagram Only → "Create in Azure / Remove from diagram / Skip"; Azure Only → "Add to diagram / Delete from Azure / Skip". Do not write any files while collecting choices.

**10b.** Group the decisions into two buckets — diagram updates (Step 8 flow) and Azure updates (Step 9 flow) — and apply each bucket's confirmation gate separately. Skip the bulk confirmations inside the procedures; the per-resource choices replace them, except the "confirm" gate before generating Azure deletion artifacts, which still applies once.

**10c.** Present a combined result: what changed in each direction, and what was skipped.

### 11. Resolution: Property Drifts (Deep Mode Only)

Follow section **B. Property-Level Drift Resolution** of `.github/skills/shared/procedures/resolution-update-azure.md`. That procedure covers per-property choices (Update Azure / Accept Azure / Skip), targeted CLI commands and full-resource Bicep snippets, `.bicepparam` updates for accepted Azure values, and the final confirmation gate.

Note operational impact where relevant — for example, changing `vmSize` requires VM deallocation.

### 12. No Action

Confirm that the report is for reference only and no changes were made. Suggest related skills: **azv-diagram-to-bicep** (generate Bicep from the diagram), **azv-azure-to-diagram** (regenerate the diagram from Azure), **azv-bicep-drift-detection** (validate the Bicep templates instead).

---

## Important Notes

- **When the diagram is updated (Step 8 or selective Step 10), Bicep files are regenerated automatically** if they already exist in the diagram's directory.
- **Destructive operations always require explicit confirmation** — both for deleting Azure resources and for removing diagram elements.
- This skill never applies changes to Azure directly; it generates Bicep and CLI alternatives for the user to review and deploy.
- Never write secret values into generated artifacts — use `@secure()` parameters.
