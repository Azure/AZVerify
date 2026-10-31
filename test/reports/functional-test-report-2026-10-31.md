# AzVerify Skill Functional Test Report

**Run date:** 2026-10-31
**Scope:** All seven repository skills in `.github/skills/`
**Azure test groups:** `AzVerify1` and `AzVerify2`
**Result:** 2 PASS, 2 PARTIAL, 2 FAIL, 1 BLOCKED

## Summary by skill

| Skill | Status | Test performed | Result |
|---|---|---|---|
| `azv-azure-to-bicep` | **PASS** | Auth, live discovery, enriched extraction, read-only stripping, Bicep build and ARM validation | Discovered and enriched one tagged storage account. Confirmed deployable values are available separately from the raw ARM properties. Generated test Bicep validated without deployment. |
| `azv-azure-to-diagram` | **PARTIAL** | Live discovery, filtering, diagram output, then parse-back | Produced `test/artifacts/2026-10-31/azverify1/azverify1.drawio` and `original-request.md`. The parser recognized the resource-group container and storage account. Draw.io MCP/visual validation was unavailable; the skill's direct-file fallback was used. |
| `azv-bicep-drift-detection` | **PASS** | Azure fast path baseline, reversible access-tier drift, and restored baseline | Baseline reported `COMPLETE`, one `No Change`; Hot→Cool reported one `Modify` for `accessTier`; after restoring Hot, the generated modular template reported `COMPLETE`, one `No Change`. |
| `azv-bicep-policy-check` | **FAIL** | API check against a temporary deny assignment, cross-checked with non-deploying ARM validation | ARM validation returned `RequestDisallowedByPolicy`, but `checkPolicyRestrictions` returned no evaluations or field restrictions. The skill's empty-result rule would classify this resource as compliant. The test helper exited non-zero as intended and removed the temporary assignment. |
| `azv-diagram-drift-detection` | **FAIL** | Quick and deep comparisons of a parsed diagram with the live resource group; explicit-property comparison control | Quick mode reported the diagram's resource-group container as `Diagram Only`, although the storage account matched. Deep mode returned `No Comparable Properties` (0 compared) for the matched storage account. An explicit synthetic `accessTier` expectation did produce the expected property drift. |
| `azv-diagram-to-bicep` | **PARTIAL** | Generated modular Bicep and `.bicepparam` from the test diagram | Main template, module, and parameters compiled; `az deployment group validate` succeeded without deployment. Bicep MCP best-practice validation was unavailable; shared guidance and CLI validation were used. |
| `azv-sketch-to-diagram` | **BLOCKED** | Existing sketch example's diagram was covered by parser smoke tests | Sketch conversion itself was not run: the required Draw.io MCP was unavailable and this skill has no documented direct-file fallback. |

## Shared fixture suite

Ran `.github/skills/shared/scripts/Invoke-Fixtures.ps1` against all four example scenarios. **All 24 checks passed**: Draw.io parsing, Bicep and parameter compilation, filtering, and comparison completed with non-empty models. The fixture comparison reports also contained multiple unmatched resources; this runner is a smoke suite and does not assert full diagram/Bicep equivalence.

| Fixture | Diagram resources | Bicep resources → filtered | Comparison: in sync / name differs / diagram only / Bicep only | Checks |
|---|---:|---:|---|---|
| `azure-to-diagram-contoso-notify` | 12 | 16 → 11 | 0 / 6 / 6 / 5 | PASS |
| `azure-to-diagram-contoso-voting` | 7 | 12 → 7 | 0 / 6 / 1 / 1 | PASS |
| `description-to-diagram-securewebapp` | 16 → 15 | 24 → 20 | 0 / 12 / 3 / 8 | PASS |
| `sketch-to-diagram-resourcegroup01` | 9 | 13 → 11 | 0 / 8 / 1 / 3 | PASS |

## Findings and recommended fixes

### 1. HIGH — Policy check can report compliant when a deny policy blocks deployment

**Affected:** `.github/skills/azv-bicep-policy-check/SKILL.md`, step 5a (line 231).
**Evidence:** A temporary `Allowed locations` deny assignment in `AzVerify2` allowed only `northeurope`. A hypothetical `swedencentral` storage account was rejected by `az deployment group validate` with `RequestDisallowedByPolicy`. The documented `checkPolicyRestrictions` call returned `policyEvaluations=[]` and `fieldRestrictions=[]`; the same result occurred with explicit pending fields and with resource-group and subscription endpoints. The skill says empty evaluations mean compliant, which would produce a false pass.
**Suggested fix:** Treat empty policy API results as inconclusive when an applicable assignment is known. Investigate/validate the request and scope against the API contract, and fall back to another pre-deployment evaluation path rather than declaring compliance. The regression probe is `test/scripts/Test-PolicyRestrictions.ps1`.

### 2. MEDIUM — Diagram resource-group containers appear as Azure drift

**Affected:** `azv-diagram-drift-detection`; diagram parsing/filtering comparison path.
**Evidence:** The parser emits a `Microsoft.Resources/resourceGroups` resource for the diagram container, while `Get-AzureResourceModel.ps1` lists resources inside the group and did not add the group itself. Comparing the generated `AzVerify1` diagram to its live group reported one storage account in sync plus `AzVerify1` as `Diagram Only`. The shared diagram filter retained the container.
**Suggested fix:** Exclude resource-group container cells from the resource comparison, or explicitly add the known Azure resource group to the live model before comparing.

### 3. MEDIUM — Deep diagram mode has no expected values for ordinary diagrams

**Affected:** `.github/skills/azv-diagram-drift-detection/SKILL.md`, deep-mode behavior (lines 140–147), and `Compare-ResourceModels.ps1`.
**Evidence:** A normal parsed diagram contains resource identity/relationships, not tracked configuration properties. The storage account match therefore had 0 comparable properties. The skill promises expected values from the diagram or defaults in `azure-property-paths.json`, but the storage mapping contains tracked property paths without defaults, and the `-CompareProperties` path compares only properties present in model A. A synthetic expected value for `accessTier` correctly produced a drift, so the comparison works when the diagram model actually contains a value.
**Suggested fix:** Either provide and apply defined defaults for the deep-mode properties, add a supported configuration source to diagrams, or revise deep-mode claims and report insufficient expected configuration as incomplete rather than implying property-level coverage.

## Environment, changes, and cleanup

- Both approved resource groups existed in the active subscription and were in `swedencentral`; both were initially empty and had no policy assignments.
- Created/reused one functional-test storage account in `AzVerify1`: `azvtest9bd9cf0b` (`Standard_LRS`, `Hot`, TLS 1.2, HTTPS-only, blob public access disabled, public network access disabled). It contains no test data and is left in place for later runs; normal storage charges may apply.
- `AzVerify2` remains empty. The temporary policy assignment was deleted and the assignment count returned to zero.
- No production resource groups were accessed. No product skill was fixed or edited.
- Draw.io MCP, Azure best-practice/schema MCP, and Bicep MCP were not available in this session. The Bicep CLI and shared references were used where supported; generated diagram XML was parse-checked but not visually checked in Draw.io.
- Runtime: Azure CLI 2.91.0, Bicep CLI 0.48.1, PowerShell 7.5.2. The host lacked ICU for `az bicep`; commands were run with `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1`.

## Retained test artifacts

- `test/functional-testing.md` — repeatable seven-skill test procedure, moved out of skill discovery after the first run.
- `.github/agents/azv-functional-testing.agent.md` — manually invoked maintainer test agent that reads the procedure.
- `test/assets/test-storage.bicep` — low-cost fixture template.
- `test/scripts/Test-PolicyRestrictions.ps1` — temporary-policy regression probe with cleanup.
- `test/artifacts/2026-10-31/azverify1/` — parse-checked diagram, generated Bicep/parameters, original-request record, and validation README.
