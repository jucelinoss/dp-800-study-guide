-- =================================================================================
-- DP-800 - HANDS-ON LAB: CTEs (RECURSIVE, MATERIALIZATION) AND WINDOW FUNCTIONS
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/03-advanced-tsql/01-ctes-window-functions.md
--    Open the theory guide alongside this lab for conceptual context.
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to restore the
-- AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/sql/samples/adventureworks-install-configure
-- =================================================================================
-- This script demonstrates advanced use of CTEs and Window Functions in SQL Server:
--   Part 1    -> Recursive CTEs + MAXRECURSION (overflow, TRY/CATCH)
--   Part 1.5  -> Multiple CTEs (WITH A, B, C ... comma-separated)
--   Part 1.6  -> CTE Non-Materialization vs #temp (NEWID() proof)
--   Part 2    -> Ranking Functions: ROW_NUMBER / RANK / DENSE_RANK / NTILE
--   Part 3    -> Window Framing: ROWS vs RANGE (Running Total with date ties)
--   Part 4    -> Offset Functions: LAG, LEAD, FIRST_VALUE and LAST_VALUE pitfall
--   Extra 4.1 -> RANGE vs ROWS on LAST_VALUE (tied Amount values)
--   Part 4.2  -> lab.sp_render_tree: generic hierarchy renderer
--   Scenarios -> Dedup, Percentiles, HIERARCHYID, Gap Detection, Top-N per Group
-- =================================================================================

USE AdventureWorks2025;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'lab')
    EXEC(N'CREATE SCHEMA lab AUTHORIZATION dbo;');
GO

-- Preventive cleanup
DROP PROCEDURE IF EXISTS lab.sp_render_tree;
DROP TABLE IF EXISTS lab.OrgChartHierarchyid;
DROP TABLE IF EXISTS lab.OrgChart;
DROP TABLE IF EXISTS lab.SalesData;
DROP TABLE IF EXISTS lab.CustomerEvents;
GO

-- Table structures for testing
CREATE TABLE lab.OrgChart (
    EmployeeID INT PRIMARY KEY,
    EmployeeName NVARCHAR(100) NOT NULL,
    ManagerID INT NULL
);

CREATE TABLE lab.SalesData (
    SaleID INT IDENTITY(1,1) PRIMARY KEY,
    SalesPersonID INT NOT NULL,
    SaleDate DATE NOT NULL,
    Amount DECIMAL(18,2) NOT NULL
);

CREATE TABLE lab.CustomerEvents (
    EventID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    EventName NVARCHAR(50) NOT NULL,
    EventDate DATETIME2 NOT NULL
);
GO


-- =================================================================================
-- PART 1: RECURSIVE CTEs AND RECURSION CONTROL (MAXRECURSION)
-- =================================================================================
-- KEY CONCEPTS:
--   - RECURSIVE CTE: Anchor Member + UNION ALL + Recursive Member referencing the CTE
--     until the termination condition is met.
--   - MAXRECURSION: Default limit is 100 levels to prevent infinite loops.
--     Use OPTION (MAXRECURSION n) to override (0 = no limit, use with caution).

-- 1. Populate organizational hierarchy data
INSERT INTO lab.OrgChart VALUES 
(1, 'CEO / Presidente', NULL),
(2, 'VP de Vendas', 1),
(3, 'Gerente de Vendas Regiao A', 2),
(4, 'Vendedor Senior 1', 3),
(5, 'Vendedor Junior 2', 3);
GO

-- 2. Recursive CTE query to map hierarchy levels
WITH EmployeeHierarchy AS (
    -- Anchor Member: top of the pyramid (no manager)
    SELECT EmployeeID, EmployeeName, ManagerID, 0 AS Level
    FROM lab.OrgChart
    WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive Member: subordinate employees
    SELECT e.EmployeeID, e.EmployeeName, e.ManagerID, h.Level + 1
    FROM lab.OrgChart e
    JOIN EmployeeHierarchy h ON e.ManagerID = h.EmployeeID
)
SELECT EmployeeID, EmployeeName, Level, REPLICATE('--- ', Level) + EmployeeName AS HierarchyTree
FROM EmployeeHierarchy
ORDER BY Level, EmployeeName;
GO

-- [DP-800 EXAM TIP] Recursion Overflow Test (MAXRECURSION Exceeded):
-- Generates a long sequence to force SQL Server error 530.
BEGIN TRY
    ;WITH InfiniteSeq AS (
        SELECT 1 AS N
        UNION ALL
        SELECT N + 1 FROM InfiniteSeq WHERE N < 200
    )
    SELECT * FROM InfiniteSeq; -- Fails because 200 > 100 (default limit)
END TRY
BEGIN CATCH
    PRINT 'EXPECTED MAXRECURSION ERROR: ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PART 1.5: MULTIPLE CTEs (COMMA-SEPARATED DEFINITIONS)
-- =================================================================================
-- KEY CONCEPTS:
--   - Multiple CTEs can be defined in a single WITH statement separated by commas.
--   - A later CTE can REFERENCE an earlier CTE (no forward references).
--   - Clean syntax for breaking logic into named stages instead of nested subqueries.
--
-- [DP-800 EXAM TIP] Classic question: "How many times is a CTE name evaluated
--   if referenced N times in the query?" ANSWER: N times.
--   A CTE is a MACRO expanded in the execution plan, NOT a materialized temp table.

WITH
    -- CTE 1: Gross sales per salesperson
    SalesPerSalesperson AS (
        SELECT SalesPersonID, SUM(Amount) AS TotalSales
        FROM lab.SalesData
        GROUP BY SalesPersonID
    ),
    -- CTE 2: Global metrics (references previous CTE via total aggregation)
    GlobalMetrics AS (
        SELECT
            SUM(TotalSales) AS GrandTotal,
            AVG(TotalSales * 1.0) AS AvgPerSalesperson
        FROM SalesPerSalesperson
    )
-- Main query combines both CTEs without additional JOIN
SELECT
    s.SalesPersonID,
    s.TotalSales,
    g.GrandTotal,
    g.AvgPerSalesperson,
    -- Each salesperson's share of total
    CAST(s.TotalSales * 100.0 / NULLIF(g.GrandTotal, 0) AS DECIMAL(6,2)) AS PctOfTotal
FROM SalesPerSalesperson s
CROSS JOIN GlobalMetrics g
ORDER BY s.TotalSales DESC;
GO


-- =================================================================================
-- PART 1.6: CTE NON-MATERIALIZATION vs #temp (PRACTICAL PROOF)
-- =================================================================================
-- KEY CONCEPT:
--   - CTE: Result is NOT persisted. If a CTE appears 2x in the final query,
--     its logic is EXECUTED 2x (risk of inconsistency with non-deterministic data).
--   - #temp (local temp table): Materializes rows in tempdb. Reads 1x, uses Nx.
--
-- Demonstration: NEWID() is non-deterministic. If the CTE were materialized,
-- the same GUID would appear in both columns.

-- ===== (A) CTE referenced TWICE -> NEWID() differs in each column =====
WITH CteWithGuid AS (
    SELECT SalesPersonID, NEWID() AS NonDeterministicGuid
    FROM lab.SalesData
    WHERE SalesPersonID = 101
)
SELECT
    a.SalesPersonID,
    a.NonDeterministicGuid AS GuidFromFirstRef,
    b.NonDeterministicGuid AS GuidFromSecondRef,
    SameGuid = CASE WHEN a.NonDeterministicGuid = b.NonDeterministicGuid
                    THEN 'YES (materialized)' ELSE 'NO (executed 2x)' END
FROM CteWithGuid a
INNER JOIN CteWithGuid b ON a.SalesPersonID = b.SalesPersonID;
-- Expected: SameGuid = "NO" -- proves the CTE ran twice!
GO

-- ===== (B) #TEMP referenced TWICE -> NEWID() same in both columns =====
DROP TABLE IF EXISTS #TempWithGuid;
CREATE TABLE #TempWithGuid (SalesPersonID INT, NonDeterministicGuid UNIQUEIDENTIFIER);
INSERT INTO #TempWithGuid (SalesPersonID, NonDeterministicGuid)
SELECT SalesPersonID, NEWID()
FROM lab.SalesData
WHERE SalesPersonID = 101;

SELECT
    a.SalesPersonID,
    a.NonDeterministicGuid AS GuidFromFirstRef,
    b.NonDeterministicGuid AS GuidFromSecondRef,
    SameGuid = CASE WHEN a.NonDeterministicGuid = b.NonDeterministicGuid
                    THEN 'YES (materialized)' ELSE 'NO (executed 2x)' END
FROM #TempWithGuid a
INNER JOIN #TempWithGuid b ON a.SalesPersonID = b.SalesPersonID;
-- Expected: SameGuid = "YES" -- #temp is computed ONCE and reused.
DROP TABLE IF EXISTS #TempWithGuid;
GO


-- =================================================================================
-- PART 2: RANKING FUNCTIONS (ROW_NUMBER, RANK, DENSE_RANK, NTILE)
-- =================================================================================
-- KEY CONCEPTS:
--   - ROW_NUMBER(): Strict unique sequential number (no ties, arbitrary tiebreaker).
--   - RANK(): Ranking with ties. Leaves GAPS in subsequent ranks (e.g., 1, 1, 3).
--   - DENSE_RANK(): Ranking with ties. NO GAPS in subsequent ranks (e.g., 1, 1, 2).
--   - NTILE(n): Divides result set into n buckets (quartiles, deciles, etc.).

-- Data for all remaining sections
INSERT INTO lab.SalesData (SalesPersonID, SaleDate, Amount) VALUES 
-- Salesperson 101: 3 sales (multiple rows per partition for framing demo)
(101, '2025-01-05', 500.00),
(101, '2025-01-10', 800.00),
(101, '2025-01-15', 1200.00),
-- Salesperson 102: 2 sales (intentional value tie for Ranking demo)
(102, '2025-01-03', 500.00),
(102, '2025-01-08', 500.00),
-- Salesperson 103: 3 sales, TWO ON THE SAME DAY (2025-01-12) -> tie in SaleDate
-- Essential to demonstrate RANGE (logical block) vs ROWS (physical) difference
(103, '2025-01-02', 300.00),
(103, '2025-01-12', 250.00),
(103, '2025-01-12', 200.00),
-- Salesperson 104: 2 sales
(104, '2025-01-01', 200.00),
(104, '2025-01-20', 950.00);
GO

-- =================================================================================
-- THEORY: HOW PARTITION BY WORKS INSIDE OVER()
-- =================================================================================
-- The OVER() clause has 3 components executed in order:
--    1. PARTITION BY  -> divides the dataset into separate groups
--    2. ORDER BY      -> orders each group (required for framing and offset)
--    3. ROWS/RANGE    -> defines a sliding window within the ordered group
--
-- Key rule:
--    OVER() with NO parameters = single partition = entire result set
--    OVER(PARTITION BY col)   = N independent partitions, one per value
--
-- Example with LAG() on a subset of lab.SalesData:
--
--   Row | Salesperson | Amount
--   ----|-------------|--------
--   L1  | 101         | 500
--   L2  | 101         | 800
--   L3  | 101         | 1200
--   L4  | 102         | 500
--   L5  | 102         | 500
--
--   CASE A - WITHOUT PARTITION BY: OVER(ORDER BY Salesperson, SaleID)
--     Everything is one partition. LAG crosses salesperson boundaries.
--     L1 -> NULL, L2 -> 500, L3 -> 800, L4 -> 1200 (from L3 - DIFFERENT salesperson!)
--     L5 -> 500 (from L4)
--
--   CASE B - WITH PARTITION BY: OVER(PARTITION BY SalesPersonID ...)
--     Two independent partitions: {L1,L2,L3} and {L4,L5}.
--     Each resets counting from zero.
--     Partition 101: L1 -> NULL, L2 -> 500, L3 -> 800
--     Partition 102: L4 -> NULL (AGAIN!), L5 -> 500
--
-- IN THE SECTIONS BELOW, queries come in two variants:
--   LAB A -> same dataset WITHOUT PARTITION BY (global)
--   LAB B -> same dataset WITH PARTITION BY SalesPersonID (per salesperson)
-- Compare columns side by side to see the difference in practice.
-- =================================================================================


-- =================================================================================
-- LAB A vs LAB B - RANKING FUNCTIONS (Part 2)
-- =================================================================================
-- LAB A - WITHOUT PARTITION BY: Global ranking (all 10 sales compete together)
-- LAB B - WITH PARTITION BY SalesPersonID: Ranking WITHIN EACH SALESPERSON
--         (each salesperson starts with rank 1 for their own highest sale)
SELECT
    SaleID,
    SalesPersonID,
    Amount,

    -- LAB A - Global Ranking (entire dataset = 1 partition)
    ROW_NUMBER() OVER (ORDER BY Amount DESC)          AS A_RN_Global,
    RANK()       OVER (ORDER BY Amount DESC)          AS A_RK_Global,  -- note 1,1,3
    DENSE_RANK() OVER (ORDER BY Amount DESC)          AS A_DR_Global,  -- note 1,1,2
    NTILE(2)     OVER (ORDER BY Amount DESC)          AS A_NTile2_Global,

    -- LAB B - Ranking PER SALESPERSON (each = independent partition)
    ROW_NUMBER() OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS B_RN_PerSales,
    RANK()       OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS B_RK_PerSales,
    DENSE_RANK() OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS B_DR_PerSales,
    NTILE(2)     OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS B_NTile2_PerSales

FROM lab.SalesData
ORDER BY SalesPersonID, Amount DESC, SaleID;
-- Observations:
--   - Salesperson 101 ($500, 800, 1200): In LAB A appears as 5,3,1 (global)
--     but in LAB B they are 3,2,1 (only competing with themselves)
--   - Salesperson 102 has Amount TIED at $500 (2 rows). In LAB B, DENSE_RANK
--     returns 1,1 without gap, RANK returns 1,1 without gap (only 2 rows,
--     no other values to create a gap).
GO


-- =================================================================================
-- LAB A vs LAB B - WINDOW FRAMING & RUNNING TOTAL (Part 3)
-- =================================================================================
-- KEY CONCEPTS:
--   - RANGE (Default when ORDER BY used without explicit frame):
--     Logical framing. Treats ALL rows with identical ORDER BY values as
--     a single block - "CURRENT ROW" in RANGE = all rows with same value.
--   - ROWS: Strict physical framing. Evaluates row by row,
--     no grouping by value.
--   - Full DEFAULT frame (MS Learn):
--     RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--
-- [DP-800 EXAM TIP] For RUNNING TOTAL:
--   - Use ROWS UNBOUNDED PRECEDING for performance (spool optimization)
--     and predictability.
--   - RANGE can give DIFFERENT results with tied ORDER BY values
--     and is SLOWER on large volumes.

SELECT
    SaleID,
    SalesPersonID,
    SaleDate,
    Amount,

    -- LAB A - WITHOUT PARTITION BY (GLOBAL: entire dataset = 1 partition)
    -- Running total starts on earliest date and sums ALL salespeople
    SUM(Amount) OVER (ORDER BY SaleDate, SaleID ROWS UNBOUNDED PRECEDING)
        AS A_RT_Global_ROWS,
    SUM(Amount) OVER (ORDER BY SaleDate, SaleID RANGE UNBOUNDED PRECEDING)
        AS A_RT_Global_RANGE,  -- watch logical block on 12/jan (salesperson 103)

    -- Global moving average (last 2 rows)
    AVG(Amount) OVER (ORDER BY SaleDate, SaleID ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)
        AS A_MA2_Global,

    -- LAB B - WITH PARTITION BY SalesPersonID (PER SALESPERSON)
    -- Running total RESETS for each new salesperson
    -- (B1) Running Total with ROWS (physical): row by row
    -- Salesperson 103: 300 -> 550 -> 750 (step by step)
    SUM(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate, SaleID
        ROWS UNBOUNDED PRECEDING
    ) AS B_RT_PerSales_ROWS_Physical,

    -- (B2) Running Total with RANGE (logical): treats 12/jan as single block
    -- Salesperson 103: 300 -> 750 -> 750 (both 12/jan rows get the total at once)
    SUM(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate
        RANGE UNBOUNDED PRECEDING
    ) AS B_RT_PerSales_RANGE_Logical,

    -- (B3) Running Total with IMPLICIT DEFAULT frame (no ROWS/RANGE written)
    -- IDENTICAL result to (B2) RANGE - proves SQL Server default
    SUM(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate
    ) AS B_RT_PerSales_DefaultImplicit,

    -- Moving average per salesperson (last 2 rows of same salesperson)
    AVG(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate, SaleID
        ROWS BETWEEN 1 PRECEDING AND CURRENT ROW
    ) AS B_MA2_PerSales

FROM lab.SalesData
ORDER BY SaleDate, SaleID;
-- Crucial observations:
--   - Compare salesperson 103's line on 12/jan (SaleID 6 and 7):
--     A_RT_Global_RANGE jumped 2 at once (RANGE block of entire 12/jan)
--     B_RT_PerSales_RANGE = 750 in BOTH lines 6 and 7 (block per salesperson)
--   - On salesperson 102's first line (SaleID 4): A_MA2_Global averages with
--     salesperson 104 (previous row in ordered dataset), while B_MA2_PerSales
--     brings ONLY the value of line 102 (first of partition, no prior row).
GO


-- =================================================================================
-- LAB A vs LAB B - OFFSET FUNCTIONS + THE LAST_VALUE PITFALL (Part 4)
-- =================================================================================
-- KEY CONCEPTS (aligned with MS Learn DP-800):
--   - LAG / LEAD: Access previous/subsequent rows without self-join.
--     IMPORTANT: LAG and LEAD do NOT use ROWS/RANGE framing. Offset is
--     controlled ONLY by the offset parameter. No "pitfall" like LAST_VALUE.
--
--   - FIRST_VALUE / LAST_VALUE: Return first/last value of the FRAME,
--     NOT the entire partition by default. Default frame (MS Learn):
--     RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--
--   - LAST_VALUE PITFALL (common exam question):
--     Without ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING,
--     LAST_VALUE sees only up to current row -> returns CURRENT ROW VALUE.
--     FIRST_VALUE doesn't show this problem because the default frame
--     start is already the partition's first row.

-- [DP-800 EXAM TIP] FULL DEMONSTRATION - SAME DUAL SELECT
SELECT 
    SaleID,
    SalesPersonID,
    SaleDate,
    Amount,

    -- LAB A - WITHOUT PARTITION BY (ENTIRE TABLE AS SINGLE PARTITION)
    LAG(Amount, 1, 0)  OVER (ORDER BY SaleDate, SaleID)        AS A_LAG_Global,
    LEAD(Amount, 1, 0) OVER (ORDER BY SaleDate, SaleID)        AS A_LEAD_Global,

    FIRST_VALUE(Amount) OVER (ORDER BY SaleDate, SaleID)       AS A_FirstV_Global,
    -- Pitfall: without explicit frame, returns current row
    LAST_VALUE(Amount)  OVER (ORDER BY SaleDate, SaleID)       AS A_LV_Global_Default,
    LAST_VALUE(Amount)  OVER (
        ORDER BY SaleDate, SaleID
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                                                          AS A_LV_Global_Correct,

    -- LAB B - WITH PARTITION BY SalesPersonID (PER SALESPERSON)
    LAG(Amount, 1, 0)  OVER (PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID) AS B_LAG_PerSales,
    LEAD(Amount, 1, 0) OVER (PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID) AS B_LEAD_PerSales,

    FIRST_VALUE(Amount) OVER (PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID)
                                                                                  AS B_FirstV_PerSales,
    -- Pitfall: without frame, returns current row not last of salesperson
    LAST_VALUE(Amount) OVER (
        PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID
    )                                                          AS B_LV_PerSales_Default,
    LAST_VALUE(Amount) OVER (
        PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                                                          AS B_LV_PerSales_Correct

FROM lab.SalesData
ORDER BY SaleDate, SaleID;
GO
-- Observations:
--   - A_LAG_Global: 1st row = 0 (default), 2nd row gets value from 1st TABLE ROW
--     (salesperson 104, not same!). B_LAG_PerSales re-zeros at each new salesperson.
--   - A_LV_Global_Correct: all rows display 950 (last sale of entire table).
--   - B_LV_PerSales_Correct: salesperson 101 -> always 1200,
--     salesperson 103 -> always 750 (their group's total).
--   - In BOTH "_Default" columns LAST_VALUE returns its own row Amount.
--     The pitfall is independent of PARTITION BY - depends only on frame.


-- =================================================================================
-- EXTRA DIDACTIC 4.1 - RANGE vs ROWS on LAST_VALUE (per salesperson)
-- Leveraging SalesPersonID=102 with Amount TIED at 500.00
-- MS Learn: RANGE treats all "tied" ORDER BY values as a single logical block.
-- In ROWS, each physical row is counted individually.
-- =================================================================================
SELECT
    SaleID,
    SalesPersonID,
    SaleDate,
    Amount,

    -- LAST_VALUE with RANGE: tied Amount values are treated as one block,
    -- so both rows get the last value of the block (the highest tied value)
    LAST_VALUE(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY Amount
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS LV_Range_LogicalTies,

    -- LAST_VALUE with ROWS: each row is separate, returns its own value
    LAST_VALUE(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY Amount
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS LV_Rows_PhysicalRowByRow

FROM lab.SalesData
WHERE SalesPersonID IN (101, 102)  -- 101 has unique values, 102 has ties
ORDER BY SalesPersonID, Amount, SaleID;
GO


-- =================================================================================
-- PART 4.2: GENERIC HIERARCHY RENDERER (sp_render_tree)
-- =================================================================================
-- Creates a reusable procedure that accepts TABLE NAME + PARENT/CHILD COLUMNS
-- and returns a single column with the rendered tree for documentation.
--
-- Usage:
--   EXEC lab.sp_render_tree
--        @table_name = 'lab.OrgChart',
--        @col_dad    = 'ManagerID',
--        @col_son    = 'EmployeeID',
--        @col_label  = 'EmployeeName',    -- optional
--        @tree_style = 'md';              -- 'md' (markdown) | 'asc' (ASCII)
--
-- Security (aligned with MS Learn Dynamic SQL):
--   - OBJECT_ID() validates the table before building dynamic SQL
--   - sys.columns validates all column names
--   - QUOTENAME() on all identifiers (injection impossible)
--   - sp_executesql with typed parameters
--
-- Features:
--   - Cycle detection: breadcrumb path of visited IDs; stops recursion and flags
--   - ASCII rendering: uses box-drawing characters (|, |--, +--) with
--     accurate "last sibling" detection
--   - @root_id optional: render only a sub-tree
-- =================================================================================

CREATE OR ALTER PROCEDURE lab.sp_render_tree
    @table_name SYSNAME,           -- table (1 or 2 parts: 'OrgChart' or 'lab.OrgChart')
    @col_dad    SYSNAME,           -- self-reference FK column (e.g., ManagerID -> NULL = root)
    @col_son    SYSNAME,           -- PK/id column of node (e.g., EmployeeID)
    @col_label  SYSNAME   = NULL,  -- display column. If NULL, uses @col_son
    @root_id    NVARCHAR(MAX) = NULL,  -- if NULL: all roots (dad IS NULL). Else root = son == @root_id
    @max_level  INT       = 50,    -- safety against infinite recursion
    @tree_style CHAR(3)   = 'md',  -- 'md' (Markdown bullets) or 'asc' (ASCII Tree)
    @debug_sql  BIT       = 0      -- if 1, PRINT the generated dynamic SQL
AS
BEGIN
    SET NOCOUNT ON;

    -- STEP 1: STATIC VALIDATION (no dynamic SQL yet)
    DECLARE @obj_id INT = OBJECT_ID(@table_name);
    IF @obj_id IS NULL
        THROW 50001, N'[sp_render_tree] Table does not exist. Use 2-part name if schema is not dbo.', 1;

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @obj_id AND name = @col_dad)
        THROW 50002, N'[sp_render_tree] Parent column (col_dad) not found in target table.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @obj_id AND name = @col_son)
        THROW 50003, N'[sp_render_tree] Child column (col_son) not found in target table.', 1;
    IF @col_label IS NOT NULL AND
       NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @obj_id AND name = @col_label)
        THROW 50004, N'[sp_render_tree] Label column (col_label) not found in target table.', 1;
    IF @tree_style NOT IN ('md', 'asc')
        THROW 50005, N'[sp_render_tree] @tree_style must be ''md'' (markdown) or ''asc'' (ascii).', 1;

    -- Build safe identifiers via QUOTENAME
    DECLARE @schema_name SYSNAME = OBJECT_SCHEMA_NAME(@obj_id);
    DECLARE @table_only  SYSNAME = OBJECT_NAME(@obj_id);
    DECLARE @q_table NVARCHAR(300) = QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_only);
    DECLARE @q_dad   NVARCHAR(150) = QUOTENAME(@col_dad);
    DECLARE @q_son   NVARCHAR(150) = QUOTENAME(@col_son);
    DECLARE @q_label NVARCHAR(150) = CASE WHEN @col_label IS NULL THEN @q_son ELSE QUOTENAME(@col_label) END;

    -- STEP 2: BUILD DYNAMIC SQL
    -- CTE logic:
    --   (A) Pre-compute each node's sibling position (SiblingOrder + SiblingCount)
    --   (B) Recursive CTE carries:
    --         * CyclePath = ID path delimited for cycle detection
    --         * PrefixAcc = accumulated ASCII prefix for box-drawing
    --         * Level + IsLastSibling
    DECLARE @sql NVARCHAR(MAX) = N'
;WITH BaseTable AS (
    SELECT
        ' + @q_dad   + N' AS dad_id,
        ' + @q_son   + N' AS son_id,
        CONVERT(NVARCHAR(MAX), ' + @q_label + N') AS node_label,
        CONVERT(NVARCHAR(MAX), ' + @q_son   + N') AS son_id_str
    FROM ' + @q_table + N'
),
SiblingStats AS (
    SELECT
        son_id,
        ROW_NUMBER() OVER (PARTITION BY dad_id ORDER BY son_id) AS SibOrder,
        COUNT(*)     OVER (PARTITION BY dad_id)                  AS SibTotal
    FROM BaseTable
),
RecursiveTree AS (
    -- Anchor: root nodes
    SELECT
        b.dad_id, b.son_id, b.node_label, b.son_id_str,
        Level      = 0,
        IsCycle    = CAST(0 AS BIT),
        PrefixAcc  = CAST(N'''' AS NVARCHAR(MAX)),
        CyclePath  = CAST(N''»'' + b.son_id_str + N''«'' AS NVARCHAR(MAX)),
        ss.SibOrder, ss.SibTotal,
        IsLastSibling = CAST(1 AS BIT)
    FROM BaseTable b
    JOIN SiblingStats ss ON b.son_id = ss.son_id
    WHERE
        (@p_root_id IS NOT NULL AND b.son_id_str = CONVERT(NVARCHAR(MAX), @p_root_id))
        OR
        (@p_root_id IS NULL AND b.dad_id IS NULL)

    UNION ALL

    -- Recursion: children -> grandchildren -> ...
    SELECT
        b.dad_id, b.son_id, b.node_label, b.son_id_str,
        Level      = rt.Level + 1,
        IsCycle    = CAST(CASE
                        WHEN CHARINDEX(N''»'' + CONVERT(NVARCHAR(MAX), b.dad_id) + N''«'', rt.CyclePath) > 0
                        THEN 1 ELSE 0 END AS BIT),
        PrefixAcc  = CAST(rt.PrefixAcc
                        + CASE WHEN rt.IsLastSibling = 1 THEN N''    ''
                                                        ELSE N''|   '' END
                       AS NVARCHAR(MAX)),
        CyclePath  = CAST(rt.CyclePath + N''»'' + b.son_id_str + N''«'' AS NVARCHAR(MAX)),
        ss.SibOrder, ss.SibTotal,
        IsLastSibling = CAST(CASE WHEN ss.SibOrder = ss.SibTotal THEN 1 ELSE 0 END AS BIT)
    FROM BaseTable b
    JOIN RecursiveTree rt ON b.dad_id = rt.son_id
    JOIN SiblingStats  ss ON b.son_id = ss.son_id
    WHERE rt.IsCycle = 0
      AND rt.Level + 1 <= @p_max_level
)
SELECT ResultColumn
FROM (
    SELECT
        Level, son_id, dad_id, node_label, IsCycle, SibOrder, CyclePath,
        CASE @p_tree_style
            WHEN ''md'' THEN
                REPLICATE(N''  '', Level) + N''- ''
                + node_label
                + CASE WHEN IsCycle = 1 THEN N'' [CYCLE DETECTED]'' ELSE N'''' END
            ELSE
                CASE WHEN Level = 0 THEN N''''
                     ELSE PrefixAcc
                        + CASE WHEN IsLastSibling = 1 THEN N''\-- '' ELSE N''|-- '' END END
                + node_label
                + CASE WHEN IsCycle = 1 THEN N''  [CYCLE path='' + REPLACE(CyclePath, N''»«'', N''<'') + N'']'' ELSE N'''' END
        END AS ResultColumn
    FROM RecursiveTree
) x
ORDER BY CyclePath, SibOrder
OPTION (MAXRECURSION 0);
';

    IF @debug_sql = 1
    BEGIN
        PRINT N'-- ===== DYNAMIC SQL GENERATED BY lab.sp_render_tree =====';
        PRINT @sql;
    END;

    -- STEP 3: TYPED EXECUTION VIA sp_executesql (safe)
    DECLARE @params NVARCHAR(MAX) = N'
        @p_root_id   NVARCHAR(MAX),
        @p_max_level INT,
        @p_tree_style CHAR(3)
    ';

    EXEC sp_executesql
        @stmt   = @sql,
        @params = @params,
        @p_root_id   = @root_id,
        @p_max_level = @max_level,
        @p_tree_style = @tree_style;
END;
GO

-- Usage examples
PRINT '=== Example 1: OrgChart in MARKDOWN (bullet style) ===';
EXEC lab.sp_render_tree
     @table_name = 'lab.OrgChart',
     @col_dad    = 'ManagerID',
     @col_son    = 'EmployeeID',
     @col_label  = 'EmployeeName',
     @tree_style = 'md';
GO

PRINT '=== Example 2: Same tree in ASCII (box-drawing) ===';
EXEC lab.sp_render_tree
     @table_name = 'lab.OrgChart',
     @col_dad    = 'ManagerID',
     @col_son    = 'EmployeeID',
     @col_label  = 'EmployeeName',
     @tree_style = 'asc';
GO

PRINT '=== Example 3: Sub-tree starting from Region A Manager (EmployeeID = 3) ===';
EXEC lab.sp_render_tree
     @table_name = 'lab.OrgChart',
     @col_dad    = 'ManagerID',
     @col_son    = 'EmployeeID',
     @col_label  = 'EmployeeName',
     @root_id    = '3',
     @tree_style = 'asc';
GO

-- Example 4: Real AdventureWorks hierarchy via HIERARCHYID conversion
DROP TABLE IF EXISTS #AWDiretoria;
CREATE TABLE #AWDiretoria (
    EmployeeID   INT NOT NULL PRIMARY KEY,
    ManagerID    INT NULL FOREIGN KEY REFERENCES #AWDiretoria(EmployeeID),
    EmployeeName NVARCHAR(300) NOT NULL
);

INSERT INTO #AWDiretoria (EmployeeID, ManagerID, EmployeeName)
SELECT
    emp.BusinessEntityID,
    mgr.BusinessEntityID AS ManagerID,
    N'[' + emp.JobTitle + N'] ' + p.FirstName + N' ' + ISNULL(p.MiddleName + N' ', N'') + p.LastName
FROM HumanResources.Employee emp
INNER JOIN Person.Person p ON p.BusinessEntityID = emp.BusinessEntityID
LEFT JOIN HumanResources.Employee mgr
       ON mgr.OrganizationNode = emp.OrganizationNode.GetAncestor(1)
WHERE emp.OrganizationLevel <= 2  -- 3 levels: CEO + Directors + Managers
ORDER BY emp.OrganizationLevel, emp.BusinessEntityID;

PRINT '=== Example 4: AdventureWorks Executive Team (HIERARCHYID -> Adjacency List) ===';
EXEC lab.sp_render_tree
     @table_name = 'tempdb..#AWDiretoria',
     @col_dad    = 'ManagerID',
     @col_son    = 'EmployeeID',
     @col_label  = 'EmployeeName',
     @tree_style = 'asc';
GO

-- Technical note: sp_render_tree is a stored procedure, not a TVF,
-- because UDFs cannot call EXEC/sp_executesql (dynamic SQL).
-- Workaround to use result as "table":
--   CREATE TABLE #TreeResult (ResultColumn NVARCHAR(MAX));
--   INSERT INTO #TreeResult EXEC lab.sp_render_tree ...;
--   SELECT * FROM #TreeResult WHERE ...;


-- =================================================================================
-- PART 5: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Deduplicating Event Records (keep latest per customer)
INSERT INTO lab.CustomerEvents (CustomerID, EventName, EventDate) VALUES 
    (1001, 'Login', '2025-01-01 10:00:00'),
    (1001, 'UpdateProfile', '2025-01-01 10:05:00'), -- Most recent
    (1002, 'Login', '2025-01-01 11:00:00');
GO

WITH RankedEvents AS (
    SELECT 
        EventID, CustomerID, EventName, EventDate,
        ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY EventDate DESC) AS RowNum
    FROM lab.CustomerEvents
)
SELECT EventID, CustomerID, EventName, EventDate
FROM RankedEvents
WHERE RowNum = 1; -- Keep only the most recent per customer
GO


--- SCENARIO 2: Percentile Analysis (PERCENTILE_CONT/DISC, CUME_DIST, PERCENT_RANK)
-- KEY CONCEPTS:
--   - PERCENTILE_CONT(p): Continuous INTERPOLATION (may not exist in data).
--     E.g., median P50 of {10,20,30,40} = 25 (interpolated).
--   - PERCENTILE_DISC(p): Discrete value that EXISTS in the column.
--     Returns smallest value where CUME_DIST >= p. P50 of above = 20.
--   - CUME_DIST(): Cumulative distribution (0,1]. P100 = 1.0.
--   - PERCENT_RANK(): Relative rank [0,1]. First row = 0.
--
-- [DP-800 EXAM TIP] PERCENTILE_CONT/DISC use WITHIN GROUP (ORDER BY ...),
--   NOT OVER (ORDER BY ...). OVER() only accepts PARTITION BY.

SELECT DISTINCT
    SalesPersonID,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Amount)
        OVER (PARTITION BY SalesPersonID) AS P50_MedianContinuous,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY Amount)
        OVER (PARTITION BY SalesPersonID) AS P50_MedianDiscrete,
    PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY Amount)
        OVER (PARTITION BY SalesPersonID) AS P90_Discrete
FROM lab.SalesData
ORDER BY SalesPersonID;
GO

-- CUME_DIST vs PERCENT_RANK side by side (salesperson 103 with 3 sales)
SELECT
    SaleID, SalesPersonID, Amount,
    CUME_DIST()    OVER (PARTITION BY SalesPersonID ORDER BY Amount) AS CumeDist,
    PERCENT_RANK() OVER (PARTITION BY SalesPersonID ORDER BY Amount) AS PercentRank
FROM lab.SalesData
WHERE SalesPersonID = 103
ORDER BY Amount;
GO


--- SCENARIO 3: HIERARCHYID - Native Type vs Adjacency List + Recursive CTE
-- MS Learn: SQL Server offers HIERARCHYID for tree representation without
-- recursive CTEs. Stores path (e.g., /1/3/2/) as binary.
-- Operations: .GetLevel(), .GetAncestor(n), .IsDescendantOf(x), .ToString().
-- Advantage: sub-tree and ancestor queries are O(1) with clustered index.
-- Disadvantage: manual maintenance (rebalancing).
--
-- [DP-800 EXAM TIP] When to use each:
--   - HIERARCHYID = deep trees needing fast ancestor queries
--   - Adjacency List + Recursive CTE = simpler, flexible, portable

CREATE TABLE lab.OrgChartHierarchyid (
    NodeId      HIERARCHYID NOT NULL PRIMARY KEY,
    EmployeeID  INT NOT NULL UNIQUE,
    EmployeeName NVARCHAR(100) NOT NULL,
    Level AS NodeId.GetLevel()  -- computed column!
);
GO

INSERT INTO lab.OrgChartHierarchyid (NodeId, EmployeeID, EmployeeName) VALUES
('/1/',     1, N'CEO / Presidente'),
('/1/1/',   2, N'VP de Vendas'),
('/1/1/1/', 3, N'Gerente de Vendas Regiao A'),
('/1/1/1/1/',4, N'Vendedor Senior 1'),
('/1/1/1/2/',5, N'Vendedor Junior 2');
GO

-- Query 1: Path visualization (no CTE needed - native HIERARCHYID)
SELECT
    NodeId.ToString() AS PathString,
    Level,
    EmployeeID,
    EmployeeName,
    NodeId.GetAncestor(1).ToString() AS ImmediateParent
FROM lab.OrgChartHierarchyid
ORDER BY NodeId;
GO

-- Query 2: Sub-tree under "Gerente de Vendas Regiao A" (EmployeeID=3)
-- No recursion - simple IsDescendantOf predicate!
DECLARE @manager HIERARCHYID = (SELECT NodeId FROM lab.OrgChartHierarchyid WHERE EmployeeID = 3);
SELECT
    REPLICATE('  ', Level - @manager.GetLevel()) + '- ' + EmployeeName AS SubTreeMarkdown,
    EmployeeID
FROM lab.OrgChartHierarchyid
WHERE NodeId.IsDescendantOf(@manager) = 1
ORDER BY NodeId;
GO


--- SCENARIO 4: Gap Detection with LAG() predicate
-- KEY CONCEPT: In time series / sequential ID data, a "gap" is when
-- the current value is not previous + 1. LAG solves this in one pass.

WITH Gaps AS (
    SELECT
        SaleID,
        LAG(SaleID, 1) OVER (ORDER BY SaleID) AS PreviousSaleID
    FROM lab.SalesData
)
SELECT
    PreviousSaleID + 1 AS GapStart,
    SaleID - 1 AS GapEnd,
    SaleID - PreviousSaleID - 1 AS MissingCount
FROM Gaps
WHERE PreviousSaleID IS NOT NULL
  AND SaleID <> PreviousSaleID + 1 -- gap detected
ORDER BY GapStart;
GO

-- Date-based gap detection: check if sales have > 5 day gap per salesperson
WITH SalesWithPrev AS (
    SELECT
        SalesPersonID, SaleDate, Amount,
        LAG(SaleDate, 1) OVER (
            PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID
        ) AS PreviousSaleDate
    FROM lab.SalesData
)
SELECT
    SalesPersonID, SaleDate, PreviousSaleDate,
    DATEDIFF(DAY, PreviousSaleDate, SaleDate) AS DaysSinceLastSale
FROM SalesWithPrev
WHERE PreviousSaleDate IS NOT NULL
  AND DATEDIFF(DAY, PreviousSaleDate, SaleDate) > 1;
GO


--- SCENARIO 5: Top-N per Group - ROW_NUMBER vs RANK for cutoff
-- ROW_NUMBER() gives exactly N rows per group (arbitrary tiebreaker)
-- RANK() can give more than N if there are ties at the boundary

-- Top 1 per salesperson (ROW_NUMBER: exactly 1 row)
WITH Ranked AS (
    SELECT SalesPersonID, SaleDate, Amount,
           ROW_NUMBER() OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS RowNum
    FROM lab.SalesData
)
SELECT SalesPersonID, SaleDate, Amount AS TopSaleAmount
FROM Ranked
WHERE RowNum = 1
ORDER BY SalesPersonID;
GO

-- Top 1 per salesperson (RANK: could return >1 if ties exist at position 1)
WITH Ranked AS (
    SELECT SalesPersonID, SaleDate, Amount,
           RANK() OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS RankNum
    FROM lab.SalesData
)
SELECT SalesPersonID, SaleDate, Amount AS TopSaleAmount
FROM Ranked
WHERE RankNum = 1
ORDER BY SalesPersonID;
-- Note: Salesperson 102 has 2 identical $500 sales. ROW_NUMBER returns 1 row
-- (arbitrarily), RANK returns 2 rows (all tied for 1st).
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/03-advanced-tsql/01-ctes-window-functions.md
-- =================================================================================================
