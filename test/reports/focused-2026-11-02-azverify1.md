# Focused Azure skill verification: AzVerify1

**Run:** `focused-20261102T0850Z-azverify1`
**Date:** 2026-11-02
**Scope:** `azv-azure-to-bicep` and `azv-azure-to-diagram`, using the existing tagged `AzVerify1` fixture. No Azure deployment was performed. This focused report does not claim that the seven-skill functional suite was run.

## Outcome

| Skill | Status | Summary |
|---|---|---|
| `azv-azure-to-bicep` | PASS | Fresh live and offline extraction, schema checks, generated output, complete builds, and non-deploying ARM validation succeeded. |
| `azv-azure-to-diagram` | PASS | Both documented output paths created two-page diagrams; resource coverage, relationships, icons, edge parents, and rendered fit were checked. |

No existing report was overwritten. Deliverables are in `test/artifacts/focused-20261102T0850Z-azverify1/`.

## Environment and capability checks

- PowerShell 7.6.9, Azure CLI, and Bicep CLI 0.48.1 were available.
- The `Test-AzureAuth.ps1` probe succeeded with the authorized subscription ID explicitly supplied and matched; the ID is withheld from this report.
- `AzVerify1` and `AzVerify2` both exist in `swedencentral` and were readable.
- Azure Best Practices MCP and Bicep Schema MCP tools were called successfully. Stable schemas/API versions were reviewed for Storage `2026-06-01`, Log Analytics `2026-03-01`, Key Vault `2026-05-15`, Managed Identity `2024-11-30`, Network resources/subnets and VNet peering `2026-01-01`, Application Insights `2020-02-02`, and Action Groups `2023-01-01`.
- Draw.io MCP initialization, tool listing, and `create_diagram` succeeded. The raw-file fallback was also written and rendered.

## Method-level coverage

| Skill/method | Result | Evidence |
|---|---|---|
| Resource-group discovery and enriched extraction | PASS - 15 discovered; Bicep filtering retained 14 and diagram filtering retained 11 | Generated Bicep and diagram deliverables; fresh extraction assertions |
| Read-only stripping and secret handling | PASS - computed values are masked, no deployable secret paths; singleton subnet and NIC arrays retained in live extraction | Bicep modules; final focused artifact redaction scan |
| Offline `-FromJson` replay | PASS - replay retained 14 Bicep and 11 diagram resources | Replayed captured `az resource list` output; temporary capture removed |
| Schema-reviewed modular generation | PASS - all generated resource types had callable schema tools and reviewed stable API versions | `azure-to-bicep/` |
| Bicep and parameter compilation | PASS - 7/7 `.bicep` and 3/3 `.bicepparam` built | `azure-to-bicep/README.md` |
| ARM validation without deployment | PASS - main, both reciprocal peering templates, and standalone data module all returned `Succeeded` | `azure-to-bicep/README.md`; `dependencies/README.md` |
| Deployment verification categories | PASS with configuration warnings - all nine documented categories were evaluated; 0 errors | `azure-to-bicep/README.md` |
| Diagram count/type summary | PASS - 11 resources across 7 resource types; 15 inferred relationships | `azure-to-diagram/original-request.md` |
| Diagram relationship inference | PASS - subnet containment, subnet NSG/route-table associations, NIC subnet/NSG relationships, storage identity assignment, and external peering are represented by containment, per-subnet icons, labels, or explicit edges | Both `.drawio` files |
| Draw.io MCP and raw-file fallback | PASS - both outputs contain Overview and Network Topology pages | `mcp-generated.drawio`, `raw-fallback.drawio` |
| XML coverage, icons, labels, metadata, and edges | PASS - 11/11 resources per page; container/icon cells and labels present; all edge parents are `1` | Parsed both final `.drawio` files |
| Rendered diagram inspection and fit | PASS - both pages in both outputs rendered; maximum width 1783 px | Final previews: `mcp-overview.png`, `mcp-network-topology.png`, `fallback-overview.png`, and `fallback-network-topology.png` |

## Pre-deployment verification

The nine categories in `azure-deployment-verification.md` were checked: SKU dependencies; resource compatibility; networking; security; regional availability; API-version currency; Bicep best practices; missing dependencies; and parameter completeness. There were **0 errors**.

Warnings retained accurately from the live fixture:

1. Both storage accounts are Hot and have TLS 1.2 and public network access disabled, but their network ACL `defaultAction` is `Allow`. The templates preserve it.
2. Key Vault public access is disabled and its ACL default is Deny, but its soft-delete retention is 7 days and the live response did not confirm purge protection enabled.
3. The root ARM validation succeeded; because the data module receives its identity ID from a module output, that module was also validated independently and succeeded.
4. Draw.io MCP's cross-page diagnostic flags the standard `0`/`1` root/layer IDs as duplicates. IDs are unique within each page, and both multipage files rendered successfully.

## Diagram details

The Overview page shows the three subnets vertically. The separate Network Topology page uses a compact three-column subnet grid with 36 px route-table and NSG icons inside each subnet; storage, Key Vault, identity, and unattached route tables are in a distinct outside-VNet lane. No resources were placed in a subnet without a confirmed association.

The labeled VNet-peering callout is visible in both final Network Topology renders; the earlier MCP-render discrepancy is resolved.

MCP returned nested parents for the identity edges. Those edges were normalized to parent `1`; the MCP response and unmodified returned XML remain preserved. The identity edges had no explicit absolute route points, so their relative geometry and terminals were left unchanged. Explicit VNet-peering waypoints were already root-parented and retained. Details are in `azure-to-diagram/normalization.md`.

The diagram filter excludes Log Analytics, Application Insights, the action group, and an untagged platform alert rule. The Bicep filter excludes only the platform alert rule and retains 14 resources.

## Final safety gate

- Both storage accounts remained Hot.
- The temporary functional-test policy assignment was absent from both `AzVerify1` and `AzVerify2`.
- No Azure resources were deployed.
- Intermediate resource models and earlier scratch artifact folders were removed after verification.
- The final artifact scan found no authorized subscription ID or unredacted secrets.
