---
title: "Revisão Final do DP-800 — Manhã do Exame"
type: study-material
tags:
  - dp-800
  - final-review
  - exam-prep
---

# Revisão Final do DP-800 — Manhã do Exame

> [!abstract] Leia isto em 20 minutos
>
> - Fatos com maior probabilidade de serem testados em todos os três domínios do exame
> - Leitura corrida, sem aprofundamentos — oriente sua mente antes de entrar na prova
> - Após a leitura: abra suas cheat sheets e revise as listas de verificação "Before the Exam, I Can…" (Antes do Exame, Eu Consigo...)

---

## Domínio 1: Design and Develop (35–40%)

- **Clustered Columnstore Index (CCI):** ideal para cargas de trabalho puramente analíticas; execução em modo lote (batch mode); buffers em rowstore delta retêm as inserções antes de comprimi-las. Para cargas mistas de OLTP + analytics, adicione um CCI *não clusterizado* (non-clustered CCI) sobre a tabela rowstore.
- **Tabelas temporais (Temporal tables):** a cláusula `FOR SYSTEM_TIME AS OF '2025-01-01T12:00:00'` realiza consultas point-in-time (em um ponto específico no tempo). As colunas `SysStartTime`/`SysEndTime` são gerenciadas pelo sistema. A tabela de histórico é criada automaticamente ou especificada pelo usuário.
- **Tabelas Ledger:** evidência de violação blockchain-style, apenas para anexação (append-only). Requer `GENERATED ALWAYS AS ROW START/END` + `LEDGER = ON`. Não é possível atualizar (`UPDATE`) ou excluir (`DELETE`) linhas no modo append-only.
- **Tabelas otimizadas para memória (Memory-optimized tables):** `DURABILITY = SCHEMA_AND_DATA` (sobrevive a reinicializações) vs `SCHEMA_ONLY` (dados perdidos ao reiniciar). Requer o uso de `MEMORY_OPTIMIZED = ON` e um filegroup específico no banco.
- **Funções JSON:** `JSON_VALUE` = retorna um valor escalar; `JSON_QUERY` = retorna um fragmento de objeto ou array; `OPENJSON` = converte JSON em linhas de tabela; `JSON_MODIFY` = atualiza um caminho (path) específico in-place; `FOR JSON PATH` = serializa linhas de tabela em formato JSON.
- **SEQUENCE vs IDENTITY:** `SEQUENCE` é um objeto independente no banco, compartilhado entre tabelas e aceita ciclos; `IDENTITY` é vinculado a uma coluna específica de uma tabela e não aceita ciclos de forma automática.
- **Particionamento:** a partição *function* define os intervalos de valores → a partição *scheme* mapeia esses intervalos para filegroups → a tabela utiliza o scheme. `$PARTITION.FunctionName(col)` retorna o número da partição correspondente. A troca de partições (partition switching) realiza cargas ou arquivamentos em massa instantâneos.
- **Recursive CTE:** composta por membro âncora (anchor member) `UNION ALL` membro recursivo (recursive member). O membro âncora executa uma vez; o recursivo roda repetidamente até que nenhuma linha seja retornada. `OPTION (MAXRECURSION n)` limita a profundidade da recursão.
- **Funções de janela (Window functions) em empates:** `ROW_NUMBER` = gera números sequenciais únicos (critério de desempate arbitrário); `RANK` = pula posições em caso de empate; `DENSE_RANK` = não pula números. `NTILE(n)` = divide os resultados em grupos (buckets).
- **Tabelas de Grafos (Graph tables):** criadas com `CREATE TABLE … AS NODE` ou `AS EDGE`. Consulte usando a cláusula `MATCH (A)-[E]->(B)`. Use `SHORTEST_PATH` para travessia de grafos. As tabelas de Edge (arestas) devem fazer referência a tabelas de NODE (nós).
- **Triggers:** `AFTER` dispara após a conclusão da instrução DML; `INSTEAD OF` dispara no lugar da instrução DML. As tabelas temporárias `INSERTED` (contém novos valores) e `DELETED` (valores antigos) estão ambas disponíveis nos triggers de `UPDATE`.
- **Inline TVF vs multi-statement TVF:** uma Inline Table-Valued Function (TVF) é expandida como uma view comum (o otimizador enxerga seu interior e permite paralelismo); uma multi-statement TVF atua como uma caixa preta (black box), impedindo o paralelismo e resultando em piores estimativas de cardinalidade.

---

## Domínio 2: Secure, Optimize, Deploy (35–40%)

- **TDE (Transparent Data Encryption):** criptografa todo o banco de dados em repouso (at rest); transparente para a aplicação; o servidor enxerga os dados em texto plano; habilitado por padrão no Azure SQL. Não protege dados em trânsito (in transit) — para isso, use TLS.
- **Always Encrypted:** criptografia em nível de coluna; o servidor NUNCA enxerga os dados em texto plano; o driver do cliente lida com criptografia/descriptografia. Chaves: CMK (Column Master Key, mantida no lado cliente no Key Vault) → CEK (Column Encryption Key, criptografada pela CMK e armazenada no banco) → dados da coluna.
- **DDM (Dynamic Data Masking):** oculta os valores originais para usuários não privilegiados no momento da consulta; NÃO criptografa os dados. A permissão `UNMASK` revela os dados reais. Máscaras disponíveis: `default()`, `email()`, `partial()`, `random()`.
- **RLS (Row-Level Security):** uma função de predicado de segurança retorna um filtro que é anexado à tabela usando `CREATE SECURITY POLICY`. É transparente para o usuário — ele simplesmente não vê as linhas ocultadas. Predicado de filtro (SELECT) vs predicado de bloqueio (INSERT/UPDATE/DELETE).
- **Precedência de Permissões:** a negação (`DENY`) sempre ganha da concessão (`GRANT`), mesmo que o `GRANT` venha por meio de uma regra de grupo/role. O comando `REVOKE` remove um `GRANT` ou `DENY` previamente aplicado — ele não nega permissão por si só.
- **Query Store:** persiste planos de consulta e estatísticas de execução entre reinicializações. Para forçar um plano, use `sp_query_store_force_plan`. Para desfazer, utilize `sp_query_store_unforce_plan`. Detecta regressões de plano automaticamente via Automatic Plan Correction.
- **Níveis de Isolamento (Isolation levels):** `READ COMMITTED` = padrão do SQL Server; `READ UNCOMMITTED` = permite leituras sujas (dirty reads); `REPEATABLE READ` = impede alterações de dados já lidos, mas permite linhas fantasma; `SERIALIZABLE` = isolamento total. `SNAPSHOT` = otimista, baseado em versionamento de linhas, ativado por transação (requer `ALLOW_SNAPSHOT_ISOLATION ON`). `RCSI` (Read Committed Snapshot Isolation) = configuração no nível do banco de dados que altera o comportamento padrão do `READ COMMITTED` para usar versionamento de linhas — configurado via `READ_COMMITTED_SNAPSHOT ON`.
- **Bloqueio (Blocking) vs Deadlock:** bloqueio = uma sessão espera por um recurso retido por outra (resolve-se quando o bloqueio é liberado); deadlock = ciclo de espera mútuo entre sessões (o SQL Server escolhe automaticamente uma vítima para abortar). Investigue usando `sys.dm_exec_requests` e `sys.dm_os_waiting_tasks`.
- **Projetos de Banco de Dados SQL (SQL DB Projects):** arquivo `.sqlproj`; compilação gera um arquivo `.dacpac`; a publicação (Publish via SqlPackage.exe) faz a implantação incremental de diferenças no banco de destino. Scripts pré e pós-implantação (pre/post-deployment) rodam fora da comparação incremental. `SqlPackage.exe /Action:Publish` implanta; `/Action:Extract` extrai um dacpac a partir de um banco de dados existente.
- **DAB (Data API Builder):** mapeia entidades do banco para endpoints REST (`/api/{Entity}`) e GraphQL (`/graphql`) via arquivo de configuração JSON; sem necessidade de código customizado. Suporta permissões baseadas em funções: anonymous, authenticated e role-based.
- **Change Data Capture vs Change Tracking:** CDC = captura os valores de antes e depois de cada linha modificada, dependendo do serviço SQL Server Agent; CT = mais leve, apenas registra o fato de que ocorreu uma alteração (mas não os dados alterados), não requer o SQL Server Agent.
- **Private endpoint vs service endpoint:** private endpoint = IP privado dentro da sua VNet (comunicação 100% privada); service endpoint = direciona o tráfego do serviço Azure pelo backbone interno da Azure, mas o endpoint do recurso permanece publicamente acessível.

---

## Domínio 3: AI Capabilities (25–30%)

- **Tipo de dados VECTOR:** `VECTOR(n)` — array de números de ponto flutuante com dimensão fixa. `VECTOR(1536)` = comumente usado para modelos como `text-embedding-3-small` ou `ada-002`; `VECTOR(3072)` = correspondente ao `text-embedding-3-large`.
- **VECTOR_DISTANCE:** busca exata de vizinhos mais próximos (ENN - Exact Nearest Neighbor). Sintaxe: `VECTOR_DISTANCE('cosine', v1, v2)`. Métricas disponíveis: `cosine` (cosseno), `euclidean` (euclidiana) e `dot` (produto escalar). Menores distâncias significam maior similaridade (exceto no produto escalar, onde valores maiores indicam maior similaridade).
- **VECTOR_SEARCH:** busca aproximada de vizinhos mais próximos (ANN - Approximate Nearest Neighbor) por meio de um índice DiskANN; ideal para cenários de larga escala. Suporta `cosine`, `dot` e `euclidean` — a **métrica do índice DiskANN deve ser idêntica** à métrica utilizada na consulta `VECTOR_SEARCH`.
- **VECTOR_NORMALIZE:** normaliza o vetor para comprimento unitário (L2 norm = 1). Após a normalização, o produto escalar (`dot`) passa a ser equivalente à similaridade de cosseno (`cosine`), sendo muito usado como proxy de alta performance.
- **Busca textual (Full-text search):** `CONTAINS` = busca exata por termos estruturados, proximidade de palavras e termos ponderados; `FREETEXT` = busca linguística por linguagem natural de forma mais ampla; ambos requerem um índice de texto completo (full-text index). `CONTAINSTABLE`/`FREETEXTTABLE` retornam os resultados com score de relevância (rank).
- **Busca híbrida com RRF (Reciprocal Rank Fusion):** combina resultados de busca vetorial com os resultados de busca por palavra-chave (FTS). A fórmula padrão é `score = Σ 1/(k + rank)` onde o padrão é `k=60`. Quanto maior o score RRF, melhor. Não é uma média de pontuações, mas sim um algoritmo de fusão por posições de classificação.
- **Fragmentação (Chunking):** tamanho fixo (previsível) vs semântico (respeita limites de frases e parágrafos). O uso de sobreposição de tokens (`overlap_tokens`) evita que contextos importantes sejam divididos nas fronteiras dos blocos. Chunks muito pequenos perdem contexto; chunks muito grandes diluem a relevância.
- **sp_invoke_external_rest_endpoint:** executa chamadas para APIs REST externas (ex: Azure OpenAI). Requer o uso de uma `DATABASE SCOPED CREDENTIAL` para armazenar o token de acesso de forma segura. O resultado retornado em JSON é extraído com `JSON_VALUE`/`JSON_QUERY`.
- **Fluxo do RAG:** (1) Gera o embedding da pergunta do usuário → (2) Busca no banco com `VECTOR_SEARCH` e `CONTAINS` → (3) Recupera os K blocos (chunks) mais relevantes → (4) Constrói o prompt (mensagem de sistema + contexto recuperado + pergunta do usuário) → (5) Envia ao LLM → (6) Retorna a resposta fundamentada ao usuário.
- **Fundamentação (Grounding):** o RAG fornece fatos e contexto ao modelo em *tempo de inferência* (inference time) — ele NÃO treina ou ajusta o modelo (fine-tuning). O LLM usa os dados apenas para gerar essa resposta pontual; os pesos internos do modelo não são alterados.
- **Estrutura de Prompt:** mensagem de sistema (regras/persona) + mensagem do usuário (pergunta + contexto). A temperatura regula a aleatoriedade (0 = determinístico, 1 = criativo). Para cenários de RAG, utilize temperaturas baixas para minimizar o risco de alucinação.

---

## Atualizações de 2026 — O que a Microsoft Acrescentou e Destacou

- **SQL Server 2025 em GA:** O tipo `VECTOR` e a função `VECTOR_DISTANCE` são oficiais e estão **GA** no SQL Server 2025 e no Azure SQL Database. As funções `VECTOR_SEARCH`, `VECTOR_NORMALIZE` e `VECTORPROPERTY` continuam em **public preview** nas mesmas plataformas.
- **Índice vetorial DiskANN:** em **public preview** no SQL Server 2025, Azure SQL Database, Azure SQL Managed Instance e bancos de dados SQL no Fabric. No SQL Server 2025 local, também requer `PREVIEW_FEATURES = ON`. A métrica de distância do índice DiskANN (`cosine`/`euclidean`/`dot`) deve coincidir com a métrica passada à consulta `VECTOR_SEARCH` — **uma divergência de métrica gera um aviso (warning) e faz o otimizador recuar para busca exata (kNN)**, sem disparar um erro de compilação.
- **Vetores de meia precisão (`float16`):** em preview; reduzem à metade o espaço de armazenamento físico para a mesma quantidade de dimensões. O limite documentado do tipo de dado `VECTOR` é de **1.998** dimensões de forma absoluta — o uso de float16 não estende esse limite.
- **Endpoints de servidor MCP (Model Context Protocol):** explicitamente cobrados. Utiliza-se protocolo `stdio` para integrações locais e `HTTP+SSE` para conexões hospedadas/remotas (ex: Fabric lakehouse). As credenciais devem ser repassadas via variáveis de ambiente, nunca escritas no arquivo de configuração do MCP. O servidor MCP roda sob o contexto de segurança e **permissões da string de conexão** configurada (princípio de menor privilégio).
- **Microsoft Foundry:** listado como um mecanismo nativo e gerenciado de manutenção de embeddings no Microsoft Fabric, integrando-se nativamente com triggers, CT, CDC, CES, Azure Functions e Logic Apps.
- **Change Event Streaming (CES):** fluxo push-based (baseado em envio) direto do banco SQL no Fabric para Eventstreams ou KQL databases. É uma alternativa de infraestrutura zero em relação ao CDC tradicional.
- **Detecção de desvios de esquema (Schema drift):** em Projetos de Banco de Dados SQL, pode ser gerenciada com SDK-style `.sqlproj`, gerando relatórios de divergência com `SqlPackage.exe /Action:DriftReport` ou por meio de visualização comparativa na extensão do VS Code.
- **Acesso sem senha (Passwordless):** String de conexão utilizando `Authentication=Active Directory Managed Identity`; criação do usuário no banco por meio de `CREATE USER [nome] FROM EXTERNAL PROVIDER`. É uma das abordagens de segurança mais cobradas nas provas.
- **Criação de Credenciais Seguras:** para a execução de chamadas externas com a procedure `sp_invoke_external_rest_endpoint`, a sintaxe recomendada de segurança sem senha é `CREATE DATABASE SCOPED CREDENTIAL ... WITH IDENTITY = 'Managed Identity'`.
- **Expansão da família REGEXP:** funções T-SQL adicionais suportadas no escopo: `REGEXP_LIKE`, `REGEXP_REPLACE`, `REGEXP_SUBSTR`, `REGEXP_INSTR`, `REGEXP_COUNT`, `REGEXP_MATCHES` e `REGEXP_SPLIT_TO_TABLE`. A função `REGEXP_SPLIT_TO_TABLE` retorna linhas de tabela, facilitando o processo de tokenização de textos no próprio banco.

---

## Pegadinhas e Armadilhas de Última Hora

1. **`JSON_VALUE` em caminhos contendo objetos ou arrays retorna NULL** — isso não causa erros de execução. Para retornar objetos ou fragmentos de arrays inteiros, use `JSON_QUERY`.
2. **A métrica do índice DiskANN deve bater com a métrica da consulta** — o DiskANN suporta `cosine`, `dot` e `euclidean`. A métrica do índice precisa ser a mesma da consulta. **Uma divergência de métrica NÃO causa erro** — ela gera um aviso interno e o SQL Server reverte silenciosamente a busca para busca exata (kNN linear). Crie um índice separado para cada métrica necessária.
3. **`DENY` sempre sobressai a um `GRANT`** — mesmo que o `GRANT` tenha sido herdado por meio de uma role hierarquicamente superior. A única forma de desfazer um `DENY` é aplicando um `REVOKE` no mesmo nível.
4. **Mascaramento de Dados (DDM) NÃO é criptografia** — o DDM mascara as informações na exibição, mas o dado é armazenado em texto plano físico. Administradores ou usuários que possuem o privilégio de `UNMASK` visualizam os dados originais.
5. **Isolamento de SNAPSHOT é diferente de RCSI** — o nível `SNAPSHOT` deve ser ativado manualmente na aplicação em cada transação; o `RCSI` (Read Committed Snapshot Isolation) altera globalmente o comportamento do nível `READ COMMITTED` padrão do banco de dados para utilizar versionamento de linhas de forma transparente.
6. **`VECTOR_SEARCH` com `WITH APPROXIMATE` é aproximado** — ele pode não encontrar o vizinho geograficamente mais próximo em troca de velocidade extrema. `VECTOR_DISTANCE` na cláusula `ORDER BY` tradicional sem a cláusula de busca aproximada é exato (ENN), porém consome muito mais processamento linear. Nas versões mais recentes, utilize `SELECT TOP (N) … WITH APPROXIMATE` (o parâmetro antigo `TOP_N` foi descontinuado e gera o erro Msg 42274).
7. **CMK (Column Master Key) permanece no cliente** — na arquitetura do Always Encrypted, a chave mestra reside no chaveiro local ou no Azure Key Vault do lado cliente, nunca sendo repassada ao SQL Server. O banco de dados armazena apenas a CEK em formato criptografado.
8. **`SqlPackage.exe /Action:Extract` é diferente de Publish** — o comando `/Action:Extract` extrai e gera um dacpac a partir de um banco de dados real ativo. O comando `/Action:Publish` publica um arquivo dacpac alterando o banco destino.
9. **Partition Function é diferente de Partition Scheme** — a *function* define os limites de valores lógicos das partições; o *scheme* distribui esses intervalos para filegroups físicos. Você precisa definir ambos para conseguir criar uma tabela particionada.
10. **RAG não realiza treinamento** — o contexto trazido do banco de dados é injetado dinamicamente no corpo do prompt para aquela requisição de inferência individual; os parâmetros de pesos fundamentais do modelo de linguagem (LLM) não são alterados.
