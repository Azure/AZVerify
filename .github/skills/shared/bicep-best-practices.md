# Bicep Best Practices

Mandatory rules for all Bicep generation in AzVerify skills. Before generating any Bicep, call Azure Best Practices MCP (`azure-get_azure_bestpractices`, `get_azure_bestpractices_get`) for the latest guidance. Use Bicep Schema MCP (`azure-bicepschema`, `bicepschema_get`) when a resource schema or API version is uncertain.

---

## Rules

| # | Rule | Detail |
|---|------|--------|
| 1 | No `name` on module statements | Omit the `name` field on `module` blocks; Bicep generates it automatically |
| 2 | User-defined types over open types | Avoid `array`, unless it is an array of strings, or `object` params; define typed structures |
| 3 | `.bicepparam` files | Always generate `.bicepparam`, never JSON parameter files |
| 4 | `parent` property for child resources | Never build child names with `/`; use `parent:` with a symbolic ref |
| 5 | `existing` resource for parent lookups | If parent is not in the same file, add an `existing` resource block |
| 6 | Symbolic references | Use `foo.id` / `foo.properties.x`, not `resourceId()` or `reference()` |
| 7 | `@secure()` on sensitive params | Always decorate passwords, keys, connection strings |
| 8 | `@description()` on params and types | Describe every parameter; describe type properties where context is unclear |
| 9 | Resource-derived types | Prefer `resourceInput<>` / `resourceOutput<>` over hand-written types |
| 10 | Minimal comments | Only add comments beyond what `@description()` says. No `// ====` banners. Do use comments for complicated operations or ternaries |
| 11 | Safe-dereference | Use `.?` and `??` for null handling, not ternaries or `!.` |

## Template Structure

Applies to every skill that generates a `main.bicep` + `modules/` + `.bicepparam` set.

| Area | Rule |
|------|------|
| `main.bicep` | `targetScope = 'resourceGroup'`; declare every param with `@description()`; `@allowed()` where a fixed value set applies; `@secure()` for sensitive params; one module ref per category (do not set the `name:` property inside module blocks — the symbolic name before `=` is still required); outputs for key resource IDs and endpoints |
| Module files | Only generate modules that have resources; pass each module only the params it needs; `parent:` for child resources; `existing` blocks for cross-file parent refs; symbolic refs (`foo.id`) |
| Module categories | `networking`, `compute`, `data`, `identity`, `monitoring`. A resource that fits none of these goes in `modules/other.bicep`, and its resource type is listed in the generated README under "Manually Reviewed Resources" |
| `.bicepparam` | `using 'main.bicep'`; include **all** param values; comment block per param (see below); `readEnvironmentVariable('PARAM_NAME')` for secrets, never hardcoded |
| Param naming | camelCase and descriptive (e.g., `vmSize`, `appServicePlanSkuName`, `vnetAddressPrefix`) |
| Secure defaults | `httpsOnly: true`, `minimumTlsVersion: '1.2'`, `publicNetworkAccess: 'Disabled'` where private endpoints exist |
| Version currency | Verify runtime stacks, API versions, and OS images are current before use — never copy defaults from reference files unchecked |

## Bicepparam Comment Guidelines

Keep comments to 1-3 lines per parameter. Cover:
- What the setting controls (plain language)
- 2-3 common alternatives with cost/capacity impact
- Security consequences where applicable

```bicep
// VM size — CPU, memory, cost.
//   Standard_B2s → 2 vCPU, 4 GB (~$30/mo) — dev/test
//   Standard_D4s_v5 → 4 vCPU, 16 GB (~$140/mo) — production
param vmSize = 'Standard_B2s'
```

## API Version Rule

Use the latest **stable** (non-preview) API version for each resource type. Call Bicep Schema MCP (`azure-bicepschema`, `bicepschema_get`) to verify when uncertain.

## Bicepparam File Pattern

The `.bicepparam` file must include ALL parameter values with descriptive comments. Use `readEnvironmentVariable()` for secrets — never hardcode them.

```bicep
using 'main.bicep'

// Azure region. Options: eastus, westeurope, westus2
param location = 'eastus'

// VM size — cost, CPU, memory.
//   Standard_B2s    → 2 vCPU, 4 GB  (~$30/mo) — dev/test
//   Standard_D2s_v3 → 2 vCPU, 8 GB  (~$70/mo) — general
param vmSize = 'Standard_B2s'

// SQL admin password — reads from env var at deploy time.
param sqlAdminPassword = readEnvironmentVariable('SQLPASSWORD')
```

## Private Endpoint groupIds by Target

| Target Resource | groupIds |
|---|---|
| App Service | `['sites']` |
| Storage (Blob) | `['blob']` |
| Storage (File) | `['file']` |
| SQL Server | `['sqlServer']` |
| Cosmos DB | `['Sql']` |
| Key Vault | `['vault']` |
| Redis | `['redisCache']` |
