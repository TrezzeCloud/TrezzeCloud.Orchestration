# UsersAPI no AKS — primeira implantação

Este diretório prepara somente UsersAPI, SQL Server e RabbitMQ, sem alterar os manifests locais da Fase 3. Os três serviços usam ClusterIP; não há exposição pública. O acesso inicial à API será feito por port-forward.

## Preparação

1. Atualizar a UsersAPI para a branch `feature/fase4-ci`.
2. Executar os testes de .NET e publicar uma imagem nova usando `scripts/publish-acr.ps1` da UsersAPI.
3. Anotar o endereço completo da imagem publicado pelo script. A imagem antiga `fase4-58e32f7` **não** contém a correção que desabilita o usuário de teste no ambiente Production.
4. Atualizar a branch `feature/fase4-infra` da Orchestration.
5. Conferir o contexto kubectl para não publicar no cluster errado.

Na pasta raiz da Orchestration, com o AKS iniciado:

```powershell
kubectl config current-context

.\infra\azure\deploy-users-demo.ps1 `
    -ExpectedContext aks-fcg-canadateste `
    -Image "<registry>.azurecr.io/trezzecloud-users-api:fase4-<commit>"
```

O script cria o namespace `fcg-fase4`, gera senhas fortes de SQL Server, RabbitMQ, admin e JWT, e salva os valores apenas em um Kubernetes Secret. Se esse Secret já existir, é reutilizado sem gerar novas senhas.

Os recursos da demonstração ficam apenas nesse namespace. SQL Server usa um PVC de 10 GiB (disco Azure gerenciado, cobrado mesmo com AKS parado); RabbitMQ não possui armazenamento persistente nesta etapa e perderá mensagens quando o pod for recriado.

```powershell
kubectl -n fcg-fase4 get pods
kubectl -n fcg-fase4 get pvc
kubectl -n fcg-fase4 logs deployment/users-api --tail=100
kubectl -n fcg-fase4 port-forward svc/users-api 8080:8080
```

Com o port-forward ativo em outro terminal, verifique `http://localhost:8080/swagger/index.html`. Não exponha a API publicamente enquanto as autenticações, configurações de borda e rotas não estiverem finalizadas.

## Observações

- `Production` é obrigatório para evitar a criação automática do usuário de teste da Fase 3.
- A imagem deve ser nova: a alteração na inicialização da UsersAPI ainda precisa ser compilada e publicada no ACR.
- Nunca usar os manifestos de `k8s/users-api`, `k8s/sqlserver` e `k8s/rabbitmq` diretamente no Azure: eles preservam configurações locais de desenvolvimento.
- Não execute `kubectl apply -f users-api.yaml` manualmente: o manifesto tem um placeholder de imagem resolvido pelo script.
- A primeira instalação gera dados e senhas novos. Se apagar o Secret e mantiver o PVC do SQL Server, precisará restaurar as credenciais existentes ou recriar a instância.
- A imagem SQL Server utiliza a edição Developer para ambiente de testes, não produção.
- Reiniciar o pod de RabbitMQ pode apagar mensagens, porque não há PVC nesta primeira etapa.
- O ambiente continua sujeito às cobranças de VM, disco, registry e rede.
- Os manifestos são um smoke test incremental. Não representam ainda toda a implantação da Fase 4: faltam CatalogAPI, MongoDB, Redis, busca, Kong, pipelines e notificações.

## Interrupção

```powershell
az aks stop -g rg-fcg-fase4-canadateste -n aks-fcg-canadateste
```

Os volumes e o ACR podem continuar gerando custos. Para remover somente os recursos deste teste, `kubectl delete namespace fcg-fase4` elimina também o PVC e seus dados; antes disso, confira o que está no namespace.
