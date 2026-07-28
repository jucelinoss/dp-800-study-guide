-- ====================================================================
-- DP-800 Study Guide — Lab 09: Index Introduction
-- Database: AdventureWorks2025
-- Purpose: STATISTICS IO, CREATE INDEX, measure before/after, covering
-- Prerequisite: Labs 01-08 (DML and query patterns)
-- ====================================================================

-- THEORY REFERENCE: ../../../certification/00-fundamentals/09-subqueries-and-ctes.md
--    Open the theory guide alongside this lab for conceptual context.

-- ====================================================================
-- PART 1: Measure baseline (no targeted index)
-- KEY CONCEPT: STATISTICS IO shows logical reads — pages read from cache.
-- Fewer logical reads usually means less work for the query.
-- ====================================================================
SET STATISTICS IO ON;

-- [OBSERVE] Note the logical reads in the Messages tab.
-- With no targeted index, SQL Server may scan the entire table.
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';
GO

-- [NOTE] Write down the logical reads number from the Messages tab.
-- If the table is small, the difference may be modest, but the
-- measurement technique is what matters.

-- ====================================================================
-- PART 2: Create a targeted index (idempotent)
-- KEY CONCEPT: DROP INDEX IF EXISTS makes the script safe to rerun.
-- ====================================================================
DROP INDEX IF EXISTS IX_Lab_SalesOrderHeader_OrderDate
    ON Sales.SalesOrderHeader;
GO

CREATE INDEX IX_Lab_SalesOrderHeader_OrderDate
    ON Sales.SalesOrderHeader (OrderDate);
GO

PRINT 'Index IX_Lab_SalesOrderHeader_OrderDate created.';
GO

-- ====================================================================
-- PART 3: Measure with the new index
-- KEY CONCEPT: Compare logical reads to the baseline above.
-- A well-used index should show fewer logical reads.
-- ====================================================================
-- Run the same query again
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';
GO

-- [OBSERVE] Compare the logical reads from the Messages tab
-- with those from PART 1. The reduction is the index benefit.

SET STATISTICS IO OFF;
GO

-- ====================================================================
-- PART 4: Inspect index metadata
-- KEY CONCEPT: sys.indexes shows all indexes on a table including
-- those created by constraints (PK, UNIQUE).
-- ====================================================================
SELECT i.name          AS index_name,
       i.type_desc     AS index_type,
       i.is_unique,
       i.is_primary_key,
       i.fill_factor
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'Sales.SalesOrderHeader')
ORDER BY i.type;
GO

-- [OBSERVE] You should see the clustered PK index and the new
-- nonclustered index. Note that type_desc distinguishes them.

-- ====================================================================
-- PART 5: Clustered vs nonclustered in practice
-- KEY CONCEPT: The clustered index defines the physical row order.
-- A nonclustered index key points back to the clustered key.
-- ====================================================================
-- Query that benefits from the clustered index (scan in PK order)
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
ORDER BY SalesOrderID;
GO

-- Query that benefits from the nonclustered index we created
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';
GO

-- ====================================================================
-- PART 6: Covering index (concept)
-- KEY CONCEPT: When ALL columns in the query are in the index,
-- SQL Server can answer from the index alone (no Key Lookup).
-- ====================================================================
-- Create an index that covers this specific query
DROP INDEX IF EXISTS IX_Lab_Covering_Test
    ON Sales.SalesOrderHeader;
GO

CREATE INDEX IX_Lab_Covering_Test
    ON Sales.SalesOrderHeader (OrderDate)
    INCLUDE (TotalDue, SubTotal, TaxAmt);
GO

PRINT 'Covering index IX_Lab_Covering_Test created.';
GO

-- Measure: this query can be answered entirely from the index
SET STATISTICS IO ON;

SELECT OrderDate, TotalDue, SubTotal, TaxAmt
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';
GO

SET STATISTICS IO OFF;
GO

-- [OBSERVE] The INCLUDE columns are stored at the leaf level but
-- don't participate in index navigation. They exist only to make
-- the index "cover" the query and avoid key lookups.

-- ====================================================================
-- PART 7: Index impact on writes (conceptual)
-- KEY CONCEPT: Each index adds cost to INSERT, UPDATE, DELETE.
-- ====================================================================
-- Create a temp table with and without indexes to demonstrate
CREATE TABLE #TestWrite (
    Id    INT NOT NULL,
    Value NVARCHAR(100) NOT NULL
);

-- Insert 1000 rows into a table with NO indexes
DECLARE @i INT = 1;
WHILE @i <= 1000
BEGIN
    INSERT INTO #TestWrite (Id, Value)
    VALUES (@i, N'Row ' + CAST(@i AS NVARCHAR(10)));
    SET @i = @i + 1;
END;
PRINT 'Inserted 1000 rows into heap (no indexes).';

-- Now add an index
CREATE INDEX IX_TestWrite_Id ON #TestWrite (Id);

-- Insert 1000 more rows (slower due to index maintenance)
SET @i = 1001;
WHILE @i <= 2000
BEGIN
    INSERT INTO #TestWrite (Id, Value)
    VALUES (@i, N'Row ' + CAST(@i AS NVARCHAR(10)));
    SET @i = @i + 1;
END;
PRINT 'Inserted 1000 more rows into indexed table.';

DROP TABLE IF EXISTS #TestWrite;
GO

-- [OBSERVE] The second insert is slower because each row must also
-- be written to the IX_TestWrite_Id index. More indexes = slower writes.

-- ====================================================================
-- Clean up lab indexes
-- KEY CONCEPT: Remove the indexes created in this lab so they don't
-- affect future labs or production query plans.
-- ====================================================================
DROP INDEX IF EXISTS IX_Lab_SalesOrderHeader_OrderDate
    ON Sales.SalesOrderHeader;
DROP INDEX IF EXISTS IX_Lab_Covering_Test
    ON Sales.SalesOrderHeader;
GO

PRINT 'Lab indexes cleaned up. See Lab 09 for index fundamentals.';
GO

-- ====================================================================
-- CHECK YOURSELF:
-- 1. Create an index to accelerate a query filtering by DueDate.
-- 2. Use sys.indexes to check if an index is clustered or nonclustered.
-- 3. What happens to logical reads when you add a covering index?
-- 4. Why does each additional index slow down INSERT operations?

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/00-fundamentals/09-subqueries-and-ctes.md
-- =================================================================================================
