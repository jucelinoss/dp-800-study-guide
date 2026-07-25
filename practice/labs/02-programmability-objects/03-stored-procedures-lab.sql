-- =================================================================================
-- DP-800 - HANDS-ON LAB: STORED PROCEDURES (sp_executesql, OUTPUT, TVP, TRY/CATCH AND EXECUTE AS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates creating, parameterizing, and error handling in Stored Procedures:
--   1. OUTPUT Parameters and Table-Valued Parameters (TVP)
--   2. Secure Dynamic SQL: sp_executesql vs EXEC(@sql) (SQL Injection and Plan Reuse)
--   3. Advanced Error Handling and Transactions (TRY/CATCH, THROW and XACT_STATE)
--   4. Parameter Sniffing and Recompilation (OPTION (OPTIMIZE FOR UNKNOWN) and WITH RECOMPILE)
--   5. Security Context (EXECUTE AS OWNER / CALLER)
--   6. Practical Project Scenarios (Batch Order Processing with Protected Transactions)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_CreateOrderWithOutput' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_CreateOrderWithOutput;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ProcessOrderBatch' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_ProcessOrderBatch;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SearchOrdersDynamic' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_SearchOrdersDynamic;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SafeTransactionTransfer' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_SafeTransactionTransfer;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SearchOrdersRecompile' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_SearchOrdersRecompile;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ReadOrdersAsOwner' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_ReadOrdersAsOwner;

IF EXISTS (SELECT * FROM sys.types WHERE name = 'OrderItemTableType' AND schema_id = SCHEMA_ID('lab'))
    DROP TYPE lab.OrderItemTableType;

DROP TABLE IF EXISTS lab.BankAccounts;
DROP TABLE IF EXISTS lab.OrderItems;
DROP TABLE IF EXISTS lab.Orders;
GO

-- Table Structure for Testing
CREATE TABLE lab.Orders (
    OrderID INT IDENTITY(1000,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    TotalAmount DECIMAL(18,2) NOT NULL DEFAULT 0.00
);

CREATE TABLE lab.OrderItems (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductName NVARCHAR(100) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL,
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderID) REFERENCES lab.Orders(OrderID)
);

CREATE TABLE lab.BankAccounts (
    AccountID INT PRIMARY KEY,
    AccountHolder NVARCHAR(100) NOT NULL,
    Balance DECIMAL(18,2) NOT NULL
);
GO


-- =================================================================================
-- PART 1: OUTPUT PARAMETERS AND TABLE-VALUED PARAMETERS (TVP)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - OUTPUT PARAMETERS: Allow returning individual values back to the procedure caller.
--     Requires the `OUTPUT` keyword both in the procedure signature and the `EXEC` call.
--   - TABLE-VALUED PARAMETERS (TVP): Allow passing entire tables as parameters to a procedure.
--     Requirement: The table type must be created via `CREATE TYPE` and declared as `READONLY` in the procedure.

-- 1. Create a Table Type (TVP)
CREATE TYPE lab.OrderItemTableType AS TABLE (
    ProductName NVARCHAR(100) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL
);
GO

-- 2. Procedure using OUTPUT Parameter and TVP READONLY
CREATE PROCEDURE lab.usp_ProcessOrderBatch
    @CustomerID INT,
    @Items lab.OrderItemTableType READONLY, -- Mandatory READONLY
    @NewOrderID INT OUTPUT                 -- Return Parameter
AS
BEGIN
    SET NOCOUNT ON;

    -- Insert order header
    INSERT INTO lab.Orders (CustomerID, TotalAmount)
    VALUES (@CustomerID, 0);

    SET @NewOrderID = SCOPE_IDENTITY();

    -- Insert items from the TVP batch
    INSERT INTO lab.OrderItems (OrderID, ProductName, Quantity, UnitPrice)
    SELECT @NewOrderID, ProductName, Quantity, UnitPrice
    FROM @Items;

    -- Update order total amount
    UPDATE lab.Orders
    SET TotalAmount = (SELECT SUM(Quantity * UnitPrice) FROM lab.OrderItems WHERE OrderID = @NewOrderID)
    WHERE OrderID = @NewOrderID;
END;
GO

-- Executing the procedure with TVP and capturing the OUTPUT
DECLARE @ItemsBatch lab.OrderItemTableType;
INSERT INTO @ItemsBatch (ProductName, Quantity, UnitPrice)
VALUES ('Monitor 4K', 1, 450.00), ('Mouse Sem Fio', 2, 25.00);

DECLARE @CreatedOrderID INT;
EXEC lab.usp_ProcessOrderBatch 
    @CustomerID = 101, 
    @Items = @ItemsBatch, 
    @NewOrderID = @CreatedOrderID OUTPUT;

SELECT @CreatedOrderID AS OrderIDGerado;
SELECT * FROM lab.Orders WHERE OrderID = @CreatedOrderID;
SELECT * FROM lab.OrderItems WHERE OrderID = @CreatedOrderID;
GO


-- =================================================================================
-- PART 2: SECURE DYNAMIC SQL: SP_EXECUTESQL VS EXEC(@SQL)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - EXEC(@sql): Concatenates raw strings. Does NOT parameterize queries, exposes the application to SQL INJECTION
--     and prevents execution plan reuse in the cache.
--   - SP_EXECUTESQL: Executes parameterized dynamic SQL. Prevents SQL injection and reuses execution plans.
--   - QUOTENAME(): Essential function for sanitizing dynamic object names (tables/columns).

CREATE PROCEDURE lab.usp_SearchOrdersDynamic
    @CustomerID INT = NULL,
    @MinAmount DECIMAL(18,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @ParamDef NVARCHAR(500);

    SET @Sql = N'SELECT OrderID, CustomerID, TotalAmount FROM lab.Orders WHERE 1=1';

    IF @CustomerID IS NOT NULL
        SET @Sql += N' AND CustomerID = @CustID';

    IF @MinAmount IS NOT NULL
        SET @Sql += N' AND TotalAmount >= @MinAmt';

    -- Parameter definition for sp_executesql
    SET @ParamDef = N'@CustID INT, @MinAmt DECIMAL(18,2)';

    -- -- [DP-800 EXAM TIP]
    -- Safe execution with parameterized sp_executesql
    EXEC sp_executesql 
        @stmt = @Sql, 
        @params = @ParamDef, 
        @CustID = @CustomerID, 
        @MinAmt = @MinAmount;
END;
GO

-- Dynamic search test
EXEC lab.usp_SearchOrdersDynamic @CustomerID = 101, @MinAmount = 100.00;
GO


-- =================================================================================
-- PART 3: ERROR HANDLING AND TRANSACTIONS (TRY/CATCH, THROW AND XACT_STATE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - XACT_STATE(): Returns 1 (committable transaction), 0 (no transaction) or -1 (uncommittable/doomed transaction).
--   - If XACT_STATE() = -1, SQL Server PROHIBITS any COMMIT. ROLLBACK is MANDATORY.
--   - THROW: Modern command to rethrow errors preserving the original exception number (replaces RAISERROR).

INSERT INTO lab.BankAccounts VALUES (1, 'Conta Origem', 1000.00), (2, 'Conta Destino', 500.00);
GO

CREATE PROCEDURE lab.usp_SafeTransactionTransfer
    @FromAccount INT,
    @ToAccount INT,
    @Amount DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- Recommended to ensure automatic rollback on fatal errors

    BEGIN TRANSACTION;
    BEGIN TRY
        -- 1. Debit balance
        UPDATE lab.BankAccounts
        SET Balance = Balance - @Amount
        WHERE AccountID = @FromAccount;

        -- Validate if balance went negative (Throws business error)
        IF (SELECT Balance FROM lab.BankAccounts WHERE AccountID = @FromAccount) < 0
            THROW 51000, 'Saldo insuficiente para concluir a transferência.', 1;

        -- 2. Credit balance
        UPDATE lab.BankAccounts
        SET Balance = Balance + @Amount
        WHERE AccountID = @ToAccount;

        COMMIT TRANSACTION;
        PRINT 'Transferência realizada com sucesso!';
    END TRY
    BEGIN CATCH
        -- -- [DP-800 EXAM TIP]
        -- XACT_STATE() verification in CATCH
        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        PRINT 'ERRO NA TRANSAÇÃO: ' + ERROR_MESSAGE();
        THROW; -- Rethrows the error to the calling application
    END CATCH;
END;
GO

-- Transfer test with insufficient balance (Failure and Safe Rollback)
BEGIN TRY
    EXEC lab.usp_SafeTransactionTransfer @FromAccount = 1, @ToAccount = 2, @Amount = 5000.00;
END TRY
BEGIN CATCH
    PRINT 'CAPTURADO PELA APLICAÇÃO: ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PART 4: PARAMETER SNIFFING AND RECOMPILATION
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - PARAMETER SNIFFING: Occurs when the procedure compiles the execution plan based on the FIRST parameter
--     received. If the first parameter is atypical (e.g., searches few rows), the cached plan can be terrible for high-volume searches.
--   - SOLUTIONS FOR PARAMETER SNIFFING:
--     1. `OPTION (OPTIMIZE FOR (@Param UNKNOWN))`: Instructs the optimizer to use average statistics (Most recommended).
--     2. `OPTION (RECOMPILE)` on the specific query: Recompiles the plan only on that execution without affecting the entire procedure.
--     3. `WITH RECOMPILE` on procedure creation: Forces full recompilation on every call (high CPU cost).

-- Example with recompilation only on the sensitive statement. The procedure remains reusable for
-- other commands, while this query compiles for the current @CustomerID value.
CREATE PROCEDURE lab.usp_SearchOrdersRecompile
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT OrderID, CustomerID, TotalAmount
    FROM lab.Orders
    WHERE CustomerID = @CustomerID
    OPTION (RECOMPILE);
END;
GO

EXEC lab.usp_SearchOrdersRecompile @CustomerID = 101;
GO


-- =================================================================================
-- PART 5: SECURITY CONTEXT (EXECUTE AS OWNER)
-- =================================================================================
-- EXECUTE AS OWNER allows exposing a controlled operation without granting direct SELECT on the table
-- to the caller. In production, grant only EXECUTE on the procedure and maintain the principle of least privilege.
CREATE PROCEDURE lab.usp_ReadOrdersAsOwner
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT OrderID, CustomerID, OrderDate, TotalAmount
    FROM lab.Orders;
END;
GO

EXEC lab.usp_ReadOrdersAsOwner;
GO
GO
