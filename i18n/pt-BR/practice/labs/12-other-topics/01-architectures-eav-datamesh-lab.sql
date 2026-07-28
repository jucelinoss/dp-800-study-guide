-- =================================================================================
-- DP-800 - LAB PRÁTICO: ARQUITETURAS MODERNAS (EAV VS JSON HÍBRIDO, DATA MESH E AMBIENTES)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script simula na prática 3 agrupamentos lógicos de arquitetura de dados no SQL Server:
--   1. AGRUPAMENTO 1: Modelo Clássico EAV (O Antipadrão) vs JSON Híbrido (O Padrão Moderno)
--   2. AGRUPAMENTO 2: Data Mesh & Produtos de Dados (Data Products) sem Redesplegue de Código
--   3. AGRUPAMENTO 3: Simulação de Ambientes (On-Premises, Nuvem/Fabric Zero-ETL e Híbrido/Azure Arc)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/12-other-topics/01-architectures-eav-datamesh-sqlserver.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
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
-- AGRUPAMENTO LÓGICO 1: EAV CLÁSSICO (O ANTIPADRÃO) VS JSON HÍBRIDO (O PADRÃO MODERNO)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - EAV (Entity-Attribute-Value): Divide dados em 3 tabelas. Exige múltiplos JOINs (Join Explosion)
--     e perde estatísticas de coluna no SQL Server.
--   - JSON HÍBRIDO: Mantém 1 tabela com colunas relacioanais núcleo + 1 coluna JSON com atributos dinâmicos.
--     Usa 'PERSISTED Computed Columns' para criar índices B-Tree e acelerar buscas sem JOINs.

-- 1.1 Criando a Estrutura EAV Clássica (3 Tabelas)
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

-- Inserir dados de teste no modelo EAV
INSERT INTO lab.EavEntities (EntityName) VALUES (N'Smartphone X'), (N'T-Shirt Premium');
INSERT INTO lab.EavAttributes (AttributeName) VALUES (N'Brand'), (N'Color'), (N'ScreenSize'), (N'Material');

INSERT INTO lab.EavValues (EntityID, AttributeID, ValueText) VALUES
(1, 1, N'TechCorp'), (1, 3, N'6.1 inches'), -- Smartphone: Brand, ScreenSize
(2, 1, N'StyleCo'),  (2, 2, N'Navy Blue'), (2, 4, N'Cotton'); -- T-Shirt: Brand, Color, Material
GO

-- 1.2 Consulta EAV Clássica (Exige múltiplos JOINs para cada atributo - Join Explosion)
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

-- 1.3 Criando a Estrutura JSON Híbrida (1 Tabela Relacional + Coluna JSON + PERSISTED Computed Column)
CREATE TABLE lab.HybridProducts (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    Title NVARCHAR(100) NOT NULL,
    Price DECIMAL(10,2) NOT NULL,
    AttributesJson NVARCHAR(MAX) NOT NULL,
    
    -- Validação do formato JSON
    CONSTRAINT CK_HybridProducts_Json CHECK (ISJSON(AttributesJson) = 1)
);

-- Atributo de alta frequência indexado via Coluna Computada Persistida (sem limites de 8000 bytes via CAST)
ALTER TABLE lab.HybridProducts
ADD Brand AS CAST(JSON_VALUE(AttributesJson, '$.brand') AS NVARCHAR(50)) PERSISTED;

CREATE NONCLUSTERED INDEX IX_HybridProducts_Brand ON lab.HybridProducts(Brand);
GO

INSERT INTO lab.HybridProducts (Title, Price, AttributesJson) VALUES
(N'Smartphone X', 999.99, N'{"brand": "TechCorp", "screen_size": "6.1 inches"}'),
(N'T-Shirt Premium', 29.90, N'{"brand": "StyleCo", "color": "Navy Blue", "material": "Cotton"}');
GO

-- 1.4 Consulta no JSON Híbrido (Simples, direta e sem JOINs!)
SELECT 
    Title,
    Price,
    Brand, -- Coluna computada persistida indexada (Index Seek)
    JSON_VALUE(AttributesJson, '$.screen_size') AS ScreenSize,
    JSON_VALUE(AttributesJson, '$.color') AS Color
FROM lab.HybridProducts
WHERE Brand = N'TechCorp';
GO


-- =================================================================================
-- AGRUPAMENTO LÓGICO 2: DATA MESH & PRODUTO DE DADOS (SEM REDESPLEGUE DE CÓDIGO)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DATA MESH: Arquitetura onde cada domínio gerencia seus próprios Produtos de Dados.
--   - SEM REDESPLEGUE (NO RE-DEPLOYMENT): Usando metadados em JSON, um domínio de Vendas expõe novos campos
--     na API dinamicamente sem precisar alterar código DDL ou recompilar a aplicação backend.

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

-- Simulação de Geração do Payload JSON do Produto de Dados para Consumidores (FOR JSON PATH)
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
-- AGRUPAMENTO LÓGICO 3: SIMULAÇÃO DE AMBIENTES (ON-PREMISES, NUVEM E HÍBRIDO)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - ON-PREMISES: Foco em validação estrita de dados locais (ISJSON e integridade).
--   - CLOUD NATIVE (FABRIC ZERO-ETL): Simulação de exportação Delta/JSON para OneLake sem pipelines manuais.
--   - HÍBRIDO (AZURE ARC / MULTI-TENANT): Governança centralizada e isolamento por Tenant com RLS (Security Policy).

-- 3.1 Simulação Híbrida (Azure Arc / Multi-Tenant RLS): Tabela com isolamento por Unidade de Negócio/Tenant
CREATE TABLE lab.HybridTenantOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    TenantID INT NOT NULL, -- 1: Datacenter Brasil (On-Prem), 2: Cloud Azure US
    CustomerName NVARCHAR(100) NOT NULL,
    OrderTotal DECIMAL(10,2) NOT NULL
);

INSERT INTO lab.HybridTenantOrders (TenantID, CustomerName, OrderTotal) VALUES
(1, N'Empresa Local SP (On-Premises)', 1500.00),
(2, N'Global Cloud Client NY (Azure)', 5400.00);
GO

-- Criar Função de Segurança RLS (Row-Level Security) para Simular Isolamento Híbrido Arc
CREATE FUNCTION lab.fn_TenantAccessPredicate(@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_TenantAccessPredicate_result
       WHERE @TenantID = CAST(SESSION_CONTEXT(N'CurrentTenantID') AS INT)
          OR SESSION_CONTEXT(N'CurrentTenantID') IS NULL; -- Admin vê todos
GO

CREATE SECURITY POLICY lab.TenantSecurityPolicy
ADD FILTER PREDICATE lab.fn_TenantAccessPredicate(TenantID) ON lab.HybridTenantOrders,
ADD BLOCK PREDICATE lab.fn_TenantAccessPredicate(TenantID) ON lab.HybridTenantOrders;
GO

-- Teste de Leitura Isolada por Tenant (Simulando Sessão On-Premises Tenant = 1)
EXEC sp_set_session_context @key = N'CurrentTenantID', @value = 1;

SELECT * FROM lab.HybridTenantOrders; -- Retorna apenas a linha do Tenant 1 (On-Premises)
GO

-- Limpar contexto de sessão
EXEC sp_set_session_context @key = N'CurrentTenantID', @value = NULL;
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/12-other-topics/01-architectures-eav-datamesh-sqlserver.md
-- =================================================================================================
