-- =================================================================================
-- DP-800 - LABORATÓRIO PRÁTICO: RAW VAULT E HISTORIZAÇÃO DATA VAULT
-- Banco de dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- Demonstra: snapshots de origem, Hubs e Links idempotentes, histórico de
-- Satellites, hashdiffs SHA2_256, consulta point-in-time e gates de qualidade.
-- Este script SQL Server simula os limites do Raw Vault. O armazenamento e a
-- orquestração do Fabric podem usar Lakehouse/Warehouse, OneLake, pipelines,
-- notebooks, Spark ou materialized lake views.
-- TEORIA: ../../../certification/12-other-topics/03-data-vault-architecture.md
-- HASHBYTES: https://learn.microsoft.com/en-us/sql/t-sql/functions/hashbytes-transact-sql
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

DROP TABLE IF EXISTS lab_datavault.BusinessSales;
DROP TABLE IF EXISTS lab_datavault.SatOrder;
DROP TABLE IF EXISTS lab_datavault.SatCustomer;
DROP TABLE IF EXISTS lab_datavault.LinkOrderProduct;
DROP TABLE IF EXISTS lab_datavault.LinkOrderCustomer;
DROP TABLE IF EXISTS lab_datavault.HubProduct;
DROP TABLE IF EXISTS lab_datavault.HubOrder;
DROP TABLE IF EXISTS lab_datavault.HubCustomer;
DROP TABLE IF EXISTS lab_datavault.SourceSalesSnapshot;
GO

IF SCHEMA_ID(N'lab_datavault') IS NULL
    EXEC(N'CREATE SCHEMA lab_datavault AUTHORIZATION dbo;');
GO

-- =================================================================================
-- PARTE 1: ATERrar DOIS SNAPSHOTS DA ORIGEM
-- =================================================================================
CREATE TABLE lab_datavault.SourceSalesSnapshot (
    SnapshotID BIGINT IDENTITY(1,1) CONSTRAINT PK_DvSourceSnapshot PRIMARY KEY,
    LoadDate DATETIME2(0) NOT NULL,
    BatchID NVARCHAR(50) NOT NULL,
    RecordSource NVARCHAR(100) NOT NULL,
    CustomerCode NVARCHAR(50) NOT NULL,
    CustomerName NVARCHAR(150) NOT NULL,
    CustomerStatus NVARCHAR(30) NOT NULL,
    OrderCode NVARCHAR(50) NOT NULL,
    OrderDate DATE NOT NULL,
    OrderStatus NVARCHAR(30) NOT NULL,
    ProductCode NVARCHAR(50) NOT NULL,
    ProductName NVARCHAR(150) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL
);
GO

INSERT INTO lab_datavault.SourceSalesSnapshot
    (LoadDate, BatchID, RecordSource, CustomerCode, CustomerName, CustomerStatus,
     OrderCode, OrderDate, OrderStatus, ProductCode, ProductName, Quantity, UnitPrice)
VALUES
    ('2026-08-01T08:00:00', N'crm-sales-2026-08-01', N'CRM+ERP', N'C-100', N'Contoso Brasil', N'ACTIVE', N'O-1001', '2026-07-31', N'PLACED', N'P-501', N'Capacete Adventure', 2, 25.00),
    ('2026-08-01T08:00:00', N'crm-sales-2026-08-01', N'CRM+ERP', N'C-200', N'Northwind Bikes', N'ACTIVE', N'O-1002', '2026-07-31', N'PLACED', N'P-502', N'Pneu Touring', 1, 80.00),
    -- Um snapshot posterior altera o contexto do cliente e o status do pedido.
    ('2026-08-10T08:00:00', N'crm-sales-2026-08-10', N'CRM+ERP', N'C-100', N'Contoso Brasil Ltda.', N'ACTIVE', N'O-1001', '2026-07-31', N'SHIPPED', N'P-501', N'Capacete Adventure', 2, 25.00),
    ('2026-08-10T08:00:00', N'crm-sales-2026-08-10', N'CRM+ERP', N'C-200', N'Northwind Bikes', N'SUSPENDED', N'O-1002', '2026-07-31', N'CANCELLED', N'P-502', N'Pneu Touring', 1, 80.00);
GO

SELECT LoadDate, BatchID, RecordSource, CustomerCode, OrderCode, OrderStatus,
       ProductCode, Quantity, UnitPrice
FROM lab_datavault.SourceSalesSnapshot
ORDER BY LoadDate, SnapshotID;
GO

-- =================================================================================
-- PARTE 2: HUBS DO RAW VAULT
-- =================================================================================
CREATE TABLE lab_datavault.HubCustomer (
    CustomerHashKey BINARY(32) NOT NULL CONSTRAINT PK_DvHubCustomer PRIMARY KEY,
    CustomerCode NVARCHAR(50) NOT NULL CONSTRAINT UQ_DvHubCustomer_Code UNIQUE,
    LoadDate DATETIME2(0) NOT NULL,
    RecordSource NVARCHAR(100) NOT NULL
);
CREATE TABLE lab_datavault.HubOrder (
    OrderHashKey BINARY(32) NOT NULL CONSTRAINT PK_DvHubOrder PRIMARY KEY,
    OrderCode NVARCHAR(50) NOT NULL CONSTRAINT UQ_DvHubOrder_Code UNIQUE,
    LoadDate DATETIME2(0) NOT NULL,
    RecordSource NVARCHAR(100) NOT NULL
);
CREATE TABLE lab_datavault.HubProduct (
    ProductHashKey BINARY(32) NOT NULL CONSTRAINT PK_DvHubProduct PRIMARY KEY,
    ProductCode NVARCHAR(50) NOT NULL CONSTRAINT UQ_DvHubProduct_Code UNIQUE,
    LoadDate DATETIME2(0) NOT NULL,
    RecordSource NVARCHAR(100) NOT NULL
);
GO

INSERT INTO lab_datavault.HubCustomer (CustomerHashKey, CustomerCode, LoadDate, RecordSource)
SELECT CONVERT(BINARY(32), HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(CustomerCode))))), CustomerCode, MIN(LoadDate), MIN(RecordSource)
FROM lab_datavault.SourceSalesSnapshot AS s
WHERE NOT EXISTS (SELECT 1 FROM lab_datavault.HubCustomer AS h WHERE h.CustomerCode = s.CustomerCode)
GROUP BY CustomerCode;
INSERT INTO lab_datavault.HubOrder (OrderHashKey, OrderCode, LoadDate, RecordSource)
SELECT CONVERT(BINARY(32), HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(OrderCode))))), OrderCode, MIN(LoadDate), MIN(RecordSource)
FROM lab_datavault.SourceSalesSnapshot AS s
WHERE NOT EXISTS (SELECT 1 FROM lab_datavault.HubOrder AS h WHERE h.OrderCode = s.OrderCode)
GROUP BY OrderCode;
INSERT INTO lab_datavault.HubProduct (ProductHashKey, ProductCode, LoadDate, RecordSource)
SELECT CONVERT(BINARY(32), HASHBYTES('SHA2_256', UPPER(LTRIM(RTRIM(ProductCode))))), ProductCode, MIN(LoadDate), MIN(RecordSource)
FROM lab_datavault.SourceSalesSnapshot AS s
WHERE NOT EXISTS (SELECT 1 FROM lab_datavault.HubProduct AS h WHERE h.ProductCode = s.ProductCode)
GROUP BY ProductCode;
GO

SELECT N'HubCustomer' AS ObjectName, COUNT_BIG(*) AS RowsLoaded FROM lab_datavault.HubCustomer
UNION ALL SELECT N'HubOrder', COUNT_BIG(*) FROM lab_datavault.HubOrder
UNION ALL SELECT N'HubProduct', COUNT_BIG(*) FROM lab_datavault.HubProduct;
GO

-- =================================================================================
-- PARTE 3: LINKS DO RAW VAULT
-- =================================================================================
CREATE TABLE lab_datavault.LinkOrderCustomer (
    OrderCustomerHashKey BINARY(32) NOT NULL CONSTRAINT PK_DvLinkOrderCustomer PRIMARY KEY,
    OrderHashKey BINARY(32) NOT NULL CONSTRAINT FK_DvLinkOrderCustomer_Order REFERENCES lab_datavault.HubOrder(OrderHashKey),
    CustomerHashKey BINARY(32) NOT NULL CONSTRAINT FK_DvLinkOrderCustomer_Customer REFERENCES lab_datavault.HubCustomer(CustomerHashKey),
    LoadDate DATETIME2(0) NOT NULL,
    RecordSource NVARCHAR(100) NOT NULL,
    CONSTRAINT UQ_DvLinkOrderCustomer_Pair UNIQUE (OrderHashKey, CustomerHashKey)
);
CREATE TABLE lab_datavault.LinkOrderProduct (
    OrderProductHashKey BINARY(32) NOT NULL CONSTRAINT PK_DvLinkOrderProduct PRIMARY KEY,
    OrderHashKey BINARY(32) NOT NULL CONSTRAINT FK_DvLinkOrderProduct_Order REFERENCES lab_datavault.HubOrder(OrderHashKey),
    ProductHashKey BINARY(32) NOT NULL CONSTRAINT FK_DvLinkOrderProduct_Product REFERENCES lab_datavault.HubProduct(ProductHashKey),
    LoadDate DATETIME2(0) NOT NULL,
    RecordSource NVARCHAR(100) NOT NULL,
    CONSTRAINT UQ_DvLinkOrderProduct_Pair UNIQUE (OrderHashKey, ProductHashKey)
);
GO

INSERT INTO lab_datavault.LinkOrderCustomer (OrderCustomerHashKey, OrderHashKey, CustomerHashKey, LoadDate, RecordSource)
SELECT CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONCAT(UPPER(s.OrderCode), N'|', UPPER(s.CustomerCode)))), o.OrderHashKey, c.CustomerHashKey, MIN(s.LoadDate), MIN(s.RecordSource)
FROM lab_datavault.SourceSalesSnapshot AS s
JOIN lab_datavault.HubOrder AS o ON o.OrderCode = s.OrderCode
JOIN lab_datavault.HubCustomer AS c ON c.CustomerCode = s.CustomerCode
WHERE NOT EXISTS (SELECT 1 FROM lab_datavault.LinkOrderCustomer AS l WHERE l.OrderHashKey = o.OrderHashKey AND l.CustomerHashKey = c.CustomerHashKey)
GROUP BY s.OrderCode, s.CustomerCode, o.OrderHashKey, c.CustomerHashKey;
INSERT INTO lab_datavault.LinkOrderProduct (OrderProductHashKey, OrderHashKey, ProductHashKey, LoadDate, RecordSource)
SELECT CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONCAT(UPPER(s.OrderCode), N'|', UPPER(s.ProductCode)))), o.OrderHashKey, p.ProductHashKey, MIN(s.LoadDate), MIN(s.RecordSource)
FROM lab_datavault.SourceSalesSnapshot AS s
JOIN lab_datavault.HubOrder AS o ON o.OrderCode = s.OrderCode
JOIN lab_datavault.HubProduct AS p ON p.ProductCode = s.ProductCode
WHERE NOT EXISTS (SELECT 1 FROM lab_datavault.LinkOrderProduct AS l WHERE l.OrderHashKey = o.OrderHashKey AND l.ProductHashKey = p.ProductHashKey)
GROUP BY s.OrderCode, s.ProductCode, o.OrderHashKey, p.ProductHashKey;
GO

SELECT N'LinkOrderCustomer' AS ObjectName, COUNT_BIG(*) AS RowsLoaded FROM lab_datavault.LinkOrderCustomer
UNION ALL SELECT N'LinkOrderProduct', COUNT_BIG(*) FROM lab_datavault.LinkOrderProduct;
GO

-- =================================================================================
-- PARTE 4: SATELLITES E HISTORIZAÇÃO POR HASHDIFF
-- =================================================================================
CREATE TABLE lab_datavault.SatCustomer (
    CustomerHashKey BINARY(32) NOT NULL CONSTRAINT FK_DvSatCustomer_Hub REFERENCES lab_datavault.HubCustomer(CustomerHashKey),
    LoadDate DATETIME2(0) NOT NULL,
    HashDiff BINARY(32) NOT NULL,
    CustomerName NVARCHAR(150) NOT NULL,
    CustomerStatus NVARCHAR(30) NOT NULL,
    RecordSource NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_DvSatCustomer PRIMARY KEY (CustomerHashKey, LoadDate)
);
CREATE TABLE lab_datavault.SatOrder (
    OrderHashKey BINARY(32) NOT NULL CONSTRAINT FK_DvSatOrder_Hub REFERENCES lab_datavault.HubOrder(OrderHashKey),
    LoadDate DATETIME2(0) NOT NULL,
    HashDiff BINARY(32) NOT NULL,
    OrderDate DATE NOT NULL,
    OrderStatus NVARCHAR(30) NOT NULL,
    ProductCode NVARCHAR(50) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL,
    RecordSource NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_DvSatOrder PRIMARY KEY (OrderHashKey, LoadDate)
);
GO

INSERT INTO lab_datavault.SatCustomer (CustomerHashKey, LoadDate, HashDiff, CustomerName, CustomerStatus, RecordSource)
SELECT DISTINCT c.CustomerHashKey, s.LoadDate, CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONCAT(s.CustomerName, N'|', s.CustomerStatus))), s.CustomerName, s.CustomerStatus, s.RecordSource
FROM lab_datavault.SourceSalesSnapshot AS s JOIN lab_datavault.HubCustomer AS c ON c.CustomerCode = s.CustomerCode
WHERE NOT EXISTS (SELECT 1 FROM lab_datavault.SatCustomer AS sat WHERE sat.CustomerHashKey = c.CustomerHashKey AND sat.LoadDate = s.LoadDate);
INSERT INTO lab_datavault.SatOrder (OrderHashKey, LoadDate, HashDiff, OrderDate, OrderStatus, ProductCode, Quantity, UnitPrice, RecordSource)
SELECT DISTINCT o.OrderHashKey, s.LoadDate, CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONCAT(CONVERT(NVARCHAR(30), s.OrderDate, 126), N'|', s.OrderStatus, N'|', s.ProductCode, N'|', s.Quantity, N'|', s.UnitPrice))), s.OrderDate, s.OrderStatus, s.ProductCode, s.Quantity, s.UnitPrice, s.RecordSource
FROM lab_datavault.SourceSalesSnapshot AS s JOIN lab_datavault.HubOrder AS o ON o.OrderCode = s.OrderCode
WHERE NOT EXISTS (SELECT 1 FROM lab_datavault.SatOrder AS sat WHERE sat.OrderHashKey = o.OrderHashKey AND sat.LoadDate = s.LoadDate);
GO

SELECT N'Histórico de cliente' AS HistoryName, c.CustomerCode AS BusinessKey, sat.LoadDate, sat.CustomerName, sat.CustomerStatus, CONVERT(VARCHAR(64), sat.HashDiff, 2) AS HashDiff
FROM lab_datavault.SatCustomer AS sat JOIN lab_datavault.HubCustomer AS c ON c.CustomerHashKey = sat.CustomerHashKey
UNION ALL
SELECT N'Histórico de pedido', o.OrderCode, sat.LoadDate, sat.OrderStatus, CONCAT(N'Qtd=', sat.Quantity, N'; Preço=', sat.UnitPrice), CONVERT(VARCHAR(64), sat.HashDiff, 2)
FROM lab_datavault.SatOrder AS sat JOIN lab_datavault.HubOrder AS o ON o.OrderHashKey = sat.OrderHashKey
ORDER BY HistoryName, BusinessKey;
GO

-- =================================================================================
-- PARTE 5: CONSULTA POINT-IN-TIME E PROJEÇÃO BUSINESS VAULT
-- =================================================================================
DECLARE @AsOf DATETIME2(0) = '2026-08-05T23:59:59';
SELECT o.OrderCode, c.CustomerCode, customer_sat.CustomerName, customer_sat.CustomerStatus,
       order_sat.OrderStatus, order_sat.Quantity, order_sat.UnitPrice, order_sat.LoadDate AS OrderVersionLoadedAt
FROM lab_datavault.LinkOrderCustomer AS loc
JOIN lab_datavault.HubOrder AS o ON o.OrderHashKey = loc.OrderHashKey
JOIN lab_datavault.HubCustomer AS c ON c.CustomerHashKey = loc.CustomerHashKey
OUTER APPLY (SELECT TOP (1) sat.CustomerName, sat.CustomerStatus FROM lab_datavault.SatCustomer AS sat WHERE sat.CustomerHashKey = c.CustomerHashKey AND sat.LoadDate <= @AsOf ORDER BY sat.LoadDate DESC) AS customer_sat
OUTER APPLY (SELECT TOP (1) sat.OrderStatus, sat.Quantity, sat.UnitPrice, sat.LoadDate FROM lab_datavault.SatOrder AS sat WHERE sat.OrderHashKey = o.OrderHashKey AND sat.LoadDate <= @AsOf ORDER BY sat.LoadDate DESC) AS order_sat;
GO

SELECT o.OrderCode, s.OrderStatus, s.Quantity, CONVERT(DECIMAL(14,2), s.Quantity * s.UnitPrice) AS CurrentOrderValue
FROM lab_datavault.HubOrder AS o JOIN lab_datavault.SatOrder AS s ON s.OrderHashKey = o.OrderHashKey
WHERE s.LoadDate = (SELECT MAX(s2.LoadDate) FROM lab_datavault.SatOrder AS s2 WHERE s2.OrderHashKey = s.OrderHashKey);
GO

-- =================================================================================
-- PARTE 6: CHECKS DE QUALIDADE E IDEMPOTÊNCIA
-- =================================================================================
IF EXISTS (SELECT CustomerCode FROM lab_datavault.HubCustomer GROUP BY CustomerCode HAVING COUNT(*) > 1)
    THROW 51030, 'Verificação de unicidade da chave do Hub falhou.', 1;
IF EXISTS (SELECT l.OrderHashKey FROM lab_datavault.LinkOrderCustomer AS l LEFT JOIN lab_datavault.HubOrder AS o ON o.OrderHashKey = l.OrderHashKey LEFT JOIN lab_datavault.HubCustomer AS c ON c.CustomerHashKey = l.CustomerHashKey WHERE o.OrderHashKey IS NULL OR c.CustomerHashKey IS NULL)
    THROW 51031, 'Verificação de integridade referencial do Link falhou.', 1;
IF EXISTS (SELECT sat.CustomerHashKey FROM lab_datavault.SatCustomer AS sat LEFT JOIN lab_datavault.HubCustomer AS h ON h.CustomerHashKey = sat.CustomerHashKey WHERE h.CustomerHashKey IS NULL)
    THROW 51032, 'Verificação do Hub pai do Satellite falhou.', 1;
SELECT N'PASSOU' AS DataVaultQualityGate, N'Hubs, links, satellites, histórico hashdiff e referências pai são válidos.' AS Result;
GO

-- PRÓXIMO PASSO: revise a teoria em
-- ../../../certification/12-other-topics/03-data-vault-architecture.md
