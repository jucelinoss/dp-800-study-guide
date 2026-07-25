-- =================================================================================
-- DP-800 - HANDS-ON LAB: DATABASE AUDITING (SQL AUDIT AND SPECIFICATIONS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates native SQL Server audit configuration:
--   1. Creating Server Audit with file specifications and failure handling (ON_FAILURE)
--   2. Creating Database Audit Specification with action groups (BATCH_COMPLETED_GROUP)
--   3. Reading and analyzing audit logs via `sys.fn_get_audit_file`
--   4. Using Custom User Audits via `sp_audit_write`
--   5. Practical Project Scenarios (Query Tracking on Salary Tables and Compliance Auditing)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.database_audit_specifications WHERE name = 'LabDatabaseAuditSpec')
    ALTER DATABASE AUDIT SPECIFICATION LabDatabaseAuditSpec WITH (STATE = OFF);

IF EXISTS (SELECT * FROM sys.database_audit_specifications WHERE name = 'LabDatabaseAuditSpec')
    DROP DATABASE AUDIT SPECIFICATION LabDatabaseAuditSpec;

IF EXISTS (SELECT * FROM sys.server_audits WHERE name = 'LabServerAudit')
    ALTER SERVER AUDIT LabServerAudit WITH (STATE = OFF);

IF EXISTS (SELECT * FROM sys.server_audits WHERE name = 'LabServerAudit')
    DROP SERVER AUDIT LabServerAudit;

DROP TABLE IF EXISTS lab.AuditTestTable;
GO

-- Table Structure for Testing
CREATE TABLE lab.AuditTestTable (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    DataValue NVARCHAR(100) NOT NULL
);
GO


-- =================================================================================
-- PART 1: CREATING SERVER AUDIT AND DATABASE AUDIT SPECIFICATION
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - SERVER AUDIT: Defines WHERE audit records will be saved (File, Windows Event Log, etc).
--   - ON_FAILURE: `CONTINUE` (allows continuation if logging fails - prioritizes availability) or `SHUTDOWN` (shuts down SQL Server - prioritizes security).
--   - BATCH_COMPLETED_GROUP: The critical action group for capturing the full text of SQL statements (including SELECTs).

-- -- [DP-800 EXAM TIP]
-- 1. Create Server Audit writing to a directory (or using Application Log)
CREATE SERVER AUDIT LabServerAudit
TO APPLICATION_LOG -- Using Application Log for portability in lab tests
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
GO

-- Enable the Server Audit
ALTER SERVER AUDIT LabServerAudit WITH (STATE = ON);
GO

-- 2. Create Database Audit Specification to capture SELECT and DML on the test table
CREATE DATABASE AUDIT SPECIFICATION LabDatabaseAuditSpec
FOR SERVER AUDIT LabServerAudit
ADD (SELECT, INSERT, UPDATE, DELETE ON lab.AuditTestTable BY PUBLIC),
ADD (USER_DEFINED_AUDIT_GROUP) -- Allows registering custom events via sp_audit_write
WITH (STATE = ON);
GO


-- =================================================================================
-- PART 2: SIMULATION OF AUDIT EVENTS AND CUSTOM REGISTRATION
-- =================================================================================

-- 1. Execute monitored operations
INSERT INTO lab.AuditTestTable (DataValue) VALUES ('Teste Audit 1'), ('Teste Audit 2');
SELECT * FROM lab.AuditTestTable;
GO

-- -- [DP-800 EXAM TIP]
-- 2. Register custom developer event via sp_audit_write
EXEC sp_audit_write 
    @user_defined_id = 50001,
    @succeeded = 1,
    @user_defined_message = N'Ação critica de exportacao executada pela aplicacao.';
GO


-- =================================================================================
-- PART 3: READING AND QUERYING AUDIT LOGS VIA SYS.FN_GET_AUDIT_FILE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - sys.fn_get_audit_file: Table function used to read `.sqlaudit` log files.
--   - In Azure SQL environments writing to Storage Account or Log Analytics, queries use KQL (Kusto Query Language).

-- Conceptual example of reading logs from disk
SELECT 
    event_time,
    action_id,
    succeeded,
    session_server_principal_name AS LoginUsuario,
    database_name AS BancoDados,
    object_name AS ObjetoAcessado,
    statement AS TextoConsultaSQL
FROM sys.fn_get_audit_file('C:\AuditLogs\*.sqlaudit', DEFAULT, DEFAULT)
ORDER BY event_time DESC;
GO


-- =================================================================================
-- PART 4: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Inspecting Active Audit Specifications on the Server
-- Used by security consultants and auditors to validate compliance coverage (GDPR/LGPD).

SELECT 
    sa.name AS ServerAuditName,
    sa.status_desc AS StatusAuditoria,
    sa.audit_destination_desc AS DestinoLogs,
    das.name AS DatabaseSpecName,
    das.is_state_enabled AS EspecificacaoAtiva
FROM sys.server_audits sa
LEFT JOIN sys.database_audit_specifications das ON sa.server_audit_guid = das.server_audit_guid;
GO
