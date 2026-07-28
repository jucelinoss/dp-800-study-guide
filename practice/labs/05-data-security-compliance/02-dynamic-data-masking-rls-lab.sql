-- =================================================================================
-- DP-800 - HANDS-ON LAB: DYNAMIC DATA MASKING (DDM) AND ROW-LEVEL SECURITY (RLS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/05-data-security-compliance/02-dynamic-data-masking-rls.md
--    Open the theory guide alongside this lab for conceptual context.
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to restore the
-- AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates dynamic access control at column and row levels:
--   1. Dynamic Data Masking (DDM): default(), email(), partial() and random() functions
--   2. UNMASK Permission Control at Table and Column Level
--   3. Row-Level Security (RLS): Inline TVF with WITH SCHEMABINDING and SESSION_CONTEXT
--   4. RLS Block Predicates (AFTER INSERT, AFTER UPDATE) to prevent write leakage
--   5. Practical Design Scenarios (Multi-Tenant Isolation in E-Commerce SaaS)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.security_policies WHERE name = 'TenantIsolationPolicy')
    DROP SECURITY POLICY TenantIsolationPolicy;

IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_TenantSecurityPredicate' AND schema_id = SCHEMA_ID('Security'))
    DROP FUNCTION Security.fn_TenantSecurityPredicate;

IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'Security')
    DROP SCHEMA Security;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'TenantAppUser')
    DROP USER TenantAppUser;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'SupportUser')
    DROP USER SupportUser;

DROP TABLE IF EXISTS lab.TenantOrders;
GO

-- Create Security Schema for RLS Predicates
CREATE SCHEMA Security;
GO

-- Table Structure with DDM and RLS for Testing
CREATE TABLE lab.TenantOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    TenantID INT NOT NULL,
    CustomerName NVARCHAR(100) NOT NULL,
    CustomerEmail NVARCHAR(100) MASKED WITH (FUNCTION = 'email()') NOT NULL,
    CreditCard NVARCHAR(20) MASKED WITH (FUNCTION = 'partial(0, "XXXX-XXXX-XXXX-", 4)') NOT NULL,
    OrderAmount DECIMAL(18,2) MASKED WITH (FUNCTION = 'default()') NOT NULL
);
GO

-- Insert test data for multiple tenants
INSERT INTO lab.TenantOrders (TenantID, CustomerName, CustomerEmail, CreditCard, OrderAmount) VALUES 
(100, 'Alice Silva', 'alice@empresaA.com', '4532111122223333', 1500.00),
(100, 'Bob Santos', 'bob@empresaA.com', '5412888899990000', 850.50),
(200, 'Charlie Lima', 'charlie@empresaB.com', '3782444455556666', 3200.00);
GO


-- =================================================================================
-- PART 1: DYNAMIC DATA MASKING (DDM) AND UNMASK PERMISSION
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DDM (Dynamic Data Masking): Hides sensitive column data at query time for unauthorized users.
--   - DDM IS NOT ENCRYPTION: Data on disk remains in plaintext. DBAs and users with `UNMASK` see the real value.
--   - UNMASK PERMISSION: Can be granted at table or individual column level (SQL 2022+).

-- 1. Create support user without UNMASK permission
CREATE USER SupportUser WITHOUT LOGIN;
GRANT SELECT ON lab.TenantOrders TO SupportUser;
GO

-- -- [DP-800 EXAM TIP]
-- 2. Query as Support User (Masked values returned)
EXECUTE AS USER = 'SupportUser';
GO

SELECT OrderID, TenantID, CustomerName, CustomerEmail, CreditCard, OrderAmount
FROM lab.TenantOrders;
GO

REVERT;
GO

-- 3. Grant UNMASK permission at column level for Email only
GRANT UNMASK ON lab.TenantOrders(CustomerEmail) TO SupportUser;
GO

-- Verify Email is displayed unmasked while Card and Amount remain masked
EXECUTE AS USER = 'SupportUser';
GO

SELECT OrderID, CustomerEmail, CreditCard FROM lab.TenantOrders;
GO

REVERT;
GO


-- =================================================================================
-- PART 2: ROW-LEVEL SECURITY (RLS - FILTER AND BLOCK PREDICATES)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - RLS (Row-Level Security): Hides entire rows based on the result of an Inline TVF with `WITH SCHEMABINDING`.
--   - FILTER PREDICATE: Silently filters rows returned in SELECT, UPDATE, and DELETE.
--   - BLOCK PREDICATE: Blocks insert/update operations that would violate isolation (e.g., `AFTER INSERT`).
--   - SESSION_CONTEXT: Read-only session context set by the application via `sp_set_session_context`.

-- 1. Create Application User
CREATE USER TenantAppUser WITHOUT LOGIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON lab.TenantOrders TO TenantAppUser;
GO

-- -- [DP-800 EXAM TIP]
-- 2. Create Security Predicate Function with SCHEMABINDING
CREATE FUNCTION Security.fn_TenantSecurityPredicate (@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
    SELECT 1 AS fn_result
    WHERE @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT)
       OR USER_NAME() = 'dbo'
);
GO

-- 3. Create RLS Security Policy with FILTER and BLOCK Predicates
CREATE SECURITY POLICY TenantIsolationPolicy
ADD FILTER PREDICATE Security.fn_TenantSecurityPredicate(TenantID) ON lab.TenantOrders,
ADD BLOCK PREDICATE Security.fn_TenantSecurityPredicate(TenantID) ON lab.TenantOrders AFTER INSERT
WITH (STATE = ON);
GO


-- =================================================================================
-- PART 3: TESTING MULTI-TENANT ISOLATION VIA SESSION_CONTEXT
-- =================================================================================

-- 1. Simulate Application connecting as Tenant 100
EXECUTE AS USER = 'TenantAppUser';
GO

-- Set session context as Tenant 100
EXEC sp_set_session_context @key = N'TenantID', @value = 100, @read_only = 1;

-- User will see ONLY Tenant 100 records (Silent; no error messages)
SELECT OrderID, TenantID, CustomerName FROM lab.TenantOrders;
GO

-- -- [DP-800 EXAM TIP]
-- 2. Test the BLOCK PREDICATE (Invalid insert for Tenant 200 while in Tenant 100 context)
BEGIN TRY
    INSERT INTO lab.TenantOrders (TenantID, CustomerName, CustomerEmail, CreditCard, OrderAmount)
    VALUES (200, 'Tentativa Invasao', 'hack@test.com', '0000111122223333', 10.00);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO RLS BLOCK PREDICATE: ' + ERROR_MESSAGE();
    -- Error: "The attempted operation failed because the target object 'TenantOrders' has a security policy..."
END CATCH;
GO

REVERT;
GO


-- =================================================================================
-- PART 4: PRACTICAL DESIGN SCENARIOS
-- =================================================================================

--- SCENARIO 1: Audit Query of RLS Policies and Masked Columns in the Database
-- Allows security auditors to validate all active policies in the server.

SELECT 
    sp.name AS NomePolitica,
    sp.is_enabled AS PoliticaAtiva,
    spr.predicate_type_desc AS TipoPredicado,
    o.name AS TabelaProtegida,
    spr.predicate_definition AS ExpressaoPredicado
FROM sys.security_policies sp
JOIN sys.security_predicates spr ON sp.object_id = spr.object_id
JOIN sys.objects o ON spr.target_object_id = o.object_id;

SELECT 
    o.name AS Tabela,
    c.name AS Coluna,
    mc.masking_function AS FuncaoMascaramento
FROM sys.masked_columns mc
JOIN sys.objects o ON mc.object_id = o.object_id
JOIN sys.columns c ON mc.object_id = c.object_id AND mc.column_id = c.column_id;
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/05-data-security-compliance/02-dynamic-data-masking-rls.md
-- =================================================================================================
