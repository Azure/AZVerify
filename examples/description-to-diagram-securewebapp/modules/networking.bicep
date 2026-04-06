@description('Azure region for all networking resources')
param location string

@description('Name of the virtual network')
param vnetName string

@description('Address prefixes for the VNet')
param vnetAddressPrefixes string[]

@description('Name of the Application Gateway subnet')
param snetAppGwName string

@description('Address prefix for the Application Gateway subnet')
param snetAppGwAddressPrefix string

@description('Name of the VNet integration subnet')
param snetIntegrationName string

@description('Address prefix for the VNet integration subnet')
param snetIntegrationAddressPrefix string

@description('Name of the private link subnet')
param snetPrivateLinkName string

@description('Address prefix for the private link subnet')
param snetPrivateLinkAddressPrefix string

@description('Name of the public IP address for Application Gateway')
param publicIpName string

@description('Domain name for the public DNS zone')
param dnsZoneName string

@description('Name of the Application Gateway')
param appGwName string

@description('SKU tier of the Application Gateway')
@allowed([
  'Standard_v2'
  'WAF_v2'
])
param appGwSkuTier string

@description('Capacity (instance count) of the Application Gateway')
@minValue(1)
@maxValue(125)
param appGwCapacity int

@description('Name of the WAF policy')
param wafPolicyName string

@description('WAF mode — Detection logs threats, Prevention blocks them')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string

@description('FQDN of the backend App Service')
param appServiceFqdn string

// WAF Policy — required for WAF_v2 Application Gateway
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-05-01' = {
  name: wafPolicyName
  location: location
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: wafMode
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
  }
}

// Public DNS Zone
resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: dnsZoneName
  location: 'global'
  properties: {
    zoneType: 'Public'
  }
}

// Public IP — Standard SKU with Static allocation required for App Gateway v2
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: vnetAddressPrefixes
    }
  }
}

// Subnets deployed sequentially to avoid concurrent update conflicts
resource snetAppGw 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: snetAppGwName
  properties: {
    addressPrefix: snetAppGwAddressPrefix
  }
}

resource snetIntegration 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: snetIntegrationName
  properties: {
    addressPrefix: snetIntegrationAddressPrefix
    delegations: [
      {
        name: 'Microsoft.Web-serverFarms'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
  dependsOn: [snetAppGw]
}

resource snetPrivateLink 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: snetPrivateLinkName
  properties: {
    addressPrefix: snetPrivateLinkAddressPrefix
  }
  dependsOn: [snetIntegration]
}

// Application Gateway with WAF_v2
var appGwResourceId = resourceId('Microsoft.Network/applicationGateways', appGwName)

resource appGw 'Microsoft.Network/applicationGateways@2024-05-01' = {
  name: appGwName
  location: location
  properties: {
    sku: {
      name: appGwSkuTier
      tier: appGwSkuTier
      capacity: appGwCapacity
    }
    firewallPolicy: {
      id: wafPolicy.id
    }
    gatewayIPConfigurations: [
      {
        name: 'appGwIpConfig'
        properties: {
          subnet: {
            id: snetAppGw.id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwFrontendIp'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'appServiceBackendPool'
        properties: {
          backendAddresses: [
            {
              fqdn: appServiceFqdn
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'appServiceHttpSettings'
        properties: {
          port: 443
          protocol: 'Https'
          pickHostNameFromBackendAddress: true
          requestTimeout: 30
        }
      }
    ]
    httpListeners: [
      {
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: {
            id: '${appGwResourceId}/frontendIPConfigurations/appGwFrontendIp'
          }
          frontendPort: {
            id: '${appGwResourceId}/frontendPorts/port_80'
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'routingRule'
        properties: {
          priority: 100
          ruleType: 'Basic'
          httpListener: {
            id: '${appGwResourceId}/httpListeners/httpListener'
          }
          backendAddressPool: {
            id: '${appGwResourceId}/backendAddressPools/appServiceBackendPool'
          }
          backendHttpSettings: {
            id: '${appGwResourceId}/backendHttpSettingsCollection/appServiceHttpSettings'
          }
        }
      }
    ]
  }
}

// DNS A record pointing to App Gateway public IP
resource dnsARecord 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: dnsZone
  name: '@'
  properties: {
    TTL: 3600
    targetResource: {
      id: publicIp.id
    }
  }
}

@description('Resource ID of the Application Gateway subnet')
output snetAppGwId string = snetAppGw.id

@description('Resource ID of the VNet integration subnet')
output snetIntegrationId string = snetIntegration.id

@description('Resource ID of the private link subnet')
output snetPrivateLinkId string = snetPrivateLink.id

@description('Resource ID of the virtual network')
output vnetId string = vnet.id
