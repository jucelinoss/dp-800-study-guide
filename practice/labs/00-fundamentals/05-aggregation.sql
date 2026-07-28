-- ====================================================================
-- DP-800 Study Guide — Lab 05: Aggregation and GROUP BY
-- Database: AdventureWorks2025
-- Purpose: COUNT, SUM, AVG, MIN, MAX, GROUP BY, HAVING, conditional agg
-- Prerequisite: Lab 04 (familiarity with AdventureWorks schema)
-- ====================================================================

-- THEORY REFERENCE: ../../../certification/00-fundamentals/05-relationships-and-joins.md
--    Open the theory guide alongside this lab for conceptual context.

-- ====================================================================
-- Aggregate functions overview
-- KEY CONCEPT: All aggregates except COUNT(*) ignore NULL values.
-- All aggregates return a single row when used without GROUP BY.
-- ====================================================================
-- OVERALL STATS on SalesOrderHeader (~31k rows)
SELECT COUNT(*)              AS TotalOrders,
       COUNT(ShipDate)       AS ShippedOrders,    -- ignores NULL ShipDate
       COUNT(DISTINCT CustomerID) AS UniqueCustomers,
       MIN(TotalDue)         AS SmallestOrder,
       MAX(TotalDue)         AS LargestOrder,
       AVG(TotalDue)         AS AvgOrderValue,
       SUM(TotalDue)         AS GrandTotal
FROM Sales.SalesOrderHeader;
GO

-- [OBSERVE] ShippedOrders < TotalOrders because some orders have NULL ShipDate.
-- COUNT(DISTINCT CustomerID) counts unique customers, ignoring NULLs.

-- ====================================================================
-- COUNT variations
-- KEY CONCEPT: COUNT(*) vs COUNT(col) vs COUNT(DISTINCT col)
-- ====================================================================
SELECT COUNT(*)              AS AllRows,           -- 31465
       COUNT(ShipDate)       AS WithShipDate,      -- fewer (NULL excluded)
       COUNT(DISTINCT CustomerID) AS UniqueCust     -- unique non-null customers
FROM Sales.SalesOrderHeader;
GO

-- ====================================================================
-- GROUP BY single column
-- KEY CONCEPT: One result row per unique value of the GROUP BY column.
-- ====================================================================
-- EXPECTED: One row per territory (~10 rows)
SELECT st.Name AS Territory,
       COUNT(soh.SalesOrderID) AS OrderCount,
       SUM(soh.TotalDue)       AS TotalSales,
       AVG(soh.TotalDue)       AS AvgOrderValue
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c
    ON c.CustomerID = soh.CustomerID
INNER JOIN Sales.SalesTerritory AS st
    ON st.TerritoryID = c.TerritoryID
GROUP BY st.Name
ORDER BY TotalSales DESC;
GO

-- [OBSERVE] The grain: "one row per territory". Each aggregate summarizes
-- all orders within that territory.

-- ====================================================================
-- GROUP BY composite (multiple columns)
-- KEY CONCEPT: One row per unique combination of the grouping columns.
-- ====================================================================
-- EXPECTED: ~500 rows (year × product combinations)
SELECT YEAR(soh.OrderDate)   AS OrderYear,
       p.Name                AS ProductName,
       SUM(sod.OrderQty)     AS TotalSold,
       SUM(sod.LineTotal)    AS TotalRevenue
FROM Sales.SalesOrderDetail AS sod
INNER JOIN Production.Product AS p
    ON p.ProductID = sod.ProductID
INNER JOIN Sales.SalesOrderHeader AS soh
    ON soh.SalesOrderID = sod.SalesOrderID
GROUP BY YEAR(soh.OrderDate), p.Name
ORDER BY OrderYear, TotalRevenue DESC;
GO

-- [OBSERVE] This query has grain: "one row per year + product combination".
-- Each row tells you how much of a product sold in a specific year.

-- ====================================================================
-- HAVING to filter groups
-- KEY CONCEPT: WHERE filters rows BEFORE grouping.
-- HAVING filters groups AFTER aggregation.
-- ====================================================================
-- Territories with average order value > $1,000
SELECT st.Name AS Territory,
       COUNT(soh.SalesOrderID) AS OrderCount,
       AVG(soh.TotalDue)       AS AvgOrderValue
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c
    ON c.CustomerID = soh.CustomerID
INNER JOIN Sales.SalesTerritory AS st
    ON st.TerritoryID = c.TerritoryID
WHERE soh.OrderDate >= '2013-01-01'           -- filter rows first
GROUP BY st.Name
HAVING AVG(soh.TotalDue) > 1000              -- filter groups second
ORDER BY AvgOrderValue DESC;
GO

-- ====================================================================
-- LEFT JOIN + aggregation (handling NULLs)
-- KEY CONCEPT: COUNT(ChildID) correctly returns zero for unmatched parents.
-- COUNT(*) would count the NULL-extended row as 1, which is wrong.
-- ====================================================================
-- All products with total sold quantity (including unsold)
SELECT p.ProductID,
       p.Name,
       COUNT(sod.ProductID) AS SaleCount,    -- 0 if never sold
       COALESCE(SUM(sod.OrderQty), 0) AS TotalQty
FROM Production.Product AS p
LEFT JOIN Sales.SalesOrderDetail AS sod
    ON sod.ProductID = p.ProductID
GROUP BY p.ProductID, p.Name
ORDER BY TotalQty DESC;
GO

-- [OBSERVE] Products with NULL in SaleCount never appear because COUNT
-- of a NULL-extended column is 0, not NULL. COALESCE handles SUM returning NULL.

-- ====================================================================
-- Conditional aggregation using CASE
-- KEY CONCEPT: SUM(CASE WHEN ... THEN 1 ELSE 0 END) counts conditions.
-- SUM(CASE WHEN ... THEN value ELSE 0 END) sums conditionally.
-- ====================================================================
-- Per customer: total orders, large orders (> $1,000), and large order total
SELECT TOP 10
    CustomerID,
    COUNT(*) AS AllOrders,
    SUM(CASE WHEN TotalDue > 1000 THEN 1 ELSE 0 END) AS LargeOrders,
    SUM(CASE WHEN TotalDue > 1000 THEN TotalDue ELSE 0 END) AS LargeOrdersTotal
FROM Sales.SalesOrderHeader
GROUP BY CustomerID
ORDER BY LargeOrders DESC;
GO

-- [OBSERVE] Conditional aggregation answers multiple questions in one pass.
-- Without CASE, you'd need separate queries with WHERE filters.

-- ====================================================================
-- GROUP BY with expressions (not just bare columns)
-- KEY CONCEPT: You can group by calculated expressions like YEAR() or LEFT().
-- ====================================================================
-- Products grouped by first letter of product number
SELECT LEFT(ProductNumber, 1) AS ProductSeries,
       COUNT(*)               AS ProductCount,
       AVG(ListPrice)         AS AvgPrice
FROM Production.Product
GROUP BY LEFT(ProductNumber, 1)
ORDER BY ProductSeries;
GO

-- ====================================================================
-- Common aggregation pitfalls demonstrated
-- KEY CONCEPT: Always verify NULL behavior and grain.
-- ====================================================================

-- Pitfall 1: AVG ignores NULL, which may lower the average unexpectedly.
-- Compare AVG of a column with and without NULLs.
CREATE TABLE #TestAvg (Val INT NULL);
INSERT INTO #TestAvg VALUES (10), (20), (NULL);
SELECT AVG(Val) AS AvgWithoutNullHandling,   -- 15 (ignores NULL)
       AVG(ISNULL(Val, 0)) AS AvgWithNullAsZero  -- 10 (treats NULL as 0)
FROM #TestAvg;
DROP TABLE #TestAvg;
GO

-- Pitfall 2: GROUP BY without enough columns causes errors.
-- Correct: add non-aggregated columns to GROUP BY
SELECT CustomerID,
       YEAR(OrderDate) AS OrderYear,
       COUNT(*) AS OrderCount
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-01-01' AND OrderDate < '2014-01-01'
GROUP BY CustomerID, YEAR(OrderDate)
ORDER BY CustomerID, OrderYear;
GO

-- ====================================================================
-- CHECK YOURSELF:
-- 1. How many products have ListPrice > $100?
-- 2. Which product category has the highest average ListPrice?
--    (Hint: join Production.Product to Production.ProductSubcategory
--     to Production.ProductCategory)
-- 3. Count orders by year, showing only years with > 5,000 orders.
-- 4. Write a conditional aggregation that counts red, blue, and black
--    products separately in one query.

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/00-fundamentals/05-relationships-and-joins.md
-- =================================================================================================
