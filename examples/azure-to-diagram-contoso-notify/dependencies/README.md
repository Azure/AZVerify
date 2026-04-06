# External Dependencies

Resources outside the Contoso-Notify resource group that this deployment depends on, or that require manual configuration after deployment.

## Summary

| External Resource | Resource Group | Dependency Type | Required Action | Depended On By |
|---|---|---|---|---|
| DefaultWorkspace-...-SEC (Log Analytics) | DefaultResourceGroup-SEC | log-analytics | Workspace must exist before deployment | Application Insights |
| contoso-openai (Azure OpenAI) | Unknown (another RG) | external-ai | AI resource must exist; identity needs Cognitive Services OpenAI User role | Function App |
| <DOMAIN> DNS zone | External DNS provider | dns-zone | DNS records must be created for domain verification | Email Domain, ACS |
| contosonotify Key Vault | Contoso-Notify (same RG) | rbac-assignment | Function App system-assigned identity needs Key Vault Secrets User role | Function App |

---

## 1. Log Analytics Workspace

**Type**: log-analytics  
**Resource**: `DefaultWorkspace-<SUBSCRIPTION_ID>-SEC`  
**Resource Group**: `DefaultResourceGroup-SEC`  
**Depended on by**: Application Insights (`contoso-notify`)

The Application Insights component requires a Log Analytics workspace for telemetry storage.
This is the subscription-wide default workspace created by Azure Monitor.

### Verify it exists

```bash
az monitor log-analytics workspace show \
  --resource-group DefaultResourceGroup-SEC \
  --workspace-name DefaultWorkspace-<SUBSCRIPTION_ID>-SEC
```

### Deploy if missing

```bash
az deployment group create \
  --resource-group DefaultResourceGroup-SEC \
  --template-file dependencies/log-analytics.bicep \
  --parameters @dependencies/log-analytics.bicepparam
```

---

## 2. Azure AI Foundry / Azure OpenAI

**Type**: external-ai  
**Resource**: `contoso-openai` (Cognitive Services / Azure OpenAI)  
**Endpoint**: `https://<AI_ENDPOINT>/`  
**Depended on by**: Function App (`contoso-notify`) via `AzureAIFoundryEndpoint` app setting

The Function App calls the Azure OpenAI Responses API to process Contoso-Notify tasks using the `gpt-5-mini` model.

### Required action

The Function App identity (system-assigned or UAMI `contoso-notify-uami`) needs the **`Cognitive Services OpenAI User`** role on the AI resource.

```bash
# Get the UAMI principal ID
UAMI_PID=$(az identity show \
  --name contoso-notify-uami \
  --resource-group Contoso-Notify \
  --query principalId -o tsv)

# Find the AI resource ID (update resource group as needed)
AI_ID=$(az cognitiveservices account show \
  --name contoso-openai \
  --resource-group <resource-group> \
  --query id -o tsv)

# Assign role
az role assignment create \
  --role "Cognitive Services OpenAI User" \
  --assignee-object-id "$UAMI_PID" \
  --scope "$AI_ID"
```

---

## 3. DNS Records for <DOMAIN>

**Type**: dns-zone  
**Depended on by**: Email Domain (`<DOMAIN>`), ACS Communication Service

The custom email domain requires DNS records at the domain registrar/DNS provider before Azure can verify it and allow outbound email.

### Current verification status

| Record | Status |
|---|---|
| Domain TXT | VerificationFailed (DnsRecordsNotMatched) |
| SPF | NotStarted |
| DKIM | NotStarted |
| DKIM2 | NotStarted |
| DMARC | NotStarted |

### Required DNS records

Add these at your DNS provider for `<DOMAIN>`:

| Type | Name | Value | TTL |
|---|---|---|---|
| TXT | `<DOMAIN>` | `ms-domain-verification=<DOMAIN_VERIFICATION_TOKEN>` | 3600 |
| TXT | `<DOMAIN>` | `v=spf1 include:spf.protection.outlook.com -all` | 3600 |
| CNAME | `selector1-azurecomm-prod-net._domainkey` | `selector1-azurecomm-prod-net._domainkey.azurecomm.net` | 3600 |
| CNAME | `selector2-azurecomm-prod-net._domainkey` | `selector2-azurecomm-prod-net._domainkey.azurecomm.net` | 3600 |

### Trigger verification after DNS records propagate

```bash
az communication email-service domain initiate-verification \
  --email-service-name contoso-email-service \
  --resource-group Contoso-Notify \
  --domain-name <DOMAIN> \
  --verification-type Domain

az communication email-service domain initiate-verification \
  --email-service-name contoso-email-service \
  --resource-group Contoso-Notify \
  --domain-name <DOMAIN> \
  --verification-type SPF

az communication email-service domain initiate-verification \
  --email-service-name contoso-email-service \
  --resource-group Contoso-Notify \
  --domain-name <DOMAIN> \
  --verification-type DKIM
```

### After successful verification

Update `senderEmail` in `Contoso-Notify.bicepparam`:
```
param senderEmail = 'donotreply@<DOMAIN>'
```

---

## 4. Key Vault RBAC — Function App System-Assigned Identity

**Type**: rbac-assignment  
**Resource**: Key Vault `<KV_NAME>` (same resource group)  
**Depended on by**: Function App Key Vault secret references (`AcsConnectionString`, `ExternalApiToken`)

The Function App uses system-assigned managed identity for Key Vault references (`keyVaultReferenceIdentity: 'SystemAssigned'`). The system-assigned identity is only created after the Function App is deployed, so this role assignment must be done post-deployment.

### Assign after first deployment

```bash
# Get the Function App system-assigned identity
PRINCIPAL_ID=$(az webapp identity show \
  --name contoso-notify \
  --resource-group Contoso-Notify \
  --query principalId -o tsv)

# Get the Key Vault resource ID
KV_ID=$(az keyvault show \
  --name <KV_NAME> \
  --resource-group Contoso-Notify \
  --query id -o tsv)

# Assign Key Vault Secrets User role
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$KV_ID"
```

### Verify secrets are accessible

```bash
az webapp config appsettings list \
  --name contoso-notify \
  --resource-group Contoso-Notify \
  --query "[?starts_with(name, 'Acs') || starts_with(name, 'Contoso-Notify')]"
```

Key Vault references show as `@Microsoft.KeyVault(...)` when the role is not yet assigned, and resolve to the secret value once the role is in place.

---

## Deployment Order

1. **Log Analytics workspace** (if missing): `az deployment group create --resource-group DefaultResourceGroup-SEC --template-file dependencies/log-analytics.bicep --parameters @dependencies/log-analytics.bicepparam`
2. **Main deployment**: `az deployment group create --resource-group Contoso-Notify --template-file main.bicep --parameters @Contoso-Notify.bicepparam`
3. **Post-deployment**: Assign Key Vault Secrets User role to Function App system-assigned identity (see §4)
4. **Post-deployment**: Assign Cognitive Services OpenAI User role for Azure AI Foundry (see §2)
5. **DNS verification**: Add DNS records and verify `<DOMAIN>` domain (see §3)
