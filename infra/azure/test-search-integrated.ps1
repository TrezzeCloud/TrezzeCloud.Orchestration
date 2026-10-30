param(
    [Parameter(Mandatory = $true)][string]$ExpectedContext,
    [string]$UsersBaseUrl = 'http://localhost:8080',
    [string]$CatalogBaseUrl = 'http://localhost:8081'
)

$ErrorActionPreference = 'Stop'
foreach ($url in @($UsersBaseUrl, $CatalogBaseUrl)) {
    if ($url -notmatch '^http://(localhost|127\\.0\\.0\\.1):[0-9]+/?$') {
        throw 'Este teste exige port-forward local. Nao envie tokens por HTTP publico.'
    }
}
$UsersBaseUrl = $UsersBaseUrl.TrimEnd('/')
$CatalogBaseUrl = $CatalogBaseUrl.TrimEnd('/')

$current = kubectl config current-context
if ($LASTEXITCODE -ne 0 -or $current.Trim() -ne $ExpectedContext) {
    throw "Contexto incorreto: $current"
}

function Call-Api {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [ValidateSet('GET','POST','PUT','DELETE')][string]$Method = 'GET',
        [object]$Body = $null,
        [string]$Jwt = '',
        [int]$Status = 200
    )
    $headers = @{}
    if ($Jwt) { $headers.Authorization = "Bearer $Jwt" }
    $args = @{ Uri = $Uri; Method = $Method; Headers = $headers; UseBasicParsing = $true }
    if ($null -ne $Body) {
        $args.ContentType = 'application/json'
        $args.Body = ConvertTo-Json -InputObject $Body -Depth 8 -Compress
    }
    try { $response = Invoke-WebRequest @args }
    catch {
        $httpStatus = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        throw "$Method $Uri falhou (HTTP $httpStatus). Verifique se Elasticsearch gerenciado e API estao acessiveis. $($_.Exception.Message)"
    }
    if ([int]$response.StatusCode -ne $Status) {
        throw "$Method $Uri: esperado HTTP $Status; recebido HTTP $($response.StatusCode)"
    }
    if ([string]::IsNullOrWhiteSpace($response.Content)) { return $null }
    return ConvertFrom-Json -InputObject $response.Content
}

$raw = kubectl -n fcg-fase4 get secret users-demo-secrets -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $raw.data.AdminUser__Password) {
    throw 'Secret do admin ausente. Execute antes o deploy-users-demo.ps1.'
}
$adminPassword = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($raw.data.AdminUser__Password))
$raw = $null
$admin = Call-Api -Method POST -Uri "$UsersBaseUrl/api/users/login" -Body @{
    email = 'admin@trezzecloud.com'
    password = $adminPassword
}
$adminPassword = $null
if (-not $admin.accessToken) { throw 'Login do administrador nao retornou token.' }
Write-Host 'OK: login administrativo pela UsersAPI.'

$reindex = Call-Api -Method POST -Uri "$CatalogBaseUrl/search/reindex" -Jwt $admin.accessToken
if ($null -eq $reindex.indexed) { throw 'Reindexacao nao retornou quantidade de jogos processados.' }
Write-Host "OK: POST /search/reindex processou $($reindex.indexed) jogos anteriores."

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 10)
$title = "Cyber Drift $suffix"
$game = Call-Api -Method POST -Uri "$CatalogBaseUrl/api/games" -Status 201 -Jwt $admin.accessToken -Body @{
    title = $title
    description = 'Arcade racing game for FIAP Phase 4 integration'
    price = 39.90
    category = 'Racing'
    imageUrl = 'https://example.invalid/cyber.png'
    disponibilizationDate = [DateTime]::UtcNow.AddDays(-2).ToString('o')
}
if (-not $game.id) { throw 'Cadastro de jogo nao retornou id.' }
Write-Host "OK: jogo indexavel criado ($($game.id))."

$q1 = [Uri]::EscapeDataString('cybr drft')
$found = @(Call-Api -Uri "$CatalogBaseUrl/search?q=$q1&limit=20")
if (-not @($found | Where-Object { "$($_.id)" -eq "$($game.id)" }).Count) {
    throw 'Fuzzy Search falhou: jogo Cyber Drift nao apareceu para cybr drft.'
}
Write-Host 'OK: Fuzzy Search encontra titulo com erro de digitacao.'

$newTitle = "Ocean Quest $suffix"
$null = Call-Api -Method PUT -Uri "$CatalogBaseUrl/api/games/$($game.id)" -Status 204 -Jwt $admin.accessToken -Body @{
    title = $newTitle
    description = 'Ocean exploration game for FIAP Phase 4 integration'
    price = 49.90
    category = 'Adventure'
    imageUrl = 'https://example.invalid/ocean.png'
    disponibilizationDate = [DateTime]::UtcNow.AddDays(-2).ToString('o')
}
$q2 = [Uri]::EscapeDataString('ocen qust')
$afterUpdate = @(Call-Api -Uri "$CatalogBaseUrl/search?q=$q2&limit=20")
if (-not @($afterUpdate | Where-Object { "$($_.id)" -eq "$($game.id)" -and $_.title -eq $newTitle }).Count) {
    throw 'Indice nao refletiu atualizacao de titulo com fuzzy search.'
}
Write-Host 'OK: atualizacao no SQL sincronizada com Elasticsearch.'

$null = Call-Api -Method DELETE -Uri "$CatalogBaseUrl/api/games/$($game.id)" -Status 204 -Jwt $admin.accessToken
$afterDelete = @(Call-Api -Uri "$CatalogBaseUrl/search?q=$q2&limit=20")
if (@($afterDelete | Where-Object { "$($_.id)" -eq "$($game.id)" }).Count) {
    throw 'Jogo desativado continua aparecendo na busca.'
}
Write-Host 'OK: exclusao logica remove jogo da busca.'

Write-Host ''
Write-Host 'TESTE ELASTICSEARCH GERENCIADO APROVADO: reindex, criacao, fuzzy, update e disable.'
Write-Host 'O jogo de teste permanece desativado no SQL Server como evidencia; nenhuma credencial foi exibida.'
