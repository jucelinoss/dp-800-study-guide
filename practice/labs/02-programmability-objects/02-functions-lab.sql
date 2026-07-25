-- =================================================================================
-- DP-800 - HANDS-ON LAB: SCALAR AND TABLE-VALUED FUNCTIONS (UDFs, iTVF, mTVF AND APPLY)
-- Database: AdventureWorks2025 (or similar)
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
--   6. Practical Design Scenarios (Inline Discount Calculation and Hierarchical Reports)
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
--     Remains less transparent to the optimizer. In SQL Server 2025, eligible read-only queries
--     can use interleaved execution to review the estimate after materializing the mTVF; this does not transform
--     the function into an iTVF nor eliminate all its costs.

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


-- =================================================================================
-- PART 3: APPLY OPERATORS (CROSS APPLY VS OUTER APPLY)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CROSS APPLY: Works like an `INNER JOIN`. Executes the table function for each row of the
--     left table and returns only rows where the function produced at least one result.
--   - OUTER APPLY: Works like a `LEFT JOIN`. Returns all rows from the left table,
--     padding with NULL in the function fields when it returns no rows.

-- Insert test data
INSERT INTO lab.Customers (FirstName, LastName) VALUES ('Alice', 'Smith'), ('Bob', 'Jones'), ('Charlie', 'Brown');
INSERT INTO lab.Orders (CustomerID, OrderDate) VALUES (1, '2025-01-10');
INSERT INTO lab.OrderItems (OrderID, ProductName, Quantity, UnitPrice) VALUES (1, 'Teclado', 1, 150.00);
GO

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

-- Didactic comparison: enable Actual Execution Plan (Ctrl+M) and compare iTVF vs mTVF.
-- The iTVF is expanded inline; the mTVF returns a materialized table. In SQL Server 2025,
-- a read-only query may show interleaved execution and revised estimate for the mTVF.
SELECT c.CustomerID, c.FirstName, fn.OrderID, fn.TotalAmount
FROM lab.Customers AS c
OUTER APPLY lab.fn_GetCustomerOrdersMultiStatement(c.CustomerID) AS fn;
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

--- SCENARIO 1: Inline Progressive Discount Calculation in Sales Report
-- Instead of calling a scalar function inside SELECT over millions of rows,
-- use an Inline TVF combined with CROSS APPLY for ideal performance.

SELECT 
    c.CustomerID,
    lab.fn_FormatCustomerName(c.FirstName, c.LastName) AS CustomerNameFormatted,
    ord.OrderID,
    ord.TotalAmount
FROM lab.Customers c
CROSS APPLY lab.fn_GetCustomerOrdersInline(c.CustomerID) ord;
GO
