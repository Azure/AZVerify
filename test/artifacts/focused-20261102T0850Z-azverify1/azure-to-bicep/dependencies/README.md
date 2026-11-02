# External Dependencies

The AzVerify1 VNet peers with `AzVerify2/azvft2-vnet`. The two existing peering resources are both `Connected`; the dependency templates below model each direction independently so they can be validated or deployed in the owning resource group.

| External resource | Resource group | Type | Required action | Depended on by |
|---|---|---|---|---|
| `azvft2-vnet` | `AzVerify2` | VNet peering | Keep the reciprocal VNet peering in sync with AzVerify1 | `azvft1-vnet` |

| File | Purpose |
|---|---|
| `vnet-peering-azverify1.bicep` / `.bicepparam` | Peering owned by the AzVerify1 VNet |
| `vnet-peering-azverify2.bicep` / `.bicepparam` | Reciprocal peering owned by the AzVerify2 VNet |

Both peerings are currently connected and allow virtual-network access. The templates are included for repeatable validation and future maintenance only; this focused test did not deploy them.

If needed, validate each file in its owning resource group:

```bash
az deployment group validate --subscription "$SUBSCRIPTION_ID" --resource-group AzVerify1 --template-file vnet-peering-azverify1.bicep --parameters vnet-peering-azverify1.bicepparam
az deployment group validate --subscription "$SUBSCRIPTION_ID" --resource-group AzVerify2 --template-file vnet-peering-azverify2.bicep --parameters vnet-peering-azverify2.bicepparam
```

Deploy AzVerify1 and AzVerify2 peerings separately only when the operator explicitly intends to update both sides. Verify both states return `Connected` afterward.
