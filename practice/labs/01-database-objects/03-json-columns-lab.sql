-- =============================================================================
-- DP-800 - HANDS-ON LAB: JSON COLUMNS, INDEXES, AND PERFORMANCE
-- Prerequisite: AdventureWorks2025 restored. This script changes only lab objects.
-- Enable the Actual Execution Plan in SSMS/Azure Data Studio before Parts 4-6.
-- Goal: decide which attributes stay relational and when a JSON attribute deserves
-- an indexable projection. JSON parsing and serialization are covered in the JSON Functions lab.
-- =============================================================================
-- THEORY REFERENCE: ../../../certification/01-database-objects/03-json-columns.md
--    Open the theory guide alongside this lab for conceptual context.
-- =============================================================================

USE AdventureWorks2025;
GO

-- Required for creating and using indexes on computed columns.
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

DROP TABLE IF EXISTS lab.JsonColumnsOrders;
DROP TABLE IF EXISTS lab.JsonColumnsNative;
GO

-- PART 1: MODEL REAL ORDER DATA AS RELATIONAL COLUMNS PLUS A FLEXIBLE DOCUMENT
-- Keys, date, and TotalDue remain relational. Shipping, territory, and items are
-- document-shaped attributes derived from real AdventureWorks orders and products.
CREATE TABLE lab.JsonColumnsOrders
(
    SalesOrderID int NOT NULL CONSTRAINT PK_JsonColumnsOrders PRIMARY KEY,
    OrderDate datetime NOT NULL,
    CustomerID int NOT NULL,
    TotalDue money NOT NULL,
    OrderDocument nvarchar(max) NOT NULL,
    CONSTRAINT CK_JsonColumnsOrders_Document CHECK (ISJSON(OrderDocument) = 1)
);
GO

INSERT INTO lab.JsonColumnsOrders
    (SalesOrderID, OrderDate, CustomerID, TotalDue, OrderDocument)
SELECT TOP (5000)
    h.SalesOrderID, h.OrderDate, h.CustomerID, h.TotalDue,
    (
        SELECT
            st.Name AS [territory.name],
            cr.CountryRegionCode AS [territory.countryCode],
            a.City AS [shipping.city],
            sp.StateProvinceCode AS [shipping.stateProvince],
            JSON_QUERY((
                SELECT d.SalesOrderDetailID AS [lineId],
                       p.ProductNumber AS [product.number],
                       p.Name AS [product.name],
                       d.OrderQty AS [quantity], d.UnitPrice AS [unitPrice]
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
JOIN Person.StateProvince AS sp ON sp.StateProvinceID = a.StateProvinceID
JOIN Person.CountryRegion AS cr ON cr.CountryRegionCode = sp.CountryRegionCode
ORDER BY h.SalesOrderID;
GO

SELECT COUNT(*) AS Orders, MAX(JSON_VALUE(OrderDocument, '$.territory.name')) AS ExampleTerritory
FROM lab.JsonColumnsOrders;
GO

-- Inspect a real document. Country is duplicated here only for the experiment;
-- promote it to a relational column when joins, security, domain validation, or
-- frequent filtering require the database to govern the value directly.
SELECT TOP (1) SalesOrderID, OrderDate, CustomerID, TotalDue, OrderDocument
FROM lab.JsonColumnsOrders ORDER BY SalesOrderID;
GO

-- PART 2: INTEGRITY AND MODELING BOUNDARIES
-- ISJSON proves JSON syntax, not that required business properties exist or have
-- the right type/domain.
BEGIN TRY
    INSERT INTO lab.JsonColumnsOrders
        (SalesOrderID, OrderDate, CustomerID, TotalDue, OrderDocument)
    VALUES (-1, GETDATE(), -1, 0, N'{"shipping":');
END TRY
BEGIN CATCH
    PRINT N'Expected CHECK error: ' + ERROR_MESSAGE();
END CATCH;
GO
-- A CHECK permits NULL when the column itself is nullable. This lab uses NOT NULL.
-- For an optional payload use: CHECK (Payload IS NULL OR ISJSON(Payload) = 1).
-- SQL Server 2022+ can require an object with ISJSON(Payload, OBJECT).

-- Compare a relational measure with a flexible JSON attribute. Do not move
-- frequently joined keys or additive measures into a document just to use JSON.
SELECT TOP (20)
    SalesOrderID, CustomerID, TotalDue,
    JSON_VALUE(OrderDocument, '$.territory.name') AS Territory,
    JSON_VALUE(OrderDocument, '$.shipping.city') AS ShipCity
FROM lab.JsonColumnsOrders
ORDER BY TotalDue DESC;
GO

-- PART 3: BASELINE - JSON_VALUE HAS NO ACCESS PATH YET
-- Capture logical reads, CPU, duration, actual/estimated rows, and operators.
SET STATISTICS IO, TIME ON;

SELECT SalesOrderID, CustomerID, TotalDue
FROM lab.JsonColumnsOrders
WHERE JSON_VALUE(OrderDocument, '$.territory.countryCode') = N'US';

SET STATISTICS IO, TIME OFF;
GO
-- Diagnosis: symptom = reads and a Scan; hypothesis = no access path exists for
-- the JSON expression. Part 4 applies an indexable computed projection. Risk: for
-- a low-selectivity value, a Scan can still be the correct plan; do not force seeks.

-- PART 4: SARGABILITY THROUGH THE SAME INDEXED EXPRESSION
-- A small, explicit type avoids an nvarchar(4000) index key. The query below
-- repeats this exact CONVERT + JSON_VALUE expression so SQL Server can match it.
-- JSON_VALUE returns nvarchar(4000); choose a narrower type from the real domain.
ALTER TABLE lab.JsonColumnsOrders
ADD CountryCode AS CONVERT(nvarchar(3),
    JSON_VALUE(OrderDocument, '$.territory.countryCode'));
GO

CREATE INDEX IX_JsonColumnsOrders_CountryCode
ON lab.JsonColumnsOrders (CountryCode);
GO

SET STATISTICS IO, TIME ON;

SELECT SalesOrderID, CustomerID, TotalDue
FROM lab.JsonColumnsOrders
WHERE CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.territory.countryCode')) = N'US';

SET STATISTICS IO, TIME OFF;
GO
-- Diagnosis: an index can find rows but still need repeated Key Lookups for columns
-- outside it. Part 5 compares a covering index. Risk: INCLUDE increases write cost.

-- Inspect the plan: a Key Lookup can be reasonable for few rows. Do not force
-- an index or assume a seek; compare actual rows, logical reads, CPU, and time.
-- These variants can prevent an expression match or reduce seek usefulness:
SELECT SalesOrderID
FROM lab.JsonColumnsOrders
WHERE UPPER(JSON_VALUE(OrderDocument, '$.territory.countryCode')) = N'US';

SELECT SalesOrderID
FROM lab.JsonColumnsOrders
WHERE CountryCode LIKE N'%S';
GO

-- PART 5: COVERING IS A MEASURED TRADE-OFF
DROP INDEX IX_JsonColumnsOrders_CountryCode ON lab.JsonColumnsOrders;
GO

CREATE INDEX IX_JsonColumnsOrders_CountryCode
ON lab.JsonColumnsOrders (CountryCode)
INCLUDE (CustomerID, TotalDue);
GO

SET STATISTICS IO, TIME ON;

SELECT SalesOrderID, CustomerID, TotalDue
FROM lab.JsonColumnsOrders
WHERE CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.territory.countryCode')) = N'US';

SET STATISTICS IO, TIME OFF;
GO
-- A covering index does not cover the entire document. Do not include nvarchar(max)
-- merely to remove a Lookup without measuring its write and storage impact.
SELECT SalesOrderID, CustomerID, TotalDue, OrderDocument
FROM lab.JsonColumnsOrders WHERE CountryCode = N'US';
GO

-- PART 6: EXECUTABLE DIAGNOSTIC CASES
-- Case A — measure selectivity before adding indexes. Frequent values may justify
-- a Scan even when an index exists.
SELECT CountryCode, COUNT(*) AS Orders,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS decimal(5, 2)) AS PercentOfTotal
FROM lab.JsonColumnsOrders GROUP BY CountryCode ORDER BY Orders DESC;
GO

-- Case B — residual predicate versus a composite index. Before the new index,
-- inspect rows read versus returned and the residual StateProvinceCode predicate.
ALTER TABLE lab.JsonColumnsOrders
ADD StateProvinceCode AS CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.shipping.stateProvince'));
GO
SET STATISTICS IO, TIME ON;
SELECT SalesOrderID, CustomerID, TotalDue FROM lab.JsonColumnsOrders
WHERE CountryCode = N'US'
  AND CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.shipping.stateProvince')) = N'WA';
SET STATISTICS IO, TIME OFF;
GO
CREATE INDEX IX_JsonColumnsOrders_CountryCode_StateProvinceCode
ON lab.JsonColumnsOrders (CountryCode, StateProvinceCode) INCLUDE (CustomerID, TotalDue);
GO
SET STATISTICS IO, TIME ON;
SELECT SalesOrderID, CustomerID, TotalDue FROM lab.JsonColumnsOrders
WHERE CountryCode = N'US'
  AND CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.shipping.stateProvince')) = N'WA';
SET STATISTICS IO, TIME OFF;
GO
-- Diagnosis: the composite index gives both filters an access path. If estimates
-- differ sharply from actual rows, review statistics, types, and selectivity first.
-- Sort/Hash spills require checking memory grants and reducing rows early.

-- Case C — wide projection. The document is deliberately not covered by the index.
SET STATISTICS IO, TIME ON;
SELECT SalesOrderID, CustomerID, TotalDue, OrderDocument FROM lab.JsonColumnsOrders
WHERE CountryCode = N'US' AND StateProvinceCode = N'WA';
SET STATISTICS IO, TIME OFF;
GO
-- Diagnosis: compare reads/Lookup with Part 5. Prefer a narrower result, on-demand
-- document retrieval, or relational modeling over blindly indexing a large payload.
-- A filtered index cannot be created directly on a computed column; materialize a
-- physical value during load or model the attribute relationally when necessary.

-- SQL Server 2025 on-premises: native json type and JSON index. Earlier versions
-- skip this test without blocking the nvarchar(max) exercises above.
DECLARE @NativeMajorVersion int = TRY_CONVERT(int, SERVERPROPERTY(N'ProductMajorVersion'));
DECLARE @NativeCompatibility int = CONVERT(int, DATABASEPROPERTYEX(DB_NAME(), N'CompatibilityLevel'));
IF @NativeMajorVersion >= 17 AND @NativeCompatibility >= 170
BEGIN
    EXEC sys.sp_executesql N'
        CREATE TABLE lab.JsonColumnsNative
        (EventId int NOT NULL PRIMARY KEY CLUSTERED, Payload json NOT NULL);
        INSERT INTO lab.JsonColumnsNative (EventId, Payload)
        SELECT SalesOrderID, OrderDocument FROM lab.JsonColumnsOrders;
        CREATE JSON INDEX IX_JsonColumnsNative_Payload
            ON lab.JsonColumnsNative (Payload) FOR (''$.territory.countryCode'');
        SET STATISTICS IO, TIME ON;
        SELECT EventId FROM lab.JsonColumnsNative
        WHERE JSON_VALUE(Payload, ''$.territory.countryCode'') = N''US'';
        SET STATISTICS IO, TIME OFF;';
    PRINT N'Native json and JSON index test ran on SQL Server 2025 on-premises.';
END
ELSE
    PRINT N'Native json/JSON index test skipped: SQL Server 2025 (17.x) and compatibility 170 are required.';
GO

-- Manual equivalent retained for study:
-- CREATE TABLE lab.JsonColumnsNative
-- (EventId int NOT NULL PRIMARY KEY CLUSTERED, Payload json NOT NULL);
-- CREATE JSON INDEX IX_JsonColumnsNative_Payload
--     ON lab.JsonColumnsNative (Payload) FOR ('$.territory.countryCode');

-- Optional cleanup:
-- DROP TABLE IF EXISTS lab.JsonColumnsOrders;
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/01-database-objects/03-json-columns.md
-- =================================================================================================
