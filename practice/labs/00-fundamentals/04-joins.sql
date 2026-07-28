-- ====================================================================
-- DP-800 Study Guide — Lab 04: JOINs
-- Database: AdventureWorks2025
-- Purpose: INNER, LEFT, RIGHT, CROSS JOIN, self-join, multi-join
-- Prerequisite: Labs 01-03 (not required, but recommended context)
-- ====================================================================

-- THEORY REFERENCE: ../../../certification/00-fundamentals/04-select-and-filter.md
--    Open the theory guide alongside this lab for conceptual context.

-- ====================================================================
-- INNER JOIN: only matching rows from both sides
-- KEY CONCEPT: Both sides must match. Rows without a match are excluded.
-- ====================================================================
-- EXPECTED: ~31k rows (one per order)
SELECT soh.SalesOrderID,
       soh.OrderDate,
       c.AccountNumber
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c
    ON c.CustomerID = soh.CustomerID;
GO

-- [OBSERVE] Every order has a customer (FK ensures this), so INNER JOIN
-- returns all orders. If a customer had been deleted, that order wouldn't
-- appear — but the FK prevents orphan orders.

-- ====================================================================
-- LEFT JOIN: preserve all rows from the left table
-- KEY CONCEPT: All products survive, even if never ordered.
-- Unmatched right-side columns show as NULL.
-- ====================================================================
-- EXPECTED: All 504 products, some with NULL sale date
SELECT p.ProductID, p.Name, MAX(sod.ModifiedDate) AS LastSale
FROM Production.Product AS p
LEFT JOIN Sales.SalesOrderDetail AS sod
    ON sod.ProductID = p.ProductID
GROUP BY p.ProductID, p.Name
ORDER BY LastSale DESC;
GO

-- [OBSERVE] Products never sold have NULL in LastSale. The LEFT JOIN
-- preserved them. If this were INNER JOIN, unsold products would be absent.

-- ====================================================================
-- RIGHT JOIN: preserve all rows from the right table
-- KEY CONCEPT: RIGHT JOIN is less common. Usually rewrite as LEFT JOIN
-- by swapping table order for consistency.
-- ====================================================================
-- Same as the previous query, but with RIGHT JOIN syntax
SELECT p.ProductID, p.Name, MAX(sod.ModifiedDate) AS LastSale
FROM Sales.SalesOrderDetail AS sod
RIGHT JOIN Production.Product AS p
    ON sod.ProductID = p.ProductID
GROUP BY p.ProductID, p.Name
ORDER BY LastSale DESC;
GO

-- [OBSERVE] RIGHT JOIN preserves the right table (Product). The result
-- is identical to the LEFT JOIN above. Most developers prefer LEFT JOIN
-- for readability.

-- ====================================================================
-- CROSS JOIN: every combination (Cartesian product)
-- KEY CONCEPT: No ON clause. Every row from left matches every row
-- from right. Use deliberately — never accidentally.
-- ====================================================================
-- WARNING: This returns 504 × 3 = 1512 rows
SELECT p.Name AS Product, c.Name AS Category
FROM Production.Product AS p
CROSS JOIN Production.ProductCategory AS c;
GO

-- [OBSERVE] CROSS JOIN is useful for generating combinations (e.g.,
-- all products × all stores). Without a WHERE filter, it multiplies.

-- CROSS JOIN with a WHERE filter to demonstrate safe usage
SELECT p.Name AS Product, c.Name AS Category
FROM Production.Product AS p
CROSS JOIN Production.ProductCategory AS c
WHERE p.ProductCategoryID = c.ProductCategoryID;
GO

-- [OBSERVE] Adding a WHERE turned this into an INNER JOIN equivalent.
-- Always prefer explicit JOIN...ON syntax to avoid accidental Cartesian products.

-- ====================================================================
-- Self-join: same table, different aliases
-- KEY CONCEPT: Useful for hierarchies (manager → employee, category → parent).
-- ====================================================================
-- Employees and their managers using OrganizationNode hierarchy.
-- GetAncestor(1) returns the parent node one level up.
SELECT emp.JobTitle AS Employee,
       mgr.LoginID  AS ManagerLogin
FROM HumanResources.Employee AS emp
LEFT JOIN HumanResources.Employee AS mgr
    ON emp.OrganizationNode.GetAncestor(1) = mgr.OrganizationNode;
GO

-- [OBSERVE] The CEO has no manager (NULL). This self-join pattern
-- works for any adjacency-list hierarchy.

-- ====================================================================
-- Multi-join: 3+ tables
-- KEY CONCEPT: Each JOIN combines the previous result with a new table.
-- Mixing INNER and OUTER joins can unexpectedly drop rows (see theory).
-- ====================================================================
-- Order → Customer → Territory
-- EXPECTED: ~31k rows (same as INNER JOIN above, but with territory name)
SELECT soh.SalesOrderID,
       soh.OrderDate,
       c.AccountNumber,
       st.Name AS Territory
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c
    ON c.CustomerID = soh.CustomerID
INNER JOIN Sales.SalesTerritory AS st
    ON st.TerritoryID = c.TerritoryID;
GO

-- [OBSERVE] The query flows: orders → customers → territories.
-- Each INNER JOIN requires a match, so only customers with a territory survive.

-- Multi-join with LEFT JOIN to preserve all orders
-- EXPECTED: ~31k rows, Territory may be NULL if customer has no territory
SELECT soh.SalesOrderID,
       soh.OrderDate,
       c.AccountNumber,
       st.Name AS Territory
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c
    ON c.CustomerID = soh.CustomerID
LEFT JOIN Sales.SalesTerritory AS st
    ON st.TerritoryID = c.TerritoryID;
GO

-- [OBSERVE] Mixing INNER and LEFT JOIN: orders are matched to customers
-- (INNER), but a missing territory doesn't remove the row (LEFT).

-- ====================================================================
-- ON vs WHERE in outer joins
-- KEY CONCEPT: ON controls which rows match; WHERE filters the result.
-- For outer joins, moving a condition from ON to WHERE can change row
-- preservation (removing NULL-extended rows).
-- ====================================================================
-- LEFT JOIN: filter in ON (preserves all products)
SELECT p.Name, sod.SalesOrderID
FROM Production.Product AS p
LEFT JOIN Sales.SalesOrderDetail AS sod
    ON sod.ProductID = p.ProductID
   AND sod.OrderQty > 10
ORDER BY p.Name;
GO

-- Same query: filter in WHERE (removes products with no matching order detail)
SELECT p.Name, sod.SalesOrderID
FROM Production.Product AS p
LEFT JOIN Sales.SalesOrderDetail AS sod
    ON sod.ProductID = p.ProductID
WHERE sod.OrderQty > 10
ORDER BY p.Name;
GO

-- [OBSERVE] The first query keeps ALL products (NULL if no match or qty <= 10).
-- The second query removes products that didn't match — effectively an INNER JOIN.

-- ====================================================================
-- CHECK YOURSELF:
-- 1. List all customers and their last order date
--    (include customers with NO orders — use AccountNumber).
-- 2. Find products that have never been sold
--    (LEFT JOIN + WHERE NULL check on SalesOrderDetail).
-- 3. Which sales territories have no customers?
--    (Sales.SalesTerritory LEFT JOIN Sales.Customer).
-- 4. Write a self-join query to find product subcategories and their
--    parent categories (ProductSubcategory LEFT JOIN to itself, or
--    join ProductSubcategory to ProductCategory).

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/00-fundamentals/04-select-and-filter.md
-- =================================================================================================
