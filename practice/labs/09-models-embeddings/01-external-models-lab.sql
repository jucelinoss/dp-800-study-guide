-- =================================================================================
-- DP-800 - PRACTICAL LAB: EXTERNAL AI MODELS (CREATE EXTERNAL MODEL AND PREDICT)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- CONFIGURATION NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates the integration of AI models (Azure OpenAI) as database objects:
--   1. Creating Scope Credentials (`CREATE DATABASE SCOPED CREDENTIAL`)
--   2. Registering External Models (`CREATE EXTERNAL MODEL`) for Embeddings and Completions
--   3. Invocation via `PREDICT(MODEL = ..., DATA = ...)` Function
--   4. Usage Permission Management (`GRANT EXECUTE ON EXTERNAL MODEL`)
--   5. Practical Project Scenarios (Storing 1536-dimension Vectors)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventative cleanup
IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'AzureOpenAI_Embedding_Small')
    DROP EXTERNAL MODEL [AzureOpenAI_Embedding_Small];

IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'AzureOpenAIApiKeyCred')
    DROP DATABASE SCOPED CREDENTIAL [AzureOpenAIApiKeyCred];

DROP TABLE IF EXISTS lab.ProductEmbeddings;
GO

-- Table Structure for Vector Storage
CREATE TABLE lab.ProductEmbeddings (
    ProductID INT PRIMARY KEY,
    ProductDescription NVARCHAR(MAX) NOT NULL,
    EmbeddingVector NVARCHAR(MAX) NULL -- Stores the 1536-dimension vector serialized as JSON
);
GO

INSERT INTO lab.ProductEmbeddings (ProductID, ProductDescription) VALUES
(1, N'Capacete de ciclismo leve com alta protecao contra impactos'),
(2, N'Bicicleta de montanha com 24 marchas e suspensao dupla');
GO


-- =================================================================================
-- PART 1: EXTERNAL MODEL REGISTRATION AND SCOPE CREDENTIAL
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CREATE EXTERNAL MODEL: Registers an AI endpoint (Azure OpenAI / Fabric AI) in the database object catalog.
--   - CREDENTIAL: References the scope credential containing the API key (Bearer Token) securely.

-- -- [DP-800 POINT OF ATTENTION]
-- 1. Create the Scope Credential with the API access key
CREATE DATABASE SCOPED CREDENTIAL [AzureOpenAIApiKeyCred]
WITH IDENTITY = 'HTTPEndpointHeaders',
SECRET = '{"api-key": "SUA_AZURE_OPENAI_KEY_AQUI"}';
GO

-- 2. Create the External Model for Embeddings (text-embedding-3-small)
CREATE EXTERNAL MODEL [AzureOpenAI_Embedding_Small]
WITH (
    LOCATION = 'https://meu-recurso-openai.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings',
    API_FORMAT = 'Azure_OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    CREDENTIAL = [AzureOpenAIApiKeyCred]
);
GO

-- 3. Query registered external models in the catalog view
SELECT 
    name AS NomeModelo,
    model_type_desc AS TipoModelo,
    location AS EndpointURL,
    create_date AS DataCriacao
FROM sys.external_models;
GO


-- =================================================================================
-- PART 2: INVOKING THE MODEL VIA PREDICT AND ASSIGNING PERMISSIONS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - PREDICT: Native T-SQL function to invoke integrated AI models.
--   - PERMISSIONS: To invoke a model with PREDICT, the user needs the `GRANT EXECUTE ON EXTERNAL MODEL` permission.

-- -- [DP-800 POINT OF ATTENTION]
-- 1. Grant external model execution permission to the application role
GRANT EXECUTE ON EXTERNAL MODEL::[AzureOpenAI_Embedding_Small] TO [public];
GO

-- 2. Conceptual example of batch call via PREDICT to populate the vector column
/*
UPDATE p
SET EmbeddingVector = CAST(
    PREDICT(MODEL = [AzureOpenAI_Embedding_Small],
            DATA = (SELECT p2.ProductDescription AS input_text)
           ) AS NVARCHAR(MAX))
FROM lab.ProductEmbeddings p
CROSS APPLY (SELECT p.ProductDescription) p2(ProductDescription)
WHERE p.EmbeddingVector IS NULL;
*/
GO


-- =================================================================================
-- PART 3: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Embedding Model Dimensioning Comparison Matrix
-- Architecture decision guide for vector storage and cost.

SELECT 
    'text-embedding-3-small' AS Modelo,
    1536 AS DimensoesVetor,
    'Baixo / Otimo para a maioria dos casos' AS CustoStorage,
    'Recomendado como padrao para RAG e busca semantica' AS Recomendacao
UNION ALL
SELECT 
    'text-embedding-3-large',
    3072,
    'Alto (Dobro do tamanho por vetor)',
    'Usar apenas quando for exigida altíssima precisão de busca';
GO
