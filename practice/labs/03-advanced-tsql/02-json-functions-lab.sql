-- =============================================================================
-- DP-800 - HANDS-ON LAB: JSON FUNCTIONS WITH ADVENTUREWORKS2025
-- Prerequisite: AdventureWorks2025 restored; OPENJSON requires compatibility 130+.
-- This script creates and changes only lab.JsonFunctions... objects.
-- Goal: extract, validate, shred, modify, and serialize JSON documents. Enable an
-- Actual Execution Plan for Parts 2 and 6 and capture rows, reads, CPU, and memory.
-- =============================================================================

USE AdventureWorks2025;
GO

SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF SCHEMA_ID(N'lab') IS NULL EXEC(N'CREATE SCHEMA lab');
GO

DROP TABLE IF EXISTS lab.JsonFunctionsStage;
DROP TABLE IF EXISTS lab.JsonFunctionsOrders;
DROP TABLE IF EXISTS lab.JsonFunctionsCustomers;
DROP TABLE IF EXISTS lab.JsonFunctionsMapping;
DROP TABLE IF EXISTS lab.JsonFunctionsProductAttributes;
DROP PROCEDURE IF EXISTS lab.usp_JsonFunctionsProjection;
GO

CREATE TABLE lab.JsonFunctionsOrders
(
    SalesOrderID int NOT NULL CONSTRAINT PK_JsonFunctionsOrders PRIMARY KEY,
    OrderDate datetime NOT NULL,
    OrderDocument nvarchar(max) NOT NULL,
    CONSTRAINT CK_JsonFunctionsOrders_Document CHECK (ISJSON(OrderDocument) = 1)
);
GO

INSERT INTO lab.JsonFunctionsOrders (SalesOrderID, OrderDate, OrderDocument)
SELECT TOP (1000)
    h.SalesOrderID, h.OrderDate,
    (
        SELECT h.SalesOrderNumber AS [order.number],
               st.Name AS [territory.name],
               a.City AS [shipping.city],
               JSON_QUERY((
                    SELECT p.ProductNumber AS [sku], p.Name AS [name],
                           d.OrderQty AS [qty], d.UnitPrice AS [price]
                    FROM Sales.SalesOrderDetail AS d
                    JOIN Production.Product AS p ON p.ProductID = d.ProductID
                    WHERE d.SalesOrderID = h.SalesOrderID
                    FOR JSON PATH
               )) AS [items]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )
FROM Sales.SalesOrderHeader AS h
JOIN Sales.SalesTerritory AS st ON st.TerritoryID = h.TerritoryID
JOIN Person.Address AS a ON a.AddressID = h.ShipToAddressID
ORDER BY h.SalesOrderID;

-- Controlled lab-only row to show OUTER APPLY preserving an empty array.
INSERT INTO lab.JsonFunctionsOrders (SalesOrderID, OrderDate, OrderDocument)
VALUES (-1, GETDATE(), N'{"order":{"number":"LAB-EMPTY"},"territory":{"name":"Lab"},"items":[]}');
GO

SELECT COUNT(*) AS Documents,
       SUM(CASE WHEN SalesOrderID = -1 THEN 1 ELSE 0 END) AS EmptyArrayDocuments
FROM lab.JsonFunctionsOrders;
GO

-- PART 1: JSON_VALUE, JSON_QUERY, PATHS, AND LAX/STRICT
-- Expected result: WrongScalar is NULL; ItemsArray returns the JSON array.
SELECT TOP (5)
    JSON_VALUE(OrderDocument, '$.order.number') AS OrderNumber,
    JSON_VALUE(OrderDocument, '$.shipping.city') AS ShipCity,
    JSON_VALUE(OrderDocument, '$.items') AS WrongScalar,
    JSON_QUERY(OrderDocument, '$.items') AS ItemsArray
FROM lab.JsonFunctionsOrders
WHERE SalesOrderID > 0;
GO

DECLARE @doc nvarchar(max) = N'{"customer":{"name":"Ada"},"address line":"One"}';
SELECT JSON_VALUE(@doc, '$."address line"') AS QuotedKey,
       JSON_VALUE(@doc, 'lax $.missing') AS LaxMissing;
BEGIN TRY
    SELECT JSON_VALUE(@doc, 'strict $.missing') AS StrictMissing;
END TRY
BEGIN CATCH
    PRINT N'Expected strict error: ' + ERROR_MESSAGE();
END CATCH;
GO

-- JSON_VALUE returns nvarchar(4000); use OPENJSON for scalar values beyond it.
-- SELECT JSON_VALUE(@largeDocument, '$.longScalar'); -- NULL in lax if > 4000
-- Use strict for contractual properties. In ingestion, triage in lax first so one
-- malformed document does not stop the entire batch.

-- PART 2: OPENJSON DEFAULT, WITH, AS JSON, CROSS APPLY, OUTER APPLY
-- WITH projects typed paths and AS JSON preserves a nested object/array for further parsing.
DECLARE @oneOrder nvarchar(max) =
    (SELECT TOP (1) OrderDocument FROM lab.JsonFunctionsOrders WHERE SalesOrderID > 0);

SELECT [key], [value], [type] FROM OPENJSON(@oneOrder);

SELECT OrderNumber, Territory, Items
FROM OPENJSON(@oneOrder)
WITH
(
    OrderNumber nvarchar(25) '$.order.number',
    Territory nvarchar(50) '$.territory.name',
    Items nvarchar(max) '$.items' AS JSON
);

SELECT o.SalesOrderID, item.Sku, item.Qty, item.Price
FROM lab.JsonFunctionsOrders AS o
CROSS APPLY OPENJSON(o.OrderDocument, '$.items')
WITH (Sku nvarchar(25) '$.sku', Qty int '$.qty', Price money '$.price') AS item
WHERE o.SalesOrderID IN (-1, 43659);

SELECT o.SalesOrderID, item.Sku, item.Qty
FROM lab.JsonFunctionsOrders AS o
OUTER APPLY OPENJSON(o.OrderDocument, '$.items')
WITH (Sku nvarchar(25) '$.sku', Qty int '$.qty') AS item
WHERE o.SalesOrderID IN (-1, 43659);
GO
-- CROSS APPLY removes order -1; OUTER APPLY preserves it with NULL item values.
-- OPENJSON multiplies rows, so reduce the outer set before APPLY whenever possible.

-- PART 3: VALIDATE STAGING THEN LOAD STRICTLY
-- Never apply strict paths directly to untrusted batches: triage invalid JSON and
-- missing required properties first, then read the approved rows strictly.
CREATE TABLE lab.JsonFunctionsStage (RowId int IDENTITY PRIMARY KEY, JsonData nvarchar(max) NULL);
INSERT INTO lab.JsonFunctionsStage (JsonData)
VALUES (N'{"id":1,"name":"valid"}'), (N'{"id":2}'), (N'{"id":');

SELECT RowId, JsonData
FROM lab.JsonFunctionsStage
WHERE ISJSON(JsonData) = 0
   OR JSON_VALUE(JsonData, '$.id') IS NULL
   OR JSON_VALUE(JsonData, '$.name') IS NULL;

SELECT JSON_VALUE(JsonData, 'strict $.id') AS Id,
       JSON_VALUE(JsonData, 'strict $.name') AS Name
FROM lab.JsonFunctionsStage
WHERE ISJSON(JsonData) = 1 AND JSON_VALUE(JsonData, '$.name') IS NOT NULL;
GO

-- PART 4: MODIFY AND SERIALIZE WITHOUT CHANGING ADVENTUREWORKS TABLES
-- JSON_MODIFY returns a new document. The source table is not updated here.
SELECT TOP (3) SalesOrderID,
    JSON_MODIFY(JSON_MODIFY(OrderDocument, '$.shipping.city', N'Redacted'),
                '$.temporary', NULL) AS SafeProjection
FROM lab.JsonFunctionsOrders;

SELECT TOP (3)
    h.SalesOrderID AS [order.id], h.OrderDate AS [order.date],
    p.FirstName AS [customer.firstName], p.LastName AS [customer.lastName]
FROM Sales.SalesOrderHeader AS h
JOIN Sales.Customer AS c ON c.CustomerID = h.CustomerID
LEFT JOIN Person.Person AS p ON p.BusinessEntityID = c.PersonID
FOR JSON PATH, ROOT('orders');

SELECT TOP (3) h.SalesOrderID, d.SalesOrderDetailID, d.OrderQty
FROM Sales.SalesOrderHeader AS h
JOIN Sales.SalesOrderDetail AS d ON d.SalesOrderID = h.SalesOrderID
FOR JSON AUTO;
GO

-- PART 4B: JSON_MODIFY DETAILS AND SQL SERVER 2025 ON-PREMISES TESTS
DECLARE @config nvarchar(max) = N'{"env":"dev","tags":["dp800","json"]}';
SELECT JSON_MODIFY(@config, '$.env', NULL) AS RemovedInLax,
       JSON_MODIFY(@config, '$.tags', JSON_QUERY(@config, '$.tags')) AS ArrayNotEscaped;
BEGIN TRY
    SELECT JSON_MODIFY(@config, 'strict $.missing', N'x') AS StrictFailure;
END TRY
BEGIN CATCH
    PRINT N'Expected JSON_MODIFY strict error: ' + ERROR_MESSAGE();
END CATCH;
GO

-- SQL Server 2025 on-premises can run these tests. Dynamic SQL prevents parsing
-- failures on earlier on-premises versions; FOR JSON remains the portable fallback.
-- SELECT JSON_OBJECT('orderId': SalesOrderID) FROM lab.JsonFunctionsOrders;
-- SELECT JSON_ARRAYAGG(SalesOrderID) FROM lab.JsonFunctionsOrders;
-- SELECT JSON_CONTAINS(OrderDocument, '"Lab"', '$.territory.name')
-- FROM lab.JsonFunctionsOrders;
DECLARE @FeatureMajorVersion int = TRY_CONVERT(int, SERVERPROPERTY(N'ProductMajorVersion'));
DECLARE @FeatureCompatibility int = CONVERT(int, DATABASEPROPERTYEX(DB_NAME(), N'CompatibilityLevel'));
IF @FeatureMajorVersion >= 17 AND @FeatureCompatibility >= 170
BEGIN
    EXEC sys.sp_executesql N'
        SELECT JSON_ARRAYAGG(SalesOrderID ORDER BY SalesOrderID) AS OrderIdsJson
        FROM lab.JsonFunctionsOrders WHERE SalesOrderID > 0;
        SELECT SalesOrderID,
               JSON_CONTAINS(CAST(OrderDocument AS json), ''"Northwest"'', ''$.territory.name'') AS IsNorthwest
        FROM lab.JsonFunctionsOrders
        WHERE SalesOrderID > 0
          AND JSON_CONTAINS(CAST(OrderDocument AS json), ''"Northwest"'', ''$.territory.name'') = 1;';
END
ELSE
    PRINT N'SQL Server 2025 JSON features skipped: version 17.x and compatibility 170 are required.';
GO

-- PART 4C: ROW AGGREGATION AND AN API/LLM PAYLOAD
CREATE TABLE lab.JsonFunctionsProductAttributes
(
    ProductID int NOT NULL,
    AttributeName sysname NOT NULL,
    AttributeValue nvarchar(100) NOT NULL,
    CONSTRAINT PK_JsonFunctionsProductAttributes PRIMARY KEY (ProductID, AttributeName)
);
INSERT INTO lab.JsonFunctionsProductAttributes (ProductID, AttributeName, AttributeValue)
SELECT TOP (12) p.ProductID, v.AttributeName, v.AttributeValue
FROM Production.Product AS p
CROSS APPLY (VALUES
    (N'productNumber', CONVERT(nvarchar(100), p.ProductNumber)),
    (N'color', COALESCE(p.Color, N'not-specified')),
    (N'class', COALESCE(p.Class, N'not-specified'))
) AS v(AttributeName, AttributeValue)
WHERE p.ProductNumber IS NOT NULL ORDER BY p.ProductID, v.AttributeName;
GO
-- Portable fallback: attributes as an array for each product.
SELECT a.ProductID, JSON_QUERY((
    SELECT a2.AttributeName AS [name], a2.AttributeValue AS [value]
    FROM lab.JsonFunctionsProductAttributes AS a2
    WHERE a2.ProductID = a.ProductID ORDER BY a2.AttributeName FOR JSON PATH
)) AS AttributesJson
FROM lab.JsonFunctionsProductAttributes AS a
GROUP BY a.ProductID ORDER BY a.ProductID;
GO
DECLARE @AttributeMajorVersion int = TRY_CONVERT(int, SERVERPROPERTY(N'ProductMajorVersion'));
IF @AttributeMajorVersion >= 17
    EXEC sys.sp_executesql N'
        SELECT ProductID, JSON_ARRAYAGG(AttributeName ORDER BY AttributeName) AS AttributeNamesJson,
               JSON_OBJECTAGG(AttributeName: AttributeValue) AS AttributesObjectJson
        FROM lab.JsonFunctionsProductAttributes GROUP BY ProductID ORDER BY ProductID;';
GO

-- This only builds an output payload from real product data; it sends no request
-- to an AI service and stores no secrets. JSON_QUERY avoids escaped nested arrays.
DECLARE @SystemPrompt nvarchar(400) = N'Answer only with catalog recommendations based on the supplied context.';
DECLARE @UserPrompt nvarchar(400) = N'Summarize available bicycle products and highlight color and product number.';
SELECT (
    SELECT N'gpt-4.1' AS [model], CONVERT(decimal(3,1), 0.2) AS [temperature],
           JSON_QUERY((SELECT m.[role], m.[content] FROM (
               SELECT N'system' AS [role], @SystemPrompt AS [content]
               UNION ALL SELECT N'user', @UserPrompt
           ) AS m FOR JSON PATH)) AS [messages],
           JSON_QUERY((SELECT TOP (3) p.ProductID AS [id], p.ProductNumber AS [number],
                              p.Name AS [name], p.Color AS [color]
                       FROM Production.Product AS p WHERE p.ProductNumber IS NOT NULL
                       ORDER BY p.ProductID FOR JSON PATH)) AS [context.products]
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
) AS PayloadJson;
GO

-- PART 6: PLAN AND ROW EXPANSION
ALTER TABLE lab.JsonFunctionsOrders
ADD TerritoryName AS CONVERT(nvarchar(50), JSON_VALUE(OrderDocument, '$.territory.name'));
CREATE INDEX IX_JsonFunctionsOrders_TerritoryName ON lab.JsonFunctionsOrders (TerritoryName);
GO

SET STATISTICS IO, TIME ON;
SELECT SalesOrderID
FROM lab.JsonFunctionsOrders
WHERE CONVERT(nvarchar(50), JSON_VALUE(OrderDocument, '$.territory.name')) = N'Northwest';

-- Compare estimated and actual rows around APPLY. Restrict outer orders first.
SELECT o.SalesOrderID, item.Sku, item.Qty
FROM lab.JsonFunctionsOrders AS o
CROSS APPLY OPENJSON(o.OrderDocument, '$.items')
WITH (Sku nvarchar(25) '$.sku', Qty int '$.qty') AS item
WHERE o.OrderDate >= '20070101'
  AND CONVERT(nvarchar(50), JSON_VALUE(o.OrderDocument, '$.territory.name')) = N'Northwest';
SET STATISTICS IO, TIME OFF;
GO

-- Review: scans/seeks, lookups, reads, CPU, row estimates, row multiplication,
-- join/sort operators, memory grants, and spills. Do not expect a fixed plan.
-- A JSON index can improve the territory predicate but cannot eliminate the cost of
-- expanding every item; reduce outer orders before OPENJSON.

-- PART 7: ADVANCED METADATA-DRIVEN PROJECTION WITH SAFE DYNAMIC SQL
-- =================================================================================
-- This procedure is METADATA-DRIVEN: it reads a projection definition saved
-- in lab.JsonFunctionsMapping (as JSON) and dynamically builds the SELECT
-- column list. To reuse on ANY table with a JSON column, simply pass:
--   @MappingName -> mapping name saved in lab.JsonFunctionsMapping
--   @TableName   -> fully qualified table name (e.g., lab.JsonFunctionsProducts)
--   @JsonColumn  -> name of the JSON column in that table (e.g., AttributesJson)
--   @KeyColumn   -> name of the primary key column returned as 1st SELECT column
--                   (e.g., ProductID, SalesOrderID, CustomerID, etc.)
-- =================================================================================
CREATE TABLE lab.JsonFunctionsMapping
(
    MappingName sysname NOT NULL CONSTRAINT PK_JsonFunctionsMapping PRIMARY KEY,
    Definition  nvarchar(max) NOT NULL CONSTRAINT CK_JsonFunctionsMapping CHECK (ISJSON(Definition) = 1)
);
GO
INSERT INTO lab.JsonFunctionsMapping (MappingName, Definition) VALUES
(N'OrderSummary', N'[
  {"alias":"OrderNumber","path":"$.order.number","kind":"scalar"},
  {"alias":"Territory",  "path":"$.territory.name","kind":"scalar"},
  {"alias":"Items",      "path":"$.items",          "kind":"json"}]');
GO

-- =================================================================================
-- FULLY GENERIC PROCEDURE: accepts ANY table + JSON column + primary key.
-- Security validations (aligned with MS Learn Dynamic SQL):
--   1) sys.tables confirms table exists in the expected schema
--   2) sys.columns confirms @JsonColumn and @KeyColumn exist in table
--   3) OBJECT_ID + QUOTENAME isolate identifiers against SQL injection
--   4) Typed sp_executesql avoids value concatenation
-- =================================================================================
CREATE OR ALTER PROCEDURE lab.usp_JsonFunctionsProjection
     @MappingName sysname,   -- e.g., N'OrderSummary'
     @TableName   sysname,   -- e.g., N'lab.JsonFunctionsOrders' (2-part required)
     @JsonColumn  sysname,   -- e.g., N'OrderDocument' (JSON column in table)
     @KeyColumn   sysname,   -- e.g., N'SalesOrderID'  (PK returned as 1st column)
     @Debug       bit = 0    -- 1 = PRINT the built SQL before executing
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @schema sysname, @table sysname, @definition nvarchar(max),
            @selectList nvarchar(max), @sql nvarchar(max);

    ------------------------------------------------------------------
    -- 1) Parse @TableName into schema + table (safe 2-part name)
    ------------------------------------------------------------------
    SELECT @schema = PARSENAME(@TableName, 2),
           @table  = PARSENAME(@TableName, 1);

    IF @schema IS NULL OR @table IS NULL
        THROW 50001, N'Provide table name in schema.table format.', 1;

    ------------------------------------------------------------------
    -- 2) Validate TABLE exists via sys.tables
    ------------------------------------------------------------------
    IF OBJECT_ID(@TableName, 'U') IS NULL
        THROW 50002, N'Table "' + @TableName + N'" does not exist in current database.', 1;

    ------------------------------------------------------------------
    -- 3) Validate that @JsonColumn and @KeyColumn EXIST in the table
    ------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.tables  t ON t.object_id = c.object_id
        WHERE SCHEMA_NAME(t.schema_id) = @schema
          AND t.name  = @table
          AND c.name  = @JsonColumn)
        THROW 50003, N'JSON column "' + @JsonColumn + N'" does not exist in ' + @TableName + N'.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.tables  t ON t.object_id = c.object_id
        WHERE SCHEMA_NAME(t.schema_id) = @schema
          AND t.name  = @table
          AND c.name  = @KeyColumn)
        THROW 50004, N'Key column "' + @KeyColumn + N'" does not exist in ' + @TableName + N'.', 1;

    ------------------------------------------------------------------
    -- 4) Read the saved mapping DEFINITION
    ------------------------------------------------------------------
    SELECT @definition = Definition
    FROM   lab.JsonFunctionsMapping
    WHERE  MappingName = @MappingName;

    IF @definition IS NULL
        THROW 50005, N'Mapping "' + @MappingName + N'" not found in lab.JsonFunctionsMapping.', 1;

    ------------------------------------------------------------------
    -- 5) Build the SELECT LIST dynamically
    --    JSON_VALUE / JSON_QUERY need to know which JSON column to read —
    --    @JsonColumn is safe because validated against sys.columns (step 3).
    --    JSON paths from mapping are validated by JsonPath LIKE '$.%'.
    ------------------------------------------------------------------
    SELECT @selectList = STRING_AGG(
        CASE WHEN Kind = N'scalar'
             THEN N'JSON_VALUE(' + QUOTENAME(@JsonColumn) + N', '''
                + REPLACE(JsonPath, '''', '''''') + N''') AS ' + QUOTENAME(AliasName)
             ELSE N'JSON_QUERY(' + QUOTENAME(@JsonColumn) + N', '''
                + REPLACE(JsonPath, '''', '''''') + N''') AS ' + QUOTENAME(AliasName)
        END,
        N',' + CHAR(10) + N'    ')
    FROM OPENJSON(@definition)
    WITH (
        AliasName sysname      N'$.alias',
        JsonPath  nvarchar(400) N'$.path',
        Kind      nvarchar(10)  N'$.kind'
    )
    WHERE JsonPath LIKE N'$.%' AND Kind IN (N'scalar', N'json');

    IF @selectList IS NULL
        THROW 50006, N'Mapping "' + @MappingName + N'" has no allowed paths.', 1;

    ------------------------------------------------------------------
    -- 6) Build the final SQL — ALL via QUOTENAME (no value concatenation)
    ------------------------------------------------------------------
    SET @sql = N'SELECT ' + QUOTENAME(@KeyColumn) + N',' + CHAR(10) + N'    ' + @selectList
             + CHAR(10) + N'FROM '   + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N';';

    IF @Debug = 1
        PRINT @sql;

    EXEC sys.sp_executesql @sql;
END;
GO

-- =================================================================================
-- USAGE EXAMPLES — same proc, SAME mapping, different tables/columns.
-- =================================================================================

-- (A) OrderSummary against the ORDERS table (the original)
EXEC lab.usp_JsonFunctionsProjection
     @MappingName = N'OrderSummary',
     @TableName   = N'lab.JsonFunctionsOrders',
     @JsonColumn  = N'OrderDocument',
     @KeyColumn   = N'SalesOrderID',
     @Debug       = 1;
GO

-- (B) Demonstrating mapping REUSE: same proc, SAME JSON, SAME structure,
--     but pointing to a hypothetical customers table (example only).
--     The proc validates via sys.columns before building SQL, so any
--     valid @TableName.@JsonColumn combination works:
IF OBJECT_ID('lab.JsonFunctionsCustomers', 'U') IS NULL
BEGIN
    CREATE TABLE lab.JsonFunctionsCustomers (
        CustomerID   int NOT NULL PRIMARY KEY,
        CustomerName sysname NOT NULL,
        CustomerData nvarchar(max) NOT NULL
            CONSTRAINT CK_JsonFunctionsCustomers_Data CHECK (ISJSON(CustomerData) = 1)
    );
    INSERT INTO lab.JsonFunctionsCustomers (CustomerID, CustomerName, CustomerData) VALUES
    (1, N'ACME Corp.', N'{"order":{"number":"AC-001"},"territory":{"name":"North"},"items":[{"sku":"X","qty":2}]}'),
    (2, N'Globex',    N'{"order":{"number":"GB-002"},"territory":{"name":"South"},"items":[]}');
END;
GO
-- To reuse the same "OrderSummary" structure for the customers table,
-- declare a new mapping pointing to CustomerData:
INSERT INTO lab.JsonFunctionsMapping (MappingName, Definition) VALUES
(N'CustomerOrderSummary', N'[
  {"alias":"OrderNumber","path":"$.order.number","kind":"scalar"},
  {"alias":"Territory",  "path":"$.territory.name","kind":"scalar"},
  {"alias":"Items",      "path":"$.items",          "kind":"json"}]');
GO
EXEC lab.usp_JsonFunctionsProjection
     @MappingName = N'CustomerOrderSummary',
     @TableName   = N'lab.JsonFunctionsCustomers',
     @JsonColumn  = N'CustomerData',
     @KeyColumn   = N'CustomerID';
GO

-- =================================================================================
-- (C) Safe FAILURE demonstration — passing a non-existent column, the proc REJECTS
--     before attempting any dynamic SQL (protection against typos and SQL injection):
-- =================================================================================
EXEC lab.usp_JsonFunctionsProjection
     @MappingName = N'OrderSummary',
     @TableName   = N'lab.JsonFunctionsOrders',
     @JsonColumn  = N'ColunaInexistente',
     @KeyColumn   = N'SalesOrderID';
-- (expected error: "JSON column 'ColunaInexistente' does not exist in lab.JsonFunctionsOrders.")
GO
-- QUOTENAME protects aliases; it does NOT make an unvalidated JSON path trustworthy.
-- Optional cleanup:
-- DROP TABLE IF EXISTS lab.JsonFunctionsStage;
-- DROP TABLE IF EXISTS lab.JsonFunctionsOrders;
GO
