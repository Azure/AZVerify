---
name: azv-functional-testing
description: Run repeatable, bounded functional tests for all seven AzVerify Azure architecture skills using the approved AzVerify1 and AzVerify2 resource groups. Produces a dated test report and recommendations without changing product skills.
license: MIT
metadata:
  author: AzVerify
  version: "1.0"
  project: AzVerify
---

Run an end-to-end functional test pass for the AzVerify skills in this repository. This skill records failures and recommendations; it does **not** implement fixes to the skills under test.

## Scope and safety

Test these seven skills:

- `azv-azure-to-bicep`
- `azv-azure-to-diagram`
- `azv-bicep-drift-detection`
- `azv-bicep-policy-check`
- `azv-diagram-drift-detection`
- `azv-diagram-to-bicep`
- `azv-sketch-to-diagram`

Only use the user-designated test resource groups `AzVerify1` and `AzVerify2`. Verify the active subscription and both groups before making Azure changes. Stop if either group is absent, belongs to another subscription, or is not readable. Do not query or change other resource groups.

This test pass creates or reuses one tagged `Standard_LRS` storage account in `AzVerify1`. It does not write data to the account. The account is left in place for later runs; storage and transaction charges may still apply. A temporary deny-policy assignment is created only in `AzVerify2` by `scripts/Test-PolicyRestrictions.ps1`; that script removes it in `finally`. Never leave that assignment in place. Do not delete the storage account or any other Azure resource as part of the ordinary test run.

Use the test Bicep template in `assets/test-storage.bicep`; do not deploy the example architectures, which may contain costly services. No Azure resource deployment is part of the drift or policy checks. Never choose a resolution that changes production Azure or removes test data.

## Prerequisites and capability checks

1. Confirm the repository root, the seven skill files, `az`, PowerShell 7 (`pwsh`), and Azure CLI authentication. Use `.github/skills/shared/scripts/Test-AzureAuth.ps1`.
2. Record `az version`, PowerShell version, Bicep CLI version, active subscription name/ID (mask the ID in the committed report), and each test group's location and initial resource/policy-assignment counts.
3. Check whether Draw.io MCP and Bicep best-practice/schema MCP tools are available. Follow each target skill's own fallback contract:
   - If Azure-to-Diagram's Draw.io MCP is unavailable, its documented direct-file fallback may be used, but record that visual/MCP validation was not done.
   - Sketch-to-Diagram requires Draw.io MCP and has no direct-file fallback. Mark generation **BLOCKED** if that MCP is unavailable; parsing an existing example is not a successful generation test.
   - For Bicep MCP checks, use repository shared references and local Bicep CLI only where the target skill explicitly permits a fallback. Record the missing check.
4. If `az bicep` fails only because the host is missing ICU, retry with `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` for that process and record the workaround. Do not install system packages just for this test.

If a prerequisite is missing, continue independent tests that remain valid and mark only the affected skill/test **BLOCKED** or **PARTIAL**. Never turn an unavailable capability into a PASS.

## Test sequence

### 1. Run the shared fixture suite

From the repository root, run:

```powershell
pwsh .github/skills/shared/scripts/Invoke-Fixtures.ps1
```

Record the exit code and per-fixture checks. This suite smoke-tests Draw.io parsing, Bicep compilation and parameter compilation, resource filtering, and model comparison across `examples/`. It does not prove that the models are fully aligned; retain the comparison counts and do not describe the suite as an end-to-end generation test.

### 2. Verify and prepare the Azure fixture

For each approved group, run `az group show` and `az resource list`. Use only the active subscription explicitly. Derive a stable storage name as `azvtest` followed by the first eight lowercase hexadecimal characters of the subscription ID (15 characters total).

Before creating anything:

1. If the account exists in `AzVerify1`, verify its `azverifyFunctionalTest=true` tag and expected test configuration. Reuse it only if it is the test fixture; otherwise stop and report the collision.
2. If it does not exist, run `az storage account check-name`, then `az deployment group validate` using `assets/test-storage.bicep`.
3. Deploy the validated template once with `az deployment group create`. Record the resource ID in the report, but mask the subscription ID.
4. Verify the account through `az resource list` and `az storage account show`. Keep it at `accessTier=Hot`, TLS 1.2, HTTPS-only, blob public access disabled, and public network access disabled.

### 3. Test `azv-azure-to-bicep`

Run live inventory and enriched extraction:

```powershell
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 `
  -ResourceGroup AzVerify1 -Enrich -Mode bicep -StripReadOnly `
  -OutFile <temporary-output>/azure-model.json
```

Confirm the storage resource is present, its deployable configuration is in `deployableProperties`, and the Bicep-generation input does not copy secret values or serialize the raw ARM `properties` bag. Generate a small modular Bicep output from the extracted state in a new, non-colliding test output folder. Run `az bicep build` on the entry point and modules, compile the `.bicepparam`, and run `az deployment group validate` against `AzVerify1`; do not deploy the generated output. Record unavailable Azure best-practice/schema MCP checks and any permitted CLI/reference fallback.

### 4. Test `azv-azure-to-diagram`

Use `AzVerify1` as the resource-group input. Discover/enrich resources using the shared script, apply `Select-AzureResources.ps1 -Mode diagram`, then generate the diagram and `original-request.md` in a unique solution folder. Use the Draw.io MCP when available; otherwise use only the skill's documented direct-file fallback and note the missing visual validation.

Parse the resulting diagram with `ConvertFrom-DrawioDiagram.ps1`. Assert that the test storage account is represented exactly once with type `Microsoft.Storage/storageAccounts`, and that its resource-group containment is represented. Do not leave intermediate resource-model JSON behind.

### 5. Test `azv-diagram-to-bicep`

Use the diagram from Step 4. Generate `main.bicep`, non-empty modules, a matching `.bicepparam`, and README. Preserve current storage settings and secure defaults. Build the entry point, modules, and parameter file with Bicep CLI, then run `az deployment group validate` against `AzVerify1`. Do not deploy. If the Bicep MCP server is unavailable, use shared Bicep guidance and CLI validation only when permitted by the skill and mark the MCP validation as not run.

### 6. Test `azv-bicep-drift-detection`

Use the parameterized output from Step 3 or 5 and the explicit scope `AzVerify1` plus the current subscription ID.

1. Run the Azure-mode fast path and require status `COMPLETE`, one unchanged fixture resource, and zero create/modify/delete candidates.
2. Induce one reversible, low-impact change by changing only the test account's access tier from Hot to Cool.
3. Run the fast path again; require a complete report with exactly one `Modify` finding for `accessTier`.
4. In a `finally` block, restore Hot and verify it. Re-run the baseline comparison and record zero drift.

Never leave the account in Cool. Do not resolve drift by redeploying or deleting resources.

### 7. Test `azv-diagram-drift-detection`

Run both quick and deep modes with a diagram and `AzVerify1`. Parse the diagram, discover/enrich Azure with `-Mode diagram`, then compare with `Compare-ResourceModels.ps1` using the respective mode flags. Record all `Diagram Only`, `Azure Only`, matched, and property-comparison counts.

For a diagram with no explicit configuration values, verify that deep mode reports `No Comparable Properties` rather than claiming property-level in-sync. Also test a synthetic expected model with an explicit tracked property (for example `accessTier`) to ensure an actual value difference is surfaced. Do not silently fill missing expected values with guesses; verify any documented defaults against the actual shared data.

If the skill promises defaults but the shared mapping has no default values, record that as a functional failure and recommend either adding explicit defaults or narrowing the deep-mode claim.

### 8. Test `azv-bicep-policy-check`

Run the policy probe as one script invocation:

```powershell
pwsh .github/skills/azv-functional-testing/scripts/Test-PolicyRestrictions.ps1 `
  -SubscriptionId <subscription-id> -ResourceGroup AzVerify2
```

The script temporarily assigns the built-in **Allowed locations** deny policy to `AzVerify2`, checks a hypothetical storage account in the group's location with `checkPolicyRestrictions`, performs a non-deploying ARM validation, and removes only its own marked assignment in `finally`. It refuses to overwrite an unrelated assignment with the same name.

Interpret `RequestDisallowedByPolicy` from validation as confirmation that the temporary policy was active. Compare that with both `contentEvaluationResult.policyEvaluations` and `fieldRestrictions`. A zero policy-evaluation/restriction result despite the confirmed deny is a **FAIL** for the check; do not report the hypothetical resource as compliant. Verify the assignment count returns to its initial value even if the script exits non-zero. If cleanup fails, stop and remove only the marked temporary assignment before finishing.

### 9. Test `azv-sketch-to-diagram`

When Draw.io MCP is available, use `examples/sketch-to-diagram-resourcegroup01/resourcegroup01-originalSketch.jpeg` as the input fixture, complete the skill's resource-model, clarification/validation, and Microsoft Learn documentation checks, and generate a diagram. Parse the generated diagram and check its resources/relationships against the approved model.

When Draw.io MCP is unavailable, mark diagram generation **BLOCKED**. The pre-existing example diagram can be parsed as a parser smoke test, but it does not count as a successful sketch conversion. Do not fabricate a success by writing XML around the required integration.

### 10. Report and cleanup

Write `docs/functional-test-report-YYYY-MM-DD.md` with:

- Environment and the exact test resource group names.
- Every one of the seven skills, each test performed, result (`PASS`, `PARTIAL`, `FAIL`, or `BLOCKED`), and evidence.
- The fixture-suite result and individual resource/model counts.
- Findings ranked by severity with affected skill/step, observed behavior, reproduction, and suggested fix. Do not change the affected skill in this task.
- Missing integrations, fallbacks, and tests not exercised.
- Remaining test resources and confirmation that temporary policy assignments/intermediate JSON have been removed.

Delete only intermediate files created by this run. Keep the tagged storage account and useful final test outputs for the next run. Never delete unrelated files, existing Azure resources, or an account whose test tag/configuration cannot be verified.

## Result definitions

- **PASS**: the exact expected behavior was exercised and verified.
- **PARTIAL**: a substantial workflow or documented fallback was tested, but a required integration or branch was not.
- **FAIL**: the observed behavior contradicts the skill's documented behavior or produces an incorrect result.
- **BLOCKED**: an essential capability/input is unavailable and no documented fallback can complete the test.
