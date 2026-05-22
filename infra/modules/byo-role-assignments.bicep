// BYO (Cosmos + Storage + Search) role chain for the Foundry project MI.
//
// Split into two passes around capabilityHost creation per Microsoft sample 18:
//
//   PRE-CAPHOST  — must exist before the capabilityHost is provisioned
//     • Storage Blob Data Contributor   (project MI → Storage)
//     • Cosmos DB Operator              (project MI → Cosmos)
//     • Search Index Data Contributor   (project MI → Search)
//     • Search Service Contributor      (project MI → Search)
//
//   POST-CAPHOST — applied after capabilityHost so the runtime-created
//                  agent containers exist before the conditioned role grant
//     • Storage Blob Data Owner with condition on workspace-scoped containers
//     • Cosmos Built-In Data Contributor (SQL role on Cosmos)
//
// The post-caphost grants are deployed via a separate module
// (post-caphost-role-assignments.bicep) so resources.bicep can sequence them
// after the capabilityHost module.

@description('Principal ID of the Foundry project system-assigned managed identity')
param projectPrincipalId string

@description('Name of the Cosmos DB account')
param cosmosName string

@description('Name of the Storage account')
param storageName string

@description('Name of the AI Search service')
param searchName string

// --- Existing resources to scope roles ---

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosName
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource search 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: searchName
}

// --- Role definition IDs (built-in) ---

var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var cosmosDbOperatorRoleId = '230815da-be43-4aae-9cb4-875f7bd000aa'
var searchIndexDataContributorRoleId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var searchServiceContributorRoleId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'

// --- Pre-caphost: project MI on Storage ---

resource storageBlobDataContributorProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(projectPrincipalId, storageBlobDataContributorRoleId, storage.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// --- Pre-caphost: project MI on Cosmos ---

resource cosmosDbOperatorProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cosmos
  name: guid(projectPrincipalId, cosmosDbOperatorRoleId, cosmos.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cosmosDbOperatorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// --- Pre-caphost: project MI on Search ---

resource searchIndexDataContributorProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(projectPrincipalId, searchIndexDataContributorRoleId, search.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributorProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(projectPrincipalId, searchServiceContributorRoleId, search.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}
