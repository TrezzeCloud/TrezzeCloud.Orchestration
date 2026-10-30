param(
    [Parameter(Mandatory = $true)][string]$ExpectedContext,
    [Parameter(Mandatory = $true)][string]$Endpoint
)

$ErrorActionPreference = 'Stop'

if (-not $Endpoint.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Informe o endpoint HTTPS do Elasticsearch gerenciado.'
}

$context = kubectl config current-context
if ($LASTEXITCODE -ne 0 -or $context.Trim() -ne $ExpectedContext) {
    throw "O contexto kubectl nao corresponde ao cluster esperado: $context"
}

$namespace = 'fcg-fase4'
$deploymentJson = kubectl -n $namespace get deployment catalog-api -o json
if ($LASTEXITCODE -ne 0) { throw 'CatalogAPI nao encontrada no cluster.' }
$deployment = $deploymentJson | ConvertFrom-Json
$image = ($deployment.spec.template.spec.containers | Where-Object { $_.name -eq 'catalog-api' } | Select-Object -First 1).image
if ($image -notmatch '^[a-z0-9]+\.azurecr\.io/trezzecloud-catalog-api:[A-Za-z0-9_.-]+$') {
    throw 'Imagem da CatalogAPI nao identificada no deployment.'
}

$secureApiKey = Read-Host 'Cole a API key do Elasticsearch (nao sera exibida)' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
try {
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'A API key nao pode ser vazia.' }

    function To-Base64([string]$value) {
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value))
    }

    $secret = @{
        apiVersion = 'v1'
        kind = 'Secret'
        type = 'Opaque'
        metadata = @{ name = 'catalog-search-secrets'; namespace = $namespace }
        data = @{
            'Elasticsearch__Endpoint' = To-Base64 $Endpoint.TrimEnd('/')
            'Elasticsearch__ApiKey' = To-Base64 $apiKey
        }
    }

    $json = $secret | ConvertTo-Json -Depth 6 -Compress
    $json | kubectl -n $namespace apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar o Secret de busca.' }
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $secureApiKey = $null
    $apiKey = $null
    $json = $null
    $secret = $null
}

$manifestPath = Join-Path $PSScriptRoot '..\..\k8s\cloud\catalog-demo\catalog-api.yaml'
$manifest = (Get-Content $manifestPath -Raw).Replace('CATALOG_API_IMAGE_PLACEHOLDER', $image)
$manifest | kubectl -n $namespace apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar o manifesto CatalogAPI.' }

kubectl -n $namespace rollout restart deployment/catalog-api
if ($LASTEXITCODE -ne 0) { throw 'Falha ao reiniciar a CatalogAPI com a configuracao de busca.' }

kubectl -n $namespace rollout status deployment/catalog-api --timeout=360s
if ($LASTEXITCODE -ne 0) { throw 'CatalogAPI nao ficou pronta. Consulte os logs.' }

Write-Host 'Busca Elasticsearch configurada. A reconciliacao inicial de jogos inicia em segundo plano.'
Write-Host 'Teste: kubectl -n fcg-fase4 port-forward svc/catalog-api 8081:8080'
Write-Host 'Em outro terminal: curl.exe "http://localhost:8081/search?q=game"'
