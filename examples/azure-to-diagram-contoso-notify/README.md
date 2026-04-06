# Contoso-Notify — Generated Bicep Templates

**Source**: Azure resource group `Contoso-Notify`, Subscription Azure subscription 1 (`<SUBSCRIPTION_ID>`)  
**Generated**: 2026-04-05  
**Tool**: azv-azure-to-bicep (Claude Sonnet 4.6)

---

## Pre-Deployment Verification

✅ 12 checks passed  
⚠️ 3 warnings  
❌ 0 errors

### Warnings (informational)
- ⚠️ **Security**: `publicNetworkAccess: Enabled` on Storage and Key Vault — matches current Azure state; no private endpoints deployed in this scope
- ⚠️ **Security**: Key Vault `softDeleteRetentionInDays: 7` — minimum retention; consider 90 days for production workloads (noted in code comments)
- ⚠️ **Compatibility**: Storage `kind: Storage` — older kind; `StorageV2` is recommended for new workloads but matches current Azure configuration

---

## Generated Files

| File | Description |
|---|---|
| `main.bicep` | Entry point — orchestrates all 5 modules |
| `Contoso-Notify.bicepparam` | User-editable parameters with comments |
| `modules/identity.bicep` | User-assigned managed identity |
| `modules/monitoring.bicep` | Application Insights |
| `modules/data.bicep` | Storage Account + Key Vault + deployment container |
| `modules/communication.bicep` | Email Service + custom domain + ACS |
| `modules/compute.bicep` | App Service Plan (FC1 FlexConsumption) + Function App |
| `dependencies/README.md` | Dependency summary + post-deploy steps |
| `dependencies/log-analytics.bicep` | Log Analytics workspace (DefaultResourceGroup-SEC) |
| `dependencies/log-analytics.bicepparam` | Params for log-analytics.bicep |

**Resources**: 9 fully extracted · 0 partial · 2 excluded (auto-managed)  
**External dependencies**: 3 (Log Analytics, Azure AI Foundry, DNS zone)  
**Secrets**: 0 hardcoded — `AcsConnectionString` and `ExternalApiToken` use Key Vault references ✅

---

## Deployment

```powershell
# 1. (If needed) Deploy Log Analytics workspace in DefaultResourceGroup-SEC first
az deployment group create `
  --resource-group DefaultResourceGroup-SEC `
  --template-file dependencies/log-analytics.bicep `
  --parameters @dependencies/log-analytics.bicepparam

# 2. Deploy main stack
az deployment group create `
  --resource-group Contoso-Notify `
  --template-file main.bicep `
  --parameters @Contoso-Notify.bicepparam
```

Or with PowerShell:

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName "Contoso-Notify" `
  -TemplateFile "main.bicep" `
  -TemplateParameterFile "Contoso-Notify.bicepparam"
```

---

## Next Steps

1. **Post-deployment RBAC** — Assign `Key Vault Secrets User` to the Function App system-assigned identity (details in `dependencies/README.md` §4)
2. **Azure AI Foundry** — Assign `Cognitive Services OpenAI User` role to `contoso-notify-uami` (`dependencies/README.md` §2)
3. **DNS verification** — Add DNS records for `<DOMAIN>` and run `initiate-verification` (`dependencies/README.md` §3), then update `senderEmail` to `donotreply@<DOMAIN>`
4. **Populate Key Vault secrets** — Add `AcsConnectionString` and `ExternalApiToken` secrets to `<KV_NAME>` vault manually after deployment
5. **Related skills**: Run `/azv-bicep-whatif` to compare this template against live Azure, or `/azv-bicep-policy-check` to validate against Azure Policy
