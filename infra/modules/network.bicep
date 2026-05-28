// Virtual Network for BYO-VNet Foundry Agent Service.
//
// Subnet layout (in 10.0.0.0/16):
//   snet-<prefix>-pe       10.0.1.0/24   Private endpoints for Foundry + BYO data resources
//   snet-<prefix>-vm       10.0.2.0/24   Jumpbox + NAT Gateway egress
//   AzureBastionSubnet     10.0.3.0/26   Bastion (fixed name required)
//   snet-<prefix>-agent    10.0.4.0/24   DELEGATED to Microsoft.App/environments —
//                                         Foundry agent compute (Data Proxy + Hosted/Prompt
//                                         agent Micro VMs) lives here. /24 recommended for
//                                         production; /26 minimum for ~50 concurrent
//                                         sessions per the networking deep-dive.

@description('Azure region for deployment')
param location string

@description('Resource name prefix')
param prefix string

@description('Deploy NAT Gateway on the VM subnet. Only needed when a jumpbox lives in the subnet and needs outbound internet (pip install, GitHub).')
param deployNatGateway bool = true

var vnetName = 'vnet-${prefix}'
var peSubnetName = 'snet-${prefix}-pe'
var vmSubnetName = 'snet-${prefix}-vm'
var agentSubnetName = 'snet-${prefix}-agent'

// --- NAT Gateway for the VM subnet (default-outbound retirement workaround) ---

resource natPip 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (deployNatGateway) {
  name: 'pip-${prefix}-natgw'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2024-07-01' = if (deployNatGateway) {
  name: 'natgw-${prefix}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 10
    publicIPAddresses: [
      {
        id: natPip.id
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: peSubnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: vmSubnetName
        properties: {
          addressPrefix: '10.0.2.0/24'
          natGateway: deployNatGateway ? {
            id: natGateway.id
          } : null
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.3.0/26'
        }
      }
      {
        // Agent subnet — DELEGATED to Microsoft.App/environments. This is the
        // defining characteristic of the BYO-VNet model. The platform deploys
        // the single-tenant Data Proxy and any Hosted/Prompt agent Micro VMs
        // here. IPs consumed at ~1 per 10 pods + 1 per Hosted-agent revision.
        // Size /24 to absorb upgrade rollouts and scale events; do not plan
        // to exceed ~80% utilization.
        name: agentSubnetName
        properties: {
          addressPrefix: '10.0.4.0/24'
          delegations: [
            {
              name: 'Microsoft.App/environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output peSubnetId string = vnet.properties.subnets[0].id
output vmSubnetId string = vnet.properties.subnets[1].id
output bastionSubnetId string = vnet.properties.subnets[2].id
output agentSubnetId string = vnet.properties.subnets[3].id
output agentSubnetName string = agentSubnetName
