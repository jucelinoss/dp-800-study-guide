-- =================================================================================
-- DP-800 - PRACTICAL LAB: VECTOR SEARCH AND EMBEDDING DISTANCE (VECTOR_DISTANCE)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates vector storage and semantic similarity search in T-SQL:
--   1. Vector Property Storage and Inspection (`VECTORPROPERTY`)
--   2. Exact Nearest Neighbor (ENN) Distance Calculation with `VECTOR_DISTANCE` (Metrics: `cosine`, `euclidean`, `dot`)
--   3. Vector Normalization with `VECTOR_NORMALIZE(..., 'norm2')`
--   4. Approximate Nearest Neighbor (ANN via DiskANN) Indexing and the `VECTOR_SEARCH` Function
--   5. Practical Project Scenarios (Converting Distance to Similarity Score from 0 to 1)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.VectorProducts;
GO

-- Table Structure for Vector Storage (1536 dimensions)
CREATE TABLE lab.VectorProducts (
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL,
    DescriptionVector NVARCHAR(MAX) NOT NULL -- Simulation in JSON / VARBINARY in standard T-SQL
);
GO

-- Populate test data with simulated vectors
INSERT INTO lab.VectorProducts (ProductID, ProductName, Description, DescriptionVector) VALUES
(1, N'Capacete Ciclismo Pro', N'Capacete leve de alta protecao', N'[0.025, -0.038, 0.089, 0.120]'),
(2, N'Capacete Urbano', N'Capacete para uso diario na cidade', N'[0.023, -0.035, 0.082, 0.115]'),
(3, N'Bicicleta de Trilha', N'Bike mountain bike 24 marchas', N'[-0.085, 0.120, -0.045, -0.010]');
GO


-- =================================================================================
-- PART 1: EXACT NEAREST NEIGHBOR (ENN) DISTANCE QUERY
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - VECTOR_DISTANCE: Calculates the mathematical distance between the query vector and stored vectors.
--   - COSINE METRIC: Returns values between 0 (identical direction vectors) and 2 (opposite). Ideal for text.
--   - COSINE SIMILARITY: Calculated as `1.0 - VECTOR_DISTANCE('cosine', v1, v2)`.

-- -- [DP-800 KEY POINT]
-- Simulated Semantic Search Example (Finding the product closest to the Cycling Helmet Pro vector)
DECLARE @QueryVector NVARCHAR(MAX) = N'[0.025, -0.038, 0.089, 0.120]';

SELECT 
    ProductID,
    ProductName,
    Description,
    -- Simulation of VECTOR_DISTANCE function in offline environment
    CASE ProductID 
        WHEN 1 THEN 0.0000 -- Zero distance (exact vector)
        WHEN 2 THEN 0.0425 -- Very low distance (very close semantics)
        ELSE 0.8950        -- High distance (completely different product)
    END AS CosineDistance,
    -- Conversion to Similarity Score (0.0 to 1.0)
    1.0 - (CASE ProductID WHEN 1 THEN 0.0000 WHEN 2 THEN 0.0425 ELSE 0.8950 END) AS SimilarityScore
FROM lab.VectorProducts
ORDER BY CosineDistance ASC;
GO


-- =================================================================================
-- PART 2: APPROXIMATE VECTOR INDEXES (DISKANN AND VECTOR_SEARCH)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DISKANN: Vector index type optimized for disk-based storage and approximate graph search (ANN).
--   - VECTOR_SEARCH: Table function that consumes the DiskANN index to answer searches in sub-second time on tables with millions of rows.

-- -- [DP-800 KEY POINT]
-- DiskANN index creation structure (Reference syntax from official documentation)
/*
CREATE INDEX IX_VectorProducts_DescriptionVector
ON lab.VectorProducts (DescriptionVector)
USING DISKANN
WITH (METRIC = 'cosine');
*/
GO


-- =================================================================================
-- PART 3: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Vector Distance Metric Selection Matrix
-- Architecture decision guide for vector search optimization.

SELECT 
    'cosine' AS MetricaDistancia,
    '0.0 (Identico) a 2.0 (Oposto)' AS IntervaloValores,
    'Independe do tamanho da frase / magnitude do vetor' AS Vantagens,
    'Busca semantica de texto, RAG e comparacao de artigos' AS CasoDeUsoIdeal
UNION ALL
SELECT 
    'euclidean',
    '0.0 a Infinito',
    'Mede a distancia direta em linha reta entre os pontos no espaco',
    'Dados de coordenadas geograficas, imagens e atributos fisicos'
UNION ALL
SELECT 
    'dot',
    'Inverso do Produto Escalar',
    'Altissima velocidade computacional se os vetores forem normalizados',
    'Vetores pré-normalizados com L2 (VECTOR_NORMALIZE norm2)';
GO

-- SCENARIO 2: Hybrid ranking decision. RRF merges ranks and is safer when vector
-- distance and full-text RANK have unrelated scales. A weighted formula is valid
-- only when the numeric distance is available and both signals are normalized.
SELECT
    N'RRF' AS Pattern,
    N'Rank only: 1/(60 + rank)' AS Formula,
    N'Use when combining independent ranked candidate lists' AS UseCase
UNION ALL
SELECT
    N'Weighted score',
    N'(distance * 0.60) + ((1.0 - rank / 1000.0) * 0.40)',
    N'Use only after validating score distributions; lower result is better';
GO
-- VECTOR_SEARCH is ANN retrieval. If a formula needs the actual numeric distance,
-- calculate it with VECTOR_DISTANCE; do not pretend that ordered ANN output exposes it.
