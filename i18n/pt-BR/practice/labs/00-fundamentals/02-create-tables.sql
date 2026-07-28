-- ====================================================================
-- DP-800 Guia de Estudo — Laboratório 02: Criar Tabelas com Restrições
-- Banco de Dados: StudyDB
-- Objetivo: Cria o modelo relacional com PK, FK, CHECK, DEFAULT.
-- Pré-requisito: Laboratório 01 (StudyDB deve existir com schema study)
-- ====================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/00-fundamentals/02-relational-model-and-data-types.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.

USE StudyDB;
GO

-- ====================================================================
-- PARTE 1: Tabela Customer
-- CONCEITO CHAVE: IDENTITY = inteiro auto-incrementável.
-- PRIMARY KEY = unique + NOT NULL (cria índice clusterizado por padrão).
-- ====================================================================
CREATE TABLE study.Customer (
    CustomerId   int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Customer PRIMARY KEY,
    CustomerName nvarchar(100) NOT NULL,
    Email        nvarchar(320) NULL,
    IsActive     bit NOT NULL
        CONSTRAINT DF_Customer_IsActive DEFAULT (1)
);
GO

-- [OBSERVE] IDENTITY(1,1) significa começar em 1, incrementar em 1.
-- A restrição PK impõe unicidade E não-anulabilidade.

-- Verifique metadados: nomes de colunas, tipos e anulabilidade.
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'study' AND TABLE_NAME = 'Customer';
GO

-- ====================================================================
-- PARTE 2: Tabela Product
-- CONCEITO CHAVE: Restrição CHECK previne preços negativos.
-- ====================================================================
CREATE TABLE study.Product (
    ProductId   int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Product PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    UnitPrice   decimal(10,2) NOT NULL
        CONSTRAINT CK_Product_UnitPrice CHECK (UnitPrice >= 0)
);
GO

-- [OBSERVE] A restrição CHECK garante que UnitPrice seja sempre >= 0.
-- Tentar inserir um preço negativo levantará o erro 547.

-- ====================================================================
-- PARTE 3: Tabela SalesOrder (nível de cabeçalho)
-- CONCEITO CHAVE: FOREIGN KEY requer uma linha pai correspondente.
-- ====================================================================
CREATE TABLE study.SalesOrder (
    SalesOrderId int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_SalesOrder PRIMARY KEY,
    CustomerId   int NOT NULL,
    OrderDate    date NOT NULL
        CONSTRAINT DF_SalesOrder_OrderDate
            DEFAULT (CAST(SYSDATETIME() AS date)),
    OrderTotal   decimal(10,2) NOT NULL
        CONSTRAINT CK_SalesOrder_OrderTotal CHECK (OrderTotal >= 0),
    CONSTRAINT FK_SalesOrder_Customer
        FOREIGN KEY (CustomerId) REFERENCES study.Customer(CustomerId)
);
GO

-- [OBSERVE] A FK liga SalesOrder.CustomerId -> Customer.CustomerId.
-- Inserir um SalesOrder com um CustomerId inexistente falhará.

-- Consulte visualizações do sistema para ver a definição da FK
SELECT fk.name AS foreign_key_name,
       tp.name AS parent_table,
       ref.name AS referenced_table,
       fk.delete_referential_action_desc,
       fk.update_referential_action_desc
FROM sys.foreign_keys AS fk
INNER JOIN sys.tables AS tp ON fk.parent_object_id = tp.object_id
INNER JOIN sys.tables AS ref ON fk.referenced_object_id = ref.object_id
WHERE tp.name = 'SalesOrder';
GO

-- ====================================================================
-- PARTE 4: Tabela SalesOrderItem (detalhe do item de linha)
-- CONCEITO CHAVE: Chave primária composta + FK para SalesOrder.
-- Isso permite consultas com múltiplos joins em laboratórios posteriores.
-- ====================================================================
CREATE TABLE study.SalesOrderItem (
    SalesOrderId int NOT NULL,
    ProductId    int NOT NULL,
    Quantity     smallint NOT NULL
        CONSTRAINT CK_SalesOrderItem_Quantity CHECK (Quantity > 0),
    UnitPrice    decimal(10,2) NOT NULL
        CONSTRAINT CK_SalesOrderItem_UnitPrice CHECK (UnitPrice >= 0),
    CONSTRAINT PK_SalesOrderItem
        PRIMARY KEY (SalesOrderId, ProductId),
    CONSTRAINT FK_SalesOrderItem_SalesOrder
        FOREIGN KEY (SalesOrderId) REFERENCES study.SalesOrder(SalesOrderId),
    CONSTRAINT FK_SalesOrderItem_Product
        FOREIGN KEY (ProductId) REFERENCES study.Product(ProductId)
);
GO

-- [OBSERVE] A PK composta (SalesOrderId, ProductId) garante
-- que cada produto apareça no máximo uma vez por pedido. A FK em ProductId
-- garante que referenciamos apenas produtos existentes.

-- ====================================================================
-- Verifique todas as tabelas e suas restrições
-- ====================================================================

-- Liste todas as tabelas no schema study
SELECT TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'study';
GO

-- Liste todas as restrições
SELECT tc.TABLE_SCHEMA, tc.TABLE_NAME, tc.CONSTRAINT_NAME, tc.CONSTRAINT_TYPE
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS AS tc
WHERE tc.TABLE_SCHEMA = 'study'
ORDER BY tc.TABLE_NAME, tc.CONSTRAINT_TYPE;
GO

-- [OBSERVE] Você deve ver 4 tabelas: Customer, Product, SalesOrder, SalesOrderItem.
-- Tipos de restrição: PRIMARY KEY, FOREIGN KEY, CHECK.

-- CONCEITO CHAVE: sys.indexes mostra todos os índices (incluindo aqueles criados
-- por restrições). Observe que restrições PK criaram índices clusterizados.
SELECT OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,
       OBJECT_NAME(i.object_id) AS table_name,
       i.name AS index_name,
       i.type_desc AS index_type,
       i.is_unique,
       i.is_primary_key
FROM sys.indexes AS i
WHERE i.object_id IN (
    OBJECT_ID(N'study.Customer'),
    OBJECT_ID(N'study.Product'),
    OBJECT_ID(N'study.SalesOrder'),
    OBJECT_ID(N'study.SalesOrderItem')
)
ORDER BY schema_name, table_name, index_type;
GO

-- ====================================================================
-- VERIFIQUE-SE:
-- 1. UnitPrice em Product pode ser NULL? Por que ou por que não?
-- 2. Qual(is) tabela(s) contém uma FOREIGN KEY? A que pai elas referenciam?
-- 3. Que erro você obtém ao inserir um SalesOrder com CustomerId = 999?
-- 4. Por que SalesOrderItem usa uma chave primária composta?
-- ====================================================================

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/00-fundamentals/02-relational-model-and-data-types.md
-- =================================================================================================
