-- ====================================================================
-- DP-800 Study Guide — Lab 10: Final Review and Cleanup
-- Database: AdventureWorks2025
-- Purpose: Multi-join aggregation review + CTE bonus
-- ====================================================================

-- ====================================================================
-- FINAL REVIEW: Multi-join aggregation
-- Business question: "Show each territory with total sales, order count,
-- and average order value, sorted by total sales descending."
-- ====================================================================
SELECT st.Name AS Territory,
       COUNT(soh.SalesOrderID) AS OrderCount,
       SUM(soh.TotalDue)       AS TotalSales,
       AVG(soh.TotalDue)       AS AvgOrderValue
FROM Sales.SalesTerritory AS st
INNER JOIN Sales.Customer AS c
    ON c.TerritoryID = st.TerritoryID
INNER JOIN Sales.SalesOrderHeader AS soh
    ON soh.CustomerID = c.CustomerID
GROUP BY st.Name
ORDER BY TotalSales DESC;
GO

-- [OBSERVE] This query combines 3 JOINs + aggregation. Each territory
-- appears once (grain = territory), with aggregated order statistics.

-- ====================================================================
-- BONUS: Same query with CTE
-- KEY CONCEPT: A CTE makes multi-step logic easier to read.
-- ====================================================================
WITH TerritorySales AS (
    SELECT c.TerritoryID,
           COUNT(soh.SalesOrderID) AS OrderCount,
           SUM(soh.TotalDue)       AS TotalSales,
           AVG(soh.TotalDue)       AS AvgOrderValue
    FROM Sales.Customer AS c
    INNER JOIN Sales.SalesOrderHeader AS soh
        ON soh.CustomerID = c.CustomerID
    GROUP BY c.TerritoryID
)
SELECT st.Name AS Territory,
       ts.OrderCount,
       ts.TotalSales,
       ts.AvgOrderValue
FROM TerritorySales AS ts
INNER JOIN Sales.SalesTerritory AS st
    ON st.TerritoryID = ts.TerritoryID
ORDER BY ts.TotalSales DESC;
GO

-- [OBSERVE] The CTE separates the aggregation logic from the final
-- SELECT with territory names. This is easier to read and debug.

-- ====================================================================
-- What you have learned in Part 0 — Fundamentals:
-- ====================================================================
-- 1. Create database, schema, tables with constraints (Labs 01-02 / StudyDB)
-- 2. SELECT, WHERE, ORDER BY, TOP with real data (Lab 03 / AdventureWorks)
-- 3. INNER JOIN, LEFT JOIN, CROSS JOIN, self-join (Lab 04)
-- 4. Aggregation: COUNT, SUM, AVG, GROUP BY, HAVING (Lab 05)
-- 5. Derived tables, CTEs, temp tables, table variables (Lab 06)
-- 6. Safe DML with transactions, OUTPUT, @@ROWCOUNT (Lab 07)
-- 7. Integrity rules: PK, FK, UNIQUE, CHECK, DEFAULT (Lab 08)
-- 8. Index fundamentals: seek vs scan, STATISTICS IO (Lab 09)

PRINT 'Congratulations! You have completed Part 0 — Fundamentals.';
PRINT 'You are ready to move on to the DP-800 exam sections.';
GO

-- ====================================================================
-- OPTIONAL CLEANUP: Drop StudyDB (if no longer needed)
-- Remove the comments below to delete the StudyDB database.
-- ====================================================================
-- USE master;
-- GO
-- IF DB_ID(N'StudyDB') IS NOT NULL
-- BEGIN
--     ALTER DATABASE StudyDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
--     DROP DATABASE StudyDB;
-- END;
-- GO
-- PRINT 'StudyDB has been removed.';
-- GO
