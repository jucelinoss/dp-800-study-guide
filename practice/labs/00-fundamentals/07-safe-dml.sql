-- ====================================================================
-- DP-800 Study Guide — Lab 07: Safe DML
-- Database: AdventureWorks2025
-- Purpose: UPDATE, DELETE, OUTPUT clause, transactions, @@ROWCOUNT
-- Prerequisite: Labs 01-06 (familiarity with AdventureWorks schema)
-- ====================================================================

-- WARNING: This lab uses BEGIN TRAN / ROLLBACK to prevent permanent
-- changes. Replace ROLLBACK with COMMIT only when you intend to save.

-- ====================================================================
-- UPDATE with transaction: SELECT first, then UPDATE
-- KEY CONCEPT: Always preview the rows you will change inside a
-- transaction so you can ROLLBACK if the wrong rows are affected.
-- ====================================================================
BEGIN TRAN;
    -- Step 1: Preview the rows that will change
    SELECT ProductID, Name, ListPrice
    FROM Production.Product
    WHERE Name LIKE N'%HL Road%';

    -- Step 2: Apply the change (5% price increase)
    UPDATE Production.Product
    SET ListPrice = ListPrice * 1.05
    WHERE Name LIKE N'%HL Road%';

    -- Step 3: Verify the change (read your own uncommitted data)
    SELECT ProductID, Name, ListPrice
    FROM Production.Product
    WHERE Name LIKE N'%HL Road%';

    -- Step 4: Print how many rows were affected
    PRINT 'Rows updated: ' + CAST(@@ROWCOUNT AS NVARCHAR(10));
ROLLBACK;  -- Undo the change. Replace with COMMIT when ready to persist.
GO

-- [OBSERVE] After ROLLBACK, the data is back to its original state.
-- Always verify you selected the correct rows before UPDATE.

-- ====================================================================
-- DELETE with transaction
-- KEY CONCEPT: Same SELECT-first pattern applies. DELETE is logged
-- and can be rolled back within a transaction.
-- ====================================================================
BEGIN TRAN;
    -- Preview rows to delete (a subset of addresses)
    SELECT TOP 5 AddressID, AddressLine1, City
    FROM Person.Address
    WHERE City = N'Paris'
    ORDER BY AddressID;

    -- Delete only one specific address (for safety)
    DELETE FROM Person.Address
    WHERE AddressID = 1;  -- This may fail due to FK constraints

    PRINT 'Rows deleted: ' + CAST(@@ROWCOUNT AS NVARCHAR(10));

    -- Check what remains
    SELECT AddressID, AddressLine1, City
    FROM Person.Address
    WHERE City = N'Paris';
ROLLBACK;
GO

-- [OBSERVE] If the DELETE fails due to a FK constraint (error 547),
-- the transaction is still active. Use BEGIN TRY/CATCH in production.

-- ====================================================================
-- @@ROWCOUNT to verify affected rows
-- KEY CONCEPT: @@ROWCOUNT returns the number of rows affected by
-- the LAST statement. Check it after every DML to confirm intent.
-- ====================================================================
BEGIN TRAN;
    -- Update a known product
    UPDATE Production.Product
    SET ListPrice = ListPrice * 1.10
    WHERE ProductID = 750;

    -- Check how many rows changed
    IF @@ROWCOUNT = 0
        PRINT 'WARNING: No rows updated. Check your WHERE clause.';
    ELSE IF @@ROWCOUNT = 1
        PRINT 'OK: 1 row updated as expected.';
    ELSE
        PRINT 'UNEXPECTED: ' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + ' rows updated.';
ROLLBACK;
GO

-- ====================================================================
-- OUTPUT clause to capture changes
-- KEY CONCEPT: OUTPUT returns the old (deleted) and new (inserted)
-- values. Useful for audit logs, change tracking, or confirmation.
-- ====================================================================
BEGIN TRAN;
    -- Update price with OUTPUT
    UPDATE Production.Product
    SET ListPrice = ListPrice * 1.10
    OUTPUT deleted.ProductID,
           deleted.Name,
           deleted.ListPrice AS OldPrice,
           inserted.ListPrice AS NewPrice
    WHERE ProductID = 750;
ROLLBACK;
GO

-- [OBSERVE] The OUTPUT clause shows the before-and-after values in
-- the results grid. No need for a separate SELECT to verify.

-- OUTPUT with DELETE
BEGIN TRAN;
    -- Delete a sales order detail line with OUTPUT
    DELETE FROM Sales.SalesOrderDetail
    OUTPUT deleted.SalesOrderDetailID,
           deleted.ProductID,
           deleted.OrderQty,
           deleted.LineTotal
    WHERE SalesOrderDetailID = 1;
ROLLBACK;
GO

-- ====================================================================
-- DELETE vs TRUNCATE
-- KEY CONCEPT: DELETE logs each row (can have WHERE, can roll back).
-- TRUNCATE minimally logs (no WHERE, resets identity, faster).
-- ====================================================================
CREATE TABLE #Demo (
    Id    INT IDENTITY(1,1) PRIMARY KEY,
    Value NVARCHAR(10)
);

INSERT INTO #Demo (Value) VALUES ('A'), ('B'), ('C');

-- DELETE with WHERE (logged per row)
DELETE FROM #Demo WHERE Value = 'B';
PRINT 'After DELETE: ' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + ' row(s) deleted.';

-- TRUNCATE (minimal logging, identity reset)
TRUNCATE TABLE #Demo;
PRINT 'After TRUNCATE: table empty, identity counter reset.';

-- Verify: next insert gets ID = 1 (not 4)
INSERT INTO #Demo (Value) VALUES ('D');
SELECT * FROM #Demo;

DROP TABLE IF EXISTS #Demo;
GO

-- [OBSERVE] After TRUNCATE, the IDENTITY counter resets.
-- After DELETE, the counter continues from where it left off.

-- ====================================================================
-- BEGIN TRY / CATCH for DML safety
-- KEY CONCEPT: Wrap DML in TRY/CATCH to handle errors gracefully.
-- ====================================================================
BEGIN TRY
    BEGIN TRAN;
        -- Intentionally cause an FK violation
        DELETE FROM Sales.Customer WHERE CustomerID = 1;
    COMMIT;
END TRY
BEGIN CATCH
    ROLLBACK;
    PRINT 'ERROR: ' + ERROR_MESSAGE();
    PRINT 'Transaction rolled back. No data was harmed.';
END CATCH;
GO

-- ====================================================================
-- CHECK YOURSELF:
-- 1. Update ListPrice of a specific product by 10% inside a transaction
--    and roll back. Use OUTPUT to capture the old and new prices.
-- 2. Explain why you should always run SELECT before DELETE or UPDATE.
-- 3. What is the difference between DELETE and TRUNCATE in terms of
--    logging, WHERE support, and identity reset?
-- 4. Write a TRY/CATCH block around an UPDATE that might fail.
-- ====================================================================
