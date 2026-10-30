# Fase 4 — Guia do integrante para reproduzir e demonstrar a FCG

**Objetivo:** reproduzir toda a infraestrutura e os testes usando a propria assinatura Azure, propria conta Elastic Cloud e proprios forks GitHub, sem depender de credenciais do ambiente de referencia. Elaborado para Windows com PowerShell.

**Status:** os testes foram aprovados na assinatura de referencia em 30/10/2026; a execucao integral em outra assinatura e com forks proprios ainda precisa ser comprovada.

## 1. Contas, portal Azure e custos

1. Entre em https://portal.azure.com com a SUA conta.
2. Abra **Subscriptions / Assinaturas > sua assinatura > Overview**. Identifique o seu Subscription ID e confirme que a assinatura esta ativa.
3. Verifique se voce tem permissao de criar Resource Group, AKS, ACR, identidade gerenciada e atribuicoes IAM. Conta Azure for Students pode ter limites de quota, regioes e SKUs.
4. Em **Cost Management + Billing**, examine seus creditos, estime o custo e crie um Budget com alertas, quando permitido. Alertas nao param automaticamente o consumo.
5. Tenha conta propria GitHub e Elastic Cloud. Elastic Cloud possui trial e cobranca independentes da assinatura Azure.
6. Na Fase 4 o cluster executa seis Deployments: SQL Server, RabbitMQ, UsersAPI, MongoDB, Redis e CatalogAPI. PaymentsAPI e Notifications.Functions nao sao implantados pelos manifests deste guia; nao afirme que os quatro microsservicos das fases anteriores rodam no AKS.

## 2. Instalar ferramentas no Windows

Em um PowerShell administrativo, quando ainda nao instaladas:

~~~powershell
winget install --exact --id Git.Git
winget install --exact --id Microsoft.AzureCLI
winget install --exact --id Microsoft.DotNet.SDK.10
winget install --exact --id Docker.DockerDesktop
winget install --exact --id Helm.Helm
winget install --exact --id Microsoft.PowerShell
~~~

Feche/reabra o terminal. Inicie Docker Desktop com WSL 2 e Linux containers. Em um PowerShell normal:

~~~powershell
az aks install-cli
az bicep install
git --version
az version
az bicep version
dotnet --list-sdks
docker info
kubectl version --client
helm version --short
~~~

Esperado: SDK 10 e todas as ferramentas respondendo. Em AKS com Microsoft Entra, se necessario, configure kubelogin com login Azure CLI. Nao use credenciais de administrador de outro integrante.

## 3. Forks pessoais e clone

No seu GitHub, faca Fork dos repositorios publicos:
- https://github.com/TrezzeCloud/TrezzeCloud.Orchestration
- https://github.com/TrezzeCloud/TrezzeCloud.UsersAPI
- https://github.com/TrezzeCloud/TrezzeCloud.CatalogAPI

O fork de Orchestration e recomendado. **Os forks UsersAPI e CatalogAPI sao indispensaveis para CI/CD com ambientes/Secrets independentes.** Sincronize sua main com o codigo oficial antes de comecar.

~~~powershell
$githubLogin = "SEU_USUARIO_GITHUB"
$root = "$HOME\Dev\TrezzeCloud"
New-Item -ItemType Directory -Force -Path $root | Out-Null
Set-Location $root
git clone "https://github.com/$githubLogin/TrezzeCloud.Orchestration.git"
git clone "https://github.com/$githubLogin/TrezzeCloud.UsersAPI.git"
git clone "https://github.com/$githubLogin/TrezzeCloud.CatalogAPI.git"
Set-Location "$root\TrezzeCloud.Orchestration"
~~~

As tres pastas precisam ficar irmas. Se nao houver fork da Orchestration, pode clonar o repositorio publico original apenas para executar scripts.

## 4. Selecionar sua assinatura e criar AKS/ACR

~~~powershell
az login
az account list -o table
$sub = "SEU_SUBSCRIPTION_ID"
$member = "aluno02"
$location = "canadacentral"
$vm = "Standard_D4_v4"
$rg = "rg-fcg-fase4-$member"
$aks = "aks-fcg-$member"
az account set --subscription $sub
az account show --query "{Name:name,Id:id,Tenant:tenantId}" -o table
az vm list-skus --location $location --resource-type virtualMachines --size $vm -o table
az bicep build --file .\infra\azure\main.bicep
.\infra\azure\deploy.ps1 -MemberId $member -SubscriptionId $sub -Location $location -VmSize $vm
~~~

**Substitua todos os valores de exemplo pelos seus.** MemberId so pode ter de 2 a 12 caracteres minusculos/numeros. Region e VM devem ser permitidos pela sua quota e ter custo aceitavel. O script pede **CRIAR**, exibe um plano what-if, depois pede **IMPLANTAR**. Nao execute se o plano nao for adequado.

No portal Azure abra **Resource groups > rg-fcg-fase4-SEU_MEMBER**, depois **Kubernetes services** e **Container registries** para conferir os recursos.

~~~powershell
$acr = (az acr list -g $rg --query "[0].name" -o tsv).Trim()
$registry = (az acr show -g $rg -n $acr --query loginServer -o tsv).Trim()
az aks get-credentials -g $rg -n $aks --overwrite-existing
$context = (kubectl config current-context).Trim()
az aks update -g $rg -n $aks --attach-acr $acr
kubectl get nodes
az aks show -g $rg -n $aks --query powerState.code -o tsv
~~~

Esperado: node Ready, AKS Running e contexto correspondente ao seu cluster. O attach-acr habilita o AKS a baixar imagens do seu registry. Falha de quota, politica ou IAM exige resolver na propria assinatura.

## 5. Testar, publicar e implantar as duas APIs

Na raiz da Orchestration, com Docker Engine funcionando:

~~~powershell
dotnet test ..\TrezzeCloud.UsersAPI\TrezzeCloud.UsersAPI.slnx -c Release
dotnet test ..\TrezzeCloud.CatalogAPI\TrezzeCloud.CatalogAPI.slnx -c Release
& ..\TrezzeCloud.UsersAPI\scripts\publish-acr.ps1 -RegistryName $acr
& ..\TrezzeCloud.CatalogAPI\scripts\publish-acr.ps1 -RegistryName $acr
$usersCommit = (git -C ..\TrezzeCloud.UsersAPI rev-parse --short HEAD).Trim()
$catalogCommit = (git -C ..\TrezzeCloud.CatalogAPI rev-parse --short HEAD).Trim()
$usersImage = "$registry/trezzecloud-users-api:fase4-$usersCommit"
$catalogImage = "$registry/trezzecloud-catalog-api:fase4-$catalogCommit"
.\infra\azure\deploy-users-demo.ps1 -ExpectedContext $context -Image $usersImage
.\infra\azure\deploy-catalog-demo.ps1 -ExpectedContext $context -Image $catalogImage
kubectl -n fcg-fase4 get deployments
kubectl -n fcg-fase4 get pods,pvc
~~~

Os scripts publicam pelo Docker local e evitam depender de ACR Tasks. Execute **Users antes do Catalog**: os Secrets de passwords e JWT compartilhado sao gerados no seu AKS, e a CatalogAPI reutiliza o JWT da UsersAPI. **Nao copie nem substitua passwords no codigo, appsettings ou YAML.** Esperado: seis Deployments 1/1 Ready e PVCs sqlserver-data e mongodb-data Bound.

## 6. Ingress HTTPS privado e testes funcionais

~~~powershell
.\infra\azure\deploy-edge-demo.ps1 -ExpectedContext $context
kubectl -n fcg-ingress get deployments,services
kubectl -n fcg-fase4 get ingress fcg-apis
~~~

Em um terminal separado:

~~~powershell
kubectl -n fcg-ingress port-forward svc/fcg-traefik 8443:443
~~~

Em outro terminal:

~~~powershell
curl.exe -k -i https://localhost:8443/api/games
curl.exe -k -i https://localhost:8443/api/users
~~~

Esperado: HTTP 200 em jogos e 401 em Users sem JWT. -k ignora certificado autossinado apenas no teste.

Para os testes seguintes, abra dois port-forwards simultaneos, mantendo cada comando em seu terminal:

~~~powershell
# Terminal 1
kubectl -n fcg-fase4 port-forward svc/users-api 8080:8080
# Terminal 2, em outra janela
kubectl -n fcg-fase4 port-forward svc/catalog-api 8081:8080
~~~

Em um terceiro terminal, na Orchestration:

~~~powershell
.\infra\azure\test-users-demo.ps1
.\infra\azure\test-catalog-demo.ps1 -ExpectedContext $context
.\infra\azure\test-catalog-integrated.ps1 -ExpectedContext $context
~~~

Registre registro/login, HTTP 401/403, SQL Server, Redis TTL/hit/invalidation, avaliacao criada/lida no MongoDB e compartilhamento de JWT. Os scripts usam dados ficticios. Nao mostre JWT nem valores de Kubernetes Secrets.
