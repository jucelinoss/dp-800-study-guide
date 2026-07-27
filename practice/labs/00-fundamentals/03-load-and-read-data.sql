-- ====================================================================
-- DP-800 Study Guide — Lab 03: Load and Read Data
-- Database: AdventureWorks2025 (or AdventureWorks2022, etc.)
-- Purpose: Basic SELECT, WHERE, ORDER BY, TOP, OFFSET-FETCH
-- Prerequisite: AdventureWorks must be restored on your instance.
--   Download: https://learn.microsoft.com/sql/samples/adventureworks-install-configure
-- ====================================================================

-- SETUP NOTE: If AdventureWorks is not yet installed, restore the OLTP
-- backup. The schema used here is standard across AdventureWorks versions.

-- Create lab schema for our temporary objects (runs once)
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'lab')
    EXEC ('CREATE SCHEMA lab');
GO

-- Verify you are connected to the right database
SELECT DB_NAME() AS current_database;
GO

-- ====================================================================
-- Basic SELECT with column aliases
-- KEY CONCEPT: Aliases (AS) make output column names readable.
-- ====================================================================
-- EXPECTED: 19972 rows (Person.Person has ~20k people)
SELECT TOP 10 FirstName,
              MiddleName,
              LastName
FROM Person.Person
ORDER BY LastName;
GO

-- [OBSERVE] MiddleName is NULL for some people. NULL = unknown/missing.

-- ====================================================================
-- WHERE with comparison operators
-- KEY CONCEPT: WHERE filters rows BEFORE they are returned.
-- ====================================================================
-- Products with ListPrice above $1,000
-- EXPECTED: ~200 products
SELECT ProductID, Name, ListPrice
FROM Production.Product
WHERE ListPrice > 1000
ORDER BY ListPrice DESC;
GO

-- Products in specific categories (IN list)
-- EXPECTED: ~40 products in categories 1, 2, 3
SELECT ProductID, Name, ProductCategoryID
FROM Production.Product
WHERE ProductCategoryID IN (1, 2, 3)
ORDER BY ProductCategoryID, Name;
GO

-- ====================================================================
-- Filtering date ranges (SARG pattern)
-- KEY CONCEPT: Use range predicates (col >= 'date' AND col < 'date')
-- instead of wrapping the column in a function (YEAR(col) = 2013).
-- Range predicates are SARGable (can use an index seek).
-- ====================================================================
-- EXPECTED: ~7k orders in 2013
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-01-01' AND OrderDate < '2014-01-01'
ORDER BY OrderDate;
GO

-- ====================================================================
-- LIKE pattern matching
-- KEY CONCEPT: LIKE with leading wildcard (%Bike%) may be slow.
-- Prefix patterns (Bike%) are faster when the column is indexed.
-- ====================================================================
-- Find stores with 'Bike' in the name
-- EXPECTED: ~150 stores
SELECT BusinessEntityID, Name
FROM Sales.Store
WHERE Name LIKE N'%Bike%'
ORDER BY Name;
GO

-- Products starting with 'HL' (prefix pattern — more efficient)
SELECT ProductID, Name, ListPrice
FROM Production.Product
WHERE Name LIKE N'HL%'
ORDER BY Name;
GO

-- ====================================================================
-- ORDER BY and TOP
-- KEY CONCEPT: TOP without ORDER BY returns arbitrary rows.
-- Always specify ORDER BY when using TOP for deterministic results.
-- ====================================================================
-- Top 5 most expensive products
SELECT TOP 5 Name, ListPrice
FROM Production.Product
WHERE ListPrice > 0
ORDER BY ListPrice DESC;
GO

-- ====================================================================
-- OFFSET-FETCH (pagination)
-- KEY CONCEPT: OFFSET skips N rows; FETCH NEXT returns M rows.
-- Works only with ORDER BY. This is the standard SQL pagination syntax.
-- ====================================================================
-- Products page 3 (rows 21-30), sorted by name
SELECT ProductID, Name, ListPrice
FROM Production.Product
ORDER BY Name
OFFSET 20 ROWS
FETCH NEXT 10 ROWS ONLY;
GO

-- ====================================================================
-- DISTINCT to eliminate duplicates
-- KEY CONCEPT: DISTINCT removes duplicate rows from the result.
-- It is NOT a substitute for proper GROUP BY (see Lab 05).
-- ====================================================================
-- How many different job titles exist?
SELECT DISTINCT JobTitle
FROM HumanResources.Employee
ORDER BY JobTitle;
GO

-- [OBSERVE] DISTINCT applies to ALL selected columns together.
-- SELECT DISTINCT City, StateProvinceID means unique city+state combos.

-- ====================================================================
-- WHERE with AND, OR, and parentheses
-- KEY CONCEPT: AND has higher precedence than OR. Use parentheses
-- to make the logic explicit and avoid subtle bugs.
-- ====================================================================
-- Products that are red OR black, AND have a list price > 100
SELECT ProductID, Name, Color, ListPrice
FROM Production.Product
WHERE (Color = N'Red' OR Color = N'Black')
  AND ListPrice > 100
ORDER BY ListPrice DESC;
GO

-- Products in specific size range
SELECT ProductID, Name, Size, ListPrice
FROM Production.Product
WHERE Size BETWEEN N'M' AND N'L'
ORDER BY Size;
GO

-- ====================================================================
-- NULL filtering
-- KEY CONCEPT: NULL = unknown. Use IS NULL / IS NOT NULL,
-- never = NULL or != NULL (those always return UNKNOWN).
-- ====================================================================
-- Products with a known color vs unknown color
SELECT COUNT(*) AS TotalProducts FROM Production.Product;
SELECT COUNT(*) AS WithColor FROM Production.Product WHERE Color IS NOT NULL;
SELECT COUNT(*) AS NoColor FROM Production.Product WHERE Color IS NULL;
GO

-- ====================================================================
-- CHECK YOURSELF:
-- 1. Write a query that returns products with "HL" in the product
--    number (not the name), sorted by ListPrice descending.
-- 2. Return the 10 most recent orders (by OrderDate).
-- 3. Find all people whose last name starts with 'S'.
-- 4. Use OFFSET-FETCH to return products 11-20 when sorted by Name.
-- ====================================================================
