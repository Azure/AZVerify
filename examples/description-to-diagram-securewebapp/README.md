# Secure Webapp WAF — Infrastructure Code

## Source

**Diagram:** `results/securewebapp/claude-Opus-4.6/artifacts/secure-webapp-waf.drawio`
**Generated:** 2026-04-05

## Pre-Deployment Verification

✅ **19 checks passed** | ⚠️ 0 warnings | ❌ 0 errors

| Category | Status |
|----------|--------|
| SKU dependency rules | ✅ All passed (WAF policy linked, Standard PIP, S1+ for VNet integration) |
| Resource compatibility | ✅ All passed (HTTPS backend, correct DNS zone, VNet link) |
| Networking rules | ✅ All passed (no overlap, dedicated AppGw subnet, correct sizing) |
| Security rules | ✅ All passed (TLS 1.2+, HTTPS only, FTPS disabled, secrets via env var) |
| Version currency | ✅ All passed (latest stable API versions, .NET 8 LTS runtime) |
| Bicep best practices | ✅ All passed (parent property, symbolic refs, no name on modules) |

## Generated Files

| File | Description |
|------|-------------|
| main.bicep | Entry point — 4 module references, all params with `@description` |
| secure-webapp-waf.bicepparam | User-editable parameter values with cost/sizing comments |
| modules/networking.bicep | VNet, 3 subnets, PIP, DNS zone, Application Gateway (WAF_v2), WAF Policy |
| modules/compute.bicep | App Service Plan (S1), App Service with VNet integration |
| modules/data.bicep | SQL Server, SQL Database, Key Vault, Private Endpoint, Private DNS Zone + VNet Link |
| modules/monitoring.bicep | Log Analytics Workspace, Application Insights |

## Architecture

- **Inbound traffic:** Public DNS → Public IP → Application Gateway (WAF_v2) → App Service
- **Data access:** App Service → VNet integration → Private Endpoint → SQL Server
- **Secrets:** App Service & App Gateway → Key Vault (RBAC authorization)
- **Telemetry:** App Service → Application Insights → Log Analytics

## Customize

Edit `secure-webapp-waf.bicepparam` to change any deployment settings.
Each parameter has comments explaining the setting, alternatives, and cost.

**Globally unique names required:** `appServiceName`, `sqlServerName`, `keyVaultName` must be unique across Azure.

## Deploy

```powershell
# Azure CLI
az deployment group create \
  --resource-group "my-rg" \
  --template-file main.bicep \
  --parameters @secure-webapp-waf.bicepparam

# PowerShell
New-AzResourceGroupDeployment `
  -ResourceGroupName "my-rg" `
  -TemplateFile main.bicep `
  -TemplateParameterFile secure-webapp-waf.bicepparam
```

**Required environment variable:** Set `SQLPASSWORD` before deploying (used by `readEnvironmentVariable()` in the bicepparam file).

## Next Steps

1. Edit `secure-webapp-waf.bicepparam` to set real, globally unique resource names and your DNS domain
2. Set the `SQLPASSWORD` environment variable
3. Run `azv-bicep-whatif` to preview changes against a live environment
4. Run `azv-bicep-diagram-sync` to verify Bicep matches the diagram
5. Run `azv-bicep-policy-check` to check Azure Policy compliance
