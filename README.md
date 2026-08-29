# TrezzeCloud.Orchestration

Repositório responsável pela orquestração da plataforma TrezzeCloud utilizando Docker Compose e Kubernetes.

## Objetivo

Centralizar toda a infraestrutura necessária para execução dos microsserviços da plataforma:

- RabbitMQ
- SQL Server
- UsersAPI
- CatalogAPI
- PaymentsAPI
- NotificationsAPI

Além disso, este repositório contém os manifestos Kubernetes utilizados para deploy local da aplicação.

---

# Arquitetura

A solução foi construída utilizando arquitetura de microsserviços orientada a eventos.

## Microsserviços

| Serviço | Responsabilidade |
|----------|----------|
| UsersAPI | Cadastro, autenticação JWT e autorização |
| CatalogAPI | CRUD de jogos e fluxo de compra |
| PaymentsAPI | Processamento de pagamentos |
| NotificationsAPI | Envio de notificações |

---

# Tecnologias

- .NET 10
- ASP.NET Core
- Entity Framework Core
- SQL Server
- RabbitMQ
- MassTransit
- Docker
- Docker Compose
- Kubernetes
- Kong API Gateway

---

# Repositórios

## Orchestration
https://github.com/GuiMassi/TrezzeCloud.Orchestration.git

## UsersAPI
https://github.com/GuiMassi/TrezzeCloud.UsersAPI.git

## CatalogAPI
https://github.com/GuiMassi/TrezzeCloud.CatalogAPI.git

## PaymentsAPI
https://github.com/GuiMassi/TrezzeCloud.PaymentsAPI.git

## NotificationsAPI
https://github.com/GuiMassi/TrezzeCloud.NotificationsAPI.git

---

# Docker Compose

## Executar aplicação completa

```bash
docker compose up --build
```

---

# Kubernetes

## Pré-requisitos

- Docker Desktop
- Kubernetes habilitado (Settings → Kubernetes → Enable Kubernetes)
- kubectl instalado

---

## Estrutura Kubernetes

```txt
k8s/
 ├── rabbitmq
 ├── sqlserver
 ├── users-api
 ├── catalog-api
 ├── payments-api
 ├── notifications-api
 └── kong
      ├── Kong.yaml     # Deployment + Service do Kong (porta única de entrada)
      └── routes.yaml   # Configuração declarativa: services, routes, consumer e plugin JWT
```

---

## API Gateway (Kong)

Foi implementado o **Kong API Gateway** como ponto único de entrada da plataforma TrezzeCloud, atendendo ao requisito obrigatório do Tech Challenge (Módulo 1 — Implementação de um API Gateway).

O Kong roda em modo **DB-less / declarativo** (`KONG_DATABASE=off`), sem banco de dados próprio e sem depender do Kong Ingress Controller. A configuração de rotas, serviços e o plugin de JWT é escrita em `routes.yaml` e injetada no container via `ConfigMap` do Kubernetes.

O Gateway é responsável por:

- Receber todas as requisições externas.
- Validar tokens JWT nas rotas protegidas.
- Encaminhar requisições para o UsersAPI.
- Encaminhar requisições para o CatalogAPI.
- Centralizar o acesso aos microsserviços da aplicação.

### Rotas Configuradas

| Rota | Serviço | Protegida por JWT? |
|---|---|---|
| `/api/users/login` | UsersAPI | Não (necessário para obter o token) |
| `/api/users/register` | UsersAPI | Não |
| `/api/users` | UsersAPI | Sim |
| `/api/games` | CatalogAPI | Não |

> **Nota:** o path do catálogo é `/api/games` (nome do controller da CatalogAPI), e não `/api/catalog`.

### Autenticação JWT

O Kong foi configurado com o plugin `jwt` aplicado apenas às rotas que exigem autenticação. As rotas de login e registro ficam deliberadamente fora da proteção, para que seja possível obter um token antes de acessar os recursos protegidos.

Para que o Kong aceite os tokens emitidos pela UsersAPI, foi cadastrado um `consumer` declarativo com uma credencial JWT cuja `key` corresponde ao claim `iss` (issuer) do token, e o `secret` é o mesmo utilizado pela UsersAPI para assinar os tokens:

```yaml
consumers:
  - username: trezzecloud-app
    jwt_secrets:
      - key: TrezzeCloud
        algorithm: HS256
        secret: SUPER_SECRET_KEY_123456789_SUPER_SECRET_KEY
```

Todas as requisições às rotas protegidas devem enviar o token através do cabeçalho:

```http
Authorization: Bearer <token>
```

Caso o token seja inválido, inexistente ou expirado, o acesso é bloqueado pelo Gateway (`401 Unauthorized`).

### Configuração completa (`routes.yaml`)

```yaml
_format_version: "3.0"
consumers:
  - username: trezzecloud-app
    jwt_secrets:
      - key: TrezzeCloud
        algorithm: HS256
        secret: SUPER_SECRET_KEY_123456789_SUPER_SECRET_KEY
services:
  - name: users-api
    url: http://users-api:80
    routes:
      - name: users-public-route
        paths:
          - /api/users/login
          - /api/users/register
        strip_path: false
      - name: users-protected-route
        paths:
          - /api/users
        strip_path: false
        plugins:
          - name: jwt
            config:
              claims_to_verify:
                - exp
  - name: catalog-api
    url: http://catalog-api:80
    routes:
      - name: catalog-route
        paths:
          - /api/games
        strip_path: false
```

### Fluxo de Comunicação

```txt
Cliente
   |
   v
Kong API Gateway (NodePort 30090)
   |
   +--> /api/users/login, /api/users/register  --> UsersAPI (público)
   |
   +--> /api/users  (JWT obrigatório)           --> UsersAPI
   |
   +--> /api/games                              --> CatalogAPI
```

---

# Fluxos de Eventos

## Cadastro de Usuário

1. UsersAPI cria usuário.
2. Publica UserCreatedEvent.
3. NotificationsAPI consome evento.
4. Simula envio de e-mail de boas-vindas.

---

## Compra de Jogo

1. CatalogAPI inicia compra.
2. Publica OrderPlacedEvent.
3. PaymentsAPI processa pagamento.
4. Publica PaymentProcessedEvent.
5. CatalogAPI adiciona o jogo à biblioteca.
6. NotificationsAPI envia confirmação.

---

# Deploy Local Kubernetes

## 1. RabbitMQ

```bash
kubectl apply -f .\k8s\rabbitmq\rabbitmq.yaml
```

## 2. SQL Server

```bash
kubectl apply -f .\k8s\sqlserver\sqlserver.yaml
```

## 3. UsersAPI

```bash
kubectl apply -f .\k8s\users-api\users-api.yaml
```

## 4. CatalogAPI

```bash
kubectl apply -f .\k8s\catalog-api\catalog-api.yaml
```

## 5. PaymentsAPI

```bash
kubectl apply -f .\k8s\payments-api\payments-api.yaml
```

## 6. NotificationsAPI

```bash
kubectl apply -f .\k8s\notifications-api\notifications-api.yaml
```

## 7. Kong API Gateway

O Kong precisa que a configuração declarativa (`routes.yaml`) seja carregada como um `ConfigMap` **antes** de o Deployment ser aplicado:

```bash
kubectl create configmap kong-declarative-config --from-file=kong.yml=.\k8s\kong\routes.yaml
kubectl apply -f .\k8s\kong\Kong.yaml
```

> Sempre que `routes.yaml` for alterado, é necessário recriar o ConfigMap e reiniciar o Kong:
> ```bash
> kubectl delete configmap kong-declarative-config
> kubectl create configmap kong-declarative-config --from-file=kong.yml=.\k8s\kong\routes.yaml
> kubectl rollout restart deployment kong
> ```

---

# Verificação Final

```bash
kubectl get pods
kubectl get svc
```

## Testes do API Gateway

```bash
# Rota pública (catálogo) — deve retornar 200
curl http://localhost:30090/api/games

# Rota protegida sem token — deve retornar 401
curl http://localhost:30090/api/users

# Login — retorna accessToken
curl -X POST http://localhost:30090/api/users/login `
  -H "Content-Type: application/json" `
  -d '{"email":"admin@trezzecloud.com","password":"Admin@123"}'

# Rota protegida com token válido — deve retornar 200
curl http://localhost:30090/api/users -H "Authorization: Bearer <accessToken>"
```

Portas expostas via NodePort:

| Serviço | NodePort |
|---|---|
| Kong — Proxy (entrada pública) | 30090 |
| Kong — Admin API | 30091 |
| UsersAPI (debug direto) | 30081 |
| CatalogAPI (debug direto) | 30082 |
| SQL Server | 31433 |
| RabbitMQ (management UI) | 31672 |
