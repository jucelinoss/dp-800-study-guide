-- =================================================================================
-- DP-800 - HANDS-ON LAB: SENSITIVITY CLASSIFICATION
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/05-data-security-compliance/data-security-compliance.md
--
-- SQL Server 2019+ / Azure SQL Database:
--   sys.sensitivity_classifications stores one row per classified column.
--   The classification is metadata; it does not mask, encrypt, or change data.
-- =================================================================================
-- This lab demonstrates:
--   1. Why sys.sensitivity_classifications can be empty
--   2. How to create a safe lab table from AdventureWorks data
--   3. How to classify columns with ADD SENSITIVITY CLASSIFICATION
--   4. How to report all classifications and filter by label
--   5. How to remove a classification with DROP SENSITIVITY CLASSIFICATION
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup: this lab owns only the lab schema/table below.
IF OBJECT_ID('lab.SensitiveCustomerData', 'U') IS NOT NULL
BEGIN
    DROP TABLE lab.SensitiveCustomerData;
END;
GO

IF SCHEMA_ID('lab') IS NULL
    EXEC('CREATE SCHEMA lab');
GO

-- Create a small table using realistic columns from AdventureWorks.
CREATE TABLE lab.SensitiveCustomerData
(
    CustomerID       INT            NOT NULL PRIMARY KEY,
    FirstName        NVARCHAR(50)   NOT NULL,
    LastName         NVARCHAR(50)   NOT NULL,
    EmailAddress     NVARCHAR(50)   NULL,
    PhoneNumber      NVARCHAR(25)   NULL,
    BirthDate        DATE           NULL,
    NationalIDNumber NVARCHAR(15)   NULL
);
GO

INSERT INTO lab.SensitiveCustomerData
(
    CustomerID,
    FirstName,
    LastName,
    EmailAddress,
    PhoneNumber,
    BirthDate,
    NationalIDNumber
)
SELECT TOP (10)
    p.BusinessEntityID,
    p.FirstName,
    p.LastName,
    e.EmailAddress,
    pp.PhoneNumber,
    eom.BirthDate,
    eom.NationalIDNumber
FROM Person.Person AS p
LEFT JOIN HumanResources.Employee AS eom
    ON eom.BusinessEntityID = p.BusinessEntityID
OUTER APPLY
(
    SELECT TOP (1) EmailAddress
    FROM Person.EmailAddress
    WHERE BusinessEntityID = p.BusinessEntityID
    ORDER BY EmailAddressID
) AS e
OUTER APPLY
(
    SELECT TOP (1) PhoneNumber
    FROM Person.PersonPhone
    WHERE BusinessEntityID = p.BusinessEntityID
    ORDER BY PhoneNumberTypeID, PhoneNumber
) AS pp
ORDER BY p.BusinessEntityID;
GO

-- PART 1: Before classification, the catalog view may be empty for this table.
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS TableName,
    c.name AS ColumnName,
    sc.information_type,
    sc.label,
    sc.rank_desc
FROM sys.sensitivity_classifications AS sc
JOIN sys.objects AS o
    ON o.object_id = sc.major_id
JOIN sys.columns AS c
    ON c.object_id = sc.major_id
   AND c.column_id = sc.minor_id
WHERE o.object_id = OBJECT_ID('lab.SensitiveCustomerData')
ORDER BY SchemaName, TableName, ColumnName;
-- Expected result: zero rows.
GO

-- PART 2: Add sensitivity metadata to selected columns.
ADD SENSITIVITY CLASSIFICATION TO
    lab.SensitiveCustomerData.EmailAddress,
    lab.SensitiveCustomerData.PhoneNumber
WITH
(
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Contact Info',
    RANK = HIGH
);

ADD SENSITIVITY CLASSIFICATION TO
    lab.SensitiveCustomerData.BirthDate,
    lab.SensitiveCustomerData.NationalIDNumber
WITH
(
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Credentials',
    RANK = CRITICAL
);
GO

-- PART 3: Report every classification in the current database.
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS TableName,
    c.name AS ColumnName,
    sc.information_type,
    sc.label,
    sc.rank_desc
FROM sys.sensitivity_classifications AS sc
JOIN sys.objects AS o
    ON o.object_id = sc.major_id
JOIN sys.columns AS c
    ON c.object_id = sc.major_id
   AND c.column_id = sc.minor_id
ORDER BY SchemaName, TableName, ColumnName;
GO

-- PART 4: Filter the report like a compliance inventory.
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS TableName,
    c.name AS ColumnName,
    sc.information_type,
    sc.label,
    sc.rank_desc
FROM sys.sensitivity_classifications AS sc
JOIN sys.objects AS o
    ON o.object_id = sc.major_id
JOIN sys.columns AS c
    ON c.object_id = sc.major_id
   AND c.column_id = sc.minor_id
WHERE sc.label IN ('Confidential', 'Highly Confidential')
ORDER BY SchemaName, TableName, ColumnName;
GO

-- The classification is metadata only: the values are still returned normally.
SELECT *
FROM lab.SensitiveCustomerData;
GO

-- PART 5: Optional cleanup for a disposable lab environment.
-- Uncomment only when you want to return sys.sensitivity_classifications to empty
-- for this lab table.
-- DROP SENSITIVITY CLASSIFICATION FROM lab.SensitiveCustomerData.EmailAddress;
-- DROP SENSITIVITY CLASSIFICATION FROM lab.SensitiveCustomerData.PhoneNumber;
-- DROP SENSITIVITY CLASSIFICATION FROM lab.SensitiveCustomerData.BirthDate;
-- DROP SENSITIVITY CLASSIFICATION FROM lab.SensitiveCustomerData.NationalIDNumber;
-- DROP TABLE lab.SensitiveCustomerData;
