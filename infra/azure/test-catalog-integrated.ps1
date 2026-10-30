param(
    [string]$UsersBaseUrl = 'http://localhost:8080',
    [string]$CatalogBaseUrl = 'http://localhost:8081',
    [Parameter(Mandatory = $true)][string]$ExpectedContext
)

$ErrorActionPreference = 'Stop'
$namespace = 'fcg-fase4'
$cacheKey = 'TrezzeCloud:games:all:v2'

foreach ($url in @($UsersBaseUrl, $CatalogBaseUrl)) {
    if ($url -notmatch '^http://(localhost|127\.0\.0\.1):[0-9]+/?$') {
        throw 'Use somente os port-forwards locais para este teste.'
    }
}

$UsersBaseUrl = $UsersBaseUrl.TrimEnd('/')
$CatalogBaseUrl = $CatalogBaseUrl.TrimEnd('/')

$currentContext = kubectl config current-context
if ($LASTEXITCODE -ne 0 -or $currentContext.Trim() -ne $ExpectedContext) {
    throw "Contexto kubectl diferente do esperado: $currentContext"
}

function Send-Json {
    param(
        [ValidateSet('GET', 'POST', 'PUT')][string]$Method,
        [string]$Uri,
        [object]$Body,
        [string]$Token,
        [int]$ExpectedStatus
    )

    $headers = @{}
    if ($Token) {
        $headers['Authorization'] = "Bearer $Token"
    }

    $request = @{
        Method = $Method
        Uri = $Uri
        Headers = $headers
        UseBasicParsing = $true
    }

    if ($null -ne $Body) {
        $request['ContentType'] = 'application/json'
        $request['Body'] = ConvertTo-Json -InputObject $Body -Depth 8 -Compress
    }

    $response = Invoke-WebRequest @request
    if ([int]$response.StatusCode -ne $ExpectedStatus) {
        throw "$Method $Uri retornou HTTP $($response.StatusCode); esperado $ExpectedStatus."
    }

    if ([string]::IsNullOrWhiteSpace($response.Content)) {
        return $null
    }

    return ConvertFrom-Json -InputObject $response.Content
}

function Get-CacheTtl {
    $response = kubectl -n $namespace exec deployment/redis -- sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli TTL "TrezzeCloud:games:all:v2"'
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao consultar a chave de cache do Redis.'
    }

    $raw = ($response | Out-String).Trim()
    [int]$ttl = 0
    if (-not [int]::TryParse($raw, [ref]$ttl)) {
        throw "TTL inesperado do Redis: $raw"
    }

    return $ttl
}

function New-TestPassword {
    $bytes = New-Object byte[] 24
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return 'Aa1!' + [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'A').Replace('/', 'b')
}

$usersApi = "$UsersBaseUrl/api/users"
$gamesApi = "$CatalogBaseUrl/api/games"

$secret = kubectl -n $namespace get secret users-demo-secrets -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $secret.data.AdminUser__Password) {
    throw 'Secret do administrador nao encontrado no namespace.'
}

$adminPassword = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($secret.data.AdminUser__Password)
)
$secret = $null

$admin = Send-Json -Method POST -Uri "$usersApi/login" -Body @{
    email = 'admin@trezzecloud.com'
    password = $adminPassword
} -ExpectedStatus 200
$adminPassword = $null

if (-not $admin.accessToken) {
    throw 'Login do administrador nao retornou JWT.'
}
Write-Host 'Login do administrador na UsersAPI: OK'

# Garante que a chave esteja no Redis antes de testar invalidacao.
$null = Send-Json -Method GET -Uri $gamesApi -ExpectedStatus 200
$before = Get-CacheTtl
if ($before -le 0) {
    throw "O cache de jogos nao foi preenchido no Redis: TTL=$before"
}
Write-Host "Redis antes do cadastro: TTL=$before segundos"

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 10)
$gameTitle = "FIAP Fase 4 - Teste $suffix"
$game = Send-Json -Method POST -Uri $gamesApi -Token $admin.accessToken -ExpectedStatus 201 -Body @{
    title = $gameTitle
    description = 'Jogo criado no teste integrado da Fase 4'
    price = 29.90
    category = 'Teste'
    imageUrl = 'https://example.invalid/fase4.png'
    disponibilizationDate = [DateTime]::UtcNow.AddDays(-1).ToString('o')
}

if (-not $game.id) {
    throw 'Cadastro de jogo nao retornou o ID.'
}
Write-Host "Jogo criado no SQL Server: $($game.id)"

$afterCreate = Get-CacheTtl
if ($afterCreate -ne -2) {
    throw "O cadastro nao removeu a chave do Redis: TTL=$afterCreate; esperado -2."
}
Write-Host 'Redis apos cadastro: cache invalidado (-2)'

$list = @(Send-Json -Method GET -Uri $gamesApi -ExpectedStatus 200)
if (-not @($list | Where-Object { $_.id -eq $game.id }).Count) {
    throw 'O jogo cadastrado nao foi encontrado na nova lista de jogos.'
}
Write-Host 'GET /api/games: jogo encontrado e cache recriado'

$afterRead = Get-CacheTtl
if ($afterRead -le 0) {
    throw "Cache nao foi recriado apos consulta de jogos: TTL=$afterRead."
}

$email = "fase4-$([guid]::NewGuid().ToString('N'))@example.invalid"
$password = New-TestPassword

$user = Send-Json -Method POST -Uri "$usersApi/register" -ExpectedStatus 200 -Body @{
    name = 'Teste Integracao Fase 4'
    email = $email
    password = $password
}
if (-not $user.accessToken) {
    throw 'Cadastro do usuario nao retornou JWT.'
}
Write-Host 'Usuario de teste cadastrado na UsersAPI: OK'

$login = Send-Json -Method POST -Uri "$usersApi/login" -ExpectedStatus 200 -Body @{
    email = $email
    password = $password
}
$password = $null
if (-not $login.accessToken) {
    throw 'Login do usuario de teste nao retornou JWT.'
}

$comment = "Avaliacao automatizada $suffix"
$review = Send-Json -Method POST -Uri "$gamesApi/$($game.id)/reviews" -Token $login.accessToken -ExpectedStatus 201 -Body @{
    rating = 5
    comment = $comment
}
if (-not $review.id) {
    throw 'Avaliacao nao retornou identificador do MongoDB.'
}
Write-Host 'POST /api/games/{id}/reviews: HTTP 201 (JWT da UsersAPI)'

$reviews = @(Send-Json -Method GET -Uri "$gamesApi/$($game.id)/reviews" -ExpectedStatus 200)
if (-not @($reviews | Where-Object { $_.id -eq $review.id -and $_.comment -eq $comment }).Count) {
    throw 'A avaliacao cadastrada nao foi recuperada do MongoDB.'
}
Write-Host 'GET /api/games/{id}/reviews: avaliacao persistida no MongoDB'

$updatedTitle = "$gameTitle - atualizado"
$null = Send-Json -Method PUT -Uri "$gamesApi/$($game.id)" -Token $admin.accessToken -ExpectedStatus 204 -Body @{
    title = $updatedTitle
    description = 'Jogo atualizado no teste integrado da Fase 4'
    price = 39.90
    category = 'Teste'
    imageUrl = 'https://example.invalid/fase4.png'
    disponibilizationDate = [DateTime]::UtcNow.AddDays(-1).ToString('o')
}

$afterUpdate = Get-CacheTtl
if ($afterUpdate -ne -2) {
    throw "A atualizacao nao invalidou a chave do Redis: TTL=$afterUpdate."
}
Write-Host 'PUT /api/games/{id}: HTTP 204 e cache invalidado'

$updatedGames = @(Send-Json -Method GET -Uri $gamesApi -ExpectedStatus 200)
if (-not @($updatedGames | Where-Object { $_.id -eq $game.id -and $_.title -eq $updatedTitle }).Count) {
    throw 'O catalogo nao retornou o titulo atualizado.'
}

Write-Host 'Teste integrado aprovado: SQL Server, Redis, MongoDB e JWT compartilhado.'
Write-Host 'Um jogo, uma avaliacao e um usuario de demonstracao foram mantidos para verificacao posterior.'
