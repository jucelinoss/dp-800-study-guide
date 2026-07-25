-- =================================================================================
-- DP-800 - PRACTICAL LAB: HYBRID SEARCH AND RECIPROCAL RANK FUSION (RRF)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates combining full-text search with semantic (vector) search:
--   1. Obtaining Full-Text Ranks via `FREETEXTTABLE`
--   2. Obtaining Vector Ranks via `VECTOR_DISTANCE` / `VECTOR_SEARCH`
--   3. Reciprocal Rank Fusion (RRF) algorithm in T-SQL with `k = 60`
--   4. Result Fusion via `FULL OUTER JOIN` and Final Score Calculation
--   5. Practical Project Scenarios (RAG Search Engine Optimization)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP PROCEDURE IF EXISTS lab.usp_ExecuteHybridSearchRRF;
DROP TABLE IF EXISTS lab.HybridProductsCatalog;
GO

-- Table Structure for Hybrid Search Test
CREATE TABLE lab.HybridProductsCatalog (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL,
    DescriptionVector NVARCHAR(MAX) NULL -- Vector serialized as JSON
);
GO

INSERT INTO lab.HybridProductsCatalog (ProductName, Description, DescriptionVector) VALUES
(N'Capacete Ciclismo Pro', N'Capacete leve com fibra de carbono e fones bluetooth embutidos', N'[0.025, -0.038, 0.089, 0.120]'),
(N'Fones Bluetooth Esportivos', N'Fones de ouvido sem fio bluetooth com cancelamento de ruido', N'[0.023, -0.035, 0.082, 0.115]'),
(N'Bicicleta de Trilha', N'Bicicleta de montanha para corridas com cambio 24 marchas', N'[-0.085, 0.120, -0.045, -0.010]');
GO


-- =================================================================================
-- PART 1: RECIPROCAL RANK FUSION (RRF) ALGORITHM IMPLEMENTATION IN T-SQL
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - HYBRID SEARCH: Combines exact keyword precision (FTS) with vector abstraction capability (Semantics).
--   - RRF FORMULA: `Score = 1.0 / (k + Rank_FTS) + 1.0 / (k + Rank_Vector)`.
--   - CONSTANT k: The default value of k is 60. Prevents a single top-ranked item from completely dominating the final ranking.

-- -- [DP-800 KEY POINT]
CREATE PROCEDURE lab.usp_ExecuteHybridSearchRRF
    @QueryText NVARCHAR(200),
    @TopN INT = 10,
    @RRF_k INT = 60
AS
BEGIN
    SET NOCOUNT ON;

    -- Simulation of FTS (Keyword) and Vector (Semantic) Ranks using CTEs
    WITH FTS_Results AS (
        SELECT 
            ProductID,
            ROW_NUMBER() OVER (ORDER BY ProductID ASC) AS FTSRank
        FROM lab.HybridProductsCatalog
        WHERE Description LIKE '%' + @QueryText + '%' OR ProductName LIKE '%' + @QueryText + '%'
    ),
    Vector_Results AS (
        SELECT 
            ProductID,
            ROW_NUMBER() OVER (ORDER BY ProductID ASC) AS VectorRank
        FROM lab.HybridProductsCatalog
    ),
    -- Fusion with RRF via FULL OUTER JOIN
    RRFFusion AS (
        SELECT 
            COALESCE(f.ProductID, v.ProductID) AS ProductID,
            f.FTSRank,
            v.VectorRank,
            -- Reciprocal Rank Fusion score calculation
            ISNULL(1.0 / (@RRF_k + f.FTSRank), 0.0) +
            ISNULL(1.0 / (@RRF_k + v.VectorRank), 0.0) AS RRFScore
        FROM FTS_Results f
        FULL OUTER JOIN Vector_Results v ON f.ProductID = v.ProductID
    )
    SELECT TOP (@TopN)
        r.ProductID,
        p.ProductName,
        p.Description,
        r.FTSRank,
        r.VectorRank,
        r.RRFScore
    FROM RRFFusion r
    JOIN lab.HybridProductsCatalog p ON p.ProductID = r.ProductID
    ORDER BY r.RRFScore DESC;
END;
GO

-- Test execution of the Hybrid Search procedure
EXEC lab.usp_ExecuteHybridSearchRRF @QueryText = N'bluetooth', @TopN = 5, @RRF_k = 60;
GO


-- =================================================================================
-- PART 2: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Performance Comparison and Evaluation Metrics in Hybrid Search
-- Architecture decision guide for RAG engine optimization.

SELECT 
    'Reciprocal Rank Fusion (RRF)' AS Algoritmo,
    'Usa apenas as POSIÇÕES de ranking (1º, 2º, 3º...)' AS Mecanismo,
    'k = 60' AS ConstantePadrao,
    'Nao exige normalizacao de pontuacoes entre sistemas heterogeneos' AS VantagemChave
UNION ALL
SELECT 
    'Score Combination (Soma Ponderada)',
    'Usa os SCORES brutos (ex: Cosine Similarity + BM25 Score)',
    'Exige Normalização (Min-Max Scaling)',
    'Requer que ambas as pontuações estejam na mesma escala (0.0 a 1.0)';
GO
