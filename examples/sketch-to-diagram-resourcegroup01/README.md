# ResourceGroup01 — Bicep Infrastructure Code

## Source

- **Diagram:** `results/resourcegroup01-drawing/claude-Opus-4.6/resourcegroup01-drawing.drawio`
- **Generated:** 2026-04-05

## Pre-Deployment Verification

✅ **18 checks passed** | ⚠️ 0 warnings | ❌ 0 errors

| Category | Status |
|----------|--------|
| SKU dependency rules | ✅ All passed (rules 1.1–1.7 — N/A or compliant) |
| Resource compatibility rules | ✅ All passed (NIC exists for VM, DNS zone matches service, VNet link created) |
| Networking rules | ✅ All passed (no subnet overlap, adequate sizing) |
| Security rules | ✅ All passed (TLS 1.2, HTTPS only, FTPS disabled, @secure on passwords, public access disabled) |
| Version currency | ✅ All passed (latest stable API versions, current OS image) |
| Bicep best practices | ✅ All passed (no name on modules, parent property, symbolic refs, typed params) |

## Generated Files

| File | Description |
|------|-------------|
| main.bicep | Entry point — 2 module references + PE/DNS inline, all params with @description |
| resourcegroup01-drawing.bicepparam | User-editable parameter values with cost/sizing comments |
| modules/networking.bicep | VNet (VNET-01), 2 subnets (Subnet-01, Subnet-02) |
| modules/compute.bicep | NIC, VM (VM01), App Service Plan, Web App (public access disabled) |

Resources created in main.bicep (depend on both modules):
- Private Endpoint (pe-webapp) for Web App
- Private DNS Zone (privatelink.azurewebsites.net)
- Private DNS Zone VNet Link
- Private Endpoint DNS Zone Group

## Deployment

### Azure CLI

```bash
az deployment group create \
  --resource-group "ResourceGroup01" \
  --template-file main.bicep \
  --parameters @resourcegroup01-drawing.bicepparam
```

### PowerShell

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName "ResourceGroup01" `
  -TemplateFile main.bicep `
  -TemplateParameterFile resourcegroup01-drawing.bicepparam
```

### Required Environment Variables

Set these before deploying:

| Variable | Description |
|----------|-------------|
| `VM_ADMIN_PASSWORD` | Admin password for VM01 (must meet Azure complexity requirements) |
| `DEPLOY_SUFFIX` | Optional suffix for webapp name uniqueness (defaults to `dev`) |

## Next Steps

1. **Edit `resourcegroup01-drawing.bicepparam`** to set real values — each parameter has comments explaining alternatives and cost impact.
2. **Set environment variables** (`VM_ADMIN_PASSWORD`, optionally `DEPLOY_SUFFIX`) before deploying.
3. **Validate before deploying** with related skills:
   - `azv-bicep-whatif` — preview changes against a live Azure environment
   - `azv-bicep-diagram-sync` — compare Bicep against the source diagram for drift
   - `azv-bicep-policy-check` — check compliance with Azure Policy assignments
