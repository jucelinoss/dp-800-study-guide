-- =================================================================================
-- DP-800 - PRACTICAL LAB: SECURITY AND IMPACT OF AI-ASSISTED TOOLS
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates security practices when using AI-assisted tools (Copilot):
--   1. Discovery and Classification of Sensitive Data (PII) via `sys.sensitivity_classifications`
--   2. Applying Sensitivity Labels with `ADD SENSITIVITY CLASSIFICATION`
--   3. Pre-Execution Validation and Sandbox Execution with Restrictions (`EXECUTE AS USER`)
--   4. Traceability and Auditing of AI-Generated Code via Tags and Extended Events
--   5. Practical Project Scenarios (Audit Pipeline for AI-Suggested Code)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'ai_sandbox_user')
    DROP USER ai_sandbox_user;

DROP TABLE IF EXISTS lab.CustomerPII;
GO

-- Table structure with PII Data for Testing
CREATE TABLE lab.CustomerPII (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FullName NVARCHAR(100) NOT NULL,
    SSN VARCHAR(11) NOT NULL,
    CreditCard VARCHAR(16) NOT NULL,
    Email NVARCHAR(100) NOT NULL
);
GO


-- =================================================================================
-- PART 1: DISCOVERY AND CLASSIFICATION OF SENSITIVE DATA (PII / PURVIEW)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CLASSIFICATION BEFORE AI: Before enabling AI-assisted tools in the editor,
--     you must classify columns containing PII/financial data to prevent inadvertent exposure to the model.
--   - ADD SENSITIVITY CLASSIFICATION: Adds native SQL Server / Azure SQL sensitivity labels.
--   - sys.sensitivity_classifications: Catalog view that lists all classified columns.

-- -- [DP-800 EXAM TIP]
-- 1. Apply sensitivity classification to critical PII columns
ADD SENSITIVITY CLASSIFICATION TO lab.CustomerPII.SSN
WITH (LABEL = 'Confidential', LABEL_ID = '33221100-0000-0000-0000-000000000000', INFORMATION_TYPE = 'National ID', INFORMATION_TYPE_ID = '11223344-0000-0000-0000-000000000000', RANK = HIGH);

ADD SENSITIVITY CLASSIFICATION TO lab.CustomerPII.CreditCard
WITH (LABEL = 'Highly Confidential', LABEL_ID = '44332211-0000-0000-0000-000000000000', INFORMATION_TYPE = 'Credit Card', INFORMATION_TYPE_ID = '22334455-0000-0000-0000-000000000000', RANK = CRITICAL);
GO

-- 2. Query the sensitivity classification catalog (Purview Integration)
SELECT
    schema_name(o.schema_id) AS SchemaName,
    o.name                   AS TableName,
    c.name                   AS ColumnName,
    sc.information_type_name AS TipoInformacao,
    sc.label_name            AS RotuloSensibilidade,
    sc.rank_desc             AS NivelRisco
FROM sys.sensitivity_classifications sc
JOIN sys.objects o ON sc.major_id = o.object_id
JOIN sys.columns c ON sc.major_id = c.object_id AND sc.minor_id = c.column_id
WHERE o.name = 'CustomerPII';
GO


-- =================================================================================
-- PART 2: SANDBOX EXECUTION WITH LEAST PRIVILEGE (EXECUTE AS USER)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - NEVER EXECUTE AI CODE WITH OWNER OR SYSADMIN PRIVILEGES WITHOUT REVIEW:
--     AI may suggest `SELECT *` on PII columns or accidentally modify schemas.
--   - SANDBOX PATTERN: Create a user without login with restricted permissions and explicit denial (`DENY SELECT`) on sensitive tables.

-- -- [DP-800 EXAM TIP]
-- 1. Create Sandbox User
CREATE USER ai_sandbox_user WITHOUT LOGIN;
GRANT SELECT ON SCHEMA::lab TO ai_sandbox_user;
DENY SELECT ON lab.CustomerPII TO ai_sandbox_user; -- Denies access to PII data
GO

-- 2. Test execution of AI-suggested code within the Sandbox context
EXECUTE AS USER = 'ai_sandbox_user';
GO

BEGIN TRY
    -- Attempt to run an AI-suggested query on the PII table
    SELECT CustomerID, FullName, SSN FROM lab.CustomerPII;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO NO SANDBOX: ' + ERROR_MESSAGE();
    -- Expected error: "The SELECT permission was denied on the object 'CustomerPII'..."
END CATCH;
GO

REVERT; -- Returns to the original context
GO


-- =================================================================================
-- PART 3: TRACEABILITY AND TAGGING OF AI-GENERATED CODE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - AI TAGGING: Standardized addition of comments in procedure headers (`-- AI-GENERATED: ...`).
--   - EXTENDED EVENTS: Tracking session to audit executed T-SQL statements containing AI markers.

-- 1. Example of traceable Procedure generated via AI suggestion
-- AI-GENERATED: 2026-07-21 | Tool: GitHub Copilot | Reviewer: dev@contoso.com
CREATE OR ALTER PROCEDURE lab.usp_GetSafeCustomerData
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CustomerID, FullName, Email 
    FROM lab.CustomerPII
    WHERE CustomerID = @CustomerID;
END;
GO

-- -- [DP-800 EXAM TIP]
-- 2. Create Extended Events session for auditing AI-generated scripts
IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = 'AuditAIGeneratedSQL')
    DROP EVENT SESSION [AuditAIGeneratedSQL] ON SERVER;
GO

CREATE EVENT SESSION [AuditAIGeneratedSQL]
ON SERVER
ADD EVENT sqlserver.sql_batch_completed (
    WHERE sqlserver.sql_text LIKE N'%AI-GENERATED%'
)
ADD TARGET package0.ring_buffer (SET max_memory = 4096)
WITH (STARTUP_STATE = OFF);
GO


-- =================================================================================
-- PART 4: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: PII Risk Mapping Pipeline before Copilot activation
-- Scans the schema for column names susceptible to leaks before making the workspace available.

SELECT 
    t.TABLE_SCHEMA,
    t.TABLE_NAME,
    c.COLUMN_NAME,
    c.DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS c
JOIN INFORMATION_SCHEMA.TABLES t ON c.TABLE_SCHEMA = t.TABLE_SCHEMA AND c.TABLE_NAME = t.TABLE_NAME
WHERE t.TABLE_TYPE = 'BASE TABLE'
  AND (
        c.COLUMN_NAME LIKE '%ssn%'
     OR c.COLUMN_NAME LIKE '%credit%'
     OR c.COLUMN_NAME LIKE '%password%'
     OR c.COLUMN_NAME LIKE '%salary%'
  )
ORDER BY t.TABLE_SCHEMA, t.TABLE_NAME;
GO
