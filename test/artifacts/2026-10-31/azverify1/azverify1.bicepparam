using 'main.bicep'

// Azure region. This matches the existing resource group location.
param location = 'swedencentral'

// Storage account names are globally unique, lowercase, and 3-24 characters.
param storageAccountName = 'azvtest9bd9cf0b'

// Standard_LRS is the least expensive redundancy option; GRS and ZRS add resiliency and cost.
param storageSkuName = 'Standard_LRS'

// StorageV2 supports current Azure Storage features.
param storageKind = 'StorageV2'

// Hot is suitable for frequently accessed data; Cool trades lower storage cost for higher access cost.
param storageAccessTier = 'Hot'

// TLS 1.2 is enforced; the template intentionally does not allow weaker values.
param storageMinimumTlsVersion = 'TLS1_2'

// Anonymous blob access stays disabled to reduce accidental data exposure.
param storageAllowBlobPublicAccess = false

// Public network access stays disabled for this isolated functional-test fixture.
param storagePublicNetworkAccess = 'Disabled'

// HTTPS-only access is required.
param storageSupportsHttpsTrafficOnly = true
