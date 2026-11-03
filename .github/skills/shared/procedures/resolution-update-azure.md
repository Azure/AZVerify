# Resolution Procedure: Update Azure

Shared procedure for resolving drift by changing the live Azure environment to match a **source model** — a parsed diagram or Bicep model. Covers existence-level resolution and property-level drift resolution. Referenced by drift-detection skills after the user chooses an "Update Azure" or "Resolve Property Drifts" resolution. Observed names/IDs are not authorization to change or delete resources.

Throughout this procedure, `<source>` is the label of the authoritative model (`Diagram` or `Bicep`).

**Reference files (MUST read before generating Bicep):**

- `.github/skills/shared/azure-deployment-verification.md` — pre-deployment verification rules
- `.github/skills/shared/bicep-best-practices.md` — Bicep authoring rules
- `.github/skills/shared/azure-resource-configs.md` — per-resource-type configuration defaults
- `.github/skills/shared/data/azure-property-paths.json` — tracked properties and severity classifications

> This procedure never applies changes to Azure directly — it generates deployment guidance/CLI alternatives for the user to review and run. Require explicit approval for each affected resource and property before preparing changes; confirm ownership/source of truth, other pipeline management, and dependencies (including private endpoint NICs). Do not infer consent from a resource's presence, absence, or name.

---

## A. Existence-Level Resolution (Create / Delete)

### A1. Confirm Destructive Operations

List resources to create and delete, identify their owner/source of truth and relevant dependencies, and obtain per-resource decisions. Warn that Azure deletions are destructive and may cause data loss. **Require the user to type "confirm"** before generating deletion artifacts; any other response returns to the resolution options step.

**Skip this bulk confirmation when running in Selective mode** — per-resource choices were already collected, but still require "confirm" once before generating deletion artifacts.

### A2. Run Deployment Verification

Before preparing deployment artifacts, read and run the **full verification ruleset** from `.github/skills/shared/azure-deployment-verification.md`:

1. **SKU dependency rules** — verify companion resources exist
2. **Resource compatibility rules** — verify backend protocols, DNS zones
3. **Networking rules** — verify subnet sizing, no overlaps
4. **Security rules** — verify TLS, HTTPS, and secure-parameter requirements
5. **Version currency rules** — verify runtime stacks and API versions

Present verification results. Errors must be fixed where possible. Do not generate deployment artifacts for known-invalid templates. Deployment verification is distinct from `what-if`; a `what-if` preview is not a fallback for failed validation or drift detection.

### A3. Prepare Deployment for Resources to Create

For `<source>`-only resources, generate Bicep templates using `.github/skills/shared/azure-resource-configs.md` and `.github/skills/shared/bicep-best-practices.md`, unless `<source>` is Bicep and the existing approved template is the deployment source. Preserve existing parameter-file format. Do not invent values for unresolved inputs; disclose defaults and provenance when a documented default is used.

### A4. Prepare Targeted Removal Actions

For Azure-only resources explicitly approved for removal, prefer one targeted command per resource (`az resource delete --ids <resource-id>`). Confirm dependencies and ownership first. Do not recommend a Complete-mode deployment: it may also delete resources not represented in this comparison, including resources excluded by filter rules. Respect the deployment mode identified from actual pipeline references; if unknown, state that it is unknown rather than assuming Incremental.

### A5. Present Output

Show a summary of generated/selected files and targeted removal commands. Present deployment commands with the identified deployment mode; do not silently change a pipeline's mode. Warn the user to review all artifacts and the full deployment impact before running them.

---

## B. Property-Level Drift Resolution

Use when matched resources have property drift (deep comparison) and the user chooses to resolve property drifts.

### B1. Present Per-Property Choices

Show a table with columns: #, Property, Expected, Actual, Severity, Action. For each confirmed, writable drifted property, offer a separate decision:

- **Update Azure** — bring the Azure value in line with the expected value
- **Accept Azure** — adopt the Azure-actual value into the source artifacts
- **Skip** — leave the drift unresolved

Wait for per-property decisions.

### B2. "Update Azure" Decisions

Generate a targeted CLI command per drifted property (`az resource update --ids <resource-id> --set <armJsonPath>=<value>`, using a validated ARM path; use `azure-property-paths.json` where it defines that property). For explicit properties outside the catalog, validate the ARM path and writability before offering a command. When a Bicep artifact is needed, declare the full resource with the approved expected values — not an `existing` reference, which is read-only and cannot set properties — because an ARM PUT resets unspecified properties to their defaults. Note operational impact where relevant (e.g., changing `vmSize` deallocates the VM).

### B3. "Accept Azure" Decisions

Update values in the existing parameter-file format (and diagram-specified values, when the source is a diagram carrying property annotations) to match approved Azure actuals. Do not adopt omissions, default-derived values, read-only/provider-maintained values, or unresolved observations as confirmed differences. Present the changes for explicit confirmation before writing.

### B4. Confirm and Summarize

Show a summary of each approved resource/property resolution and wait for explicit confirmation before applying any file writes or presenting deployment artifacts. After applying, present a final table: Property, Resolution, Artifact (file/command).

`what-if` is an optional, separate pre-deployment preview only. Never invoke it as part of detection or as a substitute for deployment verification; it does not authorize or apply changes.
