-- =================================================================================
-- DP-800 - PRACTICAL LAB: ISOLATION LEVELS AND CONCURRENCY (RCSI, SNAPSHOT, DEADLOCKS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) from:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates concurrency and isolation management in SQL Server:
--   1. Isolation Levels: READ COMMITTED vs READ_COMMITTED_SNAPSHOT (RCSI) and SNAPSHOT
--   2. Optimistic Concurrency with `ROWVERSION` Column (Conflict Detection without Locks)
--   3. Lock Escalation Configuration (`ALTER TABLE SET (LOCK_ESCALATION = AUTO)`)
--   4. Blocking and Deadlock Diagnostics (Error 1205) in Extended Events `system_health`
--   5. Practical Design Scenarios (Eliminating Reader/Writer Blocking in OLTP)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.InventoryStock;
GO

-- Test Table Structure
CREATE TABLE lab.InventoryStock (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    ItemName NVARCHAR(100) NOT NULL,
    Quantity INT NOT NULL,
    RowVer ROWVERSION NOT NULL -- Used for optimistic concurrency
);
GO

INSERT INTO lab.InventoryStock (ItemName, Quantity) VALUES 
(N'Monitor 27 Polegadas', 50),
(N'Cadeira Ergonomica', 20);
GO


-- =================================================================================
-- PART 1: ISOLATION LEVELS (RCSI VS SNAPSHOT)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - READ COMMITTED (Pessimistic Default): Readers block writers and writers block readers.
--   - READ_COMMITTED_SNAPSHOT (RCSI): Enabled at the database level. Readers use the TempDB Version Store without blocking writers.
--   - SNAPSHOT ISOLATION: Enabled at the database (`ALLOW_SNAPSHOT_ISOLATION ON`) and activated per transaction (`SET TRANSACTION ISOLATION LEVEL SNAPSHOT`).

-- 1. Enable RCSI on the database to eliminate read blocking in OLTP
ALTER DATABASE AdventureWorks2025 SET READ_COMMITTED_SNAPSHOT ON;
GO

-- -- [DP-800 KEY POINT]
-- 2. Enable Snapshot isolation permission in the application
ALTER DATABASE AdventureWorks2025 SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

-- 3. Execute a transaction under SNAPSHOT level (Guarantees a consistent view from transaction start)
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;

SELECT ItemID, ItemName, Quantity FROM lab.InventoryStock WHERE ItemID = 1;

COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED; -- Restore default level
GO


-- =================================================================================
-- PART 2: OPTIMISTIC CONCURRENCY WITH ROWVERSION (LOCK-FREE DETECTION)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - ROWVERSION (timestamp): Automatically incremented on each row UPDATE.
--   - PATTERN: Read the row and save `RowVer`. On UPDATE, validate `WHERE ItemID = @id AND RowVer = @originalVer`.
--   - IF @@ROWCOUNT = 0: Means another user modified the row in the middle of the process!

DECLARE @ItemID INT = 1;
DECLARE @CurrentQty INT;
DECLARE @OriginalRowVer BINARY(8);

-- 1. Read without keeping locks open
SELECT 
    @CurrentQty = Quantity,
    @OriginalRowVer = RowVer
FROM lab.InventoryStock
WHERE ItemID = @ItemID;

-- 2. Simulate change and apply optimistic UPDATE
-- -- [DP-800 KEY POINT]
UPDATE lab.InventoryStock
SET Quantity = @CurrentQty - 1
WHERE ItemID = @ItemID AND RowVer = @OriginalRowVer;

IF @@ROWCOUNT = 0
BEGIN
    PRINT 'CONFLITO DE CONCORRÊNCIA DETECTADO: O registro foi alterado por outro usuário!';
END
ELSE
BEGIN
    PRINT 'Atualização realizada com sucesso!';
END
GO


-- =================================================================================
-- PART 3: LOCK ESCALATION AND BLOCKING DIAGNOSTICS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - LOCK ESCALATION: When a query accumulates ~5,000 row/page locks, SQL Server tries to escalate to a full table lock.
--   - LOCK_ESCALATION = AUTO: For partitioned tables, escalates only to the partition level, avoiding locking the entire table.

-- Configure Lock Escalation to AUTO (Best option for partitioned tables)
ALTER TABLE lab.InventoryStock SET (LOCK_ESCALATION = AUTO);
GO

-- Query the table's Lock Escalation mode
SELECT name, lock_escalation_desc
FROM sys.tables
WHERE name = 'InventoryStock';
GO

-- Query active blocking locks on the instance via DMVs
SELECT 
    r.blocking_session_id AS SessaoBloqueadora,
    r.session_id AS SessaoBloqueada,
    r.wait_type AS TipoEspera,
    r.wait_time / 1000.0 AS TempoEsperaSegundos,
    t.text AS QueryTexto
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id > 0;
GO


-- =================================================================================
-- PART 4: PRACTICAL DESIGN SCENARIOS
-- =================================================================================

--- SCENARIO 1: Deadlock Extraction Query from Extended Events `system_health`
-- Used to investigate deadlock graphs (Error 1205) captured in the native ring buffer.

WITH DeadlockCTE AS (
    SELECT CAST(target_data AS XML) AS TargetData
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address
    WHERE s.name = 'system_health'
      AND t.target_name = 'ring_buffer'
)
SELECT 
    XEvent.value('@timestamp', 'DATETIME2') AS DataHoraDeadlock,
    XEvent.query('.') AS GrafoDeadlockXML
FROM DeadlockCTE
CROSS APPLY TargetData.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS DeadlockTable(XEvent);
GO
