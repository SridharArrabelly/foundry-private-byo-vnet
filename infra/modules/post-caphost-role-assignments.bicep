// Roles that MUST be applied after the project's capabilityHost is created.
// Per Microsoft sample 18, these scope to runtime-created resources whose
// names depend on the project's workspaceId.

@description('Principal ID of the Foundry project system-assigned managed identity')
param projectPrincipalId string

@description('Name of the Storage account')
param storageName string

@description('Name of the Cosmos DB account')
param cosmosName string

@description('Project workspaceId in formatted GUID form (8-4-4-4-12)')
param projectWorkspaceIdGuid string

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosName
}

// Storage Blob Data Owner: b7e6dc6d-f1e8-4753-8033-0f276bb0955b
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'

// ABAC condition limits owner-level access to the workspace-prefixed
// *-azureml-agent containers that the agent runtime creates after caphost.
var ownerCondition = '((!(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read\'})  AND  !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action\'}) AND  !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write\'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase \'${projectWorkspaceIdGuid}\' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase \'*-azureml-agent\'))'

resource storageBlobDataOwnerProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(projectPrincipalId, storageBlobDataOwnerRoleId, storage.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalType: 'ServicePrincipal'
    conditionVersion: '2.0'
    condition: ownerCondition
  }
}

// Cosmos SQL "Built-In Data Contributor" role at the account scope.
// Role ID 00000000-0000-0000-0000-000000000002 is the SQL Data Contributor.
var cosmosSqlRoleDefId = resourceId(
  'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions',
  cosmosName,
  '00000000-0000-0000-0000-000000000002'
)

var accountScope = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.DocumentDB/databaseAccounts/${cosmosName}'

resource cosmosSqlDataContributorProject 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-12-01-preview' = {
  parent: cosmos
  name: guid(projectWorkspaceIdGuid, cosmosName, cosmosSqlRoleDefId, projectPrincipalId)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cosmosSqlRoleDefId
    scope: accountScope
  }
}
