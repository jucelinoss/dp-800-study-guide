-- =================================================================================
-- DP-800 - PRACTICAL LAB: QUERY PERFORMANCE DIAGNOSTICS AND TROUBLESHOOTING
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/06-performance-optimization/03-query-performance-troubleshooting.md
--    Open the theory guide alongside this lab for conceptual context.
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates T-SQL query analysis and optimization techniques:
--   1. Execution Plan Analysis with `SET STATISTICS IO, TIME ON` and `SET STATISTICS XML ON`
--   2. Identifying Costly Operators (Key Lookups and conversion to Covered Indexes)
--   3. Parameter Sniffing Resolution (`OPTION (RECOMPILE)` vs `OPTION (OPTIMIZE FOR UNKNOWN)`)
--   4. Using Plan Guides (`sp_create_plan_guide`) to inject hints into ORM/Third-Party code
--   5. Fragmentation Diagnosis and Index Maintenance (REORGANIZE vs REBUILD)
--   6. Practical Project Scenarios (Preventive Statistics Maintenance with `sys.dm_db_stats_properties`)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.plan_guides WHERE name = N'PG_FixParameterSniffing')
    EXEC sp_control_plan_guide N'DROP', N'PG_FixParameterSniffing';

IF EXISTS (SELECT * FROM sys.indexes WHERE name = N'IX_PerfTest_Covered' AND object_id = OBJECT_ID('lab.PerfTestOrders'))
    DROP INDEX IX_PerfTest_Covered ON lab.PerfTestOrders;

DROP TABLE IF EXISTS lab.PerfTestOrders;
GO

-- Table structure for optimization testing
CREATE TABLE lab.PerfTestOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL,
    OrderStatus NVARCHAR(20) NOT NULL
);
GO

-- Populate simulated data
INSERT INTO lab.PerfTestOrders (CustomerID, OrderDate, TotalAmount, OrderStatus) VALUES 
(1001, '2025-01-01', 500.00, 'Completed'),
(1001, '2025-01-02', 1200.00, 'Completed'),
(1002, '2025-01-03', 300.00, 'Pending'),
(1003, '2025-01-04', 1500.00, 'Completed');
GO

CREATE INDEX IX_PerfTestOrders_Customer ON lab.PerfTestOrders(CustomerID);
GO


-- =================================================================================
-- PART 1: KEY LOOKUP AND CREATING A COVERED INDEX
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - KEY LOOKUP: Occurs when the non-clustered index contains the filter columns (`WHERE`), but does NOT contain
--     the columns in the SELECT list. SQL Server needs to fetch remaining columns from the main table (clustered index).
--   - SOLUTION: Create a Covered Index by adding the returned columns in the `INCLUDE` clause.

-- -- [DP-800 EXAM SPOTLIGHT]
-- 1. Enable I/O and time statistics for diagnostics
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- Query that triggers a Key Lookup (Filters by CustomerID but needs TotalAmount and OrderStatus)
SELECT CustomerID, TotalAmount, OrderStatus 
FROM lab.PerfTestOrders 
WHERE CustomerID = 1001;
GO

-- 2. Eliminate the Key Lookup by creating a Covered Index with INCLUDE
CREATE NONCLUSTERED INDEX IX_PerfTest_Covered 
ON lab.PerfTestOrders(CustomerID)
INCLUDE (TotalAmount, OrderStatus);
GO

-- Re-execute the query (Now runs as a direct Index Seek on the covered index)
SELECT CustomerID, TotalAmount, OrderStatus 
FROM lab.PerfTestOrders 
WHERE CustomerID = 1001;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO


-- =================================================================================
-- PART 2: PARAMETER SNIFFING MITIGATION (RECOMPILE VS OPTIMIZE FOR UNKNOWN)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - OPTION (RECOMPILE): Forces recompilation on every execution. Ideal for infrequent batch reports.
--   - OPTION (OPTIMIZE FOR UNKNOWN): Compiles with generic average statistics without recompiling every time.

-- -- [DP-800 EXAM SPOTLIGHT]
-- Example of a procedure protected against Parameter Sniffing
CREATE OR ALTER PROCEDURE lab.usp_GetOrdersByCustomer
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Ideal option for high-frequency OLTP: compilation with average statistics
    SELECT OrderID, CustomerID, TotalAmount
    FROM lab.PerfTestOrders
    WHERE CustomerID = @CustomerID
    OPTION (OPTIMIZE FOR (@CustomerID UNKNOWN));
END;
GO


-- =================================================================================
-- PART 3: PLAN GUIDES FOR UNMODIFIABLE THIRD-PARTY / ORM CODE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - PLAN GUIDE: Associates an optimization hint (`hints`) with a SQL statement whose source code CANNOT be modified.
--   - REQUIREMENT: The T-SQL statement text in the Plan Guide must match EXACTLY the text sent by the application.

-- 1. Create a Plan Guide to inject the OPTIMIZE FOR UNKNOWN hint into an ORM statement
EXEC sp_create_plan_guide
    @name = N'PG_FixParameterSniffing',
    @stmt = N'SELECT OrderID, CustomerID, TotalAmount FROM lab.PerfTestOrders WHERE CustomerID = @CustIDParam',
    @type = N'SQL',
    @module_or_batch = NULL,
    @params = N'@CustIDParam INT',
    @hints = N'OPTION (OPTIMIZE FOR (@CustIDParam UNKNOWN))';
GO

-- 2. Query the active Plan Guides catalog
SELECT name, scope_type_desc, is_disabled
FROM sys.plan_guides
WHERE name = N'PG_FixParameterSniffing';
GO


-- =================================================================================
-- PART 4: STATISTICS MAINTENANCE AND INDEX FRAGMENTATION ANALYSIS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - sys.dm_db_stats_properties: Displays the number of modifications (`modification_counter`) since last update.
--   - REORGANIZE: Recommended for fragmentation between 5% and 30% (lightweight online operation).
--   - REBUILD: Recommended for fragmentation > 30% (rebuilds physical structure and updates statistics with FULLSCAN).

-- -- [DP-800 EXAM SPOTLIGHT]
-- 1. Check statistics update status and accumulated modification count
SELECT 
    OBJECT_NAME(s.object_id) AS NomeTabela,
    s.name AS NomeEstatistica,
    sp.last_updated AS UltimaAtualizacao,
    sp.rows AS TotalLinhas,
    sp.rows_sampled AS LinhasAmostradas,
    sp.modification_counter AS ContadorModificacoes
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID('lab.PerfTestOrders');
GO

-- 2. Update table statistics with full sampling (FULLSCAN)
UPDATE STATISTICS lab.PerfTestOrders WITH FULLSCAN;
GO


-- =================================================================================
-- PART 5: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Diagnostic Query for Most Expensive Queries via DMVs
-- Identifies the top 5 queries with the highest accumulated CPU time in the instance.

SELECT TOP 5
    qs.total_worker_time / qs.execution_count / 1000.0 AS TempoCpuMedioMS,
    qs.total_elapsed_time / qs.execution_count / 1000.0 AS DuracaoMediaMS,
    qs.execution_count AS TotalExecucoes,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
         ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS InstrucaoSQL
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY TempoCpuMedioMS DESC;
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/06-performance-optimization/03-query-performance-troubleshooting.md
-- =================================================================================================