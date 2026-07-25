-- =================================================================================
-- DP-800 - PRACTICAL LAB: EMBEDDING MAINTENANCE AND REGENERATION (DIRTY TRACKING AND TRIGGERS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates preventive maintenance and embedding vector update patterns:
--   1. Dirty Tracking Pattern (`IsEmbeddingStale BIT`) to identify stale vectors
--   2. Synchronous Update via Table Triggers (`AFTER INSERT, UPDATE`)
--   3. Batch Processing (Batch Regeneration) for pending vectors
--   4. Full Regeneration Strategy (AI model swap from text-embedding-ada-002 to 3-small)
--   5. Practical Project Scenarios (Text Modification Tracking vs Vector Date)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.ProductVectorCatalog;
GO

-- Table structure with Embedding Maintenance Flags
CREATE TABLE lab.ProductVectorCatalog (
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL,
    DescriptionEmbedding NVARCHAR(MAX) NULL, -- Vector serialized as JSON
    IsEmbeddingStale BIT NOT NULL DEFAULT 1, -- Dirty Tracking flag
    LastUpdated DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    EmbeddingGeneratedAt DATETIME2 NULL
);
GO

INSERT INTO lab.ProductVectorCatalog (ProductID, ProductName, Description) VALUES
(101, N'Capacete Premium', N'Capacete aerodinamico com fibra de carbono e ventilacao extra.'),
(102, N'Luvas de Ciclismo', N'Luvas acolchoadas com gel e tecido respiravel.');
GO


-- =================================================================================
-- PART 1: DIRTY TRACKING PATTERN WITH TABLE TRIGGER
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DIRTY TRACKING: Sets `IsEmbeddingStale = 1` whenever the text field changes.
--     Decouples database writes from the OpenAI API HTTP call, enabling async regeneration.

-- -- [DP-800 WATCH POINT]
-- Trigger to mark the IsEmbeddingStale column as 1 if the description changes
CREATE OR ALTER TRIGGER lab.trg_ProductVectorCatalog_DirtyTracking
ON lab.ProductVectorCatalog
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    IF UPDATE(Description)
    BEGIN
        UPDATE p
        SET 
            IsEmbeddingStale = 1,
            LastUpdated = GETUTCDATE()
        FROM lab.ProductVectorCatalog p
        INNER JOIN inserted i ON p.ProductID = i.ProductID;
    END;
END;
GO

-- Simulate description change
UPDATE lab.ProductVectorCatalog
SET Description = N'Capacete aerodinamico com fibra de carbono, ventilacao extra e luz LED traseira.'
WHERE ProductID = 101;
GO

-- Verify if the row was marked as Stale (Dirty)
SELECT ProductID, ProductName, IsEmbeddingStale, LastUpdated 
FROM lab.ProductVectorCatalog;
GO


-- =================================================================================
-- PART 2: BATCH REGENERATION (BATCH REFRESH) AND MODEL SWAP
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - MODEL SWAP: Switching from `text-embedding-ada-002` to `text-embedding-3-small` REQUIRES regenerating 100% of vectors!
--     Vectors from different models do not belong to the same vector space and produce incorrect results.

-- -- [DP-800 WATCH POINT]
-- 1. Start full model swap procedure by marking all rows as Stale
UPDATE lab.ProductVectorCatalog
SET IsEmbeddingStale = 1;
GO

-- 2. Process batch of stale records (Simulating the batch job call)
UPDATE lab.ProductVectorCatalog
SET 
    DescriptionEmbedding = N'[-0.012, 0.045, 0.089, ...]', -- Simulated vector with 1536 dimensions
    IsEmbeddingStale = 0,
    EmbeddingGeneratedAt = GETUTCDATE()
WHERE IsEmbeddingStale = 1;
GO

-- Validate if all rows were successfully re-indexed
SELECT ProductID, IsEmbeddingStale, EmbeddingGeneratedAt 
FROM lab.ProductVectorCatalog;
GO


-- =================================================================================
-- PART 3: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Comparative Matrix of Embedding Maintenance Approaches
-- Architecture decision guide for the DP-800 Exam.

SELECT 
    'Triggers de Tabela (Sincrono)' AS Abordagem,
    'Alta (API chamada durante o UPDATE)' AS LatenciaEscrita,
    'Pequenas tabelas ou escritas infrequentes' AS CasoDeUsoRecomendado,
    'API indisponivel aborta a transacao de escrita' AS RiscoArquitetural
UNION ALL
SELECT 
    'Dirty Tracking + Batch Job (Assincrono)',
    'Zero (Nao afeta o UPDATE do usuario)',
    'Alta frequencia de escrita e tabelas grandes',
    'Vetor fica temporariamente desatualizado ate a roda do job'
UNION ALL
SELECT 
    'Azure Functions SQL Trigger Binding',
    'Quase em Tempo Real (Assincrono baseado em eventos)',
    'Arquiteturas Cloud Serverless nativas Azure',
    'Requer infraestrutura de Functions e Change Tracking ativo';
GO
