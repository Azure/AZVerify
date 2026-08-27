# Plan: Consolidate 4 sync/drift skills into 2 drift-detection skills

Merge `azv-bicep-diagram-sync` + `azv-bicep-whatif` → **`azv-bicep-drift-detection`**, and `azv-diagram-azure-sync` + `azv-diagram-azure-sync-deep` → **`azv-diagram-drift-detection`** (9 skills → 7). Common resolution flows move to `shared/procedures/` to keep each SKILL.md lean; the Bicep↔Azure path gains an "update Bicep to match Azure" resolution flow (new capability, per user decision).

## Decisions

- Split by *artifact being validated* (bicep vs diagram) rather than the original azure-bicep/azure-diagram naming — it cleanly homes the offline bicep↔diagram comparison
- Old skill names kept in new descriptions as routing aliases
- Bicep↔Azure gains resolution flows; provider-registration check retained in Azure mode only
- New skills start at version 2.0; shared scripts and parsing procedures are out of scope

## Steps

### Phase 1 — Extract shared resolution procedures (foundation, blocks Phases 2–3)

1. Create `shared/procedures/resolution-update-bicep.md` — from bicep-diagram-sync Step 7 (add/remove resources, dependency-reference halt checks, deployment verification gate)
2. Create `shared/procedures/resolution-update-diagram.md` — from bicep-diagram-sync Step 8 / diagram-azure-sync Step 8 (stencil lookup, dual icon pattern, edge cleanup, XML fallback, conditional Bicep regeneration) — *parallel with step 1*
3. Create `shared/procedures/resolution-update-azure.md` — from diagram-azure-sync Steps 9 + 11 (create/delete Bicep generation, per-property drift resolution) — *parallel with steps 1–2*

### Phase 2 — Diagram drift skill

The easy merge — diagram-azure-sync already implements deep mode; the `-deep` skill is ~90% duplicate and even delegates its Steps 8–10 back to sync.

4. Create `azv-diagram-drift-detection/SKILL.md` from diagram-azure-sync, folding in only the `-deep` skill's richer Step 4b property-retrieval detail; point resolution steps at Phase 1 procedures; description mentions old names for routing
5. Delete both old skill folders

### Phase 3 — Bicep drift skill

The harder merge — behavioral reconciliation needed.

6. Create `azv-bicep-drift-detection/SKILL.md`:
   - Target-detection step (compare against **diagram** or **live Azure**)
   - Reuse bicep-diagram-sync's richer Step 1a input/entry-point discovery
   - **Conditional auth gate** (diagram mode is offline, Azure mode hard-gates via `azure-authentication.md`)
   - Keep whatif's unique provider-registration check in Azure mode
   - Unified drift report; resolution options per mode, including the new update-Bicep-from-Azure flow
7. Delete both old skill folders

### Phase 4 — Reference sweep (~22 files, depends on Phases 2–3)

8. Update cross-references in:
   - `.github/skills/azv-azure-to-bicep/SKILL.md`
   - `.github/skills/azv-azure-to-diagram/SKILL.md`
   - `.github/skills/azv-bicep-policy-check/SKILL.md`
   - `.github/skills/azv-diagram-to-bicep/SKILL.md`
   - `.github/skills/azv-sketch-to-diagram/SKILL.md`
   - `.github/skills/shared/azure-resource-model.md`
   - `README.md`
   - `docs/example-prompts.md`
   - example READMEs/original-requests (update "next steps" pointers; leave historical report contents intact)
9. Rework `docs/test-run-tracker.md`: collapse 4 skill rows → 2 per example, add a mode column (diagram/azure-quick/azure-deep), reset "done" statuses since merged skills are new code paths

### Phase 5 — Verification

10. Grep for old skill names — zero hits outside historical example reports
11. Dry-run both new skills against `examples/azure-to-diagram-contoso-notify` (has diagram + Bicep + prior reports for comparison)

## Relevant files

- `.github/skills/azv-{bicep-diagram-sync,bicep-whatif,diagram-azure-sync,diagram-azure-sync-deep}/SKILL.md` — sources to merge, then delete
- `.github/skills/shared/procedures/` — three new resolution procedure files; existing parsing/matching/auth procedures reused unchanged
- `.github/skills/shared/scripts/` — no changes; `Compare-ResourceModels.ps1` etc. already skill-agnostic

## Further Considerations

1. **Deep mode in the bicep skill too?** whatif already does property-level comparison, so the merged bicep skill is effectively always "deep" against Azure. Recommend: keep it that way (no quick/deep toggle) to avoid mode proliferation. Confirm or add a quick mode for symmetry.
2. **`E2E-testing/` artifacts** reference old flows (Update-plan.md, live-run fixtures) — excluded as historical; flag if they should be updated too.
