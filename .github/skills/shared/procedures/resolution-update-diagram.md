# Resolution Procedure: Update Diagram

Shared procedure for resolving drift by changing a Draw.io diagram to match a **source model** — either a parsed Bicep model or a discovered Azure model. Referenced by drift-detection skills after the user chooses an "Update Diagram" resolution.

Throughout this procedure, `<source>` is the label of the authoritative model (`Bicep` or `Azure`).

**Reference files:**

- `.github/skills/shared/azure-stencil-mapping.json` — resource type to Draw.io stencil mapping
- `.github/skills/shared/drawio-diagram-conventions.md` — diagram layout and edge conventions
- `.github/skills/shared/procedures/diagram-parsing.md` — includes the raw XML editing fallback for saves without Draw.io MCP

---

## 1. Confirm Changes

Present the full change set and wait for explicit confirmation:

```
## Confirm Diagram Changes

The following changes will be made to the diagram:

**Add to diagram** (<source>-only resources):
- redis-cache (Redis Cache)

**Remove from diagram** (Diagram-only resources):
- cosmos-db (Cosmos DB)

⚠️ Removing resources from the diagram is irreversible unless you have a backup.

Proceed? (yes/no)
```

Wait for explicit confirmation. If the user says no, return to the resolution options step. If the user says "no" but wants to exclude specific resources, switch to Selective resolution pre-filtered to the resources from this list.

**Skip this bulk confirmation when running in Selective mode** — per-resource choices were already collected.

## 2. Generate the Updated Diagram

If neither Draw.io MCP tool (`mcp_drawio_create_diagram` / `mcp_draw_io_create_diagram`) is available, use the raw XML editing fallback in `.github/skills/shared/procedures/diagram-parsing.md` to update the diagram file on disk.

1. Load the existing diagram XML
2. For **`<source>`-only resources** (add to diagram):
   - Look up each resource type in `.github/skills/shared/azure-stencil-mapping.json` for the correct icon and style
   - Add new `mxCell` elements with proper Azure icons
   - Placement priority: (1) if the source model gives the resource a parent (Bicep `parent:` reference, Azure containment relationship, or VNet/subnet membership), place it inside that parent's container cell; (2) otherwise place it in the top-level diagram page. If neither yields a valid target, place the resource in the top-level page and add a note in the result summary
   - For container resources (VNets, Subnets), create both the container cell and its icon child cell using the dual icon pattern
3. For **Diagram-only resources** (remove from diagram):
   - Remove the corresponding `mxCell` elements from the XML
   - Also remove any associated icon cells (cells with `id` ending in `-icon`)
   - Remove any edges connected to removed cells. If a removed cell has edges connecting two cells that both remain in the diagram, also remove those edges and add a note in the result summary: "Warning: edge between <A> and <B> was removed because it passed through the deleted resource <X>. Review connectivity in the diagram."
4. Expand the parent container's bounding box to fit any newly added child cells. Do not reposition existing cells unless they overlap a newly added cell; in that case, shift the new cell to the nearest open space within the container
5. Save the updated diagram via the Draw.io MCP tool. **If the save fails**, do not report the diagram as updated. Display: "Diagram save failed: <error message>. No changes were written to disk. Retry or save the XML manually to `<diagram-path>`." Then stop this procedure without presenting the success message.

## 3. Conditionally Regenerate Bicep

**Only when the source model is Azure** and `main.bicep` + `.bicepparam` files exist in the diagram's directory:

- Re-parse the updated diagram into a resource model
- Regenerate the Bicep files following **azv-diagram-to-bicep** conventions (reference `.github/skills/shared/azure-resource-configs.md` and `.github/skills/shared/bicep-best-practices.md`)
- Run pre-deployment verification from `.github/skills/shared/azure-deployment-verification.md`
- Preserve user-customized `.bicepparam` values where parameters still apply; add/remove parameters as needed
- Update module files and `main.bicep` outputs

If no Bicep files exist in the diagram's directory, or the source model is Bicep itself, skip this step.

## 4. Present Result

```
## Diagram Updated ✓

**Added:** 1 resource (redis-cache)
**Removed:** 1 resource (cosmos-db)

The diagram now matches the <source>.
Saved to `<diagram-path>`.
```

If Bicep was regenerated in step 3, add a table of changed Bicep files with their changes.

In Selective mode, batch all diagram changes: collect every per-resource choice first, then apply all XML changes in a single save and present a single summary table.
