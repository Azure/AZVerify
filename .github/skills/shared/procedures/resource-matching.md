# Resource Matching Script Contract

Canonical contract for `.github/skills/shared/scripts/Compare-ResourceModels.ps1`. Referenced by all sync and comparison skills.

---

## Script

- **Path**: `.github/skills/shared/scripts/Compare-ResourceModels.ps1`
- **Purpose**: Compare two resource model JSON files using the shared ordered matching rules.

## Invocation

```powershell
pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <model-a.json> -ModelB <model-b.json> -LabelA <label-a> -LabelB <label-b> [-OutFile <path>]
```

## Parameters

- `-ModelA` — required path to the first resource model JSON
- `-ModelB` — required path to the second resource model JSON
- `-LabelA` — optional label for model A (defaults to `ModelA`)
- `-LabelB` — optional label for model B (defaults to `ModelB`)
- `-OutFile` — optional output path; otherwise JSON is written to stdout

## Output

- **stdout**: Match report JSON with in-sync, name-different, and model-only classifications
- **stderr**: Diagnostics only

## Exit Codes

- `0` — comparison succeeded
- non-zero — comparison failed; stop and report the error

## Notes

- The script applies exact match, single-of-type match, substring/Levenshtein matching, child-resource context, and conditional-resource annotations.
- If `pwsh`/`powershell.exe` or the script is unavailable, use the inline fallback below.

## Script Unavailable — Inline Fallback

If `pwsh`/`powershell.exe` or the script cannot run, compare the two model JSONs directly using these ordered passes:

1. **Exact match** — same `type` and same `name` (case-insensitive) → **In Sync**.
2. **Single-of-type match** — exactly one unmatched resource of a given `type` remains in each model → **In Sync (name differs)**, recording both names.
3. **Near-name match** — same `type` with name similarity ≥ 0.7 (substring or Levenshtein) → **In Sync (name differs)**.
4. Remaining unmatched resources in Model A → **`<LabelA>` Only**; in Model B → **`<LabelB>` Only**.
5. Emit a match report JSON with `inSync`, `nameDifferent`, and per-label `only` arrays, plus summary counts. Annotate child and conditional resources where present.
