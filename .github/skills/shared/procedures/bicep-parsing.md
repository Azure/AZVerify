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

- The script requires `az bicep build` or standalone `bicep build`. If neither is available, the script exits with a non-zero code; the calling skill should then follow the inline fallback below.
- If `pwsh` or the script is unavailable, use the inline fallback below.

## Script Unavailable — Inline Fallback

If `pwsh`/`powershell.exe` is not available or the script cannot run, parse the Bicep directly:

1. Read `main.bicep` and every referenced `modules/*.bicep` file.
2. For each `resource <symbol> '<type>@<apiVersion>' = {` declaration, capture the symbolic name, `type`, `apiVersion`, the `name` value, and top-level properties.
3. If a `.bicepparam` file is provided, substitute its `param` values (and any `param ... = <default>` defaults) before resolving property values. Record values that depend on runtime expressions as `<unresolved: paramName>`.
4. Map child resources declared with `parent:` to a `contains` relationship on the parent.
5. Emit a resource model JSON conforming to `.github/skills/shared/azure-resource-model.md`.
