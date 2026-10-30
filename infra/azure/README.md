# Infraestrutura Azure — Fase 4

Os templates desta pasta criam um AKS e um Azure Container Registry (ACR). O ambiente é temporário e será usado para validar a publicação da FCG na nuvem.

O código da infraestrutura não depende de uma assinatura específica. A assinatura é informada na execução dos scripts; nenhuma credencial é armazenada no repositório.

## Escopo atual

- AKS com plano de gerenciamento Free e um node pool inicial.
- ACR Basic sem usuário administrador.
- Scripts PowerShell para criar e excluir o Resource Group.
- Workflow para compilar os arquivos Bicep.

A UsersAPI já foi validada no AKS com SQL Server e RabbitMQ. CatalogAPI, MongoDB e Redis foram implantados em `fcg-fase4`, com os três pods `Ready` e PVC do MongoDB `Bound`. Foram concluídos testes funcionais de leitura, cadastro e atualização, incluindo SQL Server, Redis, MongoDB e autenticação JWT compartilhada. Pipelines completos de UsersAPI e CatalogAPI foram validados. A busca Elasticsearch está implementada em uma feature da CatalogAPI e aguarda teste com serviço gerenciado. O ingress HTTPS está preparado para a próxima validação, e Azure Functions ainda será revisado conforme o escopo da fase.

A assinatura usada nos testes permite apenas eastus2, southcentralus, chilecentral, canadacentral e mexicocentral. A validação e o provisionamento de AKS com um nó Standard_D4_v4 e ACR Basic foram concluídos em Canada Central nesta assinatura. O nó ficou `Ready` e os pods de sistema estavam `Running`. Esse resultado não garante a mesma configuração em outras assinaturas. A região continua sendo um parâmetro, pois outras assinaturas podem ter políticas diferentes.

## Validação inicial

Pré-requisitos: Azure CLI, PowerShell, kubectl e uma assinatura com permissões e quota suficientes.

```powershell
az login
az account list -o table
az bicep build --file infra/azure/main.bicep
```

Antes de provisionar, verificar a disponibilidade da VM escolhida, a quota da assinatura e os preços na região. O SKU deve ser informado explicitamente. Uma configuracao de um unico no e apenas tentativa para demonstracao: a API do AKS pode recusar a contagem de nos ou o SKU, mesmo que a VM esteja na lista.

Para a assinatura de testes, o Resource Group e os recursos devem ficar em uma região permitida. O grupo de testes criado anteriormente em Brazil South não deve ser reutilizado. Crie um novo grupo em Canada Central e valide o template antes de executar o script de implantação.

Na raiz do repositório:

```powershell
./infra/azure/deploy.ps1 -MemberId canadateste -SubscriptionId "<subscription-id>" -Location canadacentral -VmSize "Standard_D4_v4"
```

O script mostra o plano de implantação e pede confirmação antes de criar o AKS e o ACR.

Depois de provisionar:

```powershell
$rg = "rg-fcg-fase4-canadateste"
az resource list -g $rg -o table
az aks list -g $rg -o table
az acr list -g $rg -o table
```

O AKS foi acessado com `az aks get-credentials`. O nó de sistema foi verificado como `Ready`, os pods em `kube-system` estavam `Running` e o ACR foi confirmado como `Succeeded`. O AKS foi associado ao ACR com `az aks update --attach-acr`. O teste `az aks check-acr` no Cloud Shell confirmou resolução DNS, identidade gerenciada e permissão para baixar imagens privadas. A imagem da UsersAPI foi publicada no ACR e o deployment com SQL Server e RabbitMQ foi concluído.

## CI/CD

Os pipelines CI/CD estão integrados à `main` dos repositórios UsersAPI e CatalogAPI. O CI executa testes e build Docker sem acesso ao Azure; o deploy automático via OIDC, ACR e rolling update no AKS foi validado em ambos os serviços.

Para configurar a identidade gerenciada, as credenciais federadas e as variáveis de cada assinatura, consulte `infra/azure/github-actions.md` e `infra/azure/setup-github-oidc.ps1`. Esses recursos foram provisionados e os dois deployments automáticos validados na assinatura de testes. O estado atual do AKS deve ser verificado com `az aks show` antes de qualquer operação.

## Exposição externa por Ingress Controller

A entrada HTTP(S) foi preparada com Traefik Proxy e chart Helm 42.1.3, sem depender do projeto ingress-nginx (encerrado em 2026). Por segurança e economia, o modo padrão é **interno** (`ClusterIP`, sem IP público). Para demonstrar o requisito obrigatório de acesso externo, o instalador pode configurar **um único** Service `LoadBalancer` com HTTPS e confirmação explícita. UsersAPI e CatalogAPI permanecem internos. Nenhum recurso público foi criado por esta atualização.

Consulte [k8s/cloud/edge-demo/README.md](../../k8s/cloud/edge-demo/README.md). Scripts: `infra/azure/deploy-edge-demo.ps1` e `infra/azure/destroy-edge-demo.ps1`. Antes da exposição pública, configure TLS confiável e avalie custos de IP público e Load Balancer.

## Remoção

Ao terminar o teste:

```powershell
./infra/azure/destroy.ps1 -MemberId canadateste -SubscriptionId "<subscription-id>"
```

O script solicita a confirmação do nome do Resource Group. A exclusão remove também os dados armazenados nele. Verificar no Portal se o grupo foi completamente excluído.

## Custos e limitações

O grupo utiliza assinaturas Azure for Students, cada uma com seu próprio crédito de US$ 100. O desenvolvimento e os testes iniciais serão feitos em uma única assinatura. Depois da validação, será preparado um manual separado para reproduzir o ambiente nas demais contas.

O AKS Free não inclui gratuitamente as VMs, discos, rede ou o ACR. A infraestrutura deve permanecer ativa somente durante os testes. Conferir o saldo e o consumo no Cost Management.

## Publicação de imagens

O build remoto com `az acr build` foi bloqueado pela assinatura estudantil (`TasksOperationsNotAllowed`). Para publicar imagens no ACR, executar o Docker localmente e enviar com `docker push`, sem depender de ACR Tasks.

A UsersAPI possui `scripts/publish-acr.ps1` na branch `main`. O script autentica com `az acr login`, gera uma tag baseada no commit Git e publica no registry. A automação por GitHub Actions já constrói e publica a imagem no runner, sem chamar `az acr build`.

Créditos Azure for Students não cobrem ofertas do Azure Marketplace. Isso precisa ser considerado na escolha do serviço gerenciado de Elasticsearch. O RabbitMQ Trigger das Azure Functions exige um plano de hospedagem compatível e também pode representar custo significativo.

**Status:** AKS, ACR, UsersAPI, SQL Server e RabbitMQ funcionando. Swagger HTTP 200, acesso sem autenticação HTTP 401 e testes de cadastro, login e permissão concluídos (401/403). CatalogAPI, MongoDB e Redis implantados; testes integrados de leitura, cadastro/atualização, JWT entre APIs, avaliação em MongoDB e invalidação do Redis aprovados em 30/10/2026. A exposição externa e a integração Elasticsearch com serviço gerenciado ainda dependem de validação, apesar da infraestrutura e do código já preparados.
