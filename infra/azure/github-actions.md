# CI/CD no Azure — Fase 4

Os repositórios `TrezzeCloud.UsersAPI` e `TrezzeCloud.CatalogAPI` possuem `.github/workflows/fase4-ci-cd.yml` na branch `feature/fase4-ci`.

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

Na assinatura de teste, o script foi executado em 30/10/2026: a identidade `id-fcg-fase4-actions`, as duas credenciais federadas e as atribuições `AcrPush` e `Azure Kubernetes Service Cluster User Role` foram criadas. Ainda falta configurar o ambiente `azure-demo` nos repositórios e validar o primeiro login pelo GitHub Actions.

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
repo:TrezzeCloud/TrezzeCloud.UsersAPI:environment:azure-demo
repo:TrezzeCloud/TrezzeCloud.CatalogAPI:environment:azure-demo
```

Em cada nova assinatura estudantil, execute a configuração na conta correspondente e substitua os segredos e as variáveis do ambiente `azure-demo`. Isso evita editar os workflows ou inserir credenciais nos commits.

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

O primeiro deploy com OIDC ainda precisa ser validado na assinatura estudantil. O Azure for Students pode impor restrições adicionais e a configuração IAM pode exigir permissões indisponíveis aos alunos.

## Custo

A validação por PR não precisa do AKS ligado. Para o vídeo de demonstração, inicie o cluster manualmente antes do push na `main`. Ao terminar os testes, pare o AKS e acompanhe os custos dos discos e do ACR.
