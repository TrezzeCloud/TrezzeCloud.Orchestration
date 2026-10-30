# Entrada HTTPS das APIs no AKS — Fase 4

A Fase 4 exige acesso externo via Load Balancer ou Ingress Controller. Esta implementação usa **Traefik Proxy** (chart oficial Helm **42.1.3**, Kubernetes 1.36 compatível) com **um único ponto de entrada**, roteando para os dois serviços ClusterIP já existentes no namespace `fcg-fase4`.

O antigo projeto comunitário **ingress-nginx** foi descontinuado em março de 2026 e não foi utilizado nesta solução.

## Rotas

| Rota externa | Serviço Kubernetes | Porta |
|---|---|---|
| `/api/users/*` | `users-api` | 8080 |
| `/api/games/*` | `catalog-api` | 8080 |
| `/api/store/*` | `catalog-api` | 8080 |
| `/search` | `catalog-api` | 8080 |

Não há rewrite de caminhos; os controladores mantêm suas rotas. `/search` retorna 503 se o Elasticsearch ainda não foi configurado.

Não exponha Swagger nem o dashboard do Traefik por esse Ingress. Login, cadastro e demais endpoints continuam sujeitos às políticas de autorização implementadas nas APIs, mas segurança de transporte, limitação de requisições e monitoramento também importam em ambiente real.

## Implantação segura: primeiro somente interna

Pré-requisitos: Azure CLI, `kubectl` com contexto correto, Helm 3 ou 4 e ambas as APIs **1/1 Ready** no AKS. Nenhuma assinatura ou região está fixa nos YAMLs.

Na raiz do repositório Orchestration:

```powershell
.\infra\azure\deploy-edge-demo.ps1 -ExpectedContext "<nome-do-contexto-aks>"
```

O modo padrão é `Internal`: o serviço do Traefik é **ClusterIP**, não cria um IP público, e as APIs continuam acessíveis por port-forward.

```powershell
kubectl -n fcg-ingress port-forward svc/fcg-traefik 8443:443
```

Em outro terminal:

```powershell
curl.exe -k -i https://localhost:8443/api/games
curl.exe -k -i https://localhost:8443/api/users
```

A primeira chamada deve responder 200 quando os serviços estiverem funcionais; a segunda deve retornar 401 para usuário não autenticado. A opção `-k` é **exclusiva de demonstração**: sem um certificado TLS próprio, Traefik utiliza um certificado gerado sem cadeia de confiança.

## Publicação externa: somente mediante decisão do integrante

Para usar um domínio com certificado TLS válido, crie o Secret **no namespace `fcg-fase4`** com os arquivos de certificado e chave que o integrante obteve para seu domínio:

```powershell
kubectl -n fcg-fase4 create secret tls fcg-edge-tls --cert "caminho/certificado.pem" --key "caminho/chave.pem"

.\infra\azure\deploy-edge-demo.ps1 `
    -ExpectedContext "<nome-do-contexto-aks>" `
    -Exposure Public `
    -Hostname "api.exemplo.com" `
    -TlsSecretName "fcg-edge-tls"
```

**O Secret de certificado deve corresponder ao hostname e a cadeia deve ser confiável.** Configure o DNS do domínio apontando ao IP externo que o script mostrar. O script valida a presença do Secret, mas não valida a cadeia ou o hostname do certificado.

Se não houver domínio/certificado e for indispensável uma demonstração pública com dados **estritamente fictícios**, há uma opção explícita e temporária:

```powershell
.\infra\azure\deploy-edge-demo.ps1 `
    -ExpectedContext "<nome-do-contexto-aks>" `
    -Exposure Public `
    -AllowSelfSignedDemo
```

O script exige digitar `PUBLICAR` e utiliza o certificado não confiável gerado pelo Traefik. **Não utilize contas reais, credenciais pessoais ou tokens reais nesse modo, nem trate essa opção como configuração de produção.** Sem domínio, teste `https://<IP-PUBLICO>/api/games` com `curl.exe -k`. É possível que a criação do IP público leve algum tempo.

Em ambos os modos públicos, apenas o serviço do ingress controller usa `LoadBalancer`; UsersAPI e CatalogAPI permanecem `ClusterIP`. A criação de IP público e o Load Balancer podem ter cobrança no Azure **mesmo com o AKS parado**. Planeje ativar por períodos curtos.

## Remover acesso externo e recursos de entrada

```powershell
.\infra\azure\destroy-edge-demo.ps1 -ExpectedContext "<nome-do-contexto-aks>"
```

É solicitada a confirmação `REMOVER-INGRESS`. O script remove a rota Ingress e desinstala o Traefik, encerrando seu Service `LoadBalancer`. **Confirme no Portal Azure que o IP público e as regras associadas foram realmente removidos.** Os Deployments e os volumes dos bancos não são apagados.

Se for necessário manter a rota para testes internos, execute novamente `deploy-edge-demo.ps1` sem `-Exposure Public`. Não reinicie automaticamente um IP público depois de encerrar a sessão.

## Validação e evidências

```powershell
kubectl -n fcg-ingress get deployment,service
kubectl -n fcg-fase4 get ingress fcg-apis
kubectl -n fcg-ingress logs deployment/fcg-traefik --tail=50
```

No modo externo, capture também `kubectl -n fcg-ingress get svc fcg-traefik` e uma resposta HTTP da API usando a URL de entrada. Não versionar segredos, prints com tokens ou IPs vinculados a contas de colegas.

**Validação interna concluída em 30/10/2026 (AKS Canada Central, assinatura de teste):**
- `helm upgrade --install` finalizou com `STATUS: deployed` e chart `42.1.3`, usando Traefik `v3.7.16`.
- Deployment `fcg-traefik` e pod ficaram `1/1 Ready`, `Running`, sem restarts.
- Service `fcg-traefik` ficou `ClusterIP` (`443/TCP`), **sem IP público**.
- Ingress `fcg-apis` criado com classe `fcg-traefik`.
- Por `port-forward` HTTPS único: `GET /api/games` retornou **HTTP 200** e `GET /api/users`, sem token JWT, retornou **HTTP 401**.

**Validação externa concluída em 30/10/2026 (AKS Canada Central, assinatura de teste):**
- Execução `deploy-edge-demo.ps1 -Exposure Public -AllowSelfSignedDemo`, com confirmação `PUBLICAR`: Helm release `fcg-edge` atualizado para revisão 2 (`deployed`), deployment `fcg-traefik` 1/1 Ready.
- Service `fcg-traefik` passou a `LoadBalancer`, recebeu IP público `4.248.245.117`, porta `443/TCP`.
- Testes HTTPS feitos **fora do port-forward**, diretamente no IP público, com `curl.exe -k --max-time 15`: `GET /api/games` → **HTTP 200**; `GET /api/users` sem JWT → **HTTP 401**.
- Conclusão: acesso externo via **um único Load Balancer + Ingress Traefik**, incluindo o roteamento para as duas APIs, validado. Não se trata de configuração TLS de produção; `-k` foi utilizado apenas para teste com certificado autossinado.
- **Exposição pública desativada e verificada no Kubernetes:** o integrante executou `deploy-edge-demo.ps1 -Exposure Internal` e confirmou `service/fcg-traefik` em `ClusterIP`, `EXTERNAL-IP <none>` e `443/TCP`; deployment Traefik permaneceu `1/1 Ready` e o Ingress `fcg-apis` foi preservado.
- **Liberação do IP público temporário confirmada no Azure:** `az network public-ip list -g MC_rg-fcg-fase4-canadateste_aks-fcg-canadateste_canadacentral` mostrou apenas o IP `20.175.228.27`; o IP temporário do Ingress `4.248.245.117` não estava mais presente. O IP remanescente pode ser utilizado como saída do AKS e **não deve ser removido sem verificar seu vínculo**. O cluster, discos e registry podem continuar consumindo créditos.
