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

### 1. Read Parameter Values

Read the `.bicepparam` file and extract all parameter values. These are needed to resolve name expressions in resource blocks.

### 2. Read Template Files

Read `main.bicep` and parse all `module` declarations to find referenced Bicep files. Module paths are relative to the file containing the `module` statement — they may reference files outside `modules/` (e.g., `'../shared/networking.bicep'` or `'br:myregistry.azurecr.io/bicep/networking:v1'`). Read each resolved module file recursively to discover nested module references.

### 3. Extract Resources

For each `resource` block found:

| Field | How to Extract |
|---|---|
| `type` | Resource type string, sans API version (e.g., `Microsoft.Compute/virtualMachines`) |
| `apiVersion` | API version from the resource declaration |
| `symbolicName` | The Bicep symbolic name (left side of `=`) |
| `name` | The `name` property value — resolve parameter references using `.bicepparam` values |
| `sourceFile` | Relative path of the file containing this resource |
| `conditional` | `true` if the resource has an `if` condition, `false` otherwise |
| `parent` | Symbolic name of the `parent:` reference (if any) |

### 4. Resolve Hierarchy

- Match `parent:` references to their target resource blocks
- Build parent-child relationships (e.g., subnet → VNet)

### 5. Output Model

Output the parsed Bicep resource model in chat for user verification. Schema per resource:

```json
{
  "symbolicName": "<name>",
  "type": "Microsoft.Provider/resourceType",
  "name": "<resolved-name>",
  "sourceFile": "modules/networking.bicep",
  "conditional": false,
  "parent": null
}
```

## Depth Levels
