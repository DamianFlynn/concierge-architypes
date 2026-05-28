targetScope = 'subscription'

@description('Environment prefix (e.g. t, d, p)')
param environment string

@description('Spoke/service name without environment prefix')
param serviceName string

@description('Azure region for all resources')
param location string = 'westeurope'

@description('VNet address prefix')
param vnetAddressPrefix string = '10.0.0.0/25'

@description('PeFrontendSubnet address prefix')
param peFrontendSubnetPrefix string = '10.0.0.0/27'

@description('ScalableSubnet address prefix')
param scalableSubnetPrefix string = '10.0.0.32/27'

var spokeName = '${environment}-${serviceName}'
var networkRgName = '${spokeName}-network'

resource networkRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: networkRgName
  location: location
  tags: {
    Environment: environment
    Service: serviceName
    ManagedBy: 'Innofactor'
  }
}

module nsg 'br/public:network/network-security-group:1.0.0' = {
  name: 'PeFrontendSubnet-nsg'
  scope: resourceGroup(networkRgName)
  dependsOn: [networkRg]
  params: {
    name: '${spokeName}-network-PeFrontendSubnet-nsg'
    location: location
    securityRules: []
  }
}

module vnet 'br/public:network/virtual-network:1.1.3' = {
  name: 'vnet'
  scope: resourceGroup(networkRgName)
  dependsOn: [nsg]
  params: {
    name: '${spokeName}-network-vnet'
    location: location
    addressPrefixes: [vnetAddressPrefix]
    dnsServers: []
    subnets: [
      {
        name: 'PeFrontendSubnet'
        addressPrefix: peFrontendSubnetPrefix
        networkSecurityGroupResourceId: nsg.outputs.resourceId
        privateEndpointNetworkPolicies: 'Disabled'
      }
      {
        name: 'ScalableSubnet'
        addressPrefix: scalableSubnetPrefix
        delegations: [
          {
            name: 'Microsoft.App.environments'
            properties: {
              serviceName: 'Microsoft.App/environments'
            }
          }
        ]
      }
    ]
  }
}
