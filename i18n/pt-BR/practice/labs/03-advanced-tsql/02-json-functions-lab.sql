-- =================================================================================
-- DP-800 - LAB PRÁTICO: FUNÇÕES AVANÇADAS DE JSON (OPENJSON, AGGREGAÇÕES E LLM PAYLOADS)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o processamento avançado de JSON no SQL Server:
--   1. Extração Escalar vs Fragmento: JSON_VALUE vs JSON_QUERY em modos lax e strict
--   2. Desmembramento de Documentos Aninhados com OPENJSON e CROSS APPLY
--   3. Construção e Serialização de JSON: FOR JSON PATH vs AUTO, JSON_OBJECT e JSON_ARRAY
--   4. Agregações JSON no SQL Server 2025: JSON_ARRAYAGG e JSON_OBJECTAGG
--   5. Validação de Tipos com ISJSON e Manipulação com JSON_MODIFY
--   6. Cenários Práticos de Projeto (Geração de Payloads JSON para APIs de IA / LLMs)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.ApiEvents;
DROP TABLE IF EXISTS lab.ProductAttributes;
GO

-- Estrutura de Tabelas para Teste
CREATE TABLE lab.ApiEvents (
    EventID INT IDENTITY(1,1) PRIMARY KEY,
    Payload NVARCHAR(MAX) NOT NULL,
    CONSTRAINT CK_ApiEvents_Payload CHECK (ISJSON(Payload) = 1)
);

CREATE TABLE lab.ProductAttributes (
    ProductID INT NOT NULL,
    AttributeName NVARCHAR(50) NOT NULL,
    AttributeValue NVARCHAR(100) NOT NULL,
    PRIMARY KEY (ProductID, AttributeName)
);
GO


-- =================================================================================
-- PARTE 1: JSON_VALUE VS JSON_QUERY E COMPORTAMENTO LAX VS STRICT
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - JSON_VALUE: Extrai um valor escalar (string/número/booleano). Retorna NULL se apontar para objeto ou array.
--   - JSON_QUERY: Extrai um objeto ou array JSON válido como substring. Retorna NULL se apontar para valor escalar.
--   - MODO LAX (Padrão): Caminhos inexistentes ou inválidos retornam NULL silenciosamente.
--   - MODO STRICT: Caminhos inexistentes disparam o erro de execução Msg 13608.

DECLARE @doc NVARCHAR(MAX) = N'{
    "customer": {"id": 101, "name": "Alice"},
    "tags": ["vip", "premium"],
    "score": 98.5
}';

-- -- [PONTO DE ATENÇÃO DP-800]
-- Testando a diferença de extração entre JSON_VALUE e JSON_QUERY
SELECT 
    JSON_VALUE(@doc, '$.customer.name')   AS NomeEscalar,        -- Retorna 'Alice'
    JSON_VALUE(@doc, '$.customer')        AS ValorObjetoComValue, -- Retorna NULL (Erro comum! Era objeto)
    JSON_QUERY(@doc, '$.customer')        AS ObjetoComQuery,      -- Retorna '{"id": 101, "name": "Alice"}'
    JSON_QUERY(@doc, '$.tags')            AS ArrayComQuery,       -- Retorna '["vip", "premium"]'
    JSON_VALUE(@doc, 'lax $.missingKey')  AS LaxInexistente;      -- Retorna NULL
GO

-- Teste de Erro com Modo STRICT:
-- Tentar buscar uma chave inexistente em modo strict dispara erro Msg 13608.
DECLARE @docStrict NVARCHAR(MAX) = N'{"id": 1}';
BEGIN TRY
    SELECT JSON_VALUE(@docStrict, 'strict $.missingKey');
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO MODO STRICT: ' + ERROR_MESSAGE();
    -- Erro: "Property cannot be found on the specified JSON path."
END CATCH;
GO


-- =================================================================================
-- PARTE 2: DESMEMBRAMENTO DE JSON ANINHADO COM OPENJSON E CROSS APPLY
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - OPENJSON com AS JSON: Quando uma propriedade é um array interno, a cláusula `AS JSON` na instrução `WITH`
--     mantém o array como uma string JSON bruta, permitindo fazer um segundo `CROSS APPLY OPENJSON` nele.

DECLARE @ordersPayload NVARCHAR(MAX) = N'[
    {"orderId": 5001, "customer": "Empresa A", "items": [{"sku":"KB-1", "qty":2}, {"sku":"MS-2", "qty":5}]},
    {"orderId": 5002, "customer": "Empresa B", "items": [{"sku":"MN-9", "qty":1}]}
]';

-- Desmembrando os pedidos e seus respectivos itens em um único conjunto relacional
SELECT 
    o.orderId,
    o.customer,
    item.sku,
    item.qty
FROM OPENJSON(@ordersPayload)
WITH (
    orderId  INT           '$.orderId',
    customer NVARCHAR(100) '$.customer',
    items    NVARCHAR(MAX) '$.items' AS JSON -- AS JSON preserva o array interno
) o
CROSS APPLY OPENJSON(o.items)
WITH (
    sku NVARCHAR(50) '$.sku',
    qty INT          '$.qty'
) item;
GO


-- =================================================================================
-- PARTE 3: AGREGAÇÕES NATIVAS EM JSON (JSON_ARRAYAGG E JSON_OBJECTAGG - SQL SERVER 2025)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - JSON_ARRAYAGG: Agrega valores das linhas em um array JSON unificado.
--   - JSON_OBJECTAGG: Converte pares de colunas (chave: valor) de várias linhas em um único documento de objeto JSON.
--   - SQL Server 2025: ambos os agregadores estão disponíveis em preview; permanecem úteis para
--     praticar a sintaxe cobrada no ambiente-alvo deste guia.

INSERT INTO lab.ProductAttributes VALUES 
(10, 'color', 'Red'),
(10, 'size', 'XL'),
(10, 'weight', '1.5kg'),
(20, 'color', 'Blue');
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- Converter linhas de atributos em um único objeto JSON dinâmico por produto
SELECT 
    ProductID,
    JSON_OBJECTAGG(AttributeName: AttributeValue) AS AttributesJson
FROM lab.ProductAttributes
GROUP BY ProductID;
GO

-- Converter os nomes dos atributos em um array JSON por produto.
SELECT
    ProductID,
    JSON_ARRAYAGG(AttributeName ORDER BY AttributeName) AS AttributeNamesJson
FROM lab.ProductAttributes
GROUP BY ProductID;
GO


-- =================================================================================
-- PARTE 4: MODIFICAÇÃO COM JSON_MODIFY
-- =================================================================================
DECLARE @jsonConfig NVARCHAR(MAX) = N'{"env":"dev","timeout":30}';

-- 1. Atualizar valor
SET @jsonConfig = JSON_MODIFY(@jsonConfig, '$.timeout', 60);

-- 2. Adicionar nova chave
SET @jsonConfig = JSON_MODIFY(@jsonConfig, '$.maxRetries', 3);

-- 3. Remover uma chave (atribuindo NULL)
SET @jsonConfig = JSON_MODIFY(@jsonConfig, '$.env', NULL);

SELECT @jsonConfig AS ConfigAtualizada;
GO


-- =================================================================================
-- PARTE 5: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Geração de Payloads Formatados para APIs de IA / LLM (Prompt RAG)
-- Converte uma consulta relacional em um documento JSON perfeitamente formatado
-- para consumo por um endpoint do OpenAI / Azure OpenAI Service.

DECLARE @SystemPrompt NVARCHAR(200) = N'Você é um assistente especialista em banco de dados SQL Server.';
DECLARE @UserQuery NVARCHAR(200) = N'Como posso otimizar uma consulta usando índices cobertos?';

SELECT JSON_OBJECT(
    'model'       : 'gpt-4o',
    'temperature' : 0.2,
    'messages'    : JSON_QUERY(JSON_ARRAY(
        JSON_OBJECT('role': 'system', 'content': @SystemPrompt),
        JSON_OBJECT('role': 'user',   'content': @UserQuery)
    ))
) AS LLMPayloadJSON;
GO
