# Azure skill functional tests

Maintainer-only integration tests for the seven AzVerify skills. This is an opt-in test harness, not a product skill or normal user workflow.

**Run cadence:** Run this suite before a pull request is merged, not after every change or commit. Full runs take time and consume GitHub Copilot credits, in addition to requiring the dedicated Azure environment. Do not automatically run the suite on every edit or push.

The goal is broad **method coverage** with realistic complexity:

- low-cost baseline fixture (`test/assets/test-storage.bicep`)
- multi-resource cross-RG fixture (`test/assets/complex/`)
- complex offline diagram oracle (`test/assets/complex/scenario.json`)
- both Draw.io MCP path and raw-file fallback path where the skill documents both
- both script path and offline input path (`-FromJson`) where shared scripts support both

Read the [required environment](../README.md#maintainer-tests) before running. Use the [functional-testing agent](../.github/agents/azv-functional-testing.agent.md) only after explicit user authorization.

## Scope and safety

Test only these skills:

- `azv-azure-to-bicep`
- `azv-azure-to-diagram`
- `azv-bicep-drift-detection`
- `azv-bicep-policy-check`
- `azv-diagram-drift-detection`
- `azv-diagram-to-bicep`
- `azv-sketch-to-diagram`

Hard limits:

1. Use only resource groups `AzVerify1` and `AzVerify2`.
2. Never mutate other groups, subscriptions, or org policy.
3. Keep only tagged test fixtures; remove only temporary policy assignments and intermediate files.
4. Do not deploy `examples/` stacks.
5. Report defects and suggested fixes; do not modify product skills while testing.

## Test assets and scripts

### Baseline fixture

- `test/assets/test-storage.bicep`
- one stable storage account per subscription suffix in `AzVerify1`

### Complex fixture

- `test/assets/complex/main.bicep`
- `test/assets/complex/modules/*.bicep`
- `test/assets/complex/azverify1.bicepparam`
- `test/assets/complex/azverify2.bicepparam`
- `test/assets/complex/peering.bicep`
- `test/scripts/Deploy-ComplexFixtures.ps1`

This fixture creates VNets/subnets/NSG/route table/NICs, storage, managed identity, Key Vault in both groups; monitoring resources in `AzVerify1`; and bidirectional peering.

### Complex diagram oracle

- `test/assets/complex/scenario.json`
- `test/scripts/New-ScenarioDiagram.ps1`

This generates a deterministic complex `.drawio` file for parser and drift tests without depending on Draw.io MCP availability.

### Policy regression probe

- `test/scripts/Test-PolicyRestrictions.ps1`

Creates a temporary deny assignment in `AzVerify2`, runs policy checks, and removes only the tagged assignment in `finally`.

## Prerequisites and capability checks

1. Validate auth with `.github/skills/shared/scripts/Test-AzureAuth.ps1`.
2. Record Azure CLI, PowerShell, Bicep CLI versions and active subscription.
3. Verify both test groups exist and are readable.
4. Probe integrations:
   - Draw.io MCP available/unavailable
   - Azure best-practice/schema MCP available/unavailable
   - Bicep MCP available/unavailable
5. If `az bicep` needs ICU workaround, use `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` and record it.

If a required capability is unavailable, continue independent branches and mark affected branches as `PARTIAL` or `BLOCKED`, never `PASS`.

## Method coverage matrix (required)

| Skill | Required methods to exercise |
|---|---|
| `azv-azure-to-bicep` | RG scope discovery, optional subscription-scope filtered discovery, enriched extraction (`-Enrich`), read-only stripping (`-StripReadOnly`), offline replay (`-FromJson`), modular output validation |
| `azv-azure-to-diagram` | RG scope, optional subscription scope, >10 resource summary behavior, relationship inference on complex fixture, Draw.io MCP path when available, raw-file fallback path always |
| `azv-bicep-drift-detection` | Azure fast path script, baseline comparison, reversible drift injection and restore, complex fixture comparison with external-resource classification |
| `azv-bicep-policy-check` | `checkPolicyRestrictions` API path, ARM validate cross-check, temporary deny policy cleanup guarantee |
| `azv-diagram-drift-detection` | quick and deep modes, no-comparable-properties edge case, explicit-property drift case, container handling, complex diagram against live scope |
| `azv-diagram-to-bicep` | parser path from complex diagram, module generation, `.bicepparam` generation, CLI build/build-params, ARM validate (no deploy), fallback behavior when Bicep MCP missing |
| `azv-sketch-to-diagram` | MCP path only when Draw.io MCP is available; otherwise explicit `BLOCKED` with parser-only smoke tests |

## Execution sequence

### 1. Shared fixture smoke suite

```powershell
pwsh .github/skills/shared/scripts/Invoke-Fixtures.ps1
```

Record all check results and counts.

### 2. Prepare baseline and complex Azure fixtures

Baseline storage fixture:

- validate/reuse existing tagged account in `AzVerify1`
- create only if absent

Complex fixture:

```powershell
$subscriptionId = '<subscription-id>'
$env:AZVERIFY_NAME_SUFFIX = $subscriptionId.Replace('-', '').Substring(0, 8).ToLowerInvariant()
pwsh test/scripts/Deploy-ComplexFixtures.ps1 -SubscriptionId $subscriptionId
```

The two `.bicepparam` files read `AZVERIFY_NAME_SUFFIX`, so keep this environment variable set for parameter parsing and drift detection in the same shell session.

Record resource counts/types per group and peering status.

### 3. Build a complex diagram oracle

```powershell
pwsh test/scripts/New-ScenarioDiagram.ps1 `
  -ScenarioPath test/assets/complex/scenario.json `
  -OutFile test/artifacts/<run-id>/complex-scenario.drawio
```

Then parse it:

```powershell
pwsh .github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1 `
  -DiagramPath test/artifacts/<run-id>/complex-scenario.drawio `
  -OutFile test/artifacts/<run-id>/diagram-model.json
```

### 4. Exercise discovery and filtering methods

Run `Get-AzureResourceModel.ps1` across these variants and persist every output:

- RG1 diagram mode
- RG1 bicep mode
- RG2 bicep mode
- each of the above with `-Enrich`
- offline replay with `-FromJson` of tagged resources (with and without `-Enrich`)
- `Select-AzureResources.ps1` with `-ExtraExclude` to verify custom exclusion path

Capture non-zero exits as findings with full stderr.

### 5. Exercise Bicep parsing and generation methods

Run `ConvertFrom-BicepTemplate.ps1` for both parameter sets:

- `test/assets/complex/azverify1.bicepparam`
- `test/assets/complex/azverify2.bicepparam` (monitoring condition false path)

Validate:

- `az bicep build` for complex templates
- `az bicep build-params` for both param files

### 6. Exercise drift detection methods

Run `Invoke-BicepDriftDetection.ps1` for both groups and collect:

- drift report markdown
- drift summary JSON
- stderr diagnostics

Also run direct `Compare-ResourceModels.ps1` quick and deep against at least one complex diagram/live-model pair.

### 7. Exercise policy-check method

```powershell
pwsh test/scripts/Test-PolicyRestrictions.ps1 `
  -SubscriptionId <subscription-id> -ResourceGroup AzVerify2
```

Verify:

- assignment created only with test marker
- assignment removed in `finally`
- API and ARM validation interpretation

### 8. Draw.io MCP branch and fallback branch

Run both branches explicitly in the report:

- **MCP branch**: use when Draw.io MCP is actually available in the running session.
- **Fallback branch**: generate/edit `.drawio` files directly using scripted or XML fallback.

If MCP is unavailable in the current runtime, mark MCP-dependent tests as `PARTIAL`/`BLOCKED` and still execute fallback branch.

### 9. Report

Write `test/reports/functional-test-report-YYYY-MM-DD[-suffix].md` including:

1. environment and integration availability
2. full skill status matrix (`PASS`/`PARTIAL`/`FAIL`/`BLOCKED`)
3. method-level coverage table (each method row includes pass/fail and evidence path)
4. findings ranked by severity with reproduction and suggested fixes
5. retained Azure resources and cleanup verification

## Result definitions

- **PASS**: expected behavior verified for all required methods reachable in this runtime
- **PARTIAL**: major workflow validated, but one or more required methods were unavailable
- **FAIL**: behavior contradicts skill or shared contract
- **BLOCKED**: required capability unavailable and no documented fallback can complete that branch
