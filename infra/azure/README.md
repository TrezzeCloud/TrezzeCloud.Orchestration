# Infraestrutura Azure — Fase 4

Os templates desta pasta criam um AKS e um Azure Container Registry (ACR). O ambiente é temporário e será usado para validar a publicação da FCG na nuvem.

O código da infraestrutura não depende de uma assinatura específica. A assinatura é informada na execução dos scripts; nenhuma credencial é armazenada no repositório.

## Escopo atual

- AKS com plano de gerenciamento Free e um node pool inicial.
- ACR Basic sem usuário administrador.
- Scripts PowerShell para criar e excluir o Resource Group.
- Workflow para compilar os arquivos Bicep.

A implantação dos microsserviços, bancos, Gateway, busca e Azure Functions será adicionada nas próximas etapas.

## Validação inicial

Pré-requisitos: Azure CLI, PowerShell, kubectl e uma assinatura com permissões e quota suficientes.

```powershell
az login
az account list -o table
az bicep build --file infra/azure/main.bicep
```

Antes de provisionar, verificar a disponibilidade da VM escolhida, a quota da assinatura e os preços na região. O SKU padrão é `Standard_D4as_v5`; pode ser necessário alterá-lo.

Na raiz do repositório:

```powershell
./infra/azure/deploy.ps1 -MemberId fase4teste -SubscriptionId "<subscription-id>" -Location brazilsouth
```

O script mostra o plano de implantação e pede confirmação antes de criar o AKS e o ACR.

Depois de provisionar:

```powershell
$rg = "rg-fcg-fase4-fase4teste"
az resource list -g $rg -o table
az aks list -g $rg -o table
az acr list -g $rg -o table
```

A configuração de acesso do AKS ao ACR e a publicação dos serviços serão incluídas na próxima etapa.

## Remoção

Ao terminar o teste:

```powershell
./infra/azure/destroy.ps1 -MemberId fase4teste -SubscriptionId "<subscription-id>"
```

O script solicita a confirmação do nome do Resource Group. A exclusão remove também os dados armazenados nele. Verificar no Portal se o grupo foi completamente excluído.

## Custos e limitações

O grupo utiliza assinaturas Azure for Students, cada uma com seu próprio crédito de US$ 100. O desenvolvimento e os testes iniciais serão feitos em uma única assinatura. Depois da validação, será preparado um manual separado para reproduzir o ambiente nas demais contas.

O AKS Free não inclui gratuitamente as VMs, discos, rede ou o ACR. A infraestrutura deve permanecer ativa somente durante os testes. Conferir o saldo e o consumo no Cost Management.

Créditos Azure for Students não cobrem ofertas do Azure Marketplace. Isso precisa ser considerado na escolha do serviço gerenciado de Elasticsearch. O RabbitMQ Trigger das Azure Functions exige um plano de hospedagem compatível e também pode representar custo significativo.

**Status:** templates criados, ainda sem validação de compilação e sem implantação em uma assinatura real.
