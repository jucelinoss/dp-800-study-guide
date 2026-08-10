-- =================================================================================
-- DP-800 - PRACTICAL LAB: EVENT REPLICATION AND CAPTURE (CDC VS CHANGE TRACKING)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates the two data change capture strategies in SQL Server:
--   1. Change Data Capture (CDC): Enabling, Capture Tables, and querying Before/After images
--   2. Incremental Watermarking with Log Sequence Numbers (LSN)
--   3. Change Tracking (CT): Lightweight enabling and queries with `CHANGETABLE(CHANGES ...)`
--   4. Architecture Comparison: CDC vs CT vs Event Grid / Fabric Change Event Streaming
--   5. Practical Project Scenarios (Integration Queue for Azure Functions and Logic Apps)
-- NOTE: CDC and Change Tracking change database state. Run this in a disposable
-- database with the required permissions and read the cleanup section at the end.
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/08-azure-services-integration/04-change-event-handling.md
--    Open the theory guide alongside this lab for conceptual context.

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.InventoryCT;
DROP TABLE IF EXISTS lab.CDCWatermark;
GO

-- Table for Change Tracking (CT) Test
CREATE TABLE lab.InventoryCT (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    ItemName NVARCHAR(100) NOT NULL,
    Price DECIMAL(18,2) NOT NULL
);
GO

INSERT INTO lab.InventoryCT (ItemName, Price) VALUES 
(N'Teclado Mecanico', 250.00),
(N'Mouse Sem Fio', 120.00);
GO


-- =================================================================================
-- PART 1: CHANGE DATA CAPTURE (CDC) - BEFORE AND AFTER IMAGES WITH LSN
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CDC: Captures changes at row level including the old (Before) and new (After) values.
--   - OPERATIONS (__$operation): 1 = DELETE, 2 = INSERT, 3 = UPDATE (Before), 4 = UPDATE (After).
--   - LSN: Log Sequence Number used for incremental read control (Watermarking).

-- -- [DP-800 KEY POINT]
-- 1. Enable CDC at database level
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_cdc_enabled = 0)
    EXEC sys.sp_cdc_enable_db;
GO

-- 2. Enable CDC on a specific table
IF NOT EXISTS
(
    SELECT 1 FROM sys.tables
    WHERE object_id = OBJECT_ID(N'lab.InventoryCT')
      AND is_tracked_by_cdc = 1
)
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'lab',
        @source_name = N'InventoryCT',
        @role_name = NULL,
        @supports_net_changes = 1;
GO

-- 3. Set up Incremental Read Control Table (Watermarking)
CREATE TABLE lab.CDCWatermark (
    TableName NVARCHAR(100) PRIMARY KEY,
    LastProcessedLSN BINARY(10) NOT NULL,
    LastUpdated DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
GO


-- =================================================================================
-- PART 2: CHANGE TRACKING (CT) - LIGHTWEIGHT TRACKING WITHOUT PREVIOUS IMAGE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CHANGE TRACKING: Tracks only THAT a row changed and which operation (I, U, D).
--     Does not consume extra storage by recording old values. Default used by Azure Functions SQL Trigger.

-- -- [DP-800 KEY POINT]
-- 1. Enable Change Tracking at Database Level (2-day Retention with Auto Cleanup)
ALTER DATABASE AdventureWorks2025 
SET CHANGE_TRACKING = ON 
(CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON);
GO

-- 2. Enable Change Tracking on Table
IF NOT EXISTS
(
    SELECT 1 FROM sys.change_tracking_tables
    WHERE object_id = OBJECT_ID(N'lab.InventoryCT')
)
    ALTER TABLE lab.InventoryCT
    ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
GO

-- 3. Capture initial synchronization version
DECLARE @SyncVersion BIGINT = CHANGE_TRACKING_CURRENT_VERSION();
PRINT 'Versao Atual de Sincronizacao: ' + CAST(@SyncVersion AS VARCHAR);

-- Make changes to the table to generate tracked changes
UPDATE lab.InventoryCT SET Price = 280.00 WHERE ItemID = 1;
INSERT INTO lab.InventoryCT (ItemName, Price) VALUES (N'Headset USB', 190.00);

-- CDC is asynchronous: allow the capture job to process the log before querying.
WAITFOR DELAY '00:00:05';

-- 5. Read captured changes (the option below includes before and after images)
DECLARE @CdcFromLSN BINARY(10) = sys.fn_cdc_get_min_lsn(N'lab_InventoryCT');
DECLARE @CdcToLSN BINARY(10) = sys.fn_cdc_get_max_lsn();

SELECT *
FROM cdc.fn_cdc_get_all_changes_lab_InventoryCT(@CdcFromLSN, @CdcToLSN, N'all update old');

-- 4. Query changed rows from the synchronization point
SELECT 
    ct.ItemID,
    ct.SYS_CHANGE_OPERATION AS TipoOperacao, -- I = Insert, U = Update, D = Delete
    ct.SYS_CHANGE_VERSION AS VersaoAlteracao,
    inv.ItemName,
    inv.Price
FROM CHANGETABLE(CHANGES lab.InventoryCT, @SyncVersion) AS ct
LEFT JOIN lab.InventoryCT inv ON inv.ItemID = ct.ItemID;
GO


-- =================================================================================
-- PART 3: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Comparative Matrix CDC vs Change Tracking for DP-800 Exam
-- Architecture decision guide for integration and ETL.

SELECT 
    'Change Data Capture (CDC)' AS Tecnologia,
    'SIM (Imagens de Antes e Depois)' AS GravaValorAntigo,
    'Médio (Tabelas de captura dedicadas)' AS SobrecargaArmazenamento,
    'ETL para Data Warehouse, Auditoria Completa e Synapse/Fabric' AS CasoDeUsoIdeal
UNION ALL
SELECT 
    'Change Tracking (CT)',
    'NÃO (Apenas ID da Linha e Tipo de Operação)',
    'Baixo / Mínimo',
    'Sincronização com Clientes Mobile, Azure Functions Trigger Binding';
GO

-- =================================================================================================
-- OPTIONAL CLEANUP (run only in a disposable database):
-- ALTER TABLE lab.InventoryCT DISABLE CHANGE_TRACKING;
-- ALTER DATABASE AdventureWorks2025 SET CHANGE_TRACKING = OFF;
-- EXEC sys.sp_cdc_disable_table @source_schema = N'lab', @source_name = N'InventoryCT', @capture_instance = N'lab_InventoryCT';
-- EXEC sys.sp_cdc_disable_db;
-- DROP TABLE IF EXISTS lab.CDCWatermark;
-- DROP TABLE IF EXISTS lab.InventoryCT;
-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/08-azure-services-integration/04-change-event-handling.md
-- =================================================================================================
