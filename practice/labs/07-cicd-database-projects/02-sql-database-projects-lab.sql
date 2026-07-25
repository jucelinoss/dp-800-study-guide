-- =================================================================================
-- DP-800 - PRACTICAL LAB: SQL DATABASE PROJECTS (.SQLPROJ AND DACPAC ARTIFACTS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates the structure and behavior of declarative deployment of a .sqlproj:
--   1. Difference between Schema Artifact (.dacpac) vs Schema + Data (.bacpac)
--   2. Pre-Deployment Script Pattern (Data Preservation/Migration before DACPAC alter)
--   3. Post-Deployment Script Pattern (Static data loading and permissions after DACPAC)
--   4. Name Refactoring Tracking via Log Table (`__RefactorLog`)
--   5. Practical Project Scenarios (Simulation of Data Loss Protection Actions in CI/CD)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.__RefactorLog;
DROP TABLE IF EXISTS lab.LegacyCustomers;
DROP TABLE IF EXISTS lab.MigratedCustomers;
GO

-- Structure to simulate the SQL Database Projects Refactoring table
CREATE TABLE lab.__RefactorLog (
    OperationKey UNIQUEIDENTIFIER NOT NULL PRIMARY KEY
);

-- Legacy Table Structure for Pre-Deployment Migration Test
CREATE TABLE lab.LegacyCustomers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FullContactName NVARCHAR(100) NOT NULL,
    LegacyCode VARCHAR(20) NULL
);

CREATE TABLE lab.MigratedCustomers (
    CustomerID INT PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Notes NVARCHAR(200) NULL
);
GO

INSERT INTO lab.LegacyCustomers (FullContactName, LegacyCode) VALUES 
('Alice Silva', 'LEG-1001'),
('Bob Santos', 'LEG-1002');
GO


-- =================================================================================
-- PART 1: PRE-DEPLOYMENT SCRIPT PATTERN (PRESERVATION BEFORE ALTERATION)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - PRE-DEPLOYMENT SCRIPT: Executed by SqlPackage BEFORE the DACPAC comparison and application.
--   - TYPICAL USE: Migrate data from columns that will be dropped/renamed to avoid `BlockOnPossibleDataLoss=true` error.

-- -- [DP-800 KEY POINT]
-- Pre-Deployment Script Simulation: Copy data from legacy table before the column is dropped by the DACPAC
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('lab.LegacyCustomers') AND name = 'LegacyCode')
BEGIN
    PRINT 'PRE-DEPLOYMENT: Migrando dados da coluna LegacyCode antes do DACPAC aplicar o DROP...';

    INSERT INTO lab.MigratedCustomers (CustomerID, FirstName, LastName, Notes)
    SELECT 
        CustomerID,
        SUBSTRING(FullContactName, 1, CHARINDEX(' ', FullContactName) - 1),
        SUBSTRING(FullContactName, CHARINDEX(' ', FullContactName) + 1, LEN(FullContactName)),
        CONCAT('Migrado do codigo antigo: ', LegacyCode)
    FROM lab.LegacyCustomers;
END
GO

-- Validate preserved data in Pre-Deployment
SELECT * FROM lab.MigratedCustomers;
GO


-- =================================================================================
-- PART 2: REFACTORLOG AND AVOIDING REPEATED RE-EXECUTIONS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - __RefactorLog: System table maintained by the DACPAC to track object renames via IDE.
--     Prevents SqlPackage from interpreting a rename as a DROP TABLE followed by CREATE TABLE.

-- -- [DP-800 KEY POINT]
DECLARE @RefactorGuid UNIQUEIDENTIFIER = NEWID();

IF NOT EXISTS (SELECT 1 FROM lab.__RefactorLog WHERE OperationKey = @RefactorGuid)
BEGIN
    INSERT INTO lab.__RefactorLog (OperationKey) VALUES (@RefactorGuid);
    PRINT 'REFACTORLOG: Operacao de renomeacao gravada com sucesso.';
END
GO


-- =================================================================================
-- PART 3: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: SqlPackage CLI Parameters Matrix for CI/CD Pipelines
-- Used by data engineers to configure secure DACPAC publishing in staging and production.

SELECT 
    'SqlPackage /Action:Publish' AS ComandoCLI,
    'Deploys da diferença entre DACPAC e banco alvo' AS DescricaoAcao,
    'BlockOnPossibleDataLoss=true' AS ParametroSegurancaCritical,
    'Aborta o deploy se houver DROP de colunas com dados' AS EfeitoParametro
UNION ALL
SELECT 
    'SqlPackage /Action:DeployReport',
    'Gera um relatório XML de alterações sem alterar o banco',
    'TargetFile: drift-report.xml',
    'Usado para aprovação de PRs e validação de Drift'
UNION ALL
SELECT 
    'SqlPackage /Action:Script',
    'Gera o script T-SQL resultante do DACPAC',
    'OutputPath: ./deploy.sql',
    'Recomendado para revisão por DBAs em ambientes estritos';
GO
