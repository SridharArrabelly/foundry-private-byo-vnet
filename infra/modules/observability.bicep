// Observability for the Foundry Agent runtime:
//   - Log Analytics Workspace
//   - Application Insights (workspace-based)
//   - Azure Monitor Private Link Scope (AMPLS) with PrivateOnly ingestion/query
//   - Private Endpoint (groupId: azuremonitor) + private DNS zones
//
// Once the project's AppInsights connection is wired (see ai-foundry-project.bicep),
// the Foundry runtime publishes agent traces, dependencies, and exceptions to
// THIS App Insights resource. Your own apps and the jumpbox use the AMPLS PE
// for a fully-private ingestion + query path.
//
// AMPLS PE needs 5 private DNS zones:
//   1. privatelink.monitor.azure.com
//   2. privatelink.oms.opinsights.azure.com
//   3. privatelink.ods.opinsights.azure.com
//   4. privatelink.agentsvc.azure-automation.net
//   5. privatelink.blob.<storage-suffix>            (reused — created by the
//      private-endpoints module for the agent storage account)

@description('Azure region for deployment')
param location string

@description('Resource name prefix')
param prefix string

@description('Subnet ID for private endpoints')
param peSubnetId string

@description('VNet ID for DNS zone links')
param vnetId string

@description('Resource ID of the existing privatelink.blob.* DNS zone (created by private-endpoints.bicep)')
param dnsZoneBlobId string

// --- Log Analytics Workspace ---

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${prefix}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    // Lock down LAW ingestion + query to the AMPLS path.
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

// --- Application Insights (workspace-based) ---

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${prefix}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
    // Force ingestion + query through AMPLS PE.
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
    IngestionMode: 'LogAnalytics'
  }
}

// --- Azure Monitor Private Link Scope ---

resource ampls 'Microsoft.Insights/privateLinkScopes@2021-07-01-preview' = {
  name: 'ampls-${prefix}'
  location: 'global'
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

resource amplsScopedLaw 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: 'law-scope'
  properties: {
    linkedResourceId: law.id
  }
}

resource amplsScopedAi 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: 'appinsights-scope'
  properties: {
    linkedResourceId: appInsights.id
  }
}

// --- Private DNS Zones for Azure Monitor ---

resource dnsZoneMonitor 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.monitor.azure.com'
  location: 'global'
}

resource dnsZoneOms 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.oms.opinsights.azure.com'
  location: 'global'
}

resource dnsZoneOds 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.ods.opinsights.azure.com'
  location: 'global'
}

resource dnsZoneAgentSvc 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.agentsvc.azure-automation.net'
  location: 'global'
}

// --- VNet Links ---

resource vnetLinkMonitor 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneMonitor
  name: 'link-${prefix}-monitor'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource vnetLinkOms 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneOms
  name: 'link-${prefix}-oms'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource vnetLinkOds 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneOds
  name: 'link-${prefix}-ods'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource vnetLinkAgentSvc 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneAgentSvc
  name: 'link-${prefix}-agentsvc'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

// --- Private Endpoint for AMPLS ---
// Serialize after the storage PE chain in private-endpoints.bicep via the
// dnsZoneBlobId dependency (it's only populated after that module completes).

resource peAmpls 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'pep-${prefix}-ampls'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${prefix}-ampls'
        properties: {
          privateLinkServiceId: ampls.id
          groupIds: ['azuremonitor']
        }
      }
    ]
  }
  dependsOn: [
    amplsScopedLaw
    amplsScopedAi
  ]
}

resource dnsGroupAmpls 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: peAmpls
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'config-monitor',  properties: { privateDnsZoneId: dnsZoneMonitor.id } }
      { name: 'config-oms',      properties: { privateDnsZoneId: dnsZoneOms.id } }
      { name: 'config-ods',      properties: { privateDnsZoneId: dnsZoneOds.id } }
      { name: 'config-agentsvc', properties: { privateDnsZoneId: dnsZoneAgentSvc.id } }
      { name: 'config-blob',     properties: { privateDnsZoneId: dnsZoneBlobId } }
    ]
  }
}

output logAnalyticsWorkspaceId string = law.id
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output amplsId string = ampls.id
