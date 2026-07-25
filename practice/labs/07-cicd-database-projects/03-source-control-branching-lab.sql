-- =================================================================================
-- DP-800 - HANDS-ON LAB: CODE GOVERNANCE & SCHEMA DRIFT VALIDATION
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to restore the
-- AdventureWorks OLTP database backup available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates change control and schema governance in Git/CI-CD:
--   1. Simulating Breaking Changes in Pull Requests (Adding NOT NULL column without DEFAULT)
--   2. Backward-Compatible Pattern for Pull Requests (Adding NOT NULL with DEFAULT)
--   3. Schema Drift Detection (Untracked manual changes in the repository)
--   4. Structuring CODEOWNERS rules for DBA review
--   5. Practical Project Scenarios (Auditing Objects Modified Outside the CI/CD Pipeline)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.OrdersBranchingTest;
GO

-- Table structure for testing
CREATE TABLE lab.OrdersBranchingTest (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL,
    CreateDate DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
GO

INSERT INTO lab.OrdersBranchingTest (CustomerID, TotalAmount) VALUES (101, 250.00);
GO


-- =================================================================================
-- PART 1: PULL REQUEST VALIDATION - BREAKING CHANGES VS COMPATIBLE PATTERN
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - INCOMPATIBLE: Adding a new `NOT NULL` column to a populated table without supplying a `DEFAULT` value.
--     The DACPAC deploy will fail with `BlockOnPossibleDataLoss=true`.
--   - COMPATIBLE: Adding the `NOT NULL` column together with a `DEFAULT` value (e.g., `DEFAULT 'Pending'`).

-- -- [DP-800 KEY POINT]
-- 1. Example of an Incompatible Change (Commented out as it would break the script):
-- ALTER TABLE lab.OrdersBranchingTest ADD OrderStatus NVARCHAR(20) NOT NULL; -- FAILS!

-- 2. Safe and Backward-Compatible Pattern for PRs:
ALTER TABLE lab.OrdersBranchingTest 
ADD OrderStatus NVARCHAR(20) NOT NULL 
    CONSTRAINT DF_OrdersBranchingTest_OrderStatus DEFAULT N'Pending';
GO

-- Verify that the new column received the default value for pre-existing records
SELECT * FROM lab.OrdersBranchingTest;
GO


-- =================================================================================
-- PART 2: SCHEMA DRIFT DETECTION (UNTRACKED AD-HOC CHANGES)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - SCHEMA DRIFT: Occurs when a developer or DBA runs an `ALTER` directly on the production database
--     without going through Git / DACPAC.
--   - DETECTION: Modification date DMVs (`sys.objects.modify_date`) indicate whether recent changes occurred.

-- -- [DP-800 KEY POINT]
-- Query recently modified objects that may indicate Schema Drift
SELECT 
    name AS NomeObjeto,
    type_desc AS TipoObjeto,
    create_date AS DataCriacao,
    modify_date AS UltimaModificacao
FROM sys.objects
WHERE schema_id = SCHEMA_ID('lab')
  AND DATEDIFF(DAY, modify_date, GETDATE()) <= 1
ORDER BY modify_date DESC;
GO


-- =================================================================================
-- PART 3: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: CODEOWNERS File Model for Database Repository Governance
-- Defines which teams must mandatorily review Pull Requests for schema changes.

SELECT 
    '*.sql' AS MascaraArquivo,
    '@dba-team' AS RevisorObrigatorio,
    'Revisao obrigatoria para qualquer instrucao SQL' AS ObjetivoGovernanca
UNION ALL
SELECT 
    '/src/MyDatabase/Schema/Security/*',
    '@security-team',
    'Aprovacao obrigatoria do time de seguranca para mudancas em roles/permissoes'
UNION ALL
SELECT 
    '/src/MyDatabase/Scripts/*',
    '@senior-dba-team',
    'Aprovacao de DBAs Seniores para scripts Pre/Post Deployment';
GO
