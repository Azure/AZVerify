# Bicep Parsing Script Contract

Canonical contract for `.github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1`. Referenced by skills that analyze existing Bicep files.

---

## Script

- **Path**: `.github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1`
- **Purpose**: Parse Bicep templates and optional `.bicepparam` values into the shared Azure resource model.

## Invocation

```powershell
pwsh .github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1 -BicepFile <main.bicep> [-ParamFile <file.bicepparam>] [-Depth shallow|standard|deep] [-OutFile <path>]
```

## Parameters

- `-BicepFile` — required path to the entry Bicep file
- `-ParamFile` — optional path to the `.bicepparam` file
- `-Depth` — optional extraction depth; defaults to `standard`
- `-OutFile` — optional output path; otherwise JSON is written to stdout

## Output

- **stdout**: Single resource model JSON object conforming to `.github/skills/shared/azure-resource-model.md`
- **stderr**: Diagnostics only

## Exit Codes

- `0` — parse succeeded
- non-zero — parse failed; stop and report the error

## Notes

- The script prefers `az bicep build`/`bicep build` and exits non-zero when the CLI is unavailable.
- If `pwsh` or the script is unavailable, continue with the fallback procedure.

## Fallback

Use this fallback procedure when `pwsh` or the script is unavailable. If the script has already been invoked and failed, do not attempt the fallback.

- **Path**: `.github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1`
- **Purpose**: Parse Bicep templates and optional `.bicepparam` values into the shared Azure resource model.

## Invocation

```powershell
pwsh .github/skills/shared/scripts/ConvertFrom-BicepTemplate.ps1 -BicepFile <main.bicep> [-ParamFile <file.bicepparam>] [-Depth shallow|standard|deep] [-OutFile <path>]
```

## Parameters

| Depth | What's Extracted | Use Case |
|---|---|---|
| Shallow | Type, name, file location | Quick comparison / drift detection |
| Standard | Above + params, parent refs, conditions | Sync, what-if |
| Deep | Above + all property values resolved | Policy check, detailed what-if |
