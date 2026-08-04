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

1. **Load the stencil mapping** from `.github/skills/shared/azure-stencil-mapping.json` and build a **reverse lookup**: map each `imagePath` back to its Azure resource type (e.g., `img/lib/azure2/compute/Virtual_Machine.svg` → `Microsoft.Compute/virtualMachines`).

2. **Identify resource cells**: For each `mxCell` in the diagram XML:
   - If the style contains `image=<path>` and the path matches the reverse lookup → this is an Azure resource
   - Extract: cell `id`, `value` (display name), `parent` (container relationship), matched resource type
   - **Skip icon cells**: Cells whose `id` ends in `-icon` are cosmetic container icons — do NOT add as resources

3. **Identify container cells**: Cells with `container=1` that are NOT icon cells represent groupings. Match via their icon child cell's image path or container style:

   | Style Pattern | Container Type |
   |---|---|
   | `fillColor=#fff2cc` | Resource Group |
   | `fillColor=#dae8fc` | VNet |
   | `fillColor=#e1d5e7` | Subnet |

4. **Build containment hierarchy** using the `parent` attribute:
   - `parent="1"` → top-level (diagram root)
   - `parent="<container-id>"` → inside that container
   - Map to `contains` relationships in the resource model

5. **Extract connections**: For each `mxCell` with `edge="1"`:
   - Extract `source` and `target` cell IDs
   - Determine relationship type from edge style:

   | Edge Style | Relationship |
   |---|---|
   | `strokeColor=#0078D4` | `connects` (data flow) |
   | `strokeColor=#E81123` | `secures` (security / private link) |
   | `strokeColor=#999999` + `dashed=1` | `depends` (dependency) |
   | `strokeColor=#00A4EF` + `dashed=1` | `peers` (network link) |

6. **Output the resource model** in chat so the user can verify parsing is correct.

---

## Output Schema

The parsed model follows `.github/skills/shared/azure-resource-model.md`. Each resource has: `id`, `type`, `name`, `location` (container), `relationships`, and `tags`.

