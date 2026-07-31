# Resource Filtering Script Contract

Canonical contract for `.github/skills/shared/scripts/Select-AzureResources.ps1`. Referenced by skills that filter discovered or parsed resource models.

---

## Script

- **Path**: `.github/skills/shared/scripts/Select-AzureResources.ps1`
- **Purpose**: Apply the shared exclusion rules from `.github/skills/shared/data/resource-filter-rules.json` to a resource model.

## Invocation

```powershell
pwsh .github/skills/shared/scripts/Select-AzureResources.ps1 -InputFile <resource-model.json> -Mode diagram|bicep [-ExtraExclude <pattern[]>] [-OutFile <path>]
```

## Parameters

- `-InputFile` — required path to the input resource model JSON
- `-Mode` — required filter mode: `diagram` or `bicep`
- `-ExtraExclude` — optional additional resource names or type patterns to exclude
- `-OutFile` — optional output path; otherwise JSON is written to stdout

## Output

- **stdout**: Filtered resource model JSON object
- **stderr**: Diagnostics only

## Exit Codes

- `0` — filtering succeeded
- non-zero — filtering failed; stop and report the error

## Notes

- The script applies type rules, `hidden-*` tag rules, and any extra exclusions.
- If `pwsh` or the script is unavailable, report the prerequisite and stop.
