-- =================================================================================
-- DP-800 - HANDS-ON LAB: CONSTRAINTS AND SEQUENCES
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates the practical application of integrity rules (constraints) and
-- numeric sequence generators (sequences) in SQL Server, covering:
--   1. Unique Keys: UNIQUE Constraint (1 NULL) vs Filtered Unique Index (N NULLs)
--   2. Check Constraints and optimizer reliability (Trusted vs Untrusted)
--   3. Foreign Keys and Cascading Referential Actions (CASCADE, SET NULL)
--   4. Sequences vs Identity: Shared generators, Caches and Gap behavior
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup in case the script runs more than once
DROP TABLE IF EXISTS lab.InvoiceItems;
DROP TABLE IF EXISTS lab.Invoices;
DROP TABLE IF EXISTS lab.Orders;
DROP TABLE IF EXISTS lab.CustomersUnique;
DROP TABLE IF EXISTS lab.ProductsCheck;
DROP TABLE IF EXISTS lab.SystemAuditLogs;
DROP TABLE IF EXISTS lab.OrderDetailsConsolidated;
DROP TABLE IF EXISTS lab.CustomersConsolidated;
DROP TABLE IF EXISTS lab.OrderItemsComposite;
DROP TABLE IF EXISTS lab.EmployeesHierarchy;
DROP TABLE IF EXISTS lab.Projects;
DROP TABLE IF EXISTS lab.IdentityMetadataDemo;
DROP TABLE IF EXISTS lab.BadCustomers;
DROP TABLE IF EXISTS lab.GoodCustomers;
DROP TABLE IF EXISTS lab.EtlDeduplicationStaging;
DROP TABLE IF EXISTS lab.ConsolidatedSalesDW;
DROP TABLE IF EXISTS lab.OnlineSalesStaging;
DROP TABLE IF EXISTS lab.StoreSalesStaging;
DROP SEQUENCE IF EXISTS lab.DocumentNumberSeq;
DROP SEQUENCE IF EXISTS lab.FiscalInvoiceSeq;
DROP SEQUENCE IF EXISTS lab.CycleSeq;
DROP SEQUENCE IF EXISTS lab.BulkEtlSeq;
DROP SEQUENCE IF EXISTS lab.GlobalSalesSeq;
GO


-- =================================================================================
-- PART 1: UNIQUE CONSTRAINT VS FILTERED UNIQUE INDEX (THE NULL CHALLENGE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - UNIQUE CONSTRAINT (Uniqueness Restriction): Ensures all values in a column are unique.
--     In SQL Server, according to the ANSI standard, the NULL value is treated as an ordinary value. Therefore,
--     a UNIQUE constraint allows the insertion of only a single record with a NULL value.
--     Any subsequent attempt to insert NULL will fail with a key violation error.
--   - FILTERED UNIQUE INDEX: A non-clustered unique index that includes a filter predicate
--     (e.g., `WHERE PersonalEmail IS NOT NULL`). It allows ignoring rows with NULL values during verification.
--     This way, we can have multiple NULL records simultaneously, while maintaining strict uniqueness
--     only on fields that are actually filled in.

-- 0. Ensure table cleanup before creation (Idempotency)
DROP TABLE IF EXISTS lab.CustomersUnique;

CREATE TABLE lab.CustomersUnique (
    CustomerID INT IDENTITY PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    -- Columns for uniqueness tests
    GovernmentID VARCHAR(20) NULL,
    PersonalEmail VARCHAR(100) NULL
);
GO

-- 1. Applying a classic UNIQUE CONSTRAINT on GovernmentID
ALTER TABLE lab.CustomersUnique
ADD CONSTRAINT UQ_CustomersUnique_GovernmentID UNIQUE (GovernmentID);
GO

-- Test: Insert two customers with different IDs (Success)
INSERT INTO lab.CustomersUnique (CustomerName, GovernmentID) VALUES ('Alice', '12345'), ('Bob', '67890');

-- Test: Insert the first customer with NULL (Success)
INSERT INTO lab.CustomersUnique (CustomerName, GovernmentID) VALUES ('Charlie', NULL);

-- Test: Insert the SECOND customer with NULL (Fails due to Unique Constraint!)
BEGIN TRY
    INSERT INTO lab.CustomersUnique (CustomerName, GovernmentID) VALUES ('David', NULL);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO UNIQUE CONSTRAINT: ' + ERROR_MESSAGE();
    -- Message: "Violation of UNIQUE KEY constraint..."
END CATCH;
GO

-- 2. Solution to accept Multiple NULLs: FILTERED UNIQUE INDEX
-- First we remove the old constraint
ALTER TABLE lab.CustomersUnique DROP CONSTRAINT UQ_CustomersUnique_GovernmentID;
GO

-- Create a Unique Index that ignores NULL values (WHERE Column IS NOT NULL)
CREATE UNIQUE NONCLUSTERED INDEX UIX_CustomersUnique_PersonalEmail
ON lab.CustomersUnique(PersonalEmail)
WHERE PersonalEmail IS NOT NULL;
GO

-- Test: Insert multiple customers with NULL email (Success!)
INSERT INTO lab.CustomersUnique (CustomerName, PersonalEmail) VALUES ('Daniel', NULL);
INSERT INTO lab.CustomersUnique (CustomerName, PersonalEmail) VALUES ('Eva', NULL);

-- Test: Insert customers with duplicate emails (Expected Uniqueness Failure)
INSERT INTO lab.CustomersUnique (CustomerName, PersonalEmail) VALUES ('Frank', 'frank@email.com');
BEGIN TRY
    INSERT INTO lab.CustomersUnique (CustomerName, PersonalEmail) VALUES ('Grace', 'frank@email.com');
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO UNIQUE INDEX FILTRADO: ' + ERROR_MESSAGE();
    -- Message: "Cannot insert duplicate key row..."
END CATCH;
GO


-- =================================================================================
-- PART 2: CHECK CONSTRAINTS AND THE TRUSTED FLAG (RELIABILITY)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CHECK CONSTRAINT: Logical restriction applied to columns to ensure all inserted or
--     updated data meets a logical rule / boolean condition (e.g., `Price > 0`).
--   - NOT FOR REPLICATION / NOCHECK STATE: Allows temporarily disabling a constraint's validation
--     (e.g., during massive data loads or replication). This marks the constraint as `is_not_trusted = 1`.
--   - TRUSTED VS UNTRUSTED CONSTRAINTS: A trusted constraint (`is_not_trusted = 0`) mathematically guarantees
--     to the optimizer that no row violates the rule. The optimizer uses this guarantee to simplify plans
--     (e.g., if the query filters `WHERE Price = -10` and the constraint guarantees `Price > 0`, the engine skips reading the table).
--     If `untrusted`, SQL Server ignores this optimization and reads the table anyway.
--   - REACTIVATION WITH WITH CHECK: To make a constraint trusted again, re-enable it using the
--     `WITH CHECK CHECK CONSTRAINT` statement. Using only `CHECK CONSTRAINT` re-enables the rule for new rows, but
--     keeps the `is_not_trusted` state (since old data was not verified).

CREATE TABLE lab.ProductsCheck (
    ProductID INT IDENTITY PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Price DECIMAL(18,2) NULL,
    CONSTRAINT CK_ProductsCheck_Price CHECK (Price > 0)
);
GO

-- 2. Disable the constraint for a fast bulk load
ALTER TABLE lab.ProductsCheck NOCHECK CONSTRAINT CK_ProductsCheck_Price;
GO

-- Insert inconsistent data while disabled (negative Price)
INSERT INTO lab.ProductsCheck (ProductName, Price) VALUES ('Produto Grátis/Brinde', -10.00);
GO

-- 3. Re-enable WITHOUT validating history (NOCHECK)
-- SQL Server will accept the re-activation, but will mark it as NOT TRUSTED (is_not_trusted = 1)
ALTER TABLE lab.ProductsCheck WITH NOCHECK CHECK CONSTRAINT CK_ProductsCheck_Price;
GO

-- Check whether the constraint is marked as trusted
-- If is_not_trusted = 1, the optimizer does not trust the data to optimize execution plans.
SELECT name, is_not_trusted, is_disabled 
FROM sys.check_constraints 
WHERE name = 'CK_ProductsCheck_Price';
GO

-- 4. How to CORRECTLY re-enable to make it trusted again:
-- First fix the inconsistent data
UPDATE lab.ProductsCheck SET Price = 1.00 WHERE Price < 0;

-- Now apply validation on all historical data with WITH CHECK
ALTER TABLE lab.ProductsCheck WITH CHECK CHECK CONSTRAINT CK_ProductsCheck_Price;
GO

-- Verify the flag again (Should be is_not_trusted = 0)
SELECT name, is_not_trusted, is_disabled 
FROM sys.check_constraints 
WHERE name = 'CK_ProductsCheck_Price';
GO


-- =================================================================================
-- PART 3: FOREIGN KEY AND REFERENTIAL ACTIONS (CASCADE AND SET NULL)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - FOREIGN KEY: A constraint that establishes a logical integrity link
--     between records in two tables, requiring the child column value to exist beforehand in the
--     primary key column of the parent table.
--   - CASCADE: A referential action that propagates the deletion or update of a record in the parent table
--     automatically to all linked child rows.
--   - SET NULL / SET DEFAULT: Referential actions that set the foreign key column in child tables
--     to `NULL` (or to the configured `DEFAULT` value) if the corresponding row in the parent table is deleted/updated.
--   - NO ACTION (Default): Rejects deletion or update in the parent table if there are linked child records.
--   - CYCLE AND MULTIPLE PATH PREVENTION: SQL Server prohibits creating constraints with `ON DELETE/UPDATE CASCADE`
--     if the deletion path could generate cyclic references (circular loops) or if there are redundant multiple
--     propagation paths to the same table. This aims to avoid infinite deletion loops and unpredictable behavior.

-- 1. Create Parent Table (Invoices)
DROP TABLE IF EXISTS lab.InvoiceItems;
DROP TABLE IF EXISTS lab.Invoices;

CREATE TABLE lab.Invoices (
    InvoiceID INT NOT NULL PRIMARY KEY,
    InvoiceDate DATE NOT NULL
);

-- 2. Create Child Table (InvoiceItems) with ON DELETE rules
CREATE TABLE lab.InvoiceItems (
    ItemID INT IDENTITY PRIMARY KEY,
    InvoiceID INT NOT NULL,
    Description NVARCHAR(100) NOT NULL,
    -- CASCADE: Deletes child rows if the parent row is deleted
    CONSTRAINT FK_InvoiceItems_Invoices 
        FOREIGN KEY (InvoiceID) REFERENCES lab.Invoices(InvoiceID)
        ON DELETE CASCADE
);
GO

-- 3. Insert test data
INSERT INTO lab.Invoices (InvoiceID, InvoiceDate) VALUES (1001, GETDATE());
INSERT INTO lab.InvoiceItems (InvoiceID, Description) VALUES (1001, 'Item A'), (1001, 'Item B');
GO

-- Verify records before deletion
SELECT * FROM lab.Invoices;
SELECT * FROM lab.InvoiceItems;

-- 4. Delete the Parent Invoice (Automatically deletes Child Items due to CASCADE)
DELETE FROM lab.Invoices WHERE InvoiceID = 1001;
GO

-- Verify that child items were automatically deleted!
SELECT * FROM lab.InvoiceItems;
GO


-- =================================================================================
-- PART 4: SEQUENCES VS IDENTITY (HIDDEN CACHE AND MULTI-TABLE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - IDENTITY (Identity): Column property that generates sequential numbers bound
--     exclusively to a specific table (e.g., `ID INT IDENTITY(1,1)`).
--   - SEQUENCE: An autonomous numeric generator object created at the schema level. It can be referenced
--     by multiple tables simultaneously (e.g., using `NEXT VALUE FOR schema.SequenceName`) and allows
--     obtaining the next sequential number before executing an insert into the table (via `NEXT VALUE FOR`).
--   - SEQUENCE CACHE: A performance feature that pre-allocates ranges of numbers in RAM (e.g., `CACHE 20`)
--     to avoid constant disk I/O on every insert.
--   - GAP BEHAVIOR (Gaps): If the SQL Server service suffers a forced restart, power outage
--     or crash, all numbers that were pre-allocated in the CACHE but not yet consolidated into the tables
--     will be permanently lost, creating "holes" (gaps) in the sequence. `NO CACHE` only reduces
--     gaps caused by cached values; it does not guarantee absolute contiguity on rollbacks or unused values.

-- 1. Create a Sequence with Cache
DROP SEQUENCE IF EXISTS lab.DocumentNumberSeq;
CREATE SEQUENCE lab.DocumentNumberSeq
    AS INT
    START WITH 1000
    INCREMENT BY 1
    CACHE 10; -- Pre-allocates 10 numbers in RAM
GO

-- 2. Using the Sequence across different tables
-- IMPORTANT: To recreate lab.Invoices, the child table lab.InvoiceItems must be removed first,
-- created in Part 3, which has a Foreign Key pointing to lab.Invoices.
DROP TABLE IF EXISTS lab.InvoiceItems;
DROP TABLE IF EXISTS lab.Invoices;
DROP TABLE IF EXISTS lab.Orders;

CREATE TABLE lab.Invoices (
    InvoiceID INT NOT NULL DEFAULT (NEXT VALUE FOR lab.DocumentNumberSeq) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL
);

CREATE TABLE lab.Orders (
    OrderID INT NOT NULL DEFAULT (NEXT VALUE FOR lab.DocumentNumberSeq) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL
);
GO

-- 3. Inserting records and generating numbering from the same sequence!
INSERT INTO lab.Invoices (CustomerName) VALUES ('Cliente A'); -- Gets value 1000
INSERT INTO lab.Orders (CustomerName) VALUES ('Cliente B');   -- Gets value 1001
INSERT INTO lab.Invoices (CustomerName) VALUES ('Cliente C'); -- Gets value 1002

-- Verify that numbering is integrated across tables
SELECT 'Faturas' AS Origem, InvoiceID AS ID, CustomerName FROM lab.Invoices
UNION ALL
SELECT 'Pedidos' AS Origem, OrderID AS ID, CustomerName FROM lab.Orders;
GO

-- 4. Resetting or changing the current Sequence value
ALTER SEQUENCE lab.DocumentNumberSeq RESTART WITH 2000;
GO

-- Insert a new record after the restart
INSERT INTO lab.Invoices (CustomerName) VALUES ('Cliente D'); -- Gets value 2000
SELECT * FROM lab.Invoices;
GO


-- =================================================================================
-- PART 5: ADDITIONAL PRACTICAL SCENARIOS (PK NONCLUSTERED, SET DEFAULT AND NO CACHE)
-- =================================================================================

-- 1. Audit Table using NONCLUSTERED PRIMARY KEY
-- The Clustered Index is placed on LogDate to optimize date range queries
DROP TABLE IF EXISTS lab.SystemAuditLogs;
CREATE TABLE lab.SystemAuditLogs (
    LogID UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
    LogDate DATETIME2 DEFAULT SYSUTCDATETIME() NOT NULL,
    LogMessage NVARCHAR(255) NOT NULL,
    -- Non-Clustered PK
    CONSTRAINT PK_SystemAuditLogs PRIMARY KEY NONCLUSTERED (LogID)
);

-- Clustered Index based on Log Date (For fast range scans)
CREATE CLUSTERED INDEX CIX_SystemAuditLogs_LogDate ON lab.SystemAuditLogs(LogDate);
GO

-- Test inserting into the log
INSERT INTO lab.SystemAuditLogs (LogMessage) VALUES ('Usuário admin efetuou login'), ('Sistema de backup iniciado');
SELECT * FROM lab.SystemAuditLogs ORDER BY LogDate;
GO

-- 2. Sequence with NO CACHE option (reduces gaps from cached values after restarts)
DROP SEQUENCE IF EXISTS lab.FiscalInvoiceSeq;
CREATE SEQUENCE lab.FiscalInvoiceSeq
    AS INT
    START WITH 1
    INCREMENT BY 1
    NO CACHE; -- Persists the current value on every request; additional I/O cost
GO

SELECT NEXT VALUE FOR lab.FiscalInvoiceSeq AS ProximaNotaFiscal;
SELECT NEXT VALUE FOR lab.FiscalInvoiceSeq AS ProximaNotaFiscal;
GO

-- [DP-800 EXAM TIP] Even with NO CACHE, NEXT VALUE FOR is consumed outside the transaction.
-- The rollback below does not return number 3; the next call returns 4.
BEGIN TRANSACTION;
DECLARE @NumeroReservado INT = NEXT VALUE FOR lab.FiscalInvoiceSeq;
SELECT @NumeroReservado AS NumeroConsumidoAntesDoRollback;
ROLLBACK TRANSACTION;

SELECT NEXT VALUE FOR lab.FiscalInvoiceSeq AS ProximoNumeroAposRollback;
GO


-- =================================================================================
-- PART 6: CONSOLIDATED DEMONSTRATION OF THE 5 CONSTRAINT TYPES AND SEQUENCE VS IDENTITY
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - PRIMARY KEY (PK): Uniquely identifies the row; enforces NOT NULL; creates Clustered Index by default.
--   - FOREIGN KEY (FK): Referential integrity with parent table; accepts NULL; can be disabled with NOCHECK.
--   - UNIQUE (UK): Guarantees secondary uniqueness; accepts only 1 NULL by default (or multiple via filtered index).
--   - DEFAULT (DF): Provides automatic default value if the column is omitted in the INSERT.
--   - CHECK (CHK): Validates a boolean logical rule on the row (accepts if TRUE or UNKNOWN/NULL).

-- 1. Create Consolidated Table with all 5 Constraints (PK, FK, UK, DF, CHECK)
DROP TABLE IF EXISTS lab.OrderDetailsConsolidated;
DROP TABLE IF EXISTS lab.CustomersConsolidated;

CREATE TABLE lab.CustomersConsolidated (
    CustomerID INT PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL
);

CREATE TABLE lab.OrderDetailsConsolidated (
    DetailID    INT IDENTITY(1,1),      -- 1. Local IDENTITY
    CustomerID  INT         NOT NULL,   -- 2. FK pointing to the Customers table
    TaxNumber   VARCHAR(20) NULL,       -- 3. UNIQUE (Secondary Tax Number)
    OrderStatus VARCHAR(20) NULL CONSTRAINT DF_OrderDetails_Status DEFAULT ('Pendente'), -- 4. DEFAULT
    OrderQty    INT NOT NULL,           -- 5. CHECK
    UnitPrice   DECIMAL(10,2) NOT NULL,
    
    -- Explicit constraint definitions
    CONSTRAINT PK_OrderDetailsConsolidated PRIMARY KEY CLUSTERED (DetailID),
    CONSTRAINT FK_OrderDetails_Customers FOREIGN KEY (CustomerID) REFERENCES lab.CustomersConsolidated(CustomerID),
    CONSTRAINT UQ_OrderDetails_TaxNumber UNIQUE (TaxNumber),
    CONSTRAINT CK_OrderDetails_QtyPositive CHECK (OrderQty > 0 AND UnitPrice >= 0.00)
);
GO

-- 2. Test Valid Insertion (All 5 constraints satisfied)
INSERT INTO lab.CustomersConsolidated (CustomerID, CustomerName) VALUES (1, 'Cliente Teste Matriz');

INSERT INTO lab.OrderDetailsConsolidated (CustomerID, TaxNumber, OrderQty, UnitPrice)
VALUES (1, 'TAX-998877', 5, 100.00);

-- Verify that OrderStatus received the value 'Pendente' via DEFAULT constraint
SELECT DetailID, CustomerID, TaxNumber, OrderStatus, OrderQty, UnitPrice 
FROM lab.OrderDetailsConsolidated;
GO

-- 3. Violation Tests for Each Constraint (DP-800 Traps with BEGIN TRY...CATCH)

-- 3.a FOREIGN KEY Violation Test (CustomerID 999 does not exist in parent table)
BEGIN TRY
    INSERT INTO lab.OrderDetailsConsolidated (CustomerID, TaxNumber, OrderQty, UnitPrice)
    VALUES (999, 'TAX-000000', 1, 50.00);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO 1 (FK Violation): ' + ERROR_MESSAGE();
END CATCH;

-- 3.b UNIQUE CONSTRAINT Violation Test (TaxNumber 'TAX-998877' already registered)
BEGIN TRY
    INSERT INTO lab.OrderDetailsConsolidated (CustomerID, TaxNumber, OrderQty, UnitPrice)
    VALUES (1, 'TAX-998877', 2, 30.00);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO 2 (UK Violation): ' + ERROR_MESSAGE();
END CATCH;

-- 3.c CHECK CONSTRAINT Violation Test (OrderQty = -5 violates the OrderQty > 0 rule)
BEGIN TRY
    INSERT INTO lab.OrderDetailsConsolidated (CustomerID, TaxNumber, OrderQty, UnitPrice)
    VALUES (1, 'TAX-111111', -5, 10.00);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO 3 (CHECK Violation): ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PART 7: ADVANCED THEORY FEATURES (COMPOSITE PK, MULTI-COLUMN CHECK, CYCLE AND IDENTITY METADATA)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - COMPOSITE PK: Primary key formed by 2 or more columns (e.g., N:M Association Table).
--   - SELF-REFERENCING FK: Table that points to its own primary key (e.g., Hierarchical Employee/Manager Tree).
--   - FK ON DELETE SET DEFAULT: When the parent is deleted, the child's FK assumes the DEFAULT value (e.g., Anonymous Customer ID 0).
--   - MULTI-COLUMN CHECK: A constraint that compares two or more columns from the SAME row (e.g., `EndDate >= StartDate`).
--   - SEQUENCE CYCLE: When the MAXVALUE limit is reached, the sequence automatically restarts at MINVALUE.
--   - IDENTITY FUNCTIONS AND METADATA: 
--       * `SCOPE_IDENTITY()`: Returns the last ID generated in the current scope and session (Safe against Triggers).
--       * `@@IDENTITY`: Returns the last ID generated in the entire session (May return an ID generated within a Trigger in another table!).
--       * `IDENT_CURRENT('Table')`: Returns the last ID generated in any session for a specific table.
--       * `DBCC CHECKIDENT`: Resets the current IDENTITY pointer value.

-- 1. Composite Primary Key (N:M Order Items Table)
DROP TABLE IF EXISTS lab.OrderItemsComposite;
CREATE TABLE lab.OrderItemsComposite (
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    CONSTRAINT PK_OrderItemsComposite PRIMARY KEY (OrderID, ProductID)
);
GO

INSERT INTO lab.OrderItemsComposite (OrderID, ProductID, Quantity) VALUES (101, 1, 2), (101, 2, 5);
-- Attempt to insert duplicate item in the same order (Composite PK Failure)
BEGIN TRY
    INSERT INTO lab.OrderItemsComposite (OrderID, ProductID, Quantity) VALUES (101, 1, 10);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO PK COMPOSTA: ' + ERROR_MESSAGE();
END CATCH;
GO

-- 2. Self-Referencing Foreign Key (Employee Hierarchy)
DROP TABLE IF EXISTS lab.EmployeesHierarchy;
CREATE TABLE lab.EmployeesHierarchy (
    EmployeeID INT PRIMARY KEY,
    EmployeeName NVARCHAR(100) NOT NULL,
    ManagerID INT NULL CONSTRAINT FK_Employees_Manager REFERENCES lab.EmployeesHierarchy(EmployeeID)
);
GO

INSERT INTO lab.EmployeesHierarchy (EmployeeID, EmployeeName, ManagerID) VALUES (1, 'CEO Carlos', NULL);
INSERT INTO lab.EmployeesHierarchy (EmployeeID, EmployeeName, ManagerID) VALUES (2, 'Diretora Ana', 1); -- Ana reports to Carlos (1)
INSERT INTO lab.EmployeesHierarchy (EmployeeID, EmployeeName, ManagerID) VALUES (3, 'Dev Bruno', 2);    -- Bruno reports to Ana (2)

SELECT e.EmployeeName AS Funcionario, ISNULL(m.EmployeeName, 'Sem Gerente') AS Gerente
FROM lab.EmployeesHierarchy e
LEFT JOIN lab.EmployeesHierarchy m ON e.ManagerID = m.EmployeeID;
GO

-- 3. Multi-Column Check Constraint (Comparing 2 fields from the same row)
DROP TABLE IF EXISTS lab.Projects;
CREATE TABLE lab.Projects (
    ProjectID INT IDENTITY PRIMARY KEY,
    ProjectName NVARCHAR(100) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    CONSTRAINT CK_Projects_Dates CHECK (EndDate >= StartDate)
);
GO

INSERT INTO lab.Projects (ProjectName, StartDate, EndDate) VALUES ('Projeto Alfa', '2026-01-01', '2026-06-30');

-- Violation test: End date before start date (Multi-column CHECK failure)
BEGIN TRY
    INSERT INTO lab.Projects (ProjectName, StartDate, EndDate) VALUES ('Projeto Inválido', '2026-06-01', '2026-01-01');
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO CHECK MULTI-COLUNAS: ' + ERROR_MESSAGE();
END CATCH;
GO

-- 4. Sequence with CYCLE feature (Generates values 1, 2, 3, 1, 2, 3...)
DROP SEQUENCE IF EXISTS lab.CycleSeq;
CREATE SEQUENCE lab.CycleSeq
    AS TINYINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 3
    CYCLE; -- Automatically restarts when reaching 3
GO

SELECT NEXT VALUE FOR lab.CycleSeq AS Val1, NEXT VALUE FOR lab.CycleSeq AS Val2, NEXT VALUE FOR lab.CycleSeq AS Val3;
SELECT NEXT VALUE FOR lab.CycleSeq AS ValCycle1, NEXT VALUE FOR lab.CycleSeq AS ValCycle2; -- Restarted at 1 and 2!
GO

-- 5. IDENTITY Metadata Functions (SCOPE_IDENTITY vs @@IDENTITY vs DBCC CHECKIDENT)
DROP TABLE IF EXISTS lab.IdentityMetadataDemo;
CREATE TABLE lab.IdentityMetadataDemo (
    ID INT IDENTITY(100, 5) PRIMARY KEY,
    ValueText NVARCHAR(50)
);
GO

INSERT INTO lab.IdentityMetadataDemo (ValueText) VALUES ('Inserção 1');

SELECT 
    SCOPE_IDENTITY() AS LastScopeIdentity,   -- 100
    @@IDENTITY AS LastGlobalIdentity,        -- 100
    IDENT_CURRENT('lab.IdentityMetadataDemo') AS IdentCurrentTable; -- 100

-- Resetting the IDENTITY pointer with DBCC CHECKIDENT (Reseed to 500)
DBCC CHECKIDENT ('lab.IdentityMetadataDemo', RESEED, 500);

INSERT INTO lab.IdentityMetadataDemo (ValueText) VALUES ('Inserção Pós-Reseed');
SELECT * FROM lab.IdentityMetadataDemo;
GO


-- =================================================================================
-- PART 8: BATCH SEQUENCE ALLOCATION VIA sp_sequence_get_range (ETL PERFORMANCE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - sp_sequence_get_range: A system stored procedure that reserves an entire block/range of numbers
--     from a SEQUENCE in a single call. This is ideal for bulk data ingestion applications (ETL)
--     that need to generate primary keys in the application memory before sending a concurrent BULK INSERT.

DROP SEQUENCE IF EXISTS lab.BulkEtlSeq;
CREATE SEQUENCE lab.BulkEtlSeq
    AS INT
    START WITH 100000
    INCREMENT BY 1;
GO

DECLARE 
    @FirstValue SQL_VARIANT,
    @LastValue SQL_VARIANT,
    @CycleCount INT,
    @SequenceIncrement SQL_VARIANT,
    @MinSeqValue SQL_VARIANT,
    @MaxSeqValue SQL_VARIANT;

-- Reserve a block of 1,000 IDs at once for the ETL process
EXEC sys.sp_sequence_get_range
    @sequence_name = N'lab.BulkEtlSeq',
    @range_size = 1000,
    @range_first_value = @FirstValue OUTPUT,
    @range_last_value = @LastValue OUTPUT,
    @range_cycle_count = @CycleCount OUTPUT,
    @sequence_increment = @SequenceIncrement OUTPUT,
    @sequence_min_value = @MinSeqValue OUTPUT,
    @sequence_max_value = @MaxSeqValue OUTPUT;

SELECT 
    @FirstValue AS PrimeirosID_Reservado,
    @LastValue AS UltimoID_Reservado,
    'O processo de ETL agora possui os IDs 100000 até 100999 pré-alocados na memória!' AS StatusAlocacao;
GO


-- =================================================================================
-- PART 9: THE SURROGATE KEY VS BUSINESS KEY TRAP
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - SURROGATE KEY TRAP: An `IDENTITY` or `SEQUENCE` key only guarantees uniqueness of the artificial ID number.
--     It does NOT prevent two rows from containing the same real business entity (e.g., two customers with the same CPF).
--   - ARCHITECTURE SOLUTION:
--     1. Keep IDENTITY as the Surrogate PK for physical JOIN performance.
--     2. Create a UNIQUE CONSTRAINT on the Business Key / Natural Key (e.g., `UNIQUE (CPF)`).
--     3. For batch loads (ETL/ELT), use a computed column with a Row Hash (`RowHash`) indexed.

-- 1. ERROR DEMONSTRATION: Table without UNIQUE on Business Key (Accepts business duplicates!)
DROP TABLE IF EXISTS lab.BadCustomers;
CREATE TABLE lab.BadCustomers (
    CustomerID INT IDENTITY PRIMARY KEY, -- SQL Server guarantees CustomerID is unique (1, 2)
    CPF VARCHAR(14) NOT NULL,
    CustomerName NVARCHAR(100) NOT NULL
);
GO

-- Inserting the SAME CUSTOMER twice (Succeeds in the database, but CORRUPTED / DUPLICATE data for the business!)
INSERT INTO lab.BadCustomers (CPF, CustomerName) VALUES ('123.456.789-00', 'João Silva');
INSERT INTO lab.BadCustomers (CPF, CustomerName) VALUES ('123.456.789-00', 'João Silva'); -- Generated CustomerID = 2 for the same person!

SELECT * FROM lab.BadCustomers; -- Two identical rows with different IDs!
GO

-- 2. CORRECT SOLUTION: Table with Surrogate PK + UNIQUE Constraint on Business Key (CPF)
DROP TABLE IF EXISTS lab.GoodCustomers;
CREATE TABLE lab.GoodCustomers (
    CustomerID INT IDENTITY PRIMARY KEY, -- Surrogate Key for high-performance JOINs
    CPF VARCHAR(14) NOT NULL,            -- Business Key
    CustomerName NVARCHAR(100) NOT NULL,
    -- Prevents duplication of the real business entity!
    CONSTRAINT UQ_GoodCustomers_CPF UNIQUE (CPF)
);
GO

INSERT INTO lab.GoodCustomers (CPF, CustomerName) VALUES ('123.456.789-00', 'João Silva');

-- Second attempt with the same CPF (Successfully blocked by the UNIQUE Constraint!)
BEGIN TRY
    INSERT INTO lab.GoodCustomers (CPF, CustomerName) VALUES ('123.456.789-00', 'João Silva');
END TRY
BEGIN CATCH
    PRINT 'BLOQUEIO DE DUPLICIDADE NEGOCIAL: ' + ERROR_MESSAGE();
END CATCH;
GO

-- 3. ADVANCED ETL PATTERN: Load Control with Deduplication Hash (RowHash)
DROP TABLE IF EXISTS lab.EtlDeduplicationStaging;
CREATE TABLE lab.EtlDeduplicationStaging (
    StagingID INT IDENTITY PRIMARY KEY,
    TenantID INT NOT NULL,
    DocumentNumber VARCHAR(20) NOT NULL,
    RawData NVARCHAR(MAX) NOT NULL,
    -- Computed column with Hash of the unique load combination
    RowHash AS HASHBYTES('SHA2_256', CONCAT(TenantID, '|', DocumentNumber)) PERSISTED
);

CREATE UNIQUE NONCLUSTERED INDEX UIX_EtlDeduplication_RowHash 
ON lab.EtlDeduplicationStaging(RowHash);
GO

-- Initial load
INSERT INTO lab.EtlDeduplicationStaging (TenantID, DocumentNumber, RawData) 
VALUES (10, 'DOC-998877', N'{"status": "processed"}');

-- Attempt to re-ingest the same record in the ETL pipeline (Rejected by the Hash!)
BEGIN TRY
    INSERT INTO lab.EtlDeduplicationStaging (TenantID, DocumentNumber, RawData) 
    VALUES (10, 'DOC-998877', N'{"status": "duplicated"}');
END TRY
BEGIN CATCH
    PRINT 'DUPLICATA DE CARGA ETL REJEITADA PELO HASH: ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PART 10: MERGE WITH SEQUENCE ON MULTIPLE TABLES (THE CORRECT INTEGRATlON PATTERN)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - THE SEQUENCE PROBLEM IN MERGE: If two source tables (e.g., `OnlineSales` and `StoreSales`) consume
--     from the same SEQUENCE, the generated ID (e.g., 1001 on Online and 1002 on Store) is purely arbitrary.
--   - COMMON ERROR: Attempting to `MERGE ON Target.SequenceID = Source.SequenceID`. This will NEVER MATCH,
--     generating duplicates of the same sale or updating the wrong record!
--   - ARCHITECTURE SOLUTION:
--     1. The `MERGE` MUST be done ON `Target.BusinessKey = Source.BusinessKey` (e.g., `CPF + SaleDate` or `InvoiceNumber`).
--     2. The SEQUENCE should be assigned ONLY in the `WHEN NOT MATCHED THEN INSERT (ID = NEXT VALUE FOR Seq, ...)` block.

-- 1. Create the shared Sequence and Source tables (E-Commerce and Physical Store)
DROP TABLE IF EXISTS lab.ConsolidatedSalesDW;
DROP TABLE IF EXISTS lab.OnlineSalesStaging;
DROP TABLE IF EXISTS lab.StoreSalesStaging;
DROP SEQUENCE IF EXISTS lab.GlobalSalesSeq;

CREATE SEQUENCE lab.GlobalSalesSeq AS INT START WITH 5000 INCREMENT BY 1 NO CACHE;
GO

CREATE TABLE lab.OnlineSalesStaging (
    TransactionCode VARCHAR(30) PRIMARY KEY, -- Natural Business Key
    CustomerCPF VARCHAR(14) NOT NULL,
    Amount DECIMAL(10,2) NOT NULL
);

CREATE TABLE lab.StoreSalesStaging (
    TransactionCode VARCHAR(30) PRIMARY KEY, -- Natural Business Key
    CustomerCPF VARCHAR(14) NOT NULL,
    Amount DECIMAL(10,2) NOT NULL
);

-- Consolidated Table (Data Warehouse / DW)
-- [DP-800 EXAM TIP]: To use SEQUENCE in MERGE, it MUST be defined as a DEFAULT constraint on the table!
CREATE TABLE lab.ConsolidatedSalesDW (
    GlobalSalesID INT NOT NULL DEFAULT (NEXT VALUE FOR lab.GlobalSalesSeq) PRIMARY KEY,
    TransactionCode VARCHAR(30) UNIQUE NOT NULL, -- Natural Business Key with UNIQUE Constraint!
    CustomerCPF VARCHAR(14) NOT NULL,
    Amount DECIMAL(10,2) NOT NULL,
    LastUpdated DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

-- Insert sales from different sources (Staging from Distinct Channels)
INSERT INTO lab.OnlineSalesStaging VALUES ('TX-101', '111.111.111-11', 150.00), ('TX-102', '222.222.222-22', 300.00);
INSERT INTO lab.StoreSalesStaging VALUES ('TX-102', '222.222.222-22', 350.00), ('TX-103', '333.333.333-33', 500.00); -- TX-102 with new value and TX-103 new
GO

-- 2. EXECUTE MERGE BATCH 1 (E-Commerce Load - OnlineSalesStaging)
-- Transactions TX-101 and TX-102 are new -> DEFAULT triggers NEXT VALUE FOR from the SEQUENCE (IDs 5000 and 5001)
MERGE lab.ConsolidatedSalesDW AS Target
USING lab.OnlineSalesStaging AS Source
ON Target.TransactionCode = Source.TransactionCode
WHEN MATCHED THEN 
    UPDATE SET Target.Amount = Source.Amount, Target.LastUpdated = SYSUTCDATETIME()
WHEN NOT MATCHED THEN 
    INSERT (TransactionCode, CustomerCPF, Amount)
    VALUES (Source.TransactionCode, Source.CustomerCPF, Source.Amount);
GO

-- Verify the initial DW load (IDs 5000 and 5001 generated)
SELECT * FROM lab.ConsolidatedSalesDW;
GO

-- 3. EXECUTE MERGE BATCH 2 (Physical Store Load - StoreSalesStaging)
-- [DP-800 EXAM TIP]: 
-- - TX-102 ALREADY EXISTS: Triggers WHEN MATCHED -> Updates Amount to 350.00 WITHOUT consuming a new SEQUENCE ID!
-- - TX-103 IS NEW: Triggers WHEN NOT MATCHED -> Inserts with the next SEQUENCE ID (5002)!
MERGE lab.ConsolidatedSalesDW AS Target
USING lab.StoreSalesStaging AS Source
ON Target.TransactionCode = Source.TransactionCode
WHEN MATCHED THEN 
    UPDATE SET Target.Amount = Source.Amount, Target.LastUpdated = SYSUTCDATETIME()
WHEN NOT MATCHED THEN 
    INSERT (TransactionCode, CustomerCPF, Amount)
    VALUES (Source.TransactionCode, Source.CustomerCPF, Source.Amount);
GO

-- Final Result: TX-102 was updated to 350.00 preserving ID 5001 (no ID waste),
-- and TX-103 received the new ID 5002!
SELECT GlobalSalesID, TransactionCode, CustomerCPF, Amount, LastUpdated FROM lab.ConsolidatedSalesDW;
GO

-- =================================================================================================
-- OFFICIAL MICROSOFT LEARN REFERENCES
-- =================================================================================================
-- CREATE TABLE, PRIMARY KEY, UNIQUE, CHECK and FOREIGN KEY constraints:
-- https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql?view=sql-server-ver17
-- CREATE SEQUENCE, CACHE/NO CACHE and sp_sequence_get_range:
-- https://learn.microsoft.com/en-us/sql/t-sql/statements/create-sequence-transact-sql?view=sql-server-ver17
-- Sequence numbers and NEXT VALUE FOR:
-- https://learn.microsoft.com/en-us/sql/relational-databases/sequence-numbers/sequence-numbers?view=sql-server-ver17
