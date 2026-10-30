param(
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$AksName,
    [Parameter(Mandatory = $true)][string]$AcrName,
    [string]$IdentityName = 'id-fcg-fase4-actions'
)

$ErrorActionPreference = 'Stop'

$selectedSubscription = az account show --query id -o tsv
if ($LASTEXITCODE -ne 0 -or $selectedSubscription.Trim() -ne $SubscriptionId) {
    throw 'A assinatura ativa no Azure CLI nao corresponde a SubscriptionId.'
}

$acrId = az acr show -g $ResourceGroup -n $AcrName --query id -o tsv
if ($LASTEXITCODE -ne 0 -or -not $acrId) {
    throw 'ACR nao encontrado na assinatura informada.'
}

$aksId = az aks show -g $ResourceGroup -n $AksName --query id -o tsv
if ($LASTEXITCODE -ne 0 -or -not $aksId) {
    throw 'AKS nao encontrado na assinatura informada.'
}

$tenantId = az account show --query tenantId -o tsv
$resourceLocation = az group show -n $ResourceGroup --query location -o tsv
if ($LASTEXITCODE -ne 0 -or -not $resourceLocation) {
    throw 'Resource Group nao encontrado.'
}

Write-Host "Assinatura: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Identidade: $IdentityName"
Write-Host 'A configuracao criara uma identidade gerenciada, federacao GitHub e permissoes no ACR e AKS.'
if ((Read-Host 'Digite CONFIGURAR para continuar') -ne 'CONFIGURAR') {
    Write-Host 'Cancelado.'
    return
}

$identitiesJson = az identity list -g $ResourceGroup -o json
if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar identidades gerenciadas.' }
$identities = @($identitiesJson | ConvertFrom-Json)
$identity = $identities | Where-Object { $_.name -eq $IdentityName } | Select-Object -First 1

if (-not $identity) {
    $identityJson = az identity create -g $ResourceGroup -n $IdentityName --location $resourceLocation -o json
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao criar identidade gerenciada. Verifique as permissoes e as politicas da assinatura.'
    }
    $identity = $identityJson | ConvertFrom-Json
}

$principalId = $identity.principalId
$clientId = $identity.clientId

if (-not $principalId -or -not $clientId) {
    throw 'Identidade criada sem principalId ou clientId valido.'
}

$credentialsJson = az identity federated-credential list -g $ResourceGroup --identity-name $IdentityName -o json
if ($LASTEXITCODE -ne 0) { throw 'Falha ao listar credenciais federadas.' }
$existingCredentials = @($credentialsJson | ConvertFrom-Json)

$repos = @(
    @{ Name = 'usersapi-azure-demo'; Subject = 'repo:TrezzeCloud/TrezzeCloud.UsersAPI:environment:azure-demo' },
    @{ Name = 'catalogapi-azure-demo'; Subject = 'repo:TrezzeCloud/TrezzeCloud.CatalogAPI:environment:azure-demo' }
)

foreach ($repo in $repos) {
    $existing = $existingCredentials | Where-Object { $_.name -eq $repo.Name } | Select-Object -First 1
    if ($existing) {
        if ($existing.subject -ne $repo.Subject) {
            throw "A credencial federada $($repo.Name) ja existe com outro subject."
        }
        Write-Host "Federacao ja existente: $($repo.Name)"
        continue
    }

    az identity federated-credential create --resource-group $ResourceGroup --identity-name $IdentityName --name $repo.Name --issuer 'https://token.actions.githubusercontent.com' --subject $repo.Subject --audiences 'api://AzureADTokenExchange' -o none
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao criar federacao $($repo.Name)."
    }
    Write-Host "Federacao criada: $($repo.Name)"
}

$roles = @(
    @{ Role = 'AcrPush'; Scope = $acrId },
    @{ Role = 'Azure Kubernetes Service Cluster User Role'; Scope = $aksId }
)

foreach ($item in $roles) {
    $existingAssignment = az role assignment list --scope $item.Scope --query "[?principalId=='$principalId' && roleDefinitionName=='$($item.Role)'].id" -o tsv
    if ($LASTEXITCODE -ne 0) { throw "Falha ao consultar permissao $($item.Role)." }

    if ($existingAssignment) {
        Write-Host "Permissao ja existente: $($item.Role)"
        continue
    }

    az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role $item.Role --scope $item.Scope -o none
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao atribuir $($item.Role). E necessario Owner ou User Access Administrator no escopo."
    }

    Write-Host "Permissao atribuida: $($item.Role)"
}

Write-Host ''
Write-Host 'Configure estes valores no GitHub Environment azure-demo dos DOIS repositorios:'
Write-Host 'Secrets:'
Write-Host "  AZURE_CLIENT_ID       = $clientId"
Write-Host "  AZURE_TENANT_ID       = $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID = $SubscriptionId"
Write-Host 'Variables:'
Write-Host "  ACR_NAME           = $AcrName"
Write-Host "  AKS_NAME           = $AksName"
Write-Host "  AKS_RESOURCE_GROUP = $ResourceGroup"
Write-Host ''
Write-Host 'Nenhum segredo de acesso foi gerado ou gravado em arquivo. A configuracao GitHub e manual.'
