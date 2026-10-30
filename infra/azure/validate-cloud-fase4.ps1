param(
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$AksName,
    [Parameter(Mandatory = $true)][string]$AcrName,
    [Parameter(Mandatory = $true)][string]$ExpectedContext,
    [switch]$RequirePublicIngress,
    [switch]$RequireElasticSecret
)

$ErrorActionPreference = 'Stop'

function Assert-Cli {
    param([string]$CommandName)
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Ferramenta obrigatoria nao encontrada: $CommandName"
    }
}

foreach ($binary in @('az', 'kubectl', 'helm')) { Assert-Cli $binary }

$activeSub = (az account show --query id -o tsv)
if ($LASTEXITCODE -ne 0 -or -not $activeSub -or $activeSub.Trim() -ne $SubscriptionId) {
    throw 'Assinatura Azure diferente da esperada. Execute az account set --subscription <id> antes.'
}

$context = (kubectl config current-context)
if ($LASTEXITCODE -ne 0 -or -not $context -or $context.Trim() -ne $ExpectedContext) {
    throw "Contexto kubectl incorreto: $context"
}

$aksState = az aks show -g $ResourceGroup -n $AksName --query powerState.code -o tsv
if ($LASTEXITCODE -ne 0 -or $aksState -ne 'Running') { throw "AKS nao disponivel: $aksState" }

$registry = az acr show -g $ResourceGroup -n $AcrName --query loginServer -o tsv
if ($LASTEXITCODE -ne 0 -or -not $registry) { throw 'ACR nao encontrado na assinatura.' }

$nodes = kubectl get nodes -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $nodes.items -or @($nodes.items).Count -eq 0) {
    throw 'Nao foi possivel encontrar nodes no AKS.'
}
foreach ($node in $nodes.items) {
    $condition = @($node.status.conditions | Where-Object { $_.type -eq 'Ready' } | Select-Object -First 1)
    if (-not $condition -or $condition[0].status -ne 'True') {
        throw "Node nao Ready: $($node.metadata.name)"
    }
}
Write-Host "OK: assinatura, AKS Running, ACR $registry, nodes Ready e contexto $ExpectedContext"

$namespace = 'fcg-fase4'
$deployments = @('sqlserver', 'rabbitmq', 'users-api', 'mongodb', 'redis', 'catalog-api')
foreach ($name in $deployments) {
    $obj = kubectl -n $namespace get deployment $name -o json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $obj) { throw "Deployment ausente: $name" }
    $desired = [int]$obj.spec.replicas
    $ready = [int]$obj.status.readyReplicas
    $available = [int]$obj.status.availableReplicas
    if ($desired -lt 1 -or $ready -ne $desired -or $available -ne $desired) {
        throw "Deployment $name nao Ready: $ready/$desired; disponivel $available/$desired"
    }
    foreach ($container in $obj.spec.template.spec.containers) {
        if ($container.image -match 'PLACEHOLDER') { throw "Imagem nao parametrizada em $name" }
    }
    Write-Host "OK: deployment/$name $ready/$desired Ready"
}

foreach ($pvcName in @('sqlserver-data', 'mongodb-data')) {
    $pvc = kubectl -n $namespace get pvc $pvcName -o json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $pvc.status.phase -ne 'Bound') {
        throw "PVC nao Bound: $pvcName"
    }
    Write-Host "OK: PVC/$pvcName Bound"
}

$ingress = kubectl -n $namespace get ingress fcg-apis -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $ingress.spec.ingressClassName -ne 'fcg-traefik') {
    throw 'Ingress fcg-apis ausente ou com classe inesperada.'
}

$edge = kubectl -n fcg-ingress get svc fcg-traefik -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $edge) { throw 'Service do Traefik nao encontrado.' }

if ($RequirePublicIngress) {
    if ($edge.spec.type -ne 'LoadBalancer' -or -not $edge.status.loadBalancer.ingress[0].ip) {
        throw 'Ingress publico solicitado, mas IP de LoadBalancer ainda nao disponivel.'
    }
    Write-Host 'OK: Ingress publico via LoadBalancer, conferir HTTPS por HTTP real.'
}
else {
    if ($edge.spec.type -notin @('ClusterIP', 'LoadBalancer')) {
        throw "Tipo inesperado do Service Traefik: $($edge.spec.type)"
    }
    Write-Host "OK: Ingress Traefik ($($edge.spec.type)); o teste HTTP ainda deve ser realizado."
}

if ($RequireElasticSecret) {
    $secret = kubectl -n $namespace get secret catalog-search-secrets -o json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $secret.data.Elasticsearch__Endpoint -or -not $secret.data.Elasticsearch__ApiKey) {
        throw 'Secret do Elasticsearch incompleto; configure pelo script configure-catalog-search.ps1.'
    }
    Write-Host 'OK: chaves de configuracao do Elasticsearch presentes no Secret (valores nao exibidos).'
}

Write-Host ''
Write-Host 'VALIDACAO ESTRUTURAL APROVADA. Execute os testes HTTP/Redis/Mongo/Elastic do guia para validar comportamento funcional.'
Write-Host 'Este script nao prova o CI/CD, a busca gerenciada nem ausencia de custos Azure.'
