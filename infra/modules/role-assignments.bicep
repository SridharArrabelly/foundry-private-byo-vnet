// Role assignments for the BYO-VNet flavor.
//
// Compared to the Managed VNet flavor, this is SIMPLER because:
//   * No 'Azure AI Enterprise Network Connection Approver' role needed
//     (Foundry doesn't auto-create managed PEs in BYO mode — the customer
//     PEs in your VNet are the only path)
//
// What stays the same:
//   * Account MI -> Search (Index + Service Contributor) for AI Search tool
//   * Jumpbox MI -> Search (Index + Service Contributor) for the indexer
//   * Jumpbox MI -> Foundry (OpenAI User) for embedding calls
//
// Project-MI -> data-resource RBAC is in byo-role-assignments.bicep (pre-caphost)
// and post-caphost-role-assignments.bicep (after capabilityHost provisions).

@description('Principal ID of the AI Foundry system-assigned managed identity')
param aiFoundryPrincipalId string

@description('Resource ID of the AI Search service')
param searchId string

@description('Resource ID of the AI Foundry (Cognitive Services) account')
param aiFoundryId string

@description('Principal ID of the jumpbox VM system-assigned managed identity. Pass empty string when no jumpbox is deployed; in that case the jumpbox role assignments are skipped.')
param jumpboxPrincipalId string

var searchIndexDataContributorRoleId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var searchServiceContributorRoleId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
var cognitiveServicesOpenAIUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource searchResource 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: last(split(searchId, '/'))
}

resource aiFoundryResource 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: last(split(aiFoundryId, '/'))
}

// --- AI Foundry account MI -> Search ---

resource searchIndexDataContributorFoundry 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchId, aiFoundryPrincipalId, searchIndexDataContributorRoleId)
  scope: searchResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleId)
    principalId: aiFoundryPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributorFoundry 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchId, aiFoundryPrincipalId, searchServiceContributorRoleId)
  scope: searchResource
  dependsOn: [
    searchIndexDataContributorFoundry
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalId: aiFoundryPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// --- Jumpbox VM MI -> Search (so it can create the index and upload docs) ---

resource searchIndexDataContributorVm 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(jumpboxPrincipalId)) {
  name: guid(searchId, jumpboxPrincipalId, searchIndexDataContributorRoleId)
  scope: searchResource
  dependsOn: [
    searchServiceContributorFoundry
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleId)
    principalId: jumpboxPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributorVm 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(jumpboxPrincipalId)) {
  name: guid(searchId, jumpboxPrincipalId, searchServiceContributorRoleId)
  scope: searchResource
  dependsOn: [
    searchIndexDataContributorVm
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalId: jumpboxPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// --- Jumpbox VM MI -> AI Foundry (so it can call embeddings) ---

resource cognitiveOpenAIUserVm 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(jumpboxPrincipalId)) {
  name: guid(aiFoundryId, jumpboxPrincipalId, cognitiveServicesOpenAIUserRoleId)
  scope: aiFoundryResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRoleId)
    principalId: jumpboxPrincipalId
    principalType: 'ServicePrincipal'
  }
}
