param(
    [string]$BaseUrl = 'http://localhost:8080'
)

$ErrorActionPreference = 'Stop'

if ($BaseUrl -notmatch '^http://(localhost|127\.0\.0\.1):[0-9]+/?$') {
    throw 'O teste deve usar somente o port-forward local da UsersAPI.'
}

$BaseUrl = $BaseUrl.TrimEnd('/')

function Get-StatusCode {
    param([string]$Uri, [hashtable]$Headers = @{})

    try {
        $response = Invoke-WebRequest -Uri $Uri -Headers $Headers -UseBasicParsing
        return [int]$response.StatusCode
    }
    catch {
        if ($null -eq $_.Exception.Response) {
            throw
        }

        return [int]$_.Exception.Response.StatusCode
    }
}

$registerUri = "$BaseUrl/api/users/register"
$loginUri = "$BaseUrl/api/users/login"
$usersUri = "$BaseUrl/api/users"

$unauthenticatedStatus = Get-StatusCode -Uri $usersUri
if ($unauthenticatedStatus -ne 401) {
    throw "A rota protegida retornou $unauthenticatedStatus sem autenticacao. Esperado: 401."
}
Write-Host 'GET /api/users sem token: 401 OK'

$email = "fase4-$([guid]::NewGuid().ToString('N'))@example.invalid"
$bytes = New-Object byte[] 24
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $rng.GetBytes($bytes)
}
finally {
    $rng.Dispose()
}
$password = 'Aa1!' + [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'A').Replace('/', 'b')
$registerBody = @{
    name = 'Teste Fase 4'
    email = $email
    password = $password
} | ConvertTo-Json -Compress

$registration = Invoke-RestMethod -Method Post -Uri $registerUri -ContentType 'application/json' -Body $registerBody

if (-not $registration.userId -or -not $registration.accessToken -or -not $registration.refreshToken) {
    throw 'O cadastro nao retornou o identificador e os tokens esperados.'
}
Write-Host 'POST /api/users/register: OK'

$loginBody = @{
    email = $email
    password = $password
} | ConvertTo-Json -Compress

$login = Invoke-RestMethod -Method Post -Uri $loginUri -ContentType 'application/json' -Body $loginBody

if ($login.userId -ne $registration.userId -or -not $login.accessToken) {
    throw 'Login nao retornou o mesmo usuario cadastrado.'
}
Write-Host 'POST /api/users/login: OK (usuario encontrado no SQL Server)'

$forbiddenStatus = Get-StatusCode -Uri $usersUri -Headers @{
    Authorization = "Bearer $($login.accessToken)"
}
if ($forbiddenStatus -ne 403) {
    throw "O acesso de usuario comum retornou $forbiddenStatus. Esperado: 403."
}
Write-Host 'GET /api/users com token de usuario comum: 403 OK'
Write-Host 'Teste concluido. Senha e tokens nao foram exibidos.'
