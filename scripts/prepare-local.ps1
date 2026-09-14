$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$envPath = Join-Path $repoRoot '.env'
if (!(Test-Path -LiteralPath $envPath)) {
    Copy-Item -LiteralPath (Join-Path $repoRoot '.env.example') -Destination $envPath
}
$content = [IO.File]::ReadAllText($envPath)
$match = [regex]::Match($content, '(?m)^JWT_SECRET_KEY=([^\r\n]*)')
if (!$match.Success) { throw 'Adicione JWT_SECRET_KEY= ao arquivo .env.' }
$jwtKey = $match.Groups[1].Value
if ([string]::IsNullOrWhiteSpace($jwtKey)) {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $jwtKey = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    $content = $content.Remove($match.Index, $match.Length).Insert($match.Index, "JWT_SECRET_KEY=$jwtKey")
    [IO.File]::WriteAllText($envPath, $content, (New-Object Text.UTF8Encoding($false)))
}
if ($jwtKey -notmatch '^[A-Za-z0-9_+=./-]{32,}$') { throw 'JWT_SECRET_KEY deve ter 32+ caracteres seguros para YAML.' }
$issuerMatch = [regex]::Match($content, '(?m)^JWT_ISSUER=([A-Za-z0-9_.-]+)\r?$')
if (!$issuerMatch.Success) { throw 'JWT_ISSUER ausente ou inválido.' }
$issuer = $issuerMatch.Groups[1].Value
$audienceMatch = [regex]::Match($content, '(?m)^JWT_AUDIENCE=([A-Za-z0-9_.-]+)\r?$')
if (!$audienceMatch.Success) { throw 'JWT_AUDIENCE ausente ou inválido.' }
$audience = $audienceMatch.Groups[1].Value
[IO.File]::WriteAllText((Join-Path $repoRoot 'k8s/jwt.env'), "JWT_SECRET_KEY=$jwtKey`nJWT_ISSUER=$issuer`nJwt__SecretKey=$jwtKey`nJwt__Issuer=$issuer`nJwt__Audience=$audience`n", (New-Object Text.UTF8Encoding($false)))
Write-Host 'Configuração local preparada; chave JWT não exibida. .env existente preservado; jwt.env sincronizado.'
