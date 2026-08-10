-- =================================================================================
-- DP-800 - LABORATÓRIO PRÁTICO: ARQUITETURA MEDALHÃO NO SQL SERVER
-- Banco de dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- Este script simula no SQL Server uma carga de trabalho medalhão do Fabric:
--   BRONZE = ingestão fiel à origem e metadados para replay
--   SILVER = validação, deduplicação, conformidade e quarentena
--   GOLD   = dimensões, fatos, verificações de qualidade e produto de dados
--
-- O SQL Server não cria lakehouses do OneLake nem tabelas Delta com este script.
-- Use o resultado para entender os limites de transformação e governança que um
-- pipeline do Fabric, Dataflow Gen2, notebook ou materialized lake view executaria.
--
-- REFERÊNCIA TEÓRICA:
-- ../../../certification/12-other-topics/02-medallion-architecture-fabric.md
-- REFERÊNCIA OFICIAL:
-- https://learn.microsoft.com/pt-br/fabric/onelake/onelake-medallion-lakehouse-architecture
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

DROP TABLE IF EXISTS lab_medallion_gold.FactSales;
DROP TABLE IF EXISTS lab_medallion_gold.DimProduct;
DROP TABLE IF EXISTS lab_medallion_gold.DimDate;
DROP TABLE IF EXISTS lab_medallion_gold.DataProductCatalog;
DROP TABLE IF EXISTS lab_medallion_silver.SalesConformed;
DROP TABLE IF EXISTS lab_medallion_silver.SalesQuarantine;
DROP TABLE IF EXISTS lab_medallion_silver.SalesClean;
DROP TABLE IF EXISTS lab_medallion_bronze.SalesEvents;
GO

IF SCHEMA_ID(N'lab_medallion_bronze') IS NULL
    EXEC(N'CREATE SCHEMA lab_medallion_bronze AUTHORIZATION dbo;');
IF SCHEMA_ID(N'lab_medallion_silver') IS NULL
    EXEC(N'CREATE SCHEMA lab_medallion_silver AUTHORIZATION dbo;');
IF SCHEMA_ID(N'lab_medallion_gold') IS NULL
    EXEC(N'CREATE SCHEMA lab_medallion_gold AUTHORIZATION dbo;');
GO

-- =================================================================================
-- PARTE 1: BRONZE - PRESERVAR A ORIGEM E PERMITIR REPLAY
-- =================================================================================
CREATE TABLE lab_medallion_bronze.SalesEvents (
    BronzeEventID BIGINT IDENTITY(1,1) CONSTRAINT PK_MedallionBronze PRIMARY KEY,
    SourceEventID NVARCHAR(50) NOT NULL,
    SourceSystem NVARCHAR(50) NOT NULL,
    BatchID NVARCHAR(50) NOT NULL,
    IngestedAt DATETIME2(0) NOT NULL CONSTRAINT DF_MedallionBronze_IngestedAt DEFAULT SYSUTCDATETIME(),
    Payload NVARCHAR(MAX) NOT NULL,
    IsReplay BIT NOT NULL CONSTRAINT DF_MedallionBronze_IsReplay DEFAULT 0,
    CONSTRAINT CK_MedallionBronze_Json CHECK (ISJSON(Payload) = 1)
);
GO

INSERT INTO lab_medallion_bronze.SalesEvents
    (SourceEventID, SourceSystem, BatchID, IngestedAt, Payload, IsReplay)
VALUES
    (N'evt-1001', N'web-store', N'batch-2026-08-10-a', '2026-08-10T09:00:00',
     N'{"sale_id":"evt-1001","sale_date":"2026-08-09","customer_id":101,"product_id":501,"quantity":2,"unit_price":25.00}', 0),
    (N'evt-1001', N'web-store', N'batch-2026-08-10-b', '2026-08-10T09:05:00',
     N'{"sale_id":"evt-1001","sale_date":"2026-08-09","customer_id":101,"product_id":501,"quantity":2,"unit_price":25.00}', 1),
    (N'evt-1002', N'web-store', N'batch-2026-08-10-a', '2026-08-10T09:01:00',
     N'{"sale_id":"evt-1002","sale_date":"2026-08-09","customer_id":102,"product_id":502,"quantity":1,"unit_price":80.00}', 0),
    (N'evt-1003', N'web-store', N'batch-2026-08-10-a', '2026-08-10T09:02:00',
     N'{"sale_id":"evt-1003","sale_date":"2026-08-09","customer_id":103,"product_id":503,"quantity":0,"unit_price":15.00}', 0),
    (N'evt-1004', N'web-store', N'batch-2026-08-10-a', '2026-08-10T09:03:00',
     N'{"sale_id":"evt-1004","sale_date":"2026-08-09","customer_id":104,"product_id":504,"quantity":1,"unit_price":-5.00}', 0);
GO

SELECT SourceEventID, SourceSystem, BatchID, IngestedAt, IsReplay, Payload
FROM lab_medallion_bronze.SalesEvents
ORDER BY BronzeEventID;
GO

-- =================================================================================
-- PARTE 2: SILVER - VALIDAR, DEDUPLICAR, CONFORMAR E COLOCAR EM QUARENTENA
-- =================================================================================
CREATE TABLE lab_medallion_silver.SalesClean (
    SilverSaleID BIGINT IDENTITY(1,1) CONSTRAINT PK_MedallionSilverClean PRIMARY KEY,
    SourceEventID NVARCHAR(50) NOT NULL CONSTRAINT UQ_MedallionSilver_SourceEvent UNIQUE,
    SaleDate DATE NOT NULL,
    CustomerID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL,
    Amount AS CONVERT(DECIMAL(14,2), Quantity * UnitPrice) PERSISTED,
    SourceBronzeEventID BIGINT NOT NULL,
    ConformedAt DATETIME2(0) NOT NULL CONSTRAINT DF_MedallionSilver_ConformedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_MedallionSilver_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_MedallionSilver_UnitPrice CHECK (UnitPrice >= 0)
);

CREATE TABLE lab_medallion_silver.SalesQuarantine (
    QuarantineID BIGINT IDENTITY(1,1) CONSTRAINT PK_MedallionQuarantine PRIMARY KEY,
    SourceEventID NVARCHAR(50) NOT NULL,
    BronzeEventID BIGINT NOT NULL,
    Payload NVARCHAR(MAX) NOT NULL,
    RejectionReason NVARCHAR(300) NOT NULL,
    QuarantinedAt DATETIME2(0) NOT NULL CONSTRAINT DF_MedallionQuarantine_At DEFAULT SYSUTCDATETIME(),
    IsRemediated BIT NOT NULL CONSTRAINT DF_MedallionQuarantine_Remediated DEFAULT 0
);
GO

;WITH Parsed AS (
    SELECT b.BronzeEventID, b.SourceEventID, b.Payload,
        TRY_CONVERT(DATE, JSON_VALUE(b.Payload, '$.sale_date')) AS SaleDate,
        TRY_CONVERT(INT, JSON_VALUE(b.Payload, '$.customer_id')) AS CustomerID,
        TRY_CONVERT(INT, JSON_VALUE(b.Payload, '$.product_id')) AS ProductID,
        TRY_CONVERT(INT, JSON_VALUE(b.Payload, '$.quantity')) AS Quantity,
        TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(b.Payload, '$.unit_price')) AS UnitPrice,
        ROW_NUMBER() OVER (PARTITION BY b.SourceEventID ORDER BY b.IngestedAt, b.BronzeEventID) AS EventVersion
    FROM lab_medallion_bronze.SalesEvents AS b
), Validated AS (
    SELECT *, CASE
        WHEN EventVersion > 1 THEN N'Evento de origem duplicado; somente a primeira chegada foi mantida'
        WHEN SaleDate IS NULL THEN N'sale_date ausente ou inválida'
        WHEN CustomerID IS NULL THEN N'customer_id ausente ou inválido'
        WHEN ProductID IS NULL THEN N'product_id ausente ou inválido'
        WHEN Quantity IS NULL OR Quantity <= 0 THEN N'quantity deve ser maior que zero'
        WHEN UnitPrice IS NULL OR UnitPrice < 0 THEN N'unit_price deve ser zero ou maior'
    END AS RejectionReason
    FROM Parsed
)
INSERT INTO lab_medallion_silver.SalesQuarantine
    (SourceEventID, BronzeEventID, Payload, RejectionReason)
SELECT SourceEventID, BronzeEventID, Payload, RejectionReason
FROM Validated
WHERE RejectionReason IS NOT NULL;

;WITH Parsed AS (
    SELECT b.BronzeEventID, b.SourceEventID,
        TRY_CONVERT(DATE, JSON_VALUE(b.Payload, '$.sale_date')) AS SaleDate,
        TRY_CONVERT(INT, JSON_VALUE(b.Payload, '$.customer_id')) AS CustomerID,
        TRY_CONVERT(INT, JSON_VALUE(b.Payload, '$.product_id')) AS ProductID,
        TRY_CONVERT(INT, JSON_VALUE(b.Payload, '$.quantity')) AS Quantity,
        TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(b.Payload, '$.unit_price')) AS UnitPrice,
        ROW_NUMBER() OVER (PARTITION BY b.SourceEventID ORDER BY b.IngestedAt, b.BronzeEventID) AS EventVersion
    FROM lab_medallion_bronze.SalesEvents AS b
)
INSERT INTO lab_medallion_silver.SalesClean
    (SourceEventID, SaleDate, CustomerID, ProductID, Quantity, UnitPrice, SourceBronzeEventID)
SELECT SourceEventID, SaleDate, CustomerID, ProductID, Quantity, UnitPrice, BronzeEventID
FROM Parsed
WHERE EventVersion = 1 AND SaleDate IS NOT NULL AND CustomerID IS NOT NULL
  AND ProductID IS NOT NULL AND Quantity > 0 AND UnitPrice >= 0;
GO

CREATE TABLE lab_medallion_silver.SalesConformed (
    SaleDate DATE NOT NULL,
    CustomerID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL,
    Amount DECIMAL(14,2) NOT NULL,
    CONSTRAINT PK_MedallionSilverConformed PRIMARY KEY (SaleDate, CustomerID, ProductID)
);

INSERT INTO lab_medallion_silver.SalesConformed
    (SaleDate, CustomerID, ProductID, Quantity, UnitPrice, Amount)
SELECT SaleDate, CustomerID, ProductID, Quantity, UnitPrice, Amount
FROM lab_medallion_silver.SalesClean;
GO

SELECT N'Linhas limpas' AS CheckName, COUNT_BIG(*) AS CheckValue
FROM lab_medallion_silver.SalesClean
UNION ALL
SELECT N'Linhas em quarentena', COUNT_BIG(*)
FROM lab_medallion_silver.SalesQuarantine;

SELECT SourceEventID, RejectionReason, Payload
FROM lab_medallion_silver.SalesQuarantine
ORDER BY QuarantineID;
GO

-- =================================================================================
-- PARTE 3: GOLD - PUBLICAR UM PRODUTO DE DADOS PRONTO PARA O NEGÓCIO
-- =================================================================================
CREATE TABLE lab_medallion_gold.DimDate (
    DateKey INT NOT NULL CONSTRAINT PK_MedallionDimDate PRIMARY KEY,
    CalendarDate DATE NOT NULL CONSTRAINT UQ_MedallionDimDate_Date UNIQUE,
    CalendarYear SMALLINT NOT NULL,
    CalendarMonth TINYINT NOT NULL
);

CREATE TABLE lab_medallion_gold.DimProduct (
    ProductKey INT IDENTITY(1,1) CONSTRAINT PK_MedallionDimProduct PRIMARY KEY,
    ProductID INT NOT NULL CONSTRAINT UQ_MedallionDimProduct_Product UNIQUE,
    ProductName NVARCHAR(100) NOT NULL,
    ProductCategory NVARCHAR(100) NOT NULL
);

CREATE TABLE lab_medallion_gold.FactSales (
    DateKey INT NOT NULL CONSTRAINT FK_MedallionFact_Date REFERENCES lab_medallion_gold.DimDate(DateKey),
    ProductKey INT NOT NULL CONSTRAINT FK_MedallionFact_Product REFERENCES lab_medallion_gold.DimProduct(ProductKey),
    CustomerID INT NOT NULL,
    Quantity INT NOT NULL,
    SalesAmount DECIMAL(14,2) NOT NULL,
    CONSTRAINT PK_MedallionFactSales PRIMARY KEY (DateKey, ProductKey, CustomerID),
    CONSTRAINT CK_MedallionFactSales_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_MedallionFactSales_Amount CHECK (SalesAmount >= 0)
);

CREATE TABLE lab_medallion_gold.DataProductCatalog (
    DataProductName NVARCHAR(100) NOT NULL CONSTRAINT PK_MedallionCatalog PRIMARY KEY,
    OwnerDomain NVARCHAR(100) NOT NULL,
    LayerName VARCHAR(10) NOT NULL,
    RefreshPolicy NVARCHAR(100) NOT NULL,
    IsCertified BIT NOT NULL,
    ContractVersion VARCHAR(20) NOT NULL
);
GO

INSERT INTO lab_medallion_gold.DimDate (DateKey, CalendarDate, CalendarYear, CalendarMonth)
SELECT DISTINCT CONVERT(INT, CONVERT(CHAR(8), SaleDate, 112)), SaleDate,
       DATEPART(YEAR, SaleDate), DATEPART(MONTH, SaleDate)
FROM lab_medallion_silver.SalesConformed;

INSERT INTO lab_medallion_gold.DimProduct (ProductID, ProductName, ProductCategory)
VALUES (501, N'Capacete Adventure', N'Componentes'),
       (502, N'Pneu Touring', N'Componentes');

INSERT INTO lab_medallion_gold.FactSales
    (DateKey, ProductKey, CustomerID, Quantity, SalesAmount)
SELECT CONVERT(INT, CONVERT(CHAR(8), s.SaleDate, 112)), p.ProductKey,
       s.CustomerID, s.Quantity, s.Amount
FROM lab_medallion_silver.SalesConformed AS s
JOIN lab_medallion_gold.DimProduct AS p ON p.ProductID = s.ProductID;

INSERT INTO lab_medallion_gold.DataProductCatalog
    (DataProductName, OwnerDomain, LayerName, RefreshPolicy, IsCertified, ContractVersion)
VALUES (N'Vendas diárias', N'Comércio', 'GOLD', N'Diária após as verificações de qualidade Silver', 1, 'v1.0');
GO

SELECT d.CalendarDate, p.ProductName, SUM(f.Quantity) AS UnitsSold,
       SUM(f.SalesAmount) AS SalesAmount
FROM lab_medallion_gold.FactSales AS f
JOIN lab_medallion_gold.DimDate AS d ON d.DateKey = f.DateKey
JOIN lab_medallion_gold.DimProduct AS p ON p.ProductKey = f.ProductKey
GROUP BY d.CalendarDate, p.ProductName
ORDER BY d.CalendarDate, p.ProductName;
GO

-- =================================================================================
-- PARTE 4: QUALIDADE, LINHAGEM E GATES DE PROMOÇÃO
-- =================================================================================
IF EXISTS (SELECT 1 FROM lab_medallion_silver.SalesClean WHERE Quantity <= 0 OR UnitPrice < 0)
    THROW 51020, 'Gate de qualidade Silver falhou.', 1;

IF EXISTS (
    SELECT SourceEventID FROM lab_medallion_silver.SalesClean
    GROUP BY SourceEventID HAVING COUNT(*) > 1
)
    THROW 51021, 'Gate de deduplicação Silver falhou.', 1;

IF NOT EXISTS (
    SELECT 1 FROM lab_medallion_gold.DataProductCatalog
    WHERE DataProductName = N'Vendas diárias' AND LayerName = 'GOLD' AND IsCertified = 1
)
    THROW 51022, 'Gate de certificação Gold falhou.', 1;

SELECT N'PASSOU' AS PromotionGate,
       N'As verificações de qualidade e certificação Bronze -> Silver -> Gold passaram.' AS Result;

SELECT N'BRONZE' AS LayerName, N'lab_medallion_bronze.SalesEvents' AS ObjectName,
       N'Payload bruto, ID da origem, lote, ingestão e replay' AS LineageBoundary
UNION ALL
SELECT N'SILVER', N'lab_medallion_silver.SalesClean', N'Registros interpretados, validados e deduplicados'
UNION ALL
SELECT N'SILVER', N'lab_medallion_silver.SalesQuarantine', N'Registros inválidos ou duplicados preservados para correção'
UNION ALL
SELECT N'GOLD', N'lab_medallion_gold.FactSales', N'Produto de vendas certificado e pronto para consumo';
GO

-- PRÓXIMO PASSO: revise a teoria em
-- ../../../certification/12-other-topics/02-medallion-architecture-fabric.md
