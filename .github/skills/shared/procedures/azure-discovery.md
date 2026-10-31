# Azure Discovery Script Contract

Canonical contract for `.github/skills/shared/scripts/Get-AzureResourceModel.ps1`. Referenced by all skills that build a resource model from a live Azure environment (or a captured payload).

---

## Script

- **Path**: `.github/skills/shared/scripts/Get-AzureResourceModel.ps1`
- **Purpose**: Discover Azure resources in a scope, optionally enrich each resource with its tracked configuration properties, optionally apply the shared filtering rules, and emit the shared resource model JSON.

## Invocation

```powershell
# Live discovery, enriched and filtered (recommended for drift skills)
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -ResourceGroup <rg-name> -Enrich -Mode diagram|bicep -OutFile <path>

# Offline mode from a captured `az resource list` payload
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -FromJson <captured.json> -Enrich -Mode diagram -OutFile <path>

# Expected-aware Bicep drift discovery (same path as the fast workflow)
pwsh .github/skills/shared/scripts/Get-AzureResourceModel.ps1 -SubscriptionId <sub-id> [-ResourceGroup <rg-name>] -ExpectedModel <filtered-expected.json> -Mode bicep -ManagementEndpoint <active-cloud-resource-manager-endpoint> -OutFile <path>
```

## Parameters

- `-ResourceGroup` — optional resource group name to scope live discovery
- `-SubscriptionId` — optional subscription id to scope live discovery (omit both to use the active subscription's full scope)
- `-Enrich` — when set, performs a targeted per-resource detail call (`az resource show --ids` or `Get-AzResource -ResourceId`) and extracts the tracked properties defined in `.github/skills/shared/data/azure-property-paths.json` (including composite rules such as `osImage`)
- `-StripReadOnly` — removes read-only and ARM-internal properties per `.github/skills/shared/data/arm-readonly-properties.json`. Use for Bicep generation; **leave off for drift comparison**, which may need the full property bag
- `-FromJson` — offline mode: path to a captured `az resource list` (or equivalent) JSON payload; no Azure session required
- `-Mode` — optional filter mode (`diagram` or `bicep`); when provided, the script invokes `Select-AzureResources.ps1` on the model before returning it (see `.github/skills/shared/procedures/resource-filtering.md`)
- `-OutFile` — optional output path; otherwise JSON is written to stdout
- `-ExpectedModel` — drift-only expected-aware discovery. Requires an explicit subscription and **Azure CLI authentication**, even when Az PowerShell is installed/authenticated. Scope/inventory/token calls all use that CLI session. Optional resource group restricts inventory; otherwise inventories the selected subscription.
- `-ManagementEndpoint` — ARM endpoint from `az cloud show --query endpoints.resourceManager -o json`, default public Azure
- `-ThrottleLimit`, `-MaxRetry`, `-TimeoutSeconds` — bounded detail-request concurrency, retries and timeouts for expected-aware discovery

## Output

- **stdout**: Single resource model JSON object conforming to `.github/skills/shared/azure-resource-model.md`, including:
  - derived relationships (`contains`, `connects`, `depends`, `secures`) from resource id hierarchy and property references
  - a `secrets` array per resource flagging secret-bearing property paths (values are masked before output)
- **stderr**: Diagnostics and per-resource enrichment progress only

## Exit Codes

- `0` — discovery succeeded
- non-zero — discovery failed; stop and report the error

## Prerequisites

- Run the authentication gate first — see `.github/skills/shared/procedures/azure-authentication.md`
- Live mode requires Azure CLI (`az`) on PATH **or** an authenticated Az PowerShell session with the `Az.Resources` module; Azure CLI is preferred when both are available
- Offline mode (`-FromJson`) requires only the captured JSON file

## Notes

- Drift-detection skills should invoke with `-Enrich -Mode diagram|bicep` so the returned model is already enriched and filtered — no separate `Select-AzureResources.ps1` call is needed.
- Enrichment issues one detail call per resource; expect proportional runtime on large scopes. Progress is reported on stderr.
- Subscription-level discovery can be noisy — warn the user before comparing an entire subscription.
- Bicep drift paths use `-ExpectedModel`, not legacy enrichment. Inventory confirms existence separately from configuration. Detail GETs use the declared API version, with provider-version fallback when necessary. Confirmed 404 resource absence is `Absent`; 403, exhausted 429, and unavailable reads are `Unknown` existence unless inventory already established `Found`. Projected property values become `unknown` and read errors appear in `issues`; tokens/raw responses are not persisted. An inventory/authentication failure remains a hard failure.
- If `pwsh`/`powershell.exe` or the script is unavailable, use the inline fallback below.

## Script Unavailable — Inline Fallback

If `pwsh`/`powershell.exe` or the script cannot run, build the Azure resource model directly:

1. **List resources in scope**: use `mcp_azure_group_resource_list` for a resource group scope (or `mcp_azure_subscription_list` + a subscription-wide listing), falling back to `az resource list --resource-group <rg-name> -o json`.
2. **Build model entries**: for each discovered resource create:
   ```json
   {
     "id": "<full-resource-id>",
     "type": "<Microsoft.Provider/resourceType>",
     "name": "<resource-name>",
     "resourceGroup": "<resource-group-name>",
     "location": "<region>",
     "properties": {},
     "relationships": []
   }
   ```
3. **Enrich** (when property-level detail is needed): for each resource, look up its type in `.github/skills/shared/data/azure-property-paths.json` and retrieve full properties using the listed MCP tool (primary) or `az` CLI fallback command; extract each tracked property via its ARM JSON path into the `properties` bag.
4. **Derive relationships**: child resources get a `contains` relationship from their parent (derived from resource id segments); resource-id references inside properties become `connects`, `depends`, or `secures` edges as appropriate.
5. **Filter**: apply the inline fallback in `.github/skills/shared/procedures/resource-filtering.md` for the requested mode (`diagram` or `bicep`).
6. **Emit** the resulting resource model JSON conforming to `.github/skills/shared/azure-resource-model.md`. Never include secret values — mask any credential-like property values.
