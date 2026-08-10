-- =================================================================================
-- DP-800 - PRACTICAL LAB: EXTERNAL AI MODELS (CREATE EXTERNAL MODEL AND AI_GENERATE_EMBEDDINGS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- CONFIGURATION NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- SAFETY: Run only in a disposable lab database. This script creates/drops external
-- model metadata, a database scoped credential, and a lab table. Replace the
-- credential secret and endpoint with test values; never use a production key here.
-- This script demonstrates the integration of AI models (Azure OpenAI) as database objects:
--   1. Creating Scope Credentials (`CREATE DATABASE SCOPED CREDENTIAL`)
--   2. Registering an External Model (`CREATE EXTERNAL MODEL`) for Embeddings
--   3. Embedding generation through the `AI_GENERATE_EMBEDDINGS` function
--   4. Usage Permission Management (`GRANT EXECUTE ON EXTERNAL MODEL`)
--   5. Native VECTOR storage, REST invocation, and model-dimension decisions
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/09-models-embeddings/01-external-models.md
--    Open the theory guide alongside this lab for conceptual context.

USE AdventureWorks2025;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'lab')
    EXEC(N'CREATE SCHEMA lab AUTHORIZATION dbo;');
GO

-- Preventative cleanup
IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'AzureOpenAI_Embedding_Small')
    DROP EXTERNAL MODEL [AzureOpenAI_Embedding_Small];

IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'https://my-openai-resource.openai.azure.com/')
    DROP DATABASE SCOPED CREDENTIAL [https://my-openai-resource.openai.azure.com/];

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'lab_embedding_executor')
    DROP ROLE [lab_embedding_executor];

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
-- SQL Server 2025 requires this server option; Azure SQL Database and Fabric
-- have it enabled by default. Run it with ALTER SETTINGS when applicable.
-- EXEC sp_configure 'external rest endpoint enabled', 1;
-- RECONFIGURE WITH OVERRIDE;
CREATE DATABASE SCOPED CREDENTIAL [https://my-openai-resource.openai.azure.com/]
WITH IDENTITY = 'HTTPEndpointHeaders',
SECRET = '{"api-key":"YOUR_AZURE_OPENAI_KEY_HERE"}';
GO

-- 2. Create the External Model for Embeddings (text-embedding-3-small)
CREATE EXTERNAL MODEL [AzureOpenAI_Embedding_Small]
WITH (
    LOCATION = 'https://my-openai-resource.openai.azure.com/openai/deployments/my-embedding-deployment/embeddings?api-version=2024-02-01',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'text-embedding-3-small',
    CREDENTIAL = [https://my-openai-resource.openai.azure.com/],
    PARAMETERS = '{"dimensions":1536}'
);
GO

-- 3. Query registered external models in the catalog view
SELECT 
    name AS ModelName,
    model_type_desc AS ModelType,
    location AS EndpointURL,
    create_time AS CreatedAt,
    modify_time AS ModifiedAt
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
CREATE ROLE [lab_embedding_executor];
GRANT EXECUTE ON EXTERNAL MODEL::[AzureOpenAI_Embedding_Small] TO [lab_embedding_executor];
GO

-- In a real project, add only the application/service principal to this role.
-- ALTER ROLE [lab_embedding_executor] ADD MEMBER [EmbeddingAppRole];

-- 2. Generate and persist embeddings with the external model.
-- Run this block after replacing the credential secret and deployment URL above.
SELECT AI_GENERATE_EMBEDDINGS(
    N'Lightweight cycling helmet with high impact protection'
    USE MODEL [AzureOpenAI_Embedding_Small]
) AS SingleEmbeddingJSON;
GO

-- 3. Process all pending rows in one set-based statement.
UPDATE p
SET EmbeddingVector = AI_GENERATE_EMBEDDINGS(
    p.ProductDescription USE MODEL [AzureOpenAI_Embedding_Small]
)
FROM lab.ProductEmbeddings AS p
WHERE p.EmbeddingVector IS NULL;
GO

-- 4. Inspect the generated vector metadata.
SELECT ProductID,
       VECTORPROPERTY(EmbeddingVector, 'Dimensions') AS Dimensions,
       VECTORPROPERTY(EmbeddingVector, 'BaseType') AS BaseType
FROM lab.ProductEmbeddings;
GO

-- 5. Confirm that the expected number of rows was vectorized.
SELECT
    COUNT(*) AS TotalRows,
    SUM(CASE WHEN EmbeddingVector IS NOT NULL THEN 1 ELSE 0 END) AS EmbeddedRows,
    SUM(CASE WHEN EmbeddingVector IS NULL THEN 1 ELSE 0 END) AS PendingRows
FROM lab.ProductEmbeddings;
GO

-- =================================================================================
-- OPTION B: LOCAL OLLAMA (NO CLOUD API KEY / NO PER-CALL API COST)
-- =================================================================================
-- This alternative is intentionally commented out. To use it instead of Azure:
--   1. Install Ollama and download an embedding model, for example: ollama pull all-minilm
--   2. Expose an HTTPS Ollama endpoint reachable by SQL Server.
--      The SQL Server Learn example uses https://localhost:11435/api/embed.
--      The default Ollama HTTP listener (usually port 11434) is not enough when
--      the SQL Server endpoint requires HTTPS; use TLS or a local HTTPS proxy.
--   3. Uncomment and run this section. Keep the Azure section separate from this one.
-- The all-minilm model returns 384-dimensional embeddings in the standard Ollama setup.
/*
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = 'LocalOllamaEmbedding')
    DROP EXTERNAL MODEL [LocalOllamaEmbedding];

DROP TABLE IF EXISTS lab.ProductEmbeddings_Ollama;
GO

CREATE EXTERNAL MODEL [LocalOllamaEmbedding]
WITH
(
    LOCATION = 'https://localhost:11435/api/embed',
    API_FORMAT = 'Ollama',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'all-minilm'
);
GO

CREATE TABLE lab.ProductEmbeddings_Ollama
(
    ProductID INT NOT NULL PRIMARY KEY,
    ProductDescription NVARCHAR(MAX) NOT NULL,
    EmbeddingVector VECTOR(384) NULL
);

INSERT INTO lab.ProductEmbeddings_Ollama (ProductID, ProductDescription)
VALUES
    (1, N'Local embedding with Ollama and SQL Server'),
    (2, N'Offline semantic search without a cloud API');
GO

GRANT EXECUTE ON EXTERNAL MODEL::[LocalOllamaEmbedding]
    TO [lab_embedding_executor];
GO

UPDATE p
SET EmbeddingVector = AI_GENERATE_EMBEDDINGS(
    p.ProductDescription USE MODEL [LocalOllamaEmbedding]
)
FROM lab.ProductEmbeddings_Ollama AS p
WHERE p.EmbeddingVector IS NULL;
GO

SELECT ProductID,
       VECTORPROPERTY(EmbeddingVector, 'Dimensions') AS Dimensions,
       VECTORPROPERTY(EmbeddingVector, 'BaseType') AS BaseType
FROM lab.ProductEmbeddings_Ollama;
GO
*/

-- =================================================================================
-- OPTION C: LOCAL ONNX RUNTIME (FULLY LOCAL)
-- =================================================================================
-- This alternative is intentionally commented out. It requires SQL Server 2025,
-- SQL Server Machine Learning Services, ONNX Runtime, and the tokenizers-cpp DLL.
-- Follow the Microsoft Learn setup to place model.onnx and tokenizer.json under
-- C:\onnx_runtime\model\all-MiniLM-L6-v2-onnx and runtime DLLs under C:\onnx_runtime.
-- Grant the SQL Server Launchpad service account access to that directory.
-- Enable preview features and external AI runtimes before running this block:
--   ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
--   EXEC sp_configure 'external AI runtimes enabled', 1;
--   RECONFIGURE WITH OVERRIDE;
/*
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = 'LocalOnnxEmbedding')
    DROP EXTERNAL MODEL [LocalOnnxEmbedding];

DROP TABLE IF EXISTS lab.ProductEmbeddings_Onnx;
GO

CREATE EXTERNAL MODEL [LocalOnnxEmbedding]
WITH
(
    LOCATION = 'C:\onnx_runtime\model\all-MiniLM-L6-v2-onnx',
    API_FORMAT = 'ONNX Runtime',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'allMiniLM',
    PARAMETERS = '{"valid":"JSON"}',
    LOCAL_RUNTIME_PATH = 'C:\onnx_runtime\'
);
GO

CREATE TABLE lab.ProductEmbeddings_Onnx
(
    ProductID INT NOT NULL PRIMARY KEY,
    ProductDescription NVARCHAR(MAX) NOT NULL,
    EmbeddingVector VECTOR(384) NULL
);

INSERT INTO lab.ProductEmbeddings_Onnx (ProductID, ProductDescription)
VALUES
    (1, N'Local ONNX embedding with SQL Server'),
    (2, N'Offline vectorization without a cloud endpoint');
GO

GRANT EXECUTE ON EXTERNAL MODEL::[LocalOnnxEmbedding]
    TO [lab_embedding_executor];
GO

UPDATE p
SET EmbeddingVector = AI_GENERATE_EMBEDDINGS(
    p.ProductDescription USE MODEL [LocalOnnxEmbedding]
)
FROM lab.ProductEmbeddings_Onnx AS p
WHERE p.EmbeddingVector IS NULL;
GO

SELECT ProductID,
       VECTORPROPERTY(EmbeddingVector, 'Dimensions') AS Dimensions,
       VECTORPROPERTY(EmbeddingVector, 'BaseType') AS BaseType
FROM lab.ProductEmbeddings_Onnx;
GO
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
    @credential = [https://my-openai-resource.openai.azure.com/];
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
