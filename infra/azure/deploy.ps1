param(
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9]{2,12}$')][string]$MemberId,
 [Parameter(Mandatory=$true)][string]$SubscriptionId,
 [string]$Location = 'canadacentral',
 [Parameter(Mandatory=$true)][string]$VmSize,
 [int]$NodeCount = 1
)
$ErrorActionPreference = 'Stop'
if ($NodeCount -lt 1 -or $NodeCount -gt 3) { throw 'NodeCount deve estar entre 1 e 3.' }
$rg = "rg-fcg-fase4-$MemberId"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Execute az login e confira a subscription.' }
Write-Host "Subscription: $(az account show --query name -o tsv) | RG: $rg | Region: $Location | VM: $VmSize | Nodes: $NodeCount"
$availableSku = az vm list-skus --location $Location --resource-type virtualMachines --size $VmSize --query "[?name=='$VmSize'].name" -o tsv
if ($LASTEXITCODE -ne 0 -or -not $availableSku) { throw "VM $VmSize nao esta disponivel na consulta de SKUs para $Location. Nenhum recurso foi criado." }
Write-Host 'A listagem de SKUs nao garante quota ou aceitacao pelo AKS.'
Write-Host 'ATENCAO: recursos cobram mesmo com plano AKS Free. Consulte preco e quota antes de criar.'
if ((Read-Host 'Digite CRIAR') -cne 'CRIAR') { throw 'Cancelado' }
az group create -n $rg -l $Location -o none
if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar RG' }
az deployment group what-if -g $rg -f "$PSScriptRoot/main.bicep" -p memberId=$MemberId nodeCount=$NodeCount vmSize=$VmSize
if ($LASTEXITCODE -ne 0) { throw 'Falha no what-if' }
if ((Read-Host 'Confira a estimativa de custos e digite IMPLANTAR') -cne 'IMPLANTAR') { throw 'Cancelado; verifique se RG vazio deve ser removido.' }
az deployment group create -g $rg -f "$PSScriptRoot/main.bicep" -p memberId=$MemberId nodeCount=$NodeCount vmSize=$VmSize
if ($LASTEXITCODE -ne 0) { throw 'Falha no deployment; revise recursos parcialmente criados.' }
Write-Host "Criado RG $rg. Consulte AKS/ACR no portal e configure a integracao ACR conforme README."
