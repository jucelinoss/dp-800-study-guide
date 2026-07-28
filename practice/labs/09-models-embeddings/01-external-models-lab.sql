-- =================================================================================
-- DP-800 - PRACTICAL LAB: EXTERNAL AI MODELS (CREATE EXTERNAL MODEL AND AI_GENERATE_EMBEDDINGS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- CONFIGURATION NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates the integration of AI models (Azure OpenAI) as database objects:
--   1. Creating Scope Credentials (`CREATE DATABASE SCOPED CREDENTIAL`)
--   2. Registering External Models (`CREATE EXTERNAL MODEL`) for Embeddings and Completions
--   3. Embedding generation through the `AI_GENERATE_EMBEDDINGS` function
--   4. Usage Permission Management (`GRANT EXECUTE ON EXTERNAL MODEL`)
--   5. Native VECTOR storage, REST invocation, and model-dimension decisions
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/09-models-embeddings/01-external-models.md
--    Open the theory guide alongside this lab for conceptual context.

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
    EmbeddingVector VECTOR(1536) NULL
);
GO

INSERT INTO lab.ProductEmbeddings (ProductID, ProductDescription) VALUES
(1, N'Lightweight cycling helmet with high impact protection'),
(2, N'Mountain bike with 24 gears and dual suspension');
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
SECRET = '{"api-key": "YOUR_AZURE_OPENAI_KEY_HERE"}';
GO

-- 2. Create the External Model for Embeddings (text-embedding-3-small)
CREATE EXTERNAL MODEL [AzureOpenAI_Embedding_Small]
WITH (
    LOCATION = 'https://my-openai-resource.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings',
    API_FORMAT = 'Azure_OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    CREDENTIAL = [AzureOpenAIApiKeyCred]
);
GO

-- 3. Query registered external models in the catalog view
SELECT 
    name AS ModelName,
    model_type_desc AS ModelType,
    location AS EndpointURL,
    create_date AS CreatedAt
FROM sys.external_models;
GO


-- =================================================================================
-- PART 2: INVOKING AI_GENERATE_EMBEDDINGS AND ASSIGNING PERMISSIONS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - AI_GENERATE_EMBEDDINGS: Generates an embedding from a text value using a registered embedding model.
--   - PERMISSIONS: The caller needs `GRANT EXECUTE ON EXTERNAL MODEL` for the external model.

-- -- [DP-800 POINT OF ATTENTION]
-- 1. Grant external model execution permission to the application role
GRANT EXECUTE ON EXTERNAL MODEL::[AzureOpenAI_Embedding_Small] TO [public];
GO

-- 2. Example: generate and persist embeddings with the external model
/*
UPDATE p
SET EmbeddingVector = AI_GENERATE_EMBEDDINGS(
    p.ProductDescription USE MODEL [AzureOpenAI_Embedding_Small]
)
FROM lab.ProductEmbeddings AS p
WHERE p.EmbeddingVector IS NULL;
*/
GO

-- Inspect the generated vector metadata after running the preceding example.
/*
SELECT ProductID,
       VECTORPROPERTY(EmbeddingVector, 'Dimensions') AS Dimensions,
       VECTORPROPERTY(EmbeddingVector, 'BaseType') AS BaseType
FROM lab.ProductEmbeddings;
*/


-- =================================================================================
-- PART 3: REST INVOCATION FOR A CHAT COMPLETION
-- =================================================================================

-- Embeddings are normally generated with AI_GENERATE_EMBEDDINGS. For a chat-completion
-- endpoint, call the REST endpoint explicitly and consume the returned JSON.
/*
DECLARE @Payload NVARCHAR(MAX) = N'{
  "messages": [{"role": "user", "content": "Summarize this product description."}],
  "max_tokens": 100
}';

EXEC sp_invoke_external_rest_endpoint
    @method = N'POST',
    @url = N'https://my-openai-resource.openai.azure.com/openai/deployments/my-chat-deployment/chat/completions?api-version=2024-10-21',
    @payload = @Payload,
    @credential = [AzureOpenAIApiKeyCred];
*/
GO

-- =================================================================================
-- PART 4: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Embedding Model Dimensioning Comparison Matrix
-- Architecture decision guide for vector storage and cost.

SELECT 
    'text-embedding-3-small' AS Model,
    1536 AS VectorDimensions,
    'Lower / suitable for most workloads' AS StorageCost,
    'Recommended default for RAG and semantic search' AS Recommendation
UNION ALL
SELECT 
    'text-embedding-3-large',
    3072,
    'Higher (twice as many values per vector)',
    'Use only when additional retrieval quality is required';
GO

-- Do not mix vectors from different embedding models or dimensions in one search space.

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/09-models-embeddings/01-external-models.md
-- =================================================================================================
