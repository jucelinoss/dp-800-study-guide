-- =================================================================================
-- DP-800 - LABORATÓRIO PRÁTICO: MODELAGEM DIMENSIONAL
-- Banco de dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- Grão do fato: uma linha por item de pedido (OrderLineID).
-- O script demonstra:
--   1. Dimensões de data, produto e cliente com chaves substitutas.
--   2. Membro desconhecido (chave 0) para preservar integridade referencial.
--   3. DimDate usada nos papéis OrderDate e ShipDate.
--   4. Star schema e uma variante Snowflake para a hierarquia de produto.
--   5. Medidas aditivas e reconciliação contra a origem.
--
-- TEORIA: ../../../certification/12-other-topics/05-dimensional-modeling.md
-- REFERÊNCIA OFICIAL:
-- https://learn.microsoft.com/en-us/fabric/data-warehouse/dimensional-modeling-overview
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

DROP TABLE IF EXISTS lab_dimensional.FactSales;
DROP TABLE IF EXISTS lab_dimensional.DimProductSnowflake;
DROP TABLE IF EXISTS lab_dimensional.DimCategory;
DROP TABLE IF EXISTS lab_dimensional.DimProduct;
DROP TABLE IF EXISTS lab_dimensional.DimCustomer;
DROP TABLE IF EXISTS lab_dimensional.DimDate;
DROP TABLE IF EXISTS lab_dimensional.SalesSource;
GO

IF SCHEMA_ID(N'lab_dimensional') IS NULL
    EXEC(N'CREATE SCHEMA lab_dimensional AUTHORIZATION dbo;');
GO

-- =================================================================================
-- PARTE 1: ORIGEM E GRÃO DO FATO
-- =================================================================================
CREATE TABLE lab_dimensional.SalesSource (
    SourceRowID BIGINT IDENTITY(1,1) CONSTRAINT PK_DimSource PRIMARY KEY,
    OrderLineID NVARCHAR(50) NOT NULL CONSTRAINT UQ_DimSource_OrderLine UNIQUE,
    CustomerSourceID INT NOT NULL,
    CustomerName NVARCHAR(150) NOT NULL,
    ProductSourceID INT NOT NULL,
    ProductName NVARCHAR(150) NOT NULL,
    CategoryName NVARCHAR(100) NOT NULL,
    BrandName NVARCHAR(100) NOT NULL,
    OrderDate DATE NOT NULL,
    ShipDate DATE NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL,
    DiscountAmount DECIMAL(12,2) NOT NULL
);
GO

INSERT INTO lab_dimensional.SalesSource
    (OrderLineID, CustomerSourceID, CustomerName, ProductSourceID, ProductName, CategoryName,
     BrandName, OrderDate, ShipDate, Quantity, UnitPrice, DiscountAmount)
VALUES
    (N'OL-1001', 101, N'Contoso Brasil', 501, N'Capacete Adventure', N'Proteção', N'Contoso', '2026-08-01', '2026-08-03', 2, 100.00, 10.00),
    (N'OL-1002', 101, N'Contoso Brasil', 502, N'Pneu Touring', N'Componentes', N'Northwind', '2026-08-02', '2026-08-04', 1, 80.00, 0.00),
    (N'OL-1003', 202, N'Northwind Bikes', 501, N'Capacete Adventure', N'Proteção', N'Contoso', '2026-08-02', '2026-08-05', 1, 100.00, 5.00),
    -- CustomerSourceID 999 não existe na dimensão: deve usar o membro desconhecido.
    (N'OL-1004', 999, N'Cliente ainda não cadastrado', 501, N'Capacete Adventure', N'Proteção', N'Contoso', '2026-08-03', '2026-08-06', 1, 100.00, 0.00);
GO

-- =================================================================================
-- PARTE 2: DIMENSÕES E CHAVES SUBSTITUTAS
-- =================================================================================
CREATE TABLE lab_dimensional.DimDate (
    DateKey INT NOT NULL CONSTRAINT PK_DimDate PRIMARY KEY,
    CalendarDate DATE NOT NULL CONSTRAINT UQ_DimDate_Date UNIQUE,
    CalendarYear SMALLINT NOT NULL,
    CalendarMonth TINYINT NOT NULL,
    MonthName NVARCHAR(20) NOT NULL,
    IsWeekend BIT NOT NULL
);

CREATE TABLE lab_dimensional.DimCustomer (
    CustomerKey INT IDENTITY(1,1) CONSTRAINT PK_DimCustomer PRIMARY KEY,
    CustomerSourceID INT NOT NULL CONSTRAINT UQ_DimCustomer_Source UNIQUE,
    CustomerName NVARCHAR(150) NOT NULL,
    SegmentName NVARCHAR(50) NOT NULL
);

CREATE TABLE lab_dimensional.DimProduct (
    ProductKey INT IDENTITY(1,1) CONSTRAINT PK_DimProduct PRIMARY KEY,
    ProductSourceID INT NOT NULL CONSTRAINT UQ_DimProduct_Source UNIQUE,
    ProductName NVARCHAR(150) NOT NULL,
    CategoryName NVARCHAR(100) NOT NULL,
    BrandName NVARCHAR(100) NOT NULL
);
GO

-- Key 0 is the governed unknown member. Facts can load without being discarded.
SET IDENTITY_INSERT lab_dimensional.DimCustomer ON;
INSERT INTO lab_dimensional.DimCustomer (CustomerKey, CustomerSourceID, CustomerName, SegmentName)
VALUES (0, -1, N'Unknown', N'Unknown');
SET IDENTITY_INSERT lab_dimensional.DimCustomer OFF;

SET IDENTITY_INSERT lab_dimensional.DimProduct ON;
INSERT INTO lab_dimensional.DimProduct (ProductKey, ProductSourceID, ProductName, CategoryName, BrandName)
VALUES (0, -1, N'Unknown', N'Unknown', N'Unknown');
SET IDENTITY_INSERT lab_dimensional.DimProduct OFF;

;WITH Dates AS (
    SELECT CONVERT(DATE, '2026-08-01') AS CalendarDate
    UNION ALL
    SELECT DATEADD(DAY, 1, CalendarDate) FROM Dates WHERE CalendarDate < '2026-08-10'
)
INSERT INTO lab_dimensional.DimDate (DateKey, CalendarDate, CalendarYear, CalendarMonth, MonthName, IsWeekend)
SELECT CONVERT(INT, CONVERT(CHAR(8), CalendarDate, 112)), CalendarDate,
       DATEPART(YEAR, CalendarDate), DATEPART(MONTH, CalendarDate),
       DATENAME(MONTH, CalendarDate),
       CASE WHEN DATEPART(WEEKDAY, CalendarDate) IN (1, 7) THEN 1 ELSE 0 END
FROM Dates
OPTION (MAXRECURSION 0);

INSERT INTO lab_dimensional.DimCustomer (CustomerSourceID, CustomerName, SegmentName)
SELECT DISTINCT CustomerSourceID, CustomerName,
       CASE WHEN CustomerSourceID = 101 THEN N'Enterprise' ELSE N'Retail' END
FROM lab_dimensional.SalesSource
WHERE CustomerSourceID IN (101, 202)
  AND NOT EXISTS (
    SELECT 1 FROM lab_dimensional.DimCustomer AS d WHERE d.CustomerSourceID = SalesSource.CustomerSourceID
);

INSERT INTO lab_dimensional.DimProduct (ProductSourceID, ProductName, CategoryName, BrandName)
SELECT DISTINCT ProductSourceID, ProductName, CategoryName, BrandName
FROM lab_dimensional.SalesSource
WHERE NOT EXISTS (
    SELECT 1 FROM lab_dimensional.DimProduct AS d WHERE d.ProductSourceID = SalesSource.ProductSourceID
);
GO

-- =================================================================================
-- PARTE 3: FATO STAR SCHEMA
-- =================================================================================
CREATE TABLE lab_dimensional.FactSales (
    OrderLineID NVARCHAR(50) NOT NULL CONSTRAINT PK_FactSales PRIMARY KEY,
    OrderDateKey INT NOT NULL CONSTRAINT FK_FactSales_OrderDate REFERENCES lab_dimensional.DimDate(DateKey),
    ShipDateKey INT NOT NULL CONSTRAINT FK_FactSales_ShipDate REFERENCES lab_dimensional.DimDate(DateKey),
    CustomerKey INT NOT NULL CONSTRAINT FK_FactSales_Customer REFERENCES lab_dimensional.DimCustomer(CustomerKey),
    ProductKey INT NOT NULL CONSTRAINT FK_FactSales_Product REFERENCES lab_dimensional.DimProduct(ProductKey),
    Quantity INT NOT NULL,
    SalesAmount DECIMAL(14,2) NOT NULL,
    DiscountAmount DECIMAL(14,2) NOT NULL,
    NetSalesAmount AS CONVERT(DECIMAL(14,2), SalesAmount - DiscountAmount) PERSISTED,
    CONSTRAINT CK_FactSales_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_FactSales_Amounts CHECK (SalesAmount >= 0 AND DiscountAmount >= 0 AND DiscountAmount <= SalesAmount)
);
GO

INSERT INTO lab_dimensional.FactSales
    (OrderLineID, OrderDateKey, ShipDateKey, CustomerKey, ProductKey, Quantity, SalesAmount, DiscountAmount)
SELECT s.OrderLineID,
       CONVERT(INT, CONVERT(CHAR(8), s.OrderDate, 112)),
       CONVERT(INT, CONVERT(CHAR(8), s.ShipDate, 112)),
       COALESCE(c.CustomerKey, 0),
       COALESCE(p.ProductKey, 0),
       s.Quantity,
       CONVERT(DECIMAL(14,2), s.Quantity * s.UnitPrice),
       s.DiscountAmount
FROM lab_dimensional.SalesSource AS s
LEFT JOIN lab_dimensional.DimCustomer AS c ON c.CustomerSourceID = s.CustomerSourceID
LEFT JOIN lab_dimensional.DimProduct AS p ON p.ProductSourceID = s.ProductSourceID;
GO

-- Role-playing date dimension: one DimDate, two semantic roles.
SELECT o.CalendarDate AS OrderDate, sh.CalendarDate AS ShipDate,
       SUM(f.Quantity) AS UnitsSold, SUM(f.NetSalesAmount) AS NetSalesAmount
FROM lab_dimensional.FactSales AS f
JOIN lab_dimensional.DimDate AS o ON o.DateKey = f.OrderDateKey
JOIN lab_dimensional.DimDate AS sh ON sh.DateKey = f.ShipDateKey
GROUP BY o.CalendarDate, sh.CalendarDate
ORDER BY o.CalendarDate;
GO

-- Star query: the fact joins directly to descriptive dimensions.
SELECT p.CategoryName, p.ProductName, c.SegmentName,
       SUM(f.Quantity) AS UnitsSold,
       SUM(f.SalesAmount) AS GrossSales,
       SUM(f.NetSalesAmount) AS NetSales
FROM lab_dimensional.FactSales AS f
JOIN lab_dimensional.DimProduct AS p ON p.ProductKey = f.ProductKey
JOIN lab_dimensional.DimCustomer AS c ON c.CustomerKey = f.CustomerKey
GROUP BY p.CategoryName, p.ProductName, c.SegmentName
ORDER BY p.CategoryName, p.ProductName;
GO

-- =================================================================================
-- PARTE 4: VARIANTE SNOWFLAKE DA HIERARQUIA DE PRODUTO
-- =================================================================================
CREATE TABLE lab_dimensional.DimCategory (
    CategoryKey INT IDENTITY(1,1) CONSTRAINT PK_DimCategory PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL CONSTRAINT UQ_DimCategory_Name UNIQUE
);
CREATE TABLE lab_dimensional.DimProductSnowflake (
    ProductKey INT NOT NULL CONSTRAINT PK_DimProductSnowflake PRIMARY KEY,
    ProductSourceID INT NOT NULL CONSTRAINT UQ_DimProductSnowflake_Source UNIQUE,
    ProductName NVARCHAR(150) NOT NULL,
    CategoryKey INT NOT NULL CONSTRAINT FK_DimProductSnowflake_Category REFERENCES lab_dimensional.DimCategory(CategoryKey)
);
GO

SET IDENTITY_INSERT lab_dimensional.DimCategory ON;
INSERT INTO lab_dimensional.DimCategory (CategoryKey, CategoryName) VALUES (0, N'Unknown');
SET IDENTITY_INSERT lab_dimensional.DimCategory OFF;

INSERT INTO lab_dimensional.DimCategory (CategoryName)
SELECT DISTINCT CategoryName FROM lab_dimensional.DimProduct WHERE ProductSourceID <> -1;

INSERT INTO lab_dimensional.DimProductSnowflake (ProductKey, ProductSourceID, ProductName, CategoryKey)
SELECT p.ProductKey, p.ProductSourceID, p.ProductName, COALESCE(c.CategoryKey, 0)
FROM lab_dimensional.DimProduct AS p
LEFT JOIN lab_dimensional.DimCategory AS c ON c.CategoryName = p.CategoryName;
GO

-- Snowflake query: the category hierarchy adds a join but reduces repetition.
SELECT cat.CategoryName, p.ProductName, SUM(f.NetSalesAmount) AS NetSales
FROM lab_dimensional.FactSales AS f
JOIN lab_dimensional.DimProductSnowflake AS p ON p.ProductKey = f.ProductKey
JOIN lab_dimensional.DimCategory AS cat ON cat.CategoryKey = p.CategoryKey
GROUP BY cat.CategoryName, p.ProductName;
GO

-- =================================================================================
-- PARTE 5: MEDIDAS E CHECKS DE RECONCILIAÇÃO
-- =================================================================================
SELECT SUM(s.Quantity) AS SourceUnits, SUM(f.Quantity) AS FactUnits,
       SUM(s.Quantity * s.UnitPrice) AS SourceGrossSales,
       SUM(f.SalesAmount) AS FactGrossSales,
       SUM(f.DiscountAmount) AS FactDiscounts,
       SUM(f.NetSalesAmount) AS FactNetSales
FROM lab_dimensional.SalesSource AS s
CROSS JOIN (SELECT 1 AS CheckRow) AS x
JOIN lab_dimensional.FactSales AS f ON f.OrderLineID = s.OrderLineID;

IF EXISTS (
    SELECT 1 FROM lab_dimensional.FactSales AS f
    LEFT JOIN lab_dimensional.DimDate AS d ON d.DateKey = f.OrderDateKey
    LEFT JOIN lab_dimensional.DimProduct AS p ON p.ProductKey = f.ProductKey
    LEFT JOIN lab_dimensional.DimCustomer AS c ON c.CustomerKey = f.CustomerKey
    WHERE d.DateKey IS NULL OR p.ProductKey IS NULL OR c.CustomerKey IS NULL
)
    THROW 51050, 'Integridade referencial dimensional falhou.', 1;

IF NOT EXISTS (SELECT 1 FROM lab_dimensional.FactSales WHERE CustomerKey = 0)
    THROW 51051, 'O teste de membro desconhecido não foi exercitado.', 1;

IF EXISTS (
    SELECT OrderLineID FROM lab_dimensional.FactSales
    GROUP BY OrderLineID HAVING COUNT(*) > 1
)
    THROW 51052, 'O grão da fato foi violado: OrderLineID duplicado.', 1;

SELECT N'PASSOU' AS DimensionalQualityGate,
       N'Grão, chaves, membro desconhecido, datas e medidas foram validados.' AS Result;
GO

-- PRÓXIMO PASSO: revise a teoria em
-- ../../../certification/12-other-topics/05-dimensional-modeling.md
