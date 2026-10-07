# Resolution Procedure: Update Azure

Shared procedure for resolving drift by changing the live Azure environment to match a **source model** — a parsed diagram or Bicep model. Covers existence-level resolution (create/delete via generated Bicep) and property-level drift resolution. Referenced by drift-detection skills after the user chooses an "Update Azure" or "Resolve Property Drifts" resolution.

Throughout this procedure, `<source>` is the label of the authoritative model (`Diagram` or `Bicep`).

**Reference files (MUST read before generating Bicep):**

- `.github/skills/shared/azure-deployment-verification.md` — pre-deployment verification rules
- `.github/skills/shared/bicep-best-practices.md` — Bicep authoring rules
- `.github/skills/shared/azure-resource-configs.md` — per-resource-type configuration defaults
- `.github/skills/shared/data/azure-property-paths.json` — tracked properties and severity classifications

> This procedure never applies changes to Azure directly — it generates Bicep (and CLI alternatives) for the user to review and deploy.

---

## A. Existence-Level Resolution (Create / Delete)

### A1. Confirm Destructive Operations

List the resources to create and delete. Warn that Azure deletions are destructive and may cause data loss. **Require the user to type "confirm"** to proceed; any other response returns to the resolution options step.

**Skip this bulk confirmation when running in Selective mode** — per-resource choices were already collected, but still require "confirm" once before generating deletion artifacts.

### A2. Run Deployment Verification

Before generating Bicep, read and run the **full verification ruleset** from `.github/skills/shared/azure-deployment-verification.md`:

1. **SKU dependency rules** — verify companion resources exist
2. **Resource compatibility rules** — verify backend protocols, DNS zones
3. **Networking rules** — verify subnet sizing, no overlaps

Present verification results. Errors must be auto-fixed where possible. Do not generate code with known errors.

### A3. Generate Bicep for Resources to Create

For `<source>`-only resources, generate Bicep templates using `.github/skills/shared/azure-resource-configs.md` and `.github/skills/shared/bicep-best-practices.md`. Generate a `.bicepparam` file with descriptive comments. Follow diagram-to-bicep conventions (`parent:`, `@secure()`, `@description()`, secure defaults).

### A4. Generate Bicep for Resources to Delete

For Azure-only resources that need to be removed, prefer one targeted command per resource (`az resource delete --ids <resource-id>`). Do not recommend a Complete-mode deployment: it also deletes every resource excluded from the drift report by the filter rules.

### A5. Present Output

Show a summary table of generated files (create Bicep + removal notes) with deployment commands (`az deployment group create` or `New-AzResourceGroupDeployment`). Warn the user to review all files before deploying.

---

## B. Property-Level Drift Resolution

Use when matched resources have property drift (deep comparison) and the user chooses to resolve property drifts.

### B1. Present Per-Property Choices

Show a table with columns: #, Property, Expected, Actual, Severity, Action. For each drifted property, offer:

- **Update Azure** — bring the Azure value in line with the expected value
- **Accept Azure** — adopt the Azure-actual value into the source artifacts
- **Skip** — leave the drift unresolved

Wait for per-property decisions.

### B2. "Update Azure" Decisions

Generate a targeted CLI command per drifted property (`az resource update --ids <resource-id> --set <armJsonPath>=<value>`, using the ARM path from `azure-property-paths.json`). When a Bicep artifact is needed, declare the full resource with the expected values — not an `existing` reference, which is read-only and cannot set properties — because an ARM PUT resets unspecified properties to their defaults. Note operational impact where relevant (e.g., changing `vmSize` deallocates the VM).

### B3. "Accept Azure" Decisions

Update `.bicepparam` values (and diagram-specified values, when the source is a diagram carrying property annotations) to match the Azure actuals. Present the changes for confirmation before writing.

### B4. Confirm and Summarize

Show a summary of all resolutions and wait for explicit confirmation before applying any file writes or presenting deployment artifacts. After applying, present a final table: Property, Resolution, Artifact (file/command).
