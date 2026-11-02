# Azure-to-Diagram discovery: AzVerify1

- Source scope: resource group `AzVerify1`
- Subscription: authorized test subscription (ID masked)
- Discovery date: 2026-11-02
- Discovery found 15 resources; diagram filtering retained 11 and excluded 4.
- The 11 retained resources comprise two Storage Accounts, one Key Vault, one user-assigned managed identity, one NSG, one VNet, three route tables, and two NICs.
- Monitoring resources and the platform alert were excluded by the standard diagram filter; therefore no Monitoring page was applicable.

## Resources

| # | Resource | Type | Location |
|---|---|---|---|
| 1 | azvtest9bd9cf0b | Microsoft.Storage/storageAccounts | swedencentral |
| 2 | azvft19bd9cf0b | Microsoft.Storage/storageAccounts | swedencentral |
| 3 | azvft1-kv-9bd9cf0b | Microsoft.KeyVault/vaults | swedencentral |
| 4 | azvft1-identity | Microsoft.ManagedIdentity/userAssignedIdentities | swedencentral |
| 5 | azvft1-nsg | Microsoft.Network/networkSecurityGroups | swedencentral |
| 6 | azvft1-vnet | Microsoft.Network/virtualNetworks | swedencentral |
| 7 | azvft1-routes | Microsoft.Network/routeTables | swedencentral |
| 8 | azvft1-nic-0 | Microsoft.Network/networkInterfaces | swedencentral |
| 9 | azvft1-nic-1 | Microsoft.Network/networkInterfaces | swedencentral |
| 10 | azvft1-summary-routes-1 | Microsoft.Network/routeTables | swedencentral |
| 11 | azvft1-summary-routes-2 | Microsoft.Network/routeTables | swedencentral |

## Inferred relationships

| # | Source | Relationship | Target |
|---|---|---|---|
| 1 | azvft1-vnet | contains | application subnet (10.91.2.0/24) |
| 2 | azvft1-vnet | contains | ingress subnet (10.91.1.0/24) |
| 3 | azvft1-vnet | contains | data subnet (10.91.3.0/24) |
| 4 | azvft1-nic-0 | connects | application subnet |
| 5 | azvft1-nic-1 | connects | application subnet |
| 6 | azvft1-nsg | secures | application subnet |
| 7 | azvft1-nsg | secures | ingress subnet |
| 8 | azvft1-nsg | secures | data subnet |
| 9 | azvft1-routes | routes | application subnet |
| 10 | azvft1-routes | routes | ingress subnet |
| 11 | azvft1-routes | routes | data subnet |
| 12 | azvft1-nsg | secures | azvft1-nic-0 |
| 13 | azvft1-nsg | secures | azvft1-nic-1 |
| 14 | azvft19bd9cf0b | depends on | azvft1-identity (user-assigned identity) |
| 15 | azvft1-vnet | peers | AzVerify2/azvft2-vnet (external) |

## Notes

- Subnet membership, NSG/route-table association, NIC subnet bindings, the storage managed-identity assignment, and the external VNet peering were confirmed from enriched live properties. No co-location-only relationships were inferred.
- The external VNet and AzVerify2's reciprocal peering are outside this diagram scope.
- Related skills: `azv-diagram-to-bicep`, `azv-diagram-drift-detection`.
