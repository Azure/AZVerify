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
- `-LabelA` — required label for model A (for example `Diagram`)
- `-LabelB` — required label for model B (for example `Azure` or `Bicep`)
- `-OutFile` — optional output path; otherwise JSON is written to stdout

## Output

- **stdout**: Match report JSON with in-sync, name-different, and model-only classifications
- **stderr**: Diagnostics only

## Exit Codes

- `0` — comparison succeeded
- non-zero — comparison failed; stop and report the error

## Notes

- The script applies exact match, single-of-type match, substring/Levenshtein matching, child-resource context, and conditional-resource annotations.
- If `pwsh` or the script is unavailable, report the prerequisite and stop.
