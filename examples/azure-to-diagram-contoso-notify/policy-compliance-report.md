# Policy Compliance Check — contoso-notify / claude-Opus-4.6

> **Bicep root**: `Results/contoso-notify/claude-Opus-4.6/artifacts/`
> **Evaluated by**: Claude Sonnet 4.6 · Azure subscription 1 (`<SUBSCRIPTION_ID>`)
> **Date**: 2026-04-06

---

## Summary

| # | Resource | Type | Status |
|---|----------|------|--------|
| 1 | `rg-azv-contoso-notify-opus46` | `Microsoft.Resources/subscriptions/resourceGroups` | ✅ Compliant |
| 2 | `contoso-notify-opus46-uami` | `Microsoft.ManagedIdentity/userAssignedIdentities` | ✅ Compliant |
| 3 | `<STORAGE_ACCOUNT>` | `Microsoft.Storage/storageAccounts` | ✅ Compliant |
| 4 | `kv-contoso-notify-opus46-001` | `Microsoft.KeyVault/vaults` | ✅ Compliant |
| 5 | `contoso-notify-opus46` | `Microsoft.Insights/components` | ✅ Compliant |
| 6 | `asp-contoso-notify-opus46-fc1` | `Microsoft.Web/serverfarms` | ✅ Compliant |
| 7 | `contoso-notify-opus46-001` | `Microsoft.Web/sites` | ✅ Compliant |
| 8 | `contoso-email-opus46-001` | `Microsoft.Communication/emailServices` | ✅ Compliant |
| 9 | `contoso-notify-acs-opus46-001` | `Microsoft.Communication/communicationServices` | ✅ Compliant |

**Scope**: `rg-azv-contoso-notify-opus46` (Subscription: Azure subscription 1)
**Policies evaluated**: `checkPolicyRestrictions` API — server-side evaluation across all inherited assignments (management group → subscription → resource group)
**Result**: **9 compliant, 0 non-compliant (deny), 0 non-compliant (audit), 0 modify policies active, 0 need review**

---

## Detail

### Evaluation Method

All resources were evaluated using the `Microsoft.PolicyInsights/checkPolicyRestrictions` REST API (version `2022-03-01`). This API performs **server-side evaluation** against all active policies inherited at Management Group, Subscription, and Resource Group scope. No definitions were fetched or evaluated locally.

- **Resource Group check** used subscription-level scope (even though RG already exists), to detect any `Microsoft.Resources/subscriptions/resourceGroups` policy targets.
- **All other resources** used RG-level scope.

### Per-Resource API Responses

Every resource returned:
```json
{
  "contentEvaluationResult": { "policyEvaluations": [] },
  "fieldRestrictions": []
}
```

**Interpretation:**
- `policyEvaluations: []` — No active policy assignments evaluated as non-compliant for any resource.
- `fieldRestrictions: []` — No field-level value restrictions are enforced on any declared property.

This indicates either:
1. **No Azure Policy assignments** are active in this subscription/resource group, OR
2. All active policies are **compliant** with the declared Bicep property values.

---

## Resolved Parameter Values

| Parameter | Resolved Value |
|-----------|----------------|
| `deploymentSuffix` | `001` (default from `AZV_SUFFIX` env var) |
| `location` | `swedencentral` |
| `managedIdentityName` | `contoso-notify-opus46-uami` |
| `storageAccountName` | `<STORAGE_ACCOUNT>` |
| `storageAccountSkuName` | `Standard_LRS` |
| `keyVaultName` | `kv-contoso-notify-opus46-001` |
| `keyVaultSoftDeleteRetentionInDays` | `7` |
| `applicationInsightsName` | `contoso-notify-opus46` |
| `appServicePlanName` | `asp-contoso-notify-opus46-fc1` |
| `functionAppName` | `contoso-notify-opus46-001` |
| `functionAppRuntimeName` | `dotnet-isolated` |
| `functionAppRuntimeVersion` | `10.0` |
| `functionAppInstanceMemoryMb` | `2048` |
| `functionAppMaxInstanceCount` | `100` |
| `communicationServicesName` | `contoso-notify-acs-opus46-001` |
| `communicationServicesDataLocation` | `Europe` |
| `emailServiceName` | `contoso-email-opus46-001` |
| `emailCustomDomainName` | `<DOMAIN>` |
| `functionAppDeploymentStorageUrl` | `https://<STORAGE_ACCOUNT>.blob.core.windows.net/app-package-<FUNCTION_APP>` (default) |

---

## Notes on Unresolved / Runtime Parameters

The following parameters depend on environment variables or runtime values and were **not included in policy evaluation** (they are app configuration values, not resource properties that policies typically target):

| Parameter | Reason |
|-----------|--------|
| `azureAIFoundryEndpoint` | App setting value — no policy targets this |
| `notificationEmail` | App setting value |
| `openAIModel` | App setting value |
| `senderEmail` | App setting value |
| `usePremiumFeatures` | App setting value |

---

## Conclusion

**The Bicep templates are policy-compliant.** All 9 resources (including the resource group itself) returned zero policy violations, field restrictions, or modify-policy triggers. The deployment can proceed from a policy compliance perspective.

### Recommended Next Steps

- **Deploy**: The templates are ready to deploy to `rg-azv-contoso-notify-opus46`.
- **azv-bicep-whatif**: Run a what-if operation to preview actual Azure changes before deploying.
- **Manual review items**: None — all resources fully resolved without unresolvable parameters affecting policy-relevant fields.
