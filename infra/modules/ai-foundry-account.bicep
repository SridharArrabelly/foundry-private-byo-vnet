// Foundry account configured for BYO-VNet (delegated subnet) injection.
//
// Key difference from the Managed VNet flavor:
//   * networkInjections.useMicrosoftManagedNetwork = false
//   * networkInjections.subnetArmId points at the delegated agent subnet in
//     the customer VNet (delegated to Microsoft.App/environments)
//   * No `managednetworks` child resource (that's Managed VNet only)
//   * No 'Azure AI Enterprise Network Connection Approver' role assignment
//     (no managed PEs to auto-approve — all PEs in BYO model are customer-owned)
//
// The project, model deployments, and project connections live in
// ai-foundry-project.bicep so PE+DNS can be created in between (project +
// capabilityHost provisioning still needs the BYO data resources reachable
// over private endpoints from within the agent subnet's VNet).

@description('Azure region for deployment')
param location string

@description('Resource name prefix')
param prefix string

@description('Your public IP address to allow portal/API access (leave empty to block all public access)')
param allowedIpAddress string = ''

@description('ARM ID of the delegated agent subnet (delegated to Microsoft.App/environments)')
param agentSubnetId string

var accountName = 'ais-${prefix}'

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' = {
  name: accountName
  location: location
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: empty(allowedIpAddress) ? 'Disabled' : 'Enabled'
    allowProjectManagement: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: empty(allowedIpAddress) ? [] : [
        {
          value: allowedIpAddress
        }
      ]
    }
    // BYO-VNet injection: agent compute (Data Proxy, Hosted/Prompt Micro VMs)
    // is deployed by the platform into THIS subnet in your VNet. Outbound
    // calls from agents to your BYO Cosmos/Storage/Search traverse private
    // endpoints in the same VNet.
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
        useMicrosoftManagedNetwork: false
      }
    ]
  }
}

output aiFoundryId string = aiFoundry.id
output aiFoundryName string = aiFoundry.name
output aiFoundryEndpoint string = 'https://${accountName}.cognitiveservices.azure.com'
output aiFoundryPrincipalId string = aiFoundry.identity.principalId
