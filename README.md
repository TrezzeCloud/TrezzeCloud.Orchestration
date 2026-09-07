# TrezzeCloud.Orchestration — Fase 3

Execução local com Docker Compose e manifests Kubernetes para Kong, UsersAPI, CatalogAPI, PaymentsAPI, SQL Server, RabbitMQ, MongoDB e Redis. Notificações usam Azure Functions: no Compose, o host isolated roda em container com Azurite; para Kubernetes, a estratégia é implantar a Function no Azure, fora do cluster. Não há stack de observabilidade nesta etapa.

## Arquitetura e rotas

Cliente → Kong → UsersAPI/CatalogAPI. SQL Server guarda usuários, jogos e bibliotecas; MongoDB guarda avaliações; Redis guarda a listagem de jogos por 5 minutos. O cache é invalidado após criação, atualização e exclusão lógica de jogos.

| Método | Caminho | JWT no Kong | Regra adicional da API |
|---|---|---|---|
| POST | `/api/users/register` | Não | Registro |
| POST | `/api/users/login` | Não | Login |
| POST | `/api/users/refresh-login` | Não | Valida o refresh token do corpo |
| GET | `/api/users`, `/api/users/{id}` | Sim | Role Admin |
| GET | `/api/games`, `/api/games/{id}` | Não | Consulta |
| POST | `/api/games` | Sim | Role Admin |
| PUT, DELETE | `/api/games/{id}` | Sim | Role Admin |
| GET | `/api/games/{gameId}/reviews` | Não | Consulta avaliações |
| POST | `/api/games/{gameId}/reviews` | Sim | Usuário autenticado; nota 1–5 |
| POST | `/api/store/purchase/{gameId}` | Sim | Usuário autenticado |
| GET | `/api/store/my-library` | Sim | Biblioteca do usuário autenticado |

As rotas usam métodos e expressões com término de caminho; login não libera subrotas administrativas. `strip_path: false` preserva o caminho da API. Apenas endpoints existentes são publicados; Swagger não é roteado.

Kong valida assinatura HS256, issuer (`iss`, associado à credencial) e expiração (`exp`), usando somente `Authorization: Bearer <token>`. As APIs continuam validando JWT, audience e roles. A autorização Admin não é substituída pela autenticação do Gateway. Referência: [plugin JWT do Kong](https://developer.konghq.com/how-to/authenticate-consumers-jwt/).

## Preparação local

Use os repositórios existentes como pastas irmãs:

```text
TrezzeCloud/
  TrezzeCloud.Orchestration/
  TrezzeCloud.UsersAPI/
  TrezzeCloud.CatalogAPI/
  TrezzeCloud.PaymentsAPI/
  TrezzeCloud.Notifications.Functions/
```

Pré-requisitos: Docker com containers Linux e Compose v2; PowerShell para os scripts; SDK .NET 10 para testes unitários; kubectl e um cluster com StorageClass padrão para Kubernetes.

Na raiz de Orchestration:

```powershell
./scripts/prepare-local.ps1
./scripts/validate-config.ps1
```

`prepare-local.ps1` cria `.env` a partir de `.env.example` somente se ele não existir. Se `JWT_SECRET_KEY` estiver vazio, gera 32 bytes aleatórios em hexadecimal. Preserva valores existentes e sincroniza `k8s/jwt.env`. Os dois arquivos são ignorados pelo Git. Não exiba nem versione a saída completa de `docker compose config` ou `kubectl kustomize`, pois contém credenciais.

Para Kubernetes, o Kustomize gera `jwt-secret` a partir de `k8s/jwt.env` e referencia o mesmo Secret no Kong, UsersAPI e CatalogAPI. O nome inclui hash, atualizando as referências quando a chave muda. `routes.yaml` contém somente rotas/plugins; `start-kong.sh` acrescenta a credencial em arquivo temporário em memória, com permissão restrita, na inicialização. Kong DB-less não faz interpolação automática de variáveis no YAML. Após rotação, reaplique os manifests ou recrie os containers; tokens antigos deixam de valer.

### Variáveis do Compose

| Variáveis | Uso |
|---|---|
| `JWT_SECRET_KEY`, `JWT_ISSUER`, `JWT_AUDIENCE` | Assinatura e validação compartilhadas; chave obrigatória, sem fallback no Compose |
| `SQL_SA_PASSWORD`, `USERS_CONNECTION_STRING`, `CATALOG_CONNECTION_STRING` | SQL Server e bancos das APIs |
| `USERS_ADMIN_PASSWORD` | Senha do administrador inicial (`admin@trezzecloud.com`) |
| `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS` | Usuário inicial do broker |
| `RABBITMQ_HOST`, `RABBITMQ_USERNAME`, `RABBITMQ_PASSWORD` | Conexão das APIs com o mesmo broker |
| `RABBITMQ_CONNECTION` | URI AMQP das Functions; mesmas credenciais e vhost |
| `MONGO_USERNAME`, `MONGO_PASSWORD`, `MONGO_CONNECTION_STRING`, `MONGO_DATABASE_NAME` | MongoDB autenticado no Compose e configuração da CatalogAPI |
| `REDIS_CONNECTION_STRING` | Cache da CatalogAPI (`redis:6379`) |

Ao mudar senhas, atualize também as connection strings correspondentes. Usuários de bancos já inicializados em volumes não são automaticamente recriados por variáveis novas. Credenciais de exemplo são locais. No Kubernetes, as credenciais locais não JWT continuam nos manifests de Secret dos serviços; substitua-as antes de implantação fora do ambiente de desenvolvimento. O script de preparação sincroniza apenas JWT entre Compose e Kubernetes.

## Docker Compose

```powershell
docker compose build
docker compose up -d
docker compose ps
./scripts/test-gateway.ps1
```

Entrada principal: `http://localhost:8000`. Apenas Kong publica porta no host. APIs, bancos, RabbitMQ, Azurite e Functions não publicam portas. A Admin API do Kong está desativada (`KONG_ADMIN_LISTEN=off`). Acesso administrativo ao Docker continua permitindo operações internas; o isolamento aqui se refere aos clientes externos.

O broker carrega `rabbitmq.conf`, cria seu usuário/vhost padrão no primeiro boot e só então `start-rabbitmq.sh` importa `definitions.json`. A readiness/healthcheck aguarda a importação. Isso evita que a importação antecipada suprima a criação do usuário padrão. As definições criam os exchanges fanout dos eventos de usuário e pagamento, as filas `notifications-user-created` e `notifications-payment-processed` e seus bindings. As APIs configuram as demais filas via MassTransit. O usuário guest é permitido entre containers apenas para o cenário local; para outros ambientes use um usuário próprio.

Para parar sem apagar dados:

```powershell
docker compose stop
```

### Fluxos da Fase 3

1. Registro publica `UserCreatedEvent`; a Function consome o envelope MassTransit e simula e-mail de boas-vindas.
2. Login retorna `accessToken` e `refreshToken`. Envie o access token no cabeçalho Bearer. Refresh usa `{"refreshToken":"..."}` no corpo e não exige access token válido no Gateway.
3. Administrador cria/edita/desativa jogos; a CatalogAPI invalida Redis. GET público preenche o cache em um miss.
4. Usuário autenticado envia `{"rating":5,"comment":"Ótimo jogo"}` ao endpoint de avaliações; dados são gravados no MongoDB.
5. Compra publica `OrderPlacedEvent`; PaymentsAPI processa e publica `PaymentProcessedEvent`; CatalogAPI atualiza a biblioteca e a Function simula confirmação apenas para `Approved`.

As notificações são simuladas em logs, sem envio SMTP real. Payloads inválidos são descartados com aviso, sem retry implementado nesses casos.

## Kubernetes

### Imagens e configuração

Faça build das imagens locais pelo Compose. Para Docker Desktop, se o cluster compartilha o image store, use as imagens locais via overrides Kustomize ou `kubectl set image`. Para outro cluster, disponibilize previamente as imagens corrigidas em um registry acessível e ajuste os campos `image` dos deployments. Os manifests das APIs mantêm os nomes de imagem existentes `gu1m4ss1/...:latest`; não assumem que uma imagem remota contém suas alterações locais. Este procedimento não faz push automaticamente.

```powershell
./scripts/prepare-local.ps1
kubectl config current-context
# Validação estrutural local; descarta a saída que contém Secrets.
kubectl kustomize k8s | Out-Null
# Com o cluster disponível: validação de schema/admission sem persistir.
kubectl apply --dry-run=server -k k8s
kubectl apply -k k8s
kubectl rollout status deployment/rabbitmq
kubectl rollout status deployment/mongodb
kubectl rollout status deployment/redis
kubectl rollout status deployment/users-api
kubectl rollout status deployment/catalog-api
kubectl rollout status deployment/kong
kubectl get pods,svc,pvc
```

Use `apply -k k8s`, não `apply -f k8s --recursive`: o diretório contém templates Kong e o Kustomize precisa gerar ConfigMaps/Secret e suas referências. MongoDB e Redis têm PVCs; Mongo usa 2 GiB e Redis 1 GiB com AOF. O exemplo Kubernetes usa MongoDB interno sem autenticação; adapte credenciais conforme o ambiente. SQL Server e RabbitMQ mantêm armazenamento efêmero neste exemplo Kubernetes, portanto dados desses dois serviços não sobrevivem à substituição dos pods.

O proxy Kong é o único NodePort: `30090`. UsersAPI/CatalogAPI usam ClusterIP na porta 8080; SQL Server, RabbitMQ, MongoDB e Redis também são ClusterIP. Não há porta/Service de Admin API. A NetworkPolicy `apis-from-kong` permite ingress nas APIs apenas dos pods Kong do mesmo namespace; exige CNI com suporte a NetworkPolicy. O ClusterIP impede exposição direta por NodePort independentemente dessa política. Não crie port-forwards públicos, Ingress alternativo ou LoadBalancer para as APIs.

Entrada: `http://<IP-do-node>:30090`; no Docker Desktop geralmente `http://localhost:30090`. Para teste local quando NodePort não estiver acessível:

```powershell
kubectl port-forward service/kong 8000:8000
```

### Migração de cluster já existente

Aplicar os novos manifests converte os Services das APIs para ClusterIP e remove a porta administrativa do Kong. Confira `kubectl get svc` e quaisquer Ingress/LoadBalancer criados fora deste repositório.

O arquivo antigo de NotificationsAPI contém apenas um aviso e está fora do Kustomize. `apply` não remove recursos antigos. Para migrar um cluster que já executava o consumidor legado, pare-o antes de ativar a Function no Azure; só então remova seus recursos:

```powershell
kubectl scale deployment notifications-api --replicas=0
kubectl delete deployment,service notifications-api --ignore-not-found
kubectl delete configmap notifications-api-config --ignore-not-found
kubectl delete secret notifications-api-secret --ignore-not-found
```

Esses comandos são instruções de migração; não são executados pelo script de preparação. Remover o host antigo elimina o consumidor ASP.NET Core, que disputaria mensagens com as Functions nas mesmas filas.

### Azure Functions fora do Kubernetes

A estratégia escolhida é Azure Functions v4, .NET 10 isolated, com os dois RabbitMQTriggers do repositório independente TrezzeCloud.Notifications.Functions. Não há deployment de Notifications.Api no novo conjunto Kubernetes.

1. Disponibilize uma Function App em plano **Elastic Premium ou Dedicated** compatível com o runtime .NET do projeto. RabbitMQ bindings não são plenamente suportados no plano Consumption, conforme [documentação Microsoft](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-rabbitmq).
2. Disponibilize Storage real e configure `FUNCTIONS_WORKER_RUNTIME=dotnet-isolated`, `AzureWebJobsStorage` e `RabbitMqConnection` nas configurações da Function App, usando Secrets/Key Vault conforme o ambiente.
3. Configure conectividade privada da Function até o RabbitMQ: VNet integration, DNS e um endpoint privado alcançável do broker (por exemplo, um balanceador interno do cluster). O DNS `rabbitmq` e seu ClusterIP não são alcançáveis diretamente de uma Function externa. Em um cluster apenas local, é necessário VPN/túnel privado adequado; alternativamente, valide o fluxo completo pelo Compose. Não publique a interface de management na internet.
4. Garanta usuário, permissões no vhost, TLS quando aplicável e os dois bindings de `definitions.json` no broker de destino. A URI AMQP deve apontar para esse endpoint, não para `localhost` nem para o nome de serviço do Compose.
5. Com a infraestrutura Azure pronta e autorização de implantação, publique a partir do projeto Functions:

```powershell
Set-Location ../TrezzeCloud.Notifications.Functions/src/TrezzeCloud.Notifications.Functions
func azure functionapp publish <nome-da-function-app>
```

6. Verifique a inicialização de `UserCreatedNotification` e `PaymentProcessedNotification`; faça um registro e uma compra aprovada pela entrada Kong e confira o consumo nas filas.

A Function App, Storage e a rede Azure não são provisionados por estes manifests e não foram implantados por esta etapa. O fluxo completo de notificações em Kubernetes depende dessa implantação externa.

## Validação

```powershell
./scripts/validate-config.ps1
./scripts/test-gateway.ps1 -BaseUrl http://localhost:8000
# Opcional: cria usuário, jogo, avaliação e compra de teste; desativa o jogo no fim.
./scripts/test-gateway.ps1 -BaseUrl http://localhost:8000 -IncludeWrites
# Para Kubernetes use -BaseUrl http://localhost:30090
```

O primeiro script valida Compose, isolamento das portas, consistência da chave JWT, parsing do YAML por Kustomize e JSON do RabbitMQ. O segundo faz testes HTTP públicos/protegidos, tokens inválidos/expirados/issuer incorreto, login e acesso administrativo/biblioteca. Use o administrador local configurado em `.env`; o script não exibe tokens.

Para testes unitários dos serviços, execute `dotnet test` em cada solução existente. Os builds Docker compilam as quatro aplicações, mas não executam automaticamente os testes unitários. A validação de YAML local não substitui a validação de schema/admission nem um rollout real em Kubernetes.

### Resultados finais da Fase 3

- Quatro imagens Docker reconstruídas com sucesso.
- Compose, YAML/Kustomize e `kong config parse`: aprovados; nenhum contexto Kubernetes estava configurado para validar schema/admission ou fazer rollout.
- Testes HTTP em stack isolada com volumes novos: 67 verificações aprovadas, incluindo assinatura JWT adulterada, expiração, issuer, roles, refresh, CRUD/cache, MongoDB e compra até a biblioteca.
- Duas verificações explícitas adicionais do cache aprovadas: miss na primeira consulta e hit na segunda, com respostas idênticas.
- 61 testes unitários aprovados: UsersAPI 6, CatalogAPI 19, PaymentsAPI 3 e Notifications.Functions 33; zero falhas e zero testes ignorados.
- MongoDB aprovado: criação e consulta de avaliações.
- Redis aprovado: miss, hit e invalidação após Create, Update e Delete.
- UserCreatedFunction aprovada: consumo do evento e simulação do e-mail de boas-vindas.
- PaymentProcessedFunction aprovada: pagamento Approved, inclusão na biblioteca e simulação da confirmação de compra.
- Tratamento de `price` como número JSON e string decimal corrigido e testado. O fixture sanitizado [payment-processed.masstransit.json](tests/fixtures/payment-processed.masstransit.json) reproduz o envelope real do MassTransit.
- Nenhuma vulnerabilidade encontrada nas auditorias finais de pacotes, incluindo dependências transitivas, após a correção da PaymentsAPI.
- Novo repositório Notifications.Functions publicado na organização TrezzeCloud.

### Pendências fora da validação local

- Rollout real em Kubernetes.
- Implantação real no Azure.
- Conectividade privada Azure Functions → RabbitMQ.
- Observabilidade: explicitamente fora desta etapa; nenhuma stack foi implementada.

## Repositório próprio da Function

A implementação serverless e seus 33 testes estão publicados em [TrezzeCloud.Notifications.Functions](https://github.com/TrezzeCloud/TrezzeCloud.Notifications.Functions). O Compose utiliza o novo contexto e Dockerfile da raiz. A NotificationsAPI antiga permanece apenas como legado. A validação final confirmou o consumo e a simulação das duas notificações.
