-- =================================================================================
-- DP-800 - HANDS-ON LAB: MCP SERVER ENDPOINTS (MODEL CONTEXT PROTOCOL)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/04-ai-assisted-tools/03-mcp-server-endpoints.md
--    Open the theory guide alongside this lab for conceptual context.
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks (OLTP version) database backup available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates security configuration and inspection for MCP Servers (Model Context Protocol):
--   1. Creation of a dedicated Least-Privilege Account for MCP Servers (`mcp_service_user`)
--   2. Granting Schema Discovery Permissions (`VIEW DEFINITION` and `SELECT`)
--   3. Blocking Access to Critical/Financial Tables via `DENY SELECT`
--   4. Simulation of Read Queries and Metadata Discovery executed by MCP tools
--   5. Practical Project Scenarios (MCP Endpoint Permission Audit Script)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'mcp_service_user')
    DROP USER mcp_service_user;

DROP TABLE IF EXISTS lab.FinancialRecords;
DROP TABLE IF EXISTS lab.PublicCatalog;
GO

-- Table Structures for Testing
CREATE TABLE lab.PublicCatalog (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    ItemName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(255) NULL
);

CREATE TABLE lab.FinancialRecords (
    RecordID INT IDENTITY(1,1) PRIMARY KEY,
    AccountCode NVARCHAR(50) NOT NULL,
    Balance DECIMAL(18,2) NOT NULL
);
GO


-- =================================================================================
-- PART 1: MCP SERVICE ACCOUNT CONFIGURATION (LEAST PRIVILEGE PRINCIPLE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - ELEVATED CREDENTIAL RISK IN MCP: The MCP server executes all queries under the
--     context of the credential provided in the connection string (e.g., `.vscode/mcp.json`).
--   - IF THE ACCOUNT IS DB_OWNER: The AI assistant could accidentally execute harmful DDL or DML statements.
--   - REQUIRED PATTERN: Dedicated account without native login (`WITHOUT LOGIN`) or Managed Identity with strictly read-only access.

-- -- [DP-800 EXAM TIP]
-- 1. Create a dedicated user for the MCP Server connection
CREATE USER mcp_service_user WITHOUT LOGIN;

-- 2. Grant schema definition inspection permission (Catalog read)
GRANT VIEW DEFINITION ON SCHEMA::lab TO mcp_service_user;
GRANT SELECT ON SCHEMA::lab TO mcp_service_user;

-- 3. Explicitly block sensitive financial/PII tables
DENY SELECT ON lab.FinancialRecords TO mcp_service_user;
GO


-- =================================================================================
-- PART 2: SIMULATION OF DISCOVERY QUERIES EXECUTED BY THE MCP SERVER
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - When Copilot connects via MCP, it executes queries on the SQL Server metadata repository
--     to build the object tree and understand the context in real time.

EXECUTE AS USER = 'mcp_service_user';
GO

-- 1. Simulation: MCP Server discovering visible tables in the schema
SELECT 
    t.TABLE_SCHEMA,
    t.TABLE_NAME,
    t.TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_SCHEMA = 'lab';

-- 2. Simulation: MCP Server reading column metadata to enrich prompts
SELECT 
    c.COLUMN_NAME,
    c.DATA_TYPE,
    c.CHARACTER_MAXIMUM_LENGTH,
    c.IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = 'lab' AND c.TABLE_NAME = 'PublicCatalog';

-- -- [DP-800 EXAM TIP]
-- 3. Test Access to Protected Table (Should fail)
BEGIN TRY
    SELECT * FROM lab.FinancialRecords;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO MCP LEAST-PRIVILEGE: ' + ERROR_MESSAGE();
    -- Expected error: "The SELECT permission was denied on the object 'FinancialRecords'..."
END CATCH;
GO

REVERT; -- Return to original context
GO


-- =================================================================================
-- PART 3: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Security Audit for MCP Connection Accounts in Dev/Staging Environments
-- Ensures no account configured in MCP tools has write or schema-alter privileges.

SELECT 
    dp.name AS PrincipalName,
    dp.type_desc AS PrincipalType,
    pe.permission_name AS PermissaoConcedida,
    pe.state_desc AS EstadoPermissao,
    o.name AS ObjetoAfetado
FROM sys.database_permissions pe
JOIN sys.database_principals dp ON pe.grantee_principal_id = dp.principal_id
LEFT JOIN sys.objects o ON pe.major_id = o.object_id
WHERE dp.name = 'mcp_service_user';
GO

-- SCENARIO 2: Governance inventory. Capture the identity, scope, operation type,
-- and audit expectation before enabling an MCP tool against a shared environment.
SELECT N'Schema discovery' AS ToolPurpose, N'VIEW DEFINITION' AS MinimumScope,
       N'Read-only metadata; audit caller and tool parameters' AS Governance
UNION ALL
SELECT N'Catalog lookup', N'SELECT on approved view',
       N'Exclude sensitive columns; log outcome and correlation ID'
UNION ALL
SELECT N'DDL/DML action', N'Not granted by default',
       N'Require separate identity, approval path, and production change control';
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/04-ai-assisted-tools/03-mcp-server-endpoints.md
-- =================================================================================================
