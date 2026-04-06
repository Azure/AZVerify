using 'main.bicep'

// Azure region — all resources deployed to Sweden Central.
param location = 'swedencentral'

param tags = {}

// Log Analytics workspace ID for Application Insights telemetry.
// This is the subscription-wide default workspace in DefaultResourceGroup-SEC.
// Verify it exists with: az monitor log-analytics workspace show --resource-group DefaultResourceGroup-SEC --workspace-name DefaultWorkspace-<SUBSCRIPTION_ID>-SEC
// If it doesn't exist, deploy it first: az deployment group create --resource-group DefaultResourceGroup-SEC --template-file dependencies/log-analytics.bicep --parameters @dependencies/log-analytics.bicepparam
param logAnalyticsWorkspaceId = '/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/DefaultResourceGroup-SEC/providers/Microsoft.OperationalInsights/workspaces/DefaultWorkspace-<SUBSCRIPTION_ID>-SEC'

// Notification email — receives task completion emails from the function app.
param notificationEmail = 'example@example.com'

// Azure AI Foundry / Azure OpenAI endpoint. External resource in another resource group.
// The Function App identity needs 'Cognitive Services OpenAI User' on this resource — see dependencies/README.md.
// API version: 2025-04-01-preview (as configured in Azure).
param azureAIFoundryEndpoint = 'https://<AI_ENDPOINT>/openai/responses?api-version=2025-04-01-preview'

// OpenAI model deployment name.
//   'gpt-5-mini'   → cost-optimized, current configuration
//   'gpt-4o'       → higher capability, higher cost
//   'gpt-4o-mini'  → balanced cost/capability
param openAIModel = 'gpt-5-mini'

// Enable Contoso-Notify premium features ('true'/'false').
param usePremiumFeatures = 'true'

// Sender email address for outgoing emails.
// Current value: AzureManagedDomain auto-generated address (active state).
// After custom domain verification: change to 'donotreply@<DOMAIN>'
param senderEmail = 'donotreply@<AZURE_MANAGED_DOMAIN>.azurecomm.net'
