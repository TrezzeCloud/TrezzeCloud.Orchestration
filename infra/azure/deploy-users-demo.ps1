param(
    [Parameter(Mandatory = $true)][string]$Image,
    [Parameter(Mandatory = $true)][string]$ExpectedContext
)

$ErrorActionPreference = 'Stop'

if ($Image -notmatch '^[a-z0-9]+\.azurecr\.io/trezzecloud-users-api:[A-Za-z0-9_.-]+$') {
    throw 'Informe a imagem completa publicada no ACR, incluindo a tag.'
}

$context = kubectl config current-context
if ($LASTEXITCODE -ne 0 -or $context.Trim() -ne $ExpectedContext) {
    throw "Contexto kubectl diferente do esperado. Atual: $context"
}

$namespace = 'fcg-fase4'
$manifestDir = Join-Path $PSScriptRoot '..\..\k8s\cloud\users-demo'

kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao criar o namespace.'
}

$existing = kubectl -n $namespace get secret users-demo-secrets --ignore-not-found -o name
if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao consultar os Secrets existentes.'
}

if (-not $existing) {
    function New-RandomValue {
        param([int]$Length = 32)
        $bytes = New-Object byte[] $Length
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $rng.GetBytes($bytes)
        }
        finally {
            $rng.Dispose()
        }
        return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'A').Replace('/', 'b')
    }

    function To-Base64([string]$value) {
        return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value))
    }

    $sqlPassword = 'Aa1!' + (New-RandomValue)
    $rabbitPassword = 'Aa1!' + (New-RandomValue)
    $adminPassword = 'Aa1!' + (New-RandomValue)
    $jwtSecret = New-RandomValue 48

    $connectionString = "Server=sqlserver;Database=TrezzeCloudUsers;User Id=sa;Password=$sqlPassword;Encrypt=True;TrustServerCertificate=True"

    $secret = @{
        apiVersion = 'v1'
        kind = 'Secret'
        type = 'Opaque'
        metadata = @{ name = 'users-demo-secrets'; namespace = $namespace }
        data = @{
            MSSQL_SA_PASSWORD = (To-Base64 $sqlPassword)
            ConnectionStrings__UsersDatabase = (To-Base64 $connectionString)
            RabbitMq__Username = (To-Base64 'fcguser')
            RabbitMq__Password = (To-Base64 $rabbitPassword)
            AdminUser__Password = (To-Base64 $adminPassword)
            Jwt__SecretKey = (To-Base64 $jwtSecret)
        }
    }

    $json = $secret | ConvertTo-Json -Depth 6 -Compress
    $json | kubectl apply --server-side --field-manager=fcg-fase4 -f -
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao criar os Secrets.'
    }
    $json = $null
    $secret = $null
    Write-Host 'Secrets criados no Kubernetes. Nenhuma senha foi gravada em arquivo.'
}
else {
    Write-Host 'Reutilizando os Secrets existentes. As senhas nao serao alteradas.'
}

kubectl -n $namespace apply -f (Join-Path $manifestDir 'sqlserver.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar o SQL Server.' }

kubectl -n $namespace apply -f (Join-Path $manifestDir 'rabbitmq.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar o RabbitMQ.' }

kubectl -n $namespace rollout status deployment/sqlserver --timeout=360s
if ($LASTEXITCODE -ne 0) {
    throw 'SQL Server nao ficou Ready. Consulte kubectl describe pods e os logs.'
}

kubectl -n $namespace rollout status deployment/rabbitmq --timeout=240s
if ($LASTEXITCODE -ne 0) {
    throw 'RabbitMQ nao ficou Ready. Consulte os logs antes de prosseguir.'
}

$apiManifest = (Get-Content (Join-Path $manifestDir 'users-api.yaml') -Raw).Replace('USERS_API_IMAGE_PLACEHOLDER', $Image)
$apiManifest | kubectl -n $namespace apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar a UsersAPI.' }

kubectl -n $namespace rollout status deployment/users-api --timeout=360s
if ($LASTEXITCODE -ne 0) {
    throw 'UsersAPI nao ficou Ready. Consulte kubectl logs deployment/users-api.'
}

kubectl -n $namespace get pods -o wide
kubectl -n $namespace get services
Write-Host 'Para testar localmente: kubectl -n fcg-fase4 port-forward svc/users-api 8080:8080'
