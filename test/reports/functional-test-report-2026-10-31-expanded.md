# AzVerify Expanded Functional Test Report

**Run date:** 2026-10-31
**Run id:** `2026-10-31-expanded`
**Scope:** Method-coverage expansion with complex fixtures
**Azure test groups:** `AzVerify1`, `AzVerify2`
**Result:** 1 PASS, 2 PARTIAL, 3 FAIL, 1 BLOCKED

## Environment and integration availability

- Azure subscription: `Azure subscription 1` (`9bd9…d9d2`)
- Regions: both test groups in `swedencentral`
- Runtime: Azure CLI 2.91.0, PowerShell 7.6.9, Bicep CLI 0.48.1
- Integration visibility in this runtime:
  - Draw.io MCP: **not exposed**
  - Azure best-practice/schema MCP: **not exposed**
  - Bicep MCP: **not exposed**

Because Draw.io MCP was not exposed to this session, MCP-dependent branches were marked `PARTIAL`/`BLOCKED` and fallback branches were executed.

## Fixture setup

Expanded fixture deployment succeeded in both test groups using `test/assets/complex/`:

- `AzVerify1`: 11 expanded resources + existing baseline storage account
- `AzVerify2`: 8 expanded resources
- Bidirectional VNet peering configured
- Policy assignment cleanup verified (no residual assignments in `AzVerify2`)

Evidence:

- `test/artifacts/2026-10-31-expanded/method-status.tsv`
- `test/artifacts/2026-10-31-expanded/azure-expanded-raw.json`
- `test/artifacts/2026-10-31-expanded/drift-rg1/*`
- `test/artifacts/2026-10-31-expanded/drift-rg2/*`

## Skill status summary

| Skill | Status | Method coverage exercised | Evidence |
|---|---|---|---|
| `azv-azure-to-bicep` | **FAIL** | `Get-AzureResourceModel` live RG, `-Mode bicep`, `-Enrich`, `-StripReadOnly`, offline `-FromJson`, Bicep parse/build | `method-status.tsv`, `get-rg1-bicep-enrich.err`, `get-rg2-bicep-enrich.err` |
| `azv-azure-to-diagram` | **PARTIAL** | Complex fallback diagram generation, parser round-trip, live RG discovery/filtering | `complex-scenario.drawio`, `diagram-model.json`, `azure-rg1-diagram.json` |
| `azv-bicep-drift-detection` | **FAIL** | Fast-path drift runs for both RGs, complete reports, metric output | `drift-rg1/drift-report.md`, `drift-rg2/drift-report.md` |
| `azv-bicep-policy-check` | **PASS** | `checkPolicyRestrictions` probe + ARM validate cross-check + cleanup | `policy-probe.out` |
| `azv-diagram-drift-detection` | **FAIL** | Quick/deep comparisons on complex diagram vs live model | `compare-quick-rg1.json`, `compare-deep-rg1.json` |
| `azv-diagram-to-bicep` | **PARTIAL** | Complex diagram parser path + Bicep conversion/compile from complex templates | `convert-bicep-rg1.err`, `convert-bicep-rg2.err` |
| `azv-sketch-to-diagram` | **BLOCKED** | MCP-required sketch generation branch | Draw.io MCP unavailable in this runtime |

## Method-level execution matrix (high-value branches)

| Method branch | Result | Notes |
|---|---|---|
| Shared fixture smoke suite (`Invoke-Fixtures.ps1`) | PASS | 24 checks passed |
| Complex fixture deployment (`Deploy-ComplexFixtures.ps1`) | PASS | Both RGs deployed; peering succeeded |
| Complex fallback diagram generation (`New-ScenarioDiagram.ps1`) | PASS | 26 resources, 12 edges |
| Live discovery RG1 no enrich (`Get-AzureResourceModel -Mode diagram`) | PASS | 12 discovered, 9 after diagram filtering |
| Live discovery RG1 enrich | FAIL | `az resource show` API-version mismatch for Network resources |
| Live discovery RG2 enrich | FAIL | Same failure class on route tables |
| Offline replay (`-FromJson`) | PASS | 19 resources processed (with and without enrich) |
| Extra exclusion (`Select-AzureResources -ExtraExclude`) | PASS | NICs excluded as expected |
| Bicep parse complex RG1 (`ConvertFrom-BicepTemplate`) | PASS | 17 resources resolved |
| Bicep parse complex RG2 (condition false branch) | PASS | 13 resources resolved; monitoring skipped |
| Diagram drift quick/deep compare | PASS (execution), FAIL (quality) | Executed successfully; output quality defect captured below |
| Drift fast path RG1/RG2 | PASS (execution), FAIL (quality) | Completed with deterministic false-positive drift |
| Policy restrictions probe | PASS | evaluationCount=1; deny correctly detected and assignment cleaned |

## Findings and suggested fixes

### 1) HIGH — Enriched live discovery fails on valid resources due unsupported API version selection

**Affected:** shared discovery path used by `azv-azure-to-bicep`, `azv-azure-to-diagram`, and deep drift comparisons.
**Observed:** `Get-AzureResourceModel.ps1 -Enrich` fails on `Microsoft.Network/networkSecurityGroups` and `Microsoft.Network/routeTables` in `swedencentral` with `NoRegisteredProviderFound` for API version `2026-07-01`, while provider metadata only supports up to `2026-05-01` for these types.
**Repro:** `test/artifacts/2026-10-31-expanded/get-rg1-bicep-enrich.err` and `get-rg2-bicep-enrich.err`.
**Suggested fix:** bound `az resource show` API version to a supported version from provider metadata (or omit explicit API version selection for show operations when not required).

### 2) HIGH — Fast-path Bicep drift reports false property drift for equivalent values

**Affected:** `azv-bicep-drift-detection` comparison output quality.
**Observed:** both RG runs report `addressPrefixes` drift where rendered Bicep and Azure values are both `{"Length":12}` in report output.
**Repro:** `test/artifacts/2026-10-31-expanded/drift-rg1/drift-report.md`, `drift-rg2/drift-report.md`.
**Suggested fix:** normalize array/object values consistently before drift classification and render concrete value diffs instead of object-length tokens.

### 3) MEDIUM — Deep diagram drift still provides limited value with diagram-only metadata

**Affected:** `azv-diagram-drift-detection` deep-mode interpretation.
**Observed:** quick/deep comparisons execute, but expected-value coverage remains weak when diagrams lack explicit configuration properties; deep mode can execute without actionable property checks for many resources.
**Repro:** `compare-deep-rg1.json` (summary indicates no property-drift detail despite complex topology mismatch).
**Suggested fix:** require explicit expected-property sources (diagram metadata/defaults) per tracked path, and report non-comparable property coverage as incomplete.

### 4) INFO — Policy-check regression from first run did not reproduce

**Affected:** `azv-bicep-policy-check`.
**Observed:** in this run, `checkPolicyRestrictions` returned `evaluationCount=1` and aligned with ARM validation deny.
**Repro:** `policy-probe.out`.
**Suggested follow-up:** keep this probe in regression runs because behavior changed between runs.

## Cleanup and retained state

- Temporary policy assignment removed successfully.
- Complex fixtures intentionally retained for repeatable testing:
  - `AzVerify1`: baseline + expanded fixture
  - `AzVerify2`: expanded fixture
- Artifacts retained under `test/artifacts/2026-10-31-expanded/`.
