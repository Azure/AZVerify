# Plan: Consolidate 4 sync/drift skills into 2 drift-detection skills

Merge `azv-bicep-diagram-sync` + `azv-bicep-whatif` → **`azv-bicep-drift-detection`**, and `azv-diagram-azure-sync` + `azv-diagram-azure-sync-deep` → **`azv-diagram-drift-detection`** (9 skills → 7). Common resolution flows move to `shared/procedures/` to keep each SKILL.md lean; the Bicep↔Azure path gains an "update Bicep to match Azure" resolution flow (new capability, per user decision). Both new skills adopt the existing shared script pipeline for Azure discovery, replacing the inline MCP/CLI discovery instructions the old skills carried.

## Decisions

- Split by *artifact being validated* (bicep vs diagram) rather than the original azure-bicep/azure-diagram naming — it cleanly homes the offline bicep↔diagram comparison
- Old skill names kept in new descriptions as routing aliases
- Bicep↔Azure gains resolution flows; provider-registration check retained in Azure mode only (stays inline — not worth a script)
- New skills start at version 2.0; parsing procedures reused unchanged
- Azure discovery routes through `Get-AzureResourceModel.ps1 -Enrich` and `Select-AzureResources.ps1` (same pipeline as `azv-azure-to-bicep`/`azv-azure-to-diagram`), not inline MCP/CLI steps

## Existing shared assets — reuse map

| Asset | Reused as | Changes |
|---|---|---|
| `scripts/Test-AzureAuth.ps1` + `procedures/azure-authentication.md` | Conditional auth gate (Azure-target mode only) | None |
| `scripts/ConvertFrom-DrawioDiagram.ps1` + `procedures/diagram-parsing.md` | Diagram model input, both skills | None |
| `scripts/ConvertFrom-BicepTemplate.ps1` + `procedures/bicep-parsing.md` | Bicep model input, bicep-drift skill | None |
| `scripts/Compare-ResourceModels.ps1` + `procedures/resource-matching.md` | Existence-level comparison, both skills (label-agnostic) | Optional `-CompareProperties` extension (Phase 1b) |
| `scripts/Select-AzureResources.ps1` + `procedures/resource-filtering.md` | Infra-resource exclusion (`-Mode diagram` / `-Mode bicep`) — replaces whatif's inline exclusion list | None |
| `scripts/Get-AzureResourceModel.ps1` | Live Azure discovery + property enrichment — replaces whatif Steps 5a–5c and diagram-azure-sync Steps 4/4b manual discovery | None (script); new contract doc (Phase 1) |
| `data/azure-property-paths.json` | Tracked properties, defaults, severity | None |
| `procedures/output-budget.md` | Report sizing rules | None |

**Genuine gaps** (nothing exists yet): resolution procedures (update-Bicep / update-diagram / update-Azure live only inline in the old SKILL.md files), a script contract doc for `Get-AzureResourceModel.ps1`, and scripted property-level comparison (normalization + severity rules are currently duplicated inline in whatif Step 6b and diagram-azure-sync Step 5b).

## Steps

### Phase 1 — Shared procedures & script extension (foundation, blocks Phases 2–3)

1. Create `shared/procedures/resolution-update-bicep.md` — from bicep-diagram-sync Step 7 (add/remove resources, dependency-reference halt checks, deployment verification gate)
2. Create `shared/procedures/resolution-update-diagram.md` — from bicep-diagram-sync Step 8 / diagram-azure-sync Step 8 (stencil lookup, dual icon pattern, edge cleanup, XML fallback, conditional Bicep regeneration) — *parallel with step 1*
3. Create `shared/procedures/resolution-update-azure.md` — from diagram-azure-sync Steps 9 + 11 (create/delete Bicep generation, per-property drift resolution) — *parallel with steps 1–2*
4. Create `shared/procedures/azure-discovery.md` — script contract for `Get-AzureResourceModel.ps1` (invocation, parameters, output, exit codes, inline fallback), matching the format of the other procedure contracts — *parallel with steps 1–3*
5. **Phase 1b**: extend `Compare-ResourceModels.ps1` with a `-CompareProperties` switch — normalization rules (case-insensitive enums, boolean coercion, empty-collection equivalence, numeric strings, region names) and severity tagging from `data/azure-property-paths.json`; update `procedures/resource-matching.md` contract accordingly

### Phase 2 — Diagram drift skill

The easy merge — diagram-azure-sync already implements deep mode; the `-deep` skill is ~90% duplicate and even delegates its Steps 8–10 back to sync.

6. Create `azv-diagram-drift-detection/SKILL.md` from diagram-azure-sync:
   - Fold in the `-deep` skill's richer Step 4b property-retrieval detail
   - **Replace manual MCP discovery (Step 4) with `Get-AzureResourceModel.ps1 -Enrich` + `Select-AzureResources.ps1 -Mode diagram`**, referencing the new `azure-discovery.md` contract
   - Deep comparison via `Compare-ResourceModels.ps1 -CompareProperties` (Phase 1b)
   - Point resolution steps at Phase 1 procedures; description mentions old names for routing
7. Delete both old skill folders

### Phase 3 — Bicep drift skill

The harder merge — behavioral reconciliation needed.

8. Create `azv-bicep-drift-detection/SKILL.md`:
   - Target-detection step (compare against **diagram** or **live Azure**)
   - Reuse bicep-diagram-sync's richer Step 1a input/entry-point discovery
   - **Conditional auth gate** (diagram mode is offline, Azure mode hard-gates via `azure-authentication.md`)
   - Keep whatif's unique provider-registration check in Azure mode (inline)
   - **Replace whatif's manual discovery (Steps 5a–5c) with `Get-AzureResourceModel.ps1 -Enrich` + `Select-AzureResources.ps1 -Mode bicep`**; drop the duplicated inline exclusion list
   - Property comparison via `Compare-ResourceModels.ps1 -CompareProperties` (Phase 1b)
   - Unified drift report; resolution options per mode, including the new update-Bicep-from-Azure flow
9. Delete both old skill folders

### Phase 4 — Reference sweep (~22 files, depends on Phases 2–3)

10. Update cross-references in:
    - `.github/skills/azv-azure-to-bicep/SKILL.md`
    - `.github/skills/azv-azure-to-diagram/SKILL.md`
    - `.github/skills/azv-bicep-policy-check/SKILL.md`
    - `.github/skills/azv-diagram-to-bicep/SKILL.md`
    - `.github/skills/azv-sketch-to-diagram/SKILL.md`
    - `.github/skills/shared/azure-resource-model.md`
    - `.github/skills/shared/README.md` + `shared/scripts/README.md` (folder-layout table, "nine skills" wording, new procedure files)
    - `README.md`
    - `docs/example-prompts.md`
    - example READMEs/original-requests (update "next steps" pointers; leave historical report contents intact)
11. Rework `docs/test-run-tracker.md`: collapse 4 skill rows → 2 per example, add a mode column (diagram/azure-quick/azure-deep), reset "done" statuses since merged skills are new code paths

### Phase 5 — Verification

12. Grep for old skill names — zero hits outside historical example reports
13. Run `Invoke-Fixtures.ps1` to confirm parser/filter/compare flows still pass after the `-CompareProperties` extension
14. Dry-run both new skills against `examples/azure-to-diagram-contoso-notify` (has diagram + Bicep + prior reports for comparison)

## Relevant files

- `.github/skills/azv-{bicep-diagram-sync,bicep-whatif,diagram-azure-sync,diagram-azure-sync-deep}/SKILL.md` — sources to merge, then delete
- `.github/skills/shared/procedures/` — four new files (three resolution procedures + `azure-discovery.md` contract); existing parsing/matching/auth/filtering procedures reused unchanged
- `.github/skills/shared/scripts/Compare-ResourceModels.ps1` — only script modified (`-CompareProperties`); all others reused as-is

## Further Considerations

1. **Deep mode in the bicep skill too?** whatif already does property-level comparison, so the merged bicep skill is effectively always "deep" against Azure. Recommend: keep it that way (no quick/deep toggle) to avoid mode proliferation. Confirm or add a quick mode for symmetry.
2. **`E2E-testing/` artifacts** reference old flows (Update-plan.md, live-run fixtures) — excluded as historical; flag if they should be updated too.
