# Resource Matching Script Contract

Canonical contract for `.github/skills/shared/scripts/Compare-ResourceModels.ps1`. Referenced by all sync and comparison skills.

---

## Script

- **Path**: `.github/skills/shared/scripts/Compare-ResourceModels.ps1`
- **Purpose**: Compare two resource model JSON files using the shared ordered matching rules.

## Invocation

```powershell
pwsh .github/skills/shared/scripts/Compare-ResourceModels.ps1 -ModelA <model-a.json> -ModelB <model-b.json> -LabelA <label-a> -LabelB <label-b> [-CompareProperties] [-OutFile <path>]
```

## Parameters

- `-ModelA` — required path to the first resource model JSON
- `-ModelB` — required path to the second resource model JSON
- `-LabelA` — optional label for model A (defaults to `ModelA`)
- `-LabelB` — optional label for model B (defaults to `ModelB`)
- `-CompareProperties` — optional switch enabling property-level comparison of matched resources (deep mode). Model A is the **expected** state; model B is the **actual** state
- `-OutFile` — optional output path; otherwise JSON is written to stdout

## Output

- **stdout**: Match report JSON with in-sync, name-different, and model-only classifications
- **stderr**: Diagnostics only

With `-CompareProperties`, each matched entry (`In Sync` / `In Sync (name differs)`) additionally carries a `propertyComparison` object:

```json
{
  "status": "All Properties Match | Properties Drifted | No Comparable Properties",
  "comparedCount": 5,
  "driftCount": 1,
  "drifts": [
    { "property": "vmSize", "valueA": "Standard_B2s", "valueB": "Standard_D2s_v5", "severity": "standard" }
  ]
}
```

and the summary gains `resourcesWithPropertyDrift` and `propertyDriftCount` counts.

## Exit Codes

- `0` — comparison succeeded
- non-zero — comparison failed; stop and report the error

## Notes

- The script applies exact match, single-of-type match, substring/Levenshtein matching, child-resource context, and conditional-resource annotations.
- **Property comparison semantics** (`-CompareProperties`): every property in a matched model-A resource is compared against the model-B value (keys only present in B are ignored — the expected model did not specify them; `parentId` is excluded as a matching aid). Values are normalized before comparing:
  - Case-insensitive string comparison (SKU names, tiers, enums)
  - Boolean coercion: `true`/`"true"`/`"True"` are equal
  - Empty-collection equivalence: `[]`, `{}`, `null`, `""`, and absent are all equal
  - Numeric strings: `"30"` equals `30`
  - Region names: `"West Europe"` equals `"westeurope"` (whitespace-insensitive fallback)
  - Arrays compare element-wise in order; objects compare by case-insensitive key sets with recursive value normalization
- Severity per drifted property comes from `.github/skills/shared/data/azure-property-paths.json`: per-property `severity` when declared, otherwise the resource-type `severity`, otherwise `standard`.
- If `pwsh`/`powershell.exe` or the script is unavailable, use the inline fallback below.

## Script Unavailable — Inline Fallback

If `pwsh`/`powershell.exe` or the script cannot run, compare the two model JSONs directly using these ordered passes:

1. **Exact match** — same `type` and same `name` (case-insensitive) → **In Sync**.
2. **Single-of-type match** — exactly one unmatched resource of a given `type` remains in each model → **In Sync (name differs)**, recording both names.
3. **Near-name match** — same `type` with case-insensitive substring match, or Levenshtein distance ≤ 3 between names → **In Sync (name differs)**.
4. Remaining unmatched resources in Model A → **`<LabelA>` Only**; in Model B → **`<LabelB>` Only**.
5. Emit a match report JSON with `inSync`, `nameDifferent`, and per-label `only` arrays, plus summary counts. Annotate child and conditional resources where present.
6. **Deep mode** (when property comparison was requested): for each matched pair, compare every property of the model-A resource against the model-B value using the normalization rules in the Notes section above, and record drifted properties with their severity from `.github/skills/shared/data/azure-property-paths.json`.
