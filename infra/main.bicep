targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the azd environment. Used to tag the resource group and (by default) as the resource name prefix.')
param environmentName string

@minLength(1)
@description('Azure region for all resources')
param location string

@description('Resource name prefix (lowercase, no special chars). Defaults to environmentName.')
param prefix string = toLower(replace(environmentName, '-', ''))

@description('Your public IP to allow portal/API access (leave empty for fully private)')
param allowedIpAddress string = ''

@description('Deploy AMPLS + Log Analytics + Application Insights + monitor private endpoint and DNS zones. Set false if you already have a central observability stack you intend to reuse, or for a faster minimal deployment.')
param deployObservability bool = true

@description('Deploy the Windows jumpbox VM + Azure Bastion + NAT Gateway. Set false for a faster minimal deployment when you plan to access Foundry from your dev box via allowedIpAddress.')
param deployJumpbox bool = true

@description('Admin username for the jumpbox VM (ignored when deployJumpbox is false)')
param vmAdminUsername string = 'azureadmin'

@secure()
@description('Admin password for the jumpbox VM (12+ chars, upper/lower/number/special). Required when deployJumpbox is true; ignored otherwise.')
param vmAdminPassword string = ''

var tags = {
  'azd-env-name': environmentName
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module resources 'resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    location: location
    prefix: prefix
    allowedIpAddress: allowedIpAddress
    deployObservability: deployObservability
    deployJumpbox: deployJumpbox
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AI_FOUNDRY_NAME string = resources.outputs.aiFoundryName
output AI_FOUNDRY_PROJECT_NAME string = resources.outputs.aiFoundryProjectName
output AI_FOUNDRY_ENDPOINT string = resources.outputs.aiFoundryEndpoint
output AI_SEARCH_NAME string = resources.outputs.aiSearchName
output AI_SEARCH_ENDPOINT string = resources.outputs.aiSearchEndpoint
output JUMPBOX_VM_NAME string = resources.outputs.jumpboxVmName
output BASTION_NAME string = resources.outputs.bastionName
output VNET_ID string = resources.outputs.vnetId
output AGENT_SUBNET_ID string = resources.outputs.agentSubnetId
output APPLICATIONINSIGHTS_NAME string = resources.outputs.appInsightsName
output APPLICATIONINSIGHTS_ID string = resources.outputs.appInsightsId
output LOG_ANALYTICS_WORKSPACE_ID string = resources.outputs.logAnalyticsWorkspaceId
output AZURE_MONITOR_PRIVATE_LINK_SCOPE_ID string = resources.outputs.amplsId
