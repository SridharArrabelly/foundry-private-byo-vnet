@description('Azure region for deployment')
param location string

@description('Resource name prefix')
param prefix string

@description('Subnet ID for the VM')
param vmSubnetId string

@description('Subnet ID for Azure Bastion')
param bastionSubnetId string

@description('Admin username for the VM')
param adminUsername string

@secure()
@description('Admin password for the VM')
param adminPassword string

// --- Public IP for Bastion ---

resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: 'pip-${prefix}-bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// --- Azure Bastion ---

resource bastion 'Microsoft.Network/bastionHosts@2024-07-01' = {
  name: 'bas-${prefix}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
}

// --- Network Interface for VM ---

resource vmNic 'Microsoft.Network/networkInterfaces@2024-07-01' = {
  name: 'nic-${prefix}-vm'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vmSubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// --- Windows VM ---

// Windows computer name must be <= 15 chars. Truncate 'vm<prefix>' if needed.
var rawComputerName = 'vm${prefix}'
var computerName = length(rawComputerName) > 15 ? substring(rawComputerName, 0, 15) : rawComputerName

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-${prefix}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2ms'
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-24h2-pro'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: vmNic.id
        }
      ]
    }
  }
}

output vmName string = vm.name
output vmPrincipalId string = vm.identity.principalId
output bastionName string = bastion.name
