-- =================================================================================
-- DP-800 - HANDS-ON LAB: VECTOR SEARCH (VECTOR, ENN, AND ANN)
-- Database: Azure SQL Database, SQL database in Fabric, or SQL Server 2025
-- =================================================================================
-- PREREQUISITES:
--   - VECTOR and VECTOR_DISTANCE: SQL Server 2025, Azure SQL Database, or SQL database in Fabric.
--   - VECTOR_SEARCH and CREATE VECTOR INDEX: preview features. SQL Server 2025 requires
--     PREVIEW_FEATURES; the latest index version is available in Azure SQL Database and Fabric.
--   - This lab uses four dimensions for readability. Production vectors must use the
--     embedding model's dimension, such as VECTOR(1536).
-- =================================================================================

-- NOTE: Theory content for this chapter is available at:
--       ../../../certification/10-intelligent-search/02-vector-search.md

USE AdventureWorks2025;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'lab')
    EXEC(N'CREATE SCHEMA lab AUTHORIZATION dbo;');
GO

IF OBJECT_ID(N'lab.VectorProducts', N'U') IS NOT NULL
    DROP INDEX IF EXISTS IX_VectorProducts_DescriptionVector ON lab.VectorProducts;
DROP TABLE IF EXISTS lab.VectorProducts;
GO

CREATE TABLE lab.VectorProducts (
    ProductID INT NOT NULL,
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL,
    DescriptionVector VECTOR(4) NOT NULL,
    CONSTRAINT PK_lab_VectorProducts PRIMARY KEY (ProductID)
);
GO

INSERT INTO lab.VectorProducts (ProductID, ProductName, Description, DescriptionVector) VALUES
(1, N'Pro Cycling Helmet', N'Lightweight helmet with high impact protection.', CAST(N'[0.025, -0.038, 0.089, 0.120]' AS VECTOR(4))),
(2, N'Urban Helmet', N'Helmet for daily city use.', CAST(N'[0.023, -0.035, 0.082, 0.115]' AS VECTOR(4))),
(3, N'Trail Bike', N'Mountain bike with 24 gears.', CAST(N'[-0.085, 0.120, -0.045, -0.010]' AS VECTOR(4))),
(4, N'Bluetooth Headphones', N'Wireless headphones with noise cancellation.', CAST(N'[0.310, 0.180, -0.220, 0.040]' AS VECTOR(4)));
GO

-- float16 is a preview option on supported platforms. Validate its dimension limits
-- and availability before using it: ALTER TABLE lab.VectorProducts ADD HalfVector VECTOR(1536, float16) NULL;

-- =================================================================================
-- PART 1: VECTOR, VECTORPROPERTY, AND NORMALIZATION
-- =================================================================================

SELECT ProductID,
       VECTORPROPERTY(DescriptionVector, 'Dimensions') AS Dimensions,
       VECTORPROPERTY(DescriptionVector, 'BaseType') AS BaseType
FROM lab.VectorProducts;
GO

-- L2 normalization is necessary when dot product is used as a cosine approximation.
-- VECTOR_DISTANCE('cosine', ...) itself does not require prior normalization.
SELECT ProductID,
       VECTOR_NORMALIZE(DescriptionVector, 'norm2') AS NormalizedVector
FROM lab.VectorProducts;
GO

-- VECTOR_NORM reports magnitude; VECTOR_NORMALIZE returns a unit-length vector.
SELECT TOP (4)
       ProductID,
       VECTOR_NORM(DescriptionVector, 'norm2') AS L2NormBefore,
       VECTOR_NORM(VECTOR_NORMALIZE(DescriptionVector, 'norm2'), 'norm2') AS L2NormAfter
FROM lab.VectorProducts;
GO

/* Normalize persisted vectors only when the chosen model and metric require it.
UPDATE lab.VectorProducts
SET DescriptionVector = VECTOR_NORMALIZE(DescriptionVector, 'norm2');
*/
GO

-- Optional float16 demonstration (preview; do not run on unsupported platforms).
-- float16 keeps the same dimension count but uses 2 bytes per component instead
-- of 4 bytes for float32. It is a precision/storage trade-off, not a new model.
/*
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO
CREATE TABLE lab.VectorFloat16Demo
(
    ProductID INT PRIMARY KEY,
    Embedding VECTOR(4, float16) NULL
);
INSERT INTO lab.VectorFloat16Demo (ProductID, Embedding)
VALUES (1, CAST(N'[0.025, -0.038, 0.089, 0.120]' AS VECTOR(4, float16)));
SELECT ProductID,
       VECTORPROPERTY(Embedding, 'Dimensions') AS Dimensions,
       VECTORPROPERTY(Embedding, 'BaseType') AS BaseType
FROM lab.VectorFloat16Demo;
*/
GO

-- =================================================================================
-- PART 2: ENN — EXACT SEARCH WITH VECTOR_DISTANCE
-- =================================================================================

DECLARE @QueryVector VECTOR(4) = CAST(N'[0.025, -0.038, 0.089, 0.120]' AS VECTOR(4));

SELECT TOP (3)
       ProductID,
       ProductName,
       VECTOR_DISTANCE('cosine', DescriptionVector, @QueryVector) AS CosineDistance,
       1.0 - VECTOR_DISTANCE('cosine', DescriptionVector, @QueryVector) AS CosineSimilarity,
       VECTOR_DISTANCE('euclidean', DescriptionVector, @QueryVector) AS EuclideanDistance,
       VECTOR_DISTANCE('dot', DescriptionVector, @QueryVector) AS DotDistance
FROM lab.VectorProducts
WHERE DescriptionVector IS NOT NULL
ORDER BY CosineDistance ASC;
GO

-- Structured filters restrict the candidate set before ranking. In a real
-- application, apply tenant/authorization filters to the allowed rows as well.
SELECT TOP (3)
       ProductID,
       ProductName,
       VECTOR_DISTANCE('cosine', DescriptionVector, @QueryVector) AS CosineDistance
FROM lab.VectorProducts
WHERE ProductID IN (1, 2)
  AND DescriptionVector IS NOT NULL
ORDER BY CosineDistance ASC;
GO

-- Real query embeddings must use the same model as persisted embeddings.
/*
DECLARE @RealQueryVector VECTOR(1536) = AI_GENERATE_EMBEDDINGS(
    N'comfortable helmet for urban cycling' USE MODEL [AzureOpenAI_Embedding_Small]
);
*/
GO

-- Error cases to test deliberately (leave commented so the lab remains runnable):
-- SELECT VECTOR_DISTANCE('cosine', DescriptionVector,
--     CAST(N'[0.1, 0.2, 0.3]' AS VECTOR(3))) FROM lab.VectorProducts;
-- SELECT VECTOR_DISTANCE('cosine', NULL, @QueryVector);
-- The first query demonstrates dimension mismatch; the second demonstrates NULL handling.

-- =================================================================================
-- PART 3: ANN — VECTOR INDEX AND VECTOR_SEARCH (PREVIEW)
-- =================================================================================
-- ANN trades a small amount of recall for lower latency at scale. Vector indexes need
-- at least 100 non-NULL vectors; these copies make the prerequisite visible.

;WITH Numbers AS (
    SELECT 5 AS Number
    UNION ALL
    SELECT Number + 1 FROM Numbers WHERE Number < 104
)
INSERT INTO lab.VectorProducts (ProductID, ProductName, Description, DescriptionVector)
SELECT Number,
       CONCAT(N'Test product ', Number),
       N'Additional vector used by the approximate-index exercise.',
       CAST(N'[0.025, -0.038, 0.089, 0.120]' AS VECTOR(4))
FROM Numbers
OPTION (MAXRECURSION 100);
GO

-- Run only on a platform where the preview is available.
-- SQL Server 2025: ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
/*
CREATE VECTOR INDEX IX_VectorProducts_DescriptionVector
ON lab.VectorProducts (DescriptionVector)
WITH (METRIC = 'cosine', TYPE = 'DiskANN');

DECLARE @ApproximateQuery VECTOR(4) = CAST(N'[0.025, -0.038, 0.089, 0.120]' AS VECTOR(4));

SELECT TOP (10) WITH APPROXIMATE
       p.ProductID, p.ProductName, vs.distance AS CosineDistance
FROM VECTOR_SEARCH(
    TABLE = lab.VectorProducts AS p,
    COLUMN = DescriptionVector,
    SIMILAR_TO = @ApproximateQuery,
    METRIC = 'cosine'
) AS vs
ORDER BY vs.distance;
*/
GO

-- Optional recall benchmark. Run after creating the preview vector index above.
-- ENN is the exact baseline; ANN recall is overlap with that baseline.
/*
DECLARE @ApproximateQuery VECTOR(4) = CAST(N'[0.025, -0.038, 0.089, 0.120]' AS VECTOR(4));

DECLARE @ExactIds TABLE (ProductID INT PRIMARY KEY);
INSERT INTO @ExactIds (ProductID)
SELECT TOP (10) ProductID
FROM lab.VectorProducts
WHERE DescriptionVector IS NOT NULL
ORDER BY VECTOR_DISTANCE('cosine', DescriptionVector, @ApproximateQuery);

DECLARE @ApproximateIds TABLE (ProductID INT PRIMARY KEY);
INSERT INTO @ApproximateIds (ProductID)
SELECT TOP (10) p.ProductID
FROM VECTOR_SEARCH(
    TABLE = lab.VectorProducts AS p,
    COLUMN = DescriptionVector,
    SIMILAR_TO = @ApproximateQuery,
    METRIC = 'cosine'
) AS vs
ORDER BY vs.distance;

SELECT
    COUNT(*) AS ExactTopK,
    (SELECT COUNT(*) FROM @ApproximateIds) AS ApproximateTopK,
    COUNT(a.ProductID) AS OverlapWithExact,
    CAST(COUNT(a.ProductID) * 1.0 / NULLIF(COUNT(*), 0) AS DECIMAL(5,4)) AS RecallAgainstENN
FROM @ExactIds e
LEFT JOIN @ApproximateIds a ON a.ProductID = e.ProductID;
*/
GO

-- =================================================================================
-- PART 4: DESIGN DECISIONS
-- =================================================================================

SELECT 'cosine' AS Metric, '0 (same direction) to 2 (opposite)' AS Range,
       'Text embeddings, RAG, and documents' AS UseCase,
       'No prior normalization required' AS Note
UNION ALL
SELECT 'euclidean', '0 to infinity', 'Coordinates and attributes where magnitude matters',
       'The ANN index and query must use the same metric'
UNION ALL
SELECT 'dot', 'Negative dot product as distance', 'L2-normalized vectors',
       'Normalize first for cosine equivalence';
GO

-- Do not mix models, dimensions, or metrics in one search space.
-- Use ENN for small sets and validation; use ANN to reduce latency at scale.

-- =================================================================================================
-- THEORY REFERENCE: ../../../certification/10-intelligent-search/02-vector-search.md
-- =================================================================================================
