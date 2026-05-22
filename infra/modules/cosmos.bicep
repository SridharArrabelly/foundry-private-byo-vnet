@description('Azure region for deployment')
param location string

@description('Resource name prefix')
param prefix string

// Cosmos DB for NoSQL (Document) — used by Foundry agent runtime for thread state.
// Some regions are canary-only for new Cosmos accounts; the Microsoft sample
// redirects those to westus. southafricanorth is not in that list.
var canaryRegions = ['eastus2euap', 'centraluseuap']
var cosmosLocation = contains(canaryRegions, location) ? 'westus' : location

var cosmosName = 'cosmos-${prefix}'

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' = {
  name: cosmosName
  location: cosmosLocation
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: cosmosLocation
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    disableLocalAuth: true
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    enableFreeTier: false
    publicNetworkAccess: 'Disabled'
  }
}

output cosmosId string = cosmos.id
output cosmosName string = cosmos.name
output cosmosDocumentEndpoint string = cosmos.properties.documentEndpoint
