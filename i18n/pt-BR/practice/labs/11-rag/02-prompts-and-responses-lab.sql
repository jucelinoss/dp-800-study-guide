-- =================================================================================
-- DP-800 - LAB PRATICO COMPLETO: PROMPTS E RESPOSTAS EM RAG VIA T-SQL
-- Banco de Dados: AdventureWorks2025 (ou LT - leve)
-- =================================================================================
-- OBJETIVOS DE APRENDIZADO (alinhados a DP-800 Dominio 3 - 25 a 30%):
--   1. Usar sp_invoke_external_rest_endpoint com TODOS os parametros oficiais
--   2. Criar DATABASE SCOPED CREDENTIAL com IDENTITY = 'HTTPEndpointHeaders'
--   3. Converter dados relacionais para JSON com FOR JSON PATH vs STRING_AGG
--   4. Construir prompts robustos (system/user + context injection + temperature)
--   5. Parsear respostas LLM: JSON_VALUE / JSON_QUERY / OPENJSON
--   6. Saida estruturada com response_format: { type: json_object }
--   7. Tratamento de erros robusto (TRY/CATCH + return_code + http_code)
--   8. Gerenciamento de tokens e orcamento de contexto
-- =================================================================================
-- REFERENCIA OFICIAL MICROSOFT LEARN:
--   sp_invoke_external_rest_endpoint:
--     https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-invoke-external-rest-endpoint-transact-sql
--   FOR JSON:
--     https://learn.microsoft.com/sql/relational-databases/json/format-query-results-as-json-with-for-json-sql-server
--   JSON Functions (JSON_VALUE/JSON_QUERY/OPENJSON):
--     https://learn.microsoft.com/sql/t-sql/functions/json-functions-transact-sql
--   Azure OpenAI Chat Completions:
--     https://learn.microsoft.com/azure/ai-services/openai/reference#chat-completions
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/11-rag/02-prompts-and-responses.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================

USE AdventureWorks2025;
GO

-- =================================================================================
-- LIMPEZA PREVENTIVA (safe re-run)
-- =================================================================================
DROP PROCEDURE IF EXISTS lab.usp_RagCallLlmProductAdvisor;
DROP PROCEDURE IF EXISTS lab.usp_RagSentimentAnalysisStructured;
DROP PROCEDURE IF EXISTS lab.usp_RagBatchClassifyFeedback;
DROP TABLE IF EXISTS lab.LlmCallLogs;
DROP TABLE IF EXISTS lab.RAGErrorLog;
DROP TABLE IF EXISTS lab.CustomerFeedback;
GO

CREATE SCHEMA IF NOT EXISTS lab AUTHORIZATION dbo;
GO

PRINT '=========================================================';
PRINT '  LAB 11-RAG (02) PARTE 1/7: SETUP E CREDENCIAIS';
PRINT '=========================================================';
GO

-- =================================================================================
-- PARTE 1: DATABASE SCOPED CREDENTIAL (Seguranca - PONTO CRITICO DP-800)
-- =================================================================================
-- CONCEITO CHAVE: Nunca hardcode API keys. Use CREDENCIAL escopo banco.
-- IDENTITY = 'HTTPEndpointHeaders' -> injeta o JSON secret como HEADERS HTTP.

PRINT '-------------------------------------------------------------------';
PRINT '  PASSO 1-A: Criar DATABASE SCOPED CREDENTIAL (APENAS UMA VEZ)';
PRINT '-------------------------------------------------------------------';
PRINT '';
PRINT '  SINTAXE OFICIAL (copie e adapte com sua chave real):';
PRINT '';
PRINT '  CREATE DATABASE SCOPED CREDENTIAL [AzureOpenAICredential]';
PRINT '  WITH IDENTITY = ''HTTPEndpointHeaders'',        -- <- Modo: injeta como HEADERS';
PRINT '       SECRET   = ''{"api-key": "SUA_CHAVE_AQUI"}''; -- <- Headers JSON injetados';
PRINT '';
PRINT '  PERIGO: NUNCA faca isto ->  @headers = N''{"api-key": "sk-..."}''  ';
PRINT '           (a chave fica exposta no plano de execucao e logs!)';
PRINT '';
PRINT '  Servicos na allowlist de sp_invoke_external_rest_endpoint:';
PRINT '    - Azure OpenAI, Azure AI Search, Azure Functions, etc.';
PRINT '  Para outros destinos use intermediario: Azure API Management (APIM).';
PRINT '';
PRINT '  Remover credencial (se precisar recriar):';
PRINT '    DROP DATABASE SCOPED CREDENTIAL IF EXISTS [AzureOpenAICredential];';
PRINT '-------------------------------------------------------------------';
GO

-- ---- Tabela de log das chamadas LLM (auditoria + troubleshooting) ----
CREATE TABLE lab.LlmCallLogs (
    LogId           INT              NOT NULL IDENTITY(1,1) PRIMARY KEY,
    SessionId       UNIQUEIDENTIFIER NULL,
    ProcedureReturnCode INT          NOT NULL,        -- Return do sp_invoke_...
    HttpStatusCode  INT              NULL,            -- $.response.status.http.code
    EndpointUrl     NVARCHAR(500)    NOT NULL,
    Payload         NVARCHAR(MAX)    NOT NULL,
    RawResponse     NVARCHAR(MAX)    NULL,
    PromptTokens    INT              NULL,
    CompletionTokens INT             NULL,
    TotalTokens     INT              NULL,
    ModelUsed       NVARCHAR(200)    NULL,
    LoggedAt        DATETIME2        NOT NULL DEFAULT GETUTCDATE()
);
GO

-- ---- Tabela de erros ----
CREATE TABLE lab.RAGErrorLog (
    ErrorId         INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    ProcedureName   NVARCHAR(200) NULL,
    ErrorMessage    NVARCHAR(MAX) NOT NULL,
    HttpStatusCode  INT           NULL,
    CorrelationId   UNIQUEIDENTIFIER NULL,
    PayloadSnapshot NVARCHAR(MAX) NULL,
    ErrorTime       DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);
GO

-- ---- Tabela auxiliar para Caso de Uso 3 (classificacao em lote) ----
CREATE TABLE lab.CustomerFeedback (
    FeedbackId   INT           NOT NULL PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    FeedbackText NVARCHAR(MAX) NOT NULL,
    Sentiment    NVARCHAR(20)  NULL,   -- Positivo / Negativo / Neutro
    TopicsJSON   NVARCHAR(MAX) NULL,   -- Array de topicos extraidos
    Confidence   DECIMAL(5,4)  NULL,   -- 0.0 a 1.0
    ProcessedAt  DATETIME2     NULL
);
GO

INSERT INTO lab.CustomerFeedback (FeedbackId, CustomerName, FeedbackText) VALUES
(1, N'Ana Souza',    N'A bicicleta chegou super rapido, montagem facil, estou amando!'),
(2, N'Carlos Lima',  N'O capacete veio com rachadura na parte traseira. Horrivel atendimento.'),
(3, N'Bruna Gomes',  N'Os oculos sao bonitos mas a lente arranhou facil. Nao sei se compensa.'),
(4, N'Diego Santos', N'Compra ok, entrega no prazo, produto igual ao anunciado. Nada a reclamar.'),
(5, N'Elisa Prado',  N'Atendimento perfeito, me ajudaram a escolher o tamanho certo da camisa!');
GO

PRINT '[OK] Tabelas auxiliares criadas: LlmCallLogs, RAGErrorLog, CustomerFeedback (5 rows)';
GO

-- =================================================================================
-- PARTE 2: sp_invoke_external_rest_endpoint - SINTAXE COMPLETA OFICIAL
-- =================================================================================
-- DP-800: Esta procedure e a ponte T-SQL <-> REST. Todos os parametros caem no exame.

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG (02) PARTE 2/7: Sintaxe sp_invoke_external_rest_endpoint';
PRINT '=========================================================';
GO

-- ---- Tabela de referencia dos parametros ----
SELECT
    N'@url'                           AS Parametro,
    N'NVARCHAR(4000)'                 AS Tipo,
    N'OBRIGATORIO'                    AS Obrigatoriedade,
    N'URL HTTPS completa do endpoint (ex: Azure OpenAI chat completions)' AS Descricao,
    N'https://<seu-recurso>.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-08-01-preview' AS ValorExemplo
UNION ALL SELECT N'@method',     N'VARCHAR(10)', N'OBRIGATORIO', N'Metodo HTTP: GET | POST | PUT | DELETE | PATCH', N'POST'
UNION ALL SELECT N'@headers',    N'NVARCHAR(MAX)', N'OPCIONAL', N'Objeto JSON com headers da requisicao (Content-Type, etc.)', N'{"Content-Type": "application/json"}'
UNION ALL SELECT N'@payload',    N'NVARCHAR(MAX)', N'OPCIONAL', N'Corpo da requisicao (JSON para POST/PUT)', N'{"messages":[...]}'
UNION ALL SELECT N'@credential', N'SYSNAME',       N'OPCIONAL', N'DATABASE SCOPED CREDENTIAL com IDENTITY=HTTPEndpointHeaders', N'[AzureOpenAICredential]'
UNION ALL SELECT N'@response',   N'NVARCHAR(MAX) OUTPUT', N'OPCIONAL', N'Variavel de saida com a resposta completa (JSON envelope)', N'DECLARE @resp NVARCHAR(MAX); ... @response = @resp OUTPUT'
UNION ALL SELECT N'@timeout',    N'INT',           N'OPCIONAL (padrao=30)', N'Timeout em segundos (ate 600 = 10min)', N'30'
UNION ALL SELECT N'@retry_count',N'TINYINT',       N'OPCIONAL (padrao=0, max=10)', N'Numero de retries automaticos para falhas transitorias', N'2';
GO

PRINT CHAR(13)+CHAR(10) + N'--- EXEMPLO DE CHAMADA COMPLETA (BLOCO DIDATICO, NAO EXECUTE SEM URL REAL) ---';
PRINT '';
PRINT '/*
DECLARE @response NVARCHAR(MAX), @return_code INT;
EXEC @return_code = sp_invoke_external_rest_endpoint
    @url        = N''https://SEU-RECURSO.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-08-01-preview'',
    @method     = N''POST'',
    @headers    = N''{"Content-Type": "application/json"}'',
    @payload    = @json_payload,              -- <- montado nas proximas etapas
    @credential = [AzureOpenAICredential],    -- <- segura, injeta api-key como header
    @response   = @response OUTPUT,
    @timeout    = 30,
    @retry_count = 2;
PRINT ''Codigo de retorno T-SQL (procedure): '' + CAST(@return_code AS VARCHAR);
PRINT ''Resposta HTTP envelope (JSON):''; PRINT @response;
*/';
GO

PRINT CHAR(13)+CHAR(10) + N'--- IMPORTANTE: ESTRUTURA DE DOIS ENVELOPES DA RESPOSTA ---';
PRINT '';
PRINT 'O @response SEMPRE tem dois envelopes JSON (conforme documentacao oficial):';
PRINT '';
PRINT '{';
PRINT '  "response": {                                 <-- Envelope HTTP da procedure';
PRINT '    "status":  { "http": { "code": 200 } },    <-- Código HTTP REAL';
PRINT '    "headers": { "Content-Type": "..." } },';
PRINT '  "result":   { ... }                          <-- Corpo real da API do OpenAI';
PRINT '}';
PRINT '';
PRINT '>>> REGRA DP-800: SEMPRE cheque os DOIS codigos de retorno:';
PRINT '    (1) @return_code        -> inteiro retornado pela procedure EXEC';
PRINT '    (2) $.response.status.http.code  -> codigo HTTP (JSON_VALUE)';
PRINT '';
PRINT 'Se http_code != 200: o $.result pode ser estrutura de ERRO, nao sucesso.';
GO

-- =================================================================================
-- PARTE 3: CONVERTER DADOS SQL PARA JSON / TEXTO LEGIVEL PARA O LLM
-- =================================================================================
-- DP-800: Duas abordagens para contexto em prompts: (a) FOR JSON ou (b) texto formatado.

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG (02) PARTE 3/7: FOR JSON e Contexto de Prompt';
PRINT '=========================================================';
GO

-- ---- Abordagem A: FOR JSON PATH (estruturado - bom para parsing posterior) ----
PRINT '>> Abordagem A: FOR JSON PATH (JSON estruturado)';
DECLARE @ProductsForJson NVARCHAR(MAX);
SELECT @ProductsForJson = (
    SELECT TOP 5
        p.ProductID   AS id,
        p.Name        AS name,
        p.ListPrice   AS price,
        pc.Name       AS category,
        CASE WHEN p.FinishedGoodsFlag = 1 THEN N'sim' ELSE N'nao' END AS finished_goods
    FROM Production.Product p
    INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
    INNER JOIN Production.ProductCategory pc ON pc.ProductCategoryID = psc.ProductCategoryID
    WHERE p.ListPrice > 0
    ORDER BY p.ListPrice ASC
    FOR JSON PATH, INCLUDE_NULL_VALUES
);
PRINT 'Conteudo via FOR JSON PATH:';
PRINT @ProductsForJson;
GO

-- ---- Abordagem B: STRING_AGG com CONCAT (texto livre - melhor para LLM ler) ----
PRINT CHAR(13)+CHAR(10) + '>> Abordagem B: STRING_AGG (texto legivel por humano/LLM)';
DECLARE @ProductsText NVARCHAR(MAX);
SELECT @ProductsText = STRING_AGG(
    CONCAT(
        '- Produto [ID ', p.ProductID, ']: ', p.Name,
        ' | Categoria: ', pc.Name,
        ' | Preco: R$ ', CAST(p.ListPrice AS VARCHAR(12)),
        ' | Cor: ', ISNULL(p.Color, 'N/A'),
        ' | Estoque: ', CAST(ISNULL(pi.Quantity, 0) AS VARCHAR)
    ),
    CHAR(13)+CHAR(10)
)
FROM (SELECT TOP 5 p.ProductID, p.Name, p.ListPrice, p.Color, p.ProductSubcategoryID, p.FinishedGoodsFlag
      FROM Production.Product p WHERE p.ListPrice > 0 ORDER BY p.ListPrice) p
INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
INNER JOIN Production.ProductCategory pc ON pc.ProductCategoryID = psc.ProductCategoryID
LEFT JOIN (SELECT ProductID, SUM(Quantity) Quantity FROM Production.ProductInventory GROUP BY ProductID) pi ON pi.ProductID = p.ProductID;
PRINT 'Conteudo via STRING_AGG (formato recomendado para o prompt):';
PRINT @ProductsText;
GO

-- ---- Comparativo lado a lado ----
PRINT CHAR(13)+CHAR(10) + N'--- COMPARACAO: FOR JSON vs STRING_AGG no contexto RAG ---';
SELECT
    N'FOR JSON PATH'                  AS Tecnologia,
    N'Parse facil no T-SQL (OPENJSON)' AS PontosFortes,
    N'Menos natural para LLM ler como texto corrido' AS PontosFracos,
    N'Quando a resposta do LLM sera reimportada para tabelas (saida estruturada)' AS MelhorPara
UNION ALL SELECT
    N'STRING_AGG + CONCAT',
    N'Texto muito mais legivel para o LLM. Consome menos tokens de parse.',
    N'Dificil re-importar para SQL caso precise de post-processamento estruturado.',
    N'Recomendado PADRAO para chunks, produtos e documentos em contexto RAG.';
GO

-- =================================================================================
-- PARTE 4: CONSTRUCAO DE PROMPTS ROBUSTOS (roles + temperatura + context injection)
-- =================================================================================
-- DP-800: (a) system message define regras; (b) contexto NAO eh parametro separado.

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG (02) PARTE 4/7: Construcao de Prompts';
PRINT '=========================================================';
GO

DECLARE @SystemMessage NVARCHAR(MAX) = N'Voce e um consultor senior de e-commerce de ciclismo da AdventureWorks.
REGRAS ESTRITAS (nao desobedeca por nada):
1. RESPONDA SOMENTE com base na LISTA DE PRODUTOS fornecida abaixo.
2. Se a informacao nao existir na lista escreva exatamente: "Nao possuo dados suficientes para recomendar."
3. Para cada produto recomendado cite: Nome, Preco e Categoria.
4. Classifique a recomendacao como MATCH FORTE / MATCH MEDIO / MATCH FRACO com justificativa curta.
5. Use temperatura 0 (zero), sua resposta deve ser DETERMINISTICA.
6. Nao mencione produtos inventados ou fora da lista.';

DECLARE @UserQuestion NVARCHAR(500) = N'Quais acessorios de ciclismo abaixo de R$ 200 voces tem?';

-- Contexto: resultado do Lab 01 Retriever (simulado aqui com STRING_AGG)
DECLARE @ContextProducts NVARCHAR(MAX);
SELECT @ContextProducts = STRING_AGG(
    CONCAT('[', p.Name, '] Preco=R$', CAST(p.ListPrice AS VARCHAR),
           ' | Categoria=', pc.Name, ' | Cor=', ISNULL(p.Color, 'N/A')),
    CHAR(13)+CHAR(10)
)
FROM (SELECT TOP 8 p.Name, p.ListPrice, p.Color, p.ProductSubcategoryID
      FROM Production.Product p WHERE p.ListPrice BETWEEN 1 AND 200 ORDER BY p.ListPrice) p
INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
INNER JOIN Production.ProductCategory pc ON pc.ProductCategoryID = psc.ProductCategoryID;

-- Montar user message com contexto INJETADO DENTRO do content (NAO eh parametro separado!)
-- DP-800: 2 formas validas de injetar contexto:
--   (A) dentro do user message  (abaixo - recomendado)
--   (B) no final do system message
-- ERRADO: passar contexto como campo separado fora de messages[]

DECLARE @UserMessage NVARCHAR(MAX) =
    N'[LISTA DE PRODUTOS DISPONIVEIS NO AZURE SQL]' + CHAR(13)+CHAR(10)
  + ISNULL(@ContextProducts, N'(nenhum produto encontrado)') + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
  + N'[PERGUNTA DO CLIENTE]' + CHAR(13)+CHAR(10)
  + @UserQuestion;

-- Montar array messages[] com FOR JSON PATH (nunca concatene aspas na mao - risco de JSON quebrado!)
DECLARE @MessagesJson NVARCHAR(MAX) = (
    SELECT role, content FROM (
        SELECT 1 AS ord, N'system' AS role, @SystemMessage AS content
        UNION ALL
        SELECT 2 AS ord, N'user'   AS role, @UserMessage AS content
    ) t ORDER BY ord
    FOR JSON PATH
);

-- Montar payload final (WITHOUT_ARRAY_WRAPPER = objeto, nao array)
DECLARE @Payload NVARCHAR(MAX) = (
    SELECT
        JSON_QUERY(@MessagesJson)    AS [messages],   -- JSON_QUERY evita escape duplo
        N'gpt-4o-mini'               AS model,
        0                            AS temperature,   -- 0 = deterministico (exame!)
        1.0                          AS top_p,
        700                          AS max_tokens,
        JSON_QUERY(N'{"type": "text"}') AS [response_format]
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
);

PRINT '>>> PROMPT MONTADO (pronto para ir em @payload do sp_invoke_external_rest_endpoint):';
PRINT '--------------------------------------------------------------------------------';
PRINT @Payload;
PRINT '--------------------------------------------------------------------------------';
GO

-- ---- Tabela: Efeitos da temperatura ----
PRINT CHAR(13)+CHAR(10) + N'--- TABELA: TEMPERATURA x CENARIO RAG (DP-800 semper cai!) ---';
SELECT
    0.0 AS Temperature,
    N'Deterministico, reprodutivel'                                              AS Comportamento,
    N'TODOS os fluxos RAG factuais: Q&A, suporte, analise de dados.'             AS QuandoUsar,
    N'Melhor para o exame - evita alucinacoes em questoes de "melhor resposta".'  AS ObservacaoExame
UNION ALL SELECT
    0.3, N'Pouco criativo, ainda estavel',
    N'Sumarios executivos onde pode valer a pena variar um pouco a redacao.',
    N'Na duvida, fique em 0. O exame quer a resposta FACTUAL, nao criativa.'
UNION ALL SELECT
    0.7, N'Bem criativo, risco moderado de alucinacao',
    N'Marketing, geracao de slogans, conteudo NAO factual.',
    N'NUNCA use isto para RAG baseado em dados reais do cliente.'
UNION ALL SELECT
    1.0, N'Maxima aleatoriedade, alta chance de alucinar',
    N'Ideacao criativa, brainstorms, conteudo generico sem fonte.',
    N'Proibido em RAG grounded. O exame cobra temperature=0 em Q&A factual.';
GO

-- =================================================================================
-- PARTE 5: PARSE DE RESPOSTAS LLM JSON (JSON_VALUE / JSON_QUERY / OPENJSON)
-- =================================================================================
-- DP-800: Diferenca entre as 3 funcoes e a tabela comparativa.

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG (02) PARTE 5/7: Parse de Respostas JSON';
PRINT '=========================================================';
GO

-- Resposta simulada REALISTA como se viesse de @response do sp_invoke_...
DECLARE @LlmFullResponse NVARCHAR(MAX) = N'{
  "response": {
    "status":  { "http": { "code": 200, "description": "OK" } },
    "headers": { "Content-Type": "application/json", "Retry-After": null }
  },
  "result": {
    "id": "chatcmpl-Abcd1234",
    "model": "gpt-4o-mini-2024-07-18",
    "choices": [
      {
        "index": 0,
        "message": {
          "role": "assistant",
          "content": "Aqui estao os acessorios: (1) Luva de Ciclismo R$79 (MATCH FORTE - custo beneficio) (2) Capacete R$349 (excede R$200).",
          "refusal": null
        },
        "finish_reason": "stop"
      },
      {
        "index": 1,
        "message": {
          "role": "assistant",
          "content": "Alternativa economica: Luva R$79.",
          "refusal": null
        },
        "finish_reason": "stop"
      }
    ],
    "usage": { "prompt_tokens": 412, "completion_tokens": 85, "total_tokens": 497 }
  }
}';

PRINT '>>> Resposta bruta simulada do Azure OpenAI (envelope 2 niveis) <<<';
PRINT SUBSTRING(@LlmFullResponse, 1, 200) + N'...[truncado para exibicao]...';
PRINT '';

-- =================================================================================
-- 5.1 JSON_VALUE -> Extrai UM VALOR ESCALAR (string, numero, boolean)
-- =================================================================================
PRINT '--- 5.1 JSON_VALUE (escalares): ---';
SELECT
    JSON_VALUE(@LlmFullResponse, '$.response.status.http.code')  AS [CódigoHTTP_200],
    JSON_VALUE(@LlmFullResponse, '$.result.model')                AS [ModeloUsado],
    JSON_VALUE(@LlmFullResponse, '$.result.choices[0].message.role') AS [RolePrimeiraEscolha],
    JSON_VALUE(@LlmFullResponse, '$.result.choices[0].message.content') AS [ConteudoDaResposta],
    JSON_VALUE(@LlmFullResponse, '$.result.usage.total_tokens')   AS [TotalTokensUsados];
GO

-- =================================================================================
-- 5.2 JSON_QUERY -> Extrai OBJETO ou ARRAY JSON INTEIRO (nao escalares)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '--- 5.2 JSON_QUERY (objetos/arrays inteiros): ---';
DECLARE @Resp NVARCHAR(MAX) = N'{
  "response": { "status": { "http": { "code": 200 } } },
  "result": {
    "choices": [ {"message":{"content":"R1"}}, {"message":{"content":"R2"}} ],
    "usage":   { "prompt_tokens":100, "completion_tokens":50, "total_tokens":150 }
  }
}';
SELECT
    JSON_QUERY(@Resp, '$.result.choices')   AS [ArrayChoicesInteiro],
    JSON_QUERY(@Resp, '$.result.usage')     AS [ObjetoUsageInteiro],
    JSON_QUERY(@Resp, '$.result.choices[0]') AS [PrimeiroChoiceObjeto];
GO

-- =================================================================================
-- 5.3 OPENJSON -> Transforma ARRAY JSON em LINHAS/TABELA (para iterar!)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '--- 5.3 OPENJSON (array -> tabela relacional): ---';
DECLARE @Choices NVARCHAR(MAX) = N'[
  {"index":0,"message":{"role":"assistant","content":"Resposta A"},"finish_reason":"stop"},
  {"index":1,"message":{"role":"assistant","content":"Resposta B"},"finish_reason":"stop"},
  {"index":2,"message":{"role":"assistant","content":"Resposta C"},"finish_reason":"length"}
]';

SELECT
    idx,
    MsgRole,
    MsgContent,
    FinishReason
FROM OPENJSON(@Choices) WITH (
    idx          INT            '$.index',
    MsgRole      NVARCHAR(20)   '$.message.role',
    MsgContent   NVARCHAR(MAX)  '$.message.content',
    FinishReason NVARCHAR(30)   '$.finish_reason'
) AS ParsedChoices;
GO

-- =================================================================================
-- 5.4 Tabela Comparativa OFICIAL (memorize esta tabela para o exame)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '--- TABELA COMPARATIVA DP-800: JSON_VALUE vs JSON_QUERY vs OPENJSON ---';
SELECT
    N'JSON_VALUE'  AS Funcao,
    N'Extrair UM unico valor ESCALAR (texto/numero/bool)'               AS Proposito,
    N'NVARCHAR(4000) - retorna NULL se passar de 4k ou nao for escalar' AS Retorno,
    N'Extrair answer, status, total_tokens, model, http_code de um caminho especifico' AS ExemploUso
UNION ALL SELECT
    N'JSON_QUERY',
    N'Extrair um OBJETO ou ARRAY JSON INTEIRO sem quebrar a estrutura',
    N'NVARCHAR(MAX) - preserva a estrutura JSON (nao adiciona aspas escapadas)',
    N'Extrair todo choices[], todo usage{}, mensagens[] para embutir em outro JSON'
UNION ALL SELECT
    N'OPENJSON',
    N'Transformar ARRAY JSON em TABELA de linhas (pivotar JSON -> SQL)',
    N'TABELA (result-set com as colunas do WITH)',
    N'Iterar por multiplas choices, extrair array de topics[] do LLM, normalizar produtos';
GO

-- =================================================================================
-- PARTE 6: RESPOSTA ESTRUTURADA + TRATAMENTO DE ERROS COMPLETO (TRY/CATCH)
-- =================================================================================
-- DP-800: (1) response_format:json_object ; (2) Validar return_code E http_code

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG (02) PARTE 6/7: Procedure RAG Robusta (Erros + Estruturado)';
PRINT '=========================================================';
GO

CREATE OR ALTER PROCEDURE lab.usp_RagSentimentAnalysisStructured
    @FeedbackText   NVARCHAR(MAX),
    @CorrelationId  UNIQUEIDENTIFIER = NULL,
    @DebugMode      BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @corr UNIQUEIDENTIFIER = ISNULL(@CorrelationId, NEWID());
    DECLARE @ProcName NVARCHAR(200) = OBJECT_NAME(@@PROCID);

    BEGIN TRY
        -- 1. Construir MESSAGES com SYSTEM instruindo formato JSON
        DECLARE @SysMsg NVARCHAR(MAX) = N'Voce e um classificador de feedback de clientes.
REGRAS OBRIGATORIAS DE SAIDA (nao desobedeca):
- RETORNE EXCLUSIVAMENTE um JSON valido. Nenhuma palavra antes ou depois.
- Schema JSON obrigatorio:
  {"sentiment": "Positivo|Negativo|Neutro",
   "topics":    ["topico1","topico2",...],
   "confidence": 0.0 a 1.0,
   "summary_pt": "resumo curto do feedback"}
- sentiment exatamente 1 dos 3 valores acima (case sensitive).
- confidence 0.9+ = muito certo, 0.5 = incerto.';

        DECLARE @UsrMsg NVARCHAR(MAX) = N'Feedback do cliente: ' + @FeedbackText;

        DECLARE @Messages NVARCHAR(MAX) = (
            SELECT N'system' AS [role], @SysMsg AS [content] UNION ALL
            SELECT N'user'   AS [role], @UsrMsg AS [content]
            FOR JSON PATH
        );

        DECLARE @Payload NVARCHAR(MAX) = (
            SELECT
                JSON_QUERY(@Messages) AS [messages],
                0 AS temperature,
                JSON_QUERY(N'{"type":"json_object"}') AS [response_format],  -- <- SAIDA ESTRUTURADA!
                300 AS max_tokens
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        IF @DebugMode = 1 BEGIN
            PRINT '> Payload enviado para o Azure OpenAI:';
            PRINT @Payload;
        END

        -- 2. SIMULAR a resposta completa do sp_invoke_external_rest_endpoint
        -- (Para rodar real, substitua este bloco pela chamada real, vide Parte 2)
        DECLARE @ProcedureReturnCode INT = 0;   -- 0 = sucesso da procedure T-SQL
        DECLARE @RawResponse NVARCHAR(MAX);

        -- Aqui, simulando resposta de sucesso do envelope + result:
        SET @RawResponse = N'{
          "response": {"status": {"http": {"code": 200, "description": "OK"}}},
          "result": {
            "model": "gpt-4o-mini-2024-07-18",
            "choices": [ { "message": { "content": "{\"sentiment\": \"Positivo\", \"topics\": [\"entrega\",\"montagem\",\"qualidade\"], \"confidence\": 0.95, \"summary_pt\": \"Cliente satisfeito com entrega rapida e facilidade de montagem.\"}" }, "finish_reason": "stop" } ],
            "usage": { "prompt_tokens": 180, "completion_tokens": 65, "total_tokens": 245 }
          }
        }';

        -- 3. PRIMEIRO: validar return_code da procedure (0 = OK, nao 0 = erro)
        IF @ProcedureReturnCode <> 0 BEGIN
            DECLARE @ErrProc NVARCHAR(500) = N'sp_invoke_external_rest_endpoint retornou codigo ' + CAST(@ProcedureReturnCode AS VARCHAR);
            INSERT INTO lab.RAGErrorLog (ProcedureName, ErrorMessage, CorrelationId, PayloadSnapshot)
            VALUES (@ProcName, @ErrProc, @corr, @Payload);
            RAISERROR(@ErrProc, 16, 1);
            RETURN;
        END

        -- 4. SEGUNDO: extrair e validar HTTP code do envelope
        DECLARE @HttpCode INT = ISNULL(CAST(JSON_VALUE(@RawResponse, '$.response.status.http.code') AS INT), -1);

        -- Logar a chamada (sempre!)
        INSERT INTO lab.LlmCallLogs
            (SessionId, ProcedureReturnCode, HttpStatusCode, EndpointUrl, Payload, RawResponse,
             PromptTokens, CompletionTokens, TotalTokens, ModelUsed)
        VALUES
            (@corr,
             @ProcedureReturnCode,
             @HttpCode,
             N'https://<simulado>.openai.azure.com/chat/completions',
             @Payload,
             @RawResponse,
             CAST(JSON_VALUE(@RawResponse, '$.result.usage.prompt_tokens') AS INT),
             CAST(JSON_VALUE(@RawResponse, '$.result.usage.completion_tokens') AS INT),
             CAST(JSON_VALUE(@RawResponse, '$.result.usage.total_tokens') AS INT),
             JSON_VALUE(@RawResponse, '$.result.model'));

        -- HTTP 200: esperado para parsear $.result
        IF @HttpCode BETWEEN 200 AND 299 BEGIN
            DECLARE @ContentInner NVARCHAR(MAX) = JSON_VALUE(@RawResponse, '$.result.choices[0].message.content');

            IF ISJSON(@ContentInner) <> 1 BEGIN
                DECLARE @ErrJson NVARCHAR(500) = N'Resposta inner nao e JSON valido (response_format pode ter sido ignorado). Content: ' + LEFT(@ContentInner, 300);
                INSERT INTO lab.RAGErrorLog (ProcedureName, ErrorMessage, CorrelationId)
                VALUES (@ProcName, @ErrJson, @corr);
                RAISERROR(@ErrJson, 16, 1);
                RETURN;
            END

            -- PARSE do JSON estruturado: escalares + array (OPENJSON!)
            SELECT
                JSON_VALUE(@ContentInner, '$.sentiment')           AS Sentimento,
                CAST(JSON_VALUE(@ContentInner, '$.confidence') AS DECIMAL(5,4)) AS Confianca,
                JSON_VALUE(@ContentInner, '$.summary_pt')          AS Resumo,
                JSON_QUERY(@ContentInner, '$.topics')              AS ArrayTopicosJSON,
                @corr                                              AS CorrelationId;

            SELECT
                Topic AS TopicoExtraido
            FROM OPENJSON(JSON_QUERY(@ContentInner, '$.topics'))
            WITH (Topic NVARCHAR(200) '$');

        END ELSE BEGIN
            -- Codigos de erro: 400, 401, 403, 404, 429, 500...
            DECLARE @ErrorType  NVARCHAR(100) = CASE @HttpCode
                WHEN 400 THEN N'Bad Request (prompt muito longo OU JSON invalido no payload)'
                WHEN 401 THEN N'Unauthorized (api-key errada/ausente/faltando permissao na credencial)'
                WHEN 403 THEN N'Forbidden (quota excedida ou bloqueio de IP)'
                WHEN 404 THEN N'Not Found (URL/deployment errado)'
                WHEN 429 THEN N'Too Many Requests (Rate Limit - use Retry-After header)'
                WHEN 500 THEN N'Internal Server Error (lado Azure)'
                ELSE          N'Erro HTTP nao documentado - verifique Microsoft Learn' END;

            DECLARE @ErrMore NVARCHAR(MAX) =
                N'HTTP ' + CAST(@HttpCode AS VARCHAR) + ' - ' + @ErrorType + CHAR(13)+CHAR(10) +
                N'Detalhe da API: ' + ISNULL(JSON_VALUE(@RawResponse, '$.result.error.message'), N'(sem detalhe)') +
                ISNULL(N' | Retry-After: ' + JSON_VALUE(@RawResponse, '$.response.headers."Retry-After"'), N'');

            INSERT INTO lab.RAGErrorLog (ProcedureName, ErrorMessage, HttpStatusCode, CorrelationId, PayloadSnapshot)
            VALUES (@ProcName, @ErrMore, @HttpCode, @corr, @Payload);

            RAISERROR(N'%s', 16, 1, @ErrMore);
            RETURN;
        END

    END TRY
    BEGIN CATCH
        DECLARE @CatchMsg NVARCHAR(MAX) =
            N'ERRO NAO TRATADO: [' + ERROR_PROCEDURE() + N'] Linha ' + CAST(ERROR_LINE() AS VARCHAR) +
            N' -> ' + ERROR_MESSAGE();
        INSERT INTO lab.RAGErrorLog (ProcedureName, ErrorMessage, CorrelationId)
        VALUES (@ProcName, @CatchMsg, @corr);
        THROW;  -- Rethrow para SSMS/APLICACAO ver o erro real
    END CATCH
END;
GO

PRINT CHAR(13)+CHAR(10) + '--- Executando procedure robusta (caso feliz, HTTP 200) ---';
EXEC lab.usp_RagSentimentAnalysisStructured
    @FeedbackText  = N'A bicicleta chegou super rapido, montagem facil, estou amando!',
    @DebugMode     = 0;
GO

PRINT CHAR(13)+CHAR(10) + '--- Verificando logs de auditoria ---';
SELECT * FROM lab.LlmCallLogs ORDER BY LogId DESC;
GO

-- =================================================================================
-- PARTE 7: GERENCIAMENTO DE TOKENS + CENARIOS DE PROJETO
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG (02) PARTE 7/7: Gerenciamento de Tokens + Extras';
PRINT '=========================================================';
GO

---- 7.1 Estimativa de tokens (regra de bolso: ~1 token = 4 chars ou 0.75 palavras)
PRINT '--- 7.1 Estimativa de orcamento de tokens ---';
DECLARE
    @Sys        NVARCHAR(MAX) = N'Voce e um assistente de suporte. Apenas com base no contexto.',
    @Contexto   NVARCHAR(MAX) = REPLICATE(N'Produto X: descricao rica. ', 50),  -- contexto grande
    @Pergunta   NVARCHAR(MAX) = N'Qual o melhor capacete?',
    @Reserva    INT = 800;  -- reservar tokens para a resposta do LLM

DECLARE
    @SysTok  INT = LEN(@Sys) / 4,
    @CtxTok  INT = LEN(@Contexto) / 4,
    @PergTok INT = LEN(@Pergunta) / 4,
    @TotalEstimado INT = @SysTok + @CtxTok + @PergTok + @Reserva,
    @Orcamento INT = 4096;  -- janela do modelo / teto de seguranca

SELECT
    @SysTok        AS TokensSystem,
    @CtxTok        AS TokensContexto,
    @PergTok       AS TokensPergunta,
    @Reserva       AS TokensReservaResposta,
    @TotalEstimado AS TotalEstimado,
    @Orcamento     AS OrcamentoMaximo,
    CASE WHEN @TotalEstimado > @Orcamento THEN N'RISCO DE ESTOURO - truncar contexto!'
         ELSE N'OK - dentro do orcamento' END AS StatusOrcamento;
GO

-- Logica dinamica de truncagem quando houver estouro (exemplo)
PRINT CHAR(13)+CHAR(10) + N'--- 7.2 Logica de truncagem de contexto quando o orcamento estoura ---';
DECLARE
    @System2 NVARCHAR(MAX)  = N'Voce e um assistente util.',
    @Context2 NVARCHAR(MAX) = REPLICATE(N'Chunk com texto longo do produto. ', 100),
    @Question2 NVARCHAR(MAX)= N'Resuma os produtos.',
    @Budget INT = 1000,
    @AnswerReserve INT = 300;

DECLARE
    @Used INT = LEN(@System2)/4 + LEN(@Question2)/4 + @AnswerReserve,
    @CtxBudget INT = @Budget - @Used;

IF LEN(@Context2)/4 > @CtxBudget
    SET @Context2 = LEFT(@Context2, @CtxBudget * 4);  -- Truncar com margem de seguranca

SELECT @Used       AS TokensOcupados_SemContexto,
       @CtxBudget  AS OrcamentoDisponivel_ParaContexto,
       LEN(@Context2) AS TamanhoFinalContexto_Chars,
       LEN(@Context2)/4 AS TamanhoFinalContexto_Tokens;
GO

---- 7.3 Casos de Uso avancados (processamento em LOTE)
PRINT CHAR(13)+CHAR(10) + N'--- 7.3 Exemplo: Classificacao de feedbacks em LOTE (cursor T-SQL) ---';

CREATE OR ALTER PROCEDURE lab.usp_RagBatchClassifyFeedback
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FId INT, @FTxt NVARCHAR(MAX), @Corr UNIQUEIDENTIFIER;

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT FeedbackId, FeedbackText FROM lab.CustomerFeedback WHERE ProcessedAt IS NULL;

    OPEN cur;
    FETCH NEXT FROM cur INTO @FId, @FTxt;

    WHILE @@FETCH_STATUS = 0 BEGIN
        SET @Corr = NEWID();
        PRINT N'Processando FeedbackId=' + CAST(@FId AS VARCHAR) + N'...';

        -- (Em producao, chamar lab.usp_RagSentimentAnalysisStructured aqui)
        -- Simulando resultado:
        UPDATE lab.CustomerFeedback
           SET Sentiment   = CASE @FId
                                WHEN 1 THEN N'Positivo' WHEN 2 THEN N'Negativo' WHEN 3 THEN N'Neutro'
                                WHEN 4 THEN N'Neutro'   WHEN 5 THEN N'Positivo' END,
               TopicsJSON  = CASE @FId
                                WHEN 1 THEN N'["entrega rapida","montagem facil","satisfacao"]'
                                WHEN 2 THEN N'["qualidade ruim","defeito","atendimento horrivel"]'
                                WHEN 3 THEN N'["design bom","durabilidade baixa"]'
                                WHEN 4 THEN N'["entrega no prazo","produto conforme anunciado"]'
                                WHEN 5 THEN N'["atendimento excelente","ajuda tamanho"]' END,
               Confidence  = CASE @FId
                                WHEN 1 THEN 0.95 WHEN 2 THEN 0.90 WHEN 3 THEN 0.65
                                WHEN 4 THEN 0.85 WHEN 5 THEN 0.93 END,
               ProcessedAt = GETUTCDATE()
         WHERE FeedbackId = @FId;

        FETCH NEXT FROM cur INTO @FId, @FTxt;
    END

    CLOSE cur; DEALLOCATE cur;
END;
GO

EXEC lab.usp_RagBatchClassifyFeedback;

SELECT FeedbackId, CustomerName, Sentiment, Confidence, TopicsJSON, ProcessedAt
FROM lab.CustomerFeedback ORDER BY FeedbackId;
GO

---- 7.4 Diagnostico de erros HTTP tabela rapida DP-800
PRINT CHAR(13)+CHAR(10) + N'--- TABELA DE DIAGNOSTICO DE ERROS HTTP DP-800 ---';
SELECT
    200 AS CodigoHTTP,
    N'OK / Sucesso'                                                                 AS Diagnostico,
    N'Parsear $.result.choices[0].message.content com JSON_VALUE / OPENJSON'       AS AcaoTSQL
UNION ALL SELECT 400, N'Bad Request (prompt muito longo OU JSON malformado no payload)',
    N'Verificar orcamento de tokens; validar payload com ISJSON = 1 antes de enviar; checar aspas escapadas'
UNION ALL SELECT 401, N'Unauthorized (credencial/api-key)',
    N'DROP + RECREATE DATABASE SCOPED CREDENTIAL com a api-key CORRETA; verifique IDENTITY=''HTTPEndpointHeaders'''
UNION ALL SELECT 403, N'Forbidden / Quota Exceeded / Content Policy',
    N'Aumentar quota no portal Azure OpenAI ou aguardar reset diario; verificar politica de conteudo'
UNION ALL SELECT 404, N'Not Found (URL/deployment nome errado)',
    N'Checar @url: nome do recurso, nome do deployment, api-version batendo com o portal Azure'
UNION ALL SELECT 429, N'Too Many Requests / Rate Limit',
    N'Usar @retry_count (0-10) no sp_invoke; extrair "Retry-After" header via JSON_VALUE no $.response.headers'
UNION ALL SELECT 500, N'Internal Server Error',
    N'Falha lado Azure. Tentar novamente. Se persistir, abrir ticket de suporte.';
GO

-- =================================================================================
-- FINAL: Checklist de aprendizado
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG (02) - CHECKLIST DE CONCLUSAO';
PRINT '=========================================================';

SELECT N'[OK] Sei criar DATABASE SCOPED CREDENTIAL e NAO hardcodar API keys' AS Item UNION ALL
SELECT N'[OK] Conheco TODOS os parametros de sp_invoke_external_rest_endpoint (@url/@method/@headers/@payload/@credential/@response/@timeout/@retry_count)' UNION ALL
SELECT N'[OK] Conheco os DOIS envelopes da resposta: return_code e $.response.status.http.code' UNION ALL
SELECT N'[OK] For JSON PATH vs STRING_AGG para montar contexto de prompt' UNION ALL
SELECT N'[OK] Construo messages[] via FOR JSON (nao concatenacao manual)' UNION ALL
SELECT N'[OK] Sei injetar contexto DENTRO do content de system ou user message (nunca fora)' UNION ALL
SELECT N'[OK] Uso temperature = 0 para RAG factual' UNION ALL
SELECT N'[OK] Diferenciar JSON_VALUE (escalar) vs JSON_QUERY (objeto/array) vs OPENJSON (linhas)' UNION ALL
SELECT N'[OK] Uso response_format json_object e valido ISJSON = 1 antes de parsear' UNION ALL
SELECT N'[OK] Tratamento robusto: TRY/CATCH + return_code + http_code + log de erros' UNION ALL
SELECT N'[OK] Estimo orcamento de tokens e trunco contexto se necessario' UNION ALL
SELECT N'[OK] Conheco todos os codigos HTTP (200/400/401/403/404/429/500) e as correcoes';
GO

PRINT CHAR(13)+CHAR(10) + '>>> PARABENS! Voce concluiu os labs 11-RAG (01 e 02).';
PRINT N'    Revise agora as cheat-sheets do Dominio 3 e faca as questoes de pratica.';
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/11-rag/02-prompts-and-responses.md
-- =================================================================================================
