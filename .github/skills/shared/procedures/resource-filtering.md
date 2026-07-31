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

- `-InputFile` — optional path to the input resource model JSON; if omitted, reads JSON from stdin
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
- If `pwsh` or the script is unavailable, continue with the fallback procedure.


## Fallback

Use this fallback procedure when `pwsh` or the script is unavailable. If the script has already been invoked and failed, do not attempt the fallback.

## Exclusion Table

- **Path**: `.github/skills/shared/scripts/Select-AzureResources.ps1`
- **Purpose**: Apply the shared exclusion rules from `.github/skills/shared/data/resource-filter-rules.json` to a resource model.

## Invocation

1. Check resource type against the table (case-insensitive)
2. Check if ALL tag keys start with `hidden-` (fully managed)
3. Apply any user-specified exclusion filters
4. Remove matching resources from the working list
