param applicationGatewayName string = 'myGateway'
var location = resourceGroup().location
var vnet = 'myVnet'

resource pip 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: 'mypip'
  location: location
  sku:{
    name:'Standard'
    tier:'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource myVnet 'Microsoft.Network/virtualNetworks@2021-03-01' existing = {
  name: vnet
}

var subnetname = 'ag-subnet'
var mysubnetid = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet, subnetname)

var appgwid = resourceId('Microsoft.Network/applicationGateways', applicationGatewayName)
var keyvault_name = 'kv'
var gw_cert = 'agcert'
var msi_name = 'msi'

resource existing_keyvault 'Microsoft.KeyVault/vaults@2020-04-01-preview' existing = {
  name: keyvault_name
}

resource existing_identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: msi_name
}

param sku string = 'WAF_v2'

resource applicationGateways 'Microsoft.Network/applicationGateways@2021-03-01' = {
  name: applicationGatewayName

  location: location

  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${existing_identity.id}': {}
    }
  }

  properties: {
    sku: {
      name: sku
      tier: sku
    }

    enableHttp2: false
    sslPolicy: {
      policyType: 'Predefined'
      policyName: 'AppGwSslPolicy20170401S'
    }
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 2
    }
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Detection'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.1'

      exclusions: []
      requestBodyCheck: false
    }

    sslCertificates: [
      {
        name: 'ssl-appgw-external'
        properties: {
          keyVaultSecretId: 'https://${existing_keyvault.name}.vault.azure.net/secrets/${gw_cert}'
        }
      }
    ]

    probes:[
      {
        name: 'myprobe'
        properties:{
          pickHostNameFromBackendHttpSettings:true
          interval:30
          timeout:30
          path: '/'
          port: 443
          protocol:'Https'
          unhealthyThreshold:3
          match:{
            statusCodes:[
              '200-399'
            ]
          }
        }
      }
      {
        name: 'dnuprobe'
        properties:{
          pickHostNameFromBackendHttpSettings:true
          interval:30
          timeout:30
          path: '/'
          port:443
          protocol:'Https'
          unhealthyThreshold:3
          match:{
            statusCodes:[
              '200-399'
              '404'
            ]
          }
        }
      }            
    ]

    gatewayIPConfigurations:[
      {
        name: 'appgw-ip-config'
        properties:{
          subnet:{
            id: mysubnetid
          }
        }
      }
    ]
    frontendIPConfigurations:[
      { 
        name:'appgw-public-frontend-ip'
        properties:{
          publicIPAddress:{
            id: pip.id
          }
        }
      }
      {
        name:'appgw-private-frontend-ip'
        properties:{
          privateIPAddress:'10.1.22.4'
          privateIPAllocationMethod:'Static'
          subnet:{
            id:mysubnetid
          }
        }
      }
    ]

    frontendPorts:[
      {
        name: 'port_443'
        properties:{
          port: 443
        }
      }
      {
        name:'port_8443'
        properties:{
          port: 8443
        }
      }
    ]
    backendAddressPools:[
      { 
        name: 'dnubackendpool'
        properties:{
          backendAddresses:[
            
          ]
        }
      }
      { 
        name: 'mybackendpool'
        properties:{
          backendAddresses:[
            {
              fqdn:'abc.azurewebsites.net'
            }
          ]
        }
      }
                
    ]

    backendHttpSettingsCollection:[
      {
        name: 'dnuhttpsetting'
        properties:{
          port: 8443
          protocol:'Https'
          cookieBasedAffinity:'Disabled'
          requestTimeout: 120
          
          pickHostNameFromBackendAddress:true
          probe:{
           id: concat(appgwid, '/probes/dnuprobe')
          }
        }
      } 
      {
       name: 'myhttpsetting'
       properties:{
         port: 443
         protocol:'Https'
         cookieBasedAffinity:'Disabled'
         requestTimeout: 120
         connectionDraining:{
           enabled:true
           drainTimeoutInSec: 20
         }
         pickHostNameFromBackendAddress:true
         probe:{
          id: concat(appgwid, '/probes/myprobe')
         }
         
       }
      } 
                 
     ]


     httpListeners:[
      {
        name: 'dnulistener'

        properties:{
          protocol:'Https'
          
          frontendIPConfiguration:{
            id: concat(appgwid, '/frontendIPConfigurations/appgw-public-frontend-ip')

          }
          frontendPort:{
            id: concat(appgwid, '/frontendPorts/port_8443')

          }
          sslCertificate:{
            id: concat(appgwid, '/sslCertificates/ssl-appgw-external')

          }

        }
      }
      {
        name: 'mylistener'
        properties:{
          protocol:'Https'
          frontendIPConfiguration:{
            id: concat(appgwid, '/frontendIPConfigurations/appgw-private-frontend-ip')
          }
          frontendPort:{
            id: concat(appgwid, '/frontendPorts/port_443')
          }
          sslCertificate:{
            id: concat(appgwid, '/sslCertificates/ssl-appgw-external')
          }
        }
      }
             
    ]
    requestRoutingRules:[
      {
        name: 'dnurouting'
        properties:{
          ruleType:'Basic'
          httpListener:{
            id: concat(appgwid, '/httpListeners/dnulistener')

          }
          backendAddressPool:{
            id: concat(appgwid, '/backendAddressPools/dnubackendpool')
          }
          backendHttpSettings:{
            id: concat(appgwid, '/backendHttpSettingsCollection/dnuhttpsetting')
          }
          
        }
      }
      {
        name: 'myrouting'
        properties:{
          ruleType:'Basic'
          httpListener:{
            id: concat(appgwid, '/httpListeners/mylistener')
          }
          backendAddressPool:{
            id: concat(appgwid, '/backendAddressPools/mybackendpool')
          }
          backendHttpSettings:{
            id: concat(appgwid, '/backendHttpSettingsCollection/myhttpsetting')
          }
        }
      }
                 
    ]

  }
}
