# Deep Sync Report: Diagram ↔ Azure

**Diagram**: `results/resourcegroup01-drawing/claude-Opus-4.6/artifacts/resourcegroup01-drawing.drawio`
**Azure Scope**: `rg-azv-resourcegroup01-opus46` (Azure subscription 1, `<SUBSCRIPTION_ID>`)
**Date**: 2025-04-06
**Model**: Claude Opus 4.6

---

## Tier 1 — Summary

| Resource | Type | Existence | Critical | Warning | Info |
|----------|------|-----------|----------|---------|------|
| webapp ↔ webapp-rg01-opus46-001 | `Microsoft.Web/sites` | ✅ (name differs) | 1 | 0 | 0 |
| App-Service-Plan | `Microsoft.Web/serverFarms` | ✅ | 0 | 0 | 0 |
| VNET-01 | `Microsoft.Network/virtualNetworks` | ✅ | 0 | 0 | 0 |
| Subnet-01 | `Microsoft.Network/virtualNetworks/subnets` | ✅ | 0 | 0 | 0 |
| Subnet-02 | `Microsoft.Network/virtualNetworks/subnets` | ✅ | 0 | 0 | 0 |
| NIC-01 | `Microsoft.Network/networkInterfaces` | ✅ | 0 | 0 | 0 |
| VM01 | `Microsoft.Compute/virtualMachines` | ⬜ Diagram Only | — | — | — |
| pe-webapp | `Microsoft.Network/privateEndpoints` | ⬜ Diagram Only | — | — | — |
| privatelink.azurewebsites.net | `Microsoft.Network/privateDnsZones` | 🔷 Azure Only | — | — | — |

---

## Tier 2 — Detailed Property Diffs

### webapp ↔ webapp-rg01-opus46-001 (`Microsoft.Web/sites`) — ✅ In Sync (name differs, properties drifted)

**Property Drift:**

| Property | Expected | Actual | Severity | Source |
|----------|----------|--------|----------|--------|
| publicNetworkAccess | `Disabled` | `Enabled` | Critical | auto-detect (PE connection in diagram) |

> The diagram shows a private link (secures) connection from `webapp` to `pe-webapp`, which auto-detects `publicNetworkAccess: Disabled`. However, the Private Endpoint (`pe-webapp`) does not exist in Azure, so public access remains enabled.

**Confirmed In Sync:**

| Property | Value |
|----------|-------|
| httpsOnly | `true` |
| minTlsVersion | `1.2` |
| http20Enabled | `true` |
| ftpsState | `Disabled` |

---

### App-Service-Plan (`Microsoft.Web/serverFarms`) — ✅ In Sync (all properties match)

**Confirmed In Sync:**

| Property | Value |
|----------|-------|
| skuName | `S1` |
| skuTier | `Standard` |
| kind | `app` |
| reserved | `false` |
| capacity | `1` |

---

### VNET-01 (`Microsoft.Network/virtualNetworks`) — ✅ In Sync (all properties match)

**Confirmed In Sync:**

| Property | Value |
|----------|-------|
| addressPrefixes | `10.0.0.0/16` |
| enableDdosProtection | `false` |

---

### Subnet-01 (`Microsoft.Network/virtualNetworks/subnets`) — ✅ In Sync (all properties match)

**Confirmed In Sync:**

| Property | Value |
|----------|-------|
| addressPrefix | `10.0.1.0/24` |
| serviceEndpoints | `[]` |
| delegations | `[]` |
| privateEndpointNetworkPolicies | `Disabled` |

---

### Subnet-02 (`Microsoft.Network/virtualNetworks/subnets`) — ✅ In Sync (all properties match)

**Confirmed In Sync:**

| Property | Value |
|----------|-------|
| addressPrefix | `10.0.2.0/24` |
| serviceEndpoints | `[]` |
| delegations | `[]` |
| privateEndpointNetworkPolicies | `Disabled` |

---

### NIC-01 (`Microsoft.Network/networkInterfaces`) — ✅ In Sync (all properties match)

**Confirmed In Sync:**

| Property | Value |
|----------|-------|
| enableAcceleratedNetworking | `false` |
| enableIPForwarding | `false` |
| privateIPAllocationMethod | `Dynamic` |

---

## Existence Drift Details

### ⬜ Diagram Only — Missing from Azure

| Resource | Type | Notes |
|----------|------|-------|
| VM01 | `Microsoft.Compute/virtualMachines` | VM with NIC-01 dependency in Subnet-01 |
| pe-webapp | `Microsoft.Network/privateEndpoints` | Private Endpoint for webapp in Subnet-02 |

### 🔷 Azure Only — Not in Diagram

| Resource | Type | Notes |
|----------|------|-------|
| privatelink.azurewebsites.net | `Microsoft.Network/privateDnsZones` | Private DNS zone for webapp private endpoint (infrastructure-level) |

---

## Summary

- **6 resources matched** (5 exact name, 1 name differs)
- **2 resources in diagram only** (VM01, pe-webapp — not deployed)
- **1 resource in Azure only** (Private DNS Zone — infrastructure)
- **1 property drift** (Critical: webapp publicNetworkAccess)
- **Drift types**: Existence + Property
