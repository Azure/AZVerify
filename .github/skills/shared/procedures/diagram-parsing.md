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
- If `pwsh` or the script is unavailable, use the inline fallback below.

## Script Unavailable — Inline Fallback

If `pwsh` or the script cannot run, parse the diagram directly:

1. Read the `.drawio` file as XML and load `.github/skills/shared/azure-stencil-mapping.json`.
2. For each `<mxCell>` whose `style` contains an `image=...` value, reverse-look-up the image path in the stencil mapping to resolve the Azure resource `type`; use the cell `value` as the `name`.
3. Treat container cells (VNet, subnet, resource group shapes) as parents; a cell whose `parent` is another resource cell gets a `contains` relationship from that parent.
4. Classify `<mxCell edge="1">` elements as `connects` relationships between their `source` and `target` cells.
5. Emit a resource model JSON conforming to `.github/skills/shared/azure-resource-model.md`. Skip cells with no stencil match.
