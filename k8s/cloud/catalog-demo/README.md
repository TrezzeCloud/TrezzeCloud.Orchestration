# CatalogAPI no AKS

Os manifests desta pasta são exclusivos para a demonstração no namespace `fcg-fase4`. Não modificam a infraestrutura local da Fase 3.

## Componentes

- CatalogAPI (.NET 10), usando o SQL Server e RabbitMQ já implantados.
- MongoDB 8 com autenticação e PVC de 4 GiB para avaliações de jogos.
- Redis 7 com autenticação e limite de cache de 128 MB. Os dados do Redis são descartáveis e não usam PVC.

Todos os serviços são internos (`ClusterIP`).

## Preparação

Na branch `feature/fase4-ci` da CatalogAPI:

```powershell
dotnet test TrezzeCloud.CatalogAPI.slnx -c Release

.\scripts\publish-acr.ps1 -RegistryName acrfcgcanadatestec733w2tny4nm6
```

O Azure for Students bloqueia ACR Tasks; esse script compila com Docker local e usa `docker push`. Anote a imagem completa exibida no final.

Na raiz da Orchestration (`feature/fase4-infra`), com o AKS iniciado e a UsersAPI operando:

```powershell
kubectl config current-context

.\infra\azure\deploy-catalog-demo.ps1 `
    -ExpectedContext aks-fcg-canadateste `
    -Image "<registry>.azurecr.io/trezzecloud-catalog-api:fase4-<commit>"
```

O script gera senhas de MongoDB e Redis, salva as credenciais no Kubernetes Secret `catalog-demo-secrets` e usa os valores já existentes de SQL Server, RabbitMQ e JWT. A primeira execução cria um disco para MongoDB; nas execuções seguintes o Secret e o PVC são mantidos.

## Validação do build

A CatalogAPI compilou em Release com 19 testes unitários aprovados, sem falhas. Imagem publicada no ACR: `acrfcgcanadatestec733w2tny4nm6.azurecr.io/trezzecloud-catalog-api:fase4-d7f5a4a`.

A implantação no AKS foi concluída. CatalogAPI, MongoDB e Redis ficaram `Running` e `Ready` (1/1), sem reinicializações. O PVC do MongoDB com 4 GiB ficou `Bound`, e o PVC existente do SQL Server manteve 10 GiB em `Bound`.

## Testes

```powershell
kubectl -n fcg-fase4 get pods
kubectl -n fcg-fase4 get pvc
kubectl -n fcg-fase4 logs deployment/catalog-api --tail=80
kubectl -n fcg-fase4 port-forward svc/catalog-api 8081:8080
```

Com o port-forward ativo, em outro terminal, rode o teste automatizado a partir da raiz da Orchestration:

```powershell
.\infra\azure\test-catalog-demo.ps1
```

O teste faz duas leituras de jogos e uma leitura de avaliações, depois consulta o TTL da chave de jogos no Redis. A gravação de avaliações no MongoDB ainda não faz parte desse primeiro teste.

Para consultar os endpoints manualmente:

```powershell
curl.exe -i http://localhost:8081/api/games

curl.exe -i http://localhost:8081/api/games/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/reviews
```

A rota de jogos depende do SQL Server e Redis. A rota de avaliações utiliza MongoDB. Uma lista vazia com HTTP 200 é aceitável para o primeiro teste.

A autenticação da CatalogAPI deve usar tokens da UsersAPI porque as duas aplicações reutilizam a mesma chave JWT.

## Cuidados

- O manifesto contém um placeholder para a imagem. Utilize o script; não aplique `catalog-api.yaml` isoladamente.
- Redis usa armazenamento volátil e apenas uma réplica; não é uma implantação com alta disponibilidade.
- O MongoDB possui volume persistente, sujeito a cobrança mesmo quando o AKS está parado.
- Não apague o Secret do MongoDB mantendo seu PVC: as credenciais seriam perdidas.
- Não exponha MongoDB, Redis ou SQL Server na internet.
- A busca com Elasticsearch e os pipelines de CI/CD ainda serão adicionados.
