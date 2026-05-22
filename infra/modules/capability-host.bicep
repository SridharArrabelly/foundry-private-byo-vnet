// Project capability host (Foundry "Standard Agent" runtime configuration).
//
// This is the resource that wires the project's BYO connections into the
// Foundry-managed agent runtime. Without it, the agent runtime cannot use
// the connections for thread state, file storage, or vector store — which
// is why a project with just a CognitiveSearch connection fails with
// "Invalid endpoint or connection failed" when the AI Search tool is invoked.
//
// All three connection arrays are required by the API. The connection names
// passed in must already exist on the project.

@description('Name of the Foundry account')
param accountName string

@description('Name of the project (child of the account)')
param projectName string

@description('Name of the project Cosmos DB connection (threads)')
param cosmosDBConnection string

@description('Name of the project Storage connection (files)')
param azureStorageConnection string

@description('Name of the project AI Search connection (vector store)')
param aiSearchConnection string

@description('Name for the capability host (per-project)')
param projectCapHost string = 'caphostproj'

resource account 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' existing = {
  parent: account
  name: projectName
}

#disable-next-line BCP081
resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-10-01-preview' = {
  parent: project
  name: projectCapHost
  properties: {
    capabilityHostKind: 'Agents'
    threadStorageConnections: [cosmosDBConnection]
    storageConnections: [azureStorageConnection]
    vectorStoreConnections: [aiSearchConnection]
  }
}

output capabilityHostName string = projectCapabilityHost.name
