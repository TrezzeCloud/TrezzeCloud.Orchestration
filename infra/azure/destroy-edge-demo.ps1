param(
    [Parameter(Mandatory = $true)][string]$ExpectedContext
)

$ErrorActionPreference = 'Stop'
$context = kubectl config current-context
if ($LASTEXITCODE -ne 0 -or $context.Trim() -ne $ExpectedContext) {
    throw "Contexto kubectl inesperado: $context"
}

Write-Warning 'Esta operacao remove o Ingress e o Load Balancer publico do Traefik, se existir.'
if ((Read-Host 'Digite REMOVER-INGRESS para confirmar') -ne 'REMOVER-INGRESS') {
    Write-Host 'Operacao cancelada.'
    return
}

kubectl -n fcg-fase4 delete ingress fcg-apis --ignore-not-found=true
if ($LASTEXITCODE -ne 0) { throw 'Falha ao excluir as rotas do Ingress.' }

helm status fcg-edge --namespace fcg-ingress *> $null
if ($LASTEXITCODE -eq 0) {
    helm uninstall fcg-edge --namespace fcg-ingress --wait --timeout 10m
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao desinstalar Traefik.' }
}

Write-Host 'Traefik removido. Confira no Portal Azure a exclusao do IP publico e das regras do Load Balancer.'
Write-Host 'Os Deployments, bancos, Secrets de negocio e ACR nao foram removidos.'
