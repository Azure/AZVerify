# External Dependencies

The resources in the Contoso-Voting resource group depend on the following external resources that live outside the `Contoso-Voting` resource group. These cannot be deployed by the main Bicep templates — they require separate coordination.

## Summary

| External Resource | Resource Group | Dependency Type | Required Action | Depended On By |
|---|---|---|---|---|
| DefaultWorkspace-xxxxxxxx…-NEU | DefaultResourceGroup-NEU | log-analytics | Workspace must exist; Application Insights references it for log ingestion | contoso-voting (Application Insights) |

## Dependency Details

### Log Analytics Workspace (`DefaultWorkspace-NEU`)

**Resource ID:** `/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/DefaultResourceGroup-NEU/providers/Microsoft.OperationalInsights/workspaces/DefaultWorkspace-<SUBSCRIPTION_ID>-NEU`

**Type:** `Microsoft.OperationalInsights/workspaces`

**Depends on this:** `contoso-voting` (Application Insights) — configured with `IngestionMode: LogAnalytics` pointing to this workspace.

**Required Action:** This workspace must exist before deploying the main Bicep templates. If the workspace does not exist, Application Insights will fail to configure log ingestion.

**Verify the workspace exists:**

```bash
az monitor log-analytics workspace show \
  --resource-group DefaultResourceGroup-NEU \
  --workspace-name DefaultWorkspace-<SUBSCRIPTION_ID>-NEU \
  -o json
```

**If you need to create it separately**, a template is provided:

```bash
# Deploy the Log Analytics workspace
az deployment group create \
  --resource-group DefaultResourceGroup-NEU \
  --template-file log-analytics.bicep \
  --parameters @log-analytics.bicepparam
```

## Deployment Order

1. Verify or deploy the Log Analytics workspace (`DefaultResourceGroup-NEU`)
2. Deploy the main Contoso-Voting templates (`Results/contoso-voting/claude-Opus-4.6/`)
