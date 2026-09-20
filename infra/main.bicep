targetScope = 'resourceGroup'

@description('Azure region for the optional Sysmon data collection rule.')
param location string = resourceGroup().location

@description('Existing Log Analytics workspace resource ID backing Microsoft Sentinel. Leave empty to skip Sentinel/Log Analytics resources.')
param logAnalyticsWorkspaceResourceId string = ''

@description('Name of the optional Sysmon data collection rule.')
param dcrName string = 'dcr-sysmon'

resource sysmonDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  name: dcrName
  location: location
  kind: 'Windows'
  properties: {
    description: 'AZD Sysmon Windows Event Log collection. Applies only where this DCR is associated.'
    dataSources: {
      windowsEventLogs: [
        {
          name: 'sysmonOperational'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'Microsoft-Windows-Sysmon/Operational!*'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'sentinelWorkspace'
          workspaceResourceId: logAnalyticsWorkspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Event'
        ]
        destinations: [
          'sentinelWorkspace'
        ]
      }
    ]
  }
  tags: {
    'azd-template': 'azd-sysmon'
    'purpose': 'sysmon-event-collection'
  }
}

output sysmonDcrId string = !empty(logAnalyticsWorkspaceResourceId)
  ? resourceId('Microsoft.Insights/dataCollectionRules', dcrName)
  : ''

output sysmonDcrLocation string = location

output sentinelIntegrationEnabled bool = !empty(logAnalyticsWorkspaceResourceId)
