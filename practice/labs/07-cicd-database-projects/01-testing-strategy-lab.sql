-- =================================================================================
-- DP-800 - LAB: TESTING STRATEGY AND REFERENCE DATA (TSQLT AND MERGE)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates unit testing strategies and reference data loading:
--   1. Environment Preparation for tSQLt (CLR and TRUSTWORTHY Configuration)
--   2. Test Class Structuring and Stored Procedure Unit Tests
--   3. Isolation with FakeTable, AssertEquals, and Expected Exceptions (ExpectException)
--   4. Idempotent Reference Data Loading with the MERGE Statement
--   5. Practical Project Scenarios (Domain Table Loading in Post-Deployment Scripts)
-- =================================================================================

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
--   - PREREQUISITES: Requires enabling `clr enabled = 1` and `TRUSTWORTHY ON` on the database.

-- -- [DP-800 KEY POINT]
-- 1. Enable CLR execution in SQL Server
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;
GO

-- 2. Enable TRUSTWORTHY property in the database
ALTER DATABASE AdventureWorks2025 SET TRUSTWORTHY ON;
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
        THROW 50002, 'Desconto maximo permitido e de 50%.', 1;

    SET @FinalAmount = @TotalAmount * (1.0 - (@DiscountPercent / 100.0));
END;
GO

-- Simulated Unit Test: Valid Discount Validation
DECLARE @ResultadoCalculado DECIMAL(18,2);
EXEC lab.usp_CalculateDiscountedTotal 
    @TotalAmount = 100.00, 
    @DiscountPercent = 10.00, 
    @FinalAmount = @ResultadoCalculado OUTPUT;

IF @ResultadoCalculado = 90.00
    PRINT 'TESTE PASSOU: Desconto calculado corretamente (90.00).';
ELSE
    PRINT 'TESTE FALHOU: Valor incorreto retornado.';
GO

-- -- [DP-800 KEY POINT]
-- Simulated Unit Test: Exception Validation When Exceeding Maximum Discount
BEGIN TRY
    EXEC lab.usp_CalculateDiscountedTotal 
        @TotalAmount = 100.00, 
        @DiscountPercent = 60.00, 
        @FinalAmount = NULL;
END TRY
BEGIN CATCH
    PRINT 'TESTE PASSOU: Capturou excecao esperada -> ' + ERROR_MESSAGE();
END CATCH;
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
