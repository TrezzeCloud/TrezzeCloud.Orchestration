# Fase 4: Azure temporario por integrante

Este primeiro pacote provisiona SOMENTE AKS Free tier (controle) e ACR Basic. O deploy completo, segredos, persistencia, Elasticsearch, Datadog e Functions virão nas etapas seguintes.

## Limite US$ 100
AKS Free nao isenta cobrancas por nos VM, discos, rede, IP, registry e servicos externos. Consulte calculadora oficial Azure e Cost Management antes de provisionar. Nao deixe o ambiente ligado entre testes.

## Passo a passo individual
1. Instale Azure CLI, PowerShell, kubectl e tenha quota/permissoes na assinatura Azure.
2. No repositorio Orchestration execute: az login
3. Confira: az account list -o table
4. Verifique Bicep: az bicep build --file infra/azure/main.bicep
5. Confira na calculadora Azure o custo da regiao e SKU escolhidos.
6. Provisionar (na raiz): ./infra/azure/deploy.ps1 -MemberId membro01 -SubscriptionId '<sua-subscription-id>' -Location brazilsouth
7. Confira what-if, custos, as duas confirmacoes do script e os recursos no Portal.
8. Listar: az resource list -g rg-fcg-fase4-membro01 -o table
9. Confira AKS e ACR: az aks list -g rg-fcg-fase4-membro01 -o table ; az acr list -g rg-fcg-fase4-membro01 -o table
10. Vincule ACR (exige RBAC): az aks update -g <rg> -n <aks> --attach-acr <acr>
11. Acesse cluster: az aks get-credentials -g <rg> -n <aks> ; kubectl get nodes
12. Depois da gravacao: ./infra/azure/destroy.ps1 -MemberId membro01 -SubscriptionId '<sua-subscription-id>'
13. Verifique no portal a conclusao da exclusao. Recursos fora desse RG exigem limpeza adicional.

## Regras de seguranca
Nao comitar subscriptions, credenciais, tokens, connection strings ou secrets. Cada integrante tem Resource Group e acesso Azure propios. Os scripts exigem confirmacao de criacao e de exclusao. A exclusao e irreversivel. Uma replica/no nao prova alta disponibilidade. Azure Functions com RabbitMQTrigger exige plano compativel, rede e custo adicionais.

## Estado
- [x] AKS + ACR em Bicep com parametros por integrante
- [x] Criacao e exclusao por PowerShell com confirmacao
- [x] Workflow estatico de build do Bicep sem custos Azure
- [ ] Execucao do workflow e validacao real em Azure
- [ ] Pipeline de deploy e configuracao OIDC por integrante
- [ ] Recursos adicionais, gateway, Elasticsearch, Functions e demonstracao de ponta a ponta
