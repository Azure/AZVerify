# AzVerify1 Azure-to-Bicep output

Generated from a fresh, enriched read of the tagged `AzVerify1` fixture on 2026-11-02. The active authorized subscription was explicitly pinned for every Azure probe. No template was deployed.

## Files

- `main.bicep` and `main.azverify1.bicepparam` deploy the AzVerify1 resource group.
- `modules/identity.bicep`, `networking.bicep`, `data.bicep`, and `monitoring.bicep` contain the resource modules.
- `dependencies/` contains separate templates and parameter files for the AzVerify1 and reciprocal AzVerify2 VNet peerings. See `dependencies/README.md`.

## Configuration fidelity

- The VNet preserves `10.91.0.0/16` and its three non-overlapping `/24` subnets. Each subnet retains the live NSG, route-table, and network-policy settings.
- Both NICs retain their dynamic IPv4 configuration in the application subnet and their NSG association.
- Both storage accounts remain Hot, enforce TLS 1.2, disable public network access, and preserve the live network ACL and encryption settings. The expanded account retains its user-assigned identity.
- Key Vault retains disabled public access and a Deny network ACL default. Log Analytics and Application Insights retain disabled ingestion/query public access. The action group remains disabled with no receivers.
- Computed Application Insights values are not parameters; no deployable secret paths were emitted.

## Pre-deployment verification

**Result: 9 categories checked, 0 errors.** All generated files compiled: 7/7 `.bicep` and 3/3 `.bicepparam`. ARM validation succeeded for the main template, both peering templates, and the data module independently. Validation did not deploy resources.

| Category | Result |
|---|---|
| SKU dependencies | PASS - no applicable conditional SKU dependencies were found |
| Resource compatibility | PASS - both NICs are connected to the application subnet in the VNet |
| Networking | PASS - subnet prefixes are distinct, within the VNet address space, and retain the live NSG/route-table links |
| Security | PASS with warnings - TLS 1.2 and disabled public access are preserved |
| Regional availability | PASS - all four ARM validations succeeded in `swedencentral` |
| API-version currency | PASS - Bicep Schema MCP returned stable schemas for the generated resource types |
| Bicep best practices | PASS - modular templates, symbolic references, descriptions, and parameter files compile cleanly |
| Missing dependencies | PASS - the external, reciprocal VNet peerings are modeled separately |
| Parameter completeness | PASS - all three parameter files build successfully |

### Warnings retained from the live configuration

- Both storage accounts have `networkAcls.defaultAction = 'Allow'` while `publicNetworkAccess = 'Disabled'`. The generated templates preserve these live values; review the ACL default before changing public access.
- Key Vault has a 7-day soft-delete retention period, and the live response did not confirm purge protection as enabled. The template preserves the observed configuration.
- Main-template ARM validation succeeded. Its data module receives an identity ID from another module output, so that nested module is also validated independently; the standalone data-module validation succeeded.

## Build and validation

From this directory:

```bash
for f in main.bicep modules/*.bicep dependencies/*.bicep; do
  az bicep build --file "$f"
done
for f in main.azverify1.bicepparam dependencies/*.bicepparam; do
  az bicep build-params --file "$f"
done

az deployment group validate \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group AzVerify1 \
  --template-file main.bicep \
  --parameters main.azverify1.bicepparam
```

Validate the two dependency templates separately in their owning resource groups, as shown in `dependencies/README.md`. These commands validate templates; they do not deploy them.
