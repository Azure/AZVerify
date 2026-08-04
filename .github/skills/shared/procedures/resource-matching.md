# Resource Matching Script Contract

Canonical contract for `.github/skills/shared/scripts/Compare-ResourceModels.ps1`. Referenced by all sync and comparison skills.

---

## Script

- **Path**: `.github/skills/shared/scripts/Compare-ResourceModels.ps1`
- **Purpose**: Compare two resource model JSON files using the shared ordered matching rules.

## Invocation

```powershell
pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <model-a.json> -ModelB <model-b.json> -LabelA <label-a> -LabelB <label-b> [-OutFile <path>]
```

## Parameters

- `-ModelA` — required path to the first resource model JSON
- `-ModelB` — required path to the second resource model JSON
- `-LabelA` — optional label for model A (defaults to `ModelA`)
- `-LabelB` — optional label for model B (defaults to `ModelB`)
- `-OutFile` — optional output path; otherwise JSON is written to stdout

## Output

- **stdout**: Match report JSON with in-sync, name-different, and model-only classifications
- **stderr**: Diagnostics only

## Exit Codes

- `0` — comparison succeeded
- non-zero — comparison failed; stop and report the error

## Notes

- The script applies exact match, single-of-type match, substring/Levenshtein matching, child-resource context, and conditional-resource annotations.
- If `pwsh`/`powershell.exe` or the script is unavailable, continue with the fallback procedure.


## Fallback

Use this fallback procedure when `pwsh`/`powershell.exe` or the script is unavailable. If the script has already been invoked and failed, do not attempt the fallback.

## Matching Algorithm

Apply rules in order. Stop at the first match.

| # | Rule | Result |
|---|------|--------|
| 1 | Type AND name match (case-insensitive) | **In Sync** |
| 2 | Type matches AND only ONE resource of that type exists in EACH model | **In Sync (name differs)** — report both names |
| 3 | Type matches AND multiple exist → name has case-insensitive substring match or Levenshtein distance ≤ 3 | **In Sync (name differs)** |
| 4 | Exists in Model A only | **Model A Only** (e.g., "Diagram Only", "Bicep Only", "Azure Only") |
| 5 | Exists in Model B only | **Model B Only** |

## Child Resource Matching

- Match child resources within their parent context (e.g., subnet `default` within VNet `vnet-01`)
- Resource Groups, VNets, and Subnets are compared as regular resources

## Container Resource Handling

- A VNet container in a diagram matches a `Microsoft.Network/virtualNetworks` resource
- A Subnet container in a diagram matches a `Microsoft.Network/virtualNetworks/subnets` resource
- Resource Group containers scope the comparison but are not themselves reported as drift

## Conditional Resources

- Resources in Bicep with an `if` condition are matched normally but flagged as "conditional" in reports

## Status Indicators

| Status | Indicator |
|---|---|
| In Sync | ✅ |
| In Sync (name differs) | ✅ (with note) |
| Diagram Only / Bicep Only | ⬜ |
| Azure Only | 🔷 |