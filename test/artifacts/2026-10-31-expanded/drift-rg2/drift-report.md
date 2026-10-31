# Bicep drift report (COMPLETE)

Scope: subscription `9bd9cf0b-dfc1-4fd3-833c-9fdf4d49d9d2`, resource group `AzVerify2`. Read-only run.

| Category | Count |
|---|---|
| Create (in Bicep, not in Azure) | 0 |
| Modify (property drift) | 1 |
| Not in template (in Azure only) | 0 |
| Unverified | 0 |
| No change | 10 |

## Modify
- `Microsoft.Network/virtualNetworks` `azvft2-vnet`
  - addressPrefixes: Bicep `{"Length":12}` vs Azure `{"Length":12}`

_Elapsed 12.4s, 10 ARM request(s), 0 retries._
