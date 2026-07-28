-- =================================================================================
-- DP-800 - PRACTICAL LAB: MODERN ARCHITECTURES (EAV VS HYBRID JSON, DATA MESH, AND ENVIRONMENTS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script simulates 3 logical groupings of data architecture in SQL Server:
--   1. GROUP 1: Classic EAV Model (The Anti-Pattern) vs Hybrid JSON (The Modern Pattern)
--   2. GROUP 2: Data Mesh & Data Products with No Re-Deployment
--   3. GROUP 3: Environment Simulation (On-Premises, Cloud/Fabric Zero-ETL, and Hybrid/Azure Arc)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/12-other-topics/01-architectures-eav-datamesh-sqlserver.md
--    Open the theory guide alongside this lab for conceptual context.

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.EavValues;
DROP TABLE IF EXISTS lab.EavAttributes;
DROP TABLE IF EXISTS lab.EavEntities;
DROP TABLE IF EXISTS lab.HybridProducts;
DROP TABLE IF EXISTS lab.DataProductMetadataContract;
DROP TABLE IF EXISTS lab.HybridTenantOrders;
DROP SECURITY POLICY IF EXISTS lab.TenantSecurityPolicy;
DROP FUNCTION IF EXISTS lab.fn_TenantAccessPredicate;
GO


-- =================================================================================
-- LOGICAL GROUP 1: CLASSIC EAV (THE ANTI-PATTERN) VS HYBRID JSON (THE MODERN PATTERN)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - EAV (Entity-Attribute-Value): Splits data into 3 tables. Requires multiple JOINs (Join Explosion)
--     and loses column statistics in SQL Server.
--   - HYBRID JSON: Keeps 1 table with core relational columns + 1 JSON column with dynamic attributes.
--     Uses 'PERSISTED Computed Columns' to create B-Tree indexes and accelerate queries without JOINs.

-- 1.1 Creating the Classic EAV Structure (3 Tables)
CREATE TABLE lab.EavEntities (
    EntityID INT IDENTITY(1,1) PRIMARY KEY,
    EntityName NVARCHAR(100) NOT NULL
);

CREATE TABLE lab.EavAttributes (
    AttributeID INT IDENTITY(1,1) PRIMARY KEY,
    AttributeName NVARCHAR(100) NOT NULL
);

CREATE TABLE lab.EavValues (
    ValueID INT IDENTITY(1,1) PRIMARY KEY,
    EntityID INT NOT NULL REFERENCES lab.EavEntities(EntityID),
    AttributeID INT NOT NULL REFERENCES lab.EavAttributes(AttributeID),
    ValueText NVARCHAR(MAX) NOT NULL
);
GO

-- Insert test data into the EAV model
INSERT INTO lab.EavEntities (EntityName) VALUES (N'Smartphone X'), (N'T-Shirt Premium');
INSERT INTO lab.EavAttributes (AttributeName) VALUES (N'Brand'), (N'Color'), (N'ScreenSize'), (N'Material');

INSERT INTO lab.EavValues (EntityID, AttributeID, ValueText) VALUES
(1, 1, N'TechCorp'), (1, 3, N'6.1 inches'), -- Smartphone: Brand, ScreenSize
(2, 1, N'StyleCo'),  (2, 2, N'Navy Blue'), (2, 4, N'Cotton'); -- T-Shirt: Brand, Color, Material
GO

-- 1.2 Classic EAV Query (Requires multiple JOINs per attribute - Join Explosion)
SELECT 
    e.EntityName,
    vBrand.ValueText AS Brand,
    vScreen.ValueText AS ScreenSize,
    vColor.ValueText AS Color,
    vMat.ValueText AS Material
FROM lab.EavEntities e
LEFT JOIN lab.EavValues vBrand ON e.EntityID = vBrand.EntityID AND vBrand.AttributeID = 1
LEFT JOIN lab.EavValues vScreen ON e.EntityID = vScreen.EntityID AND vScreen.AttributeID = 3
LEFT JOIN lab.EavValues vColor ON e.EntityID = vColor.EntityID AND vColor.AttributeID = 2
LEFT JOIN lab.EavValues vMat ON e.EntityID = vMat.EntityID AND vMat.AttributeID = 4;
GO

-- 1.3 Creating the Hybrid JSON Structure (1 Relational Table + JSON Column + PERSISTED Computed Column)
CREATE TABLE lab.HybridProducts (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    Title NVARCHAR(100) NOT NULL,
    Price DECIMAL(10,2) NOT NULL,
    AttributesJson NVARCHAR(MAX) NOT NULL,
    
    -- JSON format validation
    CONSTRAINT CK_HybridProducts_Json CHECK (ISJSON(AttributesJson) = 1)
);

-- High-frequency attribute indexed via Persisted Computed Column (no 8000-byte limit via CAST)
ALTER TABLE lab.HybridProducts
ADD Brand AS CAST(JSON_VALUE(AttributesJson, '$.brand') AS NVARCHAR(50)) PERSISTED;

CREATE NONCLUSTERED INDEX IX_HybridProducts_Brand ON lab.HybridProducts(Brand);
GO

INSERT INTO lab.HybridProducts (Title, Price, AttributesJson) VALUES
(N'Smartphone X', 999.99, N'{"brand": "TechCorp", "screen_size": "6.1 inches"}'),
(N'T-Shirt Premium', 29.90, N'{"brand": "StyleCo", "color": "Navy Blue", "material": "Cotton"}');
GO

-- 1.4 Hybrid JSON Query (Simple, direct, and no JOINs!)
SELECT 
    Title,
    Price,
    Brand, -- Persisted computed column indexed (Index Seek)
    JSON_VALUE(AttributesJson, '$.screen_size') AS ScreenSize,
    JSON_VALUE(AttributesJson, '$.color') AS Color
FROM lab.HybridProducts
WHERE Brand = N'TechCorp';
GO


-- =================================================================================
-- LOGICAL GROUP 2: DATA MESH & DATA PRODUCTS (WITHOUT CODE RE-DEPLOYMENT)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DATA MESH: Architecture where each domain manages its own Data Products.
--   - NO RE-DEPLOYMENT: Using JSON metadata, a Sales domain dynamically exposes new fields
--     in the API without needing to alter DDL code or recompile the backend application.

CREATE TABLE lab.DataProductMetadataContract (
    ContractID INT IDENTITY(1,1) PRIMARY KEY,
    DomainName NVARCHAR(50) NOT NULL,
    ApiEndpoint NVARCHAR(100) NOT NULL,
    ContractSchemaJson NVARCHAR(MAX) NOT NULL
);
GO

INSERT INTO lab.DataProductMetadataContract (DomainName, ApiEndpoint, ContractSchemaJson)
VALUES (
    N'Vendas',
    N'/api/v1/sales/orders',
    N'[
        {"Field": "ProductID", "Source": "ProductID", "Type": "INT"},
        {"Field": "Title", "Source": "Title", "Type": "STRING"},
        {"Field": "Brand", "Source": "Brand", "Type": "STRING"}
    ]'
);
GO

-- Simulate Generating the Data Product JSON Payload for Consumers (FOR JSON PATH)
SELECT 
    ProductID AS id,
    Title AS produto,
    Price AS preco,
    Brand AS marca,
    JSON_QUERY(AttributesJson) AS atributos_dinamicos
FROM lab.HybridProducts
FOR JSON PATH, ROOT('DataProduct_SalesOrders');
GO


-- =================================================================================
-- LOGICAL GROUP 3: ENVIRONMENT SIMULATION (ON-PREMISES, CLOUD, AND HYBRID)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - ON-PREMISES: Focus on strict local data validation (ISJSON and integrity).
--   - CLOUD NATIVE (FABRIC ZERO-ETL): Simulates Delta/JSON export to OneLake without manual pipelines.
--   - HYBRID (AZURE ARC / MULTI-TENANT): Centralized governance and per-Tenant isolation with RLS (Security Policy).

-- 3.1 Hybrid Simulation (Azure Arc / Multi-Tenant RLS): Table with Business Unit/Tenant isolation
CREATE TABLE lab.HybridTenantOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    TenantID INT NOT NULL, -- 1: Datacenter Brazil (On-Prem), 2: Cloud Azure US
    CustomerName NVARCHAR(100) NOT NULL,
    OrderTotal DECIMAL(10,2) NOT NULL
);

INSERT INTO lab.HybridTenantOrders (TenantID, CustomerName, OrderTotal) VALUES
(1, N'Empresa Local SP (On-Premises)', 1500.00),
(2, N'Global Cloud Client NY (Azure)', 5400.00);
GO

-- Create RLS (Row-Level Security) Function to Simulate Hybrid Arc Isolation
CREATE FUNCTION lab.fn_TenantAccessPredicate(@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_TenantAccessPredicate_result
       WHERE @TenantID = CAST(SESSION_CONTEXT(N'CurrentTenantID') AS INT)
          OR SESSION_CONTEXT(N'CurrentTenantID') IS NULL; -- Admin sees all
GO

CREATE SECURITY POLICY lab.TenantSecurityPolicy
ADD FILTER PREDICATE lab.fn_TenantAccessPredicate(TenantID) ON lab.HybridTenantOrders,
ADD BLOCK PREDICATE lab.fn_TenantAccessPredicate(TenantID) ON lab.HybridTenantOrders;
GO

-- Test Isolated Read per Tenant (Simulating On-Premises Session Tenant = 1)
EXEC sp_set_session_context @key = N'CurrentTenantID', @value = 1;

SELECT * FROM lab.HybridTenantOrders; -- Returns only the Tenant 1 row (On-Premises)
GO

-- Clear session context
EXEC sp_set_session_context @key = N'CurrentTenantID', @value = NULL;
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/12-other-topics/01-architectures-eav-datamesh-sqlserver.md
-- =================================================================================================
