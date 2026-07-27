-- =================================================================================
-- DP-800 - LAB PRÁTICO: MONTAGEM DE PROMPTS E PARSEAMENTO DE RESPOSTAS LLM EM T-SQL
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a construção de payloads JSON de IA e extração de respostas:
--   1. Formatação de Dados Relacionais em JSON para Prompts com `FOR JSON PATH` e `STRING_AGG`
--   2. Definição do Payload JSON para Chat Completions (`role: system`, `user`, `temperature: 0`)
--   3. Parseamento de Respostas JSON com `JSON_VALUE` e `OPENJSON`
--   4. Tratamento de Erros de API HTTP (200 OK vs 400 Bad Request vs 429 Rate Limit)
--   5. Cenários Práticos de Projeto (Geração Estruturada de Saída em JSON via `response_format`)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
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
-- PARTE 1: FORMATAÇÃO DE DADOS RELACIONAIS EM JSON PARA CONTEXTO DE PROMPT
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - FOR JSON PATH: Converte o resultado de uma consulta T-SQL diretamente em uma string no formato JSON.
--   - STRING_AGG: Concatena registros formatados como texto legível para o LLM.

-- 1. Exemplo de Conversão para JSON
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
-- PARTE 2: CONSTRUÇÃO DE PAYLOAD E CHAMADA DE PROCEDIMENTO COM TRATAMENTO DE ERRO
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - SYSTEM ROLE: Define o comportamento e as regras de restrição do assistente de IA.
--   - TEMPERATURE: `0` para respostas fatuais e determinísticas baseadas unicamente no contexto.
--   - RESPONSE_FORMAT: `{"type": "json_object"}` para forçar o modelo a retornar JSON válido.

-- -- [PONTO DE ATENÇÃO DP-800]
CREATE PROCEDURE lab.usp_InvokeLlmWithPrompt
    @UserQuestion NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Montar a mensagem do sistema e do usuário
    DECLARE @SystemPrompt NVARCHAR(MAX) = N'Voce e um assistente especializado da AdventureWorks. Responda em JSON com a estrutura: {"status": "OK", "answer": "Sua resposta"}';
    DECLARE @ContextText NVARCHAR(MAX) = N'Produto: Capacete Pro | Preco: R$ 250,00 | Estoque: 15 unidades';
    
    DECLARE @UserContent NVARCHAR(MAX) = CONCAT(N'Contexto: ', @ContextText, N'\nPergunta: ', @UserQuestion);

    -- 2. Montar o Payload JSON completo
    DECLARE @PayloadJson NVARCHAR(MAX) = N'{
        "messages": [
            {"role": "system", "content": "' + @SystemPrompt + '"},
            {"role": "user", "content": "' + @UserContent + '"}
        ],
        "temperature": 0,
        "response_format": {"type": "json_object"}
    }';

    -- 3. Simulação de Chamada REST e Parseamento da Resposta
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

    -- 4. Extrair o código de status HTTP e o conteúdo da resposta
    DECLARE @HttpCode INT = CAST(JSON_VALUE(@SimulatedHttpResponse, '$.response.status.http.code') AS INT);
    DECLARE @ContentResult NVARCHAR(MAX);
    DECLARE @TotalTokens INT;

    IF @HttpCode = 200
    BEGIN
        SET @ContentResult = JSON_VALUE(@SimulatedHttpResponse, '$.result.choices[0].message.content');
        SET @TotalTokens = CAST(JSON_VALUE(@SimulatedHttpResponse, '$.result.usage.total_tokens') AS INT);

        -- Gravar no log de auditoria
        INSERT INTO lab.LlmCallLogs (HttpStatusCode, PromptPayload, ResponseContent, TotalTokens)
        VALUES (@HttpCode, @PayloadJson, @ContentResult, @TotalTokens);

        -- Extrair o conteúdo do JSON retornado pelo modelo de IA
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

-- Executar a chamada simulada
EXEC lab.usp_InvokeLlmWithPrompt @UserQuestion = N'Qual e o preco e estoque do Capacete Pro?';
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz de Diagnóstico de Erros HTTP na API do Azure OpenAI em T-SQL
-- Guia de decisão de arquitetura para tratamento de exceções no banco de dados.

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

--- CENÁRIO 2: Gate de contrato da resposta
DECLARE @RespostaEncapsulada nvarchar(max) = N'{"result":{"choices":[{"message":{"content":"Resposta fundamentada"}}]},"status":{"http":{"code":200}}}';
SELECT JSON_VALUE(@RespostaEncapsulada, '$.status.http.code') AS CodigoHTTP,
       JSON_VALUE(@RespostaEncapsulada, '$.result.choices[0].message.content') AS Conteudo,
       CASE WHEN ISJSON(@RespostaEncapsulada) = 1 AND JSON_VALUE(@RespostaEncapsulada, '$.status.http.code') = N'200'
                 AND JSON_VALUE(@RespostaEncapsulada, '$.result.choices[0].message.content') IS NOT NULL
            THEN N'Aprovada para validação de schema e armazenamento rastreável'
            ELSE N'Rejeitar ou repetir antes de processar o conteúdo' END AS DecisaoContrato;
GO
-- Em produção: valide JSON estruturado, registre correlation ID, retenha fontes da recuperação e nunca grave segredos.
