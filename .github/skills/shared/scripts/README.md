# AzVerify shared scripts

These PowerShell scripts provide the reusable implementation behind AzVerify skill workflows.

## Prerequisites


- **PowerShell 7 (`pwsh`)** is preferred; **Windows PowerShell 5.1 (`powershell.exe`)** is also supported
- **Azure CLI (`az`)** is required for expected-aware Bicep drift detection (`-ExpectedModel`); the legacy discovery path accepts either Azure CLI or the Az PowerShell module
- **Bicep CLI support** via `az bicep` or standalone `bicep` for Bicep parsing/build flows

If a script cannot run because a prerequisite is missing, the calling skill follows the inline fallback in the matching `procedures/` contract (or the Azure MCP fallback for authentication and discovery) instead of stopping.

## Script usage

| Script | Purpose | Typical invocation | Key outputs / notes |
|---|---|---|---|
| `_Common.ps1` | Shared helper functions for JSON IO, diagnostics, matching helpers, and exit handling. | Dot-source from other scripts. | Not called directly by skills. |
| `Test-AzureAuth.ps1` | Verifies an active Azure session before Azure operations. | `pwsh .github/skills/shared/scripts/Test-AzureAuth.ps1` | Emits a JSON auth status object; non-zero exit indicates no Azure session. |
| `ConvertFrom-DrawioDiagram.ps1` | Parses a `.drawio` file into the shared resource model. | `pwsh .github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1 -DiagramPath <file>` | Used by diagram-to-Bicep and sync skills. |
| `ConvertFrom-BicepTemplate.ps1` | Compiles/parses Bicep into the shared resource model. | `pwsh .github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1 -BicepFile <main.bicep> [-ParamFile <file>]` | Prefers `az bicep build` or `bicep build`; emits normalized resources. |
| `Select-AzureResources.ps1` | Applies shared inclusion/exclusion rules for diagram or Bicep scenarios. | `pwsh .github/skills/shared/scripts/Select-AzureResources.ps1 -InputFile <model.json> -Mode diagram` | Uses `data/resource-filter-rules.json`. |
| `Compare-ResourceModels.ps1` | Compares two normalized resource models and classifies matches/drift. | `pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <a.json> -ModelB <b.json> [-CompareProperties]` | Emits summary counts and per-resource match records. `-CompareProperties` adds property-level drift with severity from `data/azure-property-paths.json`. |
| `Get-AzureResourceModel.ps1` | Builds a resource model from live Azure or captured `az resource list` JSON. | `pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -ResourceGroup <rg> [-Enrich] [-StripReadOnly]` | Supports offline mode with `-FromJson`; can enrich properties using `data/azure-property-paths.json`. `-StripReadOnly` removes read-only properties and flags secrets using `data/arm-readonly-properties.json`. |
| `Invoke-Fixtures.ps1` | Runs smoke tests across example fixtures. | `pwsh .github/skills/shared/scripts/Invoke-Fixtures.ps1` | Validates parser/filter/compare flows across `examples/`. |

Opt-in options: `ConvertFrom-BicepTemplate.ps1` accepts ARM JSON/JSONC parameter files, `-ParameterOverride`, `-SubscriptionId/-ResourceGroup/-Location`, `-ResolveDeterministicNames` (offline `uniqueString`/`guid`), `-AnalysisTimestamp` and `-MaskSecrets`.
`Get-AzureResourceModel.ps1 -ExpectedModel` discovers inventory, paginated AMPLS children and expected configuration. `Compare-ResourceModels.ps1 -AzureIdentity -TrackedProperties` compares exact IDs, catalog properties and explicit configuration beyond the catalog, consolidating compatible duplicate declarations and flagging conflicts. Unknown values and failed collection reads remain unverified.
These options are used by `azv-bicep-drift-detection/scripts/Invoke-BicepDriftDetection.ps1`, which also records pipeline/input provenance, deployment mode and build-version uncertainty. Detection is read-only and never invokes what-if.
Run `tests/Test-BicepDriftLessons.ps1`, `tests/Test-AzureDriftPipeline.ps1` and `tests/Test-ArmExpression.ps1` for the offline regression scenarios; the fixture runner includes all three.

## Recommended usage pattern in skills

1. Reference the matching procedure contract in `../procedures/`.
2. Run the script with explicit parameters.
3. Treat stdout JSON as the authoritative machine-readable result.
4. Keep diagnostics on stderr and user-facing summaries in the skill response.