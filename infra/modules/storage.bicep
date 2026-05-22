@description('Azure region for deployment')
param location string

@description('Resource name prefix (lowercase, no hyphens — storage account names allow only lowercase alphanumeric)')
param prefix string

// Storage account names: 3-24 chars, lowercase alphanumeric only (no hyphens).
// `st` + prefix should fit for any reasonable prefix.
var storageName = take(toLower('st${replace(prefix, '-', '')}'), 24)

// Some regions don't support ZRS; per sample 18 use GRS in those.
var noZRSRegions = ['southindia', 'westus']
var sku = contains(noZRSRegions, location) ? { name: 'Standard_GRS' } : { name: 'Standard_ZRS' }

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: sku
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: []
    }
    // Agent uses Entra ID (project MI) auth — no shared keys.
    allowSharedKeyAccess: false
  }
}

output storageId string = storage.id
output storageName string = storage.name
output storageBlobEndpoint string = storage.properties.primaryEndpoints.blob
