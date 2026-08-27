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
- If `pwsh`/`powershell.exe` or the script is unavailable, use the inline fallback below.
- For diagram mutations or saves when Draw.io MCP is unavailable, use the XML editing fallback below instead of stopping the workflow.

## Script Unavailable — Inline Fallback

If `pwsh`/`powershell.exe` or the script cannot run, parse the diagram directly:

1. Read the `.drawio` file as XML and load `.github/skills/shared/azure-stencil-mapping.json`.
2. For each `<mxCell>` whose `style` contains an `image=...` value, reverse-look-up the image path in the stencil mapping to resolve the Azure resource `type`; use the cell `value` as the `name`.
3. Skip any cell whose `id` ends with `-icon`; these are decorative icon overlays, not distinct resources.
4. Treat container cells (VNet, subnet, resource group shapes) as parents; a cell whose `parent` is another resource cell gets a `contains` relationship from that parent.
5. Classify each `<mxCell edge="1">` element as a relationship between its `source` and `target` cells. Determine the relationship type from the cell's `style` attribute: `strokeColor=#0078D4` → `connects`; `strokeColor=#E81123` → `secures`; `strokeColor=#00A4EF` → `peers`; `strokeColor=#999999` with `dashed=1` → `depends`. Default to `connects` when no recognized style is present.
6. Emit a resource model JSON conforming to `.github/skills/shared/azure-resource-model.md`. Skip cells with no stencil match.

## Raw XML Editing — Diagram Save Fallback

If neither Draw.io MCP tool is available, edit the `.drawio` XML directly and write it back to disk:

1. Read the `.drawio` file as XML and preserve the existing `mxfile`/`mxGraphModel` structure.
2. Keep all existing cells, style, geometry, and metadata unless a resource is being added or removed.
3. For a new resource, append a new `<mxCell>` with `vertex="1"` and the correct parent container, plus an icon child when the resource type uses the dual container/icon pattern.
4. For a removed resource, delete the matching `<mxCell>` node and any `-icon` child cells, then remove any edges whose `source` or `target` references the deleted cell.
5. If the operation adds a resource to a container, expand or minimally adjust the parent cell's geometry to fit the new child without disturbing existing cells.
6. Write the XML back to the same file path and validate that the file remains well-formed XML before continuing.
7. If the save cannot be completed, stop with an explicit error stating that no changes were written to disk.

This fallback is the same safety pattern used elsewhere in the repo: prefer the documented tool path, then use the explicit inline XML fallback when the tool is unavailable.
