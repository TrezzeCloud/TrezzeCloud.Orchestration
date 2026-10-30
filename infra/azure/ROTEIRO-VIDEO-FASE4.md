# FCG — Roteiro do video final da Fase 4 (maximo 25 minutos)

**Apresentador:** integrante do grupo usando **a propria conta Azure, os proprios forks GitHub e seu Elastic Cloud**. **Preparacao:** siga integralmente [GUIA-INTEGRANTE-DO-ZERO.md](GUIA-INTEGRANTE-DO-ZERO.md) antes de gravar.

**Regra de evidencia:** mostre sempre uma operacao + resultado verificavel. Evite gravar longas instalacoes ou a criacao demorada do AKS; deixe a infraestrutura pronta e use capturas pontuais do provisionamento. O **live deploy** deve ser mostrado com push real, pipeline e resultado na aplicacao; nao substitua por simulacao. **Nunca mostre senhas, chaves, tokens ou valores de Kubernetes Secrets**.

## Roteiro com duracoes sugeridas

| Tempo | Cena | Tela/comando e comprovacao |
|---|---|---|
| 00:00–01:00 | Abertura | Identificar FIAP Cloud Games, grupo, Fase 4, objetivo e arquitetura. Explicar que a demonstracao usa conta propria do apresentador. |
| 01:00–04:00 | Kubernetes gerenciado e registry privado | Portal Azure: RG do apresentador, AKS, node pool Ready, ACR Basic. Terminal: kubectl get nodes; kubectl -n fcg-fase4 get deploy,pods,pvc. Mostrar 6/6 Ready e PVC Bound. |
| 04:00–06:30 | Ingress/exposicao HTTPS | Portal ou kubectl: Traefik, Ingress, LoadBalancer com External IP real. curl.exe -k -i https://IP/api/games => 200; /api/users => 401. Explicar certificado temporario autossinado e que APIs continuam ClusterIP. |
| 06:30–10:30 | Banco relacional, NoSQL e cache | Rodar ou mostrar resultado de test-users-demo.ps1, test-catalog-demo.ps1 e test-catalog-integrated.ps1. Comprovar usuarios/jogos no SQL, reviews criadas no MongoDB, JWT compartilhado e Redis miss/hit/TTL/invalidation. Nao afirmar ganho de latencia sem benchmark. |
| 10:30–14:00 | Busca avancada | Elastic Cloud Serverless no painel, sem mostrar API key. Executar test-search-integrated.ps1 com port-forwards; mostrar reindexacao, busca com erros de digitacao, update e desativacao. Se necessario, GET /search?q=cybr%20drft. Explicar ordenacao por relevancia. |
| 14:00–20:30 | Live deploy real e CI/CD | No proprio fork CatalogAPI, mostrar edicao simples do GameSearchController (header X-FCG-Fase4-Demo). Commit + push em main do fork. GitHub Actions: validate, search_integration, publish_deploy, login OIDC, push ACR SHA e rollout. Portal ACR mostra nova tag. GET /search retorna 200 e o header novo. |
| 20:30–22:30 | Seguranca e infraestrutura como codigo | Mostrar Bicep, manifests com secretKeyRef, GitHub Environment azure-demo sem revelar valores, IAM OIDC. Explicar segredos injetados em tempo de execucao. YAML e workflows versionados. |
| 22:30–24:00 | Reprodutibilidade e conclusao | Apontar README e guia para cada integrante, variaveis MemberId/SubscriptionId, seu fork e Elastic individuais; mostrar checklist do requisito e links do grupo. |
| 24:00–25:00 | Margem / encerramento | Reservar para atraso breve; fechar antes de 25 minutos. Evitar ficar esperando create cluster/Elastic durante filmagem. |

## Comandos de demonstracao preparados

Na raiz do seu clone Orchestration e com os valores definidos no guia:

~~~powershell
az aks show -g $rg -n $aks --query powerState.code -o tsv
kubectl get nodes
kubectl -n fcg-fase4 get deploy,pods,pvc,ingress
kubectl -n fcg-ingress get service fcg-traefik
az acr repository list -n $acr -o table
.\infra\azure\validate-cloud-fase4.ps1 -SubscriptionId $sub -ResourceGroup $rg -AksName $aks -AcrName $acr -ExpectedContext $context -RequireElasticSecret -RequirePublicIngress
~~~

Se for demonstrar os testes completos, mantenha dois terminais extras com port-forward UsersAPI 8080 e CatalogAPI 8081:

~~~powershell
.\infra\azure\test-users-demo.ps1
.\infra\azure\test-catalog-demo.ps1 -ExpectedContext $context
.\infra\azure\test-catalog-integrated.ps1 -ExpectedContext $context
.\infra\azure\test-search-integrated.ps1 -ExpectedContext $context
~~~

Para provar live deploy (depois do push no fork), abra o job GitHub Actions no navegador e execute:

~~~powershell
kubectl -n fcg-fase4 rollout status deployment/catalog-api
kubectl -n fcg-fase4 get deployment catalog-api -o wide
curl.exe -k -i "https://$ip/search?q=cybr%20drft"
~~~

## O que explicar para o avaliador

- **Kubernetes gerenciado:** cluster AKS e um registro ACR privado nativos da nuvem, nao container rodando isolado em VM IaaS.
- **Deploy:** manifests declarativos versionados e GitHub Actions com build/test, Docker tag SHA, push ao registry e rolling update.
- **SQL + NoSQL:** SQL Server guarda entidades transacionais; MongoDB guarda avaliacoes flexiveis de jogos.
- **Cache:** Redis armazena lista de jogos temporariamente; updates invalidam cache; TTL aparece nos testes. Nao compare desempenho sem medicao controlada.
- **Busca:** Elasticsearch externo gerenciado, indice de jogos sincronizado, fuzzy search tolerante a erros e ordenacao por relevancia.
- **Seguranca:** nenhuma senha de banco nem API key em YAML/codigo; secrets no Kubernetes, identidade federada de workflow sem client secret e acesso HTTPS de demonstração.
- **Isolamento da demonstracao:** AKS do video possui UsersAPI e CatalogAPI mais quatro dependencias. Os demais projetos de fases anteriores existem, mas nao estao nesses seis Deployments.

**Preflight do CI:** certifique-se de que https://github.com/TrezzeCloud/TrezzeCloud.CatalogAPI/pull/6 foi revisado e integrado antes de usar Run workflow manual na CatalogAPI; sem essa correcao, a dependencia search_integration fica skipped no workflow_dispatch. O push de codigo na main ja estava contemplado, mas a correcao permite reproduzir tambem a execucao manual.

## Checklist antes de apertar Gravar

- [ ] Subscription selecionada pertence ao apresentador e possui credito/quota disponivel
- [ ] Forks UsersAPI/CatalogAPI configurados com environment azure-demo do proprio usuario
- [ ] Cluster AKS Running, node Ready, seis Deployments Ready e dois PVCs Bound
- [ ] Testes SQL, Redis, MongoDB e JWT aprovados
- [ ] Teste Elasticsearch gerenciado aprovado usando a chave do apresentador
- [ ] Ingress Public disponivel durante filmagem, com IP real e HTTPS de demonstracao
- [ ] GitHub Actions em main do fork autorizado a atualizar o AKS
- [ ] Codigo da alteracao de live deploy pronto, mas nao enviado antes da filmagem
- [ ] Nomes e links de repositórios, documentacao e grupo conferidos
- [ ] Nao existe chave, senha, JWT nem Secret visivel em terminal ou navegador
- [ ] Gravador de tela e audio testados; plano para concluir abaixo de 25 minutos

## Depois do video

Salve video e capturas, entregue link no relatorio (grupo, participantes, usernames Discord, documentacao, repositorios, video). Retorne o Ingress para ClusterIP, remova temporarios quando todos aprovarem e encerre seu RG e seu projeto Elastic separadamente. Registre custos/limpeza sem expor IDs secretos.

**Importante:** o script estrutural nao prova o live deploy; a prova e a mudanca versionada, Actions success, tag ACR, rollout e comportamento HTTP atualizado na mesma sessao.
