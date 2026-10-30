# FIAP Cloud Games — Auditoria da Fase 4 contra o enunciado

**Fonte de requisitos:** TC NETT — Fase 4.pdf, paginas 2–6. **Data da auditoria:** 30/10/2026. **Escopo do codigo:** main dos repositorios TrezzeCloud.UsersAPI, TrezzeCloud.CatalogAPI e TrezzeCloud.Orchestration, com scripts/manifests em infra/azure e k8s/cloud. **Evidencias de execucao:** resultados observados na assinatura de referencia, incluindo os testes fornecidos pelo grupo nesta data.

**Interpretacao de status:** IMPLEMENTADO = arquivo/codigo encontrado; VALIDADO = ha execucao real na assinatura de referencia; PENDENTE = ainda precisa de demonstracao ou verificacao adicional. O fato de funcionar na assinatura de referencia **nao comprova** que o apresentador reproduziu em outra assinatura.

## Matriz de atendimento do enunciado da Fase 4

| Exigencia da FIAP | Implementacao / arquivo verificavel | Evidencia / status | O que mostrar no video |
|---|---|---|---|
| Kubernetes gerenciado na nuvem (AKS/EKS/GKE/OKE), nao IaaS isolada | infra/azure/main.bicep; infra/azure/modules/aks.bicep; deploy.ps1 | **VALIDADO na referencia:** aks-fcg-canadateste, cluster Running e nodes Ready | Azure Portal AKS e kubectl get nodes |
| Registry privado nativo da nuvem | infra/azure/modules/acr.bicep; publish-acr.ps1 nas duas APIs | **VALIDADO:** ACR Basic e imagens publicadas; AKS associado ao ACR | ACR > Repositories e tag do commit |
| Aplicacao acessivel externamente via Ingress/Load Balancer | k8s/cloud/edge-demo/traefik-values.yaml; apis-ingress.yaml; deploy-edge-demo.ps1 | **VALIDADO anteriormente:** endpoint HTTPS externo retornou 200/401. **Estado atual:** Ingress privado ClusterIP; nova exposicao para video **PENDENTE** | External IP, Ingress, curl HTTPS 200 e 401 |
| NoSQL obrigatorio (MongoDB ou DynamoDB), driver .NET | Catalog.Infrastructure/MongoDb; GameReviewsController; k8s/cloud/catalog-demo/mongodb.yaml | **VALIDADO:** teste integrado gravou avaliacao Mongo (201) e consultou | Criar review e consultar o mesmo registro |
| Cache distribuido obrigatorio (ex. Redis) | Catalog.Infrastructure/Cache/CacheService; GameController; k8s/cloud/catalog-demo/redis.yaml | **VALIDADO:** cache com TTL e invalidacao apos create/update/delete | TTL antes/depois, cache hit/miss e resultado |
| Busca Elasticsearch/OpenSearch **gerenciado**, independente do SQL | Catalog.Infrastructure/Search/ElasticsearchGameSearchService; GameSearchController | **VALIDADO em 30/10/2026 no Elastic Cloud Serverless:** 12 jogos reindexados no ambiente referencia, fuzzy, update, disable | Elastic Cloud (chave oculta) e script de teste real |
| Atualizar indice quando cadastrar/editar jogo | GameController.UpdateSearchIndexAsync, GameSearchReindexWorker | **VALIDADO:** criar e atualizar refletidos no indice. A sincronizacao eventual tem reconciliacao periodica | Cadastro/edicao e busca correspondente |
| /search tolerante a erros de digitacao e ordenado por relevancia | GameSearchController; ElasticsearchGameSearchService (multi_match, fuzziness AUTO, _score desc) | **VALIDADO:** cybr drft / ocen qust em Elastic gerenciado; teste CI cobre relevancia | Duas pesquisas fuzzy e explicar _score |
| Pipeline GitHub Actions/Azure DevOps ao menos UsersAPI e CatalogAPI | .github/workflows/fase4-ci-cd.yml em cada API | **VALIDADO anteriormente** nos repositorios oficiais: testes, Docker, push ACR, rollout. **PENDENTE** rodar no fork do apresentador | Workflow na main do proprio fork, jobs success |
| Build e testes automatizados | workflow validate, dotnet test, docker build | **VALIDADO** no CI de referencia; Catalog inclui search_integration | Jobs validate/search_integration |
| Imagem Docker versionada e push ao ACR | workflow publish_deploy, imagem tag SHA | **VALIDADO** no CI de referencia | SHA do commit e tag no ACR |
| Security scan de imagem (desejavel) | jobs validate utilizam Trivy | **IMPLEMENTADO como informativo** (exit-code 0), portanto nao bloqueia vulnerabilidades | Mostrar job e explicar natureza informativa |
| Deploy automatico e rolling update sem downtime esperado | workflow publish_deploy, kubectl set image, rollout status/undo | **VALIDADO anteriormente** na referencia. **PENDENTE** cena nova live deploy | Push em main, workflow, rollout e resposta com novo header |
| Segredos sem hardcode em codigo/YAML de implantacao | users-demo-secrets/catalog-demo-secrets gerados por scripts; secretKeyRef nos manifests cloud; catalog-search-secrets | **VALIDADO estruturalmente:** Secrets presentes, valores nao expostos; scripts de scan de appsettings em ambas APIs | YAML sem password literal, Secret metadata, OIDC; ocultar valores |
| Cloud Native e portabilidade documental | Bicep e scripts parametrizados por SubscriptionId, MemberId, Location, VmSize; manifests Kubernetes | **IMPLEMENTADO:** nenhuma assinatura hardcoded nos scripts de provisionamento. **PENDENTE** reproduzir ponta a ponta na conta de outro aluno | Criar sua propria conta/AKS/ACR/forks e executar testes |
| Video pitch de ate 25 min | ROTEIRO-VIDEO-FASE4.md | **PENDENTE de gravacao** | Todas as cenas com evidencias |
| YAML infraestrutura, definicoes de pipeline, codigo de NoSQL e Cache | infra/azure, k8s/cloud, .github/workflows e projetos CatalogAPI/UsersAPI | **IMPLEMENTADO** nos repositorios | Links navegaveis e arquivos em GitHub |
| Relatorio com grupo e Discord, docs, repositorios, link do video | Arquivo de entrega a preparar pelo apresentador | **PENDENTE** | Relatorio submetido conforme enunciado |

## Evidencias ja existentes no ambiente de referencia (nao na conta de outro integrante)

- AKS aks-fcg-canadateste em Running, ACR existente, nodes Ready e seis Deployments 1/1 Ready.
- sqlserver-data e mongodb-data em fase Bound.
- MongoDB, Redis, JWT e SQL Server aprovados em teste funcional integrado.
- Elastic Cloud **Serverless** em Azure eastus2, acessado pela CatalogAPI no AKS; **TESTE ELASTICSEARCH GERENCIADO APROVADO**, reindexando 12 jogos e validando create/fuzzy/update/disable.
- validate-cloud-fase4.ps1 com **-RequireElasticSecret** confirmou Secret, 6/6 Deployments e Ingress Traefik em **ClusterIP**.
- GitHub Actions das duas APIs ja possuem historico de deploy na referencia; o teste em forks de outro aluno **nao foi executado nesta auditoria**.

## Ressalvas tecnicas que nao devem ser omitidas no video

1. O cluster da referencia tem **um node** e seis Deployments: adequado para demonstracao academica, mas **nao representa alta disponibilidade multi-node de producao**.
2. O Ingress da referencia esta **privado** apos o teste externo anterior. Para provar acesso publico no video, deve ser ativado o modo Public e verificado o External IP, depois removido para evitar custo.
3. O HTTPS publico de demonstracao usa **certificado autossinado** se habilitado AllowSelfSignedDemo; isso comprova transporte TLS de teste, **nao identidade TLS confiavel de um dominio real**.
4. O workflow da CatalogAPI tem **Trivy informativo** (nao reprova build por vulnerabilidades). O item no enunciado e desejavel, nao mandatou uma politica bloqueante.
5. O CI da CatalogAPI usa Elasticsearch em container de runner, enquanto a evidencia de motor **gerenciado** vem do teste separado contra Elastic Cloud Serverless.
6. O outbox persistente nao faz parte do escopo implementado; a sincronizacao Elasticsearch e eventual, com worker de reconciliacao periodica.
7. Mongo/SQL possuem PVC de demonstracao; nao prometer comportamento multi-region, DR ou escalabilidade industrial.
8. A pipeline de CI/CD nao provisiona o cluster por conta propria; o bootstrap Bicep/manifests e feito antes, e so depois o workflow atualiza as imagens.
9. Os quatro microsservicos da Fase 2 existem em repositorios, mas os manifests cloud desta Fase 4 sob analise executam duas APIs e quatro dependencias. Nao atribuir ao ambiente cloud um fluxo de pagamento/notificacoes que nao foi demostrado nele.
10. Azure for Students e Elastic Cloud estao sujeitos a politicas/quotas/precos proprios. Cada apresentador deve usar apenas sua propria assinatura e chaves.

## Trabalho necessario antes de considerar a entrega final encerrada

- [ ] Integrar os PRs documentais aprovados a main e conferir links internos dos README.
- [ ] Integrante/apresentador executar o [guia do zero](GUIA-INTEGRANTE-DO-ZERO.md) com a propria assinatura, seus forks e projeto Elastic.
- [ ] Capturar tela de AKS/ACR, 6/6 Deployments, PVC Bound, Ingress com IP publico e respostas HTTPS.
- [ ] Guardar outputs dos testes SQL/JWT/Redis/Mongo/Elastic no ambiente do apresentador.
- [ ] Demonstrar **um live deploy real** da main do fork do apresentador, com code change, Actions success, nova tag ACR, rollout e resposta HTTP atualizada.
- [ ] Gravar video ate 25 minutos sem exibir credenciais.
- [ ] Publicar relatorio de entrega com nomes, Discord, documentacao, repositorios e video.
- [ ] Retornar Ingress a privado e remover recursos/trial de cada conta apos concluir a entrega.

**Parecer desta revisao:** a arquitetura, os scripts, os manifests, os testes e o historico da assinatura de referencia **cobrem tecnicamente os requisitos centrais** listados no enunciado. **Nao declarar entrega final 100% concluida** antes do teste ponta a ponta independente, da gravacao do live deploy, da demonstracao publica do Ingress e do relatorio final. Nenhum bloqueio exige usar credenciais do desenvolvedor principal; dificuldades de IAM, quota ou subject OIDC devem ser resolvidas na conta do apresentador.
