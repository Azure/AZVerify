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
- `-AzureIdentity` — exact full ARM-ID matching; no heuristic matching. Use for Bicep versus Azure, not diagrams.
- `-TrackedProperties` — canonical projection from `azure-property-paths.json`, including top-level SKU and location. Uses `comparisonProperties` when already projected.
- For compatibility, `-CompareProperties` with an Azure label enables canonical tracked projection; a Bicep/Azure pair also enables exact ARM-ID matching. Both Azure paths therefore use the same algorithm.
- `-OutFile` — optional output path; otherwise JSON is written to stdout

## Output

- **stdout**: Match report JSON with in-sync, name-different, and model-only classifications
- **stderr**: Diagnostics only

With `-CompareProperties`, each matched entry (`In Sync` / `In Sync (name differs)`) additionally carries a `propertyComparison` object:

```json
{
  "status": "All Properties Match | Properties Drifted | Incomplete | No Comparable Properties",
  "comparedCount": 5,
  "driftCount": 1,
  "coverage": {
    "status": "Complete | Incomplete | Not Applicable",
    "trackedCount": 8,
    "specifiedCount": 2,
    "notSpecifiedProperties": ["vmSize", "osDiskType"]
  },
  "drifts": [
    { "property": "vmSize", "valueA": "Standard_B2s", "valueB": "Standard_D2s_v5", "severity": "standard" }
  ]
}
```

and the summary gains `resourcesWithPropertyDrift`, `propertyDriftCount`, `confirmedMatch`, `incompleteComparison`, `noComparableProperties`, and `unverified` counts. Each unverified resource is counted once, not once per property/read issue. `propertyComparison.uncertainties` records unavailable/unresolved values; `propertyComparison.coverage` reports how many configured tracked properties have explicit expectations and lists those not specified. Diagram `propertySources` preserves annotation/baseline provenance.

Existence is independent of configuration: `Found` means inventory or a GET confirmed the resource, `Absent` requires confirmed absence, and `Unknown` means it could not be verified. An actual entry with unknown existence matches as `Unverified`, never `In Sync`. `All Properties Match` is the only configuration result that permits “No Change.” `Incomplete` takes precedence over confirmed drift for category counting; confirmed drifts remain in its details. `No Comparable Properties` is existence-only, not a configuration check.

## Exit Codes

- `0` — comparison succeeded
- non-zero — comparison failed; stop and report the error

## Notes

- Diagram matching applies exact match, single-of-type match, substring/Levenshtein matching and child-resource context. Azure identity matching never uses these heuristics.
- Deep comparison coverage is **Incomplete** when any configured tracked property lacks an explicit expectation (including when none are specified), and **Complete** only when every tracked property has an expectation. **Not Applicable** means the resource type has no tracked-property configuration. Unspecified properties are not drift.
- **Property comparison semantics** (`-CompareProperties`): every property in a matched model-A resource is compared against the model-B value (keys only present in B are ignored — the expected model did not specify them; `parentId` and `containerName` are excluded as matching aids). Values are normalized before comparing:
  - Exact ordinal strings by default, including case and whitespace in usernames and other free text
  - Case-insensitive strings only where property metadata declares `normalization: "caseInsensitive"` (SKU names/tiers and selected enums)
  - Boolean coercion: `true`/`"true"`/`"True"` are equal
  - Empty-collection equivalence: `[]`, `{}`, `null`, `""`, and absent are all equal
  - Numeric strings: `"30"` equals `30`
  - Region names: `"West Europe"` equals `"westeurope"` only for fields declaring `normalization: "region"`; there is no general whitespace fallback
  - Arrays compare element-wise in order; expected object members compare recursively, ignoring additional actual members that Azure defaults/returns. Nested string values remain exact.
  - Two strings are never coerced to booleans/numbers; typed booleans/numbers can compare to their serialized scalar equivalents.
- Severity per drifted property comes from `.github/skills/shared/data/azure-property-paths.json`: per-property `severity` when declared, otherwise the resource-type `severity`, otherwise `standard`.
- If `pwsh`/`powershell.exe` or the script is unavailable, use the inline fallback below.

## Script Unavailable — Inline Fallback

If `pwsh`/`powershell.exe` or the script cannot run, compare the two model JSONs directly using these ordered passes:

For **Bicep versus Azure**, instead match exact full ARM IDs, project both sides using `azure-property-paths.json` (including top-level fields), preserve unknown existence/values, and apply the same incomplete/no-comparable/confirmed-match categories above. Never substitute heuristic matching or configuration defaults.

For **diagram matching**:

1. **Exact match** — same `type` and same `name` (case-insensitive) → **In Sync**.
2. **Single-of-type match** — exactly one unmatched resource of a given `type` remains in each model → **In Sync (name differs)**, recording both names.
3. **Near-name match** — same `type` with case-insensitive substring match, or Levenshtein distance ≤ 3 between names → **In Sync (name differs)**.
4. Remaining unmatched resources in Model A → **`<LabelA>` Only**; in Model B → **`<LabelB>` Only**.
5. Emit a match report JSON with `inSync`, `nameDifferent`, and per-label `only` arrays, plus summary counts. Annotate child and conditional resources where present.
6. **Deep mode** (when property comparison was requested): for each matched pair, compare every property of the model-A resource against the model-B value using the normalization rules in the Notes section above, and record drifted properties with their severity from `.github/skills/shared/data/azure-property-paths.json`.
