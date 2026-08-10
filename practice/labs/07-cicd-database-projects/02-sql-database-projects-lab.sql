-- =================================================================================
-- DP-800 - PRACTICAL LAB: SQL DATABASE PROJECTS, DACPAC AND SQLCMD
-- =================================================================================
-- Database: AdventureWorks2025 (or any disposable SQL Server database)
--
-- This lab is safe to repeat: all objects use the lab schema and the script
-- removes only objects created by this exercise.
--
-- EXECUTABLE PROJECT FLOW:
-- 1. Enter the 02-sql-database-project folder and run:
--      dotnet build DatabaseProject.sqlproj -c Release
-- 2. Generate a script without changing the database:
--      sqlpackage /Action:Script /SourceFile:bin/Release/DatabaseProject.dacpac
--        /TargetConnectionString:"<connection>" /OutputPath:planned.sql
-- 3. Review planned.sql and publish to a disposable database:
--      sqlpackage /Action:Publish /SourceFile:bin/Release/DatabaseProject.dacpac
--        /TargetConnectionString:"<connection>" /p:BlockOnPossibleDataLoss=true
-- The SQL below complements this flow with pre/post-deployment and SQLCMD exercises.
--
-- THEORY:
-- ../../../certification/07-cicd-database-projects/02-sql-database-projects.md
--
-- MICROSOFT LEARN:
-- Pre/post-deployment scripts:
-- https://learn.microsoft.com/en-us/sql/tools/sql-database-projects/concepts/pre-post-deployment-scripts?view=sql-server-ver17
-- sqlcmd commands (:r):
-- https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-commands?view=sql-server-ver17#r-filename
-- AdventureWorks installation (optional):
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================

USE AdventureWorks2025;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID(N'lab') IS NULL
    EXEC(N'CREATE SCHEMA lab');
GO

-- ---------------------------------------------------------------------------------
-- PART 0: RESET ONLY THE LAB OBJECTS
-- ---------------------------------------------------------------------------------
DROP TABLE IF EXISTS lab.ReferenceCountries;
DROP TABLE IF EXISTS lab.ReferenceOrderStatus;
DROP TABLE IF EXISTS lab.__RefactorLog;
DROP TABLE IF EXISTS lab.MigratedCustomers;
DROP TABLE IF EXISTS lab.LegacyCustomers;
GO

-- ---------------------------------------------------------------------------------
-- PART 1: SIMULATE A PRE-DEPLOYMENT DATA MIGRATION
-- ---------------------------------------------------------------------------------
-- A pre-deployment script runs before the deployment plan is applied. The plan is
-- calculated before the pre-deployment script runs, so this is the place to copy
-- values that would otherwise be lost by a column rename/drop.

CREATE TABLE lab.LegacyCustomers
(
    CustomerID INT NOT NULL CONSTRAINT PK_LegacyCustomers PRIMARY KEY,
    FullContactName NVARCHAR(100) NOT NULL,
    LegacyCode VARCHAR(20) NULL
);

CREATE TABLE lab.MigratedCustomers
(
    CustomerID INT NOT NULL CONSTRAINT PK_MigratedCustomers PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Notes NVARCHAR(200) NULL
);
GO

INSERT INTO lab.LegacyCustomers (CustomerID, FullContactName, LegacyCode)
VALUES
    (1001, N'Alice Silva', 'LEG-1001'),
    (1002, N'Bob Santos', 'LEG-1002');
GO

-- Idempotent pre-deployment pattern: executing this block twice does not duplicate
-- the migrated rows. A production migration should also handle names without a
-- space and should be tested against the real data distribution.
DECLARE @MigrationRows INT;

INSERT INTO lab.MigratedCustomers (CustomerID, FirstName, LastName, Notes)
SELECT
    l.CustomerID,
    LEFT(l.FullContactName, CHARINDEX(N' ', l.FullContactName + N' ') - 1),
    LTRIM(SUBSTRING(l.FullContactName, CHARINDEX(N' ', l.FullContactName + N' '), 100)),
    CONCAT(N'Migrated from legacy code: ', l.LegacyCode)
FROM lab.LegacyCustomers AS l
WHERE l.LegacyCode IS NOT NULL
  AND NOT EXISTS
  (
      SELECT 1
      FROM lab.MigratedCustomers AS m
      WHERE m.CustomerID = l.CustomerID
  );

SET @MigrationRows = @@ROWCOUNT;
PRINT CONCAT(N'PRE-DEPLOYMENT: rows migrated in this run = ', @MigrationRows);

-- Repeat the same block to prove that the second execution inserts zero rows.
INSERT INTO lab.MigratedCustomers (CustomerID, FirstName, LastName, Notes)
SELECT
    l.CustomerID,
    LEFT(l.FullContactName, CHARINDEX(N' ', l.FullContactName + N' ') - 1),
    LTRIM(SUBSTRING(l.FullContactName, CHARINDEX(N' ', l.FullContactName + N' '), 100)),
    CONCAT(N'Migrated from legacy code: ', l.LegacyCode)
FROM lab.LegacyCustomers AS l
WHERE l.LegacyCode IS NOT NULL
  AND NOT EXISTS
  (
      SELECT 1
      FROM lab.MigratedCustomers AS m
      WHERE m.CustomerID = l.CustomerID
  );

PRINT CONCAT(N'PRE-DEPLOYMENT: rows migrated in repeat run = ', @@ROWCOUNT);
GO

SELECT CustomerID, FirstName, LastName, Notes
FROM lab.MigratedCustomers
ORDER BY CustomerID;
GO

-- ---------------------------------------------------------------------------------
-- PART 2: REFACTOR LOG AND DETERMINISTIC OPERATION KEYS
-- ---------------------------------------------------------------------------------
-- SQL Database Projects uses a refactor log to preserve renames made through the
-- project tooling. This table is only a teaching simulation; do not create or edit
-- the real project-managed refactor log manually.

CREATE TABLE lab.__RefactorLog
(
    OperationKey UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_lab_RefactorLog PRIMARY KEY,
    OperationDescription NVARCHAR(200) NOT NULL,
    AppliedAt DATETIME2(0) NOT NULL CONSTRAINT DF_lab_RefactorLog_AppliedAt DEFAULT SYSUTCDATETIME()
);
GO

DECLARE @OperationKey UNIQUEIDENTIFIER = '11111111-1111-1111-1111-111111111111';

IF NOT EXISTS
(
    SELECT 1
    FROM lab.__RefactorLog
    WHERE OperationKey = @OperationKey
)
BEGIN
    INSERT INTO lab.__RefactorLog (OperationKey, OperationDescription)
    VALUES (@OperationKey, N'Rename LegacyCustomers.FullContactName mapping');

    PRINT N'REFACTOR LOG: operation recorded.';
END
ELSE
    PRINT N'REFACTOR LOG: operation already recorded; nothing to repeat.';
GO

-- ---------------------------------------------------------------------------------
-- PART 3: POST-DEPLOYMENT REFERENCE DATA WITH AN IDEMPOTENT UPSERT
-- ---------------------------------------------------------------------------------
-- A post-deployment script runs after the deployment plan completes. Reference data
-- should be versioned with the project and loaded in a way that is safe to repeat.

CREATE TABLE lab.ReferenceOrderStatus
(
    StatusCode VARCHAR(20) NOT NULL CONSTRAINT PK_ReferenceOrderStatus PRIMARY KEY,
    StatusName NVARCHAR(100) NOT NULL,
    IsActive BIT NOT NULL
);

CREATE TABLE lab.ReferenceCountries
(
    CountryCode CHAR(2) NOT NULL CONSTRAINT PK_ReferenceCountries PRIMARY KEY,
    CountryName NVARCHAR(100) NOT NULL
);
GO

-- This is the T-SQL that a referenced data file could contain.
UPDATE target
SET target.StatusName = source.StatusName,
    target.IsActive = source.IsActive
FROM lab.ReferenceOrderStatus AS target
JOIN
(
    VALUES
        ('NEW', N'New', CONVERT(BIT, 1)),
        ('CLOSED', N'Closed', CONVERT(BIT, 1)),
        ('CANCELLED', N'Cancelled', CONVERT(BIT, 0))
) AS source(StatusCode, StatusName, IsActive)
    ON target.StatusCode = source.StatusCode;

INSERT INTO lab.ReferenceOrderStatus (StatusCode, StatusName, IsActive)
SELECT source.StatusCode, source.StatusName, source.IsActive
FROM
(
    VALUES
        ('NEW', N'New', CONVERT(BIT, 1)),
        ('CLOSED', N'Closed', CONVERT(BIT, 1)),
        ('CANCELLED', N'Cancelled', CONVERT(BIT, 0))
) AS source(StatusCode, StatusName, IsActive)
WHERE NOT EXISTS
(
    SELECT 1
    FROM lab.ReferenceOrderStatus AS target
    WHERE target.StatusCode = source.StatusCode
);

INSERT INTO lab.ReferenceCountries (CountryCode, CountryName)
SELECT source.CountryCode, source.CountryName
FROM
(
    VALUES
        ('BR', N'Brazil'),
        ('US', N'United States'),
        ('CA', N'Canada')
) AS source(CountryCode, CountryName)
WHERE NOT EXISTS
(
    SELECT 1
    FROM lab.ReferenceCountries AS target
    WHERE target.CountryCode = source.CountryCode
);

PRINT N'POST-DEPLOYMENT: reference data loaded without duplicate keys.';
GO

SELECT StatusCode, StatusName, IsActive
FROM lab.ReferenceOrderStatus
ORDER BY StatusCode;

SELECT CountryCode, CountryName
FROM lab.ReferenceCountries
ORDER BY CountryCode;
GO

-- ---------------------------------------------------------------------------------
-- PART 4: HOW :r COMPOSES A POST-DEPLOYMENT SCRIPT
-- ---------------------------------------------------------------------------------
-- The following lines are intentionally comments so this lab runs in normal SSMS
-- mode. To execute them, create the files shown below and enable Query > SQLCMD
-- Mode in SSMS (or run the parent script with sqlcmd).
--
-- Scripts/PostDeployment/PostDeployment.sql:
-- PRINT 'Post-deployment: loading reference data...';
-- :r .\..\..\Data\ReferenceData\dbo.OrderStatus.data.sql
-- :r .\..\..\Data\ReferenceData\dbo.Countries.data.sql
-- PRINT 'Post-deployment complete.';
--
-- :r is processed by sqlcmd before SQL Server receives the batch. The referenced
-- files are read relative to the sqlcmd startup directory, and their contents are
-- inserted in order. The files must be excluded from model compilation in the
-- .sqlproj file with Build Remove, while remaining visible as None when desired.

-- ---------------------------------------------------------------------------------
-- PART 5: DACPAC, BACPAC AND BAK — RECOGNIZE THE ARTIFACT
-- ---------------------------------------------------------------------------------
SELECT Artifact, ContainsSchema, ContainsUserData, DeploymentOrRestore
FROM
(
    VALUES
        (N'DACPAC', N'Yes', N'No', N'Declarative schema deployment / diff'),
        (N'BACPAC', N'Yes', N'Yes', N'Import/export package'),
        (N'BAK', N'Backup pages and log as applicable', N'Yes', N'Physical restore')
) AS artifacts(Artifact, ContainsSchema, ContainsUserData, DeploymentOrRestore);
GO

-- ---------------------------------------------------------------------------------
-- PART 6: CLI ACTIONS AND RELEASE GATES
-- ---------------------------------------------------------------------------------
SELECT ActionName, Purpose, ChangesTarget
FROM
(
    VALUES
        (N'dotnet build', N'Compile and validate the SQL project', N'No'),
        (N'/Action:Script', N'Generate the deployment T-SQL for review', N'No'),
        (N'/Action:DeployReport', N'Generate the XML deployment report', N'No'),
        (N'/Action:Publish', N'Apply the DACPAC deployment', N'Yes')
) AS actions(ActionName, Purpose, ChangesTarget);
GO

-- ---------------------------------------------------------------------------------
-- PART 7: AUTOMATED LAB ASSERTIONS
-- ---------------------------------------------------------------------------------
IF (SELECT COUNT(*) FROM lab.MigratedCustomers) <> 2
    THROW 51000, 'Expected exactly two migrated customers.', 1;

IF (SELECT COUNT(*) FROM lab.__RefactorLog) <> 1
    THROW 51001, 'Expected exactly one deterministic refactor operation.', 1;

IF (SELECT COUNT(*) FROM lab.ReferenceOrderStatus) <> 3
    THROW 51002, 'Expected exactly three order statuses.', 1;

IF (SELECT COUNT(*) FROM lab.ReferenceCountries) <> 3
    THROW 51003, 'Expected exactly three countries.', 1;

PRINT N'LAB PASSED: migration, refactor tracking, reference data, and artifact checks completed.';
GO

-- Cleanup is intentionally left as a separate command so you can inspect the rows.
-- Run the following only when you are finished:
-- DROP TABLE IF EXISTS lab.ReferenceCountries;
-- DROP TABLE IF EXISTS lab.ReferenceOrderStatus;
-- DROP TABLE IF EXISTS lab.__RefactorLog;
-- DROP TABLE IF EXISTS lab.MigratedCustomers;
-- DROP TABLE IF EXISTS lab.LegacyCustomers;
