# CI/CD no Azure — Fase 4

Os repositórios UsersAPI e CatalogAPI possuem o workflow `.github/workflows/fase4-ci-cd.yml` na branch `main`. Cada conta Azure utiliza seu proprio environment de GitHub Actions; use forks para permitir testes verdadeiramente independentes.

## Funcionamento

- Push em `feature/**` e pull request para `main`: restaura dependências, executa os testes .NET 10 e compila a imagem Docker linux/amd64 no runner. Não usa a assinatura Azure.
- Push em `main`: após os testes, autentica no Azure por OIDC, gera imagem com tag igual ao SHA do commit, envia ao ACR e atualiza o Deployment correspondente no namespace `fcg-fase4`.
- Execução manual (`workflow_dispatch`) só publica quando executada a partir da `main`.
- Se o AKS estiver parado, o job de publicação falha com uma mensagem informativa. O pipeline não inicia o AKS automaticamente.
- Se o rollout falhar, o job solicita rollback e retorna erro. É necessário verificar o estado da implantação.

O ACR Tasks não é utilizado. O build é feito no runner GitHub e a imagem é enviada via Docker.

## 1. Identidade Azure

A autenticação usa uma identidade gerenciada atribuída pelo usuário e credenciais federadas do GitHub, sem client secret.

O script abaixo configura uma identidade, duas credenciais federadas e duas permissões de escopo limitado. É necessária permissão para criar identidades e atribuir papéis no Azure. Execute somente quando decidir habilitar o deploy automático.

```powershell
az account show --query "{Name:name,Id:id}" -o table

.\infra\azure\setup-github-oidc.ps1 `
    -SubscriptionId (az account show --query id -o tsv) `
    -ResourceGroup rg-fcg-fase4-canadateste `
    -AksName aks-fcg-canadateste `
    -AcrName acrfcgcanadatestec733w2tny4nm6
```

O script reutiliza a identidade e as credenciais federadas existentes em execuções posteriores. A assinatura ativa deve corresponder à fornecida. Ele não modifica o AKS nem inicia VMs, mas cria uma identidade gerenciada e permissões IAM, se ainda não existirem.

Na assinatura de teste, a identidade `id-fcg-fase4-actions` foi criada em 30/10/2026 com permissões no ACR e AKS. O primeiro deploy da UsersAPI passou na validação, mas falhou em `azure/login` com `AADSTS700213`: o GitHub emitiu um subject OIDC com IDs imutáveis, enquanto o Azure tinha o formato antigo. O script foi corrigido para atualizar as duas credenciais existentes com os subjects mostrados abaixo. É necessário executá-lo novamente na assinatura antes de repetir o deploy.

Os IDs de organização e repositório usados nesses subjects pertencem aos repositórios do grupo e não à assinatura Azure de cada aluno. Ao mudar de conta Azure, reutilize os mesmos subjects para esses repositórios.

As permissões atribuídas são `AcrPush` somente no ACR e `Azure Kubernetes Service Cluster User Role` somente no AKS. A autorização Kubernetes do cluster também deve permitir atualizar os Deployments. Se a assinatura ou o tenant da FIAP bloquear criação de identidade ou atribuição de papéis, não insira credenciais pessoais no YAML: será preciso avaliar outro método de autenticação.

## 2. Configurar o GitHub

Nos **dois** repositórios, entre em `Settings > Environments` e crie o ambiente `azure-demo`. Restrinja o ambiente à branch `main`; se estiver disponível no plano, exija revisão antes de fazer deploy.

Cadastre no ambiente `azure-demo`:

| Tipo | Nome | Conteúdo |
|---|---|---|
| Secret | `AZURE_CLIENT_ID` | Client ID da identidade gerenciada |
| Secret | `AZURE_TENANT_ID` | Tenant ID da assinatura |
| Secret | `AZURE_SUBSCRIPTION_ID` | ID da assinatura Azure |
| Variable | `ACR_NAME` | Nome do ACR, sem `.azurecr.io` |
| Variable | `AKS_NAME` | Nome do cluster |
| Variable | `AKS_RESOURCE_GROUP` | Resource Group do cluster |

O script imprime os valores necessários ao final, mas não gera nem salva senhas. Nenhum desses valores deve ser incluído diretamente no workflow.

As credenciais federadas usam estes subjects:

```text
repo:TrezzeCloud@321194422/TrezzeCloud.UsersAPI@1243857293:environment:azure-demo
repo:TrezzeCloud@321194422/TrezzeCloud.CatalogAPI@1244703727:environment:azure-demo
```

Em cada nova assinatura estudantil, execute a configuração na conta correspondente e substitua os segredos e as variáveis do ambiente `azure-demo`. Isso evita editar os workflows ou inserir credenciais nos commits.

## Primeira publicação automatizada validada

Em 30/10/2026, a UsersAPI concluiu a primeira execução automática após corrigir o subject OIDC:
- Pipeline GitHub Actions [run #41111414981](https://github.com/TrezzeCloud/TrezzeCloud.UsersAPI/actions/runs/41111414981), tentativa 2: `success`.
- CI de validação aprovado (`.NET 10` e Docker).
- `azure/login` autenticou via OIDC com a identidade gerenciada.
- Imagem `trezzecloud-users-api:12284933a78352ec3bad08e30dbab3676b8ace7b` enviada ao ACR.
- `kubectl set image` executado e `deployment/users-api` apresentou `successfully rolled out`, com 1/1 Ready.

O PR #2 da CatalogAPI foi integrado à `main` em 30/10/2026 (commit `1450ab42e5b1bae2b2a9273208eba55acf21406d`). O workflow [run #41114425029](https://github.com/TrezzeCloud/TrezzeCloud.CatalogAPI/actions/runs/41114425029) concluiu com `success`: CI aprovado, autenticação Azure via OIDC, Docker build/push no ACR e `deployment/catalog-api` atualizado automaticamente com rollout concluído e 1/1 Ready. Imagem: `trezzecloud-catalog-api:1450ab42e5b1bae2b2a9273208eba55acf21406d`.

## Validacao de execucao manual e automatica da CatalogAPI

Em 30/10/2026, o [PR #6](https://github.com/TrezzeCloud/TrezzeCloud.CatalogAPI/pull/6) corrigiu o filtro `if` de `search_integration`, que anteriormente era ignorada em `workflow_dispatch` e impedia `publish_deploy` devido a dependencia `needs`. A correcao foi integrada a `main` no commit `43b43b1bcbaf27da487955abd01612199b011326`.

- [GitHub Actions por push #41140430463](https://github.com/TrezzeCloud/TrezzeCloud.CatalogAPI/actions/runs/41140430463): `validate`, `search_integration` e `publish_deploy` com `success`.
- [GitHub Actions manual #41140622341](https://github.com/TrezzeCloud/TrezzeCloud.CatalogAPI/actions/runs/41140622341): `validate`, `search_integration` e `publish_deploy` com `success` usando `workflow_dispatch` na `main`.

Estes testes comprovam o pipeline na **assinatura de referencia**. Para um fork pessoal, a identidade OIDC, os Secrets e Variables do environment `azure-demo` precisam pertencer ao integrante, e a publicacao deve ser validada novamente. O live deploy em video exige tambem alterar codigo no fork e demonstrar que a nova versao aparece na API.

## 3. Preparação para a primeira publicação automática

Antes de integrar os PRs à `main`:

1. Verifique se o CI das branches aprovou testes e Docker build.
2. Verifique se a identidade foi configurada, o ambiente `azure-demo` existe nos dois repositórios e os valores estão corretos.
3. Inicie o AKS manualmente e verifique `kubectl get nodes`.
4. Reaplique o manifesto da UsersAPI pelo `deploy-users-demo.ps1` para habilitar `RollingUpdate` (o manifesto anterior usava `Recreate`).
5. Verifique que os Deployments `users-api` e `catalog-api` existem no namespace `fcg-fase4`.
6. Faça merge somente após a revisão. Um push em `main` acionará a publicação automaticamente.

Após a publicação:

```powershell
kubectl -n fcg-fase4 get deployments
kubectl -n fcg-fase4 rollout status deployment/users-api
kubectl -n fcg-fase4 rollout status deployment/catalog-api
```

**Status atualizado:** os dois servicos foram publicados pelo GitHub Actions com OIDC e rolling update em 30/10/2026, inclusive as versoes com protecao de segredos. A CatalogAPI com Elasticsearch integrado tambem teve pipeline principal concluido com sucesso. A homologacao de forks e de assinaturas Azure diferentes nao esta comprovada por essa execucao. Consulte [GUIA-REPRODUCAO-E-VALIDACAO.md](GUIA-REPRODUCAO-E-VALIDACAO.md).

## Custo

A validação por PR não precisa do AKS ligado. Para o vídeo de demonstração, inicie o cluster manualmente antes do push na `main`. Ao terminar os testes, pare o AKS e acompanhe os custos dos discos e do ACR.
