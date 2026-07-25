-- =================================================================================
-- DP-800 - LAB: REGEX, PHONETIC MATCHING (SOUNDEX/DIFFERENCE) AND FUZZY MATCHING
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates pattern validation, data cleaning, and fuzzy matching:
--   1. Pattern Validation: LIKE with Character Classes ([A-Z], [^0-9]) and ESCAPE Clause
--   2. Normalization and Cleaning: TRANSLATE vs REPLACE and STRING_SPLIT with Ordinal Support (SQL 2022+)
--   3. Phonetic Matching: SOUNDEX and the DIFFERENCE Function (Scale 0 to 4)
--   4. Fuzzy Matching Algorithms: EDIT_DISTANCE (Levenshtein), SIMILARITY, and JARO_WINKLER_DISTANCE
--   5. Practical Project Scenarios (Contact Deduplication and Data Preparation for Embeddings/RAG)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.RawContacts;
GO

-- Test table structure
CREATE TABLE lab.RawContacts (
    ContactID INT IDENTITY(1,1) PRIMARY KEY,
    FullName NVARCHAR(100) NOT NULL,
    Phone NVARCHAR(50) NULL,
    ProductCode NVARCHAR(20) NULL
);
GO


-- =================================================================================
-- PART 1: PATTERN VALIDATION WITH ADVANCED LIKE AND ESCAPE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - PATTERN MATCHING WITH LIKE: Native T-SQL supports character classes:
--     * `[A-Z]`: Any character in the alphabetic range.
--     * `[0-9]`: Any digit.
--     * `[^0-9]`: Any character that is NOT a digit.
--   - ESCAPE CLAUSE: Allows searching for literal wildcard characters (like `%`, `_`, `[`) using an escape character (e.g., `ESCAPE '\'`).

INSERT INTO lab.RawContacts (FullName, Phone, ProductCode) VALUES 
('Alice Smith', '(11) 98765-4321', 'ABC-1234'),
('Bob Smyth', '11.98765.4321', 'XYZ-9999'),
('Charlie Brown', '11987654321', 'INVALID-12'),
('David 50% Sale', 'N/A', 'OFF-50%');
GO

-- -- [DP-800 EXAM TIP]
-- 1. Validate Product Codes: Exactly 3 uppercase letters, dash, and 4 digits (e.g., ABC-1234)
SELECT ContactID, ProductCode
FROM lab.RawContacts
WHERE ProductCode LIKE '[A-Z][A-Z][A-Z]-[0-9][0-9][0-9][0-9]';

-- 2. Search for literal % character using ESCAPE
SELECT ContactID, FullName
FROM lab.RawContacts
WHERE FullName LIKE '%\%%' ESCAPE '\';
GO

-- 3. SQL Server 2025: same rule using regular expression.
-- REGEXP_LIKE requires compatibility level 170. Confirm before running on another database:
-- SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME();
SELECT ContactID, ProductCode
FROM lab.RawContacts
WHERE REGEXP_LIKE(ProductCode, '^[A-Z]{3}-\d{4}$');
GO


-- =================================================================================
-- PART 2: STRING NORMALIZATION WITH TRANSLATE AND ORDINAL STRING_SPLIT
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - TRANSLATE(string, source_chars, dest_chars): Replaces individual characters in a single pass.
--     Avoids chaining multiple `REPLACE(REPLACE(REPLACE(...)))`.
--     Requirement: `source_chars` and `dest_chars` must have exactly the same length!
--   - STRING_SPLIT(string, delimiter, 1): As of SQL Server 2022, the `enable_ordinal = 1` parameter
--     adds the `ordinal` column that preserves the original position of the item in the array.

-- 1. Normalize phone numbers by removing parentheses, dots, and dashes at once
SELECT 
    ContactID,
    Phone AS TelefoneBruto,
    TRANSLATE(Phone, '().- ', '     ') AS TelefoneFormatado,
    REPLACE(TRANSLATE(Phone, '().- ', '     '), ' ', '') AS ApenasDigitos
FROM lab.RawContacts;
GO

-- 2. STRING_SPLIT with ordinal preservation (SQL Server 2022+)
DECLARE @tags NVARCHAR(200) = N'SQL,Azure,Database,Security,AI';

SELECT value AS TagName, ordinal AS Posicao
FROM STRING_SPLIT(@tags, ',', 1);
GO


-- =================================================================================
-- PART 3: PHONETIC MATCHING (SOUNDEX AND DIFFERENCE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - SOUNDEX(): Converts a string into a 4-character phonetic code (one letter + 3 digits).
--     Identifies how words sound in English.
--   - DIFFERENCE(str1, str2): Compares the SOUNDEX codes of two words and returns an integer from 0 to 4:
--     * 4: Nearly identical sounds (e.g., 'Smith' vs 'Smyth').
--     * 0: Completely different sounds.

-- -- [DP-800 EXAM TIP]
SELECT 
    SOUNDEX('Smith') AS SoundexSmith,
    SOUNDEX('Smyth') AS SoundexSmyth,
    DIFFERENCE('Smith', 'Smyth') AS ScoreSmithSmyth, -- Returns 4 (Maximum similarity)
    DIFFERENCE('Smith', 'Brown') AS ScoreSmithBrown; -- Returns 1 or 0
GO

-- Find contacts whose name sounds like 'Smith'
SELECT ContactID, FullName, DIFFERENCE(FullName, 'Smith') AS PontuacaoFonetica
FROM lab.RawContacts
WHERE DIFFERENCE(FullName, 'Smith') >= 3;
GO


-- =================================================================================
-- PART 4: FUZZY MATCHING ALGORITHMS (EDIT DISTANCE AND SIMILARITY)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - EDIT_DISTANCE (Levenshtein): Returns the absolute number of character insertions, deletions, and substitutions.
--   - EDIT_DISTANCE_SIMILARITY: Returns a normalized score from 0 (different) to 100 (identical).
--   - JARO_WINKLER_DISTANCE: Returns a value between 0.0 and 1.0, weighting matching initial characters.

-- Compatibility Note: EDIT_DISTANCE, EDIT_DISTANCE_SIMILARITY, and the JARO_WINKLER functions
-- are in preview in SQL Server 2025. Input values cannot be varchar(max)/nvarchar(max).
-- In earlier versions, SOUNDEX/DIFFERENCE are the native alternatives available.
-- To enable preview features in this study database, run separately (requires ALTER ANY DATABASE permission):
-- ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;

-- Compare the modern metrics. Lower distance means higher proximity; higher similarity means better match.
-- Dynamic SQL allows the rest of the lab to run even if PREVIEW_FEATURES is disabled.
IF EXISTS (
    SELECT 1
    FROM sys.database_scoped_configurations
    WHERE name = 'PREVIEW_FEATURES' AND value = 1
)
BEGIN
    EXEC sys.sp_executesql N'
        SELECT
            FullName,
            EDIT_DISTANCE(FullName, N''Alice Smith'') AS DistanciaEdicao,
            EDIT_DISTANCE_SIMILARITY(FullName, N''Alice Smith'') AS SimilaridadeEdicao,
            JARO_WINKLER_DISTANCE(FullName, N''Alice Smith'') AS DistanciaJaroWinkler,
            JARO_WINKLER_SIMILARITY(FullName, N''Alice Smith'') AS SimilaridadeJaroWinkler
        FROM lab.RawContacts;';
END
ELSE
    PRINT 'PREVIEW_FEATURES está desabilitado; execute a instrução comentada acima para praticar as métricas fuzzy.';
GO


-- =================================================================================
-- PART 5: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Deduplication and Name Cleaning before Vectorization (Embeddings for RAG)
-- In AI pipelines, duplicate names with incorrect spellings must be 
-- cleaned via TRANSLATE and grouped by SOUNDEX/DIFFERENCE code to avoid noise in vectors.

SELECT 
    c1.ContactID AS ID1, c1.FullName AS Nome1,
    c2.ContactID AS ID2, c2.FullName AS Nome2,
    DIFFERENCE(c1.FullName, c2.FullName) AS GrauSimilaridade
FROM lab.RawContacts c1
JOIN lab.RawContacts c2 ON c1.ContactID < c2.ContactID
WHERE DIFFERENCE(c1.FullName, c2.FullName) >= 3;
GO
