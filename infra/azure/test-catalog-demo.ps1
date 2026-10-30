param(
    [string]$BaseUrl = 'http://localhost:8081',
    [Parameter(Mandatory = $true)][string]$ExpectedContext
)

$ErrorActionPreference = 'Stop'

if ($BaseUrl -notmatch '^http://(localhost|127\.0\.0\.1):[0-9]+/?$') {
    throw 'Este teste deve usar o port-forward local da CatalogAPI.'
}

$context = kubectl config current-context
if ($LASTEXITCODE -ne 0 -or $context.Trim() -ne $ExpectedContext) {
    throw "Contexto kubectl diferente do esperado: $context"
}

$BaseUrl = $BaseUrl.TrimEnd('/')
$gameId = [guid]::NewGuid().ToString('D')

$games = Invoke-WebRequest -Uri "$BaseUrl/api/games" -UseBasicParsing
if ([int]$games.StatusCode -ne 200) {
    throw "GET /api/games retornou HTTP $($games.StatusCode)."
}
$gamesData = $games.Content | ConvertFrom-Json
Write-Host 'GET /api/games: HTTP 200 (SQL Server + Redis)'

$again = Invoke-WebRequest -Uri "$BaseUrl/api/games" -UseBasicParsing
if ([int]$again.StatusCode -ne 200) {
    throw "Segunda leitura de /api/games retornou HTTP $($again.StatusCode)."
}
Write-Host 'GET /api/games (segunda leitura): HTTP 200'

$reviews = Invoke-WebRequest -Uri "$BaseUrl/api/games/$gameId/reviews" -UseBasicParsing
if ([int]$reviews.StatusCode -ne 200) {
    throw "GET /api/games/{id}/reviews retornou HTTP $($reviews.StatusCode)."
}
$null = $reviews.Content | ConvertFrom-Json
Write-Host 'GET /api/games/{id}/reviews: HTTP 200 (MongoDB)'

$ttl = kubectl -n fcg-fase4 exec deployment/redis -- sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli TTL "TrezzeCloud:games:all:v2"'
if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao consultar o Redis.'
}
$ttlText = ($ttl | Out-String).Trim()
[int]$ttlSeconds = 0
if (-not [int]::TryParse($ttlText, [ref]$ttlSeconds)) {
    throw "Resposta inesperada do Redis para TTL: $ttlText"
}

if ($ttlSeconds -lt 0) {
    throw "A chave de cache nao foi encontrada com expiracao: TTL=$ttlSeconds. Verifique o Redis e a configuracao do cache."
}
Write-Host "Redis: chave de jogos encontrada, TTL=$ttlSeconds segundos"
Write-Host 'Teste concluido. O acesso a MongoDB foi somente leitura; gravacao de avaliacoes sera testada separadamente.'
