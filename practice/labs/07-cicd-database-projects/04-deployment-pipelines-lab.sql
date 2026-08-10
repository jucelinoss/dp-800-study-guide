-- =================================================================================
-- DP-800 - HANDS-ON LAB: DEPLOYMENT PIPELINES AND SQLPACKAGE CLI COMMANDS
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and the other lab scripts, restore the AdventureWorks
-- (OLTP) database backup available at:
-- https://learn.microsoft.com/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates SQL Server CI/CD pipeline behavior and automation:
--   1. SqlPackage CLI actions (/Action:Publish, /Action:Extract, /Action:Export, /Action:DeployReport)
--   2. A comparison of environment-specific safety switches (Dev, Staging, and Production)
--   3. Schema-drift diagnostics using SqlPackage XML reports
--   4. Passwordless pipeline authentication using Managed Identity and Azure Key Vault
--   5. Practical design scenarios (simulated pipeline execution with deployment transactions)
-- NOTE: this is a SQL-oriented simulation. CLI commands and Key Vault access must
-- run on a pipeline/runner, not inside SSMS.
-- =================================================================================

-- NOTE: Theory content for this chapter is available at:
--       ../../../certification/07-cicd-database-projects/04-deployment-pipelines.md

USE AdventureWorks2025;
GO

-- PART 4: REFERENCE DEPLOYMENT GATES
-- This is a safety sequence, not an engine-enforced workflow. It makes the
-- ordering questions in the exam concrete: validate before a production change.
SELECT 1 AS StepNumber, N'Commit and branch-policy validation' AS GateName,
       N'Source-controlled project change' AS Evidence
UNION ALL SELECT 2, N'Build and validate DACPAC', N'Build output and model validation'
UNION ALL SELECT 3, N'Run tests and drift/deploy reports', N'Automated test and report artifacts'
UNION ALL SELECT 4, N'Review script and approvals', N'Data-loss review and human approval'
UNION ALL SELECT 5, N'Deploy and monitor', N'Controlled environment and deployment history';
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.PipelineDeployHistory;
GO

-- Structure for recording CI/CD deployment history
CREATE TABLE lab.PipelineDeployHistory (
    DeployID INT IDENTITY(1,1) PRIMARY KEY,
    EnvironmentName NVARCHAR(50) NOT NULL,
    DacpacVersion NVARCHAR(20) NOT NULL,
    DeployedBy NVARCHAR(100) NOT NULL DEFAULT SUSER_SNAME(),
    DeployDate DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
GO


-- =================================================================================
-- PART 1: SQLPACKAGE CLI ACTIONS AND SWITCHES
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - /Action:Publish: Applies the DACPAC desired state by calculating and running the delta against the target database.
--   - /Action:Extract: Creates a schema-only .dacpac file from an existing database.
--   - /Action:Export: Creates a schema-and-data .bacpac file for migration or import.
--   - /Action:DeployReport: Creates an XML change report without modifying the database (ideal for drift detection).
--   - /p:IncludeTransactionalScripts=true: Requests transactions during deployment
--     when possible; it does not guarantee one transaction for every operation/script.

-- [DP-800 EXAM TIP]
-- Simulate a post-publication record insertion by the pipeline
INSERT INTO lab.PipelineDeployHistory (EnvironmentName, DacpacVersion)
VALUES ('Production', 'v1.2.0');
GO

-- Query publication history
SELECT * FROM lab.PipelineDeployHistory;
GO


-- =================================================================================
-- PART 2: ENVIRONMENT-SPECIFIC DEPLOYMENT CONFIGURATION MATRIX
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DEVELOPMENT: Permissive. `/p:BlockOnPossibleDataLoss=false`, `/p:DropObjectsNotInSource=true`.
--   - STAGING: Moderate. `/p:BlockOnPossibleDataLoss=true`, `/p:DropObjectsNotInSource=false`.
--   - PRODUCTION: Strict. `/p:BlockOnPossibleDataLoss=true`, `/p:IncludeTransactionalScripts=true`, `/p:GenerateSmartDefaults=true`.

-- [DP-800 EXAM TIP]
-- Sample configuration matrix for the exam
SELECT 
    'Desenvolvimento' AS Ambiente,
    '/p:BlockOnPossibleDataLoss=false /p:DropObjectsNotInSource=true' AS FlagsSqlPackage,
    'Permite recriação e perda de dados de teste' AS Justificativa
UNION ALL
SELECT 
    'Staging / UAT',
    '/p:BlockOnPossibleDataLoss=true /p:DropObjectsNotInSource=false',
    'Bloqueia perda acidental e valida dados legados'
UNION ALL
SELECT 
    'Produção',
    '/p:BlockOnPossibleDataLoss=true /p:IncludeTransactionalScripts=true /p:GenerateSmartDefaults=true',
    'Garante rollback transacional em falhas e exige defaults para NOT NULL';
GO


-- =================================================================================
-- PART 3: PRACTICAL DESIGN SCENARIOS
-- =================================================================================

-- SCENARIO 1: CLI script template for DACPAC publishing through Azure Pipelines / GitHub Actions
-- Example of the exact command run in a runner task.

/*
# Run the publication to the Production environment through a PowerShell / Bash runner:
sqlpackage /Action:Publish \
    /SourceFile:./bin/Release/AdventureWorks2025.dacpac \
    /TargetConnectionString:"Server=tcp:sql-prod.database.windows.net,1433;Initial Catalog=AdventureWorks2025;Authentication=Active Directory Managed Identity;" \
    /p:BlockOnPossibleDataLoss=true \
    /p:IncludeTransactionalScripts=true \
    /p:GenerateSmartDefaults=true
*/
GO

-- =================================================================================================
-- THEORY REFERENCE: ../../../certification/07-cicd-database-projects/04-deployment-pipelines.md
-- =================================================================================================
