# Diagram Parsing Script Contract

Canonical contract for `.github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1`. Referenced by all skills that consume Draw.io diagrams.

---

## Script

- **Path**: `.github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1`
- **Purpose**: Parse a Draw.io XML file into the shared Azure resource model.

## Invocation

```powershell
pwsh .github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1 -DiagramPath <diagram-file> [-StencilMapping .github/skills/shared/azure-stencil-mapping.json] [-OutFile <path>]
```

## Parameters

- `-DiagramPath` — required path to the `.drawio` file
- `-StencilMapping` — optional path to the stencil mapping JSON
- `-OutFile` — optional output path; otherwise JSON is written to stdout

## Output

- **stdout**: Single resource model JSON object conforming to `.github/skills/shared/azure-resource-model.md`
- **stderr**: Diagnostics only

## Exit Codes

- `0` — parse succeeded
- non-zero — parse failed; stop and report the error

## Notes

- The script performs the reverse stencil lookup, container detection, containment mapping, and edge classification.
- If `pwsh` or the script is unavailable, continue with the fallback procedure.


## Fallback

Use this fallback procedure when `pwsh` or the script is unavailable. If the script has already been invoked and failed, do not attempt the fallback.

- **Path**: `.github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1`
- **Purpose**: Parse a Draw.io XML file into the shared Azure resource model.

## Invocation

```powershell
pwsh .github/skills/shared/scripts/ConvertFrom-DrawioDiagram.ps1 -DiagramPath <diagram-file> [-StencilMapping .github/skills/shared/azure-stencil-mapping.json] [-OutFile <path>]
```

## Parameters

- `-DiagramPath` — required path to the `.drawio` file
- `-StencilMapping` — optional path to the stencil mapping JSON
- `-OutFile` — optional output path; otherwise JSON is written to stdout

## Output

- **stdout**: Single resource model JSON object conforming to `.github/skills/shared/azure-resource-model.md`
- **stderr**: Diagnostics only

## Exit Codes

- `0` — parse succeeded
- non-zero — parse failed; stop and report the error

## Notes

The parsed model follows `.github/skills/shared/azure-resource-model.md`. Each resource has: `id`, `type`, `name`, `location` (container), `relationships`, and `tags`.

