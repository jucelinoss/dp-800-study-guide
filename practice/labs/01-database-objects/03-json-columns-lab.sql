-- =================================================================================
-- DP-800 - HANDS-ON LAB: JSON COLUMNS AND INDEXES
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates hands-on manipulation, querying, and indexing of data
-- in JSON format within SQL Server, covering:
--   1. Classic Storage with ISJSON validation
--   2. Read Functions: JSON_VALUE vs JSON_QUERY
--   3. Search Modes: LAX vs STRICT (Error 13608)
--   4. OPENJSON with and without the WITH clause (with CROSS APPLY)
--   5. Modern Aggregators: JSON_ARRAYAGG and JSON_OBJECTAGG (Azure SQL / SQL Server 2025)
--   6. Optimization and Indexing with Computed Columns
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup in case the script is run more than once
DROP TABLE IF EXISTS lab.OrdersJSON;
GO


-- =================================================================================
-- PART 1: STORAGE AND VALIDATION (ISJSON)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - JSON STORAGE: Traditionally, SQL Server stores JSON as text strings (`NVARCHAR(MAX)`).
--     The native `json` type is GA in Azure SQL Database and Azure SQL Managed Instance; in SQL Server 2025,
--     it remains in preview. This lab uses NVARCHAR(MAX) to work on traditional SQL Server.
--   - ISJSON(): Validation function. Returns 1 if the text is valid JSON.
--     In SQL Server 2022+, you can specify type validation parameters, such as:
--     `ISJSON(column, SCALAR)`, `ISJSON(column, ARRAY)` or `ISJSON(column, OBJECT)`.
--   - CHECK CONSTRAINT WITH ISJSON: Essential table constraint to prevent corrupted strings
--     or malformed data in columns intended to store JSON as text.

CREATE TABLE lab.OrdersJSON
(
    OrderID INT IDENTITY PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    OrderDetails NVARCHAR(MAX) NULL,
    -- JSON column
    -- CHECK constraint for structural integrity
    CONSTRAINT CK_OrdersJSON_OrderDetails CHECK (ISJSON(OrderDetails) = 1)
);
GO

-- Inserting a valid JSON record
INSERT INTO lab.OrdersJSON
    (CustomerName, OrderDetails)
VALUES
    ('Alice Smith', N'{
    "region": "South",
    "delivery": { "carrier": "DHL", "days": 3 },
    "items": [
        { "product": "Smartphone", "qty": 1, "price": 899.00 },
        { "product": "Charger", "qty": 2, "price": 25.00 }
    ]
}');
GO

-- Test: Attempt to insert malformed JSON (Should fail the CHECK)
BEGIN TRY
    INSERT INTO lab.OrdersJSON
    (CustomerName, OrderDetails)
VALUES
    ('Bob Jones', N'{"region": "North", "delivery": {"carrier": "FedEx", "days": 5 }'); -- Missing closing of the main object
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO: ' + ERROR_MESSAGE();
    -- Will return: "The INSERT statement conflicted with the CHECK constraint..."
END CATCH;
GO


-- =================================================================================
-- PART 2: READING VALUES (JSON_VALUE VS JSON_QUERY)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - JSON_VALUE: Extracts a simple scalar value (e.g., a single string, number, or boolean) from a JSON string.
--     Always returns the value converted to `NVARCHAR(4000)`. If pointed to an entire object or array,
--     returns NULL in lax mode (default) or fails in strict mode.
--   - JSON_QUERY: Extracts an entire structured fragment (an object `{}` or an array `[]`) from a JSON string.
--     Always returns a valid JSON string. If pointed to a simple scalar value (e.g., number or string),
--     returns NULL in lax mode or generates an error in strict mode.
--   - PATH EXPRESSIONS: Both functions use the `$` character to represent the JSON root,
--     followed by dot notation to navigate objects (e.g., `$.delivery.carrier`) or brackets for arrays (e.g., `$.items[0]`).

DECLARE @json NVARCHAR(MAX);
SELECT TOP 1
    @json = OrderDetails
FROM lab.OrdersJSON
WHERE CustomerName = 'Alice Smith';

SELECT @json
SELECT
    -- 1. Correct extraction of scalar values using JSON_VALUE
    JSON_VALUE(@json, '$.region') AS Region,
    JSON_VALUE(@json, '$.delivery.carrier') AS Carrier,
    JSON_VALUE(@json, '$.items[0].product') AS FirstProduct,

    -- 2. Attempting to retrieve an object/array using JSON_VALUE (Silently returns NULL!)
    JSON_VALUE(@json, '$.delivery') AS DeliveryObject_Value_Fail,
    JSON_VALUE(@json, '$.items') AS ItemsArray_Value_Fail,

    -- 3. Correct extraction of objects/arrays using JSON_QUERY
    JSON_QUERY(@json, '$.delivery') AS DeliveryObject_Query_Success,
    JSON_QUERY(@json, '$.items') AS ItemsArray_Query_Success,

    -- 4. Inverse attempt: retrieving a scalar value using JSON_QUERY (Also silently returns NULL!)
    JSON_QUERY(@json, '$.region') AS Scalar_Query_Fail,
    JSON_QUERY(@json, '$.delivery.carrier') AS ScalarCarrier_Query_Fail;
GO


-- =================================================================================
-- PART 3: PATH MODES (LAX VS STRICT)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - LAX MODE (Default): If the query tries to access a non-existent path,
--     a missing element, or mismatches the expected type (e.g., mapping a scalar to JSON_QUERY),
--     SQL Server silently returns NULL.
--   - STRICT MODE: Requires exact mapping. If the path does not exist or there is a type mismatch
--     (e.g., element not found, missing key), the engine interrupts the query and raises
--     execution error 13608 ("Property cannot be found on the specified JSON path").
--   - PRACTICAL APPLICATION: `strict` mode is essential for rigorous schema validation in ETL/Staging pipelines,
--     while `lax` mode is preferable for flexible queries tolerant of dynamic schemas.

DECLARE @json NVARCHAR(MAX) = N'{"name": "Alice"}';

-- Test 1: LAX Mode (Default) - silently returns NULL
SELECT
    JSON_VALUE(@json, 'lax $.age') AS AgeLax,
    JSON_VALUE(@json, '$.age') AS AgeDefault;
-- lax is the default if omitted

-- Test 2: STRICT Mode - triggers execution error Msg 13608
BEGIN TRY
    SELECT JSON_VALUE(@json, 'strict $.age') AS AgeStrict;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO STRICT: ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PART 4: OPENJSON - PARSING JSON INTO A RELATIONAL TABLE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - OPENJSON(): Table-valued function that parses JSON text and returns its properties
--     in a tabular format (rows and columns).
--   - OPENJSON WITHOUT THE WITH CLAUSE: Returns a fixed standard structure with 3 columns:
--     * key: Property name (or numeric index for arrays).
--     * value: Element value.
--     * type: Integer mapping the data type (0: Null, 1: String, 2: Number, 3: Boolean, 4: Array, 5: Object).
--   - OPENJSON WITH THE WITH CLAUSE: Allows explicitly declaring the resulting table schema, defining
--     column names, SQL types, and corresponding JSON paths (e.g., `Carrier VARCHAR(50) '$.delivery.carrier'`).
--   - AS JSON MODIFIER: Special instruction in the `WITH` clause required when a mapped column must
--     contain an entire sub-object or sub-array instead of a scalar value. Without it, SQL returns NULL.
--   - CROSS APPLY VS OUTER APPLY:
--     * CROSS APPLY: Behaves like INNER JOIN. If the '$.items' sub-array is empty ([]), missing, or NULL,
--       the parent table row is COMPLETELY DISCARDED from the final result.
--     * OUTER APPLY: Behaves like LEFT OUTER JOIN. If the '$.items' sub-array is empty ([]) or missing,
--       the parent table row IS PRESERVED in the final result with JSON columns filled with NULL.

-- -- [DP-800 EXAM TIP]
-- 1. In the exam, pay attention to whether the requirement asks to "keep orders without items in the listing".
--    If so, use OUTER APPLY. If it requires "only orders with valid items", use CROSS APPLY.
-- 2. The syntax "CROSS OUTER APPLY" does not exist in T-SQL; explicitly choose CROSS APPLY or OUTER APPLY.

DECLARE @json NVARCHAR(MAX);
SELECT TOP 1
    @json = OrderDetails
FROM lab.OrdersJSON
WHERE CustomerName = 'Alice Smith';

-- 1. OPENJSON without the WITH clause
-- Returns a standard table with three columns: key, value, and type.
-- Type: 1 = String, 2 = Number, 3 = Boolean, 4 = Array, 5 = Object, 0 = Null
SELECT *
FROM OPENJSON(@json);

-- 2. OPENJSON with the WITH clause (Root Document)
-- Directly maps JSON properties into user-defined typed columns.
SELECT *
FROM OPENJSON(@json)
WITH (
    Region NVARCHAR(50) '$.region',
    CarrierName NVARCHAR(50) '$.delivery.carrier',
    DeliveryDays INT '$.delivery.days',
    ItemsRaw NVARCHAR(MAX) '$.items' AS JSON -- 'AS JSON' prevents the array structure from being flattened
);

-- 3. Standalone query on the right side of CROSS APPLY (using @json variable):
SELECT
    Product,
    Qty,
    Price,
    (Qty * Price) AS LineTotal
FROM OPENJSON(@json, '$.items')
WITH (
    Product NVARCHAR(100) '$.product',
    Qty     INT           '$.qty',
    Price   DECIMAL(18,2) '$.price'
);

-- 3.b Direct inline subquery in OPENJSON's first parameter (without needing @json variable):
-- Quickly test reading any path against real table rows!
SELECT
    Product,
    Qty,
    Price,
    (Qty * Price) AS LineTotal
FROM OPENJSON(
    (SELECT TOP 1 OrderDetails FROM lab.OrdersJSON WHERE CustomerName = 'Alice Smith'),
    '$.items' -- Changing this path lets you navigate different parts of the JSON (e.g.: '$', '$.delivery', '$.items')
)
WITH (
    Product NVARCHAR(100) '$.product',
    Qty     INT           '$.qty',
    Price   DECIMAL(18,2) '$.price'
);

-- 4. CROSS APPLY with OPENJSON (INNER JOIN behavior)
-- If an order has an empty ([]) or missing (NULL) '$.items' array, the order row IS DISCARDED from the result.
SELECT
    o.OrderID,
    o.CustomerName,
    item.Product,
    item.Qty,
    item.Price,
    (item.Qty * item.Price) AS LineTotal
FROM lab.OrdersJSON o
CROSS APPLY OPENJSON(o.OrderDetails, '$.items')
WITH (
    Product NVARCHAR(100) '$.product',
    Qty     INT           '$.qty',
    Price   DECIMAL(18,2) '$.price'
) AS item;

-- 5. OUTER APPLY with OPENJSON (LEFT OUTER JOIN behavior)
-- Even if an order has an empty ([]) or missing '$.items' array, the order row IS PRESERVED in the result (filling items with NULL).
SELECT
    o.OrderID,
    o.CustomerName,
    item.Product,
    item.Qty,
    item.Price,
    (item.Qty * item.Price) AS LineTotal
FROM lab.OrdersJSON o
OUTER APPLY OPENJSON(o.OrderDetails, '$.items')
WITH (
    Product NVARCHAR(100) '$.product',
    Qty     INT           '$.qty',
    Price   DECIMAL(18,2) '$.price'
) AS item;
GO




-- =================================================================================
-- PART 5: MODERN AGGREGATORS (JSON_ARRAYAGG AND JSON_OBJECTAGG)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - JSON_ARRAYAGG: Aggregation function that groups values from a data column and converts them
--     into a single logical JSON array (e.g., `["Product A", "Product B"]`). Replaces the old need
--     for complex string concatenation hacks.
--   - JSON_OBJECTAGG: Aggregation function that creates a JSON object from two key-value fields
--     extracted from a relational table (e.g., `{"KeyA": "ValueA", "KeyB": "ValueB"}`).
--   - PLATFORM: Use these examples in Azure SQL Database/Managed Instance or SQL Server 2025,
--     where the aggregators are in preview. They are not features of SQL Server 2022.

-- 1. Creating a JSON Array of product names by category
SELECT
    pc.Name AS Categoria,
    JSON_ARRAYAGG(p.Name ORDER BY p.Name) AS Produtos
FROM Production.Product p
    JOIN Production.ProductSubcategory ps ON p.ProductSubcategoryID = ps.ProductSubcategoryID
    JOIN Production.ProductCategory pc ON ps.ProductCategoryID = pc.ProductCategoryID
GROUP BY pc.Name;

-- 2. Creating a JSON object of products by category.
-- Each ProductID becomes a property and the product name becomes the value.
-- [DP-800 EXAM TIP] JSON_OBJECTAGG aggregates key:value pairs, unlike
-- JSON_ARRAYAGG, which aggregates only values into a list.
SELECT
    pc.Name AS Categoria,
    JSON_OBJECTAGG(CONVERT(NVARCHAR(10), p.ProductID): p.Name) AS ProdutosPorId
FROM Production.Product AS p
JOIN Production.ProductSubcategory AS ps
    ON p.ProductSubcategoryID = ps.ProductSubcategoryID
JOIN Production.ProductCategory AS pc
    ON ps.ProductCategoryID = pc.ProductCategoryID
GROUP BY pc.Name;

-- 3. Generating a complex nested JSON payload (Orders with Items Array)
SELECT
    soh.SalesOrderID,
    soh.OrderDate,
    JSON_ARRAYAGG(JSON_OBJECT(
        'productID': sod.ProductID,
        'qty': sod.OrderQty,
        'price': sod.UnitPrice
    )) AS ItensDoPedido
FROM Sales.SalesOrderHeader soh
    JOIN Sales.SalesOrderDetail sod ON soh.SalesOrderID = sod.SalesOrderID
WHERE soh.SalesOrderID BETWEEN 43659 AND 43662
GROUP BY soh.SalesOrderID, soh.OrderDate;
GO


-- =================================================================================
-- PART 6: JSON INDEXING VIA COMPUTED COLUMNS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - JSON INDEXING LIMITATION: In tables with text-based JSON (`NVARCHAR(MAX)`), SQL Server does not
--     index the JSON path directly. Without an equivalent index, the query may require a scan;
--     always check the execution plan and estimated cost.
--   - COMPUTED COLUMN: Extract the path with JSON_VALUE into a calculated column and create a conventional
--     rowstore index. For JSON_VALUE, the column does not need to be PERSISTED to be indexed, as long as the expression
--     meets the usual determinism and precision requirements.
--   - JSON INDEXING: The index on the computed column enables selective searches on the internal JSON value.

-- 1. Populate the table with 1,000 random rows (using ABS(CHECKSUM(NEWID())) per attribute)
WITH
    Numbers
    AS
    (
        SELECT TOP (1000)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
    )
INSERT INTO lab.OrdersJSON
    (CustomerName, OrderDetails)
SELECT
    CONCAT('Customer_', n) AS CustomerName,
    JSON_OBJECT(
        'region': CASE (ABS(CHECKSUM(NEWID())) % 4) 
                    WHEN 0 THEN 'North' 
                    WHEN 1 THEN 'South' 
                    WHEN 2 THEN 'East' 
                    ELSE 'West' 
                  END,
        'delivery': JSON_OBJECT(
            'carrier': CASE (ABS(CHECKSUM(NEWID())) % 4) 
                        WHEN 0 THEN 'FedEx' 
                        WHEN 1 THEN 'DHL' 
                        WHEN 2 THEN 'Correios' 
                        ELSE 'UPS' 
                       END,
            'days': (ABS(CHECKSUM(NEWID())) % 10) + 1
        ),
        'items': CASE WHEN (ABS(CHECKSUM(NEWID())) % 5) = 0 THEN JSON_ARRAY() -- 20% of orders have no items (array []) to test CROSS vs OUTER APPLY
                 ELSE JSON_ARRAY(
                    JSON_OBJECT('product': 'Bike Helmet', 'qty': (ABS(CHECKSUM(NEWID())) % 3) + 1, 'price': 50.00),
                    JSON_OBJECT('product': 'Water Bottle', 'qty': (ABS(CHECKSUM(NEWID())) % 4) + 1, 'price': 10.00)
                 )
            END
    ) AS OrderDetails
FROM Numbers;
GO

-- 2. Enable I/O statistics
SET STATISTICS IO ON;
GO

-- Test 1: Query filtering JSON property before creating the index.
-- EXECUTION PLAN: with this volume, it is common to see a Clustered Index Scan, but the plan depends
-- on the data, statistics, and estimated cost.
SELECT CustomerName, OrderDetails
FROM lab.OrdersJSON
WHERE JSON_VALUE(OrderDetails, '$.region') = 'South';
GO

-- 3. Create a computed column extracting the JSON property
-- ARCHITECTURE NOTE / DP-800:
--   - JSON_VALUE returns NVARCHAR(4000) by default (which occupies 8,000 bytes).
--   - The maximum key size for a non-clustered index is 1,700 bytes.
--   - If we do not use CAST, SQL Server issues an 8,000-byte WARNING.
--   - SOLUTION: Apply CAST(JSON_VALUE(...) AS NVARCHAR(50)) to define the exact size and eliminate warnings.
--ALTER TABLE lab.OrdersJSON
--drop column Region 
--GO
ALTER TABLE lab.OrdersJSON
ADD Region AS CAST(JSON_VALUE(OrderDetails, '$.region') AS NVARCHAR(50));
GO

-- 4. Create the non-clustered COVERING INDEX on the computed column
-- KEY CONCEPTS AND DEFINITIONS (COVERING INDEX VS KEY LOOKUP):
--   - WITHOUT INCLUDE: The index only stores (Region + PK OrderID). To return CustomerName and OrderDetails,
--     SQL Server performs an "Index Seek" on the index and then a "Key Lookup" on the main table for each row.
--   - WITH INCLUDE: Adding 'INCLUDE (CustomerName, OrderDetails)' stores these columns directly in the index
--     leaf pages. This transforms it into a COVERING INDEX. The query satisfies 100% of the data
--     directly from the index, ELIMINATING THE KEY LOOKUP and performing only a pure, ultra-fast INDEX SEEK!


--drop INDEX IX_OrdersJSON_Region_Covered
--ON lab.OrdersJSON 


CREATE NONCLUSTERED INDEX IX_OrdersJSON_Region_Covered
ON lab.OrdersJSON(Region) 
INCLUDE (CustomerName, OrderDetails);
GO

-- Test 2.a: Query filtering by JSON_VALUE expression
SELECT CustomerName, OrderDetails
FROM lab.OrdersJSON
WHERE JSON_VALUE(OrderDetails, '$.region') = 'South';
GO

-- Test 2.b: SARGable query filtering directly by the computed column 'Region'
-- Since the index includes (CustomerName, OrderDetails), the plan performs a pure INDEX SEEK without Key Lookup!
SELECT CustomerName, OrderDetails
FROM lab.OrdersJSON WITH (INDEX (IX_OrdersJSON_Region_Covered))
WHERE Region = 'South';
GO

SET STATISTICS IO OFF;
GO


-- =================================================================================
-- PART 7: DYNAMIC T-SQL QUERIES GENERATED FROM JSON SCHEMA (METADATA)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DYNAMIC METADATA-DRIVEN QUERIES: It is perfectly possible (and very common in modern
--     ETL, Data Mesh, and EAV architectures) to store JSON field/mapping definitions in a metadata table.
--   - MECHANISM:
--     1. A table stores the desired schema structure in JSON format.
--     2. Using `OPENJSON`, we read these metadata (column names, paths, and whether scalar or object).
--     3. We use `STRING_AGG` to concatenate the `SELECT` statement dynamically with `JSON_VALUE` or `JSON_QUERY`.
--     4. Execute with `sp_executesql` ensuring security and flexibility.

-- 1. Create the Schema Metadata table
DROP TABLE IF EXISTS lab.DynamicJsonMapping;
CREATE TABLE lab.DynamicJsonMapping
(
    MappingID INT IDENTITY(1,1) PRIMARY KEY,
    TargetTableName NVARCHAR(100) NOT NULL,
    SchemaDefinition NVARCHAR(MAX) NOT NULL
);
GO

-- 2. Insert the dynamic schema definition in JSON format
INSERT INTO lab.DynamicJsonMapping
    (TargetTableName, SchemaDefinition)
VALUES
    (
        'OrdersJSON',
        N'[
        {"ColumnAlias": "RegiaoPedido", "JsonPath": "$.region", "DataType": "NVARCHAR(50)", "IsScalar": 1},
        {"ColumnAlias": "Transportadora", "JsonPath": "$.delivery.carrier", "DataType": "NVARCHAR(50)", "IsScalar": 1},
        {"ColumnAlias": "ObjetoEntregaCompleto", "JsonPath": "$.delivery", "DataType": "NVARCHAR(MAX)", "IsScalar": 0}
    ]'
);
GO

-- 3. Procedure/T-SQL block to build and execute the query dynamically
DECLARE @TargetTable NVARCHAR(100) = 'OrdersJSON';
DECLARE @SchemaJson NVARCHAR(MAX);
DECLARE @DynamicSql NVARCHAR(MAX);
DECLARE @ColumnSelectList NVARCHAR(MAX);

-- Retrieve the JSON schema definition stored in the metadata table
SELECT @SchemaJson = SchemaDefinition
FROM lab.DynamicJsonMapping
WHERE TargetTableName = @TargetTable;

-- Parse the definition with OPENJSON and build the SELECT clauses using STRING_AGG
SELECT @ColumnSelectList = STRING_AGG(
    CASE 
        WHEN IsScalar = 1 THEN CONCAT('JSON_VALUE(OrderDetails, ''', JsonPath, ''') AS [', ColumnAlias, ']')
        ELSE CONCAT('JSON_QUERY(OrderDetails, ''', JsonPath, ''') AS [', ColumnAlias, ']')
    END,
    ',' + CHAR(10) + '    '
)
FROM OPENJSON(@SchemaJson)
WITH (
    ColumnAlias NVARCHAR(100) '$.ColumnAlias',
    JsonPath    NVARCHAR(200) '$.JsonPath',
    DataType    NVARCHAR(50)  '$.DataType',
    IsScalar    BIT           '$.IsScalar'
);

-- Build the complete SELECT statement
SET @DynamicSql = CONCAT(
    'SELECT CustomerName, ', CHAR(10), '    ', @ColumnSelectList, CHAR(10),
    'FROM lab.OrdersJSON;'
);

-- Display the T-SQL statement that was automatically generated
PRINT '=== T-SQL DINÂMICO GERADO A PARTIR DOS METADADOS JSON ===';
PRINT @DynamicSql;

-- Execute the dynamically generated query
EXEC sp_executesql @DynamicSql;
GO


-- =================================================================================
-- PART 8: ENCAPSULATION IN A 100% DYNAMIC STORED PROCEDURE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - 100% DYNAMIC METADATA-DRIVEN QUERIES: Instead of hardcoding table names or keys,
--     the Stored Procedure reads ALL metadata (Schema, Table, Primary Key Columns, JSON Column, and Mappings).
--   - MECHANISM:
--     1. A flexible metadata table registers the target table, which key columns to select, the JSON column, and the attribute mappings.
--     2. The procedure `lab.sp_ExecuteFullyDynamicJsonQuery` inspects the mapping table.
--     3. It 100% dynamically builds the SELECT, FROM, column names, and JSON_VALUE / JSON_QUERY functions without any hardcoding.
--     4. Executes with `sp_executesql`.

-- 1. Create the 100% Flexible Schema Metadata table
DROP TABLE IF EXISTS lab.FullyDynamicJsonMapping;
CREATE TABLE lab.FullyDynamicJsonMapping (
    MappingID INT IDENTITY(1,1) PRIMARY KEY,
    SchemaName NVARCHAR(128) NOT NULL DEFAULT 'lab',
    TargetTableName NVARCHAR(128) NOT NULL,
    KeyColumns NVARCHAR(250) NOT NULL, -- Relational table columns to preserve in SELECT
    JsonColumnName NVARCHAR(128) NOT NULL, -- Name of the physical column containing the JSON
    SchemaDefinition NVARCHAR(MAX) NOT NULL
);
GO

-- 2. Insert the dynamic schema definition in JSON format
INSERT INTO lab.FullyDynamicJsonMapping (SchemaName, TargetTableName, KeyColumns, JsonColumnName, SchemaDefinition)
VALUES (
    'lab',
    'OrdersJSON',
    'OrderID, CustomerName',
    'OrderDetails',
    N'[
        {"ColumnAlias": "RegiaoPedido", "JsonPath": "$.region", "DataType": "NVARCHAR(50)", "IsScalar": 1},
        {"ColumnAlias": "Transportadora", "JsonPath": "$.delivery.carrier", "DataType": "NVARCHAR(50)", "IsScalar": 1},
        {"ColumnAlias": "ObjetoEntregaCompleto", "JsonPath": "$.delivery", "DataType": "NVARCHAR(MAX)", "IsScalar": 0}
    ]'
);
GO

-- 3. 100% Dynamic Stored Procedure for any Table and any JSON
CREATE OR ALTER PROCEDURE lab.sp_ExecuteFullyDynamicJsonQuery
    @TargetTableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SchemaName NVARCHAR(128);
    DECLARE @KeyColumns NVARCHAR(250);
    DECLARE @JsonColumnName NVARCHAR(128);
    DECLARE @SchemaJson NVARCHAR(MAX);
    DECLARE @ColumnSelectList NVARCHAR(MAX);
    DECLARE @DynamicSql NVARCHAR(MAX);

    -- 1. Retrieve ALL table metadata from the mapping repository
    SELECT 
        @SchemaName = SchemaName,
        @KeyColumns = KeyColumns,
        @JsonColumnName = JsonColumnName,
        @SchemaJson = SchemaDefinition 
    FROM lab.FullyDynamicJsonMapping 
    WHERE TargetTableName = @TargetTableName;

    IF @SchemaJson IS NULL
    BEGIN
        RAISERROR('Nenhum mapeamento de metadados encontrado para a tabela %s', 16, 1, @TargetTableName);
        RETURN;
    END;

    -- 2. Parse the schema with OPENJSON and build JSON extraction expressions using STRING_AGG
    SELECT @ColumnSelectList = STRING_AGG(
        CASE 
            WHEN IsScalar = 1 THEN CONCAT('JSON_VALUE(', QUOTENAME(@JsonColumnName), ', ''', JsonPath, ''') AS [', ColumnAlias, ']')
            ELSE CONCAT('JSON_QUERY(', QUOTENAME(@JsonColumnName), ', ''', JsonPath, ''') AS [', ColumnAlias, ']')
        END,
        ',' + CHAR(10) + '    '
    )
    FROM OPENJSON(@SchemaJson)
    WITH (
        ColumnAlias NVARCHAR(100) '$.ColumnAlias',
        JsonPath    NVARCHAR(200) '$.JsonPath',
        DataType    NVARCHAR(50)  '$.DataType',
        IsScalar    BIT           '$.IsScalar'
    );

    -- 3. Build the SELECT statement 100% dynamically (No hardcoded table or column names!)
    SET @DynamicSql = CONCAT(
        'SELECT ', @KeyColumns, ', ', CHAR(10), '    ', @ColumnSelectList, CHAR(10),
        'FROM ', QUOTENAME(@SchemaName), '.', QUOTENAME(@TargetTableName), ';'
    );

    -- 4. Display the generated T-SQL for auditing
    PRINT '================ T-SQL 100% DINÂMICO GERADO VIA METADADOS ================';
    PRINT @DynamicSql;

    -- 5. Execute the query
    EXEC sp_executesql @DynamicSql;
END;
GO

-- Execution Test of the 100% Dynamic Stored Procedure:
EXEC lab.sp_ExecuteFullyDynamicJsonQuery @TargetTableName = 'OrdersJSON';
GO
