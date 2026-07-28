-- =================================================================================
-- DP-800 - LAB PRATICO COMPLETO: EXTERNAL MODELS E AI_GENERATE_EMBEDDINGS
-- Banco de Dados: AdventureWorks2025 (ou LT - Light / 2022 - funciona o lab)
-- =================================================================================
-- OBJETIVOS DE APRENDIZADO (alinhados DP-800 Dominio 3 - 25 a 30%):
--   1. Fundamentos: embeddings = representacao vetorial densa do significado
--   2. Dimensoes dos modelos: 1536 (ada-002, 3-small) vs 3072 (3-large)
--   3. Criar DATABASE SCOPED CREDENTIAL e CREATE EXTERNAL MODEL sintaxe oficial
--   4. Diferenca critica EXAME: permissao EXECUTE vs ALTER ANY EXTERNAL MODEL
--   5. AI_GENERATE_EMBEDDINGS - linha unica e em lote com WHERE NULL
--   6. VECTORPROPERTY: Dimensions e BaseType
--   7. Matriz de 7 capacidade + 7 modelos + 8 casos de uso
--   8. Gerenciamento deployments Azure: versionamento, quota, TPM, Monitor
--   9. Questao estilo exame com gabarito explicado
-- =================================================================================
-- REFERENCIAS MICROSOFT LEARN:
--   - External Models in Fabric SQL:
--     https://learn.microsoft.com/en-us/fabric/database/sql/ai-external-model
--   - CREATE EXTERNAL MODEL T-SQL:
--     https://learn.microsoft.com/en-us/sql/t-sql/statements/create-external-model-transact-sql
--   - Azure OpenAI Models:
--     https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/models
--   - VECTOR Data Type:
--     https://learn.microsoft.com/en-us/sql/t-sql/data-types/vector-data-type
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/09-models-embeddings/01-external-models.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================

USE AdventureWorks2025;
GO

-- =================================================================================
-- LIMPEZA PREVENTIVA (safe re-run)
-- =================================================================================
DROP PROCEDURE IF EXISTS lab.usp_SelectEmbeddingModelForWorkload;
DROP PROCEDURE IF EXISTS lab.usp_EmbedAdventureWorksProducts;
DROP TABLE IF EXISTS lab.EmbeddedProducts;
GO

CREATE SCHEMA IF NOT EXISTS lab AUTHORIZATION dbo;
GO

IF EXISTS (SELECT * FROM sys.external_models WHERE name = N'AzureOpenAI_Embedding3Small')
    DROP EXTERNAL MODEL [AzureOpenAI_Embedding3Small];

IF EXISTS (SELECT * FROM sys.external_models WHERE name = N'AzureOpenAI_Embedding3Large')
    DROP EXTERNAL MODEL [AzureOpenAI_Embedding3Large];

IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = N'AzureOpenAIApiCred')
    DROP DATABASE SCOPED CREDENTIAL [AzureOpenAIApiCred];
GO

PRINT '=========================================================';
PRINT '  LAB 09-ME (01) PARTE 1/7: FUNDAMENTOS DE EMBEDDINGS E VETORES';
PRINT '=========================================================';
GO

-- =================================================================================
-- PARTE 1: Fundamentos - O que e um embedding?
-- =================================================================================
-- O QUE CAI NO EXAME:
-- - Embedding = vetor denso de floats representando SIGNIFICADO SEMANTICO
-- - Dimensao e FIXA por modelo. Misturar dimensoes = busca quebrada.
-- - Sempre guarde o TEXTO ORIGINAL junto do vetor (RAG precisa do texto!)

SELECT
    N'Vetor de embedding / VECTOR(n)' AS Conceito,
    N'Lista de n floats que captura o "significado" de um texto ou dado' AS Definicao,
    N'Mesmo que nao haja palavras identicas, frases semanticamente proximas estao "perto" no espaco vetorial' AS Proposito,
    N'Azure SQL tipo nativo:     VECTOR(1536)  ou  VECTOR(3072)' AS TipoSQL,
    N'Armazenamento por linha:  1536 * 4 bytes = 6KB   (3-large: 12KB)' AS TamanhoDisco,
    N'Busca: funcoes de distancia (cosine / euclidean / dot) ou VECTOR_SEARCH' AS ModoBusca
UNION ALL
SELECT
    N'Dimensao = propriedade do MODELO, nao do dado',
    N'Cada modelo produz uma dimensao fixa (ex: 1536 ou 3072)',
    N'Coluna VECTOR(n) deve ter n IGUAL a dimensao do modelo. Nao ha downgrade/upgrade automatico.',
    N'text-embedding-3-small  = 1536 dims',
    N'text-embedding-3-large  = 3072 dims',
    N'text-embedding-ada-002  = 1536 dims  (legado, use 3-small)'
UNION ALL
SELECT
    N'Regra critica de incompatibilidade',
    N'Trocar de modelo (ex: ada-002 -> 3-small) ou de dimensao',
    N'TODOS os embeddings existentes devem ser REGENERADOS; nao compare vetores de modelos diferentes',
    N'UPDATE ... SET Embedding = AI_GENERATE_EMBEDDINGS(...)   SEM WHERE (re-embed total)',
    N'Armazene model_version + embedded_at para auditoria',
    N'DP-800 sempre pergunta: "mudei de modelo, o que devo fazer?" -> REGENERAR TUDO';
GO

-- =================================================================================
-- PARTE 2: Dimensoes de Capacidade + Tabela de 7 Modelos (Oficial MS Learn)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (01) PARTE 2/7: 7 DIMENSOES DE CAPACIDADE + 7 MODELOS';
PRINT '=========================================================';
GO

-- --- 2.1 7 Dimensoes de capacidade para avaliar modelos ---
SELECT
    N'Multimodal'                 AS DimensaoDeCapacidade,
    N'Processa imagens/audios/videos alem de texto'  AS Consideracoes,
    N'GPT-4o, GPT-4o Vision (OCR em foto de etiqueta)' AS Exemplos
UNION ALL SELECT N'Multilingue',
    N'Qualidade em outros idiomas (portugues, espanhol, etc.)',
    N'GPT-4o, text-embedding-3-large (melhor semantica em PT-BR)'
UNION ALL SELECT N'Saida estruturada (JSON / function calling)',
    N'Saida JSON confiavel, schema definido, chamadas de funcao',
    N'GPT-4o, GPT-4o-mini (response_format=json_object -> 100% JSON valido)'
UNION ALL SELECT N'Dimensao do vetor (embeddings)',
    N'Maior = mais discriminacao semantica; porem mais storage e custo',
    N'1536 (3-small), 3072 (3-large). Default recomendado = 1536.'
UNION ALL SELECT N'Janela de contexto',
    N'Maximo tokens in+out; afeta tamanho de chunk e conversas',
    N'8k (gpt-35 legado), 128k (4o-mini / 4o), 200k+ (o1-series)'
UNION ALL SELECT N'Latencia',
    N'Tempo por request; modelos menores = mais rapidos',
    N'gpt-4o-mini < gpt-4o < o1 (4o-mini ~ 90% mais barato e + rapido que 4o)'
UNION ALL SELECT N'Custo',
    N'Por mil tokens de input/output; use custo-beneficio',
    N'4o-mini << 4o; 3-small custo 0.5x ada-002 com qualidade melhor.';
GO

-- --- 2.2 Tabela Oficial: 7 modelos + Tipo + Melhor Para ---
-- OBSERVACAO DP-800: gpt-35-turbo = OBSOLETO / descontinuado. Substituto = gpt-4o-mini.
SELECT
    N'text-embedding-3-small'              AS Modelo,
    N'Embedding'                            AS Tipo,
    N'Equilibrio perfeito / custo-beneficio. 1536 dims. MODELO PADRAO.' AS MelhorPara,
    1536                                    AS Dimensao_Embedding,
    N'0.5x o preco do ada-002, qualidade MELHOR. Substitui ada-002 HOJE.' AS Observacao
UNION ALL SELECT
    N'text-embedding-3-large', N'Embedding',
    N'Maxima qualidade semantica, busca em documentos longos.',
    3072, N'Custo ~2x 3-small. 3072 dims = 12KB por linha. Use apenas se medir ganho real.'
UNION ALL SELECT
    N'text-embedding-ada-002 (LEGADO)', N'Embedding',
    N'Somente se voce ja tem milhoes de vetores existentes e nao pode re-embedar.',
    1536, N'LEGADO. MS recomenda migrar para 3-small imediatamente.'
UNION ALL SELECT
    N'gpt-4o', N'Chat Completion',
    N'Raciocinio complexo RAG, multimodal (fotos), JSON estruturado.',
    NULL, N'Quando a QUALIDADE da resposta importa mais que custo.'
UNION ALL SELECT
    N'gpt-4o-mini', N'Chat Completion',
    N'90% dos fluxos RAG de producao. Substituto direto do gpt-35-turbo.',
    NULL, N'RECOMENDADO PADRAO. Menor custo, maior velocidade, otimo para PT-BR.'
UNION ALL SELECT
    N'o1', N'Reasoning Model',
    N'Problemas de logica, matematica, puzzles de multiplos passos.',
    NULL, N'Alta latencia, alto custo. NAO use para tarefas simples de RAG.'
UNION ALL SELECT
    N'o3-mini', N'Reasoning Model',
    N'Matematica / codigo com varios passos, menor custo que o1.',
    NULL, N'Bom para tarefas tecnicas (codigo SQL) que precisam de raciocinio.';
GO

-- --- 2.3 Trade-offs tamanho vs precisao ---
PRINT CHAR(13)+CHAR(10) + N'--- Trade-ofs: Custo x Dimensao x Latencia ---';
SELECT
    N'text-embedding-ada-002' AS Modelo,
    1536                      AS Dimensoes,
    N'Custo 1.0x (referencia)' AS CustoRelativo,
    N'Precisao base (legado)'  AS Precisao,
    N'Migrado para 3-small'    AS Recomendacao
UNION ALL SELECT N'text-embedding-3-small', 1536,
    N'Custo 0.5x (mais BARATO que ada-002!)',
    N'Superior ao ada-002',
    N'>>> PADRAO RECOMENDADO para todos os novos projetos'
UNION ALL SELECT N'text-embedding-3-large', 3072,
    N'Custo 2.0x',
    N'Melhor precisao semantica, busca mais assertiva',
    N'Apenas se 3-small nao alcancar o recall desejado no seu dataset real.';
GO

-- =================================================================================
-- PARTE 3: DATABASE SCOPED CREDENTIAL + CREATE EXTERNAL MODEL (Sintaxe Oficial)
-- =================================================================================
-- PONTO DP-800:
--   IDENTITY = 'HTTPEndpointHeaders' -> SECRET JSON vira HEADERS HTTP.
--   NUNCA coloque a chave dentro de @payload ou @headers da procedure.

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (01) PARTE 3/7: CREDENCIAL + CREATE EXTERNAL MODEL';
PRINT '=========================================================';
GO

PRINT '-------------------------------------------------------------------';
PRINT '  BLOCO DIDATICO: Criacao da Credencial + 2 External Models';
PRINT '  (Descomente apenas se tiver uma Azure OpenAI provisionada REAL)';
PRINT '-------------------------------------------------------------------';
PRINT '';
PRINT '/*';
PRINT '  -- 3.1. DATABASE SCOPED CREDENTIAL (API key injetada via HEADERS)';
PRINT '  CREATE DATABASE SCOPED CREDENTIAL [AzureOpenAIApiCred]';
PRINT '  WITH IDENTITY = N''HTTPEndpointHeaders'',';
PRINT '       SECRET   = N''{"api-key": "sua-chave-real-aqui-xxxxxxxxxxx"}'';';
PRINT '';
PRINT '  -- 3.2 External Model 1: text-embedding-3-small (PADRAO = 1536 dims)';
PRINT '  CREATE EXTERNAL MODEL [AzureOpenAI_Embedding3Small]';
PRINT '  WITH (';
PRINT '      LOCATION   = N''https://SEURECURSO.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings'',';
PRINT '      API_FORMAT = N''Azure OpenAI'',    -- <- sem underscore, valor documentado';
PRINT '      MODEL_TYPE = EMBEDDINGS,';
PRINT '      MODEL      = N''text-embedding-3-small'',';
PRINT '      CREDENTIAL = [AzureOpenAIApiCred]';
PRINT '  );';
PRINT '';
PRINT '  -- 3.3 External Model 2: text-embedding-3-large (3072 dims - qualidade max)';
PRINT '  CREATE EXTERNAL MODEL [AzureOpenAI_Embedding3Large]';
PRINT '  WITH (';
PRINT '      LOCATION   = N''https://SEURECURSO.openai.azure.com/openai/deployments/text-embedding-3-large/embeddings'',';
PRINT '      API_FORMAT = N''Azure OpenAI'',';
PRINT '      MODEL_TYPE = EMBEDDINGS,';
PRINT '      MODEL      = N''text-embedding-3-large'',';
PRINT '      CREDENTIAL = [AzureOpenAIApiCred]';
PRINT '  );';
PRINT '*/';
PRINT '';
PRINT N'>>> IMPORTANTE sobre cada parametro do CREATE EXTERNAL MODEL:';
PRINT N'    LOCATION     = URL COMPLETA do endpoint do deployment (ate /embeddings)';
PRINT N'    API_FORMAT   = Azure OpenAI | OpenAI | Ollama | ONNX Runtime';
PRINT N'    MODEL_TYPE   = EMBEDDINGS  (obrigatorio para AI_GENERATE_EMBEDDINGS)';
PRINT N'    MODEL        = nome do modelo hospedado';
PRINT N'    CREDENTIAL   = nome do objeto DATABASE SCOPED CREDENTIAL (nao a chave!)';
PRINT N'';
PRINT N'>>> Regra de seguranca: coloque os modelos em schema [ai] ou [lab], nao em [dbo].';
PRINT N'    Facilita o gerenciamento de permissao sem dar db_owner.';
GO

-- --- 3.4 Consultar catalogo sys.external_models ---
PRINT CHAR(13)+CHAR(10) + N'--- Catalog view sys.external_models (sempre havera linhas reais se voce descomentar o bloco acima) ---';
SELECT
    name,
    model_type_desc,
    location,
    CAST(NULL AS SYSNAME) AS credential_name,
    CAST(NULL AS DATE)    AS create_date,
    CAST(NULL AS DATE)    AS modify_date
WHERE 1 = 2       -- zero linhas enquanto nao houver external model real
UNION ALL
SELECT 'AzureOpenAI_Embedding3Small' AS name,
       N'EMBEDDINGS'                 AS model_type_desc,
       N'https://SEURECURSO.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings',
       N'AzureOpenAIApiCred',
       CAST(GETDATE() AS DATE), CAST(GETDATE() AS DATE);
GO

PRINT CHAR(13)+CHAR(10) + N'--- ALTER e DROP didaticos ---';
PRINT N'-- Trocar a credencial (ex: rotacao de API key):';
PRINT N'  ALTER EXTERNAL MODEL [AzureOpenAI_Embedding3Small] WITH (CREDENTIAL = [NovaCredencial]);';
PRINT N'';
PRINT N'-- Remover modelo obsoleto (ex: migrando de ada-002):';
PRINT N'  DROP EXTERNAL MODEL [OldAda002Model];';
GO

-- =================================================================================
-- PARTE 4: PERMISSOES - EXECUTE vs ALTER ANY EXTERNAL MODEL (DICA DO EXAME!)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (01) PARTE 4/7: PERMISSOES (Cai no Exame!)';
PRINT '=========================================================';
GO

-- Tabela comparativa oficial.
SELECT
    N'EXECUTE ON EXTERNAL MODEL <nome>'  AS Permissao,
    N'Permite USAR (chamar) o modelo. AI_GENERATE_EMBEDDINGS(...) com sucesso.' AS OQuePermite,
    N'Nao. So permite executar o modelo ja existente.' AS CriaOuModifica,
    N'Application Roles, Users de API, ReportingRole, DataAnalystRole' AS QuemDeveReceber,
    N'>>> EH O QUE O EXAME PEDIRA para usuarios que precisam GERAR embeddings' AS ObservacaoExame
UNION ALL SELECT
    N'ALTER ANY EXTERNAL MODEL',
    N'Permite CRIAR, ALTERAR, DROPAR external models no banco inteiro.',
    N'SIM. Permite criar novos e mexer em todos os existentes.',
    N'DBA, DatabaseDeveloper, Lead AI Engineer. Apenas admin.',
    N'NAO conceda isto a usuarios comuns! ERRO COMUM no exame: usuario de relatorio nao precisa disto.'
UNION ALL SELECT
    N'SELECT em sys.external_models',
    N'Apenas ver a lista de modelos existentes (metadados: name, location).',
    N'Nao. So visualizar.',
    N'Qualquer usuario que precise diagnosticar / documentar.',
    N'Nao substitui EXECUTE. Ver metadados nao permite chamar AI_GENERATE_EMBEDDINGS!';
GO

PRINT CHAR(13)+CHAR(10) + N'--- Sintaxe exemplos GRANT ---';
PRINT N'-- Certo: permitir que o time de analise use um modelo ESPECIFICO:';
PRINT N'  GRANT EXECUTE ON EXTERNAL MODEL [lab].[AzureOpenAI_Embedding3Small] TO DataAnalystRole;';
PRINT N'';
PRINT N'-- Errado (excesso de privilegio): nao faca isso para usuarios comuns!';
PRINT N'  GRANT ALTER ANY EXTERNAL MODEL TO DataAnalystRole;   -- errado: permissao de admin';
PRINT N'';
PRINT N'-- Muito errado (ainda pior):';
PRINT N'  EXEC sp_addrolemember ''db_owner'', ''um_usuario_comum'';   -- overkill, anti-padrao seguranca';
GO

-- =================================================================================
-- PARTE 5: AI_GENERATE_EMBEDDINGS + AdventureWorks Dados Reais
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (01) PARTE 5/7: AI_GENERATE_EMBEDDINGS c/ AdventureWorks';
PRINT '=========================================================';
GO

-- Tabela para armazenar embeddings de produtos AdventureWorks (dados reais)
CREATE TABLE lab.EmbeddedProducts (
    ProductID        INT            NOT NULL PRIMARY KEY,
    ProductName      NVARCHAR(200)  NOT NULL,
    CategoryName     NVARCHAR(100)  NOT NULL,
    SubcategoryName  NVARCHAR(100)  NOT NULL,
    ListPrice        DECIMAL(10,2)  NOT NULL,
    TextToEmbed      NVARCHAR(MAX)  NOT NULL,
    Embedding3Small  VECTOR(1536)   NULL,    -- 3-small: 1536
    EmbeddedModelID  SYSNAME        NULL,    -- nome do external model usado
    EmbeddedAt       DATETIME2      NULL     -- timestamp de geracao
);
GO

-- 5.1 Montar TextToEmbed: concatenar NOME + CATEGORIA + SUBCATEGORIA + PRECO + DESCRICAO
-- (REGRA DE QUALIDADE: prefixar cada campo com "NomeDoCampo: " - melhora semantica!)
INSERT INTO lab.EmbeddedProducts
    (ProductID, ProductName, CategoryName, SubcategoryName, ListPrice, TextToEmbed)
SELECT TOP 25
    p.ProductID,
    p.Name,
    pc.Name,
    psc.Name,
    p.ListPrice,
    CONCAT(
        N'Product: ',       p.Name,        N'. ',
        N'Category: ',      pc.Name,       N'. ',
        N'Subcategory: ',   psc.Name,      N'. ',
        N'ListPrice: R$ ',  CAST(p.ListPrice AS VARCHAR(20)), N'. ',
        N'Description: ',   ISNULL(CAST(pd.Description AS NVARCHAR(500)), N'Sem descricao disponivel.')
    ) AS TextToEmbed
FROM Production.Product p
INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
INNER JOIN Production.ProductCategory pc     ON pc.ProductCategoryID = psc.ProductCategoryID
LEFT JOIN Production.ProductModelProductDescriptionCulture pmpdc
    ON pmpdc.ProductModelID = p.ProductModelID AND pmpdc.CultureID = 'en'
LEFT JOIN Production.ProductDescription pd ON pd.ProductDescriptionID = pmpdc.ProductDescriptionID
WHERE p.ListPrice > 0
ORDER BY pc.Name, psc.Name;
GO

SELECT ProductID, ProductName, CategoryName, ListPrice, LEFT(TextToEmbed, 200) AS PreviewTextToEmbed
FROM lab.EmbeddedProducts
ORDER BY ProductID;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 5.2 AI_GENERATE_EMBEDDINGS sintaxe oficial (didatico / execute real) ---';
PRINT N'/*';
PRINT N'  -- Linha unica (teste / POC):';
PRINT N'  SELECT AI_GENERATE_EMBEDDINGS(';
PRINT N'      N''Capacete de ciclismo leve com ventilacao extra''';
PRINT N'      USE MODEL [lab].[AzureOpenAI_Embedding3Small]';
PRINT N'  ) AS SingleEmbeddingJSON;';
PRINT N'';
PRINT N'  -- Lote: atualizar apenas produtos sem embedding (WHERE Embedding IS NULL)';
PRINT N'  -- BOA PRATICA: UPDATE em lote > row-by-row cursor. Menos round-trips de API.';
PRINT N'  UPDATE ep';
PRINT N'  SET';
PRINT N'      Embedding3Small = AI_GENERATE_EMBEDDINGS( ep.TextToEmbed';
PRINT N'                                      USE MODEL [lab].[AzureOpenAI_Embedding3Small] ),';
PRINT N'      EmbeddedModelID  = N''text-embedding-3-small'',';
PRINT N'      EmbeddedAt       = SYSUTCDATETIME()';
PRINT N'  FROM lab.EmbeddedProducts ep';
PRINT N'  WHERE ep.Embedding3Small IS NULL;   -- <- SEMPRE processe apenas pendentes';
PRINT N'*/';
GO

-- 5.3 VECTORPROPERTY: verificar dimensoes do vetor depois de gerar
PRINT CHAR(13)+CHAR(10) + N'--- 5.3 VECTORPROPERTY: Verificar Dimensoes e BaseType apos gerar ---';
PRINT N'/*';
PRINT N'  SELECT';
PRINT N'      ProductID,';
PRINT N'      ProductName,';
PRINT N'      VECTORPROPERTY(Embedding3Small, ''Dimensions'') AS DimensoesVetor,   -- <- Esperado 1536';
PRINT N'      VECTORPROPERTY(Embedding3Small, ''BaseType'')   AS TipoBaseNumerico  -- <- REAL / FLOAT';
PRINT N'  FROM lab.EmbeddedProducts';
PRINT N'  WHERE Embedding3Small IS NOT NULL;';
PRINT N'';
PRINT N'  >>> Verifique que Dimensions = 1536. Se aparecer NULL ou 0: embedding vazio/erro.';
PRINT N'  >>> Se aparecer outra dimensao (ex: 3072 no lugar de 1536): usou modelo errado!';
PRINT N'*/';
GO

-- Simulacao visual de VECTORPROPERTY:
SELECT
    N'Exemplo apos rodar AI_GENERATE_EMBEDDINGS com 3-small' AS Produto,
    CAST(1536 AS INT)               AS [Dimensoes (Esperado)],
    N'real'                         AS [BaseType (Esperado)],
    N'Corresponde a coluna VECTOR(1536). Tudo ok!' AS Validacao
UNION ALL SELECT
    N'Cenario de erro: usou 3-large na coluna de 1536',
    CAST(3072 AS INT),
    N'real',
    N'ERRO! Dimension mismatch. VECTOR_SEARCH vai retornar lixo. Re-gerar TUDOS com modelo correto.';
GO

-- =================================================================================
-- PARTE 6: Matriz de Decisao (8 Cenarios) + Gerenciamento de Deployments
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (01) PARTE 6/7: MATRIZ DECISAO + DEPLOYMENTS AZURE';
PRINT '=========================================================';
GO

--- 6.1 Matriz de decisao 8 casos de uso -> modelo recomendado (EXAME COME ISSO!)
SELECT
    N'Geracao de embedding PADRAO (equilibrio custo/precisao)' AS CasoDeUso,
    N'text-embedding-3-small'                                  AS ModeloRecomendado,
    N'Otimo para similaridade vetorial; baixo custo; 1536 dims.' AS Porque
UNION ALL SELECT
    N'Geracao embedding MAXIMA QUALIDADE (busca em 100k+ docs)',
    N'text-embedding-3-large',
    N'Melhor precision@k; 3072 dims; compensa em corpus grandes.'
UNION ALL SELECT
    N'Sistema RAG existente que usa ada-002 ha anos (migracao)',
    N'text-embedding-3-small',
    N'Mesma dimensao 1536 (muda so a coluna nao!); re-embedar TUDOS.'
UNION ALL SELECT
    N'Chat RAG complexo (documentos juridicos/financeiros, raciocinio)',
    N'gpt-4o',
    N'Multimodal, JSON, alta qualidade para perguntas longas.'
UNION ALL SELECT
    N'Chatbot de FAQ / Suporte alto volume (custo sensivel)',
    N'gpt-4o-mini',
    N'~90% mais barato que gpt-4o. Substituto oficial do obsoleto gpt-35-turbo.'
UNION ALL SELECT
    N'Corretor de exercicios de SQL / Matematica / codificacao',
    N'o1 ou o3-mini',
    N'Modelos de raciocinio com chains-of-thought nativas.'
UNION ALL SELECT
    N'Geracao de codigo T-SQL + explicacao didatica',
    N'gpt-4o',
    N'Excelente em T-SQL moderno, FOR JSON, VECTOR, window functions.'
UNION ALL SELECT
    N'Classificacao binaria ou multiclasse simples (sentimento, rotulacao)',
    N'gpt-4o-mini',
    N'Inferencia ultra rapida + barata. Suficiente para a maioria das classificacoes.';
GO

--- 6.2 Fluxograma de decisao texto
PRINT CHAR(13)+CHAR(10) + N'--- Fluxograma Didatico para o exame ---';
PRINT N'';
PRINT N'Preciso de um MODELO DE EMBEDDING?';
PRINT N'  |- Preciso de MAXIMA precisao semantica? -> SIM -> text-embedding-3-large (3072)';
PRINT N'  |- Senao (equilibrio custo-beneficio PADRAO) ->     text-embedding-3-small (1536)';
PRINT N'  |- Apenas sistema legado sem migracao? ->          text-embedding-ada-002 (sair!)';
PRINT N'';
PRINT N'Preciso de um MODELO DE CHAT (RAG / completion)?';
PRINT N'  |- Precisa de imagem/ocr/multimodal ou RACIOCINIO COMPLEXO? -> gpt-4o';
PRINT N'  |- Custo sensivel, alto volume, substituindo gpt-35? ->          gpt-4o-mini';
PRINT N'  |- Matematica, puzzles logicos, codificacao multi-etapa? ->      o1 / o3-mini';
PRINT N'';
PRINT N'>>> Observacao: gpt-35-turbo = OBSOLETO. Sempre que aparecer uma alternativa 4o-mini,';
PRINT N'    marque a resposta alternativa 4o-mini como correta no exame.';
GO

--- 6.3 Gerenciamento de Deployments no Azure
PRINT CHAR(13)+CHAR(10) + N'--- Gerenciamento Deployments (Azure OpenAI Studio / Portal) ---';
SELECT
    N'Criacao do Deployment'            AS Topico,
    N'No Azure OpenAI Studio: Deployments -> Create -> escolher modelo + versao -> NOMEAR (ex: gpt-4o-mini).' AS Detalhe,
    N'O NOME do deployment entra no path da LOCATION do EXTERNAL MODEL.' AS ObservacaoDP800
UNION ALL SELECT
    N'Versionamento de modelo',
    N'Usa Default (auto-update para ultimo patch) ou fixa versao ex: gpt-4o-mini@2024-07-18.',
    N'PRODUCAO: fixe versao (reprodutibilidade). LAB/homolog: use auto-update.'
UNION ALL SELECT
    N'Quota de TPM (Tokens Per Minute)',
    N'Cada deployment tem limite de tokens/min. Padrao ~10k a 120k TPM.',
    N'Excedeu TPM -> 429 Too Many Requests. Aumentar via quota request portal + batching.'
UNION ALL SELECT
    N'Throughput Provisionado (PTU)',
    N'Garante latencia e capacidade por hora. Custo fixo por unidade PTU.',
    N'Cargas de trabalho mission-critical que nao podem sofrer throttling.'
UNION ALL SELECT
    N'Monitoramento (Azure Monitor / Log Analytics)',
    N'Metricas: TokensConsumed, PromptTokens, CompletionTokens, LatencyP50/P95, 4xx/5xx, ThrottledRequests.',
    N'Crie ALERTAS em erro > 5% ou p95 Latency > 2s. Nao deixe o throttling virar blackout.';
GO

-- =================================================================================
-- PARTE 7: Problemas Comuns + Boas Praticas + Questao Exame (Gabarito!)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (01) PARTE 7/7: PROBLEMAS + BOAS PRATICAS + QUESTAO EXAME';
PRINT '=========================================================';
GO

--- 7.1 Tabela Problemas Comuns x Causa x Correcao ---
SELECT
    N'Invalid API key (401 Unauthorized)' AS Problema,
    N'Secret da DATABASE SCOPED CREDENTIAL errado, vazio ou com aspas quebradas.' AS Causa,
    N'DROP + CREATE CREDENTIAL com SECRET = {"api-key":"..."} JSON valido; aspas duplas.' AS Correcao
UNION ALL SELECT
    N'Model not found (404 Not Found)',
    N'Nome do deployment na LOCATION nao existe ou esta apagado no OpenAI Studio.',
    N'Confira o deployment em Azure OpenAI Studio -> Deployments. Ajuste LOCATION do CREATE EXTERNAL MODEL.'
UNION ALL SELECT
    N'Dimension mismatch / coluna VECTOR(n) incompativel',
    N'Coluna e VECTOR(1536) mas usou modelo de 3072 (3-large).',
    N'CRIE coluna VECTOR(3072) ou use modelo 3-small. Ou se mudar de modelo, atualize TOTALMENTE a coluna.'
UNION ALL SELECT
    N'Rate limit exceeded / 429',
    N'Muitas chamadas/segundo ou TPM excedido.',
    N'Batching (UPDATE ... WHERE NULL em lote). Aumentar quota no Portal. Usar @retry_count do sp_invoke_external_rest_endpoint.'
UNION ALL SELECT
    N'Erro em AI_GENERATE_EMBEDDINGS sempre retorna NULL',
    N'MODEL_TYPE do external model nao e EMBEDDINGS, ou texto entrada null/too long.',
    N'Verifique sys.external_models.model_type_desc = EMBEDDINGS. Teste 1 texto curto primeiro. Limite do 3-small = 8191 tokens.'
UNION ALL SELECT
    N'Permission denied (usuario ao gerar embedding)',
    N'Faltou GRANT EXECUTE ON EXTERNAL MODEL para o usuario/role.',
    N'  GRANT EXECUTE ON EXTERNAL MODEL [modelo] TO ReportRole;   (NAO use ALTER ANY!)';
GO

--- 7.2 5 Boas Praticas Oficiais ---
PRINT CHAR(13)+CHAR(10) + N'--- 5 Boas Praticas (Microsoft Learn) ---';
PRINT N'';
PRINT N'  1. Schema dedicado [ai] ou [lab] com os EXTERNAL MODELs. GRANT EXECUTE por role. Nunca db_owner!';
PRINT N'  2. Padrao recomendado = text-embedding-3-small (1536). Suba para 3-large apenas se medir recall melhor.';
PRINT N'  3. Nao chame AI_GENERATE_EMBEDDINGS linha-a-linha com cursor. Sempre UPDATE ... WHERE Embedding IS NULL (lote).';
PRINT N'  4. Producao: fixe VERSÃO do modelo no deployment. Auto-update so em dev/homolog.';
PRINT N'  5. Azure Monitor: alerta em 429s, p95 latency e consumo de tokens. Antes de virar incidente!';
GO

--- 7.3 Questao Estilo EXAME DP-800 + Gabarito Explicado ---
PRINT CHAR(13)+CHAR(10) + N'================= QUESTAO DE PRATICA (ESTILO EXAME DP-800) =================';
PRINT N'';
PRINT N'Cenario:';
PRINT N'Voce tem um bando Azure SQL com uma tabela Production.ProductDescriptions. Um usuario';
PRINT N'pertencente a role [ReportingRole] consegue fazer SELECT na tabela, mas ao rodar:';
PRINT N'';
PRINT N'  SELECT AI_GENERATE_EMBEDDINGS(p.Description USE MODEL ai.EmbeddingModel)' AS foo';
PRINT N'  FROM Production.ProductDescriptions p;';
PRINT N'';
PRINT N'Recebe o erro: "Permission denied on external model ai.EmbeddingModel".';
PRINT N'';
PRINT N'Pergunta: Qual a acao correta e MINIMA (principio do menor privilegio)?';
PRINT N'';
PRINT N'  A. GRANT SELECT ON sys.external_models TO ReportingRole;';
PRINT N'  B. GRANT EXECUTE ON EXTERNAL MODEL [ai].[EmbeddingModel] TO ReportingRole;';
PRINT N'  C. GRANT ALTER ANY EXTERNAL MODEL TO ReportingRole;';
PRINT N'  D. EXEC sp_addrolemember @rolename = ''db_owner'', @membername = ''ReportingRole'';';
PRINT N'';
PRINT N'================================== GABARITO ==================================';
PRINT N'';
PRINT N'  >>> RESPOSTA CORRETA: B';
PRINT N'';
PRINT N'  Por que?';
PRINT N'    A -> Errado. SELECT em sys.external_models so permite VER os metadados do modelo. Nao permite chama-lo.';
PRINT N'    B -> Correto. AI_GENERATE_EMBEDDINGS requer EXECUTE no external model ESPECIFICO. Menor privilegio.';
PRINT N'    C -> Errado. ALTER ANY e permissao de ADMINISTRADOR para CRIAR/ALTERAR/DROPAR modelos. Total overkill.';
PRINT N'    D -> Muito errado. db_owner viola todo principio de seguranca. Nunca marque isto no exame.';
PRINT N'==============================================================================';
GO

PRINT CHAR(13)+CHAR(10) + '>>> CHECKLIST DE CONCLUSAO LAB 09-ME 01:';
SELECT N'[OK] Entendi VECTOR(n), dimensoes e incompatibilidade de modelos' AS Item UNION ALL
SELECT N'[OK] Sei criar DATABASE SCOPED CREDENTIAL + CREATE EXTERNAL MODEL sintaxe oficial' UNION ALL
SELECT N'[OK] Sei a diferenca EXECUTE vs ALTER ANY EXTERNAL MODEL (cai no exame!)' UNION ALL
SELECT N'[OK] Uso AI_GENERATE_EMBEDDINGS em lote (WHERE Embedding IS NULL)' UNION ALL
SELECT N'[OK] Sei usar VECTORPROPERTY para validar Dimensions' UNION ALL
SELECT N'[OK] Conheco os 7 modelos e quando usar cada um' UNION ALL
SELECT N'[OK] Sei resolver 6 problemas comuns (401, 404, 429, mismatch, permission denied)' UNION ALL
SELECT N'[OK] Conheco 5 boas praticas e gerencio deployments Azure.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> PROXIMO: Lab 09-ME 02 - Manutencao de Embeddings (drift, 6 metodos, Foundry).';
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/09-models-embeddings/01-external-models.md
-- =================================================================================================
