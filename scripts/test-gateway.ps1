param([string]$BaseUrl = 'http://localhost:8000', [switch]$IncludeWrites)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(20)
$script:checks = 0
function Request([string]$Method, [string]$Path, [string]$Token = '', [object]$Body = $null) {
    $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::new($Method), "$BaseUrl$Path")
    if ($Token) { $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token) }
    if ($null -ne $Body -and $Method -notin @('GET', 'HEAD')) { $request.Content = [System.Net.Http.StringContent]::new(($Body | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json') }
    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try { return @{ Status = [int]$response.StatusCode; Body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } }
        finally { $response.Dispose() }
    } finally { $request.Dispose() }
}
function Check($Response, [int]$Expected, [string]$Label) {
    if ($Response.Status -ne $Expected) { throw "$Label : esperado $Expected, recebido $($Response.Status)" }
    $script:checks++
    Write-Host "OK $Label ($Expected)"
}
function Base64Url([byte[]]$Bytes) { return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_') }
function Jwt([string]$Key, [string]$Issuer, [long]$Expiration) {
    $header = Base64Url ([Text.Encoding]::UTF8.GetBytes('{"alg":"HS256","typ":"JWT"}'))
    $payload = Base64Url ([Text.Encoding]::UTF8.GetBytes((@{iss=$Issuer;exp=$Expiration} | ConvertTo-Json -Compress)))
    $hmac = [Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($Key))
    try { return "$header.$payload.$(Base64Url ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("$header.$payload"))))" }
    finally { $hmac.Dispose() }
}
try {
    $config = @{}
    Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) '.env') | ForEach-Object {
        if ($_ -match '^([^#=]+)=(.*)$') { $config[$matches[1]] = $matches[2] }
    }
    $id = [Guid]::NewGuid().ToString()
    Check (Request GET '/api/games') 200 'catálogo público'
    Check (Request GET "/api/games/$id/reviews") 200 'avaliações públicas'
    foreach ($path in @('login','register','refresh-login')) {
        Check (Request POST "/api/users/$path" '' @{}) 400 "rota pública $path chega à API"
    }
    $protected = @(
        @('GET','/api/users'), @('GET',"/api/users/$id"), @('POST','/api/games'),
        @('PUT',"/api/games/$id"), @('DELETE',"/api/games/$id"),
        @('POST',"/api/games/$id/reviews"), @('POST',"/api/store/purchase/$id"), @('GET','/api/store/my-library')
    )
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $expired = Jwt $config.JWT_SECRET_KEY $config.JWT_ISSUER ($now - 600)
    $wrongIssuer = Jwt $config.JWT_SECRET_KEY 'invalid-issuer' ($now + 600)
    $wrongSignature = Jwt ('x' * 64) $config.JWT_ISSUER ($now + 600)
    foreach ($route in $protected) {
        foreach ($token in @('', 'invalid.token.signature', $expired, $wrongIssuer, $wrongSignature)) {
            Check (Request $route[0] $route[1] $token @{}) 401 "JWT rejeitado: $($route[0]) $($route[1])"
        }
    }
    $login = Request POST '/api/users/login' '' @{email='admin@trezzecloud.com';password=$config.USERS_ADMIN_PASSWORD}
    Check $login 200 'login real via Kong'
    $tokens = $login.Body | ConvertFrom-Json
    Check (Request GET '/api/users' $tokens.accessToken) 200 'admin com JWT real'
    Check (Request GET '/api/store/my-library' $tokens.accessToken) 200 'biblioteca com JWT real'
    Check (Request POST "/api/store/purchase/$id" $tokens.accessToken) 404 'compra autorizada chega à API'
    Check (Request POST '/api/users/login/extra' '' @{}) 404 'prefixo público não libera subrotas'
    Check (Request POST '/api/users/refresh-login' '' @{refreshToken=$tokens.refreshToken}) 200 'refresh real sem access token'
    if ($IncludeWrites) {
        $email = "gateway-$id@example.com"
        $password = 'GatewayTest@123'
        Check (Request POST '/api/users/register' '' @{name='Gateway Test';email=$email;password=$password}) 200 'registro real'
        $userLogin = Request POST '/api/users/login' '' @{email=$email;password=$password}
        Check $userLogin 200 'login usuário comum'
        $userToken = ($userLogin.Body | ConvertFrom-Json).accessToken
        Check (Request GET '/api/users' $userToken) 403 'role Admin preservada na API'
        $game = @{title="Gateway $id";description='Integration test';price=10;category='Test';imageUrl='https://example.com/game.png';disponibilizationDate='2026-01-01T00:00:00Z'}
        Check (Request POST '/api/games' $userToken $game) 403 'usuário comum não administra jogos'
        $created = Request POST '/api/games' $tokens.accessToken $game
        Check $created 201 'criação jogo'
        $gameId = ($created.Body | ConvertFrom-Json).id
        Check (Request GET "/api/games/$gameId") 200 'consulta jogo criado'
        $list = (Request GET '/api/games').Body | ConvertFrom-Json
        if (!($list | Where-Object id -eq $gameId)) { throw 'Cache não invalidado após Create.' }
        $game.title = 'Updated Gateway Test'
        Check (Request PUT "/api/games/$gameId" $tokens.accessToken $game) 204 'atualização jogo'
        $list = (Request GET '/api/games').Body | ConvertFrom-Json
        if (($list | Where-Object id -eq $gameId).title -ne $game.title) { throw 'Cache não invalidado após Update.' }
        Check (Request POST "/api/games/$gameId/reviews" $userToken @{rating=5;comment='Gateway integration'}) 201 'avaliação MongoDB'
        $reviews = Request GET "/api/games/$gameId/reviews"
        Check $reviews 200 'consulta avaliações MongoDB'
        if (!(($reviews.Body | ConvertFrom-Json) | Where-Object comment -eq 'Gateway integration')) { throw 'Avaliação não persistida.' }
        Check (Request POST "/api/store/purchase/$gameId" $userToken) 202 'compra via RabbitMQ'
        $owned = $false
        for ($attempt = 0; $attempt -lt 15; $attempt++) {
            $library = (Request GET '/api/store/my-library' $userToken).Body | ConvertFrom-Json
            if ($library | Where-Object id -eq $gameId) { $owned = $true; break }
            Start-Sleep -Seconds 1
        }
        if (!$owned) { throw 'Pagamento não chegou à biblioteca.' }
        $script:checks++
        Write-Host 'OK pagamento aprovado chegou à biblioteca'
        Check (Request DELETE "/api/games/$gameId" $tokens.accessToken) 204 'exclusão lógica jogo'
        $list = (Request GET '/api/games').Body | ConvertFrom-Json
        if (($list | Where-Object id -eq $gameId).isActive -ne $false) { throw 'Cache não invalidado após Delete.' }
        $script:checks += 4
        Write-Host 'OK persistência da avaliação e invalidação do cache nas três mutações'
    }
    Write-Host "$script:checks verificações HTTP aprovadas. Nenhum token foi exibido."
} finally { $client.Dispose() }
