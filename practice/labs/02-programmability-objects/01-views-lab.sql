-- =================================================================================
-- DP-800 - HANDS-ON LAB: VIEWS (SIMPLE, INDEXED, SCHEMABINDING AND CHECK OPTION)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/02-programmability-objects/01-views.md
--    Open the theory guide alongside this lab for conceptual context.
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates creating, optimizing, and integrity rules for Views in SQL Server:
--   1. Updatable Views and the WITH CHECK OPTION clause
--   2. Schema Integrity with WITH SCHEMABINDING
--   3. Indexed Views (Materialized Views) and the WITH (NOEXPAND) hint
--   4. Determinism Restrictions (blocking GETDATE, NEWID) in Indexed Views
--   5. View Limitations (ORDER BY and OUTER JOIN in indexed views)
--   6. Diagnosing common issues, SET options and best practices
--   7. Practical Project Scenarios (Optimized Dashboards and Security Layers)
-- =================================================================================

USE AdventureWorks2025;
GO

-- [DP-800 EXAM TIP] These seven options are required to create, maintain, and use
-- indexes on views. A connection with incompatible values may fail in DML or ignore
-- the view index in the execution plan.
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- Create an isolated schema so the lab does not alter AdventureWorks objects.
IF SCHEMA_ID(N'lab') IS NULL
    EXEC(N'CREATE SCHEMA lab');
GO

-- Preventive cleanup in case the script is run more than once
IF EXISTS (SELECT *
FROM sys.views
WHERE name = 'vw_OrderSummaryIndexed' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_OrderSummaryIndexed;
IF EXISTS (SELECT *
FROM sys.views
WHERE name = 'vw_OrderSummaryIndexed_BadCount' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_OrderSummaryIndexed_BadCount;
IF EXISTS (SELECT *
FROM sys.views
WHERE name = 'vw_ActiveCustomers' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_ActiveCustomers;
IF EXISTS (SELECT *
FROM sys.views
WHERE name = 'vw_BoundProducts' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_BoundProducts;
IF EXISTS (SELECT *
FROM sys.views
WHERE name = 'vw_NonDeterministicView' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_NonDeterministicView;
IF EXISTS (SELECT *
FROM sys.views
WHERE name = 'vw_OuterJoinIndexed' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_OuterJoinIndexed;
IF EXISTS (SELECT *
FROM sys.views
WHERE name = 'vw_NullableSumIndexed' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_NullableSumIndexed;
IF EXISTS (SELECT *
FROM sys.views
WHERE name = 'vw_InvalidOrderBy' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_InvalidOrderBy;
IF EXISTS (SELECT *
FROM sys.views
WHERE name = 'vw_DailyCustomerRevenueIndexed' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_DailyCustomerRevenueIndexed;
IF EXISTS (SELECT *
FROM sys.views
WHERE name = 'vw_ActiveCustomerRevenueIndexed' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_ActiveCustomerRevenueIndexed;

DROP TABLE IF EXISTS lab.Orders;
DROP TABLE IF EXISTS lab.NullableOrders;
DROP TABLE IF EXISTS lab.Customers;
DROP TABLE IF EXISTS lab.Products;
GO

-- Base tables for tests
CREATE TABLE lab.Customers
(
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    IsActive BIT NOT NULL DEFAULT 1
);

CREATE TABLE lab.Orders
(
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL,
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES lab.Customers(CustomerID)
);

CREATE TABLE lab.Products
(
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL
);
GO


-- =================================================================================
-- PART 1: UPDATABLE VIEWS AND THE WITH CHECK OPTION CLAUSE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - UPDATABLE VIEWS: Views that allow DML operations (INSERT, UPDATE, DELETE) reflected in the base table.
--     Each DML command must modify columns from only ONE base table and cannot contain aggregations,
--     DISTINCT, TOP or GROUP BY. A view with JOIN may still allow UPDATE of columns from a single table.
--   - WITH CHECK OPTION: Clause that prevents insertions or updates made through the view from violating
--     the view's filtering predicate (WHERE clause). Without it, an INSERT of a row that does not meet
--     the filter is written to the base table but "disappears" from the view's perspective (phantom rows).

-- 1. Create an Updatable View with WITH CHECK OPTION
CREATE VIEW lab.vw_ActiveCustomers
AS
    SELECT CustomerID, CustomerName, IsActive
    FROM lab.Customers
    WHERE IsActive = 1
WITH CHECK OPTION; -- Prevents DML for inactive customers through this view
GO

-- Insert active customer through the view (Success!)
INSERT INTO lab.vw_ActiveCustomers
    (CustomerName, IsActive)
VALUES
    ('Active Customer 1', 1);

-- DML through the view: UPDATE directly affects the lab.Customers table.
UPDATE lab.vw_ActiveCustomers
SET CustomerName = 'Active Customer 1 - Updated'
WHERE CustomerName = 'Active Customer 1';

SELECT CustomerID, CustomerName, IsActive
FROM lab.Customers
WHERE CustomerName = 'Active Customer 1 - Updated';

-- DML through the view: DELETE is also forwarded to the single base table.
INSERT INTO lab.vw_ActiveCustomers
    (CustomerName, IsActive)
VALUES
    ('Customer to Delete', 1);

DELETE FROM lab.vw_ActiveCustomers
WHERE CustomerName = 'Customer to Delete';

SELECT CustomerID, CustomerName
FROM lab.Customers
WHERE CustomerName = 'Customer to Delete';
-- Expected result: no rows.
GO

-- -- [DP-800 EXAM TIP]
-- Violation Test: Attempt to insert an INACTIVE customer (IsActive = 0) through the view
-- With WITH CHECK OPTION, the operation is immediately aborted with error 550.
BEGIN TRY
    INSERT INTO lab.vw_ActiveCustomers
    (CustomerName, IsActive)
VALUES
    ('Inactive Customer Attempt', 0);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR WITH CHECK OPTION: ' + ERROR_MESSAGE();
    -- Error: "The attempted insert or update failed because the target view specifies WITH CHECK OPTION..."
END CATCH;
GO


-- =================================================================================
-- PART 2: SCHEMA BINDING (WITH SCHEMABINDING)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - WITH SCHEMABINDING: Binds the view to the base tables. Prevents referenced tables or columns
--     from being altered or dropped via ALTER TABLE / DROP TABLE while the view exists.
--   - SCHEMABINDING REQUIREMENTS:
--     1. All referenced tables must use two-part names (e.g., `lab.Products`, not just `Products`).
--     2. Using `SELECT *` is expressly PROHIBITED (all columns must be declared).

CREATE VIEW lab.vw_BoundProducts
WITH
    SCHEMABINDING
AS
    SELECT ProductID, ProductName, UnitPrice
    FROM lab.Products;
GO

-- -- [DP-800 EXAM TIP]
-- DDL Protection Test: Attempt to remove the ProductName column from the base table Products
-- SQL Server blocks the change due to schema binding (error 3729).
BEGIN TRY
    ALTER TABLE lab.Products DROP COLUMN ProductName;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR SCHEMABINDING (DDL BLOCK): ' + ERROR_MESSAGE();
    -- Error: "Cannot DROP COLUMN 'ProductName' because it is being used by object 'vw_BoundProducts'..."
END CATCH;
GO


-- =================================================================================
-- PART 3: INDEXED VIEWS (MATERIALIZED VIEWS) AND THE WITH (NOEXPAND) HINT
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - INDEXED VIEW: A view whose result set is physically stored and updated on disk.
--     Transforms the virtual view into a physically materialized structure through an index.
--   - MANDATORY REQUIREMENTS TO INDEX A VIEW:
--     1. Must be created with `WITH SCHEMABINDING`.
--     2. The FIRST index created on the view MUST be a `UNIQUE CLUSTERED INDEX`.
--     3. In queries with `GROUP BY`, the `COUNT_BIG(*)` aggregate function is mandatory.
--     4. OUTER JOINs, CTEs, subqueries, DISTINCT, TOP or non-deterministic functions are prohibited.
--   - WITH (NOEXPAND) HINT: In SQL Server Standard, forces direct querying of the indexed view.
--     In Azure SQL Database and Azure SQL Managed Instance, the optimizer can use indexed views automatically;
--     the hint remains useful when you want to demonstrate or require direct access to the materialized index.

-- [DP-800 EXAM TIP] EXPECTED ERROR: COUNT(*) cannot be used in an
-- indexed view with GROUP BY. We create the incorrect version only to observe the failure.
CREATE VIEW lab.vw_OrderSummaryIndexed_BadCount
WITH
    SCHEMABINDING
AS
    SELECT
        CustomerID,
        COUNT(*) AS TotalOrders,
        SUM(TotalAmount) AS TotalSpent
    FROM lab.Orders
    GROUP BY CustomerID;
GO

BEGIN TRY
    CREATE UNIQUE CLUSTERED INDEX CIX_vw_OrderSummaryIndexed_BadCount
    ON lab.vw_OrderSummaryIndexed_BadCount(CustomerID);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR COUNT_BIG: ' + ERROR_MESSAGE();
    -- The message states that COUNT_BIG must replace COUNT in a grouped indexed view.
END CATCH;
GO

DROP VIEW lab.vw_OrderSummaryIndexed_BadCount;
GO

-- 1. Create the correct View with Schemabinding and COUNT_BIG(*)
CREATE VIEW lab.vw_OrderSummaryIndexed
WITH
    SCHEMABINDING
AS
    SELECT
        CustomerID,
        COUNT_BIG(*) AS TotalOrders,
        SUM(TotalAmount) AS TotalSpent
    FROM lab.Orders
    GROUP BY CustomerID;
GO

-- Populate data to materialize
INSERT INTO lab.Customers
    (CustomerName, IsActive)
VALUES
    ('Customer A', 1),
    ('Customer B', 1);
INSERT INTO lab.Orders
    (CustomerID, OrderDate, TotalAmount)
VALUES
    (1, '2025-01-01', 500.00),
    (1, '2025-01-02', 300.00);
GO

-- 2. Materialize the View by creating the UNIQUE CLUSTERED INDEX (Mandatory requirement)
CREATE UNIQUE CLUSTERED INDEX CIX_vw_OrderSummaryIndexed
ON lab.vw_OrderSummaryIndexed(CustomerID);
GO

-- Confirm that the unique clustered index materialized the view result.
SELECT name, type_desc, is_unique
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'lab.vw_OrderSummaryIndexed');
GO

-- [DP-800 EXAM TIP] The indexed view does not become stale after DML:
-- SQL Server maintains its index during base table changes.
INSERT INTO lab.Orders
    (CustomerID, OrderDate, TotalAmount)
VALUES
    (1, '2025-01-03', 50.00);
GO

SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_OrderSummaryIndexed
WHERE CustomerID = 1;
-- Expected result: TotalOrders = 3 and TotalSpent = 850.00.
GO

-- -- [DP-800 EXAM TIP]
-- 3. Query with the WITH (NOEXPAND) hint. Enable the Actual Execution Plan (Ctrl + M)
-- and compare this query with the identical query without the hint just below.
-- In SQL Server Standard, NOEXPAND is required to query the view index directly.
-- In Azure SQL Database and Azure SQL Managed Instance, the optimizer can use the view automatically.
SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_OrderSummaryIndexed WITH (NOEXPAND)
WHERE CustomerID = 1;
GO

SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_OrderSummaryIndexed
WHERE CustomerID = 1;
GO


-- =================================================================================
-- PART 4: VIEW AND INDEXED VIEW LIMITATIONS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - ORDER BY does not define the ordering of a view; the outer query must contain ORDER BY.
--   - An indexed view cannot contain OUTER JOIN, CTE, subquery, DISTINCT, TOP, APPLY or self-join.
--   - Regular views may have JOINs, but INSERT and DELETE are not allowed when there is more than one base table.

-- [DP-800 EXAM TIP] ORDER BY without TOP in a regular view definition fails.
-- We use dynamic SQL because CREATE VIEW must be the first statement in the batch.
BEGIN TRY
    EXEC(N'
        CREATE VIEW lab.vw_InvalidOrderBy
        AS
        SELECT CustomerID, CustomerName
        FROM lab.Customers
        ORDER BY CustomerName;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR ORDER BY IN VIEW: ' + ERROR_MESSAGE();
END CATCH;
GO

-- OUTER JOIN can exist in a regular view but prevents creating an index on the view.
CREATE VIEW lab.vw_OuterJoinIndexed
WITH
    SCHEMABINDING
AS
    SELECT
        c.CustomerID,
        c.CustomerName,
        o.OrderID
    FROM lab.Customers AS c
        LEFT JOIN lab.Orders AS o
        ON o.CustomerID = c.CustomerID;
GO

BEGIN TRY
    CREATE UNIQUE CLUSTERED INDEX CIX_vw_OuterJoinIndexed
    ON lab.vw_OuterJoinIndexed(CustomerID, OrderID);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR OUTER JOIN IN INDEXED VIEW: ' + ERROR_MESSAGE();
END CATCH;
GO

DROP VIEW lab.vw_OuterJoinIndexed;
GO


-- =================================================================================
-- PART 5: DETERMINISM RESTRICTIONS IN INDEXED VIEWS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DETERMINISM: Deterministic functions always return the same value for the same parameters (e.g., `ROUND`, `DATEADD`).
--   - NON-DETERMINISM: Functions like `GETDATE()`, `NEWID()`, `RAND()` vary on each execution.
--   - SQL Server prohibits creating indexes on views that contain non-deterministic functions.

CREATE VIEW lab.vw_NonDeterministicView
WITH
    SCHEMABINDING
AS
    SELECT CustomerID, CustomerName, GETDATE() AS QueryDate
    FROM lab.Customers;
GO

-- -- [DP-800 EXAM TIP]
-- Attempt to index view with GETDATE() -> Index creation fails (Error 2601/1949)
BEGIN TRY
    CREATE UNIQUE CLUSTERED INDEX CIX_vw_NonDeterministicView
    ON lab.vw_NonDeterministicView(CustomerID);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR NON-DETERMINISM (GETDATE): ' + ERROR_MESSAGE();
    -- Error: "Cannot create index on view... because it uses non-deterministic function 'GETDATE'..."
END CATCH;
GO


-- =================================================================================
-- PART 6: SET OPTIONS, COMMON ISSUES AND BEST PRACTICES
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - The six ANSI/arithmetic options must be ON and NUMERIC_ROUNDABORT must be OFF.
--   - A SUM of a nullable expression cannot be used in an indexed view definition.
--   - Use the sys.views and sys.indexes catalog views to confirm schema binding and materialization.

-- 1. Check the effective SET options of the session before creating/maintaining indexed views.
SELECT
    SESSIONPROPERTY(N'ANSI_NULLS') AS ANSI_NULLS,
    SESSIONPROPERTY(N'ANSI_PADDING') AS ANSI_PADDING,
    SESSIONPROPERTY(N'ANSI_WARNINGS') AS ANSI_WARNINGS,
    SESSIONPROPERTY(N'ARITHABORT') AS ARITHABORT,
    SESSIONPROPERTY(N'CONCAT_NULL_YIELDS_NULL') AS CONCAT_NULL_YIELDS_NULL,
    SESSIONPROPERTY(N'QUOTED_IDENTIFIER') AS QUOTED_IDENTIFIER,
    SESSIONPROPERTY(N'NUMERIC_ROUNDABORT') AS NUMERIC_ROUNDABORT;
-- Expected result: the first six values are 1; NUMERIC_ROUNDABORT is 0.
GO

-- [DP-800 EXAM TIP] Changing a required option blocks DML on the participating table.
SET NUMERIC_ROUNDABORT ON;
GO

BEGIN TRY
    INSERT INTO lab.Orders
    (CustomerID, OrderDate, TotalAmount)
VALUES
    (1, '2025-01-04', 1.00);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR SET OPTION: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Restore the option immediately so subsequent commands and re-executions work.
SET NUMERIC_ROUNDABORT OFF;
GO

-- 2. SUM on a nullable column prevents creating the index on the view.
CREATE TABLE lab.NullableOrders
(
    NullableOrderID INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_NullableOrders PRIMARY KEY,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2) NULL
);
GO

INSERT INTO lab.NullableOrders
    (CustomerID, TotalAmount)
VALUES
    (1, 10.00),
    (1, NULL);
GO

CREATE VIEW lab.vw_NullableSumIndexed
WITH
    SCHEMABINDING
AS
    SELECT
        CustomerID,
        COUNT_BIG(*) AS TotalOrders,
        SUM(TotalAmount) AS TotalSpent
    FROM lab.NullableOrders
    GROUP BY CustomerID;
GO

BEGIN TRY
    CREATE UNIQUE CLUSTERED INDEX CIX_vw_NullableSumIndexed
    ON lab.vw_NullableSumIndexed(CustomerID);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR NULLABLE SUM: ' + ERROR_MESSAGE();
    -- Fix, when NULL represents zero: SUM(ISNULL(TotalAmount, 0)).
END CATCH;
GO

DROP VIEW lab.vw_NullableSumIndexed;
DROP TABLE lab.NullableOrders;
GO

-- 3. Diagnosis: confirm the schema binding best practice and the materialized index.
SELECT
    s.name AS SchemaName,
    v.name AS ViewName,
    OBJECTPROPERTYEX(v.object_id, N'IsSchemaBound') AS IsSchemaBound,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique
FROM sys.views AS v
    JOIN sys.schemas AS s
    ON s.schema_id = v.schema_id
    LEFT JOIN sys.indexes AS i
    ON i.object_id = v.object_id
        AND i.index_id > 0
WHERE v.object_id IN
(
    OBJECT_ID(N'lab.vw_BoundProducts'),
    OBJECT_ID(N'lab.vw_OrderSummaryIndexed')
)
ORDER BY v.name, i.index_id;
GO


-- =================================================================================
-- PART 7: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

-- An indexed view makes a difference when the SAME aggregation/join is read frequently,
-- the base tables are large, and the additional cost of every INSERT/UPDATE/DELETE is acceptable.
-- It does not "eliminate" query time: it trades some read processing for disk space and
-- synchronous maintenance work during DML on the base tables.

-- SCENARIO 1: Executive e-commerce dashboard ranking
-- Problem: every dashboard refresh scans sales to calculate the total per customer. With
-- millions of orders, the GROUP BY competes for CPU and logical reads.
-- Why the view helps: the total per customer is already calculated in the clustered index
-- of vw_OrderSummaryIndexed, so the query reads only the materialized groups.
-- Good fit: many dashboard reads and a moderate volume of changes.
SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_OrderSummaryIndexed WITH (NOEXPAND)
WHERE TotalSpent > 100.00
ORDER BY TotalSpent DESC;
GO

-- Compare the execution plan with the aggregation performed on the base table. In a real
-- workload, expect the second query to process all qualifying rows in lab.Orders, while
-- the first seeks the view index. The results must be identical.
SET STATISTICS IO, TIME ON;
GO

SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_OrderSummaryIndexed WITH (NOEXPAND)
WHERE TotalSpent > 100.00;

SELECT CustomerID, COUNT_BIG(*) AS TotalOrders, SUM(TotalAmount) AS TotalSpent
FROM lab.Orders
GROUP BY CustomerID
HAVING SUM(TotalAmount) > 100.00;
GO

SET STATISTICS IO, TIME OFF;
GO

-- SCENARIO 2: Intraday monitoring of customer revenue and volume
-- Problem: an operations center refreshes cards such as "today's revenue", "order count",
-- and sales-drop alerts every few seconds.
-- Why the view helps: the same customer-and-date aggregation is no longer recalculated
-- repeatedly. The index can directly locate a day and a customer.
-- Good fit: read-intensive dashboards where there are fewer order changes than indicator reads.
CREATE VIEW lab.vw_DailyCustomerRevenueIndexed
WITH SCHEMABINDING
AS
    SELECT
        o.CustomerID,
        o.OrderDate,
        COUNT_BIG(*) AS TotalOrders,
        SUM(o.TotalAmount) AS DailyRevenue
    FROM lab.Orders AS o
    GROUP BY o.CustomerID, o.OrderDate;
GO

CREATE UNIQUE CLUSTERED INDEX CIX_vw_DailyCustomerRevenueIndexed
ON lab.vw_DailyCustomerRevenueIndexed(CustomerID, OrderDate);
GO

-- This query is typical of an endpoint that feeds a dashboard card.
SELECT CustomerID, OrderDate, TotalOrders, DailyRevenue
FROM lab.vw_DailyCustomerRevenueIndexed WITH (NOEXPAND)
WHERE CustomerID = 1
  AND OrderDate >= '2025-01-01'
  AND OrderDate < '2025-02-01'
ORDER BY OrderDate;
GO

-- SCENARIO 3: Active-customer segmentation for CRM and customer service
-- Problem: several services continuously query active customers' spend and purchase count.
-- The original query joins Customers to Orders and then aggregates.
-- Why the view helps: it materializes both the INNER JOIN and aggregation. A change to
-- IsActive or to an order automatically updates the result.
-- Good fit: few status changes and many reads for segments and rankings.
CREATE VIEW lab.vw_ActiveCustomerRevenueIndexed
WITH SCHEMABINDING
AS
    SELECT
        c.CustomerID,
        COUNT_BIG(*) AS TotalOrders,
        SUM(o.TotalAmount) AS TotalSpent
    FROM lab.Customers AS c
    INNER JOIN lab.Orders AS o
        ON o.CustomerID = c.CustomerID
    WHERE c.IsActive = 1
    GROUP BY c.CustomerID;
GO

CREATE UNIQUE CLUSTERED INDEX CIX_vw_ActiveCustomerRevenueIndexed
ON lab.vw_ActiveCustomerRevenueIndexed(CustomerID);
GO

-- Example: campaign for active customers with high cumulative value.
SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_ActiveCustomerRevenueIndexed WITH (NOEXPAND)
WHERE TotalSpent >= 500.00
ORDER BY TotalSpent DESC;
GO

-- SCENARIO 4: When NOT to use an indexed view
-- An administrative screen queried once per day, or an orders table receiving many
-- INSERTs/UPDATEs per second, usually does not justify the view-index maintenance cost.
-- Every DML operation on lab.Orders makes SQL Server maintain:
--   * CIX_vw_OrderSummaryIndexed;
--   * CIX_vw_DailyCustomerRevenueIndexed; and
--   * CIX_vw_ActiveCustomerRevenueIndexed.
-- In these cases, first consider indexes on base tables, application caching, a batch-updated
-- summary table, or a separate analytics solution. Always validate with an actual plan and
-- SET STATISTICS IO, TIME, comparing saved reads with added write latency.

-- DECISION SUMMARY
-- Use case                                  | Is an indexed view usually suitable?
-- Dashboard with repeated aggregation       | Yes: pre-calculates GROUP BY/SUM/COUNT_BIG.
-- Frequent join + aggregation query         | Yes: when it meets definition restrictions.
-- Occasional report                          | Usually no: maintenance cost predominates.
-- Write-intensive OLTP                      | Usually no: every DML maintains all indexes.
-- OUTER JOIN, TOP, or GETDATE() logic       | No: it cannot compose an indexed view.
GO

-- =================================================================================
-- MAINTENANCE AND CLEANUP (OPTIONAL)
-- =================================================================================
/*
DROP VIEW IF EXISTS lab.vw_NonDeterministicView;
DROP VIEW IF EXISTS lab.vw_ActiveCustomerRevenueIndexed;
DROP VIEW IF EXISTS lab.vw_DailyCustomerRevenueIndexed;
DROP VIEW IF EXISTS lab.vw_OrderSummaryIndexed;
DROP VIEW IF EXISTS lab.vw_ActiveCustomers;
DROP VIEW IF EXISTS lab.vw_BoundProducts;
DROP TABLE IF EXISTS lab.Orders;
DROP TABLE IF EXISTS lab.Customers;
DROP TABLE IF EXISTS lab.Products;
*/


-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/02-programmability-objects/01-views.md
-- =================================================================================================

-- =================================================================================================
-- OFFICIAL MICROSOFT LEARN REFERENCES
-- =================================================================================================
-- CREATE VIEW, updatable views and WITH CHECK OPTION:
-- https://learn.microsoft.com/en-us/sql/t-sql/statements/create-view-transact-sql?view=sql-server-ver17
-- Indexed views, SCHEMABINDING, required SET options and NOEXPAND:
-- https://learn.microsoft.com/en-us/sql/relational-databases/views/create-indexed-views?view=sql-server-ver17
-- CREATE INDEX syntax and index options:
-- https://learn.microsoft.com/en-us/sql/t-sql/statements/create-index-transact-sql?view=sql-server-ver17
