param(
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9]{2,12}$')][string]$MemberId,
 [Parameter(Mandatory=$true)][string]$SubscriptionId
)
$ErrorActionPreference = 'Stop'
$rg = "rg-fcg-fase4-$MemberId"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Assinatura indisponivel.' }
Write-Host "ATENCAO: apagara todos os recursos e dados do Resource Group $rg. Verifique o conteudo no portal."
if ((Read-Host "Digite exatamente $rg para confirmar") -cne $rg) { throw 'Cancelado.' }
az group delete --name $rg --yes --no-wait
if ($LASTEXITCODE -ne 0) { throw 'Falha ao solicitar exclusao' }
Write-Host 'Exclusao solicitada. Confirme no portal que terminou; recursos externos ao RG exigem limpeza separada.'
