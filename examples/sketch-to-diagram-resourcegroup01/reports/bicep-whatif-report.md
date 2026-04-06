# Bicep What-If Report

**Target**: Resource Group `rg-azv-resourcegroup01-opus46` — Subscription `Azure subscription 1` (`<SUBSCRIPTION_ID>`)
**Template**: `results/resourcegroup01-drawing/claude-Opus-4.6/main.bicep`
**Parameters**: `results/resourcegroup01-drawing/claude-Opus-4.6/resourcegroup01-drawing.bicepparam`
**Generated**: 2026-04-06

---

## Summary

| Category | Count |
|----------|-------|
| 🆕 Create | 3 |
| ✏️ Modify | 1 |
| 🗑️ Delete | 0 |
| ✅ No Change | 7 |

---

## 🆕 Create — Resources in template but NOT in Azure

These resources will be **created** when the template is deployed.

| # | Resource | Type | Resource Group |
|---|----------|------|----------------|
| 1 | VM01 | Microsoft.Compute/virtualMachines | rg-azv-resourcegroup01-opus46 |
| 2 | pe-webapp | Microsoft.Network/privateEndpoints | rg-azv-resourcegroup01-opus46 |
| 3 | pe-webapp/default | Microsoft.Network/privateEndpoints/privateDnsZoneGroups | rg-azv-resourcegroup01-opus46 |

> **Note:** The private endpoint (`pe-webapp`) and its DNS zone group (`pe-webapp/default`) do not exist in Azure. Once they are created, private DNS resolution for the Web App will be enabled through the existing `privatelink.azurewebsites.net` DNS zone.

---

## ✏️ Modify — Resources with property differences

### webapp-rg01-opus46-001 (Microsoft.Web/sites)

| Property | Current Azure Value | Template Value | Severity |
|----------|-------------------|----------------|----------|
| publicNetworkAccess | `Enabled` | `Disabled` | 🔴 Critical |

> **Impact:** The template declares `publicNetworkAccess: 'Disabled'`, which will block all public traffic to the Web App. Currently Azure has it `Enabled`. After deployment, the Web App will only be accessible through the private endpoint (which will also be created). This is the intended secure architecture pattern — ensure the private endpoint deploys successfully first.

---

## 🗑️ Delete

No resources in Azure are absent from the template. No deletions expected.

---

<details>
<summary>✅ No Change — 7 resources match</summary>

| # | Resource | Type |
|---|----------|------|
| 1 | VNET-01 | Microsoft.Network/virtualNetworks |
| 2 | VNET-01/Subnet-01 | Microsoft.Network/virtualNetworks/subnets |
| 3 | VNET-01/Subnet-02 | Microsoft.Network/virtualNetworks/subnets |
| 4 | NIC-01 | Microsoft.Network/networkInterfaces |
| 5 | App-Service-Plan | Microsoft.Web/serverfarms |
| 6 | privatelink.azurewebsites.net | Microsoft.Network/privateDnsZones |
| 7 | VNET-01-link | Microsoft.Network/privateDnsZones/virtualNetworkLinks |

</details>
