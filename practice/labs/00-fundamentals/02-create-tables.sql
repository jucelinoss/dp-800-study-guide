-- ====================================================================
-- DP-800 Study Guide — Lab 02: Create Tables with Constraints
-- Database: StudyDB
-- Purpose: Creates the relational model with PK, FK, CHECK, DEFAULT.
-- Prerequisite: Lab 01 (StudyDB must exist with study schema)
-- ====================================================================

-- THEORY REFERENCE: ../../../certification/00-fundamentals/02-relational-model-and-data-types.md
--    Open the theory guide alongside this lab for conceptual context.

USE StudyDB;
GO

-- ====================================================================
-- PART 1: Customer table
-- KEY CONCEPT: IDENTITY = auto-incrementing integer.
-- PRIMARY KEY = unique + NOT NULL (creates clustered index by default).
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

-- [OBSERVE] IDENTITY(1,1) means start at 1, increment by 1.
-- The PK constraint enforces uniqueness AND non-nullability.

-- Verify metadata: column names, types, and nullability.
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'study' AND TABLE_NAME = 'Customer';
GO

-- ====================================================================
-- PART 2: Product table
-- KEY CONCEPT: CHECK constraint prevents negative prices.
-- ====================================================================
CREATE TABLE study.Product (
    ProductId   int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Product PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    UnitPrice   decimal(10,2) NOT NULL
        CONSTRAINT CK_Product_UnitPrice CHECK (UnitPrice >= 0)
);
GO

-- [OBSERVE] The CHECK constraint ensures UnitPrice is always >= 0.
-- Attempting to insert a negative price will raise error 547.

-- ====================================================================
-- PART 3: SalesOrder table (header-level)
-- KEY CONCEPT: FOREIGN KEY requires a matching parent row.
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

-- [OBSERVE] The FK links SalesOrder.CustomerId -> Customer.CustomerId.
-- Inserting a SalesOrder with a non-existent CustomerId will fail.

-- Query system views to see the FK definition
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
-- PART 4: SalesOrderItem table (line-item detail)
-- KEY CONCEPT: Composite primary key + FK to SalesOrder.
-- This enables multi-join queries in later labs.
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

-- [OBSERVE] The composite PK (SalesOrderId, ProductId) ensures
-- each product appears at most once per order. The FK on ProductId
-- ensures we only reference existing products.

-- ====================================================================
-- Verify all tables and their constraints
-- ====================================================================

-- List all tables in the study schema
SELECT TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'study';
GO

-- List all constraints
SELECT tc.TABLE_SCHEMA, tc.TABLE_NAME, tc.CONSTRAINT_NAME, tc.CONSTRAINT_TYPE
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS AS tc
WHERE tc.TABLE_SCHEMA = 'study'
ORDER BY tc.TABLE_NAME, tc.CONSTRAINT_TYPE;
GO

-- [OBSERVE] You should see 4 tables: Customer, Product, SalesOrder, SalesOrderItem.
-- Constraint types: PRIMARY KEY, FOREIGN KEY, CHECK.

-- KEY CONCEPT: sys.indexes shows all indexes (including those created
-- by constraints). Notice that PK constraints created clustered indexes.
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
-- CHECK YOURSELF:
-- 1. Can UnitPrice in Product be NULL? Why or why not?
-- 2. Which table(s) contain a FOREIGN KEY? What parent do they reference?
-- 3. What error do you get inserting a SalesOrder with CustomerId = 999?
-- 4. Why does SalesOrderItem use a composite primary key?

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/00-fundamentals/02-relational-model-and-data-types.md
-- =================================================================================================
