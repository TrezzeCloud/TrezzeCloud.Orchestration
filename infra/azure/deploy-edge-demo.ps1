param(
    [Parameter(Mandatory = $true)][string]$ExpectedContext,
    [ValidateSet('Internal', 'Public')][string]$Exposure = 'Internal',
    [string]$Hostname = '',
    [string]$TlsSecretName = '',
    [switch]$AllowSelfSignedDemo
)

$ErrorActionPreference = 'Stop'

$context = kubectl config current-context
if ($LASTEXITCODE -ne 0 -or $context.Trim() -ne $ExpectedContext) {
    throw "O contexto Kubernetes nao corresponde ao cluster informado: $context"
}

helm version --short | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Helm nao encontrado. Instale Helm 3 ou 4.' }

foreach ($service in @('users-api', 'catalog-api')) {
    $ready = kubectl -n fcg-fase4 get deployment $service -o jsonpath='{.status.availableReplicas}'
    if ($LASTEXITCODE -ne 0 -or $ready -ne '1') {
        throw "Deployment $service deve estar Ready (1/1) antes de instalar o Ingress."
    }
}

if ($TlsSecretName -and -not $Hostname) {
    throw 'Informe Hostname ao utilizar um Secret TLS.'
}
if ($Hostname -and -not $TlsSecretName) {
    throw 'Para usar Hostname, informe tambem TlsSecretName.'
}
if ($Hostname -and $Hostname -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$') {
    throw 'Hostname invalido.'
}
if ($TlsSecretName) {
    $secretType = kubectl -n fcg-fase4 get secret $TlsSecretName -o jsonpath='{.type}'
    if ($LASTEXITCODE -ne 0 -or $secretType -ne 'kubernetes.io/tls') {
        throw 'O Secret TLS deve existir no namespace fcg-fase4 com type kubernetes.io/tls.'
    }
}

if ($Exposure -eq 'Public') {
    if (-not $TlsSecretName -and -not $AllowSelfSignedDemo) {
        throw 'Para publicar na internet, informe Hostname e TlsSecretName com certificado confiavel. Para teste temporario, use -AllowSelfSignedDemo.'
    }

    Write-Warning 'Exposicao PUBLICA cria um Load Balancer/IP no Azure, sujeito a custos mesmo com o AKS parado.'
    if ($AllowSelfSignedDemo -and -not $TlsSecretName) {
        Write-Warning 'O certificado gerado pelo Traefik NAO e confiavel. Use apenas dados ficticios e remova o Load Balancer ao terminar.'
    }
    if ((Read-Host 'Digite PUBLICAR para permitir acesso externo') -ne 'PUBLICAR') {
        Write-Host 'Publicacao cancelada. Nada foi criado.'
        return
    }
}

$values = Join-Path $PSScriptRoot '..\..\k8s\cloud\edge-demo\traefik-values.yaml'
$ingress = Join-Path $PSScriptRoot '..\..\k8s\cloud\edge-demo\apis-ingress.yaml'
$serviceType = if ($Exposure -eq 'Public') { 'LoadBalancer' } else { 'ClusterIP' }

helm repo add traefik https://traefik.github.io/charts --force-update | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar repositorio Helm.' }
helm repo update traefik | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha ao atualizar chart do Traefik.' }

helm upgrade --install fcg-edge traefik/traefik --version '42.1.3' --namespace fcg-ingress --create-namespace --values $values --set "service.spec.type=$serviceType" --wait --timeout 10m
if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar o Ingress. Verifique os pods em fcg-ingress.' }

if ($TlsSecretName) {
    $ingressJson = kubectl create --dry-run=client -f $ingress -o json
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar manifesto Ingress.' }
    $resource = $ingressJson | ConvertFrom-Json
    $resource.spec.tls = @(@{
        hosts = @($Hostname)
        secretName = $TlsSecretName
    })
    $resource.spec.rules[0] | Add-Member -NotePropertyName host -NotePropertyValue $Hostname -Force
    $resource | ConvertTo-Json -Depth 30 -Compress | kubectl -n fcg-fase4 apply -f -
}
else {
    kubectl -n fcg-fase4 apply -f $ingress
}
if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar as rotas Ingress.' }

kubectl -n fcg-ingress get deployments,services
kubectl -n fcg-fase4 get ingress fcg-apis

if ($Exposure -eq 'Public') {
    $ip = kubectl -n fcg-ingress get service fcg-traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar IP publico.' }
    if ($ip) {
        Write-Host "IP publico do Ingress: $ip (HTTPS/443)"
        Write-Host 'Use o DNS/certificado configurado, ou apenas dados ficticios caso esteja usando TLS de teste.'
    }
    else {
        Write-Host 'IP publico ainda pendente. Consulte kubectl -n fcg-ingress get svc fcg-traefik.'
    }
}
else {
    Write-Host 'Ingress interno criado. Teste com: kubectl -n fcg-ingress port-forward svc/fcg-traefik 8443:443'
    Write-Host 'Em outro terminal: curl.exe -k -i https://localhost:8443/api/games'
}
