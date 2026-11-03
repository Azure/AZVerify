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
- `-TrackedProperties` — canonical projection from `azure-property-paths.json`, including top-level fields. Uses `comparisonProperties` when already projected; the catalog is not a ceiling on comparison.
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

and the summary gains `resourcesWithPropertyDrift`, `propertyDriftCount`, `confirmedMatch`, `incompleteComparison`, `noComparableProperties`, and `unverified` counts. Each unverified resource is counted once, not once per property/read issue. `propertyComparison.uncertainties` records unavailable/unresolved values; an `identityUnknown` classification is **Unverified**, never a confirmed difference or match. Coverage reports explicit catalog expectations and separately records explicit template leaves outside the catalog. Preserve `diagnostics.parameters` and `diagnostics.parameterScopes` from parsing, and input provenance for parameter-derived expectations.

Existence is independent of configuration: `Found` means inventory or a GET confirmed the resource, `Absent` requires confirmed absence, and `Unknown` means it could not be verified. An actual entry with unknown existence or identity matches as `Unverified`, never `In Sync`. `All Properties Match` is the only configuration result that permits “No Change.” `Incomplete` takes precedence over confirmed drift for category counting; confirmed drifts remain in its details. `No Comparable Properties` is existence-only, not a configuration check. Keep provider-maintained observations (including peering and provisioning status) in a separate `providerMaintained` collection, not in configuration drift counts/tables.

## Exit Codes

- `0` — comparison succeeded
- non-zero — comparison failed; stop and report the error

## Notes

- Diagram matching applies exact match, single-of-type match, substring/Levenshtein matching and child-resource context. Azure identity matching never uses these heuristics.
- Deep comparison coverage is **Incomplete** when any configured tracked property lacks an explicit expectation (including when none are specified), and **Complete** only when every tracked property has an expectation. **Not Applicable** means the resource type has no tracked-property configuration; explicit comparable leaf properties beyond the catalog still count as comparable. Return **No Comparable Properties** only when neither catalog expectations nor any other explicit comparable leaves can be assessed. Unspecified properties are not confirmed drift.
- The catalog defines known comparable paths, severity, and property-specific normalization; it is not an exhaustive allowlist. Conservatively compare explicit expected leaf properties beyond the catalog when the actual leaf can be read, including `properties`, `tags`, top-level `sku`, `kind`, `zones`, and `identity`. Do not infer values for omitted expected properties. Exclude provider-maintained `peeringState` and `peeringSyncLevel` from drift comparison.
- Distinguish confirmed differences from omitted expected properties, values that exist only because of defaults, read-only/provider-maintained values, and unresolved/unavailable inputs. Actual-only keys are omissions, not differences. Report them separately when useful; do not silently treat omission as a match or infer the template's intent. Keep provider-maintained observations such as `peeringState`, `peeringSyncLevel`, and provisioning status separate from both drift and user-configurable expectations.
- **Property comparison semantics** (`-CompareProperties`): compare each explicit expected leaf against the corresponding actual leaf. `parentId` and `containerName` are excluded as matching aids. A missing leaf is distinct from an explicit `null`; null, absent, empty, and default values are not universally equivalent. Values are normalized before comparing only under explicit metadata rules:
  - Exact ordinal strings by default, including case and whitespace in usernames and other free text
  - Case-insensitive comparison only where metadata declares it (selected enums/SKU fields); canonical resource-ID comparison only for ID fields
  - Boolean or numeric coercion only where the data representation is known to be a serialization of that same scalar type
  - Region normalization only for fields declaring region semantics; no general whitespace fallback
  - Arrays preserve order by default. Keyed-set comparison is permitted only where metadata declares the key and set semantics; current keyed sets include diagnostic logs/metrics, DNS configurations, storage ACL rules, and peerings. Use their keys to match entries before comparing entry values.
  - Expected object members compare recursively. Additional actual members are omissions/extra configuration, not matches for absent expected members and not automatically property differences.
  - Explicit `null` compares only with explicit `null`; it is not interchangeable with missing, empty, or default values without a specific metadata rule.
- Severity per drifted property comes from `.github/skills/shared/data/azure-property-paths.json`: per-property `severity` when declared, otherwise the resource-type `severity`, otherwise `standard`.
- If `pwsh`/`powershell.exe` or the script is unavailable, use the inline fallback below.

## Script Unavailable — Inline Fallback

If `pwsh`/`powershell.exe` or the script cannot run, compare the two model JSONs directly using these ordered passes:

For **Bicep versus Azure**, match exact full ARM IDs, project known catalog fields and retain explicit expected leaf fields outside the catalog, preserve unknown existence/values and parameter provenance, and apply the same incomplete/no-comparable/confirmed-match categories above. Never substitute heuristic matching or configuration defaults. Compare keyed sets only where metadata explicitly declares their keyed semantics. Keep Azure-only resources, confirmed differences, omissions/defaults/read-only values, and unresolved/inventory-incomplete items as distinct report groups.

For **diagram matching**:

1. **Exact match** — same `type` and same `name` (case-insensitive) → **In Sync**.
2. **Single-of-type match** — exactly one unmatched resource of a given `type` remains in each model → **In Sync (name differs)**, recording both names.
3. **Near-name match** — same `type` with case-insensitive substring match, or Levenshtein distance ≤ 3 between names → **In Sync (name differs)**.
4. Remaining unmatched resources in Model A → **`<LabelA>` Only**; in Model B → **`<LabelB>` Only**.
5. Emit a match report JSON with `inSync`, `nameDifferent`, and per-label `only` arrays, plus summary counts. Annotate child and conditional resources where present.
6. **Deep mode** (when property comparison was requested): for each matched pair, compare every property of the model-A resource against the model-B value using the normalization rules in the Notes section above, and record drifted properties with their severity from `.github/skills/shared/data/azure-property-paths.json`.
