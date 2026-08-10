-- =================================================================================
-- DP-800 - PRACTICAL LAB: DATA FABRIC AND MICROSOFT FABRIC ARCHITECTURE
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SQL Server simulation of an end-to-end governed data platform:
--   SOURCES -> CONTROL CATALOG -> BRONZE -> SILVER -> GOLD -> SEMANTIC PRODUCT
--
-- The control tables model catalog, contracts, lineage, pipeline runs, source
-- integration choices, classification, and access policy. The data tables model
-- the transformation path. OneLake, Lakehouse, Warehouse, Data Factory, and
-- Power BI are platform services represented by metadata, not created by T-SQL.
--
-- THEORY: ../../../certification/12-other-topics/04-fabric-architecture.md
-- OFFICIAL REFERENCE:
-- https://learn.microsoft.com/en-us/fabric/fundamentals/data-lifecycle
-- =================================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

USE AdventureWorks2025;
GO

DROP TABLE IF EXISTS lab_fabric_gold.SemanticSalesDaily;
DROP TABLE IF EXISTS lab_fabric_gold.FactSales;
DROP TABLE IF EXISTS lab_fabric_gold.DimCustomer;
DROP TABLE IF EXISTS lab_fabric_silver.SalesQuarantine;
DROP TABLE IF EXISTS lab_fabric_silver.SalesClean;
DROP TABLE IF EXISTS lab_fabric_bronze.SalesLanding;
DROP TABLE IF EXISTS lab_fabric_control.LineageEdges;
DROP TABLE IF EXISTS lab_fabric_control.DataContracts;
DROP TABLE IF EXISTS lab_fabric_control.PipelineRuns;
DROP TABLE IF EXISTS lab_fabric_control.AccessPolicies;
DROP TABLE IF EXISTS lab_fabric_control.CatalogItems;
DROP TABLE IF EXISTS lab_fabric_control.SourceRegistry;
DROP TABLE IF EXISTS lab_fabric_source.OrderSource;
GO

IF SCHEMA_ID(N'lab_fabric_source') IS NULL EXEC(N'CREATE SCHEMA lab_fabric_source AUTHORIZATION dbo;');
IF SCHEMA_ID(N'lab_fabric_control') IS NULL EXEC(N'CREATE SCHEMA lab_fabric_control AUTHORIZATION dbo;');
IF SCHEMA_ID(N'lab_fabric_bronze') IS NULL EXEC(N'CREATE SCHEMA lab_fabric_bronze AUTHORIZATION dbo;');
IF SCHEMA_ID(N'lab_fabric_silver') IS NULL EXEC(N'CREATE SCHEMA lab_fabric_silver AUTHORIZATION dbo;');
IF SCHEMA_ID(N'lab_fabric_gold') IS NULL EXEC(N'CREATE SCHEMA lab_fabric_gold AUTHORIZATION dbo;');
GO

-- =================================================================================
-- PART 1: SOURCE REGISTRATION AND PLATFORM CONTROL PLANE
-- =================================================================================
CREATE TABLE lab_fabric_source.OrderSource (
    SourceRowID BIGINT IDENTITY(1,1) CONSTRAINT PK_FabricSource PRIMARY KEY,
    TenantID INT NOT NULL,
    OrderID NVARCHAR(50) NOT NULL,
    CustomerID INT NOT NULL,
    CustomerName NVARCHAR(150) NOT NULL,
    OrderDate DATE NOT NULL,
    ProductName NVARCHAR(150) NOT NULL,
    Quantity INT NOT NULL,
    SalesAmount DECIMAL(14,2) NOT NULL,
    ModifiedAt DATETIME2(0) NOT NULL,
    SourceSystem NVARCHAR(50) NOT NULL
);
GO

INSERT INTO lab_fabric_source.OrderSource
    (TenantID, OrderID, CustomerID, CustomerName, OrderDate, ProductName, Quantity, SalesAmount, ModifiedAt, SourceSystem)
VALUES
    (10, N'O-5001', 101, N'Contoso Brasil', '2026-08-09', N'Adventure Helmet', 2, 50.00, '2026-08-10T08:00:00', N'SQL-OLTP'),
    (10, N'O-5001', 101, N'Contoso Brasil', '2026-08-09', N'Adventure Helmet', 2, 50.00, '2026-08-10T08:05:00', N'SQL-OLTP'),
    (20, N'O-5002', 202, N'Northwind Bikes', '2026-08-09', N'Touring Tire', 1, 80.00, '2026-08-10T08:01:00', N'SQL-OLTP'),
    (10, N'O-5003', 103, N'Fabrikam Retail', '2026-08-09', N'Road Bottle', 0, 15.00, '2026-08-10T08:02:00', N'SQL-OLTP');
GO

CREATE TABLE lab_fabric_control.SourceRegistry (
    SourceName NVARCHAR(100) NOT NULL CONSTRAINT PK_FabricSourceRegistry PRIMARY KEY,
    SourceType VARCHAR(30) NOT NULL,
    IntegrationMethod VARCHAR(30) NOT NULL,
    StorageMode VARCHAR(20) NOT NULL,
    TargetItem NVARCHAR(100) NOT NULL,
    OwnerDomain NVARCHAR(100) NOT NULL
);
CREATE TABLE lab_fabric_control.CatalogItems (
    ItemName NVARCHAR(100) NOT NULL CONSTRAINT PK_FabricCatalog PRIMARY KEY,
    ItemType VARCHAR(30) NOT NULL,
    LayerName VARCHAR(20) NOT NULL,
    OwnerDomain NVARCHAR(100) NOT NULL,
    Classification VARCHAR(30) NOT NULL,
    LifecycleStatus VARCHAR(20) NOT NULL,
    IsCertified BIT NOT NULL
);
CREATE TABLE lab_fabric_control.AccessPolicies (
    ItemName NVARCHAR(100) NOT NULL,
    PrincipalName NVARCHAR(100) NOT NULL,
    AccessLevel VARCHAR(20) NOT NULL,
    RowFilter NVARCHAR(200) NULL,
    CONSTRAINT PK_FabricAccessPolicy PRIMARY KEY (ItemName, PrincipalName)
);
CREATE TABLE lab_fabric_control.DataContracts (
    ContractName NVARCHAR(100) NOT NULL CONSTRAINT PK_FabricContract PRIMARY KEY,
    Version VARCHAR(20) NOT NULL,
    RequiredColumns NVARCHAR(500) NOT NULL,
    QualityRule NVARCHAR(300) NOT NULL,
    OwnerDomain NVARCHAR(100) NOT NULL
);
CREATE TABLE lab_fabric_control.LineageEdges (
    UpstreamItem NVARCHAR(100) NOT NULL,
    DownstreamItem NVARCHAR(100) NOT NULL,
    TransformationStep NVARCHAR(200) NOT NULL,
    CONSTRAINT PK_FabricLineage PRIMARY KEY (UpstreamItem, DownstreamItem)
);
CREATE TABLE lab_fabric_control.PipelineRuns (
    RunID BIGINT IDENTITY(1,1) CONSTRAINT PK_FabricPipelineRun PRIMARY KEY,
    PipelineName NVARCHAR(100) NOT NULL,
    SourceName NVARCHAR(100) NOT NULL,
    BatchID NVARCHAR(50) NOT NULL,
    StartedAt DATETIME2(0) NOT NULL,
    FinishedAt DATETIME2(0) NULL,
    Status VARCHAR(20) NOT NULL,
    RowsRead INT NOT NULL,
    RowsPublished INT NULL,
    ErrorMessage NVARCHAR(300) NULL
);
GO

INSERT INTO lab_fabric_control.SourceRegistry
    (SourceName, SourceType, IntegrationMethod, StorageMode, TargetItem, OwnerDomain)
VALUES
    (N'SQL-OLTP Orders', 'RELATIONAL', 'CDC_OR_WATERMARK', 'COPY', N'Lakehouse Bronze', N'Commerce'),
    (N'Partner inventory files', 'FILES', 'PIPELINE', 'SHORTCUT_OR_COPY', N'Lakehouse Bronze', N'Supply');

INSERT INTO lab_fabric_control.CatalogItems
    (ItemName, ItemType, LayerName, OwnerDomain, Classification, LifecycleStatus, IsCertified)
VALUES
    (N'SQL-OLTP Orders', 'SOURCE', 'SOURCE', N'Commerce', 'CONFIDENTIAL', 'ACTIVE', 0),
    (N'Lakehouse Bronze Orders', 'LAKEHOUSE_TABLE', 'BRONZE', N'Commerce', 'CONFIDENTIAL', 'ACTIVE', 0),
    (N'Warehouse Silver Orders', 'WAREHOUSE_TABLE', 'SILVER', N'Commerce', 'CONFIDENTIAL', 'ACTIVE', 0),
    (N'Gold Sales Product', 'SEMANTIC_SOURCE', 'GOLD', N'Commerce', 'INTERNAL', 'CERTIFIED', 1),
    (N'Sales Semantic Model', 'SEMANTIC_MODEL', 'SERVING', N'Commerce', 'INTERNAL', 'CERTIFIED', 1);

INSERT INTO lab_fabric_control.AccessPolicies (ItemName, PrincipalName, AccessLevel, RowFilter)
VALUES
    (N'Gold Sales Product', N'Commerce Analysts', 'SELECT', N'TenantID IN (10, 20)'),
    (N'Gold Sales Product', N'Tenant 10 Analysts', 'SELECT', N'TenantID = 10'),
    (N'SQL-OLTP Orders', N'Pipeline Identity', 'READ', N'Approved incremental window only');

INSERT INTO lab_fabric_control.DataContracts
    (ContractName, Version, RequiredColumns, QualityRule, OwnerDomain)
VALUES
    (N'Sales Silver Contract', 'v1.0', N'TenantID,OrderID,CustomerID,OrderDate,Quantity,SalesAmount', N'Quantity > 0; SalesAmount >= 0; OrderID unique per batch', N'Commerce'),
    (N'Sales Gold Contract', 'v1.0', N'TenantID,OrderDate,CustomerID,Quantity,SalesAmount', N'Only certified Silver rows are published', N'Commerce');

INSERT INTO lab_fabric_control.LineageEdges (UpstreamItem, DownstreamItem, TransformationStep)
VALUES
    (N'SQL-OLTP Orders', N'Lakehouse Bronze Orders', N'CDC/watermark ingestion preserves source payload and batch metadata'),
    (N'Lakehouse Bronze Orders', N'Warehouse Silver Orders', N'Deduplicate, validate contract, quarantine invalid records'),
    (N'Warehouse Silver Orders', N'Gold Sales Product', N'Conform customer and publish business-ready measures'),
    (N'Gold Sales Product', N'Sales Semantic Model', N'Expose governed measures and tenant filters');
GO

-- =================================================================================
-- PART 2: INGEST INTO BRONZE AND RECORD A PIPELINE RUN
-- =================================================================================
CREATE TABLE lab_fabric_bronze.SalesLanding (
    BronzeRowID BIGINT IDENTITY(1,1) CONSTRAINT PK_FabricBronze PRIMARY KEY,
    BatchID NVARCHAR(50) NOT NULL,
    IngestedAt DATETIME2(0) NOT NULL,
    SourceRowID BIGINT NOT NULL,
    TenantID INT NOT NULL,
    OrderID NVARCHAR(50) NOT NULL,
    CustomerID INT NOT NULL,
    CustomerName NVARCHAR(150) NOT NULL,
    OrderDate DATE NOT NULL,
    ProductName NVARCHAR(150) NOT NULL,
    Quantity INT NOT NULL,
    SalesAmount DECIMAL(14,2) NOT NULL,
    SourceSystem NVARCHAR(50) NOT NULL
);

INSERT INTO lab_fabric_control.PipelineRuns
    (PipelineName, SourceName, BatchID, StartedAt, Status, RowsRead)
VALUES
    (N'pl_orders_to_bronze', N'SQL-OLTP Orders', N'batch-2026-08-10', '2026-08-10T09:00:00', 'RUNNING', 0);

INSERT INTO lab_fabric_bronze.SalesLanding
    (BatchID, IngestedAt, SourceRowID, TenantID, OrderID, CustomerID, CustomerName,
     OrderDate, ProductName, Quantity, SalesAmount, SourceSystem)
SELECT N'batch-2026-08-10', SYSUTCDATETIME(), SourceRowID, TenantID, OrderID, CustomerID, CustomerName,
       OrderDate, ProductName, Quantity, SalesAmount, SourceSystem
FROM lab_fabric_source.OrderSource;

UPDATE lab_fabric_control.PipelineRuns
SET Status = 'SUCCEEDED', FinishedAt = SYSUTCDATETIME(), RowsRead = (SELECT COUNT(*) FROM lab_fabric_bronze.SalesLanding)
WHERE PipelineName = N'pl_orders_to_bronze' AND BatchID = N'batch-2026-08-10';
GO

-- =================================================================================
-- PART 3: SILVER CONTRACT VALIDATION AND QUARANTINE
-- =================================================================================
CREATE TABLE lab_fabric_silver.SalesClean (
    SilverRowID BIGINT IDENTITY(1,1) CONSTRAINT PK_FabricSilver PRIMARY KEY,
    BatchID NVARCHAR(50) NOT NULL,
    TenantID INT NOT NULL,
    OrderID NVARCHAR(50) NOT NULL CONSTRAINT UQ_FabricSilver_Order UNIQUE,
    CustomerID INT NOT NULL,
    CustomerName NVARCHAR(150) NOT NULL,
    OrderDate DATE NOT NULL,
    ProductName NVARCHAR(150) NOT NULL,
    Quantity INT NOT NULL,
    SalesAmount DECIMAL(14,2) NOT NULL,
    CONSTRAINT CK_FabricSilver_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_FabricSilver_Amount CHECK (SalesAmount >= 0)
);
CREATE TABLE lab_fabric_silver.SalesQuarantine (
    QuarantineID BIGINT IDENTITY(1,1) CONSTRAINT PK_FabricQuarantine PRIMARY KEY,
    BatchID NVARCHAR(50) NOT NULL,
    SourceRowID BIGINT NOT NULL,
    OrderID NVARCHAR(50) NOT NULL,
    RejectionReason NVARCHAR(300) NOT NULL,
    QuarantinedAt DATETIME2(0) NOT NULL CONSTRAINT DF_FabricQuarantine_At DEFAULT SYSUTCDATETIME()
);
GO

;WITH Ranked AS (
    SELECT b.*, ROW_NUMBER() OVER (PARTITION BY b.OrderID ORDER BY b.IngestedAt DESC, b.BronzeRowID DESC) AS rn
    FROM lab_fabric_bronze.SalesLanding AS b
), Decisions AS (
    SELECT *, CASE
        WHEN rn > 1 THEN N'Duplicate OrderID in batch'
        WHEN Quantity <= 0 THEN N'Quantity must be greater than zero'
        WHEN SalesAmount < 0 THEN N'SalesAmount must be zero or greater'
    END AS RejectionReason
    FROM Ranked
)
INSERT INTO lab_fabric_silver.SalesQuarantine (BatchID, SourceRowID, OrderID, RejectionReason)
SELECT BatchID, SourceRowID, OrderID, RejectionReason
FROM Decisions WHERE RejectionReason IS NOT NULL;

;WITH Ranked AS (
    SELECT b.*, ROW_NUMBER() OVER (PARTITION BY b.OrderID ORDER BY b.IngestedAt DESC, b.BronzeRowID DESC) AS rn
    FROM lab_fabric_bronze.SalesLanding AS b
)
INSERT INTO lab_fabric_silver.SalesClean
    (BatchID, TenantID, OrderID, CustomerID, CustomerName, OrderDate, ProductName, Quantity, SalesAmount)
SELECT BatchID, TenantID, OrderID, CustomerID, CustomerName, OrderDate, ProductName, Quantity, SalesAmount
FROM Ranked
WHERE rn = 1 AND Quantity > 0 AND SalesAmount >= 0;
GO

-- =================================================================================
-- PART 4: GOLD AND SEMANTIC SERVING PRODUCT
-- =================================================================================
CREATE TABLE lab_fabric_gold.DimCustomer (
    CustomerKey INT IDENTITY(1,1) CONSTRAINT PK_FabricDimCustomer PRIMARY KEY,
    TenantID INT NOT NULL,
    CustomerID INT NOT NULL,
    CustomerName NVARCHAR(150) NOT NULL,
    CONSTRAINT UQ_FabricDimCustomer UNIQUE (TenantID, CustomerID)
);
CREATE TABLE lab_fabric_gold.FactSales (
    TenantID INT NOT NULL,
    OrderDate DATE NOT NULL,
    CustomerKey INT NOT NULL CONSTRAINT FK_FabricFact_Customer REFERENCES lab_fabric_gold.DimCustomer(CustomerKey),
    OrderID NVARCHAR(50) NOT NULL CONSTRAINT UQ_FabricFact_Order UNIQUE,
    Quantity INT NOT NULL,
    SalesAmount DECIMAL(14,2) NOT NULL,
    CONSTRAINT PK_FabricFactSales PRIMARY KEY (TenantID, OrderID)
);
CREATE TABLE lab_fabric_gold.SemanticSalesDaily (
    TenantID INT NOT NULL,
    OrderDate DATE NOT NULL,
    UnitsSold INT NOT NULL,
    SalesAmount DECIMAL(14,2) NOT NULL,
    IsCertified BIT NOT NULL,
    CONSTRAINT PK_FabricSemanticDaily PRIMARY KEY (TenantID, OrderDate)
);
GO

INSERT INTO lab_fabric_gold.DimCustomer (TenantID, CustomerID, CustomerName)
SELECT DISTINCT TenantID, CustomerID, CustomerName
FROM lab_fabric_silver.SalesClean;

INSERT INTO lab_fabric_gold.FactSales
    (TenantID, OrderDate, CustomerKey, OrderID, Quantity, SalesAmount)
SELECT s.TenantID, s.OrderDate, c.CustomerKey, s.OrderID, s.Quantity, s.SalesAmount
FROM lab_fabric_silver.SalesClean AS s
JOIN lab_fabric_gold.DimCustomer AS c ON c.TenantID = s.TenantID AND c.CustomerID = s.CustomerID;

INSERT INTO lab_fabric_gold.SemanticSalesDaily (TenantID, OrderDate, UnitsSold, SalesAmount, IsCertified)
SELECT TenantID, OrderDate, SUM(Quantity), SUM(SalesAmount), 1
FROM lab_fabric_gold.FactSales
GROUP BY TenantID, OrderDate;
GO

SELECT TenantID, OrderDate, UnitsSold, SalesAmount
FROM lab_fabric_gold.SemanticSalesDaily
WHERE TenantID = 10;
GO

-- =================================================================================
-- PART 5: LINEAGE, ACCESS, COST, AND PROMOTION GATES
-- =================================================================================
UPDATE lab_fabric_control.PipelineRuns
SET RowsPublished = (SELECT COUNT(*) FROM lab_fabric_silver.SalesClean)
WHERE PipelineName = N'pl_orders_to_bronze' AND BatchID = N'batch-2026-08-10';

SELECT c.ItemName, c.ItemType, c.LayerName, c.OwnerDomain, c.Classification,
       c.LifecycleStatus, c.IsCertified
FROM lab_fabric_control.CatalogItems AS c
ORDER BY c.LayerName, c.ItemName;

SELECT UpstreamItem, DownstreamItem, TransformationStep
FROM lab_fabric_control.LineageEdges
ORDER BY UpstreamItem, DownstreamItem;

SELECT ItemName, PrincipalName, AccessLevel, RowFilter
FROM lab_fabric_control.AccessPolicies
WHERE ItemName = N'Gold Sales Product';
GO

IF EXISTS (SELECT 1 FROM lab_fabric_silver.SalesClean WHERE Quantity <= 0 OR SalesAmount < 0)
    THROW 51040, 'Silver contract quality gate failed.', 1;
IF NOT EXISTS (SELECT 1 FROM lab_fabric_control.LineageEdges WHERE UpstreamItem = N'Gold Sales Product' AND DownstreamItem = N'Sales Semantic Model')
    THROW 51041, 'Serving lineage gate failed.', 1;
IF NOT EXISTS (SELECT 1 FROM lab_fabric_control.CatalogItems WHERE ItemName = N'Sales Semantic Model' AND IsCertified = 1)
    THROW 51042, 'Semantic model certification gate failed.', 1;
IF EXISTS (SELECT 1 FROM lab_fabric_control.PipelineRuns WHERE Status <> 'SUCCEEDED')
    THROW 51043, 'Pipeline operational gate failed.', 1;

SELECT N'PASS' AS FabricArchitectureGate,
       N'Catalog, contract, lineage, access, pipeline, and serving checks passed.' AS Result;
GO

-- NEXT STEP: Review the theory at
-- ../../../certification/12-other-topics/04-fabric-architecture.md
