-- =================================================================================
-- DP-800 - LAB: REGEX, PHONETIC MATCHING (SOUNDEX/DIFFERENCE) AND FUZZY MATCHING
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/03-advanced-tsql/03-regex-fuzzy-matching.md
--    Open the theory guide alongside this lab for conceptual context.
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
    ContactID INT IDENTITY(1,1) CONSTRAINT PK_lab_RawContacts PRIMARY KEY,
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

-- 1. Positional example: the first character in the second argument is replaced
--    by the first character in the third argument, the second by the second, and so on.
--    Input characters may map to the same output character or to different output
--    characters.
SELECT TRANSLATE('2*[3+4]/{7-2}', '[]{}', '()()') AS NormalizedExpression;
-- Result: 2*(3+4)/(7-2)
GO

-- 2. Each input character is mapped to a different output character:
--    a -> X, b -> Y, c -> Z, and 1 -> 9.
SELECT TRANSLATE('abc-123', 'abc1', 'XYZ9') AS Result;
-- Result: XYZ-923
GO

-- 3. Different input characters may share the same destination.
--    Both '/' and '.' become '-', because their corresponding destinations are equal.
SELECT TRANSLATE('2025/07.30', '/.', '--') AS NormalizedDate;
-- Result: 2025-07-30
GO

-- 4. For phone numbers, four input characters are mapped to four spaces.
--    The arguments must have the same length: '().-' has 4 and '    ' has 4.
SELECT 
    ContactID,
    Phone AS TelefoneBruto,
    TRANSLATE(Phone, '().-', '    ') AS TelefoneFormatado
FROM lab.RawContacts;
GO

-- 5. TRANSLATE changes punctuation to spaces; REPLACE removes the spaces.
SELECT ContactID,
       Phone,
       REPLACE(TRANSLATE(Phone, '().-', '    '), ' ', '') AS ApenasDigitos
FROM lab.RawContacts;
GO

-- Error 9828: '().- ' has 5 characters, but ' ' has only 1.
-- TRANSLATE(Phone, '().- ', ' ') is invalid.

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

-- Find contacts whose last name sounds like 'Smith'. Bob Smyth is a practical
-- example: DIFFERENCE('Smyth', 'Smith') returns 4.
SELECT r.ContactID,
       r.FullName,
       s.LastName,
       DIFFERENCE(s.LastName, 'Smith') AS PhoneticScore
FROM lab.RawContacts AS r
CROSS APPLY (VALUES (PARSENAME(REPLACE(r.FullName, ' ', '.'), 1))) AS s(LastName)
WHERE DIFFERENCE(s.LastName, 'Smith') >= 4;
GO


-- =================================================================================
-- PART 4: FUZZY MATCHING ALGORITHMS (EDIT DISTANCE AND SIMILARITY)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - EDIT_DISTANCE (Levenshtein): Returns the absolute number of character insertions, deletions, and substitutions.
--   - EDIT_DISTANCE_SIMILARITY: Returns a normalized score from 0 (different) to 100 (identical).
--   - JARO_WINKLER_DISTANCE: Returns a value between 0.0 and 1.0, weighting matching initial characters.

-- IMPORTANT NOTE ABOUT THE SCALES:
--   - EDIT_DISTANCE is an absolute operation count; its value depends on string length.
--   - EDIT_DISTANCE_SIMILARITY is normalized to a score from 0 to 100.
--   - JARO_WINKLER_DISTANCE ranges from 0 to 1; lower means closer.
--   - JARO_WINKLER_SIMILARITY ranges from 0 to 100; higher means closer.
--   - For Jaro-Winkler, similarity is approximately (1 - distance) * 100.
--     Example: distance 0.33 corresponds to approximately 67% similarity.
--   - Do not compare EDIT_DISTANCE = 6 directly with JARO_WINKLER_DISTANCE = 0.33:
--     they are different metrics with different scales.
--   - Use thresholds appropriate to each metric, such as EditSimilarity >= 80
--     or JaroWinklerDistance <= 0.20.

-- Compatibility Note: EDIT_DISTANCE, EDIT_DISTANCE_SIMILARITY, and the JARO_WINKLER functions
-- are in preview in SQL Server 2025. Input values cannot be varchar(max)/nvarchar(max).
-- In earlier versions, SOUNDEX/DIFFERENCE are the native alternatives available.
-- To enable preview features in this study database, run separately (requires ALTER ANY DATABASE permission):
-- ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;

-- Compare the modern metrics. Lower distance means higher proximity;
-- higher similarity means better matching.
SELECT FullName,
       EDIT_DISTANCE(FullName, N'Alice Smith') AS EditDistance,
       EDIT_DISTANCE_SIMILARITY(FullName, N'Alice Smith') AS EditSimilarity,
       JARO_WINKLER_DISTANCE(FullName, N'Alice Smith') AS JaroWinklerDistance,
       JARO_WINKLER_SIMILARITY(FullName, N'Alice Smith') AS JaroWinklerSimilarity
FROM lab.RawContacts;
GO

-- Deduplication: thresholds reduce candidates before any merge.
-- `EditSimilarity >= 80` keeps pairs with at least 80% edit similarity.
-- `JaroWinklerDistance <= 0.20` keeps pairs with at most 20% Jaro-Winkler
-- distance, approximately 80% similarity or higher.
-- These values are starting points, not universal rules: tune them according
-- to data quality and the cost of false positives.
-- A value below 80 may include more unrelated pairs; a value above 80 may miss
-- duplicates with more spelling errors. For sensitive data, consider 95 or 98;
-- for very noisy data, 70 or 75 may be more suitable. Review candidates before MERGE.
-- `OR` keeps pairs approved by either metric; with `AND`, both metrics must approve.
SELECT c1.ContactID AS ID1,
       c1.FullName AS Name1,
       c2.ContactID AS ID2,
       c2.FullName AS Name2,
       EDIT_DISTANCE_SIMILARITY(c1.FullName, c2.FullName) AS EditSimilarity,
       JARO_WINKLER_DISTANCE(c1.FullName, c2.FullName) AS JaroWinklerDistance
FROM lab.RawContacts AS c1
JOIN lab.RawContacts AS c2 ON c1.ContactID < c2.ContactID
WHERE EDIT_DISTANCE_SIMILARITY(c1.FullName, c2.FullName) >= 80
   OR JARO_WINKLER_DISTANCE(c1.FullName, c2.FullName) <= 0.20;
GO


-- =================================================================================
-- PART 5: FULL-TEXT SEARCH (CONTAINS AND FREETEXT)
-- =================================================================================
-- Full-Text Search is created only when the feature is installed, a default
-- Full-Text catalog exists, and the table does not already have an index.
-- Population is asynchronous; if no rows are returned, wait and run the query again.
IF FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE is_default = 1)
        PRINT 'Create or designate a default Full-Text catalog before running this section.';
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1
                       FROM sys.fulltext_indexes
                       WHERE object_id = OBJECT_ID(N'lab.RawContacts'))
        BEGIN
            BEGIN TRY
                CREATE FULLTEXT INDEX ON lab.RawContacts (FullName LANGUAGE 1033)
                KEY INDEX PK_lab_RawContacts
                WITH CHANGE_TRACKING AUTO;
            END TRY
            BEGIN CATCH
                PRINT CONCAT('Full-Text index could not be created: ', ERROR_MESSAGE());
            END CATCH;
        END;

    END;
END
ELSE
    PRINT 'Full-Text Search is not installed on this instance; this section was skipped.';
GO

-- Batch 2: run the searches after the index-creation batch has completed.
-- Full-Text population is asynchronous; if no rows are returned, wait and retry.
-- PLAN IMPACT:
--   - CONTAINS and FREETEXT use the inverted Full-Text index. In the plan,
--     look for a Full-Text Match operation and a join back to the table by its
--     unique full-text key. The base-table access can still be a lookup when
--     selected columns are not covered by the full-text key.
--   - CONTAINS is more precise: terms, phrases, prefixes, Boolean operators,
--     and NEAR are translated into a structured full-text search condition.
--   - FREETEXT is broader: SQL Server analyzes the phrase with the word breaker
--     and stemmer, and searches by meaning/inflectional forms. This can return
--     more candidates and require more full-text processing than an exact term.
--   - Predicates only filter rows and do not return a relevance score. Use
--     CONTAINSTABLE or FREETEXTTABLE when the plan needs a RANK column for ordering.
--   - LIKE does not use the Full-Text index. `LIKE '%Smith%'` commonly requires
--     a scan because of the leading wildcard; a prefix such as `LIKE 'Smith%'
--     can be seekable with a suitable ordinary index.
IF FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') = 1
   AND EXISTS (SELECT 1 FROM sys.fulltext_indexes
               WHERE object_id = OBJECT_ID(N'lab.RawContacts'))
BEGIN
    -- Prefix search: matches words that start with Smith.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, '"Smith*"');

    -- Exact term search: matches the word Smith, not an arbitrary substring.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, '"Smith"');

    -- Phrase search: words must appear together and in this order.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, '"Alice Smith"');

    -- Boolean searches: both terms, or at least one term.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, '"Alice" AND "Smith"');

    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, '"Smith" OR "Smyth"');

    -- Proximity search: Alice and Smith within five terms, in this order.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, 'NEAR((Alice, Smith), 5, TRUE)');

    -- FREETEXT delegates linguistic interpretation to Full-Text Search.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE FREETEXT(FullName, N'Alice Smith');

    -- CONTAINSTABLE returns the matching key and RANK, which can be used to order
    -- results. The key joins the Full-Text result back to the base table.
    SELECT c.ContactID, c.FullName, ft.RANK AS RelevanceRank
    FROM CONTAINSTABLE(lab.RawContacts, FullName, N'"Smith"') AS ft
    JOIN lab.RawContacts AS c ON c.ContactID = ft.[KEY]
    ORDER BY ft.RANK DESC;

    -- FREETEXTTABLE applies the broader natural-language search and also returns RANK.
    SELECT c.ContactID, c.FullName, ft.RANK AS RelevanceRank
    FROM FREETEXTTABLE(lab.RawContacts, FullName, N'Alice Smith') AS ft
    JOIN lab.RawContacts AS c ON c.ContactID = ft.[KEY]
    ORDER BY ft.RANK DESC;

    -- LIKE is the substring equivalent: % can match Smith anywhere in the text.
    -- CONTAINS with "Smith*" searches a word prefix, not an arbitrary substring.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE FullName LIKE N'%Smith%';
END
ELSE
    PRINT 'A Full-Text index could not be found on lab.RawContacts.';
GO


-- PART 6: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

-- SCENARIO 1: Deduplication and name preparation before vectorization (Embeddings/RAG).
-- The workflow is intentionally read-only: generate candidates, score them, classify
-- confidence, and review the result before any UPDATE or MERGE.

-- 1. Normalize the text used by matching and embedding pipelines.
--    The original value is preserved for display and auditing.
SELECT ContactID,
       FullName AS OriginalName,
       UPPER(LTRIM(RTRIM(REPLACE(FullName, '  ', ' ')))) AS NormalizedName,
       SOUNDEX(FullName) AS SoundexCode
FROM lab.RawContacts;
GO

-- 2. Generate candidate pairs. ContactID < ContactID avoids comparing a row
--    with itself and avoids returning the same pair twice.
WITH Prepared AS
(
    SELECT ContactID,
           FullName,
           UPPER(LTRIM(RTRIM(REPLACE(FullName, '  ', ' ')))) AS NormalizedName
    FROM lab.RawContacts
), CandidatePairs AS
(
    SELECT p1.ContactID AS ID1,
           p1.FullName AS Name1,
           p2.ContactID AS ID2,
           p2.FullName AS Name2,
           EDIT_DISTANCE_SIMILARITY(p1.NormalizedName, p2.NormalizedName) AS EditSimilarity,
           JARO_WINKLER_DISTANCE(p1.NormalizedName, p2.NormalizedName) AS JaroWinklerDistance,
           DIFFERENCE(p1.NormalizedName, p2.NormalizedName) AS SoundexDifference
    FROM Prepared AS p1
    JOIN Prepared AS p2 ON p1.ContactID < p2.ContactID
)
SELECT ID1, Name1, ID2, Name2,
       EditSimilarity,
       JaroWinklerDistance,
       SoundexDifference
FROM CandidatePairs
WHERE EditSimilarity >= 80
   OR JaroWinklerDistance <= 0.20
   OR SoundexDifference >= 3;
GO

-- 3. Classify candidates instead of merging automatically.
--    HIGH requires stronger evidence from two metrics; REVIEW is a manual queue.
WITH Prepared AS
(
    SELECT ContactID,
           FullName,
           UPPER(LTRIM(RTRIM(REPLACE(FullName, '  ', ' ')))) AS NormalizedName
    FROM lab.RawContacts
), ScoredPairs AS
(
    SELECT p1.ContactID AS ID1, p1.FullName AS Name1,
           p2.ContactID AS ID2, p2.FullName AS Name2,
           EDIT_DISTANCE_SIMILARITY(p1.NormalizedName, p2.NormalizedName) AS EditSimilarity,
           JARO_WINKLER_DISTANCE(p1.NormalizedName, p2.NormalizedName) AS JaroWinklerDistance,
           DIFFERENCE(p1.NormalizedName, p2.NormalizedName) AS SoundexDifference
    FROM Prepared AS p1
    JOIN Prepared AS p2 ON p1.ContactID < p2.ContactID
)
SELECT ID1, Name1, ID2, Name2,
       EditSimilarity,
       JaroWinklerDistance,
       SoundexDifference,
       CASE
           WHEN EditSimilarity >= 95 AND JaroWinklerDistance <= 0.10 THEN 'HIGH'
           WHEN EditSimilarity >= 80 OR JaroWinklerDistance <= 0.20
                OR SoundexDifference >= 3 THEN 'REVIEW'
           ELSE 'LOW'
       END AS MatchConfidence
FROM ScoredPairs
WHERE EditSimilarity >= 80
   OR JaroWinklerDistance <= 0.20
   OR SoundexDifference >= 3;
GO

-- 4. Prepare a clean, unique name list for downstream embeddings or search.
--    This query does not merge source rows; it only shows the intended grain
--    of a normalized representation.
SELECT UPPER(LTRIM(RTRIM(REPLACE(FullName, '  ', ' ')))) AS NormalizedName,
       COUNT(*) AS SourceRowCount,
       STRING_AGG(CONVERT(varchar(12), ContactID), ', ') AS SourceContactIDs
FROM lab.RawContacts
GROUP BY UPPER(LTRIM(RTRIM(REPLACE(FullName, '  ', ' '))))
ORDER BY NormalizedName;
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/03-advanced-tsql/03-regex-fuzzy-matching.md
-- =================================================================================================
