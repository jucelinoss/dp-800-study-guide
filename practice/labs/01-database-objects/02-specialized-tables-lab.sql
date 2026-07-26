-- =================================================================================
-- DP-800 - HANDS-ON LAB: SPECIALIZED TABLES
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and the other lab scripts, restore the AdventureWorks
-- (OLTP) database backup available at:
-- https://learn.microsoft.com/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates the creation, use, and querying of the 5 main types of
-- specialized tables covered in the DP-800 exam:
--   1. In-Memory OLTP (Memory-Optimized Tables)
--   2. Temporal Tables (System-Versioned)
--   3. Ledger Tables (Updatable and Append-Only)
--   4. Graph Tables (Nodes and Edges with the MATCH operator)
--   5. External Tables (Syntax and Integration Scenarios)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup in case you run the script more than once
DROP TABLE IF EXISTS lab.FinancialTransactionsLedger;
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'SalariesLedger')
    ALTER TABLE lab.SalariesLedger SET (SYSTEM_VERSIONING = OFF);
DROP TABLE IF EXISTS lab.SalariesLedger;
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'EmployeesTemporal')
    ALTER TABLE lab.EmployeesTemporal SET (SYSTEM_VERSIONING = OFF);
DROP TABLE IF EXISTS lab.EmployeesTemporal;
DROP TABLE IF EXISTS lab.EmployeesTemporalHistory;
IF EXISTS (SELECT 1 FROM sys.external_tables WHERE object_id = OBJECT_ID(N'lab.ExternalSalesOrders'))
    DROP EXTERNAL TABLE lab.ExternalSalesOrders;
IF EXISTS (SELECT 1 FROM sys.external_tables WHERE object_id = OBJECT_ID(N'lab.ExternalYellowTaxi2013'))
    DROP EXTERNAL TABLE lab.ExternalYellowTaxi2013;
IF EXISTS (SELECT 1 FROM sys.external_tables WHERE object_id = OBJECT_ID(N'lab.ExternalGreenTaxi2013'))
    DROP EXTERNAL TABLE lab.ExternalGreenTaxi2013;
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'AzureBlobStorageSales') DROP EXTERNAL DATA SOURCE AzureBlobStorageSales;
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'NYC_Taxi_Yellow') DROP EXTERNAL DATA SOURCE NYC_Taxi_Yellow;
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'NYC_Taxi_Green') DROP EXTERNAL DATA SOURCE NYC_Taxi_Green;
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'ParquetFileFormat') DROP EXTERNAL FILE FORMAT ParquetFileFormat;
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'NycTaxiParquet') DROP EXTERNAL FILE FORMAT NycTaxiParquet;
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'CSVFileFormat') DROP EXTERNAL FILE FORMAT CSVFileFormat;
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'MyStorageCredential') DROP DATABASE SCOPED CREDENTIAL [MyStorageCredential];
DROP PROCEDURE IF EXISTS lab.sp_generate_mermaid_graph;
DROP TABLE IF EXISTS lab.OwnsCard;
DROP TABLE IF EXISTS lab.UsedIP;
DROP TABLE IF EXISTS lab.Knows;
DROP TABLE IF EXISTS lab.CreditCard;
DROP TABLE IF EXISTS lab.IPAddress;
DROP TABLE IF EXISTS lab.Person;
DROP TABLE IF EXISTS lab.SessionCacheMemData;
DROP TABLE IF EXISTS lab.SessionCacheMemOnly;
DROP TYPE IF EXISTS lab.MyMemoryTableType;
GO


-- =================================================================================
-- PART 1: IN-MEMORY (MEMORY-OPTIMIZED) TABLES & DURABILITY
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - IN-MEMORY OLTP: SQL Server technology that optimizes tables for RAM processing.
--     Uses Lock-Free and Latch-Free concurrency algorithms (without physical thread locks) and native
--     compilation of procedures to eliminate bottlenecks in high-throughput OLTP transactions.
--   - BUCKET_COUNT: Critical parameter when creating memory-optimized HASH indexes. It should be
--     sized between 1 and 2 times the estimated number of unique values in the indexed column.
--     Very low values cause hash collisions in RAM (degrading seek performance), and very high values waste memory.
--   - DURABILITY = SCHEMA_ONLY: The table keeps its structure saved on disk, but its data resides only in RAM.
--     If the SQL Server service is restarted, the table is recreated empty. Perfect for caches and transient data.
--   - DURABILITY = SCHEMA_AND_DATA: Guarantees full persistence (schema and data). Transactions are written to the
--     transaction log on disk asynchronously or synchronously, ensuring data survives database restarts.

-- 1. Check and add Memory-Optimized Filegroup if it does not exist
IF NOT EXISTS (SELECT * FROM sys.filegroups WHERE type = 'FX')
BEGIN
    -- Add the Filegroup
    ALTER DATABASE AdventureWorks2025 
    ADD FILEGROUP FG_MemOptimized CONTAINS MEMORY_OPTIMIZED_DATA;
    
    -- Add a physical folder/container to the filegroup
    -- NOTE: The directory must not pre-exist; SQL Server will create the folder.
    DECLARE @filepath NVARCHAR(260);
    SELECT TOP 1 @filepath = SUBSTRING(physical_name, 1, CHARINDEX('AdventureWorks', physical_name) - 1)
    FROM sys.master_files 
    WHERE database_id = DB_ID('AdventureWorks2025');

    SET @filepath = @filepath + 'AW_MemOpt_Container';

    DECLARE @sql NVARCHAR(MAX) = 'ALTER DATABASE AdventureWorks2025 ADD FILE (NAME = ''AW_MemOpt_File'', FILENAME = ''' + @filepath + ''') TO FILEGROUP FG_MemOptimized;';
    EXEC sp_executesql @sql;
END;
GO

-- 2. Create table with DURABILITY = SCHEMA_AND_DATA (Persistent, default)
-- Stores schema and data. Survives server restarts.
CREATE TABLE lab.SessionCacheMemData (
    SessionID uniqueidentifier NOT NULL,
    UserID INT NOT NULL,
    CachedData NVARCHAR(2000) NULL,
    CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    -- Indexes cannot be standard B-Tree, they must be NONCLUSTERED or HASH.
    CONSTRAINT PK_SessionCacheMemData PRIMARY KEY NONCLUSTERED HASH (SessionID) 
        WITH (BUCKET_COUNT = 65536) -- Bucket count should be approx. twice the planned number of unique keys
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);
GO

-- 3. Create table with DURABILITY = SCHEMA_ONLY (Transient/Volatile)
-- Only the structure (schema) is saved to disk. In case of restart,
-- the table will be empty (great for caches and temporary states).
CREATE TABLE lab.SessionCacheMemOnly (
    SessionID uniqueidentifier NOT NULL,
    UserID INT NOT NULL,
    CachedData NVARCHAR(2000) NULL,
    CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_SessionCacheMemOnly PRIMARY KEY NONCLUSTERED (SessionID) -- Default NONCLUSTERED (Bucketless/range Index Seek)
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_ONLY);
GO

-- 4. REAL LAB: Testing the Durability Difference (None vs SCHEMA_ONLY vs SCHEMA_AND_DATA)
-- A. Inserting test data into both tables
INSERT INTO lab.SessionCacheMemData (SessionID, UserID, CachedData) 
VALUES (NEWID(), 101, 'Dados persistentes na RAM e persistidos em Disco');

INSERT INTO lab.SessionCacheMemOnly (SessionID, UserID, CachedData) 
VALUES (NEWID(), 102, 'Dados voláteis apenas na RAM (perda ao reiniciar)');
GO

-- Checking the active data before restart
SELECT 'SessionCacheMemData' AS Tabela, SessionID, UserID, CachedData FROM lab.SessionCacheMemData
UNION ALL
SELECT 'SessionCacheMemOnly', SessionID, UserID, CachedData FROM lab.SessionCacheMemOnly;
GO

-- B. Durability validation.
-- [DP-800 EXAM TIP] Do not take the database OFFLINE in this lab: it drops
-- connections and may affect other users. To observe the actual loss of SCHEMA_ONLY data,
-- run the block below ONLY on a dedicated instance, after recording the results above.
/*
ALTER DATABASE AdventureWorks2025 SET OFFLINE WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE AdventureWorks2025 SET ONLINE;
GO
USE AdventureWorks2025;
GO
*/


-- C. Checking the post-restart result:
-- The SCHEMA_AND_DATA table will have its data preserved.
-- The SCHEMA_ONLY table will be COMPLETELY EMPTY (but its structure/schema continues to exist).
SELECT 'SessionCacheMemData (SCHEMA_AND_DATA)' AS Tabela, COUNT(*) AS QtdRegistros FROM lab.SessionCacheMemData
UNION ALL
SELECT 'SessionCacheMemOnly (SCHEMA_ONLY)', COUNT(*) AS QtdRegistros FROM lab.SessionCacheMemOnly;
GO

-- 5. Memory-Optimized Table Variables
-- Avoid TempDB write overhead.
-- First, create the memory-optimized table type:
CREATE TYPE lab.MyMemoryTableType AS TABLE (
    ItemID INT NOT NULL INDEX IX_ItemID NONCLUSTERED,
    ItemName NVARCHAR(100) NOT NULL
) WITH (MEMORY_OPTIMIZED = ON);
GO

-- Example usage of the memory-optimized table variable:
DECLARE @myTableVar lab.MyMemoryTableType;
INSERT INTO @myTableVar (ItemID, ItemName) VALUES (1, 'Teclado'), (2, 'Mouse');
SELECT * FROM @myTableVar;
GO


-- =================================================================================
-- PART 2: TEMPORAL TABLES (SYSTEM-VERSIONED)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - TEMPORAL TABLES (System-Versioned): Composed of two physical tables working together:
--     1. MAIN TABLE (e.g., lab.EmployeesTemporal): Keeps only the CURRENT and active data state.
--        Any active record has the SysEndTime end date set to the maximum value '9999-12-31 23:59:59.9999999'.
--     2. HISTORY TABLE (e.g., lab.EmployeesTemporalHistory): Stores all past versions of rows
--        that underwent UPDATE or DELETE. SysEndTime marks the exact expiration timestamp of the previous version.
--        Note: The history table is protected and read-only (blocks direct write commands from the application).
--   - PERIOD COLUMNS (SysStartTime / SysEndTime): Mandatory DATETIME2 fields
--     marked with the `GENERATED ALWAYS AS ROW START/END` statement. They record the temporal validity of each record.
--     IMPORTANT: SQL Server always writes these dates in UTC (Universal Time Coordinated), ignoring the local time zone.
--   - SCHEMA OPERATION (DDL): To change the column layout of the main table, you MUST temporarily disable
--     versioning (`SET (SYSTEM_VERSIONING = OFF)`), apply `ALTER TABLE` to both the main and history
--     tables, then re-enable versioning to maintain alignment.
--   - TIME TRAVEL (FOR SYSTEM_TIME AS OF): Optimizer feature that allows querying the exact data state
--     at any past instant. SQL Server automatically UNION ALLs the active table with the history table.
--   - AUDITING: Temporal records versions and UTC timestamps, but does not automatically identify who
--     changed the row. For that, record the application user or use SQL Server Audit/Azure SQL Auditing.

-- 1. Create Temporal Table with explicitly named history table (Best Practice!)
CREATE TABLE lab.EmployeesTemporal (
    EmployeeID INT NOT NULL PRIMARY KEY CLUSTERED,
    Name NVARCHAR(100) NOT NULL,
    Salary DECIMAL(18,2) NOT NULL,
    Department NVARCHAR(50) NOT NULL,
    -- Period columns (mandatory and system-managed)
    SysStartTime DATETIME2(7) GENERATED ALWAYS AS ROW START NOT NULL,
    SysEndTime DATETIME2(7) GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = lab.EmployeesTemporalHistory));
GO

-- 2. Insert some initial records
INSERT INTO lab.EmployeesTemporal (EmployeeID, Name, Salary, Department)
VALUES 
(1, 'Carlos Silva', 5000.00, 'TI'),
(2, 'Ana Costa', 6200.00, 'Financeiro');
GO

-- Let's simulate the passage of time to see historical versioning.
-- Since records need different timestamps, we will pause (WAITFOR).
WAITFOR DELAY '00:00:02';

-- 3. Update employee 1's salary (Generates historical record)
UPDATE lab.EmployeesTemporal
SET Salary = 5500.00
WHERE EmployeeID = 1;
GO

WAITFOR DELAY '00:00:02';

-- 4. Delete employee Ana Costa (Moves the entire current record to history)
DELETE FROM lab.EmployeesTemporal
WHERE EmployeeID = 2;
GO

-- 5. TIME TRAVEL QUERIES
-- A. Current state of the table (only what is active today)
SELECT * FROM lab.EmployeesTemporal;

-- B. View all historical versions (current table + history combined)
SELECT EmployeeID, Name, Salary, SysStartTime, SysEndTime 
FROM lab.EmployeesTemporal
FOR SYSTEM_TIME ALL;

-- C. Point-in-Time Query (How was the table exactly a few seconds ago?)
-- CRITICAL EXAM NOTE: SQL Server System-Versioned Temporal Tables ALWAYS store
-- the period columns (SysStartTime/SysEndTime) in UTC, regardless of the server time zone.
-- Therefore, for comparative point-in-time queries, we MUST use SYSUTCDATETIME()
-- instead of SYSDATETIME(), otherwise the query will search at a time with timezone offset (e.g., UTC-3).
DECLARE @Timestamp DATETIME2 = DATEADD(second, -3, SYSUTCDATETIME());

SELECT EmployeeID, Name, Salary 
FROM lab.EmployeesTemporal
FOR SYSTEM_TIME AS OF @Timestamp;
GO


-- =================================================================================
-- PART 3: LEDGER TABLES (CRYPTOGRAPHIC INTEGRITY PROOF)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - LEDGER: Security feature that provides tracking and cryptographic proof of data integrity (anti-tampering).
--     Each transaction generates a SHA-256 hash and stores records in chained blocks (similar to a blockchain).
--   - UPDATABLE LEDGER: Allows normal updates and deletes. However, old versions are archived
--     automatically in a protected Ledger history table, and changes can be viewed via
--     a special Ledger View (`_Ledger`).
--   - APPEND_ONLY LEDGER: Insert-only tables. Any `UPDATE` or `DELETE` statement is physically
--     blocked by the SQL Server engine natively. Ideal for audit logs and financial records.
--   - DIGESTS AND VERIFICATION (`sp_verify_database_ledger`): To validate that nobody (including sysadmins with root access)
--     has altered the hashes directly in the data files, SQL Server generates signed "digests" (hash blocks)
--     stored in secure external locations (e.g., Immutable Azure Storage). Verification recalculates the hash chain and compares with the digests.
--
-- CRITICAL EXAM NOTE & ARCHITECTURE TRADE-OFF (DATABASE PREPARATION):
-- Ledger audit execution (sp_verify_database_ledger) MANDATORILY requires ALLOW_SNAPSHOT_ISOLATION = ON.
-- IMPLICATIONS AND TRADE-OFFS OF SNAPSHOT ISOLATION IN THE DATABASE:
--   - DISADVANTAGES (TEMPDB AND DISK OVERHEAD):
--     1. Database-Wide Impact: Once activated, ANY UPDATE or DELETE command executed on ANY
--        table in the database will write the previous version of the row to the TempDB Version Store area.
--        This causes significant increases in I/O, disk space, and CPU pressure on TempDB.
--     2. 14-Byte Overhead per Row: Each modified row in the database gains a 14-byte pointer in the header
--        to map its version in TempDB. In very full/dense tables, this can cause physical Page Splits.
--     3. Garbage Collection Process: SQL Server consumes CPU running background threads to clean old versions in TempDB.
--   - ADVANTAGES (CONCURRENCY AND AUDITING):
--     1. Non-Blocking Reads: SELECT queries read TempDB versions without applying Shared Locks,
--        completely eliminating contention between readers and writers.
--     2. Ledger Verification: Enables execution of the sp_verify_database_ledger procedure to audit hashes without locking the database.



-- 1. Updatable Ledger Table
-- Allows standard DML commands, but generates hashes and tracks the audit history cryptographically.
CREATE TABLE lab.SalariesLedger (
    EmployeeID INT NOT NULL PRIMARY KEY CLUSTERED,
    Salary DECIMAL(18,2) NOT NULL
) WITH (SYSTEM_VERSIONING = ON, LEDGER = ON);
GO

-- 2. Append-Only Ledger Table
-- Excellent for logs/auditing. Natively blocks UPDATE and DELETE attempts.
CREATE TABLE lab.FinancialTransactionsLedger (
    TransactionID INT IDENTITY PRIMARY KEY,
    AccountID INT NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    -- Note: Using SYSUTCDATETIME() is best practice for logs/ledger as it aligns with the commit_time column in sys.database_ledger_transactions (UTC).
    TransactionDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
) WITH (LEDGER = ON (APPEND_ONLY = ON));
GO

-- Test 1: Running normal operations on the Updatable Ledger Table
INSERT INTO lab.SalariesLedger (EmployeeID, Salary) VALUES (1, 5000.00), (2, 7500.00);
GO
-- Update salary (Generates audit history record)
UPDATE lab.SalariesLedger SET Salary = 5500.00 WHERE EmployeeID = 1;
GO
-- Delete employee (Generates deletion history record)
DELETE FROM lab.SalariesLedger WHERE EmployeeID = 2;
GO

-- View the automatic ledger history table and the ledger view
-- Note: The SalariesLedger_Ledger view shows the sequential order of all transactions, IDs, and operations (INSERT/DELETE).
SELECT l.EmployeeID,
       l.Salary,
       l.ledger_transaction_id,
       l.ledger_sequence_number,
       l.ledger_operation_type,
       l.ledger_operation_type_desc
FROM   lab.SalariesLedger_Ledger AS l;

-- Test 2: Try to update or delete on the Append-Only table
INSERT  INTO lab.FinancialTransactionsLedger (AccountID, Amount)
VALUES                                      (10, 250.00);


GO
-- 1. Confirm that the insertion was successful on the Append-Only table
SELECT 'Tabela Append-Only (Inserção OK)' AS Status,
       TransactionID,
       AccountID,
       Amount,
       TransactionDate
FROM   lab.FinancialTransactionsLedger;


GO
-- 2. Try UPDATE on Append-Only table (SQL Server aborts the statement with error Msg 37359)
-- We use sp_executesql to isolate compilation and allow CATCH to capture the message.
BEGIN TRY
    EXEC sp_executesql N'UPDATE lab.FinancialTransactionsLedger SET Amount = 1000.00 WHERE TransactionID = 1;';
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO APPEND-ONLY UPDATE: ' + ERROR_MESSAGE();
END CATCH
GO

-- 3. Try DELETE on Append-Only table (SQL Server aborts the statement with error Msg 37359)
BEGIN TRY
    EXEC sp_executesql N'DELETE FROM lab.FinancialTransactionsLedger WHERE TransactionID = 1;';
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO APPEND-ONLY DELETE: ' + ERROR_MESSAGE();
END CATCH
GO
-- 4. Confirm that the inserted record REMAINS intact and unchanged in the table
SELECT 'Registro Mantido Intacto' AS Status,
       TransactionID,
       AccountID,
       Amount,
       TransactionDate
FROM   lab.FinancialTransactionsLedger;


-- 3. Verifying Ledger Table Integrity
-- HOW TO CONFIGURE AND OBTAIN THE DIGEST LOCATION (KEY EXPORT):
--   A. MANUAL GENERATION: The proc 'EXEC sys.sp_generate_database_ledger_digest;' generates a JSON document
--      containing the current block hash. This JSON file is saved to an immutable external location (e.g., WORM storage).
--   B. AUTOMATIC CONFIGURATION (AZURE): In Azure SQL or via Azure CLI, configure "Automatic Digest Storage"
--      pointing to the URL of the immutable Azure Blob Storage container or Azure Confidential Ledger.
--   C. PARAMETER PASSING IN VERIFICATION: To audit, the saved digest JSON content is read and passed in the
--      @digests parameter (or the URL in the @digest_locations parameter) of the sp_verify_database_ledger procedure.

-- Enable the required configuration in the database
ALTER DATABASE AdventureWorks2025 SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
BEGIN TRY
    -- Example: Generate the current digest on demand (returns the hash chain JSON)
    EXEC sys.sp_generate_database_ledger_digest;

    -- In production, the content of the returned/exported JSON file is passed in the @digests parameter:
    -- DECLARE @digests NVARCHAR(MAX) = N'[]';
    DECLARE @digests NVARCHAR(MAX) = N'[{"path":"https://myaccount.blob.core.windows.net/sqldledgermfd/mydb/2026-07-21/...json", "last_digest_block_id": 1, "is_current": true}]';
    EXEC sys.sp_verify_database_ledger @digests = @digests;
    
END TRY
BEGIN CATCH
    PRINT 'NOTA SOBRE VERIFICAÇÃO DE LEDGER: ' + ERROR_MESSAGE();
    -- In a local environment without configured export, the proc warns about the need for the digests JSON.
END CATCH;
GO

-- 4. Restore database configuration to DISABLE Snapshot Isolation and eliminate TempDB overhead
ALTER DATABASE AdventureWorks2025 SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO


-- =================================================================================
-- PART 4: GRAPH TABLES (NETWORK MODELING AND FRAUD DETECTION)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS FOR THE DP-800 EXAM:
--   - GRAPH DATABASE: Enables modeling complex N:M relationships natively with high performance.
--   - NODE TABLES: Graph entities (e.g., People, Credit Cards, IPs). Contain the implicit `$node_id` column.
--   - EDGE TABLES: Directed connections between nodes (e.g., Knows, UsesIP, OwnsCard). Contain `$from_id` and `$to_id`.
--   - CONNECTION CONSTRAINTS: Integrity constraints that define which Node types an Edge can connect.
--   - MATCH() CLAUSE: Allows expressing visual connection patterns in ASCII within the WHERE clause. E.g., `MATCH(P1-(A)->P2)`.
--   - SHORTEST_PATH: Advanced feature to find the shortest path/connection chain of N hops between two nodes.

-- 0. Specific preventive cleanup for Graph objects
-- ORDER RULE: EDGE tables must be dropped BEFORE NODE tables
-- to avoid integrity errors from CONNECTION CONSTRAINTS.
DROP TABLE IF EXISTS lab.OwnsCard;
DROP TABLE IF EXISTS lab.UsedIP;
DROP TABLE IF EXISTS lab.Knows;
DROP TABLE IF EXISTS lab.Supplies;
DROP TABLE IF EXISTS lab.Stores;
DROP TABLE IF EXISTS lab.CreditCard;
DROP TABLE IF EXISTS lab.IPAddress;
DROP TABLE IF EXISTS lab.Person;
DROP TABLE IF EXISTS lab.Supplier;
DROP TABLE IF EXISTS lab.Warehouse;
DROP TABLE IF EXISTS lab.Product;
GO

-- 1. Create the Node Tables
-- GROUP 1: Financial and Security Network (Person, CreditCard, IPAddress)
CREATE TABLE lab.Person (
    PersonID INT IDENTITY PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) NOT NULL
) AS NODE;

CREATE TABLE lab.CreditCard (
    CardID INT IDENTITY PRIMARY KEY,
    CardNumber NVARCHAR(20) NOT NULL,
    Issuer NVARCHAR(50) NOT NULL
) AS NODE;

CREATE TABLE lab.IPAddress (
    IPID INT IDENTITY PRIMARY KEY,
    IPAddress NVARCHAR(45) NOT NULL
) AS NODE;

-- GROUP 2: Logistics Network and Supply Chain (100% Independent from Group 1)
CREATE TABLE lab.Supplier (
    SupplierID INT IDENTITY PRIMARY KEY,
    SupplierName NVARCHAR(100) NOT NULL,
    City NVARCHAR(50) NOT NULL
) AS NODE;

CREATE TABLE lab.Warehouse (
    WarehouseID INT IDENTITY PRIMARY KEY,
    WarehouseName NVARCHAR(100) NOT NULL,
    Location NVARCHAR(50) NOT NULL
) AS NODE;

CREATE TABLE lab.Product (
    ProductID INT IDENTITY PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Category NVARCHAR(50) NOT NULL
) AS NODE;
GO

-- 2. Create the Edge Tables with CONNECTION CONSTRAINTS
-- GROUP 1: Financial Network Edges
CREATE TABLE lab.Knows AS EDGE;

CREATE TABLE lab.OwnsCard (
    CONSTRAINT EC_OwnsCard CONNECTION (lab.Person TO lab.CreditCard)
) AS EDGE;

CREATE TABLE lab.UsedIP (
    CONSTRAINT EC_UsedIP CONNECTION (lab.Person TO lab.IPAddress)
) AS EDGE;

-- GROUP 2: Logistics Network Edges (Supply Chain)
CREATE TABLE lab.Supplies (
    CONSTRAINT EC_Supplies CONNECTION (lab.Supplier TO lab.Warehouse)
) AS EDGE;

CREATE TABLE lab.Stores (
    CONSTRAINT EC_Stores CONNECTION (lab.Warehouse TO lab.Product)
) AS EDGE;
GO

-- 3. Insert Data into Nodes
-- GROUP 1: Financial Network Nodes
-- Note: 'Eve' is inserted with NO edges to demonstrate detection of an Isolated Node (Disconnected Island) from Group 1
INSERT INTO lab.Person (Name, Email) 
VALUES ('Alice', 'alice@empresa.com'),
       ('Bob', 'bob@empresa.com'),
       ('Charlie', 'charlie@empresa.com'),
       ('David', 'david@empresa.com'),
       ('Eve', 'eve@empresa.com');

INSERT INTO lab.CreditCard (CardNumber, Issuer)
VALUES ('4111-XXXX-XXXX-1111', 'Visa'),
       ('5500-YYYY-YYYY-2222', 'MasterCard');

INSERT INTO lab.IPAddress (IPAddress)
VALUES ('192.168.1.100'),
       ('10.0.0.5');

-- GROUP 2: Logistics Network Nodes (Supply Chain)
-- Note: 'FornecedorInativo Corp' and 'ItemObsoleto SemEstoque' are inserted without edges to test Isolated Nodes in Group 2!
INSERT INTO lab.Supplier (SupplierName, City)
VALUES ('TechComponents SA', 'São Paulo'),
       ('LogisticaGlobal LTDA', 'Curitiba'),
       ('FornecedorInativo Corp', 'Rio de Janeiro');

INSERT INTO lab.Warehouse (WarehouseName, Location)
VALUES ('Centro de Distribuição Principal', 'Campinas'),
       ('Depósito Regional Sul', 'Joinville');

INSERT INTO lab.Product (ProductName, Category)
VALUES ('Servidor Rack 2U', 'Hardware'),
       ('Switch L3 48p', 'Redes'),
       ('ItemObsoleto SemEstoque', 'Descontinuado');
GO

-- 4. Insert Relationships into Edges ($from_id -> $to_id)
-- GROUP 1: Financial Network Relationships
-- A. Friendships between People (Knows)
INSERT INTO lab.Knows ($from_id, $to_id)
VALUES 
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Alice'), (SELECT $node_id FROM lab.Person WHERE Name = 'Bob')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Bob'), (SELECT $node_id FROM lab.Person WHERE Name = 'Charlie')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Charlie'), (SELECT $node_id FROM lab.Person WHERE Name = 'David'));

-- B. Credit Cards owned by People (OwnsCard)
-- Fraud Analysis Note: Alice and Bob share THE SAME credit card!
INSERT INTO lab.OwnsCard ($from_id, $to_id)
VALUES 
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Alice'), (SELECT $node_id FROM lab.CreditCard WHERE CardNumber = '4111-XXXX-XXXX-1111')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Bob'), (SELECT $node_id FROM lab.CreditCard WHERE CardNumber = '4111-XXXX-XXXX-1111')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Charlie'), (SELECT $node_id FROM lab.CreditCard WHERE CardNumber = '5500-YYYY-YYYY-2222'));

-- C. Access IPs used by People (UsedIP)
-- Fraud Analysis Note: Bob and Charlie accessed using THE SAME IP address!
INSERT INTO lab.UsedIP ($from_id, $to_id)
VALUES 
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Alice'), (SELECT $node_id FROM lab.IPAddress WHERE IPAddress = '10.0.0.5')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Bob'), (SELECT $node_id FROM lab.IPAddress WHERE IPAddress = '192.168.1.100')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Charlie'), (SELECT $node_id FROM lab.IPAddress WHERE IPAddress = '192.168.1.100'));

-- GROUP 2: Logistics Network Relationships (Supplies & Stores)
INSERT INTO lab.Supplies ($from_id, $to_id)
VALUES 
    ((SELECT $node_id FROM lab.Supplier WHERE SupplierName = 'TechComponents SA'), (SELECT $node_id FROM lab.Warehouse WHERE WarehouseName = 'Centro de Distribuição Principal')),
    ((SELECT $node_id FROM lab.Supplier WHERE SupplierName = 'LogisticaGlobal LTDA'), (SELECT $node_id FROM lab.Warehouse WHERE WarehouseName = 'Depósito Regional Sul'));

INSERT INTO lab.Stores ($from_id, $to_id)
VALUES 
    ((SELECT $node_id FROM lab.Warehouse WHERE WarehouseName = 'Centro de Distribuição Principal'), (SELECT $node_id FROM lab.Product WHERE ProductName = 'Servidor Rack 2U')),
    ((SELECT $node_id FROM lab.Warehouse WHERE WarehouseName = 'Depósito Regional Sul'), (SELECT $node_id FROM lab.Product WHERE ProductName = 'Switch L3 48p'));
GO

-- =================================================================================
-- GRAPH ANALYSIS QUERIES (DP-800 EXAM)
-- =================================================================================
-- HOW SQL SERVER EXECUTES MATCH() INTERNALLY:
-- Although the FROM clause lists tables separated by commas (syntax similar to a Cartesian Product),
-- the SQL Server compiler intercepts MATCH() and converts the search into highly optimized JOINs
-- between the hidden system columns:
--   - P1.$node_id = O1.$from_id (Source Node connects to the Edge)
--   - O1.$to_id = C.$node_id (Edge connects to the Destination Node)
--   - C.$node_id = O2.$to_id (Return Path: The same Node connects to another inbound Edge)
--   - O2.$from_id = P2.$node_id (Edge connects to the second Person)

-- 0. MASTER MAP: View the ENTIRE Graph Relationship Tree (Network Overview)
SELECT 
    'Pessoa' AS TipoOrigem,
    P.Name AS EntidadeOrigem,
    'Possui Cartão' AS Relacionamento,
    'Cartão de Crédito' AS TipoDestino,
    C.CardNumber AS EntidadeDestino,
    '[Pessoa: ' + P.Name + '] --- (Possui Cartão) ---> [Cartão: ' + C.CardNumber + ']' AS ArvoreVisual
FROM lab.Person P, lab.OwnsCard O, lab.CreditCard C
WHERE MATCH(P-(O)->C)

UNION ALL

SELECT 
    'Pessoa' AS TipoOrigem,
    P.Name AS EntidadeOrigem,
    'Acessou pelo IP' AS Relacionamento,
    'Endereço IP' AS TipoDestino,
    IP.IPAddress AS EntidadeDestino,
    '[Pessoa: ' + P.Name + '] --- (Acessou IP) ---> [IP: ' + IP.IPAddress + ']' AS ArvoreVisual
FROM lab.Person P, lab.UsedIP U, lab.IPAddress IP
WHERE MATCH(P-(U)->IP)

UNION ALL

SELECT 
    'Pessoa' AS TipoOrigem,
    P1.Name AS EntidadeOrigem,
    'Amigo de / Conhece' AS Relacionamento,
    'Pessoa' AS TipoDestino,
    P2.Name AS EntidadeDestino,
    '[Pessoa: ' + P1.Name + '] --- (Conhece) ---> [Pessoa: ' + P2.Name + ']' AS ArvoreVisual
FROM lab.Person P1, lab.Knows K, lab.Person P2
WHERE MATCH(P1-(K)->P2)

ORDER BY EntidadeOrigem, Relacionamento;
GO

-- 1. FRAUD DETECTION 1: Find Distinct Customers Sharing the Same Credit Card
-- MATCH() ROUND-TRIP SCHEME:
--   [Person 1: Alice] ----(O1: OwnsCard)----> [Card: Visa 4111] <----(O2: OwnsCard)---- [Person 2: Bob]
--    (Source Node Outbound)                   (Meeting Node)                            (Source Node Return)
SELECT 
    P1.Name + ' ===[ CARTÃO COMPARTILHADO: ' + C.CardNumber + ' ]===> ' + P2.Name AS AlertaFraudeVisual,
    P1.Name AS Cliente1,
    P2.Name AS Cliente2,
    C.CardNumber AS CartaoCompartilhado
FROM lab.Person P1, lab.OwnsCard O1, lab.CreditCard C, lab.OwnsCard O2, lab.Person P2
WHERE MATCH(P1-(O1)->C<-(O2)-P2)
  AND P1.PersonID < P2.PersonID; -- Avoids duplicates and mirrored pairs (Alice+Bob vs Bob+Alice)
GO

-- 2. FRAUD DETECTION 2: Find Customers Sharing the Same Access IP
-- MATCH() ROUND-TRIP SCHEME:
--   [Person 1: Bob] ----(U1: UsedIP)----> [IP: 192.168.1.100] <----(U2: UsedIP)---- [Person 2: Charlie]
SELECT 
    P1.Name + ' ===[ IP COMPARTILHADO: ' + IP.IPAddress + ' ]===> ' + P2.Name AS AlertaSuspeitoIP,
    P1.Name AS Cliente1,
    P2.Name AS Cliente2,
    IP.IPAddress AS IPCompartilhado
FROM lab.Person P1, lab.UsedIP U1, lab.IPAddress IP, lab.UsedIP U2, lab.Person P2
WHERE MATCH(P1-(U1)->IP<-(U2)-P2)
  AND P1.PersonID < P2.PersonID;
GO

-- 3. STAR FRAUD DETECTION (MULTI-LEVEL 4-HOP FRAUD CHAIN):
-- COMPLETE SCHEME:
--   (Alice) --[Owns]--> (Card) <--[Owns]-- (Bob) --[UsesIP]--> (IP) <--[UsesIP]-- (Charlie)
--   Hop 1               Hop 2            Mid Point   Hop 3          Hop 4
SELECT 
    P1.Name AS Origem,
    Card.CardNumber AS CartaoEmComum,
    P2.Name AS Intermediario,
    IP.IPAddress AS IPEmComum,
    P3.Name AS DestinoSuspeito
FROM lab.Person P1, lab.OwnsCard O1, lab.CreditCard Card, lab.OwnsCard O2, lab.Person P2,
     lab.UsedIP U1, lab.IPAddress IP, lab.UsedIP U2, lab.Person P3
WHERE MATCH(P1-(O1)->Card<-(O2)-P2-(U1)->IP<-(U2)-P3)
  AND P1.PersonID <> P3.PersonID;
GO

-- 4. RECURSIVE TRAVERSAL WITH SHORTEST_PATH (FIND THE SHORTEST N-HOP CONNECTION CHAIN)
-- DP-800 Requirement: Find the shortest friendship path between Alice and David (N hops)
-- RECURSIVE TRAVERSAL SCHEME: (Alice) ----[Knows]----> (Bob) ----[Knows]----> (Charlie) ----[Knows]----> (David)
SELECT 
    P1.Name AS PessoaInicial,
    STRING_AGG(P2.Name, ' -> ') WITHIN GROUP (GRAPH PATH) AS CadeiaDeConexao,
    LAST_VALUE(P2.Name) WITHIN GROUP (GRAPH PATH) AS PessoaFinal
FROM lab.Person P1,
     lab.Knows FOR PATH K,
     lab.Person FOR PATH P2
WHERE MATCH(SHORTEST_PATH(P1(-(K)->P2)+))
  AND P1.Name = 'Alice'
  AND LAST_VALUE(P2.Name) WITHIN GROUP (GRAPH PATH) = 'David';
GO

-- 5. DETECTION OF ISOLATED NODES (DISCONNECTED ISLANDS WITHOUT EDGES)
-- Graph Analysis: Identifies registered entities in the database that have NO edge connections attached
-- DP-800 REQUIREMENT: The MATCH() operator does not allow logical OR operators within its expression.
-- To validate outbound and inbound directions with OR, we must separate into distinct MATCH() clauses or separate NOT EXISTS.
SELECT 
    P.Name AS PessoaIsolada,
    P.Email,
    'ALERTA: Nó no Grafo sem nenhuma Aresta conectada (Ilha Desconectada)' AS StatusConexao
FROM lab.Person P
WHERE NOT EXISTS (
    SELECT 1 FROM lab.OwnsCard O, lab.CreditCard C WHERE MATCH(P-(O)->C)
)
AND NOT EXISTS (
    SELECT 1 FROM lab.UsedIP U, lab.IPAddress IP WHERE MATCH(P-(U)->IP)
)
AND NOT EXISTS (
    SELECT 1 FROM lab.Knows K, lab.Person P2 WHERE MATCH(P-(K)->P2)
)
AND NOT EXISTS (
    SELECT 1 FROM lab.Knows K, lab.Person P2 WHERE MATCH(P<-(K)-P2)
);
GO

-- 6. AUTOMATIC MERMAID DIAGRAM GENERATOR (DYNAMIC SQL FROM GRAPH -> MERMAID.JS)
-- Copy the results of this query and paste into any Markdown viewer to render the visual map (https://mermaid.live/)
-- NOTE: Groups nodes by Connected Components (Main Network vs Isolated Nodes).
SELECT MermaidCode
FROM (
    SELECT 1 AS SortOrder, 'graph LR' AS MermaidCode
    UNION ALL
    SELECT 2 AS SortOrder, '    subgraph "Rede Principal de Conexões e Fraudes"' AS MermaidCode
    UNION ALL
    SELECT DISTINCT 3 AS SortOrder, '        ' + REPLACE(P.Name, ' ', '_') + '["Pessoa: ' + P.Name + '"]'
    FROM lab.Person P
    WHERE P.Name <> 'Eve'
    UNION ALL
    SELECT DISTINCT 3 AS SortOrder, '        C_' + REPLACE(REPLACE(C.CardNumber, '-', '_'), ' ', '_') + '["Cartão: ' + C.CardNumber + '"]' FROM lab.CreditCard C
    UNION ALL
    SELECT DISTINCT 3 AS SortOrder, '        IP_' + REPLACE(IP.IPAddress, '.', '_') + '["IP: ' + IP.IPAddress + '"]' FROM lab.IPAddress IP
    UNION ALL
    SELECT DISTINCT 4 AS SortOrder, '        ' + REPLACE(P.Name, ' ', '_') + ' -- "Possui" --> C_' + REPLACE(REPLACE(C.CardNumber, '-', '_'), ' ', '_')
    FROM lab.Person P, lab.OwnsCard O, lab.CreditCard C
    WHERE MATCH(P-(O)->C)
    UNION ALL
    SELECT DISTINCT 4 AS SortOrder, '        ' + REPLACE(P.Name, ' ', '_') + ' -- "Acessou IP" --> IP_' + REPLACE(IP.IPAddress, '.', '_')
    FROM lab.Person P, lab.UsedIP U, lab.IPAddress IP
    WHERE MATCH(P-(U)->IP)
    UNION ALL
    SELECT DISTINCT 4 AS SortOrder, '        ' + REPLACE(P1.Name, ' ', '_') + ' -- "Conhece" --> ' + REPLACE(P2.Name, ' ', '_')
    FROM lab.Person P1, lab.Knows K, lab.Person P2
    WHERE MATCH(P1-(K)->P2)
    UNION ALL
    SELECT 5 AS SortOrder, '    end' AS MermaidCode
    UNION ALL
    SELECT 6 AS SortOrder, '    subgraph "Nós Isolados (Ilhas sem Conexão)"' AS MermaidCode
    UNION ALL
    SELECT DISTINCT 7 AS SortOrder, '        ' + REPLACE(P.Name, ' ', '_') + '["Pessoa: ' + P.Name + '"]'
    FROM lab.Person P
    WHERE P.Name = 'Eve'
    UNION ALL
    SELECT 8 AS SortOrder, '    end' AS MermaidCode
) AS MermaidData
ORDER BY SortOrder;
GO

-- 7. ENCAPSULATION IN A 100% DYNAMIC STORED PROCEDURE: lab.sp_generate_mermaid_graph
-- This Procedure inspects the database metadata (sys.tables where is_node = 1 and is_edge = 1)
-- in a 100% GENERIC WAY (NO HARDCODING), dynamically building clauses for any graph database!
CREATE OR ALTER PROCEDURE lab.sp_generate_mermaid_graph
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#MermaidLines') IS NOT NULL DROP TABLE #MermaidLines;
    CREATE TABLE #MermaidLines (SortOrder INT, LineContent NVARCHAR(MAX));

    -- 1. BUILD THE DYNAMIC CONNECTION PREDICATE AGAINST ALL EDGE TABLES IN THE DATABASE
    DECLARE @AllEdgesExistsClause NVARCHAR(MAX) = N'';

    SELECT @AllEdgesExistsClause = STRING_AGG(
        N'EXISTS (SELECT 1 FROM ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N' WHERE $from_id = N.$node_id OR $to_id = N.$node_id)',
        N' OR '
    )
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.is_edge = 1;

    IF ISNULL(@AllEdgesExistsClause, N'') = N''
        SET @AllEdgesExistsClause = N'1 = 0';

    INSERT INTO #MermaidLines VALUES (1, 'graph LR');

    -- 2. SUBGRAPH FOR CONNECTED NODES (RELATIONSHIP NETWORK)
    INSERT INTO #MermaidLines VALUES (2, '    subgraph "Rede Principal de Conexões"');

    DECLARE @NodeSchema NVARCHAR(128), @NodeTable NVARCHAR(128), @DisplayCol NVARCHAR(128), @SQL NVARCHAR(MAX);

    DECLARE node_cursor CURSOR FOR 
    SELECT s.name AS SchemaName, t.name AS TableName,
           ISNULL((SELECT TOP 1 c.name FROM sys.columns c WHERE c.object_id = t.object_id AND c.is_hidden = 0 AND c.name NOT LIKE '%ID%' ORDER BY c.column_id),
                  (SELECT TOP 1 c.name FROM sys.columns c WHERE c.object_id = t.object_id AND c.is_hidden = 0 ORDER BY c.column_id)) AS FirstUserCol
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.is_node = 1;

    OPEN node_cursor;
    FETCH NEXT FROM node_cursor INTO @NodeSchema, @NodeTable, @DisplayCol;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Nodes that have connections in any edge registered in the metadata
        SET @SQL = N'INSERT INTO #MermaidLines ' +
                   N'SELECT 3, ''        N_'' + CONVERT(VARCHAR(32), HASHBYTES(''MD5'', N.$node_id), 2) + ' +
                   N'''["' + @NodeTable + ': '' + ISNULL(CAST(N.' + QUOTENAME(@DisplayCol) + N' AS NVARCHAR(100)), ''N/A'') + ''"]'' ' +
                   N'FROM ' + QUOTENAME(@NodeSchema) + N'.' + QUOTENAME(@NodeTable) + N' N ' +
                   N'WHERE (' + @AllEdgesExistsClause + N');';
        EXEC sp_executesql @SQL;

        FETCH NEXT FROM node_cursor INTO @NodeSchema, @NodeTable, @DisplayCol;
    END;

    CLOSE node_cursor;

    -- Edges/Connections within the Main Network (Dynamically inspects all EDGE tables)
    DECLARE @EdgeSchema NVARCHAR(128), @EdgeTable NVARCHAR(128);

    DECLARE edge_cursor CURSOR FOR 
    SELECT s.name AS SchemaName, t.name AS TableName
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.is_edge = 1;

    OPEN edge_cursor;
    FETCH NEXT FROM edge_cursor INTO @EdgeSchema, @EdgeTable;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'INSERT INTO #MermaidLines ' +
                   N'SELECT 4, ''        N_'' + CONVERT(VARCHAR(32), HASHBYTES(''MD5'', $from_id), 2) + ' +
                   N''' -- "' + @EdgeTable + N'" --> N_'' + CONVERT(VARCHAR(32), HASHBYTES(''MD5'', $to_id), 2) ' +
                   N'FROM ' + QUOTENAME(@EdgeSchema) + N'.' + QUOTENAME(@EdgeTable) + N';';
        EXEC sp_executesql @SQL;

        FETCH NEXT FROM edge_cursor INTO @EdgeSchema, @EdgeTable;
    END;

    CLOSE edge_cursor;
    DEALLOCATE edge_cursor;

    INSERT INTO #MermaidLines VALUES (5, '    end');

    -- 3. SUBGRAPH FOR ISOLATED NODES (ISLANDS WITHOUT CONNECTION)
    INSERT INTO #MermaidLines VALUES (6, '    subgraph "Nós Isolados (Ilhas sem Conexão)"');

    OPEN node_cursor;
    FETCH NEXT FROM node_cursor INTO @NodeSchema, @NodeTable, @DisplayCol;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Nodes that do NOT have connections in ANY edge (Dynamic NOT inversion)
        SET @SQL = N'INSERT INTO #MermaidLines ' +
                   N'SELECT 7, ''        N_'' + CONVERT(VARCHAR(32), HASHBYTES(''MD5'', N.$node_id), 2) + ' +
                   N'''["' + @NodeTable + ': '' + ISNULL(CAST(N.' + QUOTENAME(@DisplayCol) + N' AS NVARCHAR(100)), ''N/A'') + ''"]'' ' +
                   N'FROM ' + QUOTENAME(@NodeSchema) + N'.' + QUOTENAME(@NodeTable) + N' N ' +
                   N'WHERE NOT (' + @AllEdgesExistsClause + N');';
        EXEC sp_executesql @SQL;

        FETCH NEXT FROM node_cursor INTO @NodeSchema, @NodeTable, @DisplayCol;
    END;

    CLOSE node_cursor;
    DEALLOCATE node_cursor;

    INSERT INTO #MermaidLines VALUES (8, '    end');

    -- Display the generated Mermaid code in sequential line order
    SELECT LineContent AS MermaidCodeFromMetadata
    FROM #MermaidLines
    ORDER BY SortOrder;
END;
GO

-- Test execution of the 100% Dynamic and Generic Stored Procedure:
-- The Procedure scans sys.tables filtering by is_node = 1 and is_edge = 1.
-- Since we created TWO 100% independent graph groups (Financial/Security Network + Logistics/Supply Chain):
-- 1. The Procedure automatically detects the 6 Node tables (Person, CreditCard, IPAddress, Supplier, Warehouse, Product).
-- 2. The Procedure automatically detects the 5 Edge tables (Knows, OwnsCard, UsedIP, Supplies, Stores).
-- 3. The Procedure includes in the connected subgraph all nodes from BOTH networks that have relationships.
-- 4. The Procedure detects and inserts into the "Isolated Nodes" subgraph the disconnected islands from BOTH groups (Eve, FornecedorInativo Corp, ItemObsoleto SemEstoque).
-- ALL WITHOUT ANY HARDCODING OR CHANGES TO THE PROCEDURE CODE!
EXEC lab.sp_generate_mermaid_graph;
GO


-- =================================================================================
-- PART 5: EXTERNAL TABLES & DATA VIRTUALIZATION (POLYBASE / DATA LAKE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS (DP-800):
--   - EXTERNAL TABLES (PolyBase): Data virtualization feature that allows SQL Server / Synapse
--     to query files stored outside the database (e.g., Azure Blob Storage, Azure Data Lake Gen2, S3, HDFS)
--     as if they were local relational tables, without physically importing the data.
--   - DATABASE SCOPED CREDENTIAL: A database-level security object that encapsulates authentication credentials
--     (storage account keys, SAS tokens, managed identities) required to access the external storage.
--   - EXTERNAL DATA SOURCE: Defines the logical connection pointing to the physical external storage endpoint
--     (bucket/container URL) and associates the respective created scoped credential.
--   - EXTERNAL FILE FORMAT: Defines the formatting properties of the files residing in storage
--     (e.g., PARQUET or CSV DELIMITEDTEXT file type, Snappy/Gzip compression type, field delimiters, etc.).
--   - EXTERNAL TABLE: A virtual table that links the relational column structure (SQL types) to the physical file
--     location (LOCATION) referencing the data source (DATA_SOURCE) and format (FILE_FORMAT).

-- ---------------------------------------------------------------------------------
-- EXAMPLE 1A: BULK INSERT - IMPORT CSV LOCALLY (SQL SERVER 2022 LOCAL)
-- ---------------------------------------------------------------------------------
-- Test file: practice/labs/data/sales_data.csv (CRLF — Windows standard)
--
-- ⚠️ ATTENTION POINT 1 — CSV in SQL Server:
--   * SQL Server 2017+ supports FORMAT = 'CSV' for RFC 4180-compatible files.
--   * FORMAT = 'CSV' can be combined with FIELDTERMINATOR, ROWTERMINATOR, and FIELDQUOTE.
--   * This example uses the classic mode to highlight delimiters; prefer FORMAT = 'CSV'
--     when you need to properly handle quoted fields containing commas.
--
-- ⚠️ ATTENTION POINT 2 — ROWTERMINATOR depends on the file encoding:
--
--   SCENARIO A — CSV saved on Windows/Excel (CRLF = 0x0D 0x0A):
--     ROWTERMINATOR = '\r\n'    ← string literal   (works ✅)
--     ROWTERMINATOR = '0x0d0a'  ← equivalent hex   (also works ✅)
--
--   SCENARIO B — CSV saved on Linux/Mac/Git (pure LF = 0x0A):
--     ROWTERMINATOR = '0x0a'    ← MANDATORY to use hex (✅)
--     ROWTERMINATOR = '\n'      ← Does NOT work on Windows SQL Server (❌ empty table!)
--     → Why? SQL Server interprets '\n' as 2 literal chars (\+n),
--       not as byte 0x0A, so it never finds the line terminator.
--
--   How to detect your CSV encoding (PowerShell):
--     [System.IO.File]::ReadAllBytes('arquivo.csv') | % { '{0:X2}' -f $_ } | Select -Last 4
--     → Ends in "0D 0A" = CRLF (Scenario A) → use '\r\n'
--     → Ends in "0A"    = LF   (Scenario B) → use '0x0a'
--
-- The sales_data.csv file for this lab uses CRLF (Scenario A) — tested and functional.
-- ---------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#SalesImport') IS NOT NULL DROP TABLE #SalesImport;
CREATE TABLE #SalesImport (
    SaleID      INT,
    ProductName VARCHAR(100),
    Amount      DECIMAL(18,2),
    SaleDate    DATE
);
-- Adjust the path if the repository is in another directory.
BULK INSERT #SalesImport
FROM 'd:\source\dp-800-study-guide\practice\labs\data\sales_data.csv'
WITH (
    FIRSTROW        = 2,          -- Skip header row
    FIELDTERMINATOR = ',',        -- Column separator
    ROWTERMINATOR   = '0x0d0a',   -- ✅ CRLF as explicit hex (safe default on SQL Server Windows)
    -- ROWTERMINATOR = '0x0a',    -- Use this if the CSV uses pure LF (Linux/Mac/Git)
    TABLOCK,                      -- Table lock: better performance for batch load
    MAXERRORS       = 0           -- Abort immediately on any error
);

SELECT SaleID, ProductName, Amount, SaleDate FROM #SalesImport;
GO


/* -- EXAMPLE 1B: OPENROWSET WITH FORMAT='CSV' AND PARSER_VERSION (AZURE SYNAPSE SERVERLESS ONLY)
-- Execute this block in Azure Synapse Analytics Serverless SQL Pool, NOT in local SQL Server.
SELECT 
    SalesCSV.SaleID,
    SalesCSV.ProductName,
    SalesCSV.Amount,
    SalesCSV.SaleDate
FROM OPENROWSET(
    BULK 'd:\source\dp-800-study-guide\practice\labs\data\sales_data.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',  -- Supported only in Synapse Serverless v2 parser
    FIRSTROW = 2
) WITH (
    SaleID INT,
    ProductName VARCHAR(100),
    Amount DECIMAL(18,2),
    SaleDate DATE
) AS SalesCSV;
GO
*/

/*
-- ---------------------------------------------------------------------------------

-- EXAMPLE 2: COMPLETE DDL FOR EXTERNAL TABLES (DP-800 & SYNAPSE/POLYBASE REQUIREMENT)
-- Official Reference: Microsoft SQL DW / Synapse Samples
-- (https://github.com/microsoft/sql-server-samples/blob/master/samples/demos/SQLDW/free-trial-lab/create-external-tables.sql)
-- ---------------------------------------------------------------------------------
-- 1. Create CSV File Format (Delimited Text)
CREATE EXTERNAL FILE FORMAT CSVFileFormat
WITH (
    FORMAT_TYPE = DELIMITEDTEXT,
    FORMAT_OPTIONS (
        FIELD_TERMINATOR = ',',
        STRING_DELIMITER = '"',
        FIRST_ROW = 2,
        USE_TYPE_DEFAULT = TRUE
    )
);
GO

-- 2. Create PARQUET File Format (Snappy Compression)
CREATE EXTERNAL FILE FORMAT ParquetFileFormat
WITH (
    FORMAT_TYPE = PARQUET,
    DATA_COMPRESSION = 'org.apache.hadoop.io.compress.SnappyCodec'
);
GO

-- 3. Create Database Scoped Credential (SAS Token / Shared Key)
CREATE DATABASE SCOPED CREDENTIAL [MyStorageCredential]
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = 'sv=2021-06-08&ss=bfqt&srt=sco&sp=rwdlacupx...'; -- SAS Token from Azure Storage
GO

-- 4. Create External Data Source (Azure Data Lake Storage Gen2 / Blob Storage)
CREATE EXTERNAL DATA SOURCE AzureBlobStorageSales
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://myaccount.blob.core.windows.net/salesdata',
    CREDENTIAL = [MyStorageCredential]
);
GO

-- 5. Create External Table Mapped to Files in Data Lake
CREATE EXTERNAL TABLE lab.ExternalSalesOrders (
    SalesOrderID INT NOT NULL,
    OrderDate DATETIME2 NULL,
    CustomerID INT NULL,
    TotalDue DECIMAL(18,2) NULL
)
WITH (
    LOCATION = '/parquet_exports/2026/',
    DATA_SOURCE = AzureBlobStorageSales,
    FILE_FORMAT = ParquetFileFormat
);
GO
*/
-- =========================================================================
-- EXAMPLE 3: NYC TAXI - AZURE OPEN DATASETS (CORRECT URLs FROM OFFICIAL DOCUMENTATION)
-- =========================================================================
-- OFFICIAL SOURCE: https://learn.microsoft.com/en-us/azure/open-datasets/dataset-taxi-yellow
--
-- ✅ CORRECT URL:
--   Storage Account : azureopendatastorage
--   Container       : nyctlc            (NOT "azureopen/yellowtripdata")
--   Yellow Taxi     : nyctlc/yellow/
--   Green Taxi      : nyctlc/green/
--
-- Folder structure (Hive partitioning):
--   nyctlc/yellow/puYear=<year>/puMonth=<month>/<file>.parquet
--   nyctlc/green/puYear=<year>/puMonth=<month>/<file>.parquet
--
-- Protocol for OPENROWSET in Synapse Serverless SQL:
--   abs://<container>@<account>.blob.core.windows.net/<path>
--   abs://nyctlc@azureopendatastorage.blob.core.windows.net/yellow/puYear=2018/puMonth=6/*.parquet
--
-- ⚠️  COLUMNS: camelCase  (NOT snake_case!)
--   tpepPickupDateTime   (NOT tpep_pickup_datetime)
--   tpepDropoffDateTime  (NOT tpep_dropoff_datetime)
--   fareAmount, totalAmount, passengerCount, tripDistance ...
-- =========================================================================

-- -----------------------------------------------------------------------
-- EXAMPLE 3A-1: SINGLE FILE QUERY (ONE SPECIFIC MONTH)
-- Execute on: Azure Synapse Serverless SQL Pool or Azure SQL + PolyBase
-- -----------------------------------------------------------------------
-- Reads only one set of parquet files from a specific month/year
SELECT TOP 100
    *
FROM OPENROWSET(
    -- abs:// = Azure Blob Storage URI scheme — works on Synapse Serverless
    -- *.parquet = wildcard for all files in the month (can be subdivided into chunks)
    BULK 'abs://nyctlc@azureopendatastorage.blob.core.windows.net/yellow/puYear=2018/puMonth=6/*.parquet',
    FORMAT = 'PARQUET'
) AS TaxiYellow2018Jun
ORDER BY tpepPickupDateTime;
GO

-- -----------------------------------------------------------------------
-- EXAMPLE 3A-2: FULL FOLDER QUERY (MULTIPLE YEARS/MONTHS)
-- Uses ** wildcard to recursively scan all partitions
-- -----------------------------------------------------------------------

SELECT 
    COUNT(*)                        AS TotalCorridas
    --AVG(fareAmount)                 AS TarifaMedia,
    --AVG(passengerCount)             AS PassageirosMedio,
    --SUM(totalAmount)                AS FaturamentoTotal
FROM OPENROWSET(
    -- ** = recursive wildcard: reads ALL year/month partitions at once
    BULK 'abs://nyctlc@azureopendatastorage.blob.core.windows.net/yellow/**',
    FORMAT = 'PARQUET'
) AS TaxiYellowAll

GO

-- -----------------------------------------------------------------------
-- EXAMPLE 3B: COMPLETE DDL FOR EXTERNAL TABLES (DEDICATED SYNAPSE SQL / POLYBASE)
-- For use in Azure Synapse Analytics Dedicated SQL Pool.
-- NOTE: Public containers do NOT require DATABASE SCOPED CREDENTIAL!
-- -----------------------------------------------------------------------

-- -----------------------------------------------------------------------
-- EXAMPLE 3B: CREATE EXTERNAL TABLE — DP-800 REQUIREMENT (REFERENCE)
-- ⚠️  This block IS REFERENCE FOR THE EXAM — do not run locally!
-- -----------------------------------------------------------------------
-- CAUSE OF ERROR Msg 46525 "External tables not supported with data source type":
--
--   TYPE = BLOB_STORAGE → ONLY for BULK INSERT and ad-hoc OPENROWSET
--                          Does NOT support CREATE EXTERNAL TABLE
--
--   TYPE = HADOOP        → Required for CREATE EXTERNAL TABLE
--                          Requires PolyBase enabled on SQL Server
--
-- COMPATIBILITY MATRIX:
-- ┌─────────────────────────────┬─────────────┬──────────────────┬──────────────────┐
-- │ Operation                    │ SQL Local   │ Synapse Serverl. │ Synapse Dedicated │
-- ├─────────────────────────────┼─────────────┼──────────────────┼──────────────────┤
-- │ BULK INSERT                 │ ✅ BLOB_ST. │ ✅               │ ✅               │
-- │ OPENROWSET(BULK...)         │ ✅ BLOB_ST. │ ✅ (abs://)      │ ✅               │
-- │ CREATE EXTERNAL TABLE       │ ✅ HADOOP   │ ✅ (no DDL)      │ ✅ HADOOP/abfss  │
-- │ TYPE = BLOB_STORAGE + ExTab │ ❌ Msg 46525│ ❌               │ ❌               │
-- └─────────────────────────────┴─────────────┴──────────────────┴──────────────────┘
--
/* ============================================================
   DDL FOR SQL SERVER 2022 ON-PREMISES + POLYBASE
   Requirement: PolyBase Feature installed and enabled
   sp_configure 'polybase enabled', 1; RECONFIGURE;
   ============================================================

-- SQL Server 2022: uses TYPE = HADOOP with wasbs:// protocol
CREATE EXTERNAL DATA SOURCE NYC_Taxi_Yellow_PolyBase
WITH (
    TYPE = HADOOP,
    LOCATION = 'wasbs://nyctlc@azureopendatastorage.blob.core.windows.net'
    -- Public container: no CREDENTIAL needed
);
GO

CREATE EXTERNAL FILE FORMAT NycTaxiParquet
WITH (
    FORMAT_TYPE = PARQUET,
    DATA_COMPRESSION = 'org.apache.hadoop.io.compress.SnappyCodec'
);
GO

CREATE EXTERNAL TABLE lab.ExternalYellowTaxi (
    vendorID              VARCHAR(10),
    tpepPickupDateTime    DATETIME2(7),
    tpepDropoffDateTime   DATETIME2(7),
    passengerCount        INT,
    tripDistance          FLOAT,
    puLocationId          VARCHAR(10),
    doLocationId          VARCHAR(10),
    rateCodeId            INT,
    storeAndFwdFlag       CHAR(2),
    paymentType           INT,
    fareAmount            FLOAT,
    extra                 FLOAT,
    mtaTax                FLOAT,
    improvementSurcharge  VARCHAR(10),
    tipAmount             FLOAT,
    tollsAmount           FLOAT,
    totalAmount           FLOAT,
    puYear                INT,
    puMonth               INT
)
WITH (
    LOCATION = 'yellow/',
    DATA_SOURCE = NYC_Taxi_Yellow_PolyBase,
    FILE_FORMAT = NycTaxiParquet,
    REJECT_TYPE = VALUE,
    REJECT_VALUE = 0
);
GO
============================================================ */

/* ============================================================
   DDL FOR AZURE SYNAPSE ANALYTICS DEDICATED SQL POOL
   Uses abfss:// (Azure Data Lake Storage Gen2) or wasbs://
   ============================================================

-- Synapse Dedicated: TYPE = HADOOP with abfss://
CREATE EXTERNAL DATA SOURCE NYC_Taxi_ADLS
WITH (
    TYPE = HADOOP,
    LOCATION = 'abfss://nyctlc@azureopendatastorage.dfs.core.windows.net'
    -- For ADLS Gen2, use .dfs.core.windows.net (not .blob.)
);
GO

CREATE EXTERNAL TABLE dbo.ExternalYellowTaxi (
    vendorID              VARCHAR(10),
    tpepPickupDateTime    DATETIME2(7),
    tpepDropoffDateTime   DATETIME2(7),
    passengerCount        INT,
    tripDistance          FLOAT,
    fareAmount            FLOAT,
    totalAmount           FLOAT,
    puYear                INT,
    puMonth               INT
)
WITH (
    LOCATION = 'yellow/puYear=2018/puMonth=6/',
    DATA_SOURCE = NYC_Taxi_ADLS,
    FILE_FORMAT = NycTaxiParquet
);
GO
============================================================ */

-- -----------------------------------------------------------------------
-- EXAMPLE 3C: ANALYSIS — AD-HOC QUERY (RUNS ON SYNAPSE SERVERLESS)
-- -----------------------------------------------------------------------
-- Distribution of trips by hour of the day (June/2018)
SELECT
    DATEPART(HOUR, tpepPickupDateTime) AS HoraDoDia,
    COUNT(*)                           AS TotalCorridas,
    AVG(fareAmount)                    AS TarifaMedia,
    AVG(CAST(passengerCount AS FLOAT)) AS MediaPassageiros
FROM OPENROWSET(
    BULK 'abs://nyctlc@azureopendatastorage.blob.core.windows.net/yellow/puYear=2018/puMonth=6/*.parquet',
    FORMAT = 'PARQUET'
) AS TaxiYellow
GROUP BY DATEPART(HOUR, tpepPickupDateTime)
ORDER BY HoraDoDia;
GO

-- =================================================================================
-- GENERAL CLEANUP / TEARDOWN SCRIPT (OPTIONAL)
-- Execute this block to remove ALL objects created in this lab.
-- =================================================================================
/*
USE AdventureWorks2025;
GO

-- 1. Disable System Versioning before dropping temporal and ledger tables
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'SalariesLedger' AND schema_id = SCHEMA_ID('lab'))
    ALTER TABLE lab.SalariesLedger SET (SYSTEM_VERSIONING = OFF);

IF EXISTS (SELECT * FROM sys.tables WHERE name = 'EmployeesTemporal' AND schema_id = SCHEMA_ID('lab'))
    ALTER TABLE lab.EmployeesTemporal SET (SYSTEM_VERSIONING = OFF);

-- 2. Drop Lab 2 Tables
DROP TABLE IF EXISTS lab.FinancialTransactionsLedger;
DROP TABLE IF EXISTS lab.SalariesLedger;
DROP TABLE IF EXISTS lab.EmployeesTemporal;
DROP TABLE IF EXISTS lab.EmployeesTemporalHistory;

-- 3. Drop Graph Tables (Edges first, then Nodes)
DROP TABLE IF EXISTS lab.OwnsCard;
DROP TABLE IF EXISTS lab.UsedIP;
DROP TABLE IF EXISTS lab.Knows;
DROP TABLE IF EXISTS lab.CreditCard;
DROP TABLE IF EXISTS lab.IPAddress;
DROP TABLE IF EXISTS lab.Person;

-- 4. Drop In-Memory Tables and Types
DROP TABLE IF EXISTS lab.SessionCacheMemData;
DROP TABLE IF EXISTS lab.SessionCacheMemOnly;
DROP TYPE IF EXISTS lab.MyMemoryTableType;

-- 5. Drop Stored Procedures and External Table Objects
DROP PROCEDURE IF EXISTS lab.sp_generate_mermaid_graph;
DROP EXTERNAL TABLE IF EXISTS lab.ExternalSalesOrders;
DROP EXTERNAL TABLE IF EXISTS lab.ExternalYellowTaxi2013;
DROP EXTERNAL TABLE IF EXISTS lab.ExternalGreenTaxi2013;
DROP EXTERNAL TABLE IF EXISTS lab.ExternalYellowTaxi;

IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'AzureBlobStorageSales') DROP EXTERNAL DATA SOURCE AzureBlobStorageSales;
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'NYC_Taxi_Yellow') DROP EXTERNAL DATA SOURCE NYC_Taxi_Yellow;
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'NYC_Taxi_Green') DROP EXTERNAL DATA SOURCE NYC_Taxi_Green;

IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'ParquetFileFormat') DROP EXTERNAL FILE FORMAT ParquetFileFormat;
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'NycTaxiParquet') DROP EXTERNAL FILE FORMAT NycTaxiParquet;
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'CSVFileFormat') DROP EXTERNAL FILE FORMAT CSVFileFormat;

IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'MyStorageCredential') DROP DATABASE SCOPED CREDENTIAL [MyStorageCredential];

-- 6. BULK INSERT Temporary Table
IF OBJECT_ID('tempdb..#SalesImport') IS NOT NULL DROP TABLE #SalesImport;
GO
*/

-- =================================================================================================
-- OFFICIAL MICROSOFT LEARN REFERENCES
-- =================================================================================================
-- Memory-optimized tables and durability:
-- https://learn.microsoft.com/en-us/sql/relational-databases/in-memory-oltp/introduction-to-memory-optimized-tables?view=sql-server-ver17
-- System-versioned temporal tables:
-- https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables?view=sql-server-ver17
-- Ledger tables:
-- https://learn.microsoft.com/en-us/sql/relational-databases/security/ledger/ledger-landing-sql-server?view=sql-server-ver17
-- SQL Graph:
-- https://learn.microsoft.com/en-us/sql/relational-databases/graphs/sql-graph-overview?view=sql-server-ver17
-- External tables and PolyBase:
-- https://learn.microsoft.com/en-us/sql/t-sql/statements/create-external-table-transact-sql?view=sql-server-ver17




