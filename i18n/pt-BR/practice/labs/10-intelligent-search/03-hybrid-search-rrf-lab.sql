-- =================================================================================
-- DP-800 - LAB PRATICO COMPLETO: HYBRID SEARCH + RECIPROCAL RANK FUSION (RRF)
-- Banco de Dados: AdventureWorks2025 (ou LT - Light)
-- =================================================================================
-- OBJETIVOS DP-800 DOMINIO 3 Intelligent Search:
--   1. Quando usar FTS vs Vector vs HYBRID (tabela de cenarios)
--   2. Formula RRF: score = Σ 1/(k + rank) — k=60 convencao MS Learn
--   3. Exemplo NUMERICO passo-a-passo calculando RRF manual (tabela passo 4 docs)
--   4. FULL OUTER JOIN por que OBRIGATORIO vs INNER JOIN (tabela comparativa)
--   5. Setup HIBRIDO em AdventureWorks: tabela materializada FTS + VECTOR reutiliza labs 01/02
--   6. Implementacao Completa: FREETEXTTABLE (RANK 0-1000) + VECTOR_DISTANCE cosine
--   7. Procedure usp_HybridSearch AW reutilizavel: parametros, filtros categoria/preco
--   8. Ajuste de k: k=1 vs k=20 vs k=60 vs k=100 (tabela comparacao)
--   9. Metricas Avaliacao: Precision@K / Recall@K / MRR tabelas formulas
--  10. Ground Truth AW: tabela lab.HybridGroundTruth + avaliacao
--  11. Fallback: FTS vazio -> so vetorial, Vector vazio -> so FTS
--  12. Questao Exame 4 alternativas gabarito comentado
-- =================================================================================
-- REFERENCIAS MS LEARN:
--   Hybrid Search Azure AI Search: https://learn.microsoft.com/azure/search/hybrid-search-overview
--   Reciprocal Rank Fusion:     https://learn.microsoft.com/azure/search/hybrid-search-ranking
-- =================================================================================
-- REFERENCIA TEORICA: ../../../certification/10-intelligent-search/03-hybrid-search-rrf.md
--    Abra o guia teorico junto com este laboratorio para contexto conceitual.

USE AdventureWorks2025;
GO

-- =================================================================================
-- LIMPEZA PREVENTIVA (ordem correta: FTS INDEX -> CATALOG -> TABLES/PROC)
-- =================================================================================
IF EXISTS (SELECT * FROM sys.fulltext_indexes
           WHERE object_id = OBJECT_ID(N'lab.HybridProductCatalog'))
    DROP FULLTEXT INDEX ON lab.HybridProductCatalog;
IF EXISTS (SELECT * FROM sys.fulltext_catalogs WHERE name = N'AW_HybridFtsCatalog')
    DROP FULLTEXT CATALOG AW_HybridFtsCatalog;

DROP PROCEDURE IF EXISTS lab.usp_HybridProductSearch;
DROP TABLE IF EXISTS lab.HybridGroundTruth;
DROP TABLE IF EXISTS lab.HybridProductCatalog;
GO

CREATE SCHEMA IF NOT EXISTS lab AUTHORIZATION dbo;
GO

-- =================================================================================
-- PARTE 1/8: Conceitos + Quando usar cada busca + Formula RRF
-- =================================================================================
PRINT '=========================================================';
PRINT '  LAB 10-IS (03) PARTE 1/8: CENARIOS + FORMULA RRF';
PRINT '=========================================================';
GO

-- 1.1 Quando usar FTS, Vector, Hybrid (tabela SEMPRE cai no exame!)
SELECT
    N'SKU exato, codigo de produto (BK-M38S-42), numero de serial' AS CenarioQuery,
    N'Somente FTS (CONTAINS/CONTAINSTABLE)'                      AS MelhorAbordagem,
    N'Palavras exatas = FTS e infalivel. Vetorial = "parecido" = risco de erro.' AS PorQue
UNION ALL SELECT
    N'Query intencao vaga: "bike confortavel para trilha longa"',
    N'Somente Vetorial (VECTOR_DISTANCE cosine)',
    N'Vetorial encontra por SEMANTICA, nao por palavras. O usuario nao sabe o nome do produto.'
UNION ALL SELECT
    N'Query curta misturando palavras-chave + conceito: "Mountain 200 bike"',
    N'HIBRIDO RRF (recomendado 70% dos casos reais)',
    N'Palavras exatas batem com FTS, significado parecido com vetores. RRF combina os ranks.'
UNION ALL SELECT
    N'Multilingue (ingles + portugues misturados, traduzir na busca)',
    N'Principalmente Vetorial + fallback FTS para palavras exatas',
    N'Embeddings fazem cross-lingual bem. FTS exige idioma LCID definido por coluna.'
UNION ALL SELECT
    N'Busca em FAQ / Help Desk / KB de Suporte Tecnico',
    N'HIBRIDO RRF (MELHOR CASO DE USO!)',
    N'Usuarios parafraseiam FAQ: FTS erra por sinonimos, vec pega intencao. RRF combina!';
GO

PRINT CHAR(13)+CHAR(10) + N'--- Formula RRF OFICIAL Microsoft Learn ---';
PRINT N'';
PRINT N'   RRF_score(documento)  =  Σ  1 / (k + rank_dentro_da_lista)';
PRINT N'';
PRINT N'   - k = constante de "amortecimento". Convencao = 60. ';
PRINT N'       k=1  -> rank #1 pesa MUITO (topo da lista domina)';
PRINT N'       k=60 -> distribuicao justa, varias fontes importam (padrao)';
PRINT N'       k=100-> pesos quase uniformes, quase um "vote counting".';
PRINT N'';
PRINT N'   - rank = POSICAO (1-based) DO DOCUMENTO na lista FTS / Vector';
PRINT N'   - soma-se 1/(k+rank_fts) + 1/(k+rank_vector).';
PRINT N'   - MAIOR score = MELHOR resultado combinado.';
GO

-- 1.3 Exemplo NUMERICO passo-a-passo (4 produtos tabela exame)
PRINT CHAR(13)+CHAR(10) + N'--- Exemplo passo-a-passo RRF. k=60. ---';
SELECT
    N'Produto A'                                                        AS Documento,
    1                                                                   AS RankFTS,
    3                                                                   AS RankVector,
    CAST(1.0/(60+1) AS DECIMAL(7,5))                                    AS ParcelaFts,
    CAST(1.0/(60+3) AS DECIMAL(7,5))                                    AS ParcelaVec,
    CAST(1.0/(60+1) + 1.0/(60+3) AS DECIMAL(8,5))                      AS RRFScore
UNION ALL SELECT N'Produto B', 5, 1,
    CAST(1.0/65 AS DECIMAL(7,5)), CAST(1.0/61 AS DECIMAL(7,5)),
    CAST(1.0/65 + 1.0/61 AS DECIMAL(8,5))
UNION ALL SELECT N'Produto C', 2, 50,
    CAST(1.0/62 AS DECIMAL(7,5)), CAST(1.0/110 AS DECIMAL(7,5)),
    CAST(1.0/62 + 1.0/110 AS DECIMAL(8,5))
UNION ALL SELECT N'Produto D', 100, 2,
    CAST(1.0/160 AS DECIMAL(7,5)), CAST(1.0/62 AS DECIMAL(7,5)),
    CAST(1.0/160 + 1.0/62 AS DECIMAL(8,5));
GO

-- =================================================================================
-- PARTE 2/8: Setup Hybrid AdventureWorks (FTS + Vector na mesma tabela!)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (03) PARTE 2/8: SETUP TABELA HIBRIDA ADVENTUREWORKS';
PRINT '=========================================================';
GO

-- Tabela unica: FTS (colunas textuais indexadas por palavra) + VECTOR(1536) (semantica)
SELECT
    p.ProductID,
    CAST(p.Name AS NVARCHAR(250))         AS ProductName,
    CAST(pc.Name AS NVARCHAR(100))        AS Category,
    CAST(psc.Name AS NVARCHAR(100))        AS Subcategory,
    CAST(p.ListPrice AS MONEY)             AS ListPrice,
    CAST(ISNULL(pd.Description, N'AdventureWorks high quality product.')
      + N' Color: ' + ISNULL(p.Color, N'N/A')
      + N' Weight: ' + ISNULL(CAST(p.Weight AS VARCHAR(20)), N'N/A') + N' kg'
      + N' Size: ' + ISNULL(p.Size, N'N/A')
     AS NVARCHAR(MAX))                     AS SearchDocument,
    CAST(NULL AS VECTOR(1536))              AS Embedding,
    CONSTRAINT PK_lab_HybridProductCatalog PRIMARY KEY CLUSTERED (ProductID)
INTO lab.HybridProductCatalog
FROM Production.Product p
INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
INNER JOIN Production.ProductCategory pc     ON pc.ProductCategoryID = psc.ProductCategoryID
LEFT JOIN Production.ProductModelProductDescriptionCulture pmpdc
       ON pmpdc.ProductModelID = p.ProductModelID AND pmpdc.CultureID = N'en'
LEFT JOIN Production.ProductDescription pd ON pd.ProductDescriptionID = pmpdc.ProductDescriptionID
WHERE p.ListPrice > 0;
GO

-- 2.1 Popular Embeddings simulados por CATEGORIA (mesma logica do lab 02)
WITH CatVectors AS (
    SELECT
        Category,
        ABS(CHECKSUM(Category))                        AS Seed1,
        ABS(CHECKSUM(REVERSE(Category))) % 9973        AS Seed2,
        DENSE_RANK() OVER (ORDER BY Category) * 0.0011      AS CatOff
    FROM (SELECT DISTINCT Category FROM lab.HybridProductCatalog) d
),
VecByCat AS (
    SELECT
        cv.Category,
        N'[' + STRING_AGG(CAST(
            SIN( (cv.Seed1 % 360) + n * (0.017 + cv.CatOff) )
            + 0.2 * COS(n * 0.0031 + (cv.Seed2 % 180) * 0.017)
        AS VARCHAR(20)), N',') + N']' AS VecJson
    FROM CatVectors cv
    CROSS APPLY (SELECT TOP (1536) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b) tally
    GROUP BY cv.Category, cv.Seed1, cv.Seed2, cv.CatOff
)
UPDATE hpc SET hpc.Embedding = CAST(vbc.VecJson AS VECTOR(1536))
FROM lab.HybridProductCatalog hpc
INNER JOIN VecByCat vbc ON vbc.Category = hpc.Category;
GO

SELECT COUNT(*) TotalLinhas,
       COUNT(DISTINCT Category) QtdCategorias,
       COUNT(Embedding) QtdEmbeddingsOk
FROM lab.HybridProductCatalog;
GO

-- 2.2 Criar FTS Catalog + Index
CREATE FULLTEXT CATALOG AW_HybridFtsCatalog AS DEFAULT;
GO

CREATE FULLTEXT STOPLIST AW_HybridStopList FROM SYSTEM STOPLIST;
ALTER FULLTEXT STOPLIST AW_HybridStopList ADD N'product' LANGUAGE N'English';
GO

CREATE FULLTEXT INDEX ON lab.HybridProductCatalog (
    ProductName     LANGUAGE N'English',
    Category      LANGUAGE N'English',
    Subcategory   LANGUAGE N'English',
    SearchDocument LANGUAGE N'English'
)
KEY INDEX PK_lab_HybridProductCatalog
ON AW_HybridFtsCatalog
WITH (CHANGE_TRACKING = AUTO, STOPLIST = AW_HybridStopList);
GO

WAITFOR DELAY '00:00:03';
GO

PRINT N'--- Catalogo Hibrido (FTS + Vector) PRONTO. PopulateStatus: ';
SELECT FULLTEXTCATALOGPROPERTY(N'AW_HybridFtsCatalog', N'PopulateStatus') AS PopStatus,
       CASE FULLTEXTCATALOGPROPERTY(N'AW_HybridFtsCatalog', N'PopulateStatus')
           WHEN 0 THEN N'= 0 = Idle (Pronto!)' ELSE N'... Aguarde mais alguns segundos...' END AS Dsc;
GO

-- =================================================================================
-- PARTE 3/8: FULL OUTER JOIN OBRIGATORIO! Por que? TABELA
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (03) PARTE 3/8: POR QUE FULL OUTER JOIN?';
PRINT '=========================================================';
GO

SELECT
    N'INNER JOIN'                          AS Modo,
    N'Somente documentos que existem NAS DUAS listas (FTS E Vector ao mesmo tempo)' AS Resultado,
    N'Ruim! Perde 30-60% dos resultados bons!'                         AS Perda,
    N'NUNCA use para Hybrid Search. Apenas para debugging.'                   AS QuandoUsar
UNION ALL SELECT
    N'LEFT JOIN (FTS -> Vector)',
    N'Tudo do FTS. Vector NULL se nao houver match.',
    N'Perde documentos que so a busca vetorial retorna, mas FTS nao (ex: busca sem palavras parecidas).',
    N'Talvez se voce quiser priorizar 100% match palavras. Nunca padrao.'
UNION ALL SELECT
    N'FULL OUTER JOIN',
    N'Tudo de AMBAS as listas, combinando por ProductID iguais.',
    N'ZERO perda. Documento aparece em 1 fonte ou 2 fontes? RRF soma as parcelas.',
    N'RECOMENDADO SEMPRE! 100% MS Learn oficial.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> Armadilha: Documentos de apenas 1 lista recebem 1 parcela APENAS.';
PRINT N'    Documentos de AMBAS as listas recebem 2 parcelas, logo score maior.';
PRINT N'    Isso e BOM! Resultado ser top rankeado mais alto se AMBAS fontes concordam = auto-reforco mutuo.';
GO

-- =================================================================================
-- PARTE 4/8: Hybrid Search Implementacao MANUAL passo-a-passo (Query exemplo)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (03) PARTE 4/8: HYBRID IMPLEMENTADO DO 0';
PRINT '=========================================================';
GO

DECLARE
    @QueryText      NVARCHAR(500)  = N'Mountain 200 aluminum bike cheap',
    @QueryVector    VECTOR(1536)   = (SELECT TOP 1 Embedding FROM lab.HybridProductCatalog WHERE ProductName LIKE N'Mountain-200 Black, %'),
    @Rrf_k          INT           = 60,
    @CandidateCount INT           = 50,
    @TopN           INT           = 15;

PRINT N'>>> Query de teste: ' + @QueryText;
PRINT N'>>> k (RRF): ' + CAST(@Rrf_k AS VARCHAR);

WITH FTSResults AS (
    SELECT
        ft.[KEY]                                    AS ProductID,
        ft.[RANK]                                   AS FtsScore,
        ROW_NUMBER() OVER (ORDER BY ft.[RANK] DESC)   AS FtsRank
    FROM FREETEXTTABLE(
        lab.HybridProductCatalog,
        (ProductName, SearchDocument),
        @QueryText,
        LANGUAGE 1033,
        @CandidateCount
    ) ft
),
VectorResults AS (
    SELECT TOP (@CandidateCount)
        hpc.ProductID,
        VECTOR_DISTANCE(N'cosine', hpc.Embedding, @QueryVector) AS VecDistance,
        ROW_NUMBER() OVER (
            ORDER BY VECTOR_DISTANCE(N'cosine', hpc.Embedding, @QueryVector) ASC
        )                                                          AS VecRank
    FROM lab.HybridProductCatalog hpc
    WHERE hpc.Embedding IS NOT NULL
    ORDER BY VecDistance ASC
),
RRFScores AS (
    SELECT
        COALESCE(f.ProductID, v.ProductID)                    AS ProductID,
        CAST(
            ISNULL(1.0 / (@Rrf_k + f.FtsRank), 0.0)
          + ISNULL(1.0 / (@Rrf_k + v.VecRank), 0.0)
        AS DECIMAL(10,7))                                       AS RRFScore,
        f.FtsRank,
        f.FtsScore,
        v.VecRank,
        v.VecDistance
    FROM FTSResults f
    FULL OUTER JOIN VectorResults v ON v.ProductID = f.ProductID
)
SELECT TOP (@TopN)
    ROW_NUMBER() OVER (ORDER BY rrf.RRFScore DESC, hpc.ProductID) AS FinalRank,
    hpc.ProductID,
    hpc.ProductName,
    hpc.Category,
    hpc.Subcategory,
    hpc.ListPrice,
    rrf.RRFScore,
    rrf.FtsRank,
    rrf.FtsScore,
    rrf.VecRank,
    CAST(rrf.VecDistance AS DECIMAL(6,4)) AS VecDistance,
    CASE WHEN rrf.FtsRank IS NOT NULL AND rrf.VecRank IS NOT NULL THEN N'Nas 2 listas (reforco mutuo!)'
         WHEN rrf.FtsRank IS NOT NULL THEN N'Somente FTS'
         ELSE N'Somente Vetorial' END                                 AS FontesDeEvidencia
FROM RRFScores rrf
INNER JOIN lab.HybridProductCatalog hpc ON hpc.ProductID = rrf.ProductID
ORDER BY rrf.RRFScore DESC, hpc.ListPrice ASC;
GO

-- =================================================================================
-- PARTE 5/8: Procedure lab.usp_HybridProductSearch reutilizavel
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (03) PARTE 5/8: PROCEDURE REUTILIZAVEL';
PRINT '=========================================================';
GO

CREATE OR ALTER PROCEDURE lab.usp_HybridProductSearch
    @QueryText         NVARCHAR(500),
    @ReferenceProductID INT = NULL,
    @CustomQueryVec    VECTOR(1536) = NULL,
    @Rrf_k             INT   = 60,
    @CandidateCount    INT   = 50,
    @TopN              INT   = 15,
    @CategoryFilter    NVARCHAR(100) = NULL,
    @MinPrice          MONEY = NULL,
    @MaxPrice          MONEY = NULL,
    @FallbackMode      NVARCHAR(20) = N'BOTH'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @QueryVec VECTOR(1536);

    IF @ReferenceProductID IS NOT NULL
        SELECT @QueryVec = Embedding FROM lab.HybridProductCatalog WHERE ProductID = @ReferenceProductID;
    ELSE IF @CustomQueryVec IS NOT NULL
        SET @QueryVec = @CustomQueryVec;
    ELSE IF @QueryText IS NOT NULL
    BEGIN
        -- Heuristica: pega o vetor do primeiro match FTS
        SELECT TOP 1 @QueryVec = hpc.Embedding
        FROM lab.HybridProductCatalog hpc
        WHERE CONTAINS((ProductName, SearchDocument), @QueryText);
    END;

    WITH FTSResults AS (
        SELECT
            ft.[KEY]                                  AS ProductID,
            ft.[RANK]                                 AS FtsScore,
            ROW_NUMBER() OVER (ORDER BY ft.[RANK] DESC) AS FtsRank
        FROM FREETEXTTABLE(
            lab.HybridProductCatalog,
            (ProductName, SearchDocument),
            @QueryText, LANGUAGE 1033, @CandidateCount
        ) ft
        WHERE @FallbackMode IN (N'BOTH', N'FTS')
    ),
    VectorResults AS (
        SELECT TOP (@CandidateCount)
            hpc.ProductID,
            VECTOR_DISTANCE(N'cosine', hpc.Embedding, @QueryVec) AS VecDistance,
            ROW_NUMBER() OVER (ORDER BY VECTOR_DISTANCE(N'cosine', hpc.Embedding, @QueryVec) ASC) AS VecRank
        FROM lab.HybridProductCatalog hpc
        WHERE hpc.Embedding IS NOT NULL
          AND @FallbackMode IN (N'BOTH', N'VECTOR')
        ORDER BY VecDistance ASC
    ),
    RRFScores AS (
        SELECT
            COALESCE(f.ProductID, v.ProductID) AS ProductID,
            CAST(
                ISNULL(1.0 / (@Rrf_k + f.FtsRank), 0.0)
              + ISNULL(1.0 / (@Rrf_k + v.VecRank), 0.0)
            AS DECIMAL(12,9)) AS RRFScore,
            f.FtsRank, f.FtsScore,
            v.VecRank, v.VecDistance
        FROM FTSResults f
        FULL OUTER JOIN VectorResults v ON v.ProductID = f.ProductID
    )
    SELECT TOP (@TopN)
        ROW_NUMBER() OVER (ORDER BY rrf.RRFScore DESC, hpc.ListPrice ASC) AS FinalRank,
        hpc.ProductID,
        hpc.ProductName,
        hpc.Category,
        hpc.Subcategory,
        CAST(hpc.ListPrice AS VARCHAR(20)) AS ListPrice,
        CAST(rrf.RRFScore AS DECIMAL(10,7)) AS RRFScore,
        rrf.FtsRank,
        rrf.VecRank,
        CAST(rrf.VecDistance AS DECIMAL(6,4)) AS VecDistance,
        CASE WHEN rrf.FtsRank IS NOT NULL AND rrf.VecRank IS NOT NULL THEN N'[FTS + VECTOR]'
             WHEN rrf.FtsRank IS NOT NULL THEN N'[FTS only]'
             ELSE N'[VECTOR only]' END AS Fonte
    FROM RRFScores rrf
    INNER JOIN lab.HybridProductCatalog hpc ON hpc.ProductID = rrf.ProductID
    WHERE (@CategoryFilter IS NULL OR hpc.Category = @CategoryFilter)
      AND (@MinPrice       IS NULL OR hpc.ListPrice >= @MinPrice)
      AND (@MaxPrice       IS NULL OR hpc.ListPrice <= @MaxPrice)
    ORDER BY rrf.RRFScore DESC, hpc.ListPrice ASC;
END;
GO

PRINT N'--- Teste 1: Busca hibrida "Mountain 200 aluminum bike" k=60 ---';
EXEC lab.usp_HybridProductSearch
    @QueryText        = N'Mountain 200 aluminum bike cheap',
    @Rrf_k           = 60,
    @CandidateCount  = 30,
    @TopN            = 10;
GO

PRINT CHAR(13)+CHAR(10) + N'--- Teste 2: mesmo query, filtro categoria = Bikes, faixa de preco ---';
EXEC lab.usp_HybridProductSearch
    @QueryText        = N'Mountain bike entry level',
    @Rrf_k           = 60,
    @TopN            = 8,
    @CategoryFilter  = N'Bikes',
    @MinPrice        = 500,
    @MaxPrice        = 1500;
GO

-- =================================================================================
-- PARTE 6/8: Ajuste de k + Fallbacks + Metricas Avaliacao
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (03) PARTE 6/8: AJUSTE k + METRICAS';
PRINT '=========================================================';
GO

PRINT N'--- Impacto de k na mesma query (tabela comparativa) ---';
SELECT
    N'k = 1'                                         AS ValorDeK,
    N'Extremo. Rank #1 = 50% do score total.'           AS Distribuicao,
    N'Se for 1 nas 2 listas, posicao 1 absolutamente dominante.' AS Uso
UNION ALL SELECT
    N'k = 20',
    N'Top ranks pesam bastante, mas nao extremamente.',
    N'Datasets pequenos onde voce confia muito no ranking de uma das fontes.'
UNION ALL SELECT
    N'k = 60',
    N'Distribuicao justa. 2 fontes equilibradas. Topo e meio equilibrados.',
    N'>>> PADRAO MS Learn! 95% dos casos. Comece com k=60, ajuste.'
UNION ALL SELECT
    N'k = 100',
    N'Quase uniforme. "contagem de votos". Tudo importa quase igualmente.',
    N'Voce tem MUITAS fontes de busca (3+ fontes), ou quer explorar recall maximo.';
GO

-- Ground Truth AW para avaliar Precision@k / Recall@k / MRR
IF OBJECT_ID(N'lab.HybridGroundTruth', N'U') IS NOT NULL
    DROP TABLE lab.HybridGroundTruth;
GO

CREATE TABLE lab.HybridGroundTruth (
    QueryId INT NOT NULL,
    QueryText NVARCHAR(300) NOT NULL,
    RelevantProductId INT NOT NULL,
    CONSTRAINT PK_HybridGroundTruth PRIMARY KEY (QueryId, RelevantProductId)
);
GO

DECLARE @P1 INT, @P2 INT, @P3 INT, @P4 INT, @P5 INT;
SELECT TOP 1 @P1 = ProductID FROM Production.Product WHERE Name = N'Mountain-200 Black, 38';
SELECT TOP 1 @P2 = ProductID FROM Production.Product WHERE Name = N'Mountain-200 Black, 42';
SELECT TOP 1 @P3 = ProductID FROM Production.Product WHERE Name = N'Mountain-200 Silver, 38';
SELECT TOP 1 @P4 = ProductID FROM Production.Product WHERE Name LIKE N'Sport-100 Helmet%';
SELECT TOP 1 @P5 = ProductID FROM Production.Product WHERE Name LIKE N'Mini Sport Helmet%';

INSERT INTO lab.HybridGroundTruth VALUES
(1, N'Mountain 200 bike entry level', @P1),
(1, N'Mountain 200 bike entry level', @P2),
(1, N'Mountain 200 bike entry level', @P3),
(2, N'Sport helmet protection',       @P4),
(2, N'Sport helmet protection',       @P5);
GO

SELECT * FROM lab.HybridGroundTruth;
GO

PRINT CHAR(13)+CHAR(10) + N'--- Tabela formulas de avaliacao (exame!) ---';
SELECT N'Precision@K' AS Metrica,
       N'|relevantes no top-K| / K'                                  AS Formula,
       N'Mede: quantos dos primeiros K sao realmente bons.'            AS Significado
UNION ALL SELECT
       N'Recall@K',
       N'|relevantes no top-K| / |total de relevantes existentes|',
       N'Mede: quantos % de todos os itens relevantes existentes voce conseguiu recuperar.'
UNION ALL SELECT
       N'MRR (Mean Reciprocal Rank)',
       N'media( 1 / rank_do_primeiro_relevante )',
       N'Mede: quao rapido o primeiro resultado relevante aparece. 1/1 = MRR perfeito.';
GO

-- =================================================================================
-- PARTE 7/8: 5 Problemas Comuns (tabela)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (03) PARTE 7/8: PROBLEMAS COMUNS + DICAS';
PRINT '=========================================================';
GO

SELECT
    N'Hybrid Search retorna resultados bizarros no topo!' AS Erro,
    N'Copiou formula errada: 1/(k+rank) com rank 0 (zero) = 1/k (muito peso!).' AS Causa,
    N'ROW_NUMBER() gera ranks 1-based! Nunca 0. Confira ROW_NUMBER() OVER (ORDER BY ...) AS Rank.' AS Correcao
UNION ALL SELECT
    N'Hybrid sempre pior que FTS sozinho.',
    N'Vetores ruins (modelo errado, chunks ruins). 1 fonte lixo empurra resultado bom para baixo.',
    N'Valide qualidade vetorial primeiro. Nao misture modelos diferentes na mesma coluna Embedding.'
UNION ALL SELECT
    N'Produto X em #1 FTS e #100 Vector fica top 3 e X cai fora.',
    N'CandidateCount muito pequeno (5 ou menos). Uma das listas nao trouxe o X.',
    N'Aumente @CandidateCount: 30, 50 ou 100. RRF nao inventa documentos, so combina.'
UNION ALL SELECT
    N'RRFScore NULL em alguns resultados.',
    N'FULL OUTER JOIN com ISNULL/COALESCE faltando ou errado.',
    N'Sempre envolva cada parcela com ISNULL( 1.0/(k + rank), 0.0). Se FTS null, parcela = 0.'
UNION ALL SELECT
    N'Busca por "cancelar minha assinatura" nao retorna nada.',
    N'FTS sem thesaurus + vetores ruins para sinonimos. CTE FTS vazia, Vetor tambem nao encontra.',
    N'Adicione fallback: se contagem FTS+Vector < 3 -> chame apenas vetorial, ou expandir query.';
GO

-- =================================================================================
-- PARTE 8/8: Questao Estilo Exame + Checklist
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (03) PARTE 8/8: QUESTAO EXAME + CHECKLIST';
PRINT '=========================================================';
GO

PRINT CHAR(13)+CHAR(10) + N'QUESTAO DP-800 EXAME (estilo oficial):';
PRINT CHAR(13)+CHAR(10) + N'Voce esta implementando busca hibrida RRF em uma Knowledge Base de suporte tecnico.';
PRINT N'O CTE abaixo tem: CTE1 = FREETEXTTABLE(...), CTE2 = resultados de VECTOR_DISTANCE(...), Top 50 de cada.';
PRINT N'Qual tecnica de juncao voce deve usar para fundir as listas no passo RRF?';
PRINT CHAR(13)+CHAR(10) + N'  A. INNER JOIN;';
PRINT N'  B. LEFT JOIN a partir da tabela de CTE1 (FTS results);';
PRINT N'  C. FULL OUTER JOIN em ProductID entre CTE1 e CTE2, com ISNULL em cada parcela RRF;';
PRINT N'  D. UNION ALL entre CTE1 e CTE2, depois ORDER BY AVG([RANK]) * distancia;';
PRINT CHAR(13)+CHAR(10) + N'>>> GABARITO: C';
PRINT CHAR(13)+CHAR(10) + N'  A -> Errado. INNER = resultados que existem NAS DUAS listas. Perde 40-60% de recuperacao.';
PRINT N'  B -> Errado. LEFT = so prioriza CTE1. Perde resultados bons que so vetor retorna.';
PRINT N'  C -> Correto! FULL preserva ambos, COALESCE no ProductID, ISNULL em 1/(k+rank) = 0 se null.';
PRINT N'  D -> Errado. UNION ALL duplica ProductID (mesmo produto nas 2 listas).';
PRINT N'       UNION ALL ignora RRF! AVG(RANK)*distancia nao tem base em formula de fusao.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> CHECKLIST CONCLUSAO LAB 10-IS (03):';
SELECT N'[OK] Quando usar: FTS / Vector / Hybrid tabela decisao 5 cenarios.' UNION ALL
SELECT N'[OK] Formula RRF + exemplo numerico passo-a-passo tabela 4 produtos.' UNION ALL
SELECT N'[OK] Setup tabela hibrida AdventureWorks: FTS index + VECTOR(1536) same table.' UNION ALL
SELECT N'[OK] FULL OUTER JOIN OBRIGATORIO explicado tabela INNER vs LEFT vs FULL.' UNION ALL
SELECT N'[OK] Implementacao passo-a-passo: 4 passos (FTSList, VecList, RRF FULL JOIN, TOP N JOIN AW).' UNION ALL
SELECT N'[OK] Procedure lab.usp_HybridProductSearch reutilizavel + filtros categoria/preco.' UNION ALL
SELECT N'[OK] Ajuste de k: tabela k=1/20/60/100 impacto distribuicao pesos.' UNION ALL
SELECT N'[OK] Ground Truth AW com tabela formulas Precision@K / Recall@K / MRR.' UNION ALL
SELECT N'[OK] 5 Problemas comuns + correcoes tabela.' UNION ALL
SELECT N'[OK] Questao exame 4 alternativas gabarito C comentado.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> FIM MODULO 10-INTELLIGENT SEARCH (3 labs: FTS / Vector / Hybrid RRF).';
GO

-- =================================================================================================
-- PROXIMO PASSO: Revise a teoria em ../../../certification/10-intelligent-search/03-hybrid-search-rrf.md
-- =================================================================================================
