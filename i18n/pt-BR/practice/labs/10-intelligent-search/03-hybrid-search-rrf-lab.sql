-- =================================================================================
-- DP-800 - LAB PRÁTICO: BUSCA HÍBRIDA E RECIPROCAL RANK FUSION (RRF)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a combinação de busca palavreada (Full-Text) com busca semântica (Vetores):
--   1. Obtenção de Ranks do Full-Text via `FREETEXTTABLE`
--   2. Obtenção de Ranks do Vetorial via `VECTOR_DISTANCE` / `VECTOR_SEARCH`
--   3. Algoritmo Reciprocal Rank Fusion (RRF) em T-SQL com `k = 60`
--   4. Fusão de Resultados via `FULL OUTER JOIN` e Cálculo de Score Final
--   5. Cenários Práticos de Projeto (Otimização de Motores de Pesquisa RAG)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP PROCEDURE IF EXISTS lab.usp_ExecuteHybridSearchRRF;
DROP TABLE IF EXISTS lab.HybridProductsCatalog;
GO

-- Estrutura de Tabela para Teste de Busca Híbrida
CREATE TABLE lab.HybridProductsCatalog (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL,
    DescriptionVector NVARCHAR(MAX) NULL -- Vetor serializado em JSON
);
GO

INSERT INTO lab.HybridProductsCatalog (ProductName, Description, DescriptionVector) VALUES
(N'Capacete Ciclismo Pro', N'Capacete leve com fibra de carbono e fones bluetooth embutidos', N'[0.025, -0.038, 0.089, 0.120]'),
(N'Fones Bluetooth Esportivos', N'Fones de ouvido sem fio bluetooth com cancelamento de ruido', N'[0.023, -0.035, 0.082, 0.115]'),
(N'Bicicleta de Trilha', N'Bicicleta de montanha para corridas com cambio 24 marchas', N'[-0.085, 0.120, -0.045, -0.010]');
GO


-- =================================================================================
-- PARTE 1: IMPLEMENTAÇÃO DO ALGORITMO RECIPROCAL RANK FUSION (RRF) EM T-SQL
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - BUSCA HÍBRIDA: Une a precisão de palavras-chave exatas (FTS) com a capacidade de abstração do vetor (Semântica).
--   - FORMULA RRF: `Score = 1.0 / (k + Rank_FTS) + 1.0 / (k + Rank_Vetor)`.
--   - CONSTANTE k: O valor padrão de k é 60. Evita que um primeiro colocado isolado domine completamente o ranking final.

-- -- [PONTO DE ATENÇÃO DP-800]
CREATE PROCEDURE lab.usp_ExecuteHybridSearchRRF
    @QueryText NVARCHAR(200),
    @TopN INT = 10,
    @RRF_k INT = 60
AS
BEGIN
    SET NOCOUNT ON;

    -- Simulação dos Ranks de FTS (Palavra-chave) e Vetor (Semântica) usando CTEs
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
    -- Fusão com RRF via FULL OUTER JOIN
    RRFFusion AS (
        SELECT 
            COALESCE(f.ProductID, v.ProductID) AS ProductID,
            f.FTSRank,
            v.VectorRank,
            -- Cálculo da pontuação Reciprocal Rank Fusion
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

-- Testar execução do procedimento de Busca Híbrida
EXEC lab.usp_ExecuteHybridSearchRRF @QueryText = N'bluetooth', @TopN = 5, @RRF_k = 60;
GO


-- =================================================================================
-- PARTE 2: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Comparativo de Performance e Métricas de Avaliação em Busca Híbrida
-- Guia de decisão de arquitetura para otimização de motores RAG.

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
