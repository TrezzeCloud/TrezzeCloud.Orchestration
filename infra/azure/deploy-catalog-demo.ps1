param(
    [Parameter(Mandatory = $true)][string]$Image,
    [Parameter(Mandatory = $true)][string]$ExpectedContext
)

$ErrorActionPreference = 'Stop'

if ($Image -notmatch '^[a-z0-9]+\.azurecr\.io/trezzecloud-catalog-api:[A-Za-z0-9_.-]+$') {
    throw 'Informe a imagem completa da CatalogAPI no ACR.'
}

$context = kubectl config current-context
if ($LASTEXITCODE -ne 0 -or $context.Trim() -ne $ExpectedContext) {
    throw "O contexto kubectl nao corresponde ao cluster esperado: $context"
}

$namespace = 'fcg-fase4'
$manifestDir = Join-Path $PSScriptRoot '..\..\k8s\cloud\catalog-demo'

$usersSecret = kubectl -n $namespace get secret users-demo-secrets -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $usersSecret) {
    throw 'Os Secrets da UsersAPI nao foram encontrados. Implante primeiro a UsersAPI.'
}

function Decode-Secret([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'Secret incompleto.' }
    return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value))
}

function To-Base64([string]$value) {
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value))
}

function New-Password {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) }
    finally { $rng.Dispose() }
    return 'Aa1!' + [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'A').Replace('/', 'b')
}

$sqlPassword = Decode-Secret $usersSecret.data.MSSQL_SA_PASSWORD

$existing = kubectl -n $namespace get secret catalog-demo-secrets --ignore-not-found -o name
if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar os Secrets do Catalog.' }

if (-not $existing) {
    $mongoPassword = New-Password
    $redisPassword = New-Password
    $mongoUsername = 'fcgadmin'

    $sqlConnection = "Server=sqlserver;Database=TrezzeCloudCatalog;User Id=sa;Password=$sqlPassword;Encrypt=True;TrustServerCertificate=True"
    $mongoConnection = "mongodb://$($mongoUsername):$($mongoPassword)@mongodb:27017/?authSource=admin"
    $redisConnection = "redis:6379,password=$redisPassword,abortConnect=false"

    $secret = @{
        apiVersion = 'v1'
        kind = 'Secret'
        type = 'Opaque'
        metadata = @{ name = 'catalog-demo-secrets'; namespace = $namespace }
        data = @{
            MONGO_INITDB_ROOT_USERNAME = To-Base64 $mongoUsername
            MONGO_INITDB_ROOT_PASSWORD = To-Base64 $mongoPassword
            MongoDb__ConnectionString = To-Base64 $mongoConnection
            Redis__ConnectionString = To-Base64 $redisConnection
            REDIS_PASSWORD = To-Base64 $redisPassword
            ConnectionStrings__CatalogDatabase = To-Base64 $sqlConnection
        }
    }

    $json = $secret | ConvertTo-Json -Depth 6 -Compress
    $json | kubectl -n $namespace create -f -
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar os Secrets do Catalog.' }
    $json = $null
    $secret = $null
    Write-Host 'Secrets do Catalog criados.'
}
else {
    Write-Host 'Reutilizando os Secrets existentes do Catalog.'
}

kubectl -n $namespace rollout status deployment/sqlserver --timeout=120s
if ($LASTEXITCODE -ne 0) { throw 'SQL Server indisponivel.' }
kubectl -n $namespace rollout status deployment/rabbitmq --timeout=120s
if ($LASTEXITCODE -ne 0) { throw 'RabbitMQ indisponivel.' }

kubectl -n $namespace apply -f (Join-Path $manifestDir 'mongodb.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar o MongoDB.' }
kubectl -n $namespace apply -f (Join-Path $manifestDir 'redis.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar o Redis.' }

kubectl -n $namespace rollout status deployment/mongodb --timeout=360s
if ($LASTEXITCODE -ne 0) { throw 'MongoDB nao ficou Ready. Verifique os pods e eventos.' }
kubectl -n $namespace rollout status deployment/redis --timeout=180s
if ($LASTEXITCODE -ne 0) { throw 'Redis nao ficou Ready. Verifique os pods e eventos.' }

$manifest = (Get-Content (Join-Path $manifestDir 'catalog-api.yaml') -Raw).Replace('CATALOG_API_IMAGE_PLACEHOLDER', $Image)
$manifest | kubectl -n $namespace apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar a CatalogAPI.' }

kubectl -n $namespace rollout status deployment/catalog-api --timeout=360s
if ($LASTEXITCODE -ne 0) { throw 'CatalogAPI nao ficou Ready. Consulte os logs.' }

kubectl -n $namespace get pods
kubectl -n $namespace get pvc
Write-Host 'Teste local: kubectl -n fcg-fase4 port-forward svc/catalog-api 8081:8080'
