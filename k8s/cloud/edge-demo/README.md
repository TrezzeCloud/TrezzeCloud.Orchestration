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

**Status:** manifests e scripts preparados e validados por CI. O acesso externo ainda precisa de teste real em AKS antes de ser declarado concluído.
