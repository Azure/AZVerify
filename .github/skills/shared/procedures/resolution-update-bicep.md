# Resolution Procedure: Update Bicep

Shared procedure for resolving drift by changing Bicep templates to match a **source model** — either a parsed diagram model or a discovered Azure model. Referenced by drift-detection skills after the user chooses an "Update Bicep" resolution. Observed resource names/IDs are not authorization to edit files or adopt configuration.

Throughout this procedure, `<source>` is the label of the authoritative model (`Diagram` or `Azure`).

**Reference files (MUST read before generating Bicep):**

- `.github/skills/shared/azure-deployment-verification.md` — pre-deployment verification rules
- `.github/skills/shared/bicep-best-practices.md` — Bicep authoring rules
- `.github/skills/shared/azure-resource-configs.md` — per-resource-type configuration defaults

---

## 1. Confirm Changes

Present the full change set, ownership/source-of-truth context, and affected dependencies; obtain explicit approval before editing. For Azure updates, decide per resource and per property. A match or resource name is not consent to adopt/remove it. Check whether another pipeline owns it, and account for dependent resources such as private endpoint NICs. Wait for explicit confirmation:

```
## Confirm Bicep Changes

The following changes will be made to the Bicep templates:

**Add to Bicep** (<source>-only resources):
- cosmos-db (Microsoft.DocumentDB/databaseAccounts)

**Remove from Bicep** (Bicep-only resources):
- redis-cache (Microsoft.Cache/redis) — in modules/data.bicep

⚠️ Removing resources from Bicep templates means they will no longer be part of deployments.

Proceed? (yes/no)
```

Wait for explicit confirmation. If the user says no, return to the resolution options step. If the user says "no" but wants to exclude specific resources, switch to Selective resolution pre-filtered to the resources from this list.

**Skip this bulk confirmation when running in Selective mode** — per-resource choices were already collected.

## 2. Run Deployment Verification

Before generating any Bicep, read and run the verification rules from `.github/skills/shared/azure-deployment-verification.md`:

1. **SKU dependency rules** — verify companion resources exist
2. **Resource compatibility rules** — verify backend protocols, DNS zones
3. **Networking rules** — verify subnet sizing, no overlaps
4. **Security rules** — verify TLS 1.2+, HTTPS, `@secure()` decorators
5. **Version currency rules** — verify runtime stacks and API versions are current

Errors must be resolved (auto-fix where possible) before writing files. Do not generate code with known errors.

## 3. Apply Bicep Changes

### Add resources (`<source>`-only)

1. Determine the appropriate module file based on resource type:
   - Networking resources → `modules/networking.bicep`
   - Compute resources → `modules/compute.bicep`
   - Data/storage resources → `modules/data.bicep`
   - If no matching module exists, create one
2. Read `.github/skills/shared/bicep-best-practices.md` and generate the resource block following those rules
3. Use values explicitly supplied by the source model first. For genuinely unspecified configuration, a documented resource-config default may be proposed with its default provenance disclosed; never use a default to replace an unresolved expression, missing parameter input, or uncertain Azure observation. Represent required unknowns as parameters/uncertainties for user completion.
4. Add parameters in the existing template/parameter-file structure and preserve the parameter file's current format. Do not assume the entry point is named `main.bicep`.
5. Follow Bicep best practices: `parent:` for child resources, `@secure()`, `@description()`, symbolic references. Never copy secret values from a source model into templates — use `@secure()` parameters instead

### Remove resources (Bicep-only)

1. **Dependency halt check**: scan all remaining Bicep files for symbolic references to the resource being removed. If any are found, halt removal of that resource and report: "Cannot remove <resource-name>: it is referenced by <dependent-resource> in <file>. Resolve the dependency first or use Selective mode to skip this resource."
2. Remove the `resource` block from the module file
3. Remove associated parameters from the selected entry point and the existing parameter file, preserving that file's format
4. Remove module references from the selected entry point if the module file is now empty
5. Remove empty module files
6. **Empty-template halt check**: if the selected entry point would have no remaining resource or module declarations after removals, warn: "Removing these resources would leave the deployment entry point empty. Confirm you want to proceed or use Selective mode to retain some resources.", and halt until the user confirms.

### Update properties (drifted resources, Azure source only)

When resolving property-level drift by accepting an Azure-actual value into the templates, obtain a separate per-property decision. Do not adopt omissions, default-derived values, read-only/provider-maintained values, or unresolved observations as though they were confirmed drift. Check ownership before changing resources maintained by another pipeline:

1. Locate the property in the module file (or the parameter that feeds it)
2. Update the Bicep property value or the `.bicepparam` parameter value to the Azure-actual value
3. Present the changed values for confirmation before writing

## 4. Present Result

```
## Bicep Updated ✓

**Added:** 1 resource (cosmos-db)
**Removed:** 1 resource (redis-cache)

The Bicep templates now match the <source>.

| File | Changes |
|------|---------|
| <selected-entry-point> | Added cosmos-db module reference; removed redis-cache reference |
| modules/data.bicep | Added Cosmos DB resource; removed Redis Cache resource |
| <name>.bicepparam | Added cosmos-db parameters; removed redis-cache parameters |

⚠️ Review the updated `.bicepparam` file — new parameters use defaults that you may want to customize.
```

In Selective mode, batch all file writes: collect and verify every per-resource choice first, then apply all changes at once and present a single summary table.
