# UsersAPI no AKS — primeira implantação

Este diretório prepara somente UsersAPI, SQL Server e RabbitMQ, sem alterar os manifests locais da Fase 3. Os três serviços usam ClusterIP; não há exposição pública. O acesso inicial à API será feito por port-forward.

## Preparação

1. Atualizar a UsersAPI para a branch `main`.
2. Executar os testes de .NET e publicar uma imagem nova usando `scripts/publish-acr.ps1` da UsersAPI.
3. Anotar o endereço completo da imagem publicado pelo script. A imagem antiga `fase4-58e32f7` **não** contém a correção que desabilita o usuário de teste no ambiente Production.
4. Atualizar a branch `main` da Orchestration.
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

## Validação no AKS

A primeira execução de `deploy-users-demo.ps1` concluiu o rollout. UsersAPI, SQL Server e RabbitMQ estavam `Running` e `Ready` (1/1), sem reinicializações. O PVC `sqlserver-data` de 10 GiB ficou `Bound`. Todos os serviços ficaram internos como `ClusterIP`.

O Swagger respondeu HTTP 200 e a rota GET `/api/users` retornou HTTP 401 sem token. A inicialização registrou consultas ao SQL Server e o barramento MassTransit conectado ao RabbitMQ.

Para validar cadastro, persistência, JWT e autorização com credenciais descartáveis, mantenha o port-forward ativo e execute, na raiz da Orchestration:

```powershell
.\infra\azure\test-users-demo.ps1
```

O teste cria uma conta com e-mail aleatório, executa cadastro e login e confirma que um usuário comum não tem acesso à rota de administrador. Não imprime tokens nem senhas. O evento `UserCreatedEvent` é publicado pelo endpoint de cadastro, mas sua entrega ao consumidor ainda precisa de verificação específica.

O script de cadastro, login e acesso autorizado foi validado no ambiente de referencia; cada integrante deve executa-lo em sua propria assinatura e registrar a evidencia.

## Observações

- `Production` é obrigatório para evitar a criação automática do usuário de teste da Fase 3.
- A imagem deve ser compilada a partir da main atual e publicada no ACR da assinatura do integrante.
- Nunca usar os manifestos de `k8s/users-api`, `k8s/sqlserver` e `k8s/rabbitmq` diretamente no Azure: eles preservam configurações locais de desenvolvimento.
- Não execute `kubectl apply -f users-api.yaml` manualmente: o manifesto tem um placeholder de imagem resolvido pelo script.
- A primeira instalação gera dados e senhas novos. Se apagar o Secret e mantiver o PVC do SQL Server, precisará restaurar as credenciais existentes ou recriar a instância.
- A imagem SQL Server utiliza a edição Developer para ambiente de testes, não produção.
- Reiniciar o pod de RabbitMQ pode apagar mensagens, porque não há PVC nesta primeira etapa.
- O ambiente continua sujeito às cobranças de VM, disco, registry e rede.
- Estes manifests cuidam apenas da UsersAPI, SQL e RabbitMQ. Consulte o guia completo em ../../infra/azure/GUIA-REPRODUCAO-E-VALIDACAO.md (caminho a partir da raiz Orchestration). MongoDB, Redis, CatalogAPI, busca e Ingress sao implantados separadamente.

## Interrupção

```powershell
az aks stop -g rg-fcg-fase4-canadateste -n aks-fcg-canadateste
```

Os volumes e o ACR podem continuar gerando custos. Para remover somente os recursos deste teste, `kubectl delete namespace fcg-fase4` elimina também o PVC e seus dados; antes disso, confira o que está no namespace.
