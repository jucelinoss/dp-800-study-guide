-- =================================================================================
-- DP-800 - HANDS-ON LAB: TRIGGERS (AFTER, INSTEAD OF, DDL AND MULTI-ROW HANDLING)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to restore the
-- AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates creating, optimizing, and understanding Trigger execution rules in SQL Server:
--   1. DML AFTER Triggers and the correct use of inserted and deleted virtual tables
--   2. The Classic Single-Row Assumption Error vs Multi-Row Operation Support
--   3. INSTEAD OF Triggers on Multi-Table Views
--   4. DDL Triggers at Database Level and analysis of the EVENTDATA() function
--   5. Execution Order Rules (sp_settriggerorder) and Recursion
--   6. Practical Design Scenarios (Batch Audit Trail and Unauthorized DDL Prevention)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_AuditProducts_MultiRow')
    DROP TRIGGER lab.trg_AuditProducts_MultiRow;
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_vw_OrderCustomerDetails_Insert')
    DROP TRIGGER lab.trg_vw_OrderCustomerDetails_Insert;
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_PreventTableDrop' AND parent_class = 0)
    DROP TRIGGER trg_PreventTableDrop ON DATABASE;

IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_OrderCustomerDetails' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_OrderCustomerDetails;

DROP TABLE IF EXISTS lab.ProductAuditLog;
DROP TABLE IF EXISTS lab.Products;
DROP TABLE IF EXISTS lab.Orders;
DROP TABLE IF EXISTS lab.Customers;
GO


-- Table structure for testing
CREATE TABLE lab.Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Price DECIMAL(18,2) NOT NULL
);

CREATE TABLE lab.ProductAuditLog (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    ActionType NVARCHAR(20) NOT NULL,
    OldPrice DECIMAL(18,2) NULL,
    NewPrice DECIMAL(18,2) NULL,
    ChangedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
    ChangedBy NVARCHAR(128) DEFAULT SUSER_SNAME()
);

CREATE TABLE lab.Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) UNIQUE NOT NULL
);

CREATE TABLE lab.Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL
);
GO


-- =================================================================================
-- PART 1: AFTER TRIGGERS AND SET-BASED MULTI-ROW OPERATION SUPPORT
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - VIRTUAL TABLES inserted AND deleted:
--     * INSERT: inserted contains the new rows inserted. deleted is empty.
--     * DELETE: deleted contains the removed rows. inserted is empty.
--     * UPDATE: inserted contains the new values; deleted contains the old values before the change.
--   - CLASSIC SINGLE-ROW ASSUMPTION ERROR: Writing the trigger using `SELECT @val = col FROM inserted`.
--     If a single `UPDATE` command changes 1,000 rows at once, the trigger fires ONLY ONCE.
--     Scalar variables capture only ONE random row, ignoring the other 999!
--   - MANDATORY RULE: DML Triggers MUST use set-based logic (JOIN with inserted/deleted).

-- -- [DP-800 EXAM TIP]
-- Trigger written robustly with Multi-Row DML compatibility
CREATE TRIGGER lab.trg_AuditProducts_MultiRow
ON lab.Products
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Captures ALL affected rows in the UPDATE using a JOIN between inserted and deleted
    INSERT INTO lab.ProductAuditLog (ProductID, ActionType, OldPrice, NewPrice)
    SELECT 
        i.ProductID,
        'UPDATE',
        d.Price AS OldPrice,
        i.Price AS NewPrice
    FROM inserted i
    JOIN deleted d ON i.ProductID = d.ProductID
    WHERE i.Price <> d.Price; -- Logs only if the price actually changed
END;
GO

-- Multi-Row Test: Updating multiple products in a single SQL statement
INSERT INTO lab.Products (ProductName, Price) VALUES ('Produto A', 10.00), ('Produto B', 20.00), ('Produto C', 30.00);

-- Batch UPDATE that affects 3 rows at once
UPDATE lab.Products 
SET Price = Price * 1.10;
GO

-- Verify that the audit log recorded ALL 3 changes perfectly!
SELECT * FROM lab.ProductAuditLog;
GO


-- =================================================================================
-- PART 2: INSTEAD OF TRIGGERS ON MULTI-TABLE VIEWS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - INSTEAD OF TRIGGER: Intercepts the DML statement and executes the trigger body code INSTEAD OF the original command.
--   - USAGE IN VIEWS: Views that join multiple tables do not accept direct INSERT. The INSTEAD OF trigger
--     allows splitting the data from the `inserted` virtual table and manually routing it to each base table.

-- 1. View joining Customers and Orders (Does not accept direct INSERT)
CREATE VIEW lab.vw_OrderCustomerDetails
AS
SELECT o.OrderID, o.TotalAmount, c.CustomerName, c.Email
FROM lab.Orders o
JOIN lab.Customers c ON o.CustomerID = c.CustomerID;
GO

-- 2. Create INSTEAD OF INSERT Trigger on the View
CREATE TRIGGER lab.trg_vw_OrderCustomerDetails_Insert
ON lab.vw_OrderCustomerDetails
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Inserts the customer into the base table if they don't already exist
    INSERT INTO lab.Customers (CustomerName, Email)
    SELECT DISTINCT i.CustomerName, i.Email
    FROM inserted i
    WHERE NOT EXISTS (SELECT 1 FROM lab.Customers c WHERE c.Email = i.Email);

    -- Inserts the order linking to the corresponding CustomerID
    INSERT INTO lab.Orders (CustomerID, TotalAmount)
    SELECT c.CustomerID, i.TotalAmount
    FROM inserted i
    JOIN lab.Customers c ON c.Email = i.Email;
END;
GO

-- Test: Inserting a record directly into the Multi-Table View!
INSERT INTO lab.vw_OrderCustomerDetails (CustomerName, Email, TotalAmount)
VALUES ('Daniela Souza', 'daniela@email.com', 850.00);

-- Verify the data was routed to the base tables
SELECT * FROM lab.Customers WHERE Email = 'daniela@email.com';
SELECT * FROM lab.Orders;
GO


-- =================================================================================
-- PART 3: DDL TRIGGERS AND THE EVENTDATA() FUNCTION
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DDL TRIGGER: Fired by data definition events (`CREATE_TABLE`, `ALTER_TABLE`, `DROP_TABLE`).
--     Can have database scope (`ON DATABASE`) or server scope (`ON ALL SERVER`).
--   - EVENTDATA(): Built-in function that returns an XML document with details of the fired DDL event
--     (object name, event type, executing user, and the exact T-SQL text).

-- -- [DP-800 EXAM TIP]
-- Database-level DDL Trigger to block and audit DROP TABLE
CREATE TRIGGER trg_PreventTableDrop
ON DATABASE
FOR DROP_TABLE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EventData XML = EVENTDATA();
    DECLARE @ObjectName NVARCHAR(200) = @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(200)');
    DECLARE @LoginName NVARCHAR(200) = @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(200)');

    PRINT 'BLOQUEIO DDL: A exclusão da tabela ' + @ObjectName + ' foi bloqueada pelo usuário ' + @LoginName;
    ROLLBACK; -- Cancels the DROP TABLE command
END;
GO

-- Test: Attempt to drop a protected table (Should fail and ROLLBACK)
BEGIN TRY
    DROP TABLE lab.Products;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO DDL TRIGGER: ' + ERROR_MESSAGE();
    -- Error: "The transaction ended in the trigger. The batch has been aborted."
END CATCH;
GO

-- The blocking was demonstrated. Disable the trigger so it does not prevent further
-- operations in the study database; enable it again if you want to repeat the test.
DISABLE TRIGGER trg_PreventTableDrop ON DATABASE;
GO


-- =================================================================================
-- PART 4: TRIGGER FIRING ORDER (SP_SETTRIGGERORDER)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - sp_settriggerorder: Allows explicitly defining which trigger executes as FIRST ('First')
--     or LAST ('Last') when multiple triggers exist for the same event on the table.

EXEC sp_settriggerorder 
    @triggername = 'lab.trg_AuditProducts_MultiRow',
    @order = 'First',
    @stmttype = 'UPDATE';
GO

-- =================================================================================================
-- OFFICIAL MICROSOFT LEARN REFERENCES
-- =================================================================================================
-- CREATE TRIGGER, AFTER and INSTEAD OF triggers:
-- https://learn.microsoft.com/en-us/sql/t-sql/statements/create-trigger-transact-sql?view=sql-server-ver17
-- inserted and deleted logical tables:
-- https://learn.microsoft.com/en-us/sql/relational-databases/triggers/use-the-inserted-and-deleted-tables?view=sql-server-ver17
-- DDL triggers and EVENTDATA():
-- https://learn.microsoft.com/en-us/sql/relational-databases/triggers/ddl-triggers?view=sql-server-ver17
-- Trigger firing order with sp_settriggerorder:
-- https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-settriggerorder-transact-sql?view=sql-server-ver17
