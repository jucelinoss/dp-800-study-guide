-- =================================================================================
-- DP-800 - HANDS-ON LAB: TABLES, DATA TYPES, AND INDEXES
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and the other lab scripts, restore the AdventureWorks
-- (OLTP) database backup available at:
-- https://learn.microsoft.com/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script is designed for you to run section by section in SSMS or Azure Data
-- Studio. It demonstrates each concept covered in the DP-800 exam for lesson 01.
-- 
-- EXECUTION TIP (DDL TRIGGERS IN ADVENTUREWORKS):
--   When running DDL commands (such as CREATE/ALTER/DROP TABLE or INDEX), you will notice
--   IO statistics reading from the 'DatabaseLog' table and messages like 'CREATE_INDEX...'.
--   This happens because AdventureWorks has a database-level audit trigger
--   (ddlDatabaseTriggerLog) that logs these changes. If you want to silence it, run:
--   -> DISABLE TRIGGER ddlDatabaseTriggerLog ON DATABASE;
--   And to re-enable it after testing:
--   -> ENABLE TRIGGER ddlDatabaseTriggerLog ON DATABASE;
-- =================================================================================
USE AdventureWorks2025;


GO
-- Create a separate schema to keep your labs organized without altering
-- the original AdventureWorks tables.
IF NOT EXISTS (SELECT *
FROM sys.schemas
WHERE  name = 'lab')
    BEGIN
    EXECUTE ('CREATE SCHEMA lab');
END


-- =================================================================================
-- DP-800 - HANDS-ON LAB: TABLES, DATA TYPES, AND INDEXES
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and the other lab scripts, restore the AdventureWorks
-- (OLTP) database backup available at:
-- https://learn.microsoft.com/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script is designed for you to run section by section in SSMS or Azure Data
-- Studio. It demonstrates each concept covered in the DP-800 exam for lesson 01.
-- 
-- EXECUTION TIP (DDL TRIGGERS IN ADVENTUREWORKS):
--   When running DDL commands (such as CREATE/ALTER/DROP TABLE or INDEX), you will notice
--   IO statistics reading from the 'DatabaseLog' table and messages like 'CREATE_INDEX...'.
--   This happens because AdventureWorks has a database-level audit trigger
--   (ddlDatabaseTriggerLog) that logs these changes. If you want to silence it, run:
--   -> DISABLE TRIGGER ddlDatabaseTriggerLog ON DATABASE;
--   And to re-enable it after testing:
--   -> ENABLE TRIGGER ddlDatabaseTriggerLog ON DATABASE;
-- =================================================================================
USE AdventureWorks2025;


GO
-- Create a separate schema to keep your labs organized without altering
-- the original AdventureWorks tables.
IF NOT EXISTS (SELECT *
FROM sys.schemas
WHERE  name = 'lab')
    BEGIN
    EXECUTE ('CREATE SCHEMA lab');
END


GO
-- Preventive cleanup in case you run the script more than once
DROP PROCEDURE IF EXISTS lab.CheckColumnSparsity;
DROP TABLE IF EXISTS lab.ProductAttributesSparse;

DROP TABLE IF EXISTS lab.OrderDesignDemo;

DROP TABLE IF EXISTS lab.SalesOrderDetail_None;

DROP TABLE IF EXISTS lab.SalesOrderDetail_Row;

DROP TABLE IF EXISTS lab.SalesOrderDetail_Page;


GO
-- =================================================================================
-- PART 0: TABLE DESIGN — DATA TYPES, DATETIME2, AND FILL FACTOR
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - Choose the smallest type that meets the business rule. For monetary values, use
--     DECIMAL/NUMERIC, not FLOAT/REAL, as they are approximate.
--   - DATETIME2 is the usual choice for new projects: it offers a wider range and greater
--     precision than DATETIME. DATETIMEOFFSET is appropriate when the time zone is part of the data.
--   - FILL FACTOR reserves space in leaf pages during index creation/rebuild.
--     Reducing it can decrease page splits on keys that receive mid-range inserts, but
--     increases the number of pages and read costs. It is not a default configuration.
CREATE TABLE lab.OrderDesignDemo
(
    OrderId       INT IDENTITY(1,1) NOT NULL,
    CustomerId    INT NOT NULL,
    OrderDateUtc  DATETIME2(0) NOT NULL CONSTRAINT DF_OrderDesignDemo_OrderDateUtc DEFAULT SYSUTCDATETIME(),
    TotalAmount   DECIMAL(18,2) NOT NULL,
    CustomerNote  NVARCHAR(500) NULL,
    ExternalCode  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_OrderDesignDemo_ExternalCode DEFAULT NEWSEQUENTIALID(),
    CONSTRAINT PK_OrderDesignDemo PRIMARY KEY CLUSTERED (OrderId)
);
GO

INSERT INTO lab.OrderDesignDemo (CustomerId, TotalAmount, CustomerNote)
VALUES (1, 129.90, N'Pedido de demonstração');
GO

-- [DP-800 EXAM TIP] The key is CustomerId; OrderDateUtc goes in INCLUDE because
-- it is returned by the query but does not participate in ordering or the predicate.
CREATE NONCLUSTERED INDEX IX_OrderDesignDemo_CustomerId
    ON lab.OrderDesignDemo (CustomerId)
    INCLUDE (OrderDateUtc, TotalAmount)
    WITH (FILLFACTOR = 90);
GO

-- View properties, fill factor, and statistics of the created index.
SELECT i.name, i.type_desc, i.fill_factor, s.name AS StatisticsName, s.auto_created
FROM sys.indexes AS i
LEFT JOIN sys.stats AS s
    ON s.object_id = i.object_id
   AND s.stats_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'lab.OrderDesignDemo');
GO

-- =================================================================================
-- PART 0.1: IMPLICIT DATA TYPE CONVERSION AND PERFORMANCE IMPACT
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - TYPE PRECEDENCE: When comparing distinct types, SQL Server implicitly converts
--     the lower-precedence type to the higher-precedence type.
--   - NVARCHAR (precedence 25) has HIGHER precedence than VARCHAR (precedence 27).
--   - NON-SARGABLE QUERY: If the column is VARCHAR and the variable is NVARCHAR, the column is
--     implicitly converted (CONVERT_IMPLICIT). The index loses the SEEK and becomes an INDEX SCAN.
DROP TABLE IF EXISTS lab.ImplicitConversionDemo;
GO

CREATE TABLE lab.ImplicitConversionDemo (
    AccountCode VARCHAR(20) NOT NULL,
    AccountName NVARCHAR(100) NOT NULL,
    CreatedDate DATETIME2(0) NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT PK_ImplicitConversionDemo PRIMARY KEY CLUSTERED (AccountCode)
);
GO

-- Populate test data
INSERT INTO lab.ImplicitConversionDemo (AccountCode, AccountName)
VALUES ('ACC-1001', N'Conta Operacional'),
       ('ACC-1002', N'Conta Investimento'),
       ('ACC-1003', N'Conta Reserva');
GO

-- [DP-800 EXAM TIP] HARMFUL IMPLICIT CONVERSION (Non-Sargable)
-- NVARCHAR variable compared with VARCHAR column (causes Index Scan on the real table)
DECLARE @SearchCodeNVARCHAR NVARCHAR(20) = N'ACC-1001';

SELECT AccountCode, AccountName 
FROM lab.ImplicitConversionDemo
WHERE AccountCode = @SearchCodeNVARCHAR; 
-- In the execution plan, the filter becomes CONVERT_IMPLICIT(nvarchar(20), AccountCode) = @SearchCodeNVARCHAR
GO

-- SARGABLE FIX: Ensure the search uses the same type family (VARCHAR)
DECLARE @SearchCodeVARCHAR VARCHAR(20) = 'ACC-1001';

SELECT AccountCode, AccountName 
FROM lab.ImplicitConversionDemo
WHERE AccountCode = @SearchCodeVARCHAR; -- Performs a direct Seek on the index key.
GO

-- ATTEMPTING INCORRECT STRING TO INT CONVERSION WITH EXPECTED ERROR
BEGIN TRY
    -- String with letters converted to INT fails at runtime
    SELECT CAST('ACC-1001' AS INT);
END TRY
BEGIN CATCH
    PRINT 'Erro Esperado de Conversão Implícita/Explícita: ' + ERROR_MESSAGE();
END CATCH;
GO

-- =================================================================================
-- PART 1: HEAP VS CLUSTERED & RID LOOKUP / KEY LOOKUP OPERATORS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - HEAP: A table without a clustered index. Data is stored in an
--     unordered fashion in data pages linked by IAM (Index Allocation Map) pages.
--     The engine locates records using a physical RID (FileID:PageID:SlotID).
--   - CLUSTERED TABLE: A table with a clustered index. The physical data in the leaf level
--     of the B-Tree is organized and ordered according to the index key.
--   - RID LOOKUP: An operator that occurs when we search using a non-clustered index on a
--     Heap, and SQL needs to go to the physical data page to fetch non-indexed columns using the RID.
--   - KEY LOOKUP: Occurs in clustered tables when the non-clustered index locates the
--     clustered index key, and SQL needs to traverse the main B-Tree to fetch the remaining columns.
-- 1. Create a Heap table populated with SalesOrderDetail data
SELECT *
INTO   lab.SalesOrderDetailHeap
FROM Sales.SalesOrderDetail;


GO
-- 2. Enable the Actual Execution Plan display (Ctrl + M in SSMS)
-- And enable I/O and Time statistics to compare read effort:
-- IMPORTANT NOTE (ACTUAL VS ESTIMATED PLAN): Always use the "Actual Execution Plan" (Ctrl + M)
-- when running these labs. The "Estimated Execution Plan" (Ctrl + L) does NOT execute the code lines.
-- Therefore, local variables and directives like 'OPTION (RECOMPILE)' (as in Part 3)
-- will not have their actual values evaluated during estimation, generating incorrect
-- generic plans (which hide the use of the filtered index, for example).
SET STATISTICS IO ON;

SET STATISTICS TIME ON;


GO
-- Test 1: Point lookup on the Heap
-- EXECUTION PLAN: Should show a "Table Scan" since there is no physical order.
SELECT SalesOrderID,
    SalesOrderDetailID,
    CarrierTrackingNumber
FROM lab.SalesOrderDetailHeap
WHERE  SalesOrderDetailID = 50000;


GO
-- Test 2: Creating a Non-Clustered index on the Heap
CREATE NONCLUSTERED INDEX NIX_SalesOrderDetailHeap_SalesOrderDetailID
    ON lab.SalesOrderDetailHeap(SalesOrderDetailID);


GO
-- Now run the query again.
-- EXECUTION PLAN: You will see an "Index Seek" on the newly created non-clustered index,
-- followed by an "RID Lookup" (search for the physical row identifier in the Heap)
-- to fetch the 'CarrierTrackingNumber' column, which is not in the index.
SELECT SalesOrderID,
    SalesOrderDetailID,
    CarrierTrackingNumber
FROM lab.SalesOrderDetailHeap
WHERE  SalesOrderDetailID = 50000;


GO
-- Test 3: Convert the Heap into a Clustered Table
-- Create the primary key, which by default generates a Clustered Index (CIX).
-- EXAM NOTE (IO Statistics): When running this ALTER TABLE, you will see 2 separate logical reads:
--   1st Read: Scan on the original Heap to extract data, sort, and build the Clustered Index B-Tree.
--   2nd Read: Since we created NIX_SalesOrderDetailHeap_SalesOrderDetailID earlier, SQL Server
--              needs to rebuild this non-clustered index to update its physical pointers.
--              They change from RIDs (Heap Row IDs) to point to the new Clustered Key.
ALTER TABLE lab.SalesOrderDetailHeap
    ADD CONSTRAINT PK_SalesOrderDetailHeap PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID);


GO
-- If you run the query now, the RID Lookup disappears and becomes a "Key Lookup"
-- (because the logical pointer now points to the Clustered key instead of a disk RID).
SELECT SalesOrderID,
    SalesOrderDetailID,
    CarrierTrackingNumber
FROM lab.SalesOrderDetailHeap
WHERE  SalesOrderDetailID = 50000;


GO
SET STATISTICS IO OFF;

SET STATISTICS TIME OFF;


GO
-- =================================================================================
-- PART 2: INCLUDED COLUMNS AND COVERING INDEX
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - NON-KEY COLUMNS (INCLUDE): Columns stored only at the leaf level (last level)
--     of the non-clustered index. They do not affect the B-tree index ordering and cannot
--     be used in filters (WHERE clause) in an indexed manner.
--   - COVERING INDEX: A non-clustered index designed to
--     contain all columns referenced in the query (in SELECT, WHERE, JOIN, or GROUP BY).
--     Since all columns are contained in the index, the engine does not need to navigate to the base table
--     (Heap or Clustered Table), completely eliminating Lookup operators (RID/Key) and reducing I/O.

-- 1. Create a Rowstore table with a clustered index for testing
SELECT *
INTO   lab.SalesOrderDetailRowstore
FROM Sales.SalesOrderDetail;

ALTER TABLE lab.SalesOrderDetailRowstore
    ADD CONSTRAINT PK_SalesOrderDetailRowstore PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID);


GO
-- 2. Create a regular Non-Clustered index on the ProductID column
CREATE NONCLUSTERED INDEX NIX_SalesOrderDetailRowstore_ProductID
    ON lab.SalesOrderDetailRowstore(ProductID);


GO
SET STATISTICS IO ON;


GO
-- Test 1: Query generating Key Lookup
-- Since we select UnitPrice and OrderQty, SQL Server needs to navigate the B-Tree
-- of the non-clustered index on ProductID and then go to the base table via Key Lookup.
SELECT ProductID,
    UnitPrice,
    OrderQty
FROM lab.SalesOrderDetailRowstore
WHERE  ProductID = 776;


GO
-- Test 2: Replace the simple index with a Covering Index.
-- DROP_EXISTING can only rebuild an index with the same name. Since the
-- covering index has a different name, we explicitly drop the simple index before creating it.
DROP INDEX NIX_SalesOrderDetailRowstore_ProductID
    ON lab.SalesOrderDetailRowstore;

CREATE NONCLUSTERED INDEX NIX_SalesOrderDetailRowstore_ProductID_Covering
    ON lab.SalesOrderDetailRowstore(ProductID)
    INCLUDE(UnitPrice, OrderQty);


GO
-- Run again.
-- EXECUTION PLAN: The Key Lookup is gone! Now we have just a pure "Index Seek".
-- The I/O cost (pages read) drops significantly.
SELECT ProductID,
    UnitPrice,
    OrderQty
FROM lab.SalesOrderDetailRowstore
WHERE  ProductID = 776;


GO
SET STATISTICS IO OFF;


GO
-- =================================================================================
-- PART 3: FILTERED INDEXES AND THEIR LIMITATIONS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - FILTERED INDEX: A non-clustered index with an associated physical WHERE clause
--     (e.g., WHERE UnitPrice > 1000). It indexes only the data portion that satisfies the criteria.
--     Drastically reduces the index size on disk and maintenance times.
--   - PARAMETERIZED QUERIES: To use a filtered index, the optimizer must prove that the
--     query predicate implies the index filter. This result depends on compilation, values,
--     statistics, and estimated cost; it is not correct to assume that every variable always prevents it.
--   - OPTION (RECOMPILE): A directive that forces query recompilation on each execution, allowing the
--     optimizer to substitute the parameter with the literal runtime value and safely use the filtered index.
-- 1. Create a filtered index for expensive products (UnitPrice > 1000)
CREATE NONCLUSTERED INDEX NIX_SalesOrderDetailRowstore_Filtered_Expensive
    ON lab.SalesOrderDetailRowstore(ProductID)
    INCLUDE(UnitPrice) WHERE UnitPrice > 1000;


GO
SET STATISTICS IO ON;


GO
-- Test 1: Query using a direct literal value in the WHERE clause.
-- Examine the plan: the filtered index is a candidate because UnitPrice > 1050 implies UnitPrice > 1000.
-- The final choice is still cost-based and may vary depending on data and statistics.
SELECT ProductID,
    UnitPrice
FROM lab.SalesOrderDetailRowstore
WHERE  ProductID = 776
    AND UnitPrice > 1050;


GO
-- Test 2: Query using SQL parameters/variables.
-- Compare the plan with the previous one. Without recompilation, the filtered index may not be eligible
-- when the optimizer cannot prove the filter implication during compilation.
DECLARE @PriceThreshold AS DECIMAL (18, 2) = 1050.00;

SELECT ProductID,
    UnitPrice
FROM lab.SalesOrderDetailRowstore
WHERE  ProductID = 776
    AND UnitPrice > @PriceThreshold;


GO
-- Test 3: Workaround using OPTION (RECOMPILE)
-- This forces query recompilation by evaluating the value at runtime.
DECLARE @PriceThresholdRec AS DECIMAL (18, 2) = 1050.00;

SELECT ProductID,
    UnitPrice
FROM lab.SalesOrderDetailRowstore
WHERE  ProductID = 776
    AND UnitPrice > @PriceThresholdRec
OPTION
(RECOMPILE);


GO
SET STATISTICS IO OFF;


GO
-- =================================================================================
-- PART 4: DATA COMPRESSION (ROW AND PAGE COMPRESSION)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - ROW COMPRESSION: Reduces storage by changing the physical format of data types.
--     Fixed-size numeric values (e.g., INT, BIGINT, DECIMAL) and character types (CHAR)
--     occupy only the actual data space (e.g., an INT with value 2 uses 1 byte instead of 4).
--     Has minimal CPU impact, being highly recommended for OLTP workloads.
--   - PAGE COMPRESSION: Applies ROW compression and then performs two additional steps per 8 KB page:
--     1. Prefix Compression: Replaces repetitive patterns at the beginning of column values within a page with short tokens.
--     2. Dictionary Compression: Identifies all repeated values across the entire page and creates a local dictionary.
--     Requires higher CPU consumption to decompress in memory, but generates the greatest possible I/O and space reduction.
-- 1. Estimate space savings for ROW and PAGE compression types
-- SQL Server gives us a preview without needing to alter the actual table.
EXECUTE sp_estimate_data_compression_savings @schema_name = 'lab', @object_name = 'SalesOrderDetailRowstore', @index_id = 1, -- Clustered Index
@partition_number = NULL, @data_compression = 'ROW';

EXECUTE sp_estimate_data_compression_savings @schema_name = 'lab', @object_name = 'SalesOrderDetailRowstore', @index_id = 1, @partition_number = NULL, @data_compression = 'PAGE';


GO
-- 2. REAL LAB: Compare disk space usage (None vs ROW vs PAGE)
-- Create 3 identical tables
SELECT *
INTO   lab.SalesOrderDetail_None
FROM Sales.SalesOrderDetail;

SELECT *
INTO   lab.SalesOrderDetail_Row
FROM Sales.SalesOrderDetail;

SELECT *
INTO   lab.SalesOrderDetail_Page
FROM Sales.SalesOrderDetail;


GO
-- Add Clustered Index to all of them to organize the data pages
ALTER TABLE lab.SalesOrderDetail_None
    ADD CONSTRAINT PK_SalesOrderDetail_None PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID);

ALTER TABLE lab.SalesOrderDetail_Row
    ADD CONSTRAINT PK_SalesOrderDetail_Row PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID);

ALTER TABLE lab.SalesOrderDetail_Page
    ADD CONSTRAINT PK_SalesOrderDetail_Page PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID);


GO
-- Apply the corresponding compressions
ALTER TABLE lab.SalesOrderDetail_None REBUILD WITH (DATA_COMPRESSION = NONE);

ALTER TABLE lab.SalesOrderDetail_Row REBUILD WITH (DATA_COMPRESSION = ROW);

ALTER TABLE lab.SalesOrderDetail_Page REBUILD WITH (DATA_COMPRESSION = PAGE);


GO
-- 3. Checking the size in pages and KB of each table
-- DMV sys.dm_db_index_physical_stats tells us how many physical 8KB pages the table occupies.
SELECT OBJECT_NAME(object_id) AS Tabela,
    index_type_desc AS TipoIndice,
    page_count AS QtdPaginas_8KB,
    (page_count * 8) AS Tamanho_Total_KB,
    CAST (avg_page_space_used_in_percent AS DECIMAL (5, 2)) AS Percentual_Uso_Pagina
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED')
WHERE  object_id IN (OBJECT_ID('lab.SalesOrderDetail_None'), OBJECT_ID('lab.SalesOrderDetail_Row'), OBJECT_ID('lab.SalesOrderDetail_Page'))
    AND index_id = 1; -- Clustered Index (onde residem os dados da tabela)


GO
-- 4. Measuring the impact on logical reads (I/O) in the actual plan
-- EXPLANATORY NOTE (WHY COMPRESSION GENERATED FEWER LOGICAL READS?):
--   In SQL Server, the basic storage unit in memory/disk is the 8 KB page.
--   A "logical read" is the reading of a single 8 KB page from RAM.
--   When we compress data (ROW or PAGE):
--     1. The physical size of each data row is reduced (consumes fewer bytes).
--     2. More rows can be packed within the same 8 KB page.
--     3. Consequently, the TOTAL number of pages needed to store the table decreases.
--     4. When doing a full SCAN to read the entire table, the engine needs to read fewer
--        total 8 KB pages from RAM, resulting in fewer logical reads and lower I/O effort.
SET STATISTICS IO ON;


GO
-- Test A: Scan on the table WITHOUT Compression (More pages read)
SELECT 'NONE' AS Compressao,
    SUM(LineTotal) AS TotalVendas
FROM lab.SalesOrderDetail_None;


GO
-- Test B: Scan on the table with ROW Compression (Intermediate pages)
SELECT 'ROW' AS Compressao,
    SUM(LineTotal) AS TotalVendas
FROM lab.SalesOrderDetail_Row;


GO
-- Test C: Scan on the table with PAGE Compression (Minimum pages read, less I/O!)
SELECT 'PAGE' AS Compressao,
    SUM(LineTotal) AS TotalVendas
FROM lab.SalesOrderDetail_Page;


GO
SET STATISTICS IO OFF;


GO
-- 5. Apply compression only to the covering non-clustered index of the main lab table
ALTER INDEX NIX_SalesOrderDetailRowstore_ProductID_Covering
    ON lab.SalesOrderDetailRowstore REBUILD WITH(DATA_COMPRESSION = ROW);


GO
-- =================================================================================
-- PART 5: COLUMNSTORE INDEXES (CCI VS NCCI)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CLUSTERED COLUMNSTORE INDEX (CCI): Highly compressed columnar physical storage optimized
--     for analytical and aggregation queries. Replaces rowstore storage as the main
--     structure and is recommended for fact tables and large DW dimension tables.
--   - Since SQL Server 2016, a CCI can have secondary non-clustered rowstore indexes. This allows
--     selective seeks and also applying a UNIQUE/PRIMARY KEY constraint through an appropriate rowstore
--     index; evaluate the extra maintenance cost before adopting them.
--   - NON-CLUSTERED COLUMNSTORE INDEX (NCCI): A columnar index created on top of a Rowstore (B-tree) table.
--     Allows the table to continue running fast OLTP write transactions on the main B-Tree, while
--     parallel analytical queries use the columnar structure (HTAP hybrid scenarios).
--   - BATCH MODE: A processing mode where the query engine processes vectors (batches) of approximately
--     900 rows together in the CPU memory cache at once, instead of evaluating record by record (Row Mode).
--     Drastically accelerates aggregations and groupings.
-- 1. Create an analytical table for Clustered Columnstore Index (CCI) testing
SELECT *
INTO   lab.SalesOrderDetailCCI
FROM Sales.SalesOrderDetail;
GO

-- 2. Apply Clustered Columnstore (replaces rowstore storage)
CREATE CLUSTERED COLUMNSTORE INDEX CCI_SalesOrderDetailCCI
    ON lab.SalesOrderDetailCCI;
GO

-- A secondary rowstore index on a CCI is supported. It serves selective seeks;
-- do not confuse it with a second clustered index.
CREATE NONCLUSTERED INDEX NIX_SalesOrderDetailCCI_SalesOrderDetailID
    ON lab.SalesOrderDetailCCI (SalesOrderID, SalesOrderDetailID);
GO

-- 3. Analytical Performance Comparison (Rowstore vs Columnstore)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- Rowstore Query (Classic B-Tree Scan)
SELECT ProductID,
    SUM(LineTotal) AS TotalVendas,
    AVG(UnitPrice) AS MediaPreco
FROM lab.SalesOrderDetailRowstore
GROUP BY ProductID;
GO

-- Columnstore Query (Columnar Scan + BATCH MODE)
-- EXECUTION PLAN: How to check the "Execution Mode" property:
-- It should show "Batch" instead of "Row", processing sets of 900 rows at a time.
--   1. Run the query with "Actual Execution Plan" enabled (Ctrl + M).
--   2. Access the "Execution plan" tab in the lower results panel.
--   3. Hover the mouse (or click and press F4 to open properties on the right)
--      over the first query icon: "Clustered Index Scan (Columnstore)".
--   4. Check the field: "Actual Execution Mode" (or "Estimated Execution Mode").
--      Should show "Batch" (while the Rowstore query above shows "Row").
SELECT ProductID,
    SUM(LineTotal) AS TotalVendas,
    AVG(UnitPrice) AS MediaPreco
FROM lab.SalesOrderDetailCCI
GROUP BY ProductID;
GO

-- 4. NCCI (Non-Clustered Columnstore Index)
-- Adds a columnar index for analytical queries without altering the physical rowstore table.
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_SalesOrderDetailRowstore
    ON lab.SalesOrderDetailRowstore(ProductID, LineTotal, UnitPrice);
GO

-- Now the original Rowstore table can also use batch mode for analytical queries!
SELECT ProductID,
    SUM(LineTotal) AS TotalVendas,
    AVG(UnitPrice) AS MediaPreco
FROM lab.SalesOrderDetailRowstore
GROUP BY ProductID;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
-- =================================================================================
-- PART 6: SPARSE COLUMNS (OPTIMIZED STORAGE FOR NULLS)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - SPARSE COLUMNS: Ordinary columns with optimized storage for NULL values.
--     If the value is NULL, the column occupies exactly zero bytes in the row. If the value is filled,
--     it consumes 2 to 4 bytes more than its original physical size. Ideal for columns with 90%+ NULLs.
--   - COLUMN SET: A dynamic XML field (untyped representation) that exposes all SPARSE columns
--     of a table in a grouped manner. It allows inserting, reading, and updating sparse columns by sending XML.
--     Useful for overcoming SQL Server's maximum limit of 1,024 columns per table (allowing up to 30,000 columns).
-- 1. Create a table using SPARSE columns and COLUMN SET (dynamic XML for N sparse columns)
CREATE TABLE lab.ProductAttributesSparse
(
    ProductID INT IDENTITY (1, 1) PRIMARY KEY,
    ProductName NVARCHAR (100) NOT NULL,
    -- Sparse columns that consume zero bytes if NULL
    SpecialColor NVARCHAR (50) SPARSE NULL,
    CustomWeight DECIMAL (5, 2) SPARSE NULL,
    CustomNotes NVARCHAR (MAX) SPARSE NULL,
    -- Column Set exposes all Sparse columns of the table in a dynamic XML column
    AllSparseAttributes XML COLUMN_SET FOR ALL_SPARSE_COLUMNS
);


GO
-- 2. Inserting data
-- Note that we can insert into SPARSE columns normally
INSERT  INTO lab.ProductAttributesSparse
    (ProductName, SpecialColor, CustomWeight)
VALUES
    ('Mountain Bike Pro', 'Matte Black', 12.50);
-- And we can also insert rows with many NULLs (which will save space)

INSERT  INTO lab.ProductAttributesSparse
    (ProductName)
VALUES
    ('Road Bike Basic');
-- 3. Selecting data -- SELECT * brings the XML AllSparseAttributes column instead of the individual SPARSE columns

SELECT *
FROM lab.ProductAttributesSparse;
-- But you can still fetch columns explicitly:

SELECT ProductName,
    SpecialColor,
    CustomWeight
FROM lab.ProductAttributesSparse;
GO

-- 4. How to check the sparsity percentage (NULLs) of any column via Stored Procedure
-- EXAM NOTE (UDF LIMITATION): It is not possible to create a User-Defined Function (UDF)
-- to execute Dynamic SQL in SQL Server (since functions have prohibited side effects).
-- Therefore, we encapsulate this dynamic analysis logic in a STORED PROCEDURE.
GO

CREATE OR ALTER PROCEDURE lab.CheckColumnSparsity
    @TableName NVARCHAR(256),
    @ColumnName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Validate if the specified table and column exist in the database (avoids errors and SQL Injection)
    IF OBJECT_ID(@TableName) IS NULL
    BEGIN
        RAISERROR('Erro: A tabela informada não existe ou o schema não foi especificado.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(@TableName) AND name = @ColumnName
    )
    BEGIN
        RAISERROR('Erro: A coluna informada não existe na tabela.', 16, 1);
        RETURN;
    END;

    -- 2. Safely build and execute dynamic SQL using QUOTENAME
    DECLARE @DynamicSQL NVARCHAR(MAX);
    SET @DynamicSQL = N'
    SELECT 
        @Table AS Tabela,
        @Col AS Coluna,
        COUNT(*) AS TotalLinhas,
        SUM(CASE WHEN ' + QUOTENAME(@ColumnName) + ' IS NULL THEN 1 ELSE 0 END) AS TotalNulos,
        CAST(
            (SUM(CASE WHEN ' + QUOTENAME(@ColumnName) + ' IS NULL THEN 1.0 ELSE 0.0 END) / NULLIF(COUNT(*), 0)) * 100 
            AS DECIMAL(5,2)
        ) AS Percentual_Esparsidade_NULL
    FROM ' + QUOTENAME(OBJECT_SCHEMA_NAME(OBJECT_ID(@TableName)))
         + N'.' + QUOTENAME(OBJECT_NAME(OBJECT_ID(@TableName))) + N';';

    EXEC sp_executesql @DynamicSQL, 
                       N'@Table NVARCHAR(256), @Col NVARCHAR(128)', 
                       @Table = @TableName, 
                       @Col = @ColumnName;
END;
GO

-- Example Execution 1: Testing with our SPARSE column
EXEC lab.CheckColumnSparsity 
    @TableName = 'lab.ProductAttributesSparse', 
    @ColumnName = 'SpecialColor';
GO

-- Example Execution 2: Testing with an original AdventureWorks table
EXEC lab.CheckColumnSparsity 
    @TableName = 'Sales.SalesOrderHeader', 
    @ColumnName = 'Comment';
GO


-- =================================================================================
-- MAINTENANCE AND CLEANUP (OPTIONAL)
-- =================================================================================
-- Run when you finish the lab to avoid consuming unnecessary space in your database.
/*
DROP PROCEDURE IF EXISTS lab.CheckColumnSparsity;
DROP TABLE IF EXISTS lab.ProductAttributesSparse;
DROP TABLE IF EXISTS lab.OrderDesignDemo;
DROP TABLE IF EXISTS lab.SalesOrderDetailCCI;
DROP TABLE IF EXISTS lab.SalesOrderDetailRowstore;
DROP TABLE IF EXISTS lab.SalesOrderDetailHeap;
DROP TABLE IF EXISTS lab.SalesOrderDetail_None;
DROP TABLE IF EXISTS lab.SalesOrderDetail_Row;
DROP TABLE IF EXISTS lab.SalesOrderDetail_Page;
-- DROP SCHEMA IF EXISTS lab;
*/
