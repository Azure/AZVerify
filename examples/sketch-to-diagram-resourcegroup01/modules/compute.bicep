@description('Azure region for all resources.')
param location string

@description('Name of the network interface.')
param nicName string

@description('Resource ID of the subnet for the NIC.')
param subnetId string

@description('Name of the virtual machine.')
param vmName string

@description('Size of the virtual machine.')
param vmSize string

@description('Admin username for the VM.')
param adminUsername string

@secure()
@description('Admin password for the VM.')
param adminPassword string

@description('OS image SKU for the VM.')
param vmImageSku string

@description('Name of the App Service Plan.')
param appServicePlanName string

@description('SKU name for the App Service Plan.')
param appServicePlanSkuName string

@description('Name of the Web App.')
param webAppName string

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: vmImageSku
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: appServicePlanSkuName
  }
  properties: {
    reserved: false
  }
}

resource webApp 'Microsoft.Web/sites@2024-04-01' = {
  name: webAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
    }
  }
}

output webAppId string = webApp.id
output webAppName string = webApp.name
output vmId string = vm.id
