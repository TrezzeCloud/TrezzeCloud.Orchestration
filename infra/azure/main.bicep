targetScope = 'resourceGroup'

@description('ID unico do integrante (somente letras minusculas e numeros, 2-12 caracteres).')
@minLength(2)
@maxLength(12)
param memberId string

param location string = resourceGroup().location

@description('Quantidade de nos no pool de sistema do AKS.')
@minValue(2)
@maxValue(3)
param nodeCount int = 2

@description('Tamanho da VM. Verifique preco e quota antes de provisionar.')
param vmSize string = 'Standard_D4as_v5'

var prefix = 'fcg-${memberId}'
var acrName = 'acrfcg${memberId}${uniqueString(resourceGroup().id)}'
var tags = {
  project: 'fiap-cloud-games'
  phase: '4'
  member: memberId
  ephemeral: 'true'
}

module registry './modules/acr.bicep' = {
  name: 'acr-${memberId}'
  params: {
    name: acrName
    location: location
    resourceTags: tags
  }
}

module cluster './modules/aks.bicep' = {
  name: 'aks-${memberId}'
  params: {
    name: 'aks-${prefix}'
    location: location
    dnsPrefix: 'aks-${prefix}-${uniqueString(resourceGroup().id)}'
    nodeCount: nodeCount
    vmSize: vmSize
    resourceTags: tags
  }
}

output acrName string = registry.outputs.name
output acrLoginServer string = registry.outputs.loginServer
output aksName string = cluster.outputs.name
output resourceGroupName string = resourceGroup().name
