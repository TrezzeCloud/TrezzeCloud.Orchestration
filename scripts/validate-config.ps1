$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    docker compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose inválido.' }
    $config = docker compose config --format json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Falha na leitura do Compose.' }
    foreach ($service in $config.services.PSObject.Properties) {
        if ($service.Name -ne 'kong' -and $service.Value.ports.Count -gt 0) { throw "Portas externas inesperadas: $($service.Name)" }
    }
    if ($config.services.kong.environment.KONG_ADMIN_LISTEN -ne 'off') { throw 'Admin API habilitada.' }
    if ($config.services.kong.ports.Count -ne 1 -or $config.services.kong.ports[0].target -ne 8000) { throw 'Portas Kong inválidas.' }
    $jwt = $config.services.kong.environment.JWT_SECRET_KEY
    if ($jwt -ne $config.services.'users-api'.environment.Jwt__SecretKey -or $jwt -ne $config.services.'catalog-api'.environment.Jwt__SecretKey) { throw 'Chaves JWT divergentes.' }
    kubectl kustomize k8s | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Manifests/Kustomize inválidos.' }
    Get-Content k8s/rabbitmq/definitions.json -Raw | ConvertFrom-Json | Out-Null
    Write-Host 'Compose, YAML/Kustomize, definitions.json, isolamento de portas e consistência JWT: OK.'
} finally { Pop-Location }
