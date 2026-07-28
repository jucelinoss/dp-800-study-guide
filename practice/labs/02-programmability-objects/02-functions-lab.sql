-- =================================================================================
-- DP-800 - HANDS-ON LAB: SCALAR AND TABLE-VALUED FUNCTIONS (UDFs, iTVF, mTVF AND APPLY)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/02-programmability-objects/02-functions.md
--    Open the theory guide alongside this lab for conceptual context.
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates implementing and optimizing functions in SQL Server:
--   1. Scalar UDFs and Inlining verification (sys.sql_modules)
--   2. Inline Table-Valued Functions (iTVF) vs Multi-Statement TVFs (mTVF)
--   3. Performance Impact and Cardinality (Optimizer Visibility)
--   4. CROSS APPLY and OUTER APPLY Operators with Table Functions
--   5. Schemabinding and Determinism Testing via OBJECTPROPERTY
--   6. Million-row benchmark: iTVF + CROSS APPLY, mTVF, and Scalar UDF
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_FormatCustomerName' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_FormatCustomerName;
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_GetCustomerOrdersInline' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_GetCustomerOrdersInline;
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_GetCustomerOrdersMultiStatement' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_GetCustomerOrdersMultiStatement;
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_GetCustomerLifetimeTotalScalar' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_GetCustomerLifetimeTotalScalar;

DROP TABLE IF EXISTS lab.OrderItems;
DROP TABLE IF EXISTS lab.Orders;
DROP TABLE IF EXISTS lab.Customers;
GO

-- Table Structure for Testing
CREATE TABLE lab.Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL
);

CREATE TABLE lab.Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    Status NVARCHAR(20) NOT NULL DEFAULT 'Active'
);

CREATE TABLE lab.OrderItems (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductName NVARCHAR(100) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL
);
GO


-- =================================================================================
-- PART 1: SCALAR FUNCTIONS AND INLINING VERIFICATION
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - SCALAR FUNCTION: Returns a single value. Historically forces RBAR (Row-By-Agonizing-Row)
--     execution row by row, preventing query parallelization.
--   - SCALAR UDF INLINING (SQL Server 2019+): Intelligent Query Processing feature that converts
--     certain scalar functions into inline relational expressions at compile time.

-- 1. Create a Scalar Function with SCHEMABINDING
CREATE FUNCTION lab.fn_FormatCustomerName (
    @FirstName NVARCHAR(50),
    @LastName NVARCHAR(50)
)
RETURNS NVARCHAR(105)
WITH SCHEMABINDING
AS
BEGIN
    RETURN UPPER(LTRIM(RTRIM(@LastName))) + ', ' + LTRIM(RTRIM(@FirstName));
END;
GO

-- -- [DP-800 EXAM TIP]
-- Verifying inlining eligibility via sys.sql_modules (SQL Server 2019+).
-- is_inlineable = 1 means the definition is eligible; the optimizer still decides per query
-- whether to inline. To confirm, examine the XML plan: an inlined UDF does not
-- have the <UserDefinedFunction> node.
SELECT 
    name,
    OBJECTPROPERTY(object_id, 'IsDeterministic') AS IsDeterministic,
    sm.is_inlineable
FROM sys.objects o
JOIN sys.sql_modules sm ON o.object_id = sm.object_id
WHERE o.name = 'fn_FormatCustomerName';
GO


-- =================================================================================
-- PART 2: INLINE TVF (iTVF) VS MULTI-STATEMENT TVF (mTVF)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - INLINE TVF (iTVF): Returns the result of a single `SELECT`. Transparent to the optimizer,
--     which expands it as a Parameterized View, enabling accurate statistics and parallel execution.
--   - MULTI-STATEMENT TVF (mTVF): Explicitly populates a table variable (`@Result TABLE`) in multiple steps.
--     Remains less transparent to the optimizer. Starting with SQL Server 2017 at compatibility level 140,
--     interleaved execution can pause optimization, execute the mTVF, and use its actual row count to
--     optimize downstream operators (for example, JOINs and memory grants). It requires an eligible query,
--     does not turn the function into an iTVF, and does not eliminate all of its costs.

-- 1. Create Inline TVF (Recommended for Performance)
CREATE FUNCTION lab.fn_GetCustomerOrdersInline (@CustomerID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
    SELECT 
        o.OrderID,
        o.OrderDate,
        o.Status,
        SUM(oi.Quantity * oi.UnitPrice) AS TotalAmount
    FROM lab.Orders o
    JOIN lab.OrderItems oi ON o.OrderID = oi.OrderID
    WHERE o.CustomerID = @CustomerID
    GROUP BY o.OrderID, o.OrderDate, o.Status
);
GO

-- 2. Create Multi-Statement TVF (Black Box for the Optimizer)
CREATE FUNCTION lab.fn_GetCustomerOrdersMultiStatement (@CustomerID INT)
RETURNS @Result TABLE (
    OrderID INT,
    OrderDate DATE,
    Status NVARCHAR(20),
    TotalAmount DECIMAL(18,2)
)
AS
BEGIN
    INSERT INTO @Result
    SELECT 
        o.OrderID,
        o.OrderDate,
        o.Status,
        SUM(oi.Quantity * oi.UnitPrice)
    FROM lab.Orders o
    JOIN lab.OrderItems oi ON o.OrderID = oi.OrderID
    WHERE o.CustomerID = @CustomerID
    GROUP BY o.OrderID, o.OrderDate, o.Status;
    
    RETURN;
END;
GO

-- 3. Prepare data to compare both functions with the same calling query.
-- Charlie intentionally has no orders; this will also be used in the APPLY demonstration.
INSERT INTO lab.Customers (FirstName, LastName)
VALUES ('Alice', 'Smith'), ('Bob', 'Jones'), ('Charlie', 'Brown');
INSERT INTO lab.Orders (CustomerID, OrderDate)
VALUES (1, '2025-01-10');
INSERT INTO lab.OrderItems (OrderID, ProductName, Quantity, UnitPrice)
VALUES (1, 'Keyboard', 1, 150.00);
GO

-- 4. Didactic performance comparison: enable Actual Execution Plan (Ctrl+M).
-- Both queries return the same result. The iTVF is expanded in the plan; the mTVF
-- returns a materialized table. At compatibility level 140+ with an eligible query,
-- the mTVF may have its estimate revised through interleaved execution without exposing its logic.
SELECT c.CustomerID, c.FirstName, fn.OrderID, fn.TotalAmount
FROM lab.Customers AS c
OUTER APPLY lab.fn_GetCustomerOrdersInline(c.CustomerID) AS fn;
GO

SELECT c.CustomerID, c.FirstName, fn.OrderID, fn.TotalAmount
FROM lab.Customers AS c
OUTER APPLY lab.fn_GetCustomerOrdersMultiStatement(c.CustomerID) AS fn;
GO


-- =================================================================================
-- PART 3: APPLY OPERATORS (CROSS APPLY VS OUTER APPLY)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CROSS APPLY: Works like an `INNER JOIN`. Executes the table function for each row of the
--     left table and returns only rows where the function produced at least one result.
--   - OUTER APPLY: Works like a `LEFT JOIN`. Returns all rows from the left table,
--     padding with NULL in the function fields when it returns no rows.

-- -- [DP-800 EXAM TIP]
-- CROSS APPLY: Charlie has no orders, therefore DOES NOT APPEAR in the result
SELECT c.CustomerID, c.FirstName, fn.OrderID, fn.TotalAmount
FROM lab.Customers c
CROSS APPLY lab.fn_GetCustomerOrdersInline(c.CustomerID) fn;

-- OUTER APPLY: Charlie APPEARS in the result with null fields (preserves the parent row)
SELECT c.CustomerID, c.FirstName, fn.OrderID, fn.TotalAmount
FROM lab.Customers c
OUTER APPLY lab.fn_GetCustomerOrdersInline(c.CustomerID) fn;
GO


-- =================================================================================
-- PART 4: SCHEMABINDING AND DETERMINISM TESTING VIA OBJECTPROPERTY
-- =================================================================================

-- Testing determinism verification with OBJECTPROPERTY
SELECT 
    OBJECTPROPERTY(OBJECT_ID('lab.fn_FormatCustomerName'), 'IsDeterministic') AS IsDeterministic;
GO


-- =================================================================================
-- PART 5: PRACTICAL DESIGN SCENARIOS
-- =================================================================================

-- SCENARIO 1: High-volume benchmark — iTVF + CROSS APPLY vs. mTVF and Scalar UDF
-- Goal: compare three ways to calculate order totals with the SAME result:
--   A. Recommended: iTVF with CROSS APPLY. The internal logic participates in the calling plan.
--   B. Avoid at high volume: mTVF with CROSS APPLY. The function is invoked per customer and
--      materializes a table variable; the outer plan cannot see its internal logic.
--   C. Avoid for set-based queries: non-inlined Scalar UDF, executed once per customer.
--
-- WARNING: the default configuration inserts approximately 1,000,000 orders and 2,000,000
-- items. Adjust the two variables if the environment has limited disk space, transaction log,
-- or CPU time. Run this only in a lab database; the script deletes lab objects at the beginning.

DECLARE @BenchmarkCustomerCount INT = 100000;
DECLARE @OrdersPerCustomer INT = 10;
DECLARE @FirstBenchmarkCustomerID INT = CONVERT(INT, IDENT_CURRENT(N'lab.Customers')) + 1;

-- Generate customers in a set-based manner. sys.all_objects is used only as a number source.
;WITH Numbers AS
(
    SELECT TOP (@BenchmarkCustomerCount)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Number
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
)
INSERT INTO lab.Customers (FirstName, LastName)
SELECT
    CONCAT(N'Customer', Number),
    CONCAT(N'Benchmark', Number)
FROM Numbers;

-- Every new customer receives @OrdersPerCustomer orders: 100,000 x 10 = 1,000,000 by default.
INSERT INTO lab.Orders (CustomerID, OrderDate, Status)
SELECT
    c.CustomerID,
    DATEADD(DAY, -((c.CustomerID * @OrdersPerCustomer + n.OrderSequence) % 730), CONVERT(DATE, '2025-12-31')),
    N'Active'
FROM lab.Customers AS c
CROSS JOIN
(
    SELECT TOP (@OrdersPerCustomer)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS OrderSequence
    FROM sys.all_objects
) AS n
WHERE c.CustomerID >= @FirstBenchmarkCustomerID;

-- Two items per order: 2,000,000 items with the default configuration.
INSERT INTO lab.OrderItems (OrderID, ProductName, Quantity, UnitPrice)
SELECT
    o.OrderID,
    CONCAT(N'Product ', i.ItemSequence),
    i.ItemSequence,
    CONVERT(DECIMAL(18,2), 10.00 * i.ItemSequence)
FROM lab.Orders AS o
CROSS JOIN (VALUES (1), (2)) AS i(ItemSequence)
WHERE o.CustomerID >= @FirstBenchmarkCustomerID;
GO

-- Indexes aligned with the predicates and joins in the TVFs. Create them AFTER the load
-- to avoid maintaining indexes during the millions of INSERT operations.
CREATE INDEX IX_Orders_CustomerID_OrderID
ON lab.Orders (CustomerID, OrderID)
INCLUDE (OrderDate, Status);

CREATE INDEX IX_OrderItems_OrderID
ON lab.OrderItems (OrderID)
INCLUDE (Quantity, UnitPrice);
GO

-- Update statistics so the expanded iTVF has representative information.
UPDATE STATISTICS lab.Orders IX_Orders_CustomerID_OrderID;
UPDATE STATISTICS lab.OrderItems IX_OrderItems_OrderID;

SELECT
    (SELECT COUNT_BIG(*) FROM lab.Customers) AS Customers,
    (SELECT COUNT_BIG(*) FROM lab.Orders) AS Orders,
    (SELECT COUNT_BIG(*) FROM lab.OrderItems) AS OrderItems;
GO

-- Intentionally non-inlined Scalar UDF: used only to demonstrate RBAR cost.
-- INLINE = OFF requires SQL Server 2019+; remove the option only on an earlier version.
CREATE FUNCTION lab.fn_GetCustomerLifetimeTotalScalar (@CustomerID INT)
RETURNS DECIMAL(38,2)
WITH SCHEMABINDING, INLINE = OFF
AS
BEGIN
    DECLARE @Total DECIMAL(38,2);

    SELECT @Total = SUM(oi.Quantity * oi.UnitPrice)
    FROM lab.Orders AS o
    INNER JOIN lab.OrderItems AS oi
        ON oi.OrderID = o.OrderID
    WHERE o.CustomerID = @CustomerID;

    RETURN @Total;
END;
GO

-- Enable Actual Execution Plan (Ctrl+M). Run each query at least twice and alternate their
-- order between executions: the first run includes cache warm-up. Compare:
--   * CPU and logical reads in STATISTICS IO/TIME messages;
--   * estimated versus actual rows; and
--   * the presence of Table-valued function / UserDefinedFunction in the plan.
-- Each query returns only ONE summary row, so transferring 100,000 rows to SSMS does not
-- obscure database cost. A and B must return the same order count and total.
SET STATISTICS IO, TIME ON;
GO

-- PHASE 1 — PRIMARY COMPARISON: iTVF vs. mTVF with approximately 1 million orders.
-- A. RECOMMENDED: the iTVF is expanded and the optimizer can choose a plan for the entire set.
SELECT
    COUNT_BIG(*) AS OrdersReturned,
    SUM(ord.TotalAmount) AS GrandTotal
FROM lab.Customers AS c
CROSS APPLY lab.fn_GetCustomerOrdersInline(c.CustomerID) AS ord
WHERE c.CustomerID >= 4
OPTION (RECOMPILE);
GO

-- B. NOT RECOMMENDED AT HIGH VOLUME: same result, but an mTVF is called for every customer.
-- In the plan, observe the estimate of the Table-valued function operator and its execution count.
SELECT
    COUNT_BIG(*) AS OrdersReturned,
    SUM(ord.TotalAmount) AS GrandTotal
FROM lab.Customers AS c
CROSS APPLY lab.fn_GetCustomerOrdersMultiStatement(c.CustomerID) AS ord
WHERE c.CustomerID >= 4
OPTION (RECOMPILE);
GO

-- PHASE 2 — ADDITIONAL REFERENCE: non-inlined Scalar UDF in RBAR mode.
-- C. Same GrandTotal, but the scalar function is invoked once for each new customer.
SELECT
    COUNT_BIG(*) AS CustomersProcessed,
    SUM(lab.fn_GetCustomerLifetimeTotalScalar(c.CustomerID)) AS GrandTotal
FROM lab.Customers AS c
WHERE c.CustomerID >= 4
OPTION (RECOMPILE);
GO

SET STATISTICS IO, TIME OFF;
GO


-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/02-programmability-objects/02-functions.md
-- =================================================================================================

-- =================================================================================================
-- OFFICIAL MICROSOFT LEARN REFERENCES
-- =================================================================================================
-- CREATE FUNCTION, scalar UDFs, inline TVFs, multi-statement TVFs and SCHEMABINDING:
-- https://learn.microsoft.com/en-us/sql/t-sql/statements/create-function-transact-sql?view=sql-server-ver17
-- Scalar UDF inlining and plan verification:
-- https://learn.microsoft.com/en-us/sql/relational-databases/user-defined-functions/scalar-udf-inlining?view=sql-server-ver17
-- Interleaved execution for multi-statement TVFs:
-- https://learn.microsoft.com/en-us/sql/relational-databases/performance/intelligent-query-processing-details?view=sql-server-ver17
-- APPLY operators:
-- https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql?view=sql-server-ver17
