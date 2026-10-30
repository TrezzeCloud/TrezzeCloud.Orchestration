# Fase 4 - Reproducao do zero, validacao final e desmobilizacao

**Para o apresentador que parte de uma maquina sem ferramentas instaladas, utilize primeiro o [guia integral independente](GUIA-INTEGRANTE-DO-ZERO.md).** Depois, siga o [roteiro de video](ROTEIRO-VIDEO-FASE4.md) e a [auditoria dos requisitos](AUDITORIA-REQUISITOS-FASE4.md). Este arquivo permanece como referencia tecnica adicional de infraestrutura e desmobilizacao.


Este guia e a referencia operacional para **cada integrante montar seu proprio ambiente**, testar e remover seus recursos. Foi escrito para PowerShell em Windows e para uma conta Azure com cota/permissao adequadas. O projeto usa AKS, ACR, SQL Server, RabbitMQ, UsersAPI, CatalogAPI, MongoDB, Redis, Traefik e Elasticsearch gerenciado externo.

**Importante:** uma execucao completa em outra assinatura ainda precisa ser comprovada. Os comandos aqui documentados foram reunidos a partir das implantacoes anteriores. Nao trate uma conta ou uma regiao como universalmente compativel: SKU, cota, IAM e planos podem variar. Nao exponha credenciais, tokens nem os valores de Kubernetes Secrets nos registros da entrega.

## 0. Escolher GitHub e Azure sem conflitar com colegas

- Cada integrante usa **sua propria assinatura Azure**, seu nome curto de recurso (MemberId) e sua propria instancia Elasticsearch gerenciada.
- Para **CI/CD verdadeiramente independente**, cada integrante deve trabalhar em forks proprios de UsersAPI e CatalogAPI, com GitHub Actions habilitado, e configurar seu proprio environment GitHub chamado azure-demo. Um environment azure-demo dos repositorios compartilhados do grupo e **um so**: mudar seus Secrets para outra assinatura altera o destino do deploy de todos. Se os repositorios compartilhados forem utilizados, somente um integrante configura ou executa deploy por vez, com coordenacao do grupo.
- O script setup-github-oidc.ps1 aceita os subjects do repositorio original por padrao, e parametros UsersOidcSubject/CatalogOidcSubject para forks. No GitHub com subject OIDC customizado (como os repositorios do grupo), o subject pode conter IDs imutaveis em vez do padrao owner/repo. Deve ser exatamente o valor emitido pelo job da propria conta. OIDC para forks nao esta homologado nesta assinatura; valide a federacao antes do primeiro live deploy.
- Nao use os nomes fixos canadateste em sua assinatura. Tudo o que foi provisionado nesse grupo foi um ambiente de teste, nao o ambiente dos colegas.

## 1. Pre-requisitos

Windows PowerShell 5.1 ou PowerShell 7, Git, .NET SDK 10, Docker Engine com Linux containers e permissao para executar Docker, Azure CLI (com Bicep), kubectl e Helm 3/4. Sua assinatura precisa aceitar AKS, ACR Basic, atribuicao de identidade e quotas suficientes para node Standard_D4_v4 ou outra VM valida. MongoDB e Redis sao containers no AKS; nao crie servicos externos para eles.

Garanta os 3 repositorios como pastas irmas com `main` atualizada:

~~~text
TrezzeCloud/
  TrezzeCloud.Orchestration/
  TrezzeCloud.UsersAPI/
  TrezzeCloud.CatalogAPI/
~~~

Em cada repositorio execute `git switch main` e `git pull --ff-only origin main`. Para forks, use os clones dos forks, mas mantenha os mesmos nomes das pastas locais.

Abra PowerShell na raiz de TrezzeCloud.Orchestration, execute `az login`, depois configure os valores **do proprio integrante**:

~~~powershell
$sub = "<SEU-SUBSCRIPTION-ID>"
$member = "aluno01"             # letras minusculas e numeros, 2 a 12
$location = "canadacentral"     # confirmar regiao permitida no seu plano
$vm = "Standard_D4_v4"          # confirmar cota, disponibilidade e preco
$rg = "rg-fcg-fase4-$member"
$aks = "aks-fcg-$member"
az account set --subscription $sub
az account show --query "{Name:name,Subscription:id}" -o table
~~~

A verificacao de cota/regiao cabe a cada conta; SKU listado nao garante quota AKS. Observe o custo da VM, disco, IP e registry.

## 2. Criar AKS e ACR

~~~powershell
.\infra\azure\deploy.ps1 -MemberId $member -SubscriptionId $sub -Location $location -VmSize $vm
~~~

O script exige confirmacoes CRIAR e IMPLANTAR, gera o Resource Group, Bicep, AKS Free e ACR Basic. Ele nao implanta as APIs.

~~~powershell
$acr = az acr list -g $rg --query "[0].name" -o tsv
$registry = az acr show -g $rg -n $acr --query loginServer -o tsv
az aks get-credentials -g $rg -n $aks --overwrite-existing
$context = (kubectl config current-context).Trim()
az aks update -g $rg -n $aks --attach-acr $acr
kubectl get nodes
~~~

Esperado: node Ready e nome do ACR resolvido. Se a atribuicao ACR falhar, verifique permissao IAM. **Nao prossiga** com o contexto kubectl ou assinatura errados. O AKS e ACR nao sao vinculados automaticamente pelo Bicep: a etapa attach-acr e obrigatoria para baixar imagens privadas.

## 3. Compilar, publicar e implantar as duas APIs

A partir da raiz de Orchestration com as pastas irmas, execute:

~~~powershell
dotnet test ..\TrezzeCloud.UsersAPI\TrezzeCloud.UsersAPI.slnx -c Release
dotnet test ..\TrezzeCloud.CatalogAPI\TrezzeCloud.CatalogAPI.slnx -c Release

& ..\TrezzeCloud.UsersAPI\scripts\publish-acr.ps1 -RegistryName $acr
& ..\TrezzeCloud.CatalogAPI\scripts\publish-acr.ps1 -RegistryName $acr

$usersCommit = git -C ..\TrezzeCloud.UsersAPI rev-parse --short HEAD
$catalogCommit = git -C ..\TrezzeCloud.CatalogAPI rev-parse --short HEAD
$usersImage = "$registry/trezzecloud-users-api:fase4-$usersCommit"
$catalogImage = "$registry/trezzecloud-catalog-api:fase4-$catalogCommit"

.\infra\azure\deploy-users-demo.ps1 -ExpectedContext $context -Image $usersImage
.\infra\azure\deploy-catalog-demo.ps1 -ExpectedContext $context -Image $catalogImage
~~~

Nao dependa de ACR Tasks, que podem estar bloqueados no Azure for Students: os scripts compilam via Docker local e fazem docker push. A ordem **Users primeiro, Catalog depois** e essencial: ambos compartilham SQL Server, RabbitMQ e a chave JWT gerada pelo users-demo-secrets. Os scripts armazenam senhas no Kubernetes Secret, nao nos repositorios. O SQL Server tem PVC de 10Gi, MongoDB tem PVC de 4Gi; Redis/RabbitMQ sao efemeros neste demo.

~~~powershell
.\infra\azure\validate-cloud-fase4.ps1 -SubscriptionId $sub -ResourceGroup $rg -AksName $aks -AcrName $acr -ExpectedContext $context
~~~

Este script exige os seis deployments 1/1 Ready, os dois PVCs Bound, cluster Running, ACR e Ingress presente. **Portanto rode-o so depois do passo 4 (Ingress).** Para checar somente os pods antes do Ingress: `kubectl -n fcg-fase4 get deploy,pods,pvc`.

## 4. Ingress HTTPS e acesso externo

~~~powershell
.\infra\azure\deploy-edge-demo.ps1 -ExpectedContext $context
kubectl -n fcg-ingress get deployment,service
kubectl -n fcg-fase4 get ingress fcg-apis
~~~

Teste interno: em um terminal separado, `kubectl -n fcg-ingress port-forward svc/fcg-traefik 8443:443`; em outro:

~~~powershell
curl.exe -k -i https://localhost:8443/api/games
curl.exe -k -i https://localhost:8443/api/users
~~~

Esperado: HTTP 200 e HTTP 401, respectivamente. O -k so e permitido no teste com certificado autossinado.

Para demonstrar acesso **externo** exigido pela FIAP, em ambiente temporario e apenas com dados ficticios:

~~~powershell
.\infra\azure\deploy-edge-demo.ps1 -ExpectedContext $context -Exposure Public -AllowSelfSignedDemo
kubectl -n fcg-ingress get service fcg-traefik
~~~

Digite PUBLICAR. Quando EXTERNAL-IP aparecer, acesse `https://<IP>/api/games` com `curl.exe -k -i` e confirme HTTP 200. Registre a evidencia e **volte para modo interno** com `deploy-edge-demo.ps1 -ExpectedContext $context`. Confira a liberacao do IP temporario no Resource Group gerenciado do AKS; um IP de saida do AKS pode continuar existindo e nao deve ser removido isoladamente.

## 5. Testes funcionais de Users, SQL, Redis, Mongo e cache

Mantenha dois port-forwards ativos, em **terminais separados**:

~~~powershell
kubectl -n fcg-fase4 port-forward svc/users-api 8080:8080
~~~

~~~powershell
kubectl -n fcg-fase4 port-forward svc/catalog-api 8081:8080
~~~

Em um terceiro terminal, na pasta Orchestration:

~~~powershell
.\infra\azure\test-users-demo.ps1
.\infra\azure\test-catalog-demo.ps1 -ExpectedContext $context
.\infra\azure\test-catalog-integrated.ps1 -ExpectedContext $context
~~~

Esperado: registro/login SQL e 401/403; GET de jogos HTTP 200; cache Redis preenchido com TTL; cadastro e atualizacao de jogo invalidam cache; usuario da UsersAPI acessa CatalogAPI com JWT; avaliacao persiste e pode ser lida no MongoDB. O teste integrado **cria dados ficticios**. Ele mede invalidacao e TTL, nao constitui benchmark de latencia: para o video, compare tambem observacoes de primeira e segunda consulta, sem afirmar ganho de tempo sem medicao.

## 6. Elasticsearch gerenciado (obrigatorio para a FIAP)

**Nao basta** o container Elasticsearch no CI: o enunciado exige Elastic Cloud/OpenSearch gerenciado. Configure sua propria conta e obtenha endpoint HTTPS e API key. O servico gerenciado e externo ao Resource Group Azure; pode ter cobranca ou prazo de trial independente.

~~~powershell
.\infra\azure\configure-catalog-search.ps1 -ExpectedContext $context -Endpoint "https://<SEU-ENDPOINT-ELASTIC>"
~~~

Cole a API key quando solicitada, sem exibi-la nem grava-la em Git. O script criara catalog-search-secrets e reiniciara CatalogAPI com configuracao opcional. Confirme o Deployment Ready e rode:

~~~powershell
.\infra\azure\validate-cloud-fase4.ps1 -SubscriptionId $sub -ResourceGroup $rg -AksName $aks -AcrName $acr -ExpectedContext $context -RequireElasticSecret
.\infra\azure\test-search-integrated.ps1 -ExpectedContext $context
~~~

O teste de busca faz login Admin, `POST /search/reindex` dos jogos existentes, cria jogo Cyber Drift, pesquisa `cybr drft`, atualiza para Ocean Quest, pesquisa `ocen qust`, desativa o jogo e verifica que ele nao aparece mais. **Somente marque como aprovado se esse teste passar contra o endpoint gerenciado real**. A busca deve responder HTTP 200; HTTP 503 indica indisponibilidade/configuracao ausente.

## 7. CI/CD e live deploy em conta independente

A branch `main` das APIs possui GitHub Actions: build/test, Docker com tag do commit, scan Trivy informativo, push ACR e rolling update no AKS. A CatalogAPI exige tambem `search_integration` real no CI antes de publicar.

Para cada integrante que usa forks: abra Settings > Environments dos **seus dois forks**, crie azure-demo, restrinja a main quando disponivel e obtenha os subjects OIDC emitidos pelos seus repositorios. Em configuracao OIDC padrao podem ser `repo:<owner>/<repo>:environment:azure-demo`; **nao use esse formato por suposicao** quando o orgao personaliza o subject. O script suporta explicitamente os parametros `-UsersOidcSubject` e `-CatalogOidcSubject`.

~~~powershell
.\infra\azure\setup-github-oidc.ps1 -SubscriptionId $sub -ResourceGroup $rg -AksName $aks -AcrName $acr
# Se estiver usando forks, adicione os dois parametros -UsersOidcSubject e -CatalogOidcSubject.
~~~

Copie os IDs mostrados para **Secrets** AZURE_CLIENT_ID, AZURE_TENANT_ID e AZURE_SUBSCRIPTION_ID, e para **Variables** ACR_NAME, AKS_NAME e AKS_RESOURCE_GROUP do environment azure-demo de cada repositorio. Sao configuracoes da conta de cada integrante, nao do codigo. Se qualquer etapa de IAM ou OIDC falhar, nao considere o deploy independente validado.

Para o video da FIAP, faca uma **alteracao de codigo verificavel** e commit na main do fork, com o AKS Running. Acompanhe GitHub Actions ate success, confira a imagem com tag do novo commit no ACR, o deployment atualizado e o endpoint respondendo. Evite alterar autenticação, segredos e banco apenas para demonstracao. Não execute pushes na main compartilhada do grupo sem combinar a janela de deploy.

~~~powershell
kubectl -n fcg-fase4 rollout status deployment/users-api
kubectl -n fcg-fase4 rollout status deployment/catalog-api
kubectl -n fcg-fase4 get deployment users-api catalog-api -o wide
~~~

O CI/CD ja foi aprovado na conta de referencia, mas o **teste com forks/contas independentes e um requisito de homologacao separado**. Nao confunda o teste manual via publish-acr.ps1 com o live deploy do pipeline.

## Evidencias da assinatura de referencia (30/10/2026)

Estes resultados foram observados no AKS da assinatura de referencia e **nao substituem a execucao individual em outras assinaturas**:

| Verificacao | Resultado observado |
|---|---|
| AKS, ACR, contexto Kubernetes e nodes | Validacao estrutural aprovada |
| SQL Server, RabbitMQ, UsersAPI, MongoDB, Redis e CatalogAPI | Seis Deployments 1/1 Ready |
| PersistentVolumeClaims SQL e Mongo | Ambos Bound |
| Ingress Traefik HTTPS interno | GET /api/games HTTP 200; GET /api/users sem JWT HTTP 401 |
| Teste UsersAPI | Registro, login persistido no SQL, 401 sem JWT e 403 para usuario comum |
| Teste CatalogAPI | GET /api/games HTTP 200 duas vezes; reviews HTTP 200 |
| Redis | Chave de cache com TTL de 219 s; invalidacao comprovada com TTL=-2 apos create e update |
| Teste funcional integrado | Login Admin, jogo criado no SQL (ID eac39653-ccf0-4700-a7b6-4c8614bd28a2), avaliacao Mongo HTTP 201, titulo atualizado HTTP 204, JWT da UsersAPI aceito pela CatalogAPI |
| CI/CD CatalogAPI com busca Elasticsearch integrada a main | GitHub Actions [#41129592869](https://github.com/TrezzeCloud/TrezzeCloud.CatalogAPI/actions/runs/41129592869) aprovado (build, testes, busca em motor real de CI, envio ACR e rollout AKS) |
| Busca em Elasticsearch gerenciado | **Aprovada em 30/10/2026**: Elastic Cloud Serverless no AKS; reindexacao de 12 jogos, fuzzy search, update e desativacao |
| Implantacao em uma assinatura Azure independente com forks GitHub | **Ainda nao executada** |

**Validacao adicional de 30/10/2026:** `validate-cloud-fase4.ps1 -RequireElasticSecret` confirmou assinatura correta, AKS Running, ACR, nodes Ready, seis Deployments 1/1 Ready, PVCs SQL/Mongo Bound, Ingress Traefik em modo `ClusterIP` e presenca das chaves Elasticsearch no Secret. `test-search-integrated.ps1` concluiu com `TESTE ELASTICSEARCH GERENCIADO APROVADO`. O teste de CI em container nao substitui o teste gerenciado — ambos foram executados separadamente. Um resultado "aprovado" so vale para o escopo indicado: a consulta Mongo HTTP 200 isolada nao comprova gravacao, que foi validada no teste integrado. A validacao estrutural nao substitui o teste HTTP externo do Ingress nem o live deploy do pipeline.

### Provisionar Elastic Cloud para o teste final

**Elastic Cloud Serverless no Azure (eastus2) foi validado em 30/10/2026** com a CatalogAPI executando no AKS em Canada Central. Os fluxos reais de indexacao, consulta fuzzy, atualizacao e desativacao foram aprovados. Elastic Cloud Hosted tambem e uma opcao, mas esta evidencia corresponde especificamente a **Serverless**, nao a Hosted. Cada integrante deve provisionar sua propria instancia e validar as condicoes de custo e trial.

1. Acesse [Elastic Cloud](https://cloud.elastic.co/), crie a organizacao e confira as condicoes de avaliacao e cobranca antes de ativar.
2. Crie um projeto **Elasticsearch Serverless** (configuracao validada) ou um deployment **Hosted** (alternativa a validar). Escolha uma regiao disponivel para o provedor, lembrando que a lista de regioes varia conforme a modalidade; a validacao do grupo usou Azure eastus2.
3. Em **Connection details > Endpoints**, copie o endpoint HTTPS especifico do Elasticsearch, nao o endereco Kibana.
4. Em **Connection details > API key**, crie uma chave propria de integracao em formato **Encoded** para a API REST. Chaves de organizacao e chaves de acesso a dados podem ter finalidades distintas. Nao coloque chaves em Git, logs, screenshots ou mensagens.
5. Habilite a CatalogAPI pelo `configure-catalog-search.ps1` do passo 6 e rode `test-search-integrated.ps1`. Esperado: `TESTE ELASTICSEARCH GERENCIADO APROVADO`.
6. No encerramento, revogue a chave, remova os recursos Elastic Cloud conforme a interface e valide se existe assinatura ou cobranca separada.

O trial da Elastic e independente da assinatura Azure for Students; confira a duracao e as condicoes da modalidade contratada, bem como eventuais cobrancas. Documentacao oficial: [Criar deployment Hosted](https://www.elastic.co/docs/deploy-manage/deploy/elastic-cloud/create-an-elastic-cloud-hosted-deployment), [Obter endpoint/chave](https://www.elastic.co/docs/solutions/search/set-up/api-key-and-endpoints), [Condicoes do trial](https://www.elastic.co/docs/deploy-manage/deploy/elastic-cloud/create-an-organization).

## 8. Checklist de evidencias, antes de apagar

Registre sem expor segredos: assinatura/regiao e AKS/ACR; seis deployments Ready; dois PVCs Bound; Ingress HTTPS interno e, na janela de demonstracao, LoadBalancer/IP externo e HTTP 200; HTTP 401 sem autenticacao; 401/403 autorizacao; testes de registro, jogos, Mongo e Redis; resultado do teste Elastic gerenciado; GitHub Actions com commit/tags e deploy success; rollout e resposta da API apos live deploy. Confirme relatorio com nomes do grupo, usernames Discord, links README, repos e video de ate 25 minutos.

**O que ainda precisa ocorrer apos seguir este guia:** execucao completa de ponta a ponta na conta de pelo menos outro integrante, em especial IAM/OIDC/fork, quota e trial Elastic. O sucesso de CI e de um cluster nao garante automaticamente que toda assinatura Azure aceitará o mesmo SKU/configuracao.

## 9. Destruir sem perder evidencias

Somente apos os testes, o video e o recolhimento de evidencias: confirme que nenhum integrante usa o cluster, registre o Resource Group e o AKS e **nao copie dados reais dos bancos**. Execute na raiz Orchestration:

~~~powershell
.\infra\azure\destroy.ps1 -MemberId $member -SubscriptionId $sub
~~~

Digite exatamente o nome do Resource Group para confirmar. O script solicita exclusao assíncrona de **todo o Resource Group, AKS, ACR, discos e dados**. Nao apague recursos individualmente antes, nem delete IP do AKS de saida enquanto o cluster existir. Confirme o resultado:

~~~powershell
az group exists --name $rg
az group list --query "[?contains(name,'fcg')].name" -o table
~~~

Espere `false` para o RG excluido; avalie Resource Groups gerenciados MC_ e qualquer recurso restante na assinatura sem excluir recursos de colegas. Recursos **externos** ao RG (Elastic Cloud/trial, dominio, GitHub Secrets/Environments, eventuais Function Apps de outra fase) precisam de limpeza e encerramento **separados**. A exclusao nao zera retroativamente custos ja apurados.

A infraestrutura pode ser recriada desde o passo 1 com outro MemberId e credenciais novas; dados excluidos nao sao restaurados pelo repositorio.
