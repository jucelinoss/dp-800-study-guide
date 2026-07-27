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
--   2. Change Tracking, CDC, and event-driven integration options
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
    DescriptionEmbedding VECTOR(1536) NULL,
    IsEmbeddingStale BIT NOT NULL DEFAULT 1, -- Dirty Tracking flag
    LastUpdated DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    EmbeddingGeneratedAt DATETIME2 NULL
);
GO

INSERT INTO lab.ProductVectorCatalog (ProductID, ProductName, Description) VALUES
(101, N'Premium Helmet', N'Aerodynamic helmet with carbon fiber and extra ventilation.'),
(102, N'Cycling Gloves', N'Padded gloves with gel and breathable fabric.');
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
SET Description = N'Aerodynamic carbon-fiber helmet with extra ventilation and rear LED light.'
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

-- 2. Process a batch of stale records. The actual embedding call is shown below;
-- this executable step only updates the maintenance state.
UPDATE lab.ProductVectorCatalog
SET 
    IsEmbeddingStale = 0,
    EmbeddingGeneratedAt = GETUTCDATE()
WHERE IsEmbeddingStale = 1;
GO

-- With a configured external embedding model, use this batch update instead.
/*
UPDATE p
SET DescriptionEmbedding = AI_GENERATE_EMBEDDINGS(
        p.Description USE MODEL [AzureOpenAI_Embedding_Small]
    ),
    IsEmbeddingStale = 0,
    EmbeddingGeneratedAt = SYSUTCDATETIME()
FROM lab.ProductVectorCatalog AS p
WHERE p.IsEmbeddingStale = 1;
*/

-- Validate if all rows were successfully re-indexed
SELECT ProductID, IsEmbeddingStale, EmbeddingGeneratedAt 
FROM lab.ProductVectorCatalog;
GO


-- =================================================================================
-- PART 3: CHANGE TRACKING AND CDC
-- =================================================================================

-- Change Tracking is a lightweight option for finding changed keys. Azure Functions
-- SQL Trigger uses it while polling; it does not receive a push notification.
/*
ALTER DATABASE AdventureWorks2025
SET CHANGE_TRACKING = ON
    (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON);
GO
ALTER TABLE lab.ProductVectorCatalog
ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
GO

DECLARE @LastVersion BIGINT = 0;
SELECT p.ProductID, p.Description, ct.SYS_CHANGE_VERSION, ct.SYS_CHANGE_OPERATION
FROM CHANGETABLE(CHANGES lab.ProductVectorCatalog, @LastVersion) AS ct
JOIN lab.ProductVectorCatalog AS p ON p.ProductID = ct.ProductID;
*/

-- CDC captures row-level change data. Enable it only when its richer history is needed.
/*
EXEC sys.sp_cdc_enable_db;
EXEC sys.sp_cdc_enable_table
    @source_schema = N'lab',
    @source_name = N'ProductVectorCatalog',
    @role_name = NULL;

SELECT *
FROM cdc.fn_cdc_get_all_changes_lab_ProductVectorCatalog
    (sys.fn_cdc_get_min_lsn(N'lab_ProductVectorCatalog'), sys.fn_cdc_get_max_lsn(), N'all');
*/
GO

-- =================================================================================
-- PART 4: OUTBOX FOR ASYNCHRONOUS PROCESSING
-- =================================================================================

DROP TABLE IF EXISTS lab.EmbeddingOutbox;
GO

CREATE TABLE lab.EmbeddingOutbox (
    EventID BIGINT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    Payload NVARCHAR(MAX) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    ProcessedAt DATETIME2 NULL
);
GO

CREATE OR ALTER TRIGGER lab.trg_ProductVectorCatalog_Outbox
ON lab.ProductVectorCatalog
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- UPDATE(Description) is also true for INSERT, so this covers both operations
    -- without emitting events for maintenance-only updates.
    IF UPDATE(Description)
    BEGIN
        INSERT INTO lab.EmbeddingOutbox (ProductID, Payload)
        SELECT i.ProductID,
               CONCAT(N'{"productId":', i.ProductID, N',"description":"',
                      STRING_ESCAPE(i.Description, 'json'), N'"}')
        FROM inserted AS i;
    END;
END;
GO

UPDATE lab.ProductVectorCatalog
SET Description = N'Aerodynamic carbon-fiber helmet with extra ventilation and rear LED light.'
WHERE ProductID = 101;
GO

SELECT EventID, ProductID, Payload, CreatedAt, ProcessedAt
FROM lab.EmbeddingOutbox
ORDER BY EventID;
GO

-- A worker can call Azure OpenAI, persist the returned vector, and then acknowledge the event.
UPDATE lab.EmbeddingOutbox
SET ProcessedAt = SYSUTCDATETIME()
WHERE ProcessedAt IS NULL;
GO

-- Azure Functions can poll Change Tracking; Change Event Streams can forward database
-- changes to Event Hubs/Eventstream. Logic Apps and Foundry workflows can be consumers.

-- =================================================================================
-- PART 5: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Comparative Matrix of Embedding Maintenance Approaches
-- Architecture decision guide for the DP-800 Exam.

SELECT 
    'Synchronous table triggers' AS Approach,
    'High (the API is called during UPDATE)' AS WriteLatency,
    'Small tables or infrequent writes' AS RecommendedUseCase,
    'An unavailable API can abort the write transaction' AS ArchitectureRisk
UNION ALL
SELECT 
    'Dirty tracking + batch job (asynchronous)',
    'None (does not affect the user UPDATE)',
    'High write frequency and large tables',
    'The vector remains temporarily stale until the job runs'
UNION ALL
SELECT 
    'Azure Functions SQL Trigger binding',
    'Near real time (Change Tracking-based polling)',
    'Azure-native serverless cloud architectures',
    'Requires Functions infrastructure and Change Tracking';
GO

SELECT
    'CDC' AS Approach,
    'Scheduled or continuous consumer' AS WriteLatency,
    'Consumers that need detailed row-change history' AS RecommendedUseCase,
    'Additional operational overhead and retention management' AS ArchitectureRisk
UNION ALL
SELECT
    'Change Event Streams',
    'Asynchronous stream delivery',
    'Event-driven integration through Event Hubs or Eventstream',
    'Requires event-stream infrastructure and a consumer';
GO
