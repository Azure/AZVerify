# Contoso-Voting — Bicep Templates

## Source

- **Resource Group:** `Contoso-Voting`
- **Subscription:** Azure subscription 1 (`<SUBSCRIPTION_ID>`)
- **Generated:** 2026-04-05
- **Model:** `claude-Opus-4.6`

---

## Pre-Deployment Verification

✅ 12 checks passed
⚠️ 3 warnings
❌ 0 errors

### Warnings

- ⚠️ **Security**: App Service `ftpsState` is `FtpsOnly` (current Azure value). Consider setting `Disabled` for stricter FTPS security.
- ⚠️ **Security**: Key Vault `enablePurgeProtection` is not enabled (current Azure value). Consider enabling for production to prevent permanent deletion during soft-delete retention.
- ⚠️ **Security**: Key Vault and Storage Account have `publicNetworkAccess: Enabled`. Consider restricting to private endpoints for production workloads. Comments in the generated files note where to add this.

---

## Generated Files

| File | Description |
|------|-------------|
| `main.bicep` | Entry point — orchestrates all modules, defines all parameters |
| `Contoso-Voting.bicepparam` | User-editable parameter values with comments explaining each setting |
| `modules/compute.bicep` | App Service Plan + App Service (Web App, Linux, .NET 10) |
| `modules/data.bicep` | Storage Account, Key Vault, EventGrid System Topic |
| `modules/monitoring.bicep` | Application Insights (LogAnalytics mode) |
| `modules/identity.bicep` | User-assigned Managed Identity + Website Contributor role assignment |
| `dependencies/README.md` | External dependency documentation and deployment guidance |
| `dependencies/log-analytics.bicep` | Log Analytics workspace template (external dependency) |
| `dependencies/log-analytics.bicepparam` | Parameter values for the Log Analytics workspace |

---

## Resource Counts

| Category | Count |
|----------|-------|
| Resources discovered | 8 |
| Resources excluded (auto-created) | 1 (smartDetectorAlertRules) |
| Resources fully extracted | 7 |
| Resources partially extracted | 0 |
| External dependencies | 1 |
| Secrets requiring manual configuration | 1 |

### Secrets

| Secret | Parameter | Action Required |
|--------|-----------|----------------|
| Application Insights connection string | `appInsightsConnectionString` | Set `APPINSIGHTS_CONNECTION_STRING` env variable before deploying. The connection string is output by the monitoring module after deployment. |

---

## Deployment Commands

### Prerequisites

1. Verify the Log Analytics workspace exists in `DefaultResourceGroup-NEU`:
   ```bash
   az monitor log-analytics workspace show --resource-group DefaultResourceGroup-NEU \
     --workspace-name DefaultWorkspace-<SUBSCRIPTION_ID>-NEU
   ```
   If it doesn't exist, deploy it first:
   ```bash
   az deployment group create --resource-group DefaultResourceGroup-NEU \
     --template-file dependencies/log-analytics.bicep \
     --parameters dependencies/log-analytics.bicepparam
   ```

2. After deploying monitoring, export the Application Insights connection string:
   ```bash
   export APPINSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show \
     --resource-group Contoso-Voting --app contoso-voting --query connectionString -o tsv)
   ```
   On Windows PowerShell:
   ```powershell
   $env:APPINSIGHTS_CONNECTION_STRING = (az monitor app-insights component show `
     --resource-group Contoso-Voting --app contoso-voting --query connectionString -o tsv)
   ```

### Deploy with Azure CLI

```bash
az deployment group create \
  --resource-group Contoso-Voting \
  --template-file main.bicep \
  --parameters Contoso-Voting.bicepparam
```

### Deploy with Azure PowerShell

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName Contoso-Voting `
  -TemplateFile main.bicep `
  -TemplateParameterFile Contoso-Voting.bicepparam
```

---

## Architecture Summary

| Resource | Type | SKU/Size |
|----------|------|----------|
| `asp-contoso-voting-linux` | App Service Plan (Linux) | B1 |
| `contoso-voting` | App Service (Web App, .NET 10) | — |
| `contoso-voting` | Storage Account (StorageV2) | Standard_LRS |
| `kv-contoso-voting` | Key Vault | Standard, RBAC |
| `contoso-voting` | Application Insights | Web, LogAnalytics |
| `contoso-voting-eventgrid` | EventGrid System Topic | — |
| `deploy-uami` | User-Assigned Managed Identity | — |

---

## Next Steps

1. **External dependencies**: See [`dependencies/README.md`](dependencies/README.md) for the Log Analytics workspace setup.
2. **Post-deploy RBAC**: The managed identity `deploy-uami` has Website Contributor on the App Service — this is recreated by `modules/identity.bicep`.
3. **What-If analysis**: Run `/azv-bicep-whatif` to compare this Bicep against the live environment before deploying.
4. **Policy compliance**: Run `/azv-bicep-policy-check` to validate compliance before deploying.
5. **Architecture diagram**: Run `/azv-azure-to-diagram` to generate an architecture diagram if needed.
