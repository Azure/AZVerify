# Bicep Parsing Script Contract

Canonical contract for `.github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1`. Referenced by skills that analyze existing Bicep files.

---

## Script

- **Path**: `.github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1`
- **Purpose**: Parse Bicep or ARM JSON templates and optional parameter inputs into the shared Azure resource model.

## Invocation

```powershell
pwsh .github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1 -BicepFile <entry-point.bicep|template.json> [-ParamFile <existing-parameter-file>] [-Depth shallow|standard|deep] [-OutFile <path>]
```

## Parameters

- `-BicepFile` — required path to the deployment entry point; may be Bicep or an ARM JSON template. Its name need not be `main.bicep`
- `-ParamFile` — optional parameter file in its existing format, including `.bicepparam` or ARM JSON parameters; do not convert the file
- `-ParameterOverride` — optional explicit parameter values supplied by the orchestrator; these are authoritative over file/default values
- `-AnalysisTimestamp` — optional stable timestamp used to synthesize deterministic `utcNow()` values for analysis; it is analysis input, not evidence of deployment time
- `-Depth` — optional extraction depth; defaults to `standard`
- `-OutFile` — optional output path; otherwise JSON is written to stdout

## Output

- **stdout**: Single resource model JSON object conforming to `.github/skills/shared/azure-resource-model.md`
- **stderr**: Diagnostics only

## Exit Codes

- `0` — parse succeeded
- non-zero — parse failed; stop and report the error

## Notes

- Bicep input requires `az bicep build` or standalone `bicep build`; ARM JSON input is parsed directly. If Bicep compilation is unavailable, the script exits with a non-zero code; the calling skill should then follow the inline fallback below.
- If `pwsh` or the script is unavailable, use the inline fallback below.
- Establish entry-point and input provenance from the actual deployment references. A pipeline file supplied as `-PipelineFile` is reference/provenance only, not a YAML evaluator. The orchestrator passes only explicitly resolved overrides to the parser; `-ParameterOverride` values are authoritative over file/default values. Supported provenance labels are `ExplicitInput`, `CurrentPipeline`, and `HistoricalFallback` (`ExplicitInput` by default); historical parameter inputs are not proof of current deployed values. Record known deployment mode (`Incremental`, `Complete`, or `Unknown`, default `Unknown`) and build version when supplied.
- The compiled ARM JSON is evaluated offline by `_ArmExpression.ps1` for the deterministic constructs it explicitly supports: parameters, variables, user-defined and imported functions (e.g. `getName` / `getNameForComponent` from `commonTypesAndFunctions/namingconvention.bicep`), module deployments, conditions and copy loops. Each copy-loop iteration becomes its own resource with `symbolicName` suffixed `[i]`.
- Resources whose `condition` evaluates to `false` are omitted. `existing` resources are skipped.
- For deterministic `utcNow()` analysis, pass `-AnalysisTimestamp`; any synthesized value is analysis-only, not proof of the value used by a past/current deployment. Do not interpret that timestamp as the deployment time. Values that depend on deployment-time state or unsupported expressions/macros remain explicitly unresolved. Do not invent values or substitute resource-catalog defaults. Functions such as `guid()` and `uniqueString()` are resolved only when all required inputs and semantics are known to the parser; otherwise emit `<unresolved: reason>`. Preserve each resolved property's provenance (template default, parameter file, explicit override, analysis-time synthetic value, or unresolved source) and the associated uncertainty.
- Emit `diagnostics.parameters` and `diagnostics.parameterScopes` metadata tables in the model/report so callers can inspect parameter resolution, scope, and provenance without treating guessed or historical values as current proof.
- stderr ends with a summary: either `Resolved all N resource name(s).` or a `WARNING` listing each resource whose `name` contains `<unresolved:`.

## Script Unavailable — Inline Fallback

If `pwsh`/`powershell.exe` is not available or the script cannot run, parse the Bicep directly:

1. Read the selected entry-point template and follow its template/module references recursively; the entry point need not be named `main.bicep`. For ARM JSON, read resource declarations and nested deployments/references.
2. For each resource declaration, capture its symbolic name, `type`, `apiVersion`, name, top-level and nested properties, and source-file provenance.
3. If a parameter file is provided, preserve its format and substitute only its supported, explicit values and template parameter defaults. Apply authoritative explicit `ParameterOverride` values last. Apply a supplied stable `AnalysisTimestamp` only to synthetic `utcNow()` evaluation, labeling those values analysis-only. Mark values based on historical parameter files as `HistoricalFallback`, not current-pipeline proof. Record unsupported expressions/macros as unresolved; never guess values from resource configuration catalogs. Include parameter and parameter-scope diagnostics metadata.
4. Map child resources declared with `parent:` to a `contains` relationship on the parent.
5. Emit a resource model JSON conforming to `.github/skills/shared/azure-resource-model.md`.
