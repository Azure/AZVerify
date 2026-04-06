using 'log-analytics.bicep'

// Azure region for the Log Analytics workspace.
param location = 'northeurope'

// Log Analytics workspace name — must match the name referenced in Application Insights.
param workspaceName = 'DefaultWorkspace-<SUBSCRIPTION_ID>-NEU'

// Log data retention in days.
//   30  → minimum for PerGB2018 SKU (current)
//   90  → recommended for security/audit scenarios
//   730 → maximum
param retentionInDays = 30

// Workspace SKU — pricing tier.
//   PerGB2018 → Pay-per-GB ingestion (~$2.76/GB) — default/current
//   Free      → 500 MB/day limit, 7-day retention
param skuName = 'PerGB2018'

// Resource tags.
param tags = {}
