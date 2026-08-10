-- =================================================================================
-- DP-800 - PRACTICAL LAB: OBJECT-LEVEL PERMISSIONS AND SECURE ACCESS (RBAC / IMPERSONATION)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/05-data-security-compliance/03-permissions-access.md
--    Open the theory guide alongside this lab for conceptual context.
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates permission management, access control, and context:
--   1. Permission Hierarchy: GRANT, DENY, and the Precedence Rule (DENY always wins)
--   2. Difference between REVOKE and DENY (REVOKE only removes the explicit grant)
--   3. Custom Roles (RBAC) and Contained Database Users
--   4. Context Impersonation with `EXECUTE AS USER` and `REVERT`
--   5. Ownership Chaining and solution for breaks with `WITH EXECUTE AS OWNER`
--   6. Practical Project Scenarios (Effective Permission Audit via sys.fn_my_permissions)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
-- WARNING: this lab creates users, roles, and a procedure with impersonation.
-- Run in a disposable database and review the permissions before reusing the pattern.
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_GetSalaryReport' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_GetSalaryReport;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'JuniorAnalyst')
    DROP USER JuniorAnalyst;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'FinancialRole')
    DROP ROLE FinancialRole;

DROP TABLE IF EXISTS lab.SalaryData;
GO

-- Create Test Table
CREATE TABLE lab.SalaryData (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeName NVARCHAR(100) NOT NULL,
    Salary DECIMAL(18,2) NOT NULL
);
GO

INSERT INTO lab.SalaryData (EmployeeName, Salary) VALUES 
('Alice Smith', 12000.00),
('Bob Jones', 8500.00);
GO


-- =================================================================================
-- PART 1: PRECEDENCE RULES (DENY VS GRANT AND THE ROLE OF REVOKE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DENY OVERRIDES GRANT: If a user receives `GRANT` directly or through a role, but receives an explicit `DENY`, access is BLOCKED.
--   - REVOKE IS NOT DENY: `REVOKE` only removes the previous grant. If the user inherits access through a role, they will still have access!

-- 1. Create Financial Role and User
CREATE ROLE FinancialRole;
GRANT SELECT ON lab.SalaryData TO FinancialRole;

CREATE USER JuniorAnalyst WITHOUT LOGIN;
ALTER ROLE FinancialRole ADD MEMBER JuniorAnalyst;
GO

-- Optional contained-user exercise (SQL Server with contained authentication enabled):
-- CREATE USER LabContainedUser WITH PASSWORD = '<REPLACE_WITH_UNIQUE_LAB_PASSWORD>';
-- ALTER ROLE FinancialRole ADD MEMBER LabContainedUser;

-- Azure SQL Managed Identity exercise (run as Microsoft Entra administrator):
-- CREATE USER [my-app-service] FROM EXTERNAL PROVIDER;
-- ALTER ROLE FinancialRole ADD MEMBER [my-app-service];
GO

-- -- [DP-800 EXAM TIP]
-- 2. Grant explicit DENY on the user (Overrides the inherited Role permission)
DENY SELECT ON lab.SalaryData TO JuniorAnalyst;
GO

-- 3. Test access (Failure expected due to DENY)
EXECUTE AS USER = 'JuniorAnalyst';
GO

BEGIN TRY
    SELECT * FROM lab.SalaryData;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO DENY PRECEDENCE: ' + ERROR_MESSAGE();
    -- Error: "The SELECT permission was denied on the object 'SalaryData'..."
END CATCH;
GO

REVERT;
GO

-- 4. Test REVOKE (Removes the explicit DENY from the user, allowing them to inherit the GRANT from the Role again)
REVOKE DENY SELECT ON lab.SalaryData FROM JuniorAnalyst;
GO

EXECUTE AS USER = 'JuniorAnalyst';
GO

-- Now the query works because the DENY was removed via REVOKE
SELECT EmployeeID, EmployeeName FROM lab.SalaryData;
GO

REVERT;
GO


-- =================================================================================
-- PART 2: OWNERSHIP CHAINING AND EXECUTE AS OWNER
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - OWNERSHIP CHAINING (Intact Chain): When the Procedure and Table have the same owner (`dbo`), SQL Server
--     does NOT check SELECT permissions on the table for the Procedure executor.
--   - BROKEN CHAIN: If the table and procedure have different owners/schema owners, the chain breaks.
--   - SOLUTION: Declare the procedure with `WITH EXECUTE AS OWNER`.

-- Remove the direct SELECT permission on the table from the user
REVOKE SELECT ON lab.SalaryData FROM FinancialRole;
REVOKE SELECT ON lab.SalaryData FROM JuniorAnalyst;
GO

-- -- [DP-800 EXAM TIP]
-- Procedure with EXECUTE AS OWNER to encapsulate access to the restricted table.
-- WARNING: OWNER can be highly privileged; prefer a narrowly scoped execution
-- context or ownership chaining when it satisfies the requirement.
CREATE PROCEDURE lab.usp_GetSalaryReport
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT EmployeeID, EmployeeName, Salary FROM lab.SalaryData;
END;
GO

GRANT EXECUTE ON lab.usp_GetSalaryReport TO JuniorAnalyst;
GO

-- The user successfully executes the Procedure without having direct SELECT access on the table
EXECUTE AS USER = 'JuniorAnalyst';
GO

EXEC lab.usp_GetSalaryReport;
GO

REVERT;
GO


-- =================================================================================
-- PART 3: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Query Logged-in User's Effective Permissions Audit
-- Uses the sys.fn_my_permissions system function to map all active privileges.

EXECUTE AS USER = 'JuniorAnalyst';
GO

SELECT * FROM sys.fn_my_permissions('lab.SalaryData', 'OBJECT');
SELECT * FROM sys.fn_my_permissions('lab.usp_GetSalaryReport', 'OBJECT');
GO

REVERT;
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/05-data-security-compliance/03-permissions-access.md
-- =================================================================================================
