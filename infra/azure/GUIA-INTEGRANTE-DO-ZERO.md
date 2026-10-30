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

## 7. Criar seu Elastic Cloud e copiar sua API Key

1. Acesse https://cloud.elastic.co com **sua conta**. Confira trial e cobranca, separados do Azure.
2. Crie projeto **Elasticsearch Serverless** (tipo Elasticsearch, nao Observability/Security); escolha provedor e regiao disponiveis. A referencia usou Azure eastus2, mas nao e obrigatorio reproduzir a regiao.
3. Em **Ver detalhes da conexao > Endpoints**, copie o endpoint HTTPS de **Elasticsearch** (nao o de Kibana).
4. Em **API Key / Chave de API**, crie chave chamada, por exemplo, fcg-catalog-aluno02, em formato **Encoded**. Ela pode ser exibida uma unica vez. Chaves do painel simplificado da Elastic expiram em 90 dias, segundo a documentacao atual.
5. Guarde a chave em local seguro; **nunca** cole em mensagem, YAML, appsettings, GitHub Secrets do pipeline, logs ou gravacao. O script recebe a chave por entrada oculta e grava no Secret do seu Kubernetes.

Na Orchestration:

~~~powershell
$elasticUrl = (Read-Host "Cole seu endpoint HTTPS de Elasticsearch").TrimEnd("/")
.\infra\azure\configure-catalog-search.ps1 -ExpectedContext $context -Endpoint $elasticUrl
# Digite sua API Key somente no prompt oculto do script.
kubectl -n fcg-fase4 rollout status deployment/catalog-api --timeout=360s
.\infra\azure\validate-cloud-fase4.ps1 -SubscriptionId $sub -ResourceGroup $rg -AksName $aks -AcrName $acr -ExpectedContext $context -RequireElasticSecret
# Com port-forwards Users:8080 e Catalog:8081 ativos:
.\infra\azure\test-search-integrated.ps1 -ExpectedContext $context
~~~

Esperado: **TESTE ELASTICSEARCH GERENCIADO APROVADO**. O script reindexa jogos do SQL, cria um jogo, executa fuzzy search com erro de digitacao, atualiza e desativa. A quantidade de jogos nao precisa ser igual aos 12 da referencia. HTTP 503 indica problema de acesso/configuracao Elastic.

## 8. GitHub Actions com identidade federada na sua conta (OIDC)

Em **cada fork** UsersAPI e CatalogAPI: GitHub > **Settings > Environments > New environment**, crie **azure-demo** e, quando disponivel, restrinja deployment a **main**. Habilite Actions no fork.

O script de federacao possui, como DEFAULT, os subjects do repositorio oficial da organizacao TrezzeCloud. **Em forks pessoais voce deve fornecer os subjects proprios**. Para OIDC GitHub com formato usual, os valores candidatos sao:

~~~powershell
$usersSubject = "repo:$githubLogin/TrezzeCloud.UsersAPI:environment:azure-demo"
$catalogSubject = "repo:$githubLogin/TrezzeCloud.CatalogAPI:environment:azure-demo"
.\infra\azure\setup-github-oidc.ps1 -SubscriptionId $sub -ResourceGroup $rg -AksName $aks -AcrName $acr -UsersOidcSubject $usersSubject -CatalogOidcSubject $catalogSubject
~~~

Confirme **CONFIGURAR**. O script cria/reutiliza uma identidade gerenciada sua, com AcrPush no seu ACR e Azure Kubernetes Service Cluster User Role no seu AKS.

**Atenção:** alguns repositorios tem subjects customizados com IDs imutaveis. Se ocorrer **AADSTS700213**, consulte o subject real mencionado no erro da pipeline e refaca a federacao usando o valor exato do token emitido pelo **seu fork**. Nao copie os subjects da organizacao. O RBAC Kubernetes tambem precisa permitir atualizar os Deployments, podendo exigir outra atribuicao conforme a configuracao da assinatura.

Em **cada fork > Settings > Environments > azure-demo**, crie:

| Tipo | Nome | Valor |
|---|---|---|
| Secret | AZURE_CLIENT_ID | Client ID da sua identidade gerenciada |
| Secret | AZURE_TENANT_ID | Tenant ID da sua assinatura |
| Secret | AZURE_SUBSCRIPTION_ID | ID da sua assinatura |
| Variable | ACR_NAME | Nome do seu ACR sem dominio |
| Variable | AKS_NAME | Nome do seu AKS |
| Variable | AKS_RESOURCE_GROUP | Seu RG |

O script imprime os IDs para copiar nas configuracoes. **Nao** transfira senhas SQL/Mongo/Redis/RabbitMQ, JWT ou API Key Elastic para a pipeline: esses runtime Secrets estao no seu AKS.

Em GitHub **Actions > workflow CI/CD > Run workflow > main**, acompanhe validate, search_integration (CatalogAPI) e publish_deploy. O workflow faz build/test, Docker, login via OIDC, push da imagem com tag do commit SHA e rolling update. **O workflow nao cria AKS nem inicia um AKS parado**; o bootstrap foi feito nos passos anteriores.

## 9. Live deploy real para a gravacao

A FIAP exige **alterar codigo, dar push e mostrar a pipeline atualizando a aplicacao na nuvem**. No seu fork CatalogAPI (nunca na main do grupo):

1. Abra **src/TrezzeCloud.Catalog.Api/Controller/GameSearchController.cs**.
2. No metodo **Search**, imediatamente antes de **return Ok(items);**, adicione temporariamente esta linha:

~~~csharp
Response.Headers["X-FCG-Fase4-Demo"] = "live-deploy-aluno02";
~~~

3. No seu clone CatalogAPI:

~~~powershell
Set-Location "$root\TrezzeCloud.CatalogAPI"
git remote -v
git switch main
dotnet test .\TrezzeCloud.CatalogAPI.slnx -c Release
git add .\src\TrezzeCloud.Catalog.Api\Controller\GameSearchController.cs
git commit -m "demo(fase4): comprovar live deploy no meu fork"
git push origin main
~~~

Se a main estiver protegida, use feature/PR/merge **no seu fork**; o deploy so ocorre quando a main do fork for atualizada. Grave **Actions** executando ate success, o ACR com a **nova imagem/tag SHA**, **rollout status** no AKS e a resposta HTTP /search contendo o header **X-FCG-Fase4-Demo**. O push manual inicial de imagem do passo 5 **nao substitui** o live deploy.

## 10. Exposicao HTTPS publica somente durante a demonstracao

Na Orchestration e usando somente dados ficticios:

~~~powershell
Set-Location "$root\TrezzeCloud.Orchestration"
.\infra\azure\deploy-edge-demo.ps1 -ExpectedContext $context -Exposure Public -AllowSelfSignedDemo
kubectl -n fcg-ingress get svc fcg-traefik
$ip = (kubectl -n fcg-ingress get svc fcg-traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}').Trim()
curl.exe -k -i "https://$ip/api/games"
curl.exe -k -i "https://$ip/api/users"
curl.exe -k -i "https://$ip/search?q=cybr%20drft"
~~~

Aguarde **EXTERNAL-IP** real. Esperado: 200 em jogos, 401 Users sem token, 200 em search (pode ter lista vazia), e depois do live deploy o header novo. **-k** ignora o certificado autossinado somente neste teste. HTTPS confiavel em navegador sem alertas necessita dominio, DNS e certificado TLS valido, que os scripts nao provisionam.

## 11. Validacao final e evidencias

Com Ingress Public e Elasticsearch configurado:

~~~powershell
.\infra\azure\validate-cloud-fase4.ps1 -SubscriptionId $sub -ResourceGroup $rg -AksName $aks -AcrName $acr -ExpectedContext $context -RequireElasticSecret -RequirePublicIngress
kubectl -n fcg-fase4 get pods,deploy,pvc,ingress
kubectl -n fcg-fase4 get deployment users-api catalog-api -o wide
az acr repository list -n $acr -o table
~~~

Grave as evidencias: Azure Portal/AKS/ACR, nodes Ready, seis Deployments Ready e PVC Bound, IP/Ingress HTTPS, JWT e 401/403, SQL Server, TTL/invalidation no Redis, avaliacao MongoDB, Elastic com reindexacao/fuzzy, GitHub Actions, nova tag ACR, rollout e novo header apos live deploy. Consulte o [roteiro do video](ROTEIRO-VIDEO-FASE4.md).

O script validate-cloud-fase4 confirma **estrutura**, nao substitui os testes funcionais. Nao mostre API keys, passwords, JWTs nem valor decodificado de Secrets.

## 12. Encerrar e evitar cobrancas

Apos gravacao, volte o Ingress ao modo privado:

~~~powershell
.\infra\azure\deploy-edge-demo.ps1 -ExpectedContext $context
kubectl -n fcg-ingress get svc fcg-traefik
~~~

Apos salvar video/evidencias e coordenar com o grupo, exclua **seu** RG:

~~~powershell
.\infra\azure\destroy.ps1 -MemberId $member -SubscriptionId $sub
az group exists --name $rg
~~~

O script exige confirmar exatamente o nome do RG e remove dados, AKS, ACR e recursos desse grupo. Aguarde **false**. **Elastic Cloud e externo ao RG**: revogue a chave e encerre seu projeto/trial na interface Elastic. Se apenas parar AKS, ainda podem existir custos com discos, registry e rede. Nunca remova recursos de outro integrante.

## 13. Erros frequentes

| Problema | Verificacao |
|---|---|
| Comando az, dotnet, helm ou kubectl desconhecido | Reabrir terminal; verificar PATH/instalacao |
| Docker Engine indisponivel | Abrir Docker Desktop; verificar WSL 2/Linux containers |
| SKU/AKS nao provisiona | Checar quota, regiao, politica e custos da sua assinatura |
| ACR ImagePullBackOff | Confirmar tag da imagem no seu registry e attach-acr |
| Deployment 0/1 | kubectl describe pod; kubectl logs deployment/NOME |
| AADSTS700213 | Subject real do OIDC de seu fork incorreto |
| Pipeline sem deploy | Exige main, azure-demo, AKS Running e Deployment existente |
| 403 no job de deploy | Revisar RBAC Kubernetes da identidade federada |
| HTTP 503 em /search | Verificar Secret, endpoint, API key e permissao Elastic |
| IP publico pending | Verificar quota do LoadBalancer, Service e eventos |
| Alerta TLS | Certificado e autossinado na demo; -k somente em testes |

## Referencias oficiais

- Azure CLI: https://learn.microsoft.com/pt-br/cli/azure/install-azure-cli-windows
- .NET 10: https://learn.microsoft.com/pt-br/dotnet/core/install/windows
- AKS e kubectl: https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-deploy-cluster
- Docker Desktop: https://docs.docker.com/desktop/setup/install/windows-install/
- Elastic Serverless: https://www.elastic.co/docs/deploy-manage/deploy/elastic-cloud/create-serverless-project
- Endpoint/API Key: https://www.elastic.co/docs/solutions/search/set-up/api-key-and-endpoints
- Azure Students: https://learn.microsoft.com/pt-br/azure/education-hub/about-azure-for-students
- Budgets: https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets
- AKS parar/iniciar: https://learn.microsoft.com/pt-br/azure/aks/start-stop-cluster

**Limite da validacao:** todos os passos foram revisados com os scripts versionados, mas o teste completo em um fork e assinatura totalmente independentes ainda precisa ser executado pelo apresentador.
