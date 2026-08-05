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

- `-InputFile` — optional path to the input resource model JSON; if omitted, the script reads JSON from stdin
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
- If `pwsh`/`powershell.exe` or the script is unavailable, use the inline fallback below.

## Script Unavailable — Inline Fallback

If `pwsh`/`powershell.exe` or the script cannot run, filter the resource model directly:

1. Read `.github/skills/shared/data/resource-filter-rules.json`.
2. For each resource in the input model, exclude it when its `type` matches a rule (exact or wildcard `*`) whose `excludeForDiagram` (mode `diagram`) or `excludeForBicep` (mode `bicep`) is `true`. For a rule value of `"check individually"`, keep the resource but note it for review.
3. Exclude any resource whose tag keys **all** start with `hidden-`.
4. Exclude any resource matching a caller-supplied `-ExtraExclude` name or type prefix.
5. Return the surviving resources as the filtered model (same shape as the input).
