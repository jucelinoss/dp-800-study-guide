-- =================================================================================
-- DP-800 - LAB: PROMPT ASSEMBLY AND LLM RESPONSE PARSING IN T-SQL
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to restore the
-- AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates AI JSON payload construction and response extraction:
--   1. Formatting Relational Data into JSON for Prompts with `FOR JSON PATH` and `STRING_AGG`
--   2. Defining the JSON Payload for Chat Completions (`role: system`, `user`, `temperature: 0`)
--   3. Parsing JSON Responses with `JSON_VALUE` and `OPENJSON`
--   4. Handling HTTP API Errors (200 OK vs 400 Bad Request vs 429 Rate Limit)
--   5. Practical Project Scenarios (Structured JSON Output Generation via `response_format`)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/11-rag/02-prompts-and-responses.md
--    Open the theory guide alongside this lab for conceptual context.

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP PROCEDURE IF EXISTS lab.usp_InvokeLlmWithPrompt;
DROP TABLE IF EXISTS lab.LlmCallLogs;
GO

CREATE TABLE lab.LlmCallLogs (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    HttpStatusCode INT NOT NULL,
    PromptPayload NVARCHAR(MAX) NOT NULL,
    ResponseContent NVARCHAR(MAX) NULL,
    TotalTokens INT NULL,
    LoggedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
GO


-- =================================================================================
-- PART 1: FORMATTING RELATIONAL DATA INTO JSON FOR PROMPT CONTEXT
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - FOR JSON PATH: Converts a T-SQL query result directly into a JSON format string.
--   - STRING_AGG: Concatenates records formatted as human-readable text for the LLM.

-- 1. JSON Conversion Example
DECLARE @ProductsJson NVARCHAR(MAX);

SELECT @ProductsJson = (
    SELECT TOP 3 ProductID AS id, Name AS name, ListPrice AS price
    FROM Production.Product
    FOR JSON PATH
);

PRINT 'PRODUTOS FORMATADOS EM JSON PARA O PROMPT:';
PRINT @ProductsJson;
GO


-- =================================================================================
-- PART 2: PAYLOAD CONSTRUCTION AND PROCEDURE CALL WITH ERROR HANDLING
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - SYSTEM ROLE: Defines the AI assistant's behavior and constraint rules.
--   - TEMPERATURE: `0` for factual and deterministic responses based solely on context.
--   - RESPONSE_FORMAT: `{"type": "json_object"}` to force the model to return valid JSON.

-- -- [DP-800 KEY POINT]
CREATE PROCEDURE lab.usp_InvokeLlmWithPrompt
    @UserQuestion NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Build the system and user message
    DECLARE @SystemPrompt NVARCHAR(MAX) = N'Voce e um assistente especializado da AdventureWorks. Responda em JSON com a estrutura: {"status": "OK", "answer": "Sua resposta"}';
    DECLARE @ContextText NVARCHAR(MAX) = N'Produto: Capacete Pro | Preco: R$ 250,00 | Estoque: 15 unidades';
    
    DECLARE @UserContent NVARCHAR(MAX) = CONCAT(N'Contexto: ', @ContextText, N'\nPergunta: ', @UserQuestion);

    -- 2. Build the complete JSON Payload
    DECLARE @PayloadJson NVARCHAR(MAX) = N'{
        "messages": [
            {"role": "system", "content": "' + @SystemPrompt + '"},
            {"role": "user", "content": "' + @UserContent + '"}
        ],
        "temperature": 0,
        "response_format": {"type": "json_object"}
    }';

    -- 3. REST Call Simulation and Response Parsing
    DECLARE @SimulatedHttpResponse NVARCHAR(MAX) = N'{
        "response": { "status": { "http": { "code": 200 } } },
        "result": {
            "choices": [{
                "message": {
                    "content": "{\"status\": \"OK\", \"answer\": \"O Capacete Pro custa R$ 250,00 e possui 15 unidades em estoque.\"}"
                }
            }],
            "usage": { "total_tokens": 85 }
        }
    }';

    -- 4. Extract the HTTP status code and response content
    DECLARE @HttpCode INT = CAST(JSON_VALUE(@SimulatedHttpResponse, '$.response.status.http.code') AS INT);
    DECLARE @ContentResult NVARCHAR(MAX);
    DECLARE @TotalTokens INT;

    IF @HttpCode = 200
    BEGIN
        SET @ContentResult = JSON_VALUE(@SimulatedHttpResponse, '$.result.choices[0].message.content');
        SET @TotalTokens = CAST(JSON_VALUE(@SimulatedHttpResponse, '$.result.usage.total_tokens') AS INT);

        -- Write to audit log
        INSERT INTO lab.LlmCallLogs (HttpStatusCode, PromptPayload, ResponseContent, TotalTokens)
        VALUES (@HttpCode, @PayloadJson, @ContentResult, @TotalTokens);

        -- Extract content from the JSON returned by the AI model
        SELECT 
            JSON_VALUE(@ContentResult, '$.status') AS StatusResposta,
            JSON_VALUE(@ContentResult, '$.answer') AS TextoRespostaFinal,
            @TotalTokens AS TokensConsumidos;
    END
    ELSE
    BEGIN
        PRINT 'FALHA NA REQUISICAO HTTP DA API DE IA. CODIGO: ' + CAST(@HttpCode AS VARCHAR);
    END
END;
GO

-- Execute the simulated call
EXEC lab.usp_InvokeLlmWithPrompt @UserQuestion = N'Qual e o preco e estoque do Capacete Pro?';
GO


-- =================================================================================
-- PART 3: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: HTTP Error Diagnostic Matrix for Azure OpenAI API in T-SQL
-- Architecture decision guide for exception handling in the database.

SELECT 
    200 AS CodigoHTTP,
    'Sucesso' AS Diagnostico,
    'Extrair resposta do caminho JSON $.result.choices[0].message.content' AS AcaoTsql
UNION ALL
SELECT 
    400,
    'Bad Request (Prompt muito longo ou JSON invalido)',
    'Validar contagem de tokens e checar se aspas duplas foram escapadas'
UNION ALL
SELECT 
    401,
    'Unauthorized (Chave de API invalida ou expirada)',
    'Verificar a credencial DATABASE SCOPED CREDENTIAL e a API Key'
UNION ALL
SELECT 
    429,
    'Rate Limit Exceeded (Limite de requisições/minuto atingido)',
    'Ler o cabecalho Retry-After e implementar tempo de espera no T-SQL';
GO

-- SCENARIO 2: Response-contract gate. Treat every model response as untrusted.
-- Do not extract Content until the HTTP outcome, wrapper, and expected JSON shape
-- have been checked. sp_invoke_external_rest_endpoint can wrap provider output in
-- $.result; a direct provider path is not automatically the procedure's path.
DECLARE @WrappedResponse nvarchar(max) = N'{
  "result":{"choices":[{"message":{"content":"Grounded answer"}}]},
  "status":{"http":{"code":200}}}';

SELECT
    JSON_VALUE(@WrappedResponse, '$.status.http.code') AS HttpCode,
    JSON_VALUE(@WrappedResponse, '$.result.choices[0].message.content') AS Content,
    CASE WHEN ISJSON(@WrappedResponse) = 1
           AND JSON_VALUE(@WrappedResponse, '$.status.http.code') = N'200'
           AND JSON_VALUE(@WrappedResponse, '$.result.choices[0].message.content') IS NOT NULL
         THEN N'Approved for schema validation and traceable storage'
         ELSE N'Reject or retry before parsing business content'
    END AS ContractDecision;
GO
-- Production checklist: validate structured output, log a correlation ID, retain
-- retrieval/source references, and store only approved fields. Never log secrets.

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/11-rag/02-prompts-and-responses.md
-- =================================================================================================
