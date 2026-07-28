---
title: Prompts e Respostas em RAG via T-SQL (Prompts and Responses in T-SQL RAG)
type: study-material
tags:
  - dp-800
  - sp-invoke-external-rest-endpoint
  - rag
  - json
  - llm-response
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral](#visão-geral)
> - 📍 [2. Sintaxe de sp_invoke_external_rest_endpoint](#sintaxe-de-sp-invoke-external-rest-endpoint)
> - 📍 [3. DATABASE SCOPED CREDENTIAL para OpenAI](#database-scoped-credential-para-openai)
> - 📍 [4. Convertendo Dados para JSON com FOR JSON](#convertendo-dados-para-json-com-for-json)
> - 📍 [5. Construindo Prompts](#construindo-prompts)
> - 📍 [6. Procedure RAG Completa — End to End](#procedure-rag-completa-end-to-end)
> - 📍 [7. Parseando Respostas JSON](#parseando-respostas-json)
>   - 🔹 [JSON_VALUE — Valores Escalares Únicos](#json-value-valores-escalares-únicos)
>   - 🔹 [OPENJSON — Parseando Arrays](#openjson-parseando-arrays)
>   - 🔹 [JSON_QUERY — Extraindo Objetos/Arrays JSON](#json-query-extraindo-objetosarrays-json)
> - 📍 [8. Saída Estruturada — Forçando Respostas JSON](#saída-estruturada-forçando-respostas-json)
> - 📍 [9. Tratamento de Erros](#tratamento-de-erros)
> - 📍 [10. Gerenciamento de Tokens](#gerenciamento-de-tokens)
> - 📍 [11. Casos de Uso](#casos-de-uso)
> - 📍 [12. Problemas Comuns e Erros](#problemas-comuns-e-erros)
> - 📍 [13. Dicas para o Exame](#dicas-para-o-exame)
> - 📍 [14. Principais Conclusões](#principais-conclusões)
> - 📍 [15. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [16. Documentação Oficial](#documentação-oficial)

---

# Prompts e Respostas em RAG via T-SQL

## Visão Geral

`sp_invoke_external_rest_endpoint` é a stored procedure T-SQL para chamar endpoints HTTPS de dentro das plataformas SQL compatíveis. Ela permite integrar o banco a uma API REST autorizada; para serviços fora da lista de destinos permitidos, exponha o serviço por um intermediário seguro, como o Azure API Management. Este tópico cobre recuperar contexto, converter para JSON, construir prompts, chamar o modelo e parsear respostas.

> [!abstract]
>
> - Aborda engenharia de prompts para RAG: system message, user message, injeção de contexto e parâmetros de resposta
> - Prompts bem estruturados produzem respostas melhores e mais ancoradas do LLM
> - Tópicos-chave para o exame: roles de system vs user message, onde injetar o contexto recuperado, efeitos de temperature e top_p

> [!tip] O Que o Exame Testa
>
> - **System message**: define a persona, instruções e restrições do modelo ("Answer only from provided context")
> - **Injeção de contexto**: chunks recuperados vão no system message ou como parte do user message — **não** como um parâmetro de API separado
> - **Temperature**: 0 = determinístico (melhor para respostas factuais); 1 = criativo/aleatório; use temperature baixa para RAG para reduzir risco de alucinação

---

## Fundamentos: prompt é contexto e contrato, não só texto

Depois que a busca recupera os chunks, o prompt é o contrato que define como o modelo deve usar essa evidência. A mensagem de sistema estabelece regras persistentes — papel, limites, formato e o que fazer quando faltar informação. A mensagem de usuário traz a pergunta e, conforme o desenho, o contexto recuperado. Nenhuma instrução no prompt cria permissão de acesso: filtros de segurança precisam ocorrer antes da recuperação.

O contexto compete por espaço com instruções, pergunta e resposta dentro da janela de tokens do modelo. Enviar mais chunks não significa obter resposta melhor; trechos irrelevantes diluem a evidência e aumentam custo e latência. Recupere poucos candidatos de alta qualidade, preserve identificação/origem e defina um orçamento de tokens para o contexto e para a resposta.

Por fim, trate toda saída do modelo como **dados não confiáveis**. Mesmo com RAG, ele pode omitir detalhes, interpretar mal uma fonte ou produzir JSON inválido. Valide a estrutura, limites e regras de negócio antes de persistir ou executar qualquer ação; use saída estruturada quando precisar de um contrato de resposta, mas ainda faça validação no SQL ou na aplicação.

## Sintaxe de sp_invoke_external_rest_endpoint

```sql
EXEC sp_invoke_external_rest_endpoint
    @url         = N'https://...',           -- obrigatório: URL do endpoint
    @method      = N'POST',                  -- obrigatório: método HTTP
    @headers     = N'{"key":"value"}',       -- opcional: objeto JSON de headers
    @payload     = N'{"key":"value"}',       -- opcional: corpo da requisição (string JSON)
    @credential  = [MyCredential],           -- opcional: DATABASE SCOPED CREDENTIAL
    @response    = @response_var OUTPUT,     -- parâmetro de saída
    @timeout     = 30,                       -- opcional: segundos (padrão 30)
    @retry_count = 2;                        -- opcional: de 0 a 10
```

O parâmetro de saída `@response` pode conter a resposta HTTP completa como uma string JSON:

```json
{
  "response": {
    "status": { "http": { "code": 200, "description": "OK" } },
    "headers": { "Content-Type": "application/json" }
  },
  "result": { ... }   // O corpo real da resposta da API
}
```

> [!important] Estrutura de Dois Níveis da Resposta
>
> Em uma resposta JSON, há normalmente **dois envelopes**:
>
> - `$.response.status.http.code` → código HTTP (200, 429, 401, etc.)
> - `$.result` → corpo da API (o payload real do OpenAI)
>
> **Sempre verifique o código HTTP antes de parsear** `$.result` — respostas de erro (401, 429, 400) podem ter estrutura JSON diferente das respostas de sucesso.

---

## DATABASE SCOPED CREDENTIAL para OpenAI

```sql
-- Armazenar a chave de API com segurança (nunca hardcode na procedure)
CREATE DATABASE SCOPED CREDENTIAL [AzureOpenAICredential]
WITH IDENTITY = 'HTTPEndpointHeaders',
SECRET = '{"api-key": "your-azure-openai-api-key-here"}';
```

A credencial é referenciada em `sp_invoke_external_rest_endpoint` via `@credential` — o header da chave de API é injetado automaticamente. Restrinja também quem pode executar chamadas externas e prefira uma identidade gerenciada quando o serviço intermediário oferecer suporte.

> [!caution] Nunca Hardcode a Chave de API
>
> Colocar a chave de API diretamente no `@headers` como `"api-key": "sk-..."` funciona tecnicamente, mas é **uma falha de segurança grave**. A chave ficará visível no texto da stored procedure, no histórico de queries e nos logs. Sempre use `DATABASE SCOPED CREDENTIAL` — ela criptografa o secret e não fica exposta no plano de execução.

---

## Convertendo Dados para JSON com FOR JSON

Antes de incluir dados SQL em um prompt, converta para um formato de texto/JSON que o LLM possa entender:

```sql
-- Converter resultados de query para JSON
DECLARE @products_json NVARCHAR(MAX);

SELECT @products_json = (
    SELECT TOP 5
        ProductId   AS id,
        ProductName AS name,
        Price       AS price,
        Description AS description
    FROM dbo.Products
    WHERE InStock = 1
    ORDER BY Price ASC
    FOR JSON PATH
);
-- Resultado: [{"id":1,"name":"Wireless Headphones","price":49.99,"description":"..."}]
```

```sql
-- Converter para texto formatado (mais legível para prompts LLM)
DECLARE @products_text NVARCHAR(MAX) = '';

SELECT @products_text = STRING_AGG(
    CONCAT('Product: ', ProductName,
           ' | Price: $', CAST(Price AS VARCHAR(20)),
           ' | ', LEFT(Description, 200)),
    CHAR(10))  -- nova linha entre produtos
FROM (
    SELECT TOP 5 ProductName, Price, Description
    FROM dbo.Products WHERE InStock = 1
    ORDER BY Price ASC
) t;
```

---

## Construindo Prompts

A API de chat completions do Azure OpenAI espera um array JSON de messages com `role` e `content`:

```sql
-- Construir o array de messages para um prompt RAG
DECLARE @system_message NVARCHAR(MAX) = N'You are a helpful product advisor.
Answer the customer question based ONLY on the provided product information.
If the answer is not in the product list, say "I don''t have that information."
Do not make up any product details.';

DECLARE @user_question NVARCHAR(500) = N'What are your cheapest in-ear headphones?';
DECLARE @context       NVARCHAR(MAX) = @products_text;  -- de cima

-- Construir o array sem concatenação manual ou escape incompleto
DECLARE @user_message NVARCHAR(MAX) =
    N'Context:' + CHAR(10) + @context + CHAR(10) + CHAR(10)
    + N'Question: ' + @user_question;

DECLARE @messages NVARCHAR(MAX) = (
    SELECT N'system' AS [role], @system_message AS [content]
    UNION ALL
    SELECT N'user', @user_message
    FOR JSON PATH
);
```

> [!tip] Onde Injetar o Contexto Recuperado
>
> Há duas abordagens comuns para injetar o contexto RAG:
>
> 1. **No system message**: inclua o contexto junto com as instruções do sistema
> 2. **No user message**: formate como "Context:\n{chunks}\n\nQuestion: {pergunta}"
>
> O exame pode testar que o contexto **não** é um parâmetro separado da API — ele é injetado dentro do conteúdo dos messages existentes. Ambas as abordagens acima são corretas.

---

## Procedure RAG Completa — End to End

```sql
CREATE OR ALTER PROCEDURE dbo.ProductRAG
    @user_question NVARCHAR(500),
    @query_vector  VECTOR(1536), -- gerado pelo SDK ou AI_GENERATE_EMBEDDINGS
    @top_k         INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    -- ── Passo 1: Recuperar produtos relevantes via busca vetorial ─────────────
    DECLARE @context NVARCHAR(MAX) = '';

    SELECT @context = STRING_AGG(
        CONCAT('Product: ', p.ProductName,
               CHAR(10), 'Price: $', CAST(p.Price AS VARCHAR(20)),
               CHAR(10), 'Description: ', LEFT(p.Description, 300),
               CHAR(10), '---'),
        CHAR(10))
    FROM VECTOR_SEARCH(
        TABLE = dbo.Products AS p,
        COLUMN = DescriptionVector,
        SIMILAR_TO = @query_vector,
        METRIC = 'cosine',
        TOP_N = @top_k
    ) AS vs;

    -- ── Passo 2: Construir o prompt ───────────────────────────────────────────
    DECLARE @system_msg  NVARCHAR(MAX) = N'You are a helpful product advisor. '
        + 'Answer using ONLY the products listed below. '
        + 'If you cannot answer from the list, say "I don''t know."';

    DECLARE @user_msg    NVARCHAR(MAX) =
        N'Available products:' + CHAR(10) + @context
        + CHAR(10) + CHAR(10) + 'Customer question: ' + @user_question;

    DECLARE @messages NVARCHAR(MAX) = (
        SELECT N'system' AS [role], @system_msg AS [content]
        UNION ALL
        SELECT N'user', @user_msg
        FOR JSON PATH
    );

    DECLARE @payload NVARCHAR(MAX) = (
        SELECT JSON_QUERY(@messages) AS [messages], 500 AS [max_tokens], 0 AS [temperature]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    -- ── Passo 3: Chamar um endpoint intermediário autorizado ──────────────────
    DECLARE @response NVARCHAR(MAX), @return_code INT;

    EXEC @return_code = sp_invoke_external_rest_endpoint
        @url        = N'https://<apim-name>.azure-api.net/rag/chat',
        @method     = N'POST',
        @headers    = N'{"Content-Type": "application/json"}',
        @payload    = @payload,
        @credential = [AzureOpenAICredential],
        @response   = @response OUTPUT;

    -- ── Passo 4: Parsear e retornar a resposta ────────────────────────────────
    DECLARE @http_code INT = JSON_VALUE(@response, '$.response.status.http.code');

    IF @return_code NOT BETWEEN 200 AND 299
    BEGIN
        DECLARE @error_msg NVARCHAR(MAX) = JSON_VALUE(@response, '$.result.error.message');
        RAISERROR('OpenAI API error (HTTP %d): %s', 16, 1, @http_code, @error_msg);
        RETURN;
    END;

    SELECT
        JSON_VALUE(@response, '$.result.choices[0].message.content') AS Answer,
        JSON_VALUE(@response, '$.result.usage.total_tokens')          AS TotalTokens,
        JSON_VALUE(@response, '$.result.model')                       AS ModelUsed;
END;
```

```sql
-- Uso: gere o vetor da pergunta antes de chamar a procedure.
EXEC dbo.ProductRAG @user_question = 'What headphones do you have under $100?',
                    @query_vector = @query_vector;
```

---

## Parseando Respostas JSON

### JSON_VALUE — Valores Escalares Únicos

```sql
DECLARE @response NVARCHAR(MAX) = '{"result": {"choices": [{"message": {"content": "Answer here"}}], "usage": {"total_tokens": 123}}}';

-- Extrair valores únicos
SELECT
    JSON_VALUE(@response, '$.result.choices[0].message.content') AS Answer,
    JSON_VALUE(@response, '$.result.usage.prompt_tokens')         AS PromptTokens,
    JSON_VALUE(@response, '$.result.usage.completion_tokens')     AS CompletionTokens,
    JSON_VALUE(@response, '$.result.usage.total_tokens')          AS TotalTokens;
```

### OPENJSON — Parseando Arrays

Quando o LLM retorna um array JSON (ex: uma lista de entidades extraídas):

```sql
DECLARE @llm_json_response NVARCHAR(MAX) = '
{
  "result": {
    "choices": [{
      "message": {
        "content": "{\"products\": [{\"id\": 1, \"reason\": \"Best match\"}, {\"id\": 7, \"reason\": \"Good value\"}]}"
      }
    }]
  }
}';

-- Primeiro extrair a string de content
DECLARE @content NVARCHAR(MAX) = JSON_VALUE(@llm_json_response, '$.result.choices[0].message.content');

-- Então parsear o JSON dentro do content
SELECT
    j.id,
    j.reason
FROM OPENJSON(@content, '$.products')
WITH (
    id     INT            '$.id',
    reason NVARCHAR(500)  '$.reason'
) AS j;
```

### JSON_QUERY — Extraindo Objetos/Arrays JSON

```sql
-- Extrair um array inteiro (não um escalar)
DECLARE @choices NVARCHAR(MAX) = JSON_QUERY(@response, '$.result.choices');

-- Extrair um objeto aninhado
DECLARE @usage NVARCHAR(MAX) = JSON_QUERY(@response, '$.result.usage');
```

> [!note] JSON_VALUE vs JSON_QUERY vs OPENJSON
>
> | Função | Uso | Retorna |
> |---|---|---|
> | `JSON_VALUE` | Extrair um **escalar** (string, número) | Valor escalar (NVARCHAR) |
> | `JSON_QUERY` | Extrair um **objeto ou array** JSON | String JSON |
> | `OPENJSON` | **Parsear** um array JSON em linhas | Tabela com linhas |
>
> Para parsear `$.result.choices[0].message.content` (um escalar) → `JSON_VALUE`.
> Para extrair `$.result.choices` (um array) → `JSON_QUERY`.
> Para iterar sobre items de um array → `OPENJSON`.

---

## Saída Estruturada — Forçando Respostas JSON

Use o parâmetro `response_format` para garantir que o LLM retorne JSON válido:

```sql
DECLARE @payload NVARCHAR(MAX) = N'{
    "messages": [
        {"role": "system", "content": "Classify the sentiment and extract key topics. Return JSON with fields: sentiment (Positive/Negative/Neutral), topics (array of strings), confidence (0-1)."},
        {"role": "user",   "content": "The delivery was super fast and the product is amazing!"}
    ],
    "response_format": {"type": "json_object"},
    "max_tokens": 200,
    "temperature": 0
}';

DECLARE @response NVARCHAR(MAX);
EXEC sp_invoke_external_rest_endpoint
    @url        = N'https://<apim-name>.azure-api.net/rag/chat',
    @method     = N'POST',
    @headers    = N'{"Content-Type": "application/json"}',
    @payload    = @payload,
    @credential = [AzureOpenAICredential],
    @response   = @response OUTPUT;

-- Parsear resposta JSON estruturada
DECLARE @content NVARCHAR(MAX) = JSON_VALUE(@response, '$.result.choices[0].message.content');

SELECT
    JSON_VALUE(@content, '$.sentiment')  AS Sentiment,
    JSON_VALUE(@content, '$.confidence') AS Confidence,
    JSON_QUERY(@content, '$.topics')     AS TopicsArray;

-- Parsear o array de topics
SELECT value AS Topic
FROM OPENJSON(JSON_QUERY(@content, '$.topics'));
```

---

## Tratamento de Erros

```sql
-- Padrão robusto de tratamento de erros para chamadas de LLM
DECLARE @response NVARCHAR(MAX);
DECLARE @http_code INT;
DECLARE @api_error NVARCHAR(MAX);

BEGIN TRY
    EXEC sp_invoke_external_rest_endpoint
        @url        = @endpoint_url,
        @method     = N'POST',
        @headers    = N'{"Content-Type": "application/json"}',
        @payload    = @payload,
        @credential = [AzureOpenAICredential],
        @response   = @response OUTPUT,
        @timeout    = 30;

    SET @http_code = JSON_VALUE(@response, '$.response.status.http.code');

    -- Tratar diferentes códigos de status HTTP
    IF @http_code = 200
    BEGIN
        -- Sucesso: extrair e usar a resposta
        SELECT JSON_VALUE(@response, '$.result.choices[0].message.content') AS Answer;
    END
    ELSE IF @http_code = 429
    BEGIN
        -- Rate limited: logar e fazer retry
        SET @api_error = 'Rate limit exceeded. Retry after: '
            + JSON_VALUE(@response, '$.response.headers.Retry-After');
        RAISERROR(@api_error, 10, 1);  -- severidade ≤10 = informacional
    END
    ELSE IF @http_code = 400
    BEGIN
        -- Bad request: provavelmente prompt muito longo
        SET @api_error = JSON_VALUE(@response, '$.result.error.message');
        RAISERROR('API bad request: %s', 16, 1, @api_error);
    END
    ELSE
    BEGIN
        SET @api_error = JSON_VALUE(@response, '$.result.error.message');
        RAISERROR('API error (HTTP %d): %s', 16, 1, @http_code, @api_error);
    END

END TRY
BEGIN CATCH
    -- Logar erros em uma tabela para monitoramento
    INSERT INTO dbo.RAGErrorLog (ErrorMessage, ErrorTime, Payload)
    VALUES (ERROR_MESSAGE(), GETUTCDATE(), @payload);
    THROW;
END CATCH;
```

> [!warning] HTTP 429 — Rate Limiting
>
> O código 429 indica limitação de taxa. `sp_invoke_external_rest_endpoint` pode usar `@retry_count` (de 0 a 10) e respeita `Retry-After` quando ele é fornecido. Para políticas mais completas de repetição, limite de custo e observabilidade, prefira a camada de aplicação ou o serviço intermediário.

---

## Gerenciamento de Tokens

```sql
-- Estimativa grosseira para decidir se é necessário reduzir o contexto.
-- Use o tokenizer e o limite publicados para o modelo/deployment em produção.

DECLARE @estimated_tokens INT =
    LEN(@system_msg) / 4 +   -- system message
    LEN(@context) / 4 +       -- contexto recuperado
    LEN(@user_question) / 4 + -- pergunta do usuário
    500;                       -- reserva para resposta

-- Exemplo de orçamento definido pela aplicação/configuração, não pelo nome do modelo.
DECLARE @context_budget_tokens INT = 8000;
IF @estimated_tokens > @context_budget_tokens
BEGIN
    -- Truncar contexto para caber
    SET @context = LEFT(@context, (@context_budget_tokens - LEN(@system_msg)/4 - LEN(@user_question)/4 - 500) * 4);
END;
```

---

## Casos de Uso

- **RAG in-database**: Construa pipelines RAG completos em T-SQL sem código na camada de aplicação — útil para jobs agendados, APIs baseadas em stored procedures
- **Processamento em lote**: Processe milhares de linhas através de um LLM em um loop ou cursor T-SQL
- **Classificação**: Classifique feedback de clientes, tickets de suporte ou produtos usando um LLM chamado de um UPDATE SQL
- **Extração estruturada**: Extraia entidades (datas, nomes, valores) de texto não estruturado para colunas estruturadas

---

## Problemas Comuns e Erros

| Problema | Causa | Correção |
| :--- | :--- | :--- |
| `HTTP 401 Unauthorized` | Chave de API errada ou ausente na credencial | Recrie a DATABASE SCOPED CREDENTIAL com a chave correta |
| `HTTP 429 Too Many Requests` | Limite de rate atingido | Implemente retry com exponential backoff; aumente a quota |
| `HTTP 400 Bad Request` | Prompt muito longo ou JSON malformado | Verifique a contagem de tokens; valide o payload JSON; escape caracteres especiais |
| Erro de parse JSON na resposta | Resposta não é JSON válido | Verifique `$.response.status.http.code` primeiro; pode ser uma página de erro HTML |
| `QUOTENAME` retorna NULL para inputs > 128 chars | `QUOTENAME` aceita `nvarchar(128)` — retorna NULL para input mais longo | Para strings longas, use `REPLACE(@text, '"', '\"')` em vez disso |
| Respostas inconsistentes | Temperature > 0 | Defina `"temperature": 0` para saída factual/determinística |

---

## Dicas para o Exame

> [!tip] Dicas para o Exame
>
> - `sp_invoke_external_rest_endpoint` é a ponte T-SQL para APIs REST externas incluindo Azure OpenAI
> - A estrutura JSON de resposta tem dois níveis: `$.response.status` (metadados HTTP) e `$.result` (payload da API)
> - `DATABASE SCOPED CREDENTIAL` com `IDENTITY = 'HTTPEndpointHeaders'` injeta headers (como chaves de API) automaticamente
> - `FOR JSON PATH` converte resultados de query para JSON para embutir em prompts
> - `JSON_VALUE` extrai escalares; `JSON_QUERY` extrai objetos/arrays; `OPENJSON` parseia arrays em linhas
> - Sempre verifique o código de status HTTP antes de parsear o corpo da resposta — erros têm estrutura JSON diferente

---

## Principais Conclusões

- `sp_invoke_external_rest_endpoint` chama endpoints REST HTTPS autorizados a partir do T-SQL; use um intermediário para serviços fora da lista permitida
- Construção de prompt: system message (instruções) + context (dados recuperados como texto/JSON) + pergunta do usuário
- Parsear respostas do LLM com `JSON_VALUE` para escalares e `OPENJSON` para arrays
- Sempre trate erros HTTP (401, 429, 400) antes de extrair o conteúdo da resposta
- Use `"temperature": 0` para respostas factuais determinísticas; `"response_format": {"type": "json_object"}` para saída estruturada

---

## Resposta do modelo como contrato não confiável

Confira o resultado HTTP antes do parsing. O wrapper de
`sp_invoke_external_rest_endpoint` pode colocar a resposta em `$.result`; não
presuma o caminho de uma chamada direta. Valide schema, trate erros antes da
extração, registre correlation ID e mantenha rastreabilidade das fontes.

## Tópicos Relacionados

- [01-Casos de Uso de RAG](./01-rag-use-cases.md)
- [01-External Models](../09-models-embeddings/01-external-models.md)
- [03-Hybrid Search e RRF](../10-intelligent-search/03-hybrid-search-rrf.md)

---

## Documentação Oficial

- [sp_invoke_external_rest_endpoint](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-invoke-external-rest-endpoint-transact-sql)
- [FOR JSON (T-SQL)](https://learn.microsoft.com/en-us/sql/relational-databases/json/format-query-results-as-json-with-for-json-sql-server)
- [OPENJSON (T-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql)
- [Azure OpenAI Chat Completions API](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#chat-completions)

---

**[← Anterior](./01-rag-use-cases.md) | [↑ Voltar à Seção](./rag.md) | [Lab: Prompts e Respostas](../../practice/labs/11-rag/02-prompts-and-responses-lab.sql)**
