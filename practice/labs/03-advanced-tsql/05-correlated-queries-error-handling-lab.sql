-- =================================================================================
-- DP-800 - PRACTICE LAB: CORRELATED SUBQUERIES AND ADVANCED ERROR HANDLING
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates correlated subqueries and error resilience patterns:
--   1. Correlated Subqueries and the NOT IN NULL Trap (vs NOT EXISTS)
--   2. Safe Data Conversion with TRY_CONVERT and TRY_PARSE (Validation without CATCH)
--   3. Impact of SET XACT_ABORT ON and Doomed Transaction Diagnosis (XACT_STATE = -1)
--   4. Nested Transactions, @@TRANCOUNT and Savepoints (SAVE TRANSACTION)
--   5. Practical Project Scenarios (Batch Financial Procedure with Savepoints and Partial Rollback)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ProcessBatchWithSavepoints' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_ProcessBatchWithSavepoints;

DROP TABLE IF EXISTS lab.StagingData;
DROP TABLE IF EXISTS lab.LedgerEntries;
DROP TABLE IF EXISTS lab.Accounts;
GO

-- Table Structure for Testing
CREATE TABLE lab.Accounts (
    AccountID INT PRIMARY KEY,
    AccountHolder NVARCHAR(100) NOT NULL,
    Status NVARCHAR(20) NOT NULL DEFAULT 'Active'
);

CREATE TABLE lab.LedgerEntries (
    EntryID INT IDENTITY(1,1) PRIMARY KEY,
    AccountID INT NULL, -- Allows NULL to test the NOT IN trap
    Amount DECIMAL(18,2) NOT NULL
);

CREATE TABLE lab.StagingData (
    RawID INT IDENTITY(1,1) PRIMARY KEY,
    RawValue NVARCHAR(50) NOT NULL
);
GO


-- =================================================================================
-- PART 1: CORRELATED SUBQUERIES AND THE NOT IN NULL TRAP
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CORRELATED SUBQUERY: A subquery that references a column from the outer query (executed per outer row).
--   - NOT IN TRAP: If the subquery result set for `NOT IN` contains ANY NULL value,
--     the boolean comparison evaluates to `UNKNOWN` for ALL rows, causing SQL Server to return ZERO rows!
--   - RECOMMENDATION: Always use `NOT EXISTS` instead of `NOT IN`, because `NOT EXISTS` handles NULLs correctly.

INSERT INTO lab.Accounts (AccountID, AccountHolder, Status) VALUES (1, 'Alice', 'Active'), (2, 'Bob', 'Inactive'), (3, 'Charlie', 'Active');
INSERT INTO lab.LedgerEntries (AccountID, Amount) VALUES (1, 100.00), (NULL, 50.00); -- Includes a NULL record
GO

-- -- [DP-800 EXAM TIP]
-- 1. NOT IN test with NULL in the result set -> RETURNS ZERO ROWS! (Expected incorrect behavior)
SELECT AccountID, AccountHolder
FROM lab.Accounts
WHERE AccountID NOT IN (SELECT AccountID FROM lab.LedgerEntries);
-- ^ Returns 0 rows because of the NULL recorded in LedgerEntries!

-- 2. Test with NOT EXISTS -> RETURNS THE CORRECT ACCOUNTS (Resilient to NULLs)
SELECT a.AccountID, a.AccountHolder
FROM lab.Accounts a
WHERE NOT EXISTS (
    SELECT 1 FROM lab.LedgerEntries l 
    WHERE l.AccountID = a.AccountID
);
GO


-- =================================================================================
-- PART 2: SAFE DATA CONVERSION (TRY_CONVERT AND TRY_PARSE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - TRY_CONVERT / TRY_CAST: Attempts to convert the data type. On failure, returns `NULL` without stopping execution or raising exceptions.
--   - Avoids wrapping every raw data import row in TRY/CATCH blocks.

INSERT INTO lab.StagingData (RawValue) VALUES ('100'), ('200'), ('TEXTO_INVALIDO'), ('2025-01-01');
GO

-- Filter only rows with valid integers without generating a conversion error
SELECT 
    RawID, 
    RawValue, 
    TRY_CONVERT(INT, RawValue) AS ValorInteiroConvertido
FROM lab.StagingData
WHERE TRY_CONVERT(INT, RawValue) IS NOT NULL;
GO


-- =================================================================================
-- PART 3: IMPACT OF SET XACT_ABORT ON AND XACT_STATE()
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - SET XACT_ABORT ON: For many execution errors, terminates and rolls back the entire transaction.
--     Still, check XACT_STATE() in the CATCH block; the observed state depends on the error and context.
--   - XACT_STATE() = -1: Indicates a "Doomed Transaction". SQL Server forbids COMMIT
--     and requires the developer to execute a `ROLLBACK`.

-- -- [DP-800 EXAM TIP]
BEGIN TRY
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    INSERT INTO lab.Accounts (AccountID, AccountHolder) VALUES (10, 'Conta Teste');
    
    -- Insertion that will cause a Duplicate Primary Key error
    INSERT INTO lab.Accounts (AccountID, AccountHolder) VALUES (10, 'Conta Duplicada');

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    PRINT 'ENTROU NO CATCH. Estado da Transação (XACT_STATE): ' + CAST(XACT_STATE() AS VARCHAR(10));
    
    IF XACT_STATE() <> 0
    BEGIN
        PRINT 'Existe uma transação ativa; executando ROLLBACK...';
        ROLLBACK TRANSACTION;
    END
END CATCH;
GO


-- =================================================================================
-- PART 4: NESTED TRANSACTIONS AND SAVEPOINTS (SAVE TRANSACTION)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - SAVE TRANSACTION SavePointName: Creates a savepoint within the transaction.
--   - ROLLBACK TRANSACTION SavePointName: Undoes changes made AFTER the savepoint without canceling the outer parent transaction.
--   - @@TRANCOUNT: Count of active transactions.

BEGIN TRANSACTION; -- @@TRANCOUNT = 1
    INSERT INTO lab.Accounts (AccountID, AccountHolder) VALUES (100, 'Cliente Raiz');
    
    SAVE TRANSACTION PontoSalvamento1; -- Creates Savepoint
    
    INSERT INTO lab.Accounts (AccountID, AccountHolder) VALUES (101, 'Cliente Provisório');
    
    -- Undoes only the insertion of the provisional client
    ROLLBACK TRANSACTION PontoSalvamento1;
    
COMMIT TRANSACTION; -- @@TRANCOUNT goes back to 0. Root Client (100) is kept!
GO

-- Verify result: Only Client 100 was kept
SELECT * FROM lab.Accounts WHERE AccountID IN (100, 101);
GO


-- =================================================================================
-- PART 5: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Batch Processing with Savepoint Handling in a Stored Procedure
-- Allows processing individual items by saving valid ones and reverting individual failed items via Savepoint.

CREATE PROCEDURE lab.usp_ProcessBatchWithSavepoints
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TranCount INT = @@TRANCOUNT;

    IF @TranCount = 0
        BEGIN TRANSACTION;
    ELSE
        SAVE TRANSACTION SP_BatchProc;

    BEGIN TRY
        -- Batch operations...
        UPDATE lab.Accounts SET Status = 'Active' WHERE Status = 'Inactive';
        
        IF @TranCount = 0
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        -- A doomed transaction cannot roll back to a savepoint; it requires a full rollback.
        IF XACT_STATE() = -1
            ROLLBACK TRANSACTION;
        ELSE IF @TranCount = 0 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        ELSE IF @TranCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION SP_BatchProc;

        THROW;
    END CATCH;
END;
GO
