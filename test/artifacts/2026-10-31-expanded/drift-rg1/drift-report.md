# Bicep drift report (COMPLETE)

Scope: subscription `9bd9cf0b-dfc1-4fd3-833c-9fdf4d49d9d2`, resource group `AzVerify1`. Read-only run.

| Category | Count |
|---|---|
| Create (in Bicep, not in Azure) | 0 |
| Modify (property drift) | 1 |
| Not in template (in Azure only) | 1 |
| Unverified | 0 |
| No change | 13 |

## Modify
- `Microsoft.Network/virtualNetworks` `azvft1-vnet`
  - addressPrefixes: Bicep `{"Length":12}` vs Azure `{"Length":12}`

## Not in template (in Azure only)
These may be unmanaged, created by Azure automatically, or child resources outside this template. Review before deleting anything.
- `Microsoft.Storage/storageAccounts` `azvtest9bd9cf0b`

_Elapsed 15.8s, 12 ARM request(s), 0 retries._
