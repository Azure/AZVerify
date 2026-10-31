param location string = 'westeurope'
param candidate string = 'Prod'
param labels array = ['Prod']
param settings object = {
  Prod: 'Enabled'
}

resource equalsWrongCase 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (candidate == 'prod') {
  name: 'equals-wrong-case'
  location: location
}

resource equalsExactCase 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (candidate == 'Prod') {
  name: 'equals-exact-case'
  location: location
}

resource stringWrongCase 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (contains(candidate, 'prod')) {
  name: 'string-wrong-case'
  location: location
}

resource stringExactCase 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (contains(candidate, 'Pro')) {
  name: 'string-exact-case'
  location: location
}

resource arrayWrongCase 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (contains(labels, 'prod')) {
  name: 'array-wrong-case'
  location: location
}

resource arrayExactCase 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (contains(labels, 'Prod')) {
  name: 'array-exact-case'
  location: location
}

resource objectKeyIgnoreCase 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (contains(settings, 'prod')) {
  name: 'object-key-ignore-case'
  location: location
}

resource objectValueWrongCase 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (settings.Prod == 'enabled') {
  name: 'object-value-wrong-case'
  location: location
}
