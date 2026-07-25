-- =================================================================================
-- DP-800 - HANDS-ON LAB: ADVANCED JSON FUNCTIONS (OPENJSON, AGGREGATIONS, AND LLM PAYLOADS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to restore the AdventureWorks
-- database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates advanced JSON processing in SQL Server:
--   1. Scalar vs Fragment Extraction: JSON_VALUE vs JSON_QUERY in lax and strict modes
--   2. Unfolding Nested Documents with OPENJSON and CROSS APPLY
--   3. JSON Construction and Serialization: FOR JSON PATH vs AUTO, JSON_OBJECT and JSON_ARRAY
--   4. JSON Aggregations in SQL Server 2025: JSON_ARRAYAGG and JSON_OBJECTAGG
--   5. Type Validation with ISJSON and Manipulation with JSON_MODIFY
--   6. Practical Project Scenarios (Generating JSON Payloads for AI / LLM APIs)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.ApiEvents;
DROP TABLE IF EXISTS lab.ProductAttributes;
GO

-- Test Table Structure
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
-- PART 1: JSON_VALUE VS JSON_QUERY AND LAX VS STRICT BEHAVIOR
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - JSON_VALUE: Extracts a scalar value (string/number/boolean). Returns NULL if pointing to an object or array.
--   - JSON_QUERY: Extracts a valid JSON object or array as a substring. Returns NULL if pointing to a scalar value.
--   - LAX MODE (Default): Non-existent or invalid paths silently return NULL.
--   - STRICT MODE: Non-existent paths raise runtime error Msg 13608.

DECLARE @doc NVARCHAR(MAX) = N'{
    "customer": {"id": 101, "name": "Alice"},
    "tags": ["vip", "premium"],
    "score": 98.5
}';

-- -- [DP-800 EXAM TIP]
-- Testing the extraction difference between JSON_VALUE and JSON_QUERY
SELECT 
    JSON_VALUE(@doc, '$.customer.name')   AS NomeEscalar,        -- Returns 'Alice'
    JSON_VALUE(@doc, '$.customer')        AS ValorObjetoComValue, -- Returns NULL (Common mistake! Was an object)
    JSON_QUERY(@doc, '$.customer')        AS ObjetoComQuery,      -- Returns '{"id": 101, "name": "Alice"}'
    JSON_QUERY(@doc, '$.tags')            AS ArrayComQuery,       -- Returns '["vip", "premium"]'
    JSON_VALUE(@doc, 'lax $.missingKey')  AS LaxInexistente;      -- Returns NULL
GO

-- Error Test with STRICT Mode:
-- Trying to find a non-existent key in strict mode raises error Msg 13608.
DECLARE @docStrict NVARCHAR(MAX) = N'{"id": 1}';
BEGIN TRY
    SELECT JSON_VALUE(@docStrict, 'strict $.missingKey');
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO MODO STRICT: ' + ERROR_MESSAGE();
    -- Error: "Property cannot be found on the specified JSON path."
END CATCH;
GO


-- =================================================================================
-- PART 2: NESTED JSON UNFOLDING WITH OPENJSON AND CROSS APPLY
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - OPENJSON with AS JSON: When a property is an inner array, the `AS JSON` clause in the `WITH`
--     instruction keeps the array as a raw JSON string, allowing a second `CROSS APPLY OPENJSON` on it.

DECLARE @ordersPayload NVARCHAR(MAX) = N'[
    {"orderId": 5001, "customer": "Empresa A", "items": [{"sku":"KB-1", "qty":2}, {"sku":"MS-2", "qty":5}]},
    {"orderId": 5002, "customer": "Empresa B", "items": [{"sku":"MN-9", "qty":1}]}
]';

-- Unfolding orders and their items into a single relational result set
SELECT 
    o.orderId,
    o.customer,
    item.sku,
    item.qty
FROM OPENJSON(@ordersPayload)
WITH (
    orderId  INT           '$.orderId',
    customer NVARCHAR(100) '$.customer',
    items    NVARCHAR(MAX) '$.items' AS JSON -- AS JSON preserves the inner array
) o
CROSS APPLY OPENJSON(o.items)
WITH (
    sku NVARCHAR(50) '$.sku',
    qty INT          '$.qty'
) item;
GO


-- =================================================================================
-- PART 3: NATIVE JSON AGGREGATIONS (JSON_ARRAYAGG AND JSON_OBJECTAGG - SQL SERVER 2025)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - JSON_ARRAYAGG: Aggregates row values into a unified JSON array.
--   - JSON_OBJECTAGG: Converts column pairs (key: value) from multiple rows into a single JSON object document.
--   - SQL Server 2025: both aggregators are available in preview; they remain useful for
--     practicing the syntax tested in the target environment of this guide.

INSERT INTO lab.ProductAttributes VALUES 
(10, 'color', 'Red'),
(10, 'size', 'XL'),
(10, 'weight', '1.5kg'),
(20, 'color', 'Blue');
GO

-- -- [DP-800 EXAM TIP]
-- Convert attribute rows into a single dynamic JSON object per product
SELECT 
    ProductID,
    JSON_OBJECTAGG(AttributeName: AttributeValue) AS AttributesJson
FROM lab.ProductAttributes
GROUP BY ProductID;
GO

-- Convert attribute names into a JSON array per product.
SELECT
    ProductID,
    JSON_ARRAYAGG(AttributeName ORDER BY AttributeName) AS AttributeNamesJson
FROM lab.ProductAttributes
GROUP BY ProductID;
GO


-- =================================================================================
-- PART 4: MODIFICATION WITH JSON_MODIFY
-- =================================================================================
DECLARE @jsonConfig NVARCHAR(MAX) = N'{"env":"dev","timeout":30}';

-- 1. Update value
SET @jsonConfig = JSON_MODIFY(@jsonConfig, '$.timeout', 60);

-- 2. Add new key
SET @jsonConfig = JSON_MODIFY(@jsonConfig, '$.maxRetries', 3);

-- 3. Remove a key (assigning NULL)
SET @jsonConfig = JSON_MODIFY(@jsonConfig, '$.env', NULL);

SELECT @jsonConfig AS ConfigAtualizada;
GO


-- =================================================================================
-- PART 5: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Generating Formatted Payloads for AI / LLM APIs (RAG Prompt)
-- Converts a relational query into a perfectly formatted JSON document
-- for consumption by an OpenAI / Azure OpenAI Service endpoint.

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
