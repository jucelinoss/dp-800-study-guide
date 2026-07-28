-- ====================================================================
-- DP-800 Study Guide — Lab 06: Subqueries and CTEs
-- Database: AdventureWorks2025
-- Purpose: Derived tables, CTEs, temp tables, table variables
-- Prerequisite: Labs 01-05 (AGGREGATION concepts required)
-- ====================================================================

-- THEORY REFERENCE: ../../../certification/00-fundamentals/06-aggregation-and-grouping.md
--    Open the theory guide alongside this lab for conceptual context.

-- ====================================================================
-- Derived table: subquery in FROM with required alias
-- KEY CONCEPT: A derived table is an inline view. It must have an alias.
-- Unlike a CTE, it cannot be referenced more than once in the statement.
-- ====================================================================
-- Products with total sold quantity > 100
-- EXPECTED: ~200 products
SELECT dt.ProductID, dt.ProductName, dt.TotalSold
FROM (
    SELECT p.ProductID,
           p.Name AS ProductName,
           SUM(sod.OrderQty) AS TotalSold
    FROM Production.Product AS p
    INNER JOIN Sales.SalesOrderDetail AS sod
        ON sod.ProductID = p.ProductID
    GROUP BY p.ProductID, p.Name
) AS dt
WHERE dt.TotalSold > 100
ORDER BY dt.TotalSold DESC;
GO

-- ====================================================================
-- Simple CTE
-- KEY CONCEPT: WITH defines a named expression for the next statement.
-- The CTE name is only available in the statement immediately after it.
-- ====================================================================
WITH ProductSales AS (
    SELECT p.ProductID,
           p.Name AS ProductName,
           SUM(sod.OrderQty) AS TotalSold
    FROM Production.Product AS p
    INNER JOIN Sales.SalesOrderDetail AS sod
        ON sod.ProductID = p.ProductID
    GROUP BY p.ProductID, p.Name
)
SELECT ProductID, ProductName, TotalSold
FROM ProductSales
WHERE TotalSold > 100
ORDER BY TotalSold DESC;
GO

-- [OBSERVE] The CTE version is more readable than the derived table version
-- for the same business question. The CTE separates the logic (what is
-- ProductSales?) from the filter (WHERE TotalSold > 100).

-- ====================================================================
-- Multiple CTEs (comma-separated)
-- KEY CONCEPT: CTEs can reference earlier CTEs in the same WITH clause.
-- ====================================================================
WITH
ProductSales AS (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
),
HighSellers AS (
    SELECT ps.ProductID, p.Name, ps.TotalSold
    FROM ProductSales AS ps
    INNER JOIN Production.Product AS p
        ON p.ProductID = ps.ProductID
    WHERE ps.TotalSold > 500
)
SELECT Name, TotalSold
FROM HighSellers
ORDER BY TotalSold DESC;
GO

-- [OBSERVE] HighSellers depends on ProductSales. The comma separates
-- the CTE definitions. Each builds on the previous one.

-- ====================================================================
-- CTE vs derived table: same query, two styles
-- KEY CONCEPT: CTEs are preferred for readability, especially with
-- multiple steps. The execution plans are typically identical.
-- ====================================================================
-- Derived table: nested, harder to read
SELECT d.CustomerID, d.TotalSpend
FROM (
    SELECT CustomerID, SUM(TotalDue) AS TotalSpend
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
) AS d
WHERE d.TotalSpend > 5000;
GO

-- CTE: flatter, easier to read
WITH CustomerSpend AS (
    SELECT CustomerID, SUM(TotalDue) AS TotalSpend
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
)
SELECT CustomerID, TotalSpend
FROM CustomerSpend
WHERE TotalSpend > 5000;
GO

-- ====================================================================
-- Local temp table (#Temp)
-- KEY CONCEPT: #Temp persists for the session. Can have indexes.
-- Good for reusing intermediate results across multiple statements.
-- ====================================================================
-- Create a temp table to hold high-value orders
CREATE TABLE #HighValueOrders (
    SalesOrderID INT NOT NULL PRIMARY KEY,
    TotalDue     DECIMAL(18,2) NOT NULL
);

-- Populate it
INSERT INTO #HighValueOrders (SalesOrderID, TotalDue)
SELECT SalesOrderID, TotalDue
FROM Sales.SalesOrderHeader
WHERE TotalDue > 5000;

-- Use it in queries
SELECT COUNT(*) AS HighValueCount FROM #HighValueOrders;
SELECT AVG(TotalDue) AS AvgHighValue FROM #HighValueOrders;

-- Clean up explicitly
DROP TABLE IF EXISTS #HighValueOrders;
GO

-- [OBSERVE] Unlike a CTE, #HighValueOrders can be queried across
-- multiple batches. The temp table is dropped when the session ends,
-- but explicit cleanup is a good habit.

-- ====================================================================
-- Table variable (@TableVar)
-- KEY CONCEPT: Scoped to the batch/procedure. Lighter than #Temp,
-- but has no statistics (optimizer assumes 1 row).
-- ====================================================================
DECLARE @SelectedProducts TABLE (
    ProductID INT NOT NULL PRIMARY KEY,
    Name      NVARCHAR(50) NOT NULL,
    ListPrice DECIMAL(18,2) NOT NULL
);

INSERT INTO @SelectedProducts (ProductID, Name, ListPrice)
SELECT ProductID, Name, ListPrice
FROM Production.Product
WHERE ListPrice > 500;

-- Query the table variable
SELECT COUNT(*) AS ExpensiveProducts FROM @SelectedProducts;
SELECT AVG(ListPrice) AS AvgPrice FROM @SelectedProducts;
GO

-- [OBSERVE] @SelectedProducts is automatically cleaned up at the end
-- of the batch (after GO). It is ideal for small lookup sets.

-- ====================================================================
-- CTE + INTO #Temp (combining styles)
-- KEY CONCEPT: Use CTE for readability, then persist to a temp table
-- when you need to reuse the result across multiple statements.
-- ====================================================================
WITH ProductSales AS (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
)
SELECT p.ProductID, p.Name, ps.TotalSold
INTO #ProductSalesReport
FROM ProductSales AS ps
INNER JOIN Production.Product AS p
    ON p.ProductID = ps.ProductID;

-- Now reuse #ProductSalesReport across multiple queries
SELECT COUNT(*) AS HighSellers FROM #ProductSalesReport WHERE TotalSold > 500;
SELECT AVG(TotalSold) AS AvgSold FROM #ProductSalesReport;

-- Clean up
DROP TABLE IF EXISTS #ProductSalesReport;
GO

-- ====================================================================
-- NOT IN NULL trap (demonstration with temp table)
-- KEY CONCEPT: NOT IN returns zero rows if the subquery result
-- contains any NULL. Use NOT EXISTS for safety.
-- ====================================================================
CREATE TABLE #TestNull (CustomerID INT NULL);
INSERT INTO #TestNull VALUES (1), (NULL);

-- This returns ZERO rows because of the NULL!
SELECT CustomerID FROM Sales.Customer
WHERE CustomerID NOT IN (SELECT CustomerID FROM #TestNull);

-- This works correctly (NOT EXISTS handles NULL safely)
SELECT CustomerID FROM Sales.Customer AS c
WHERE NOT EXISTS (
    SELECT 1 FROM #TestNull AS t
    WHERE t.CustomerID = c.CustomerID
);

DROP TABLE IF EXISTS #TestNull;
GO

-- ====================================================================
-- CHECK YOURSELF:
-- 1. Rewrite the derived table query at the top of this lab as a CTE.
-- 2. Use a CTE to find the top 5 products by revenue
--    (SUM(UnitPrice * OrderQty) in SalesOrderDetail).
-- 3. When would you choose a #TempTable over a CTE?
-- 4. Create a table variable holding today's high-value orders
--    (TotalDue > 5000) and query it.

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/00-fundamentals/06-aggregation-and-grouping.md
-- =================================================================================================
