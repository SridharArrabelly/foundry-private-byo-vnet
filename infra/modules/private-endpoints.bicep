// Private Endpoints + Private DNS Zones for BYO-VNet Foundry.
//
// Layout matches the Managed VNet flavor — same 6 DNS zones, same 4 PEs
// (Foundry, Search, Cosmos, Storage). The difference is that in BYO mode
// Foundry does NOT auto-create a second set of managed PEs from its own
// VNet; the customer PEs in your VNet are the only path agent traffic
// takes to your data resources.

@description('Azure region for deployment')
param location string

@description('Resource name prefix')
param prefix string

@description('Subnet ID for private endpoints')
param peSubnetId string

@description('VNet ID for DNS zone links')
param vnetId string

@description('AI Foundry resource ID')
param aiFoundryId string

@description('AI Search resource ID')
param searchId string

@description('Cosmos DB account resource ID')
param cosmosId string

@description('Storage account resource ID')
param storageId string

// --- Private DNS Zones ---

resource dnsZoneFoundry 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.cognitiveservices.azure.com'
  location: 'global'
}

resource dnsZoneOpenAI 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.openai.azure.com'
  location: 'global'
}

resource dnsZoneAIServices 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.services.ai.azure.com'
  location: 'global'
}

resource dnsZoneSearch 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.search.windows.net'
  location: 'global'
}

resource dnsZoneCosmos 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
}

resource dnsZoneBlob 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
}

// --- VNet Links ---

resource vnetLinkFoundry 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneFoundry
  name: 'link-${prefix}-foundry'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource vnetLinkOpenAI 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneOpenAI
  name: 'link-${prefix}-openai'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource vnetLinkAIServices 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneAIServices
  name: 'link-${prefix}-aiservices'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource vnetLinkSearch 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneSearch
  name: 'link-${prefix}-search'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource vnetLinkCosmos 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneCosmos
  name: 'link-${prefix}-cosmos'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource vnetLinkBlob 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneBlob
  name: 'link-${prefix}-blob'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

// --- Private Endpoints (serialized via dependsOn to avoid subnet PATCH races) ---

resource peFoundry 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'pep-${prefix}-foundry'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${prefix}-foundry'
        properties: {
          privateLinkServiceId: aiFoundryId
          groupIds: ['account']
        }
      }
    ]
  }
}

resource peSearch 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'pep-${prefix}-search'
  location: location
  dependsOn: [peFoundry]
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${prefix}-search'
        properties: {
          privateLinkServiceId: searchId
          groupIds: ['searchService']
        }
      }
    ]
  }
}

resource peCosmos 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'pep-${prefix}-cosmos'
  location: location
  dependsOn: [peSearch]
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${prefix}-cosmos'
        properties: {
          privateLinkServiceId: cosmosId
          groupIds: ['Sql']
        }
      }
    ]
  }
}

resource peStorageBlob 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'pep-${prefix}-blob'
  location: location
  dependsOn: [peCosmos]
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${prefix}-blob'
        properties: {
          privateLinkServiceId: storageId
          groupIds: ['blob']
        }
      }
    ]
  }
}

// --- DNS Zone Groups ---

resource dnsGroupFoundry 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: peFoundry
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config-foundry', properties: { privateDnsZoneId: dnsZoneFoundry.id } }
      { name: 'config-openai', properties: { privateDnsZoneId: dnsZoneOpenAI.id } }
      { name: 'config-aiservices', properties: { privateDnsZoneId: dnsZoneAIServices.id } }
    ]
  }
}

resource dnsGroupSearch 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: peSearch
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config-search', properties: { privateDnsZoneId: dnsZoneSearch.id } }
    ]
  }
}

resource dnsGroupCosmos 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: peCosmos
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config-cosmos', properties: { privateDnsZoneId: dnsZoneCosmos.id } }
    ]
  }
}

resource dnsGroupBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: peStorageBlob
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config-blob', properties: { privateDnsZoneId: dnsZoneBlob.id } }
    ]
  }
}
