-- ====================================================================
-- DP-800 Study Guide — Lab 08: Integrity Rules
-- Database: AdventureWorks2025
-- Purpose: FK violations, UNIQUE, CHECK, DEFAULT behavior, ON DELETE
-- Prerequisite: Labs 01-07 (DML patterns)
-- ====================================================================

-- THEORY REFERENCE: ../../../certification/00-fundamentals/08-integrity-rules.md
--    Open the theory guide alongside this lab for conceptual context.

-- Create lab schema if it doesn't exist (idempotent)
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'lab')
    EXEC ('CREATE SCHEMA lab');
GO

-- ====================================================================
-- FK violation with TRY/CATCH
-- KEY CONCEPT: A FOREIGN KEY prevents inserting a child row when the
-- parent key doesn't exist. Error 547 is raised.
-- ====================================================================
-- This succeeds because CustomerID 1 exists
SELECT CustomerID, AccountNumber FROM Sales.Customer WHERE CustomerID = 1;

BEGIN TRY
    -- This will FAIL because CustomerID 99999 doesn't exist
    INSERT INTO Sales.SalesOrderHeader (
        RevisionNumber, OrderDate, DueDate, ShipDate,
        CustomerID, BillToAddressID, ShipToAddressID,
        ShipMethodID
    )
    VALUES (
        1, GETDATE(), GETDATE(), GETDATE(),
        99999, 1, 1, 1
    );
END TRY
BEGIN CATCH
    PRINT 'EXPECTED FK ERROR: ' + ERROR_MESSAGE();
    PRINT 'ERROR_NUMBER: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10));
    -- 547 = foreign key violation
END CATCH;
GO

-- [OBSERVE] The TRY/CATCH block prevents the error from stopping
-- the script. In production, you would handle this gracefully.

-- ====================================================================
-- UNIQUE constraint violation
-- KEY CONCEPT: A UNIQUE constraint rejects duplicate non-null values.
-- One NULL is allowed per column in SQL Server.
-- ====================================================================
CREATE TABLE #TestUnique (
    Email NVARCHAR(100) NOT NULL UNIQUE
);

INSERT INTO #TestUnique (Email) VALUES (N'test@example.com');

BEGIN TRY
    INSERT INTO #TestUnique (Email) VALUES (N'test@example.com');
END TRY
BEGIN CATCH
    PRINT 'UNIQUE VIOLATION: ' + ERROR_MESSAGE();
    PRINT 'ERROR_NUMBER: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10));
    -- 2627 = unique constraint violation
END CATCH;
GO

-- Test NULL behavior: only ONE NULL allowed
CREATE TABLE #TestNullUnique (Val INT NULL UNIQUE);
INSERT INTO #TestNullUnique (Val) VALUES (NULL);  -- succeeds (first NULL)
BEGIN TRY
    INSERT INTO #TestNullUnique (Val) VALUES (NULL);  -- fails (second NULL)
END TRY
BEGIN CATCH
    PRINT 'Second NULL rejected by UNIQUE: ' + ERROR_MESSAGE();
END CATCH;

DROP TABLE #TestUnique;
DROP TABLE #TestNullUnique;
GO

-- ====================================================================
-- CHECK constraint violation
-- KEY CONCEPT: CHECK rejects values where the predicate evaluates to FALSE.
-- ====================================================================
CREATE TABLE #TestCheck (
    ProductName NVARCHAR(100) NOT NULL,
    ListPrice   DECIMAL(10,2) NOT NULL CHECK (ListPrice >= 0)
);

-- This succeeds
INSERT INTO #TestCheck (ProductName, ListPrice) VALUES (N'Valid Product', 19.99);

BEGIN TRY
    -- This fails: negative price
    INSERT INTO #TestCheck (ProductName, ListPrice) VALUES (N'Bad Product', -5.00);
END TRY
BEGIN CATCH
    PRINT 'CHECK VIOLATION: ' + ERROR_MESSAGE();
END CATCH;

DROP TABLE #TestCheck;
GO

-- ====================================================================
-- CHECK + NULL behavior (UNKNOWN != FALSE)
-- KEY CONCEPT: A CHECK passes when the predicate is TRUE or UNKNOWN.
-- NULL comparison yields UNKNOWN, so NULL passes CHECK.
-- ====================================================================
CREATE TABLE #TestCheckNull (
    Val DECIMAL(10,2) NULL CHECK (Val >= 0)
);

-- This passes because NULL >= 0 is UNKNOWN, not FALSE
INSERT INTO #TestCheckNull (Val) VALUES (NULL);
PRINT 'NULL passed CHECK (UNKNOWN != FALSE)';

BEGIN TRY
    INSERT INTO #TestCheckNull (Val) VALUES (-5.00);
END TRY
BEGIN CATCH
    PRINT 'CHECK VIOLATION: ' + ERROR_MESSAGE();
END CATCH;

DROP TABLE #TestCheckNull;
GO

-- ====================================================================
-- DEFAULT vs INSERT NULL
-- KEY CONCEPT: DEFAULT fires only when the column is OMITTED from
-- the INSERT column list. Explicitly passing NULL inserts NULL.
-- ====================================================================
CREATE TABLE #TestDefault (
    Id        INT IDENTITY(1,1) PRIMARY KEY,
    Status    NVARCHAR(20) NOT NULL DEFAULT (N'Active'),
    CreatedAt DATETIME2 NOT NULL DEFAULT (SYSDATETIME())
);

-- Omit Status and CreatedAt — both use DEFAULT
INSERT INTO #TestDefault (Id) VALUES (DEFAULT);  -- uses IDENTITY default
PRINT 'Insert 1: Status and CreatedAt used defaults.';

-- Explicitly insert NULL into a NOT NULL column — will FAIL
-- INSERT INTO #TestDefault (Status) VALUES (NULL);  -- uncomment to see error

-- Insert with explicit non-null value (default is NOT used)
INSERT INTO #TestDefault (Status, CreatedAt) VALUES (N'Inactive', '2026-01-01');
PRINT 'Insert 2: explicit values used, defaults ignored.';

SELECT * FROM #TestDefault;
DROP TABLE #TestDefault;
GO

-- ====================================================================
-- ON DELETE CASCADE (conceptual — lab table)
-- KEY CONCEPT: CASCADE automatically deletes child rows when the parent
-- is deleted. Use carefully — it can chain across multiple tables.
-- ====================================================================
CREATE TABLE lab.Parent (
    ParentId INT NOT NULL PRIMARY KEY,
    Name     NVARCHAR(50) NOT NULL
);

CREATE TABLE lab.Child (
    ChildId  INT NOT NULL PRIMARY KEY,
    ParentId INT NOT NULL,
    Value    NVARCHAR(50) NOT NULL,
    CONSTRAINT FK_Child_Parent
        FOREIGN KEY (ParentId) REFERENCES lab.Parent(ParentId)
        ON DELETE CASCADE
);

INSERT INTO lab.Parent (ParentId, Name) VALUES (1, N'Group A');
INSERT INTO lab.Child (ChildId, ParentId, Value) VALUES (1, 1, N'Item 1');
INSERT INTO lab.Child (ChildId, ParentId, Value) VALUES (2, 1, N'Item 2');

-- Verify both parents and children exist
SELECT 'Before delete:', p.Name, c.Value
FROM lab.Parent AS p
INNER JOIN lab.Child AS c ON c.ParentId = p.ParentId;

-- Delete the parent — child is cascaded
DELETE FROM lab.Parent WHERE ParentId = 1;

-- Verify: both parent and children are gone
SELECT 'After delete:', COUNT(*) AS ParentCount FROM lab.Parent;
SELECT 'After delete:', COUNT(*) AS ChildCount FROM lab.Child;

-- Clean up
DROP TABLE IF EXISTS lab.Child;
DROP TABLE IF EXISTS lab.Parent;
GO

-- ====================================================================
-- CHECK YOURSELF:
-- 1. What happens when you insert NULL into a CHECK (col > 0) column
--    that is nullable? What if the column is NOT NULL?
-- 2. Create a UNIQUE constraint on a temp table, insert a value,
--    then try to insert the same value again. Catch the error.
-- 3. Explain the difference between DEFAULT firing vs not firing.
-- 4. What does ON DELETE CASCADE do? Why must it be used carefully?

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/00-fundamentals/08-integrity-rules.md
-- =================================================================================================
