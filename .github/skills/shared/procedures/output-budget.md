# Output Budget Rules

Shared discipline for skills that discover and process 20-40+ Azure resources. Follow these rules strictly to avoid hitting the LLM response length limit.

1. **Save data to files, don't print it.** After discovery and property/enrichment steps, write the resource model to a temporary JSON file. Reference the temporary file in subsequent steps instead of keeping all data in the response.
2. **Minimize inline tables.** Never print full resource tables with more than 10 rows in the response. Print a count summary and write the full table to the skill's markdown deliverable (e.g. `original-request.md`).

   **Output thresholds** (apply at every step where a list or table is displayed):

   | Item count | Chat response | File output |
   |------------|---------------|-------------|
   | ≤10 items | Inline table | Optional |
   | 11–20 items | Count summary only | Save full list to file |
   | >20 items | Count summary only + warn user | Save full list to file |

3. **No per-resource progress messages.** During extraction/enrichment, do NOT print a line per resource. Print a single summary after the batch completes (e.g., "Extracted 34 resources (3 partial)").
4. **Batch CLI calls.** Use a single `az resource list` with `--query` to get all resources, rather than per-resource MCP calls where possible.
5. **Delete intermediate files.** Intermediate files (`extract-*.json`, `resource-list-raw.json`, the temporary resource model JSON file) are never deliverables. Keep them available until the skill's summary/README step has captured the counts it needs, then delete them all before the skill finishes.

Each skill adds its own rule on top of this list for the artifact it builds (e.g. not echoing generated diagram XML or Bicep code in the response) — see the skill's own Output Budget Rules section.
