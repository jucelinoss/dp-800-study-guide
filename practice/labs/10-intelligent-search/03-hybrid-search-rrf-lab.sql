-- =================================================================================
-- DP-800 - HANDS-ON LAB: HYBRID SEARCH AND RECIPROCAL RANK FUSION (RRF)
-- Database: Azure SQL Database, SQL database in Fabric, or SQL Server 2025
-- =================================================================================
-- PREREQUISITES: Full-Text Search and the VECTOR data type must be available.
-- The optional ANN section also requires the preview vector index and VECTOR_SEARCH.
-- =================================================================================
-- This script demonstrates:
--   1. Real candidate sources: FREETEXTTABLE and VECTOR_DISTANCE
--   2. Independent ranks joined with FULL OUTER JOIN
--   3. RRF: sum of 1 / (k + rank), without mixing incompatible scores
--   4. Ground-truth evaluation: precision@K, recall@K, MRR, and latency
--   5. Tuning k, candidate counts, and an optional ANN source
-- =================================================================================

-- NOTE: Theory content for this chapter is available at:
--       ../../../certification/10-intelligent-search/03-hybrid-search-rrf.md

USE AdventureWorks2025;
GO

IF EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'lab.HybridProductsCatalog'))
    DROP FULLTEXT INDEX ON lab.HybridProductsCatalog;
IF EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'LabHybridFtsCatalog')
    DROP FULLTEXT CATALOG LabHybridFtsCatalog;
DROP TABLE IF EXISTS lab.HybridGroundTruth;
DROP TABLE IF EXISTS lab.HybridProductsCatalog;
GO

CREATE TABLE lab.HybridProductsCatalog (
    ProductID INT IDENTITY(1,1) NOT NULL,
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL,
    DescriptionVector VECTOR(4) NOT NULL,
    CONSTRAINT PK_lab_HybridProductsCatalog PRIMARY KEY (ProductID)
);
GO

INSERT INTO lab.HybridProductsCatalog (ProductName, Description, DescriptionVector) VALUES
(N'Pro Cycling Helmet', N'Lightweight carbon-fiber helmet with built-in Bluetooth headphones.', CAST(N'[0.025, -0.038, 0.089, 0.120]' AS VECTOR(4))),
(N'Sport Bluetooth Headphones', N'Comfortable wireless Bluetooth headphones with noise cancellation.', CAST(N'[0.023, -0.035, 0.082, 0.115]' AS VECTOR(4))),
(N'Trail Bike', N'Mountain bike for racing with 24 gears.', CAST(N'[-0.085, 0.120, -0.045, -0.010]' AS VECTOR(4))),
(N'Urban Helmet', N'Comfortable helmet for daily city commuting.', CAST(N'[0.020, -0.030, 0.076, 0.110]' AS VECTOR(4)));
GO

CREATE FULLTEXT CATALOG LabHybridFtsCatalog;
GO

CREATE FULLTEXT INDEX ON lab.HybridProductsCatalog (
    ProductName LANGUAGE 1033,
    Description LANGUAGE 1033
)
KEY INDEX PK_lab_HybridProductsCatalog
ON LabHybridFtsCatalog
WITH (CHANGE_TRACKING = AUTO, STOPLIST = SYSTEM);
GO

WAITFOR DELAY '00:00:02';
GO

CREATE TABLE lab.HybridGroundTruth (
    QueryText NVARCHAR(200) NOT NULL,
    ProductID INT NOT NULL,
    CONSTRAINT PK_lab_HybridGroundTruth PRIMARY KEY (QueryText, ProductID),
    CONSTRAINT FK_lab_HybridGroundTruth_Product FOREIGN KEY (ProductID)
        REFERENCES lab.HybridProductsCatalog(ProductID)
);

INSERT INTO lab.HybridGroundTruth (QueryText, ProductID) VALUES
(N'comfortable bluetooth', 2),
(N'comfortable bluetooth', 1),
(N'helmet for city', 4),
(N'helmet for city', 1);
GO

-- =================================================================================
-- PART 1: REAL HYBRID SEARCH WITH RRF
-- =================================================================================

DECLARE @QueryText NVARCHAR(200) = N'comfortable bluetooth';
DECLARE @QueryVector VECTOR(4) = CAST(N'[0.023, -0.035, 0.082, 0.115]' AS VECTOR(4));
DECLARE @CandidateCount INT = 50;
DECLARE @TopN INT = 10;
DECLARE @RrfK INT = 60;
DECLARE @StartedAt DATETIME2(7) = SYSUTCDATETIME();
DECLARE @HybridResults TABLE (
    FinalRank INT NOT NULL,
    ProductID INT NOT NULL,
    ProductName NVARCHAR(100) NOT NULL,
    FtsRank INT NULL,
    VectorRank INT NULL,
    VectorDistance FLOAT NULL,
    RrfScore FLOAT NOT NULL
);

;WITH FtsResults AS (
    SELECT f.[KEY] AS ProductID,
           f.[RANK] AS FtsScore,
           ROW_NUMBER() OVER (ORDER BY f.[RANK] DESC) AS FtsRank
    FROM FREETEXTTABLE(
        lab.HybridProductsCatalog,
        (ProductName, Description),
        @QueryText,
        LANGUAGE 1033,
        @CandidateCount
    ) AS f
),
VectorResults AS (
    SELECT TOP (@CandidateCount)
           p.ProductID,
           VECTOR_DISTANCE('cosine', p.DescriptionVector, @QueryVector) AS VectorDistance,
           ROW_NUMBER() OVER (ORDER BY VECTOR_DISTANCE('cosine', p.DescriptionVector, @QueryVector)) AS VectorRank
    FROM lab.HybridProductsCatalog AS p
    WHERE p.DescriptionVector IS NOT NULL
    ORDER BY VectorDistance
),
RrfScores AS (
    SELECT COALESCE(f.ProductID, v.ProductID) AS ProductID,
           f.FtsRank, v.VectorRank, v.VectorDistance,
           ISNULL(1.0 / (@RrfK + f.FtsRank), 0.0) +
           ISNULL(1.0 / (@RrfK + v.VectorRank), 0.0) AS RrfScore
    FROM FtsResults AS f
    FULL OUTER JOIN VectorResults AS v ON v.ProductID = f.ProductID
),
RankedResults AS (
    SELECT TOP (@TopN)
           ROW_NUMBER() OVER (ORDER BY RrfScore DESC, ProductID) AS FinalRank,
           ProductID, FtsRank, VectorRank, VectorDistance, RrfScore
    FROM RrfScores
    ORDER BY RrfScore DESC, ProductID
)
INSERT INTO @HybridResults (FinalRank, ProductID, ProductName, FtsRank, VectorRank, VectorDistance, RrfScore)
SELECT r.FinalRank, p.ProductID, p.ProductName,
       r.FtsRank, r.VectorRank, r.VectorDistance, r.RrfScore
FROM RankedResults AS r
JOIN lab.HybridProductsCatalog AS p ON p.ProductID = r.ProductID;

DECLARE @LatencyMs INT = DATEDIFF(MILLISECOND, @StartedAt, SYSUTCDATETIME());

SELECT FinalRank, ProductID, ProductName, FtsRank, VectorRank, VectorDistance, RrfScore
FROM @HybridResults
ORDER BY FinalRank;

-- RRF combines ranks, not the full-text RANK or the vector distance. FULL OUTER JOIN
-- retains documents returned by only one of the sources.

-- =================================================================================
-- PART 2: GROUND-TRUTH EVALUATION
-- =================================================================================

SELECT
    @QueryText AS QueryText,
    @TopN AS K,
    CAST(SUM(CASE WHEN gt.ProductID IS NOT NULL THEN 1.0 ELSE 0 END) / NULLIF(@TopN, 0) AS DECIMAL(5,4)) AS PrecisionAtK,
    CAST(SUM(CASE WHEN gt.ProductID IS NOT NULL THEN 1.0 ELSE 0 END) /
         NULLIF((SELECT COUNT(*) FROM lab.HybridGroundTruth WHERE QueryText = @QueryText), 0) AS DECIMAL(5,4)) AS RecallAtK,
    CAST(1.0 / NULLIF(MIN(CASE WHEN gt.ProductID IS NOT NULL THEN r.FinalRank END), 0) AS DECIMAL(5,4)) AS ReciprocalRank,
    @LatencyMs AS LatencyMs
FROM @HybridResults AS r
LEFT JOIN lab.HybridGroundTruth AS gt
    ON gt.QueryText = @QueryText
   AND gt.ProductID = r.ProductID;
GO

-- =================================================================================
-- PART 3: TUNING k, CANDIDATES, AND ANN
-- =================================================================================
-- Rerun part 1 with @RrfK = 20, 60, and 100, keeping the same test queries and
-- ground truth. Tune @CandidateCount before tuning k: RRF cannot recover a document
-- that neither source returned.

-- For large collections, replace VectorResults with ANN. It requires 100 non-NULL
-- vectors and preview features. The sample rows below satisfy the minimum.
/*
;WITH Numbers AS (
    SELECT 1 AS Number
    UNION ALL
    SELECT Number + 1 FROM Numbers WHERE Number < 100
)
INSERT INTO lab.HybridProductsCatalog (ProductName, Description, DescriptionVector)
SELECT CONCAT(N'Additional product ', Number),
       N'Demonstration row for the ANN vector-index minimum.',
       CAST(N'[0.023, -0.035, 0.082, 0.115]' AS VECTOR(4))
FROM Numbers
OPTION (MAXRECURSION 100);

CREATE VECTOR INDEX IX_HybridProducts_DescriptionVector
ON lab.HybridProductsCatalog (DescriptionVector)
WITH (METRIC = 'cosine', TYPE = 'DiskANN');

DECLARE @ApproximateQuery VECTOR(4) = CAST(N'[0.023, -0.035, 0.082, 0.115]' AS VECTOR(4));

SELECT TOP (50) WITH APPROXIMATE p.ProductID, vs.distance
FROM VECTOR_SEARCH(
    TABLE = lab.HybridProductsCatalog AS p,
    COLUMN = DescriptionVector,
    SIMILAR_TO = @ApproximateQuery,
    METRIC = 'cosine'
) AS vs
ORDER BY vs.distance;
*/
GO

-- =================================================================================
-- PART 4: DESIGN DECISIONS
-- =================================================================================

SELECT N'RRF' AS Strategy,
       N'Sum of 1 / (k + rank)' AS Formula,
       N'When full-text and vector scores use different scales' AS UseCase,
       N'Validate k, candidates, recall, precision, MRR, and latency' AS Validation
UNION ALL
SELECT N'Weighted score',
       N'Previously normalized distance and rank',
       N'Only after validating a common score scale',
       N'Do not add a full-text RANK directly to vector distance';
GO

-- =================================================================================================
-- THEORY REFERENCE: ../../../certification/10-intelligent-search/03-hybrid-search-rrf.md
-- =================================================================================================
