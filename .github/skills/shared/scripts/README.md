# AzVerify shared scripts

These PowerShell scripts provide the reusable implementation behind AzVerify skill workflows.

## Prerequisites

- **PowerShell 5.1 (`powershell.exe`) and up (`pwsh`)**
- **Azure CLI (`az`)** for Azure-backed scripts
- **Bicep CLI support** via `az bicep` or standalone `bicep` for Bicep parsing/build flows

If a script cannot run because a prerequisite is missing, the calling skill should first check the availability of MCP servers. If they are not available, it should report the prerequisite and stop.

## Script usage

| Script | Purpose | Typical invocation | Key outputs / notes |
|---|---|---|---|
| `_Common.ps1` | Shared helper functions for JSON IO, diagnostics, matching helpers, and exit handling. | Dot-source from other scripts. | Not called directly by skills. |
| `Test-AzureAuth.ps1` | Verifies an active Azure session before Azure operations. | `pwsh .github/skills/shared/scripts/Test-AzureAuth.ps1` | Emits a JSON auth status object; non-zero exit indicates no Azure session. |
| `ConvertFrom-DrawioDiagram.ps1` | Parses a `.drawio` file into the shared resource model. | `pwsh .github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1 -DiagramPath <file>` | Used by diagram-to-Bicep and sync skills. |
| `ConvertFrom-BicepTemplate.ps1` | Compiles/parses Bicep into the shared resource model. | `pwsh .github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1 -BicepFile <main.bicep> [-ParamFile <file>]` | Prefers `az bicep build` or `bicep build`; emits normalized resources. |
| `Select-AzureResources.ps1` | Applies shared inclusion/exclusion rules for diagram or Bicep scenarios. | `pwsh .github/skills/shared/scripts/Select-AzureResources.ps1 -InputFile <model.json> -Mode diagram` | Uses `data/resource-filter-rules.json`. |
| `Compare-ResourceModels.ps1` | Compares two normalized resource models and classifies matches/drift. | `pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <a.json> -ModelB <b.json>` | Emits summary counts and per-resource match records. |
| `Get-AzureResourceModel.ps1` | Builds a resource model from live Azure or captured `az resource list` JSON. | `pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -ResourceGroup <rg> [-Enrich]` | Supports offline mode with `-FromJson`; can enrich properties using `data/azure-property-paths.json`. |
| `Invoke-Fixtures.ps1` | Runs smoke tests across example fixtures. | `pwsh .github/skills/shared/scripts/Invoke-Fixtures.ps1` | Validates parser/filter/compare flows across `examples/`. |

## Recommended usage pattern in skills

1. Reference the matching procedure contract in `../procedures/`.
2. Run the script with explicit parameters.
3. Treat stdout JSON as the authoritative machine-readable result.
4. Keep diagnostics on stderr and user-facing summaries in the skill response.