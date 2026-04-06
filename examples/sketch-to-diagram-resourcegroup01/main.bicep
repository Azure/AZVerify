targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = 'eastus'

// --- Networking parameters ---

@description('Name of the virtual network.')
param vnetName string = 'VNET-01'

@description('Address prefixes for the virtual network.')
param vnetAddressPrefixes string[] = ['10.0.0.0/16']

@description('Name of the first subnet (VM workload).')
param subnet01Name string = 'Subnet-01'

@description('Address prefix for the first subnet.')
param subnet01AddressPrefix string = '10.0.1.0/24'

@description('Name of the second subnet (private endpoints).')
param subnet02Name string = 'Subnet-02'

@description('Address prefix for the second subnet.')
param subnet02AddressPrefix string = '10.0.2.0/24'

// --- Compute parameters ---

@description('Name of the network interface for the VM.')
param nicName string = 'NIC-01'

@description('Name of the virtual machine.')
param vmName string = 'VM01'

@description('Size of the virtual machine.')
param vmSize string = 'Standard_B2s'

@description('Admin username for the VM.')
param adminUsername string

@secure()
@description('Admin password for the VM.')
param adminPassword string

@description('OS image SKU for the VM.')
param vmImageSku string = '2022-datacenter-azure-edition'

@description('Name of the App Service Plan.')
param appServicePlanName string = 'App-Service-Plan'

@description('SKU name for the App Service Plan.')
param appServicePlanSkuName string = 'S1'

@description('Globally unique name for the Web App.')
param webAppName string

// --- Private Link parameters ---

@description('Name of the private endpoint for the Web App.')
param privateEndpointName string = 'pe-webapp'

// --- Modules ---

module networking 'modules/networking.bicep' = {
  params: {
    location: location
    vnetName: vnetName
    vnetAddressPrefixes: vnetAddressPrefixes
    subnet01Name: subnet01Name
    subnet01AddressPrefix: subnet01AddressPrefix
    subnet02Name: subnet02Name
    subnet02AddressPrefix: subnet02AddressPrefix
  }
}

module compute 'modules/compute.bicep' = {
  params: {
    location: location
    nicName: nicName
    subnetId: networking.outputs.subnet01Id
    vmName: vmName
    vmSize: vmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmImageSku: vmImageSku
    appServicePlanName: appServicePlanName
    appServicePlanSkuName: appServicePlanSkuName
    webAppName: webAppName
  }
}

// --- Private Endpoint and DNS (depends on both networking and compute) ---

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: networking.outputs.subnet02Id
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-connection'
        properties: {
          privateLinkServiceId: compute.outputs.webAppId
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: networking.outputs.vnetId
    }
    registrationEnabled: false
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurewebsites-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// --- Outputs ---

output webAppUrl string = 'https://${compute.outputs.webAppName}.azurewebsites.net'
output vmId string = compute.outputs.vmId
output vnetId string = networking.outputs.vnetId
