---
name: azv-bicep-policy-check
description: Check a Bicep template against the Azure Policy assignments in the target Azure environment to determine whether the resources would be compliant before deployment. Uses the checkPolicyRestrictions REST API for fast server-side evaluation, with a legacy CLI fallback. Produces a per-resource compliance report with remediation guidance.
license: MIT
metadata:
  author: AzVerify
  version: "1.0"
  project: AzVerify
---

Check Bicep templates against the Azure Policy assignments active in the target environment. Reports whether each resource would be compliant, non-compliant, or requires manual evaluation — before any deployment occurs.

**Input**: A solution folder containing Bicep templates (`main.bicep`) and a `.bicepparam` file, plus an Azure target scope (resource group name, subscription ID). The user can specify these, or the skill will auto-discover and prompt for missing inputs.

**Tools required**: File system tools (read files), Terminal (for running `az` CLI commands)

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-resource-configs.md` — Per-resource-type configuration schemas and auto-detection rules
- `.github/skills/shared/data/azure-property-paths.json` — Azure Property Retrieval Mapping (MCP tools, CLI fallbacks, ARM JSON paths)

**Shared procedures** (MUST follow):
- `.github/skills/shared/procedures/azure-authentication.md` — Azure session check procedure
- `.github/skills/shared/procedures/bicep-parsing.md` — Bicep template parsing procedure

---

## Steps

### 1. Check Azure Authentication

Follow the procedure in `.github/skills/shared/procedures/azure-authentication.md`. **HARD GATE** — stop if not authenticated.

### 2. Accept Inputs

Identify the solution folder, the Bicep template, the parameter file, and the target scope.

#### 2a. Identify the Solution Folder

**If the user specifies a folder path:**
- Verify the folder exists
- Use it as the solution folder

**If no folder is specified:**
- Search the workspace for folders containing a `main.bicep` file
- If exactly one is found, use it (announce which folder)
- If multiple are found, present the list and ask the user to select one
- If none are found, ask the user to provide a solution folder

#### 2b. Identify the Bicep Template

- Verify `main.bicep` exists in the solution folder
- If not found, report an error:
```
## No Bicep Template Found

No `main.bicep` file found in `<folder-path>`.
This skill requires a Bicep template to check policy compliance.
```
- Stop execution

#### 2c. Identify the Parameter File

**If exactly one `.bicepparam` file exists in the solution folder:**
- Use it as the parameter file (announce which file)

**If multiple `.bicepparam` files exist:**
- Present the list and ask the user to select one

**If no `.bicepparam` file exists:**
- Warn the user:
```
⚠️ No `.bicepparam` file found in `<folder-path>`. Default parameter values will be used when evaluating policy compliance.
```
- Proceed without a parameter file

#### 2d. Identify the Target Scope

**If the user specifies a resource group name:**
- Use it as the target scope
- Verify the resource group exists: run `az group show --name <name>` and capture the subscription ID from the result

**If the user specifies a subscription ID:**
- Use it as the target scope for subscription-level policy retrieval

**If no scope is specified, try to infer it:**
1. From the `.bicepparam` file: look for comments or `using` declarations indicating a target resource group
2. If a resource group name is found, propose it:
```
The `.bicepparam` file references resource group `<name>`. Use this as the target scope? (yes/no)
```
3. If no scope can be inferred, ask the user:
```
Which Azure resource group are you targeting for this deployment?
```
- Wait for user input

### 3. Parse Templates into Expected Resource Model

Read the Bicep template and parameter file to build an **expected resource model** — what the templates declare should exist.

#### 3a. Read and parse the `.bicepparam` file

Read the `.bicepparam` file and extract all parameter values. For each `param <name> = <value>` line, record the name and resolved value.

#### 3b. Read and parse `main.bicep` and all module files

Read `main.bicep` and every Bicep module it references in `modules/`. For each `resource` block, extract:

- **Resource type** (e.g., `Microsoft.Web/sites`)
- **API version**
- **Symbolic name** (Bicep variable name)
- **`name` property** — resolve parameter references using the values from Step 3a where possible
- **All other properties** — collect the full set of declared properties for policy evaluation (location, SKU, kind, properties.* fields)

Store this as the **expected resource model**: a list of resources, each with their type, name, and full declared properties.

If a property value references a parameter that cannot be resolved (e.g., it depends on deployment-time input), record it as `<unresolved: paramName>`.

#### 3c. Build resource group resource entry

Many policies (e.g., required tags) target the **resource group itself** (`Microsoft.Resources/subscriptions/resourceGroups`), not the resources inside it. The skill must check the resource group as a separate resource.

**If the resource group already exists:**
- Run `az group show --name <rgName> -o json` to get its current tags and location
- Build a resource entry using the existing RG properties

**If the resource group does not exist yet (new deployment):**
- Build a resource entry using:
  - `name` — the target resource group name
  - `location` — the `location` parameter from the `.bicepparam` file
  - `tags` — look for a `resourceGroupTags` or similar parameter in the `.bicepparam` file. If none exists, use `{}`

Add this as the **first entry** in the expected resource model:

```
Resource: <rgName>
Type: Microsoft.Resources/subscriptions/resourceGroups
API version: 2024-03-01
Properties: { location, tags }
```

> This adds only **one extra API call** (~1–3 seconds) to the check, keeping total execution fast.

### 4. Evaluate Policy Compliance via checkPolicyRestrictions API

Use the Azure `checkPolicyRestrictions` REST API to evaluate each resource against **all** active policies in a single call per resource. This replaces sequential CLI fetches of initiatives and definitions.

> **Performance goal**: 1 REST call per resource (typically 2–5 calls total). No initiative expansion, no definition fetching, no local rule evaluation needed — Azure does all policy evaluation server-side.

#### 4a. Build resource content payloads

For each resource in the expected resource model (Step 3), **including the resource group from Step 3c**, build a `resourceContent` JSON object matching what would be deployed. Include:

**For the resource group entry (from Step 3c):**
- `type` — `Microsoft.Resources/subscriptions/resourceGroups`
- `location` — resolved from parameters
- `name` — the target resource group name
- `tags` — resolved from parameters, or `{}` if none specified

> The resource group check uses **subscription-level scope** (even if the RG exists), since RG creation happens at subscription level. Use: `/subscriptions/$subscriptionId/providers/Microsoft.PolicyInsights/checkPolicyRestrictions?api-version=2022-03-01`

**For all other resources:**
- `type` — the full resource type (e.g., `Microsoft.DevCenter/devcenters`)
- `location` — resolved from parameters
- `name` — resolved from parameters
- `tags` — resolved from parameters (use `{}` if empty/unresolved)
- `sku` — if applicable
- `kind` — if applicable
- `properties` — the full properties bag, resolved from parameters where possible

For properties that reference unresolved parameters, use a reasonable placeholder value and flag the resource for manual review on those properties.

#### 4b. Run ALL resources in a single terminal invocation

> **CRITICAL**: All resource checks MUST be executed in a **single terminal command**. Do NOT run separate terminal commands per resource.

Build a single PowerShell script that:
1. Defines all resource payloads as an array (resource group FIRST, with `isRG = $true`)
2. Determines scope URLs: subscription-level for the RG itself, RG-level for child resources (subscription-level fallback if RG doesn't exist)
3. Loops through each resource, calling `az rest --method POST` against the `checkPolicyRestrictions` endpoint
4. Outputs all results as JSON

API endpoint pattern: `/subscriptions/$subscriptionId[/resourceGroups/$rgName]/providers/Microsoft.PolicyInsights/checkPolicyRestrictions?api-version=2022-03-01`

Each resource payload: `@{ resourceDetails = @{ resourceContent = <content>; apiVersion = <version> } }`

> **Performance**: Completes in **one terminal invocation** taking ~5–15 seconds total (1–3 seconds per API call).

#### 4c. Handle API errors gracefully

- **403 Forbidden**: The user may lack `Microsoft.PolicyInsights/checkPolicyRestrictions/read` permission. Fall back to the **legacy approach** (Step 4-fallback below).
- **404 Not Found**: The resource group doesn't exist yet. Retry with subscription-level scope.
- **Other errors**: Report the error and fall back to the legacy approach.

#### 4d. Parse API response

The `checkPolicyRestrictions` response contains two key sections:
- **`fieldRestrictions[]`** — per-field value restrictions with `field`, `restrictions[].result`, `restrictions[].values`, policy IDs, and `policyEffect`
- **`contentEvaluationResult.policyEvaluations[]`** — full evaluation results with `evaluationResult` ("NonCompliant"/"Compliant"), `effectDetails.effect`, and policy display names

---

### 4-fallback. Legacy Approach (if checkPolicyRestrictions is unavailable)

If the `checkPolicyRestrictions` API is not available (403, unsupported region, or older API version), fall back to this approach:

1. Fetch all assignments in one call: `az policy assignment list --scope "/subscriptions/$subscriptionId" -o json`
2. For each initiative, expand definitions and keyword-filter by resource type
3. Fetch individual definitions only for the matched subset
4. Evaluate policy rules locally against resource properties

This fallback is slower (2–5+ minutes for environments with many assignments) but does not require the `Microsoft.PolicyInsights` RP.

---

### 5. Determine Compliance Status per Resource

Map the `checkPolicyRestrictions` API response to compliance status for each resource.

#### 5a. Classify from contentEvaluationResult

For each entry in `contentEvaluationResult.policyEvaluations`:

- **`evaluationResult: "NonCompliant"` + `effect: "deny"`** → Resource would be **Non-Compliant** (deployment blocked)
- **`evaluationResult: "NonCompliant"` + `effect: "audit"`** → Resource would be **Non-Compliant** (deployment allowed but flagged)
- **`evaluationResult: "NonCompliant"` + `effect: "auditIfNotExists"`** → **Needs manual review** (depends on related resource existence in Azure)
- **`evaluationResult: "NonCompliant"` + `effect: "modify"`** → **Modify policy active** — Azure will auto-remediate post-deployment, but the value CAN be set proactively in the Bicep template. Report what the modify policy will change.
- **`evaluationResult: "NonCompliant"` + `effect: "deployIfNotExists"`** → **Auto-remediated** after deployment (separate resource created by policy; cannot be pre-set in Bicep)

If `policyEvaluations` is empty or all results are compliant, the resource is **Compliant**.

#### 5b. Classify from fieldRestrictions

For each entry in `fieldRestrictions`:
- If the resource's declared value for the restricted field is in the allowed `values` list → **Compliant** for this restriction
- If the resource's declared value is NOT in the allowed list and the effect is `deny` → **Non-Compliant** (deployment blocked)
- If the resource's declared value is NOT in the allowed list and the effect is `audit` → **Non-Compliant** (flagged)
- If the field value is unresolved (`<unresolved: paramName>`) → **Needs manual review**

#### 5c. Aggregate per resource

Combine `contentEvaluationResult` and `fieldRestrictions` classifications. The worst status wins:
1. **Non-Compliant (deny)** — highest severity
2. **Non-Compliant (audit)**
3. **Needs manual review**
4. **Modify policy active** — auto-remediated but can be proactively fixed in Bicep
5. **Auto-remediated (deployIfNotExists)** — separate resource created by policy; informational only
6. **Compliant** — lowest severity

---

### 6. Build Compliance Report

Aggregate the per-resource, per-policy evaluations into a summary compliance report.

#### 6a. Overall summary

Present a top-level summary table:

```
## Policy Compliance Check — <folder-name>

| # | Resource | Type | Status |
|---|----------|------|--------|
| 1 | <rgName> | Resource Group | ❌ Non-Compliant (deny) |
| 2 | <name> | <type> | ✅ Compliant |
| 3 | <name> | <type> | ⚠️ Non-Compliant (audit) |
| 4 | <name> | <type> | 🔧 Modify policy active |
| 5 | <name> | <type> | 🔄 Auto-remediated (DINE) |
| 6 | <name> | <type> | ❓ Needs manual review |

**Scope**: <resourceGroupName> (Subscription: <subscriptionName>)
**Policies evaluated**: <count> policy assignments (<count> definitions)
**Result**: <X> compliant, <Y> non-compliant (deny), <Z> non-compliant (audit), <M> modify policies active, <W> need review
```

> **Note**: The resource group itself is always checked as the first resource. Policies that target `Microsoft.Resources/subscriptions/resourceGroups` (e.g., required tags on resource groups) are evaluated here. This catches tag requirements, naming conventions, and other RG-level policies that would otherwise be missed.

#### 6b. Non-compliant resource details

For each non-compliant resource, show: Policy name, Assignment, Effect, Reason, Expected vs Actual values, and Remediation guidance.

#### 6c. Needs-manual-review resource details

Show: Policy name, Reason (unresolvable property or condition involving related resources), and recommend `az policy state list --resource <resourceId>` after deployment.

#### 6d. Modify policy details (actionable)

Show: Policy name, Assignment, Effect (modify), what it does, fields modified (table: Field, Policy action, Value source), current Bicep value, and proactive fix suggestion (set tags/properties in `.bicepparam` file).

#### 6e. Auto-remediated resource notes (deployIfNotExists)

Show: Policy name, Effect (deployIfNotExists), note that no Bicep changes are required — the remediation creates a separate resource post-deployment.

---

### 7. Offer Next Steps

Offer the user:
- **`fix`** — Update Bicep templates to resolve non-compliant settings AND proactively set modify-policy values
- **`save report`** — Save compliance report as `policy-compliance-report.md` in the solution folder
- **Deploy anyway** / **Re-check** / **Preview with azv-bicep-whatif**

#### 7a. Fix non-compliant and modify-policy Bicep templates (if requested)

**For deny/audit non-compliant resources** with deterministic fixes:
- Locate the property in the Bicep module, update the value, report the change

**For modify policies (proactive fix)**:
- For tag policies: add required tag keys to `.bicepparam` with placeholder values
- For other properties: set to the value the policy would apply, if deterministic
- For runtime-dependent values: add placeholder with comment explaining expected source

**For resource group-level policies** (e.g., RequireTag deny):
- Report that RG creation must include required tags
- If `targetScope = 'subscription'`, add tags to the RG resource in Bicep

- For non-compliant resources where the required change is not deterministic (e.g., involves unresolved parameters or complex conditions):
  - Report that the change must be made manually and provide guidance
- After all updates, present the list of changes made and suggest running **azv-bicep-policy-check** again to confirm

#### 7b. Save report (if requested)

If the user replies `save report` (or equivalent):

- Write the full compliance report as `policy-compliance-report.md` in the solution folder
- Confirm:
  ```
  Saved compliance report to `<folder>/policy-compliance-report.md`.
  ```

---

### 8. Important Notes

- Uses `checkPolicyRestrictions` REST API (2022-03-01) for server-side evaluation (5–15 seconds for 3–5 resources). Falls back to legacy assignment-expansion approach (2–5+ min) if API returns 403.
- Requires `Microsoft.PolicyInsights/checkPolicyRestrictions/read` permission. Most Reader/Contributor roles include this.
- Policies requiring live Azure state (e.g., `auditIfNotExists`) are marked `Needs manual review`. Same for unresolvable deployment-time parameters.
- The resource group is always checked as a separate resource to catch RG-level policies (e.g., required tags). New RGs use subscription-level scope.
- Effect precedence: `deny` (blocks deployment) > `audit` (flags) > `modify` (auto-remediates, actionable in Bicep) > `deployIfNotExists` (informational).
- The API automatically evaluates inherited policies (management group → subscription → resource group) and handles API version matching.
- This skill operates independently — does not require a diagram or prior `azv-diagram-to-bicep` run.
