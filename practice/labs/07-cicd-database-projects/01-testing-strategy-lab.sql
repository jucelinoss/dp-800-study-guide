-- =================================================================================
-- DP-800 - LAB: TESTING STRATEGY AND REFERENCE DATA (TSQLT AND MERGE)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates unit testing strategies and reference data loading:
--   1. Environment Preparation for tSQLt (CLR configuration)
--   2. A real tSQLt test class
--   3. Isolation with FakeTable, AssertEquals, and ExpectException
--   4. Idempotent Reference Data Loading with the MERGE Statement
--   5. Practical Project Scenarios (Domain Table Loading in Post-Deployment Scripts)
-- =================================================================================

-- NOTE: Theory content for this chapter is available at:
--       ../../../certification/07-cicd-database-projects/01-testing-strategy.md

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.ReferenceOrderStatus;
DROP TABLE IF EXISTS lab.TestOrders;
GO

-- Table structure for testing
CREATE TABLE lab.ReferenceOrderStatus (
    StatusID INT PRIMARY KEY,
    StatusName NVARCHAR(50) NOT NULL,
    Description NVARCHAR(200) NULL
);

CREATE TABLE lab.TestOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL,
    StatusID INT NOT NULL
);
GO


-- =================================================================================
-- PART 1: PREREQUISITES AND PREPARATION FOR THE TSQLT FRAMEWORK
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - tSQLt: Native T-SQL unit testing framework.
--   - ISOLATION: All tSQLt tests run inside transactions that are automatically rolled back at the end!
--   - PREREQUISITES: Requires `clr enabled = 1` and installation/trust of the tSQLt
--     assembly according to the official documentation. TRUSTWORTHY is not enabled here.

-- -- [DP-800 KEY POINT]
-- 1. Enable CLR execution in SQL Server
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;
GO

-- Install tSQLt before continuing:
-- https://tsqlt.org/download/
IF OBJECT_ID(N'tSQLt.Run') IS NULL
    THROW 51010, 'tSQLt is not installed in this database. Install the framework and run again.', 1;
GO


-- =================================================================================
-- PART 2: UNIT TEST STRUCTURE SIMULATION (ISOLATION AND ASSERTION)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - tSQLt.FakeTable: Replaces a real table with an empty copy without constraints or foreign keys.
--     This isolates the unit under test, preventing cascading failures due to data dependencies.
--   - tSQLt.AssertEquals: Validates that the obtained result is identical to the expected value.

-- Example procedure under test
CREATE OR ALTER PROCEDURE lab.usp_CalculateDiscountedTotal
    @TotalAmount DECIMAL(18,2),
    @DiscountPercent DECIMAL(5,2),
    @FinalAmount DECIMAL(18,2) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @DiscountPercent > 50.00
        THROW 50002, 'Maximum discount is 50%.', 1;

    SET @FinalAmount = @TotalAmount * (1.0 - (@DiscountPercent / 100.0));
END;
GO

-- Create a tSQLt test class. The IF makes repeated runs safe.
IF SCHEMA_ID(N'labDiscountTests') IS NULL
    EXEC tSQLt.NewTestClass N'labDiscountTests';
GO

CREATE OR ALTER PROCEDURE [labDiscountTests].[test valid discount returns 90]
AS
BEGIN
    DECLARE @CalculatedResult DECIMAL(18,2);

    EXEC lab.usp_CalculateDiscountedTotal
        @TotalAmount = 100.00,
        @DiscountPercent = 10.00,
        @FinalAmount = @CalculatedResult OUTPUT;

    EXEC tSQLt.AssertEquals 90.00, @CalculatedResult;
END;
GO

CREATE OR ALTER PROCEDURE [labDiscountTests].[test discount above limit raises exception]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExpectedMessagePattern = N'%Maximum discount%';

    EXEC lab.usp_CalculateDiscountedTotal
        @TotalAmount = 100.00,
        @DiscountPercent = 60.00,
        @FinalAmount = NULL;
END;
GO

-- Run the real tests. tSQLt automatically rolls back each test case.
EXEC tSQLt.Run N'labDiscountTests';
GO


-- =================================================================================
-- PART 3: IDEMPOTENT REFERENCE DATA LOADING WITH MERGE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - STATIC / REFERENCE DATA: Domain tables (e.g., Status, Countries, Currencies) must be maintained via versioned script.
--   - MERGE PATTERN: Guarantees idempotency. Can be re-executed N times in Post-Deployment without duplication or failure.

-- -- [DP-800 KEY POINT]
-- Idempotent Order Status Loading via MERGE
MERGE INTO lab.ReferenceOrderStatus AS Target
USING (VALUES
    (1, N'Pendente',   N'Pedido recebido aguardando pagamento'),
    (2, N'Processando', N'Pagamento aprovado em separacao'),
    (3, N'Enviado',     N'Pedido entregue a transportadora'),
    (4, N'Concluido',   N'Pedido entregue ao cliente final')
) AS Source (StatusID, StatusName, Description)
ON Target.StatusID = Source.StatusID
WHEN MATCHED THEN
    UPDATE SET 
        Target.StatusName = Source.StatusName,
        Target.Description = Source.Description
WHEN NOT MATCHED BY TARGET THEN
    INSERT (StatusID, StatusName, Description)
    VALUES (Source.StatusID, Source.StatusName, Source.Description);
GO

-- Verify idempotent load result
SELECT * FROM lab.ReferenceOrderStatus;
GO


-- =================================================================================
-- PART 4: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Structuring Post-Deployment Scripts for CI/CD Pipelines
-- Simulates the automation script executed after DACPAC publication to update reference data.

PRINT 'Iniciando execucao de Post-Deployment scripts...';
PRINT 'Carga de tabelas de dominio finalizada com sucesso.';
GO

-- =================================================================================================
-- THEORY REFERENCE: ../../../certification/07-cicd-database-projects/01-testing-strategy.md
-- =================================================================================================
