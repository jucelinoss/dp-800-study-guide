-- =================================================================================
-- DP-800 - HANDS-ON LAB: FULL-TEXT SEARCH (CONTAINS, FREETEXT, CONTAINSTABLE, AND STOPLISTS)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates native linguistic search in SQL Server:
--   1. Full-Text Catalog and Index Creation (`CREATE FULLTEXT CATALOG` and `INDEX`)
--   2. Precise `CONTAINS` predicates: terms, phrases, booleans, prefixes, proximity, and `FORMSOF`
--   3. Natural Language Search Predicate with `FREETEXT`
--   4. Ranked Queries with `CONTAINSTABLE` and `FREETEXTTABLE` (`[RANK]` column 0 to 1000)
--   5. Stoplists, language settings, and index maintenance
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID('lab.FtsProductCatalog'))
    DROP FULLTEXT INDEX ON lab.FtsProductCatalog;

IF EXISTS (SELECT * FROM sys.fulltext_catalogs WHERE name = 'LabFtsCatalog')
    DROP FULLTEXT CATALOG LabFtsCatalog;

IF EXISTS (SELECT * FROM sys.fulltext_stoplists WHERE name = 'LabFtsStopList')
    DROP FULLTEXT STOPLIST LabFtsStopList;

DROP TABLE IF EXISTS lab.FtsProductCatalog;
GO

-- Table Structure for Full-Text Search Testing
CREATE TABLE lab.FtsProductCatalog (
    ProductID INT IDENTITY(1,1) NOT NULL,
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL,
    CONSTRAINT PK_lab_FtsProductCatalog PRIMARY KEY (ProductID) -- Unique key required by FTS
);
GO

INSERT INTO lab.FtsProductCatalog (ProductName, Description) VALUES
(N'Pro Cycling Helmet', N'Lightweight carbon-fiber helmet with built-in Bluetooth headphones.'),
(N'Trail Bike', N'Mountain bike for racing with 24 gears.'),
(N'Sport Bluetooth Headphones', N'Wireless Bluetooth headphones with active noise cancellation.');
GO


-- =================================================================================
-- PART 1: FULL-TEXT CATALOG AND INDEX CREATION
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - FULLTEXT CATALOG: Logical container for full-text search indexes.
--   - KEY INDEX: Requires a unique non-nullable index on the table (usually the Primary Key PK).
--   - CHANGE_TRACKING = AUTO: SQL Server automatically updates the inverted index as rows change.

-- -- [DP-800 KEY POINT]
-- 1. Create the Full-Text Catalog
CREATE FULLTEXT CATALOG LabFtsCatalog;
GO

-- 2. Create a stoplist from the system list and inspect its stop words.
CREATE FULLTEXT STOPLIST LabFtsStopList FROM SYSTEM STOPLIST;
ALTER FULLTEXT STOPLIST LabFtsStopList ADD N'product' LANGUAGE 1033;

SELECT stopword, language
FROM sys.fulltext_stopwords
WHERE stoplist_id = FULLTEXT_STOPLIST_ID(N'LabFtsStopList');
GO

-- 3. Create the Full-Text Index. English data uses language 1033.
CREATE FULLTEXT INDEX ON lab.FtsProductCatalog (
    ProductName LANGUAGE 1033,
    Description LANGUAGE 1033
)
KEY INDEX PK_lab_FtsProductCatalog
ON LabFtsCatalog
WITH (CHANGE_TRACKING = AUTO, STOPLIST = LabFtsStopList);
GO

-- Wait for initial population (in production, the index is populated asynchronously)
WAITFOR DELAY '00:00:02';
GO


-- =================================================================================
-- PART 2: SEARCH PREDICATES (CONTAINS VS FREETEXT)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CONTAINS: Precise search with boolean operators (AND, OR, NOT), prefixes ("cap*"), and proximity (NEAR).
--   - FREETEXT: Semantic natural language search (ignores stopwords and applies verb inflections).

-- -- [DP-800 KEY POINT]
-- 1. Term, phrase, and boolean search. A phrase requires internal double quotes.
SELECT ProductID, ProductName, Description
FROM lab.FtsProductCatalog
WHERE CONTAINS(Description, '"carbon-fiber helmet" OR (bluetooth AND headphones)');
GO

-- 2. Prefix Search
SELECT ProductID, ProductName, Description
FROM lab.FtsProductCatalog
WHERE CONTAINS(Description, '"head*" OR "helm*"');
GO

-- 3. Proximity Search with NEAR
SELECT ProductID, ProductName, Description
FROM lab.FtsProductCatalog
WHERE CONTAINS(Description, 'NEAR((headphones, bluetooth), 5)');
GO

-- 4. Inflectional search. THESAURUS matching requires configured thesaurus entries.
SELECT ProductID, ProductName, Description
FROM lab.FtsProductCatalog
WHERE CONTAINS(Description, 'FORMSOF(INFLECTIONAL, "cancel")');
GO

-- Weighted terms alter the relative importance inside a CONTAINS expression.
SELECT ProductID, ProductName, Description
FROM lab.FtsProductCatalog
WHERE CONTAINS(Description, 'ISABOUT(bluetooth WEIGHT(0.9), headphones WEIGHT(0.5))');
GO

-- Example: WHERE CONTAINS(Description, 'FORMSOF(THESAURUS, "fast")');

-- 5. Natural Language Search with FREETEXT
SELECT ProductID, ProductName, Description
FROM lab.FtsProductCatalog
WHERE FREETEXT(Description, 'comfortable wireless headphones');
GO


-- =================================================================================
-- PART 3: RANKED QUERIES (FREETEXTTABLE AND CONTAINSTABLE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - FREETEXTTABLE / CONTAINSTABLE: Table-valued functions returning the `[KEY]` (ID) and `[RANK]` (0 to 1000) columns.
--     Allows sorting results by relevance or filtering the top N results (`TOP N`).

-- -- [DP-800 KEY POINT]
SELECT 
    p.ProductID,
    p.ProductName,
    ft.[RANK] AS RelevanceScore
FROM FREETEXTTABLE(lab.FtsProductCatalog, Description, 'bluetooth helmet', 10) AS ft
JOIN lab.FtsProductCatalog p ON p.ProductID = ft.[KEY]
ORDER BY ft.[RANK] DESC;
GO

SELECT p.ProductID, p.ProductName, ct.[RANK] AS RelevanceScore
FROM CONTAINSTABLE(lab.FtsProductCatalog, Description, 'bluetooth AND headphones') AS ct
JOIN lab.FtsProductCatalog AS p ON p.ProductID = ct.[KEY]
ORDER BY ct.[RANK] DESC;
GO

-- MANUAL tracks changes until an explicit population operation is requested.
ALTER FULLTEXT INDEX ON lab.FtsProductCatalog SET CHANGE_TRACKING MANUAL;
UPDATE lab.FtsProductCatalog
SET Description = Description + N' Updated for the manual-population exercise.'
WHERE ProductID = 1;
ALTER FULLTEXT INDEX ON lab.FtsProductCatalog START UPDATE POPULATION;
ALTER FULLTEXT INDEX ON lab.FtsProductCatalog SET CHANGE_TRACKING AUTO;
GO


-- =================================================================================
-- PART 4: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: CONTAINS vs FREETEXT Comparison Matrix for the DP-800 Exam
-- Syntax decision guide for building search engines.

SELECT 
    'CONTAINS' AS Predicate,
    'Precise / Boolean / Prefix / Proximity' AS SearchModel,
    'Phrases require quotes: ''"noise cancelling"''' AS RequiredSyntax,
    'Advanced filters and technical e-commerce' AS UseCase
UNION ALL
SELECT 
    'FREETEXT',
    'Natural language (higher recall)',
    'Simple free-text query',
    'Global search fields and search bars';
GO

-- This DMV requires VIEW SERVER STATE.
SELECT catalog_name, population_type_description, status_description
FROM sys.dm_fts_index_population;
GO
