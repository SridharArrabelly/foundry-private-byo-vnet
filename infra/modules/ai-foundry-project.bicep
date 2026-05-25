// Foundry project + model deployments + BYO project connections.
// Run AFTER ai-foundry-account.bicep and AFTER private-endpoints.bicep.

@description('Azure region for deployment')
param location string

@description('Resource name prefix')
param prefix string

@description('Name of the existing Foundry account')
param accountName string

@description('Name of the AI Search service')
param searchName string

@description('Resource ID of the AI Search service')
param searchId string

@description('Location of the AI Search service')
param searchLocation string

@description('Name of the Cosmos DB account')
param cosmosName string

@description('Resource ID of the Cosmos DB account')
param cosmosId string

@description('Location of the Cosmos DB account')
param cosmosLocation string

@description('Document endpoint of the Cosmos DB account')
param cosmosDocumentEndpoint string

@description('Name of the Storage account')
param storageName string

@description('Resource ID of the Storage account')
param storageId string

@description('Location of the Storage account')
param storageLocation string

@description('Blob endpoint of the Storage account')
param storageBlobEndpoint string

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' existing = {
  name: accountName
}

// --- Model Deployments ---
// Serialize to avoid IfMatchPreconditionFailed races on the parent account.

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: aiFoundry
  name: 'text-embedding-3-large'
  sku: {
    name: 'GlobalStandard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
  }
}

// Foundry File Search tool defaults to text-embedding-ada-002 when no model
// is specified on the vector store. Deploy it so file uploads work out of
// the box; otherwise agents fail at query time with a generic 500.
resource adaEmbeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: aiFoundry
  name: 'text-embedding-ada-002'
  sku: {
    name: 'GlobalStandard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-ada-002'
      version: '2'
    }
  }
  dependsOn: [embeddingDeployment]
}

resource gpt4MiniDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: aiFoundry
  name: 'gpt-4.1-mini'
  sku: {
    name: 'GlobalStandard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4.1-mini'
      version: '2025-04-14'
    }
  }
  dependsOn: [adaEmbeddingDeployment]
}

// --- Project ---

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' = {
  parent: aiFoundry
  name: '${prefix}-project'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
  dependsOn: [
    embeddingDeployment
    adaEmbeddingDeployment
    gpt4MiniDeployment
  ]
}

// --- BYO project connections for Foundry Agent ("Standard Agent") ---
// All three are required for the project capabilityHost to bind. authType is
// 'AAD' per Microsoft sample 18 — the capabilityHost is what maps these AAD
// connections to the project MI at agent runtime. Without the capabilityHost,
// AAD = user passthrough and the agent fails with
// "Invalid endpoint or connection failed".

resource projectCosmosConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-10-01-preview' = {
  parent: foundryProject
  name: cosmosName
  properties: {
    category: 'CosmosDB'
    target: cosmosDocumentEndpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosId
      location: cosmosLocation
    }
  }
}

resource projectStorageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-10-01-preview' = {
  parent: foundryProject
  name: storageName
  properties: {
    category: 'AzureStorageAccount'
    target: storageBlobEndpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageId
      location: storageLocation
    }
  }
  dependsOn: [projectCosmosConnection]
}

resource projectSearchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-10-01-preview' = {
  parent: foundryProject
  name: searchName
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${searchName}.search.windows.net'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchId
      location: searchLocation
    }
  }
  dependsOn: [projectStorageConnection]
}

output projectName string = foundryProject.name
output projectPrincipalId string = foundryProject.identity.principalId
#disable-next-line BCP053
output projectWorkspaceId string = foundryProject.properties.internalId
output cosmosConnectionName string = projectCosmosConnection.name
output storageConnectionName string = projectStorageConnection.name
output searchConnectionName string = projectSearchConnection.name
