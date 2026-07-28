-- =================================================================================
-- DP-800 - LAB PRATICO COMPLETO: VECTOR SEARCH (Busca Semantica / Vetorial)
-- Banco de Dados: AdventureWorks2025 (ou LT - Light)
-- =================================================================================
-- OBJETIVOS DP-800 DOMINIO 3 Intelligent Search:
--   1. Tipo VECTOR(n): dimensoes 1536 vs 3072, float32 vs float16 preview
--   2. Tabela AW materializada + vetores simulados por categoria (produtos proximos)
--   3. VECTORPROPERTY (Dimensions / BaseType) + VECTOR_NORMALIZE norm2
--   4. 3 MetricAS: cosine | euclidean | dot (tabela comparativa MS Learn)
--   5. ENN (Exact Nearest Neighbor): VECTOR_DISTANCE ORDER BY TOP N
--   6. ANN (Approximate): CREATE VECTOR INDEX DiskANN, VECTOR_SEARCH TVF, WITH APPROXIMATE
--   7. Distancia vs Similaridade: 1 - distancia cosine = similaridade (-1 a +1)
--   8. ENN vs ANN: tabela + fluxograma (quando usar cada um, fallback kNN)
--   9. Tratamento NULL + Dimension mismatch + compatibilidade METRICA indice/query
--  10. Procedure usp_VectorProductSearch com AdventureWorks JOIN reais
--  11. 6 Problemas Comuns tabela + Questao exame 4 alternativas gabarito
-- =================================================================================
-- REFERENCIAS MS LEARN:
--   VECTOR Data Type: https://learn.microsoft.com/sql/t-sql/data-types/vector-data-type
--   VECTOR_DISTANCE:  https://learn.microsoft.com/sql/t-sql/functions/vector-distance-transact-sql
--   VECTOR_SEARCH:    https://learn.microsoft.com/sql/t-sql/functions/vector-search-transact-sql
--   DiskANN Vector Index: https://learn.microsoft.com/azure/azure-sql/database/vector-index
-- =================================================================================
-- REFERENCIA TEORICA: ../../../certification/10-intelligent-search/02-vector-search.md
--    Abra o guia teorico junto com este laboratorio para contexto conceitual.

USE AdventureWorks2025;
GO

-- =================================================================================
-- LIMPEZA PREVENTIVA
-- =================================================================================
IF EXISTS (SELECT 1 FROM sys.indexes i
           JOIN sys.vector_indexes vi ON vi.object_id = i.object_id AND vi.index_id = i.index_id
           WHERE i.object_id = OBJECT_ID(N'lab.VectorProductCatalog')
             AND i.name = N'IX_VectorProductCatalog_Embedding')
    DROP INDEX IX_VectorProductCatalog_Embedding ON lab.VectorProductCatalog;

DROP PROCEDURE IF EXISTS lab.usp_VectorProductSearch;
DROP TABLE IF EXISTS lab.VectorProductCatalog;
GO

CREATE SCHEMA IF NOT EXISTS lab AUTHORIZATION dbo;
GO

-- =================================================================================
-- PARTE 1/8: Conceitos Basicos — VECTOR(n) dimensoes + storage
-- =================================================================================
PRINT '=========================================================';
PRINT '  LAB 10-IS (02) PARTE 1/8: VECTOR(n) — Dimensoes + Storage';
PRINT '=========================================================';
GO

-- TABELA PRINCIPAL: Produtos AW + Embedding simulado por CATEGORIA (produtos da
-- mesma categoria terao vetores proximos = busca semantica funciona como demo)
SELECT
    p.ProductID,
    CAST(p.Name AS NVARCHAR(250))        AS ProductName,
    CAST(pc.Name AS NVARCHAR(100))       AS Category,
    CAST(psc.Name AS NVARCHAR(100))      AS Subcategory,
    CAST(p.ListPrice AS MONEY)           AS ListPrice,
    CAST(N'Product: ' + p.Name + N'. Category: ' + pc.Name + N'. Subcategory: ' + psc.Name + N'. '
         + N'Color: ' + ISNULL(p.Color, N'N/A') + N'. '
         + ISNULL(pd.Description, N'High-quality AdventureWorks product.')
      AS NVARCHAR(MAX))                  AS TextToEmbed,
    CAST(NULL AS VECTOR(1536))           AS Embedding3Small,  -- VECTOR(n) real
    CAST(NULL AS VECTOR(3072))           AS Embedding3Large   -- apenas para mostrar coluna
INTO lab.VectorProductCatalog
FROM Production.Product p
INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
INNER JOIN Production.ProductCategory pc     ON pc.ProductCategoryID = psc.ProductCategoryID
LEFT JOIN Production.ProductModelProductDescriptionCulture pmpdc
       ON pmpdc.ProductModelID = p.ProductModelID AND pmpdc.CultureID = 'en'
LEFT JOIN Production.ProductDescription pd ON pd.ProductDescriptionID = pmpdc.ProductDescriptionID
WHERE p.ListPrice > 0;
GO

SELECT COUNT(*) AS TotalRows,
       COUNT(DISTINCT Category)    AS DistinctCategories,
       COUNT(DISTINCT Subcategory) AS DistinctSubcategories
FROM lab.VectorProductCatalog;
GO

PRINT CHAR(13)+CHAR(10) + N'--- Calculo Storage VECTOR(n) — DP-800 CAI NO EXAME ---';
SELECT
    N'text-embedding-3-small'              AS Modelo,
    1536                                    AS Dimensoes,
    N'float32 (default)'                    AS TipoBase,
    1536 * 4                                AS BytesPorLinha,
    CAST((1536*4)/1024.0 AS DECIMAL(8,3))   AS KB_PorLinha,
    CAST(1000000.0 * (1536*4) / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(6,2)) AS GB_PorMilhaoLinhas,
    1998                                    AS MaxDims_float32_Oficial_MS
UNION ALL SELECT
    N'text-embedding-3-large', 3072, N'float16 (preview)',
    3072 * 2,
    CAST((3072*2)/1024.0 AS DECIMAL(8,3)),
    CAST(1000000.0 * (3072*2) / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(6,2)),
    3996
UNION ALL SELECT
    N'text-embedding-ada-002', 1536, N'float32', 1536*4,
    CAST(1536*4/1024.0 AS DECIMAL(8,3)),
    CAST(1000000.0*(1536*4)/1024/1024/1024 AS DECIMAL(6,2)),
    1998;
GO

-- =================================================================================
-- PARTE 2/8: Gerar vetores SIMULADOS por CATEGORIA (demo sem OpenAI real)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (02) PARTE 2/8: Gerar Vetores Simulados por Categoria';
PRINT '=========================================================';
GO

/*
 * DIDATICA: Em producao voce usaria:
 *   UPDATE lab.VectorProductCatalog
 *   SET Embedding3Small = AI_GENERATE_EMBEDDINGS( TextToEmbed USE MODEL [lab].AzureOpenAI_Small ),
 *       Embedding3Large = AI_GENERATE_EMBEDDINGS( TextToEmbed USE MODEL [lab].AzureOpenAI_Large )
 *   WHERE Embedding3Small IS NULL;
 *
 * Aqui GERAMOS um vetor caracteristico por CATEGORIA usando CHECKSUM(Category)
 * como seed deterministico, assim produtos da MESMA categoria terao vetores MUITO
 * proximos entre si, e produtos de categorias DIFERENTES estarao distantes.
 * = busca semantica SIMULADA funcionando para demo sem precisar de API!
 */

-- 1 mapa categoria -> vetor base (6 primeiros floats derivados de CHECKSUM + CategoryId)
-- VECTOR(1536) exige 1536 floats. Usaremos CTE para gerar array JSON de 1536 numeros.
WITH CategoryBaseVectors AS (
    SELECT
        Category,
        -- seed = CHECKSUM da categoria
        ABS(CHECKSUM(Category))                     AS Seed1,
        ABS(CHECKSUM(REVERSE(Category))) % 9973     AS Seed2,
        DENSE_RANK() OVER (ORDER BY Category) * 0.001 AS CatOffset
    FROM (SELECT DISTINCT Category FROM lab.VectorProductCatalog) d
),
VectorJsonPerCategory AS (
    SELECT
        cbv.Category,
        N'[' + STRING_AGG(
            CAST(
                -- formula: combina seed + posicao * catOffset -> valor float entre -1 e 1
                (SIN( (cbv.Seed1 % 360) + n * (0.017 + cbv.CatOffset) ))
                + 0.2 * COS(n * 0.0031 + (cbv.Seed2 % 180) * 0.017)
            AS VARCHAR(20))
        , N',') + N']'                 AS VecJson
    FROM CategoryBaseVectors cbv
    -- Gerar 1536 numeros de posicao (tally table inline via TOP)
    CROSS APPLY (
        SELECT TOP (1536) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    ) tally
    GROUP BY cbv.Category, cbv.Seed1, cbv.Seed2, cbv.CatOffset
)
UPDATE vpc
SET vpc.Embedding3Small = CAST(vj.VecJson AS VECTOR(1536))
FROM lab.VectorProductCatalog vpc
INNER JOIN VectorJsonPerCategory vj ON vj.Category = vpc.Category;
GO

-- Verificacao: quantos embeddings gerados com sucesso?
SELECT
    COUNT(*)                                               AS TotalLinhas,
    COUNT(Embedding3Small)                                 AS ComEmbedding,
    COUNT(*) - COUNT(Embedding3Small)                      AS Nulos,
    AVG(NULLIF(CAST(VECTORPROPERTY(Embedding3Small, N'Dimensions') AS INT), 0)) AS DimMedia
FROM lab.VectorProductCatalog;
GO

-- =================================================================================
-- PARTE 3/8: VECTORPROPERTY + VECTOR_NORMALIZE (norm2)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (02) PARTE 3/8: VECTORPROPERTY + VECTOR_NORMALIZE';
PRINT '=========================================================';
GO

PRINT N'--- 3.1 VECTORPROPERTY para validar dimensoes corretas ---';
SELECT TOP 10
    ProductID,
    ProductName,
    Category,
    VECTORPROPERTY(Embedding3Small, N'Dimensions')     AS Dimensoes,    -- esperado 1536
    VECTORPROPERTY(Embedding3Small, N'BaseType')       AS TipoBase,     -- esperado float32
    -- Propriedade validada no ambiente do lab: NULL para vetores densos.
    VECTORPROPERTY(Embedding3Small, N'IsSparse')       AS IsSparse
FROM lab.VectorProductCatalog
ORDER BY Category, ProductID;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 3.2 VECTOR_NORMALIZE L2 (norm2) — OBRIGATORIO para usar DOT como cosine approx ---';
PRINT N'    VECTOR_DISTANCE(''cosine'') NAO precisa de normalizacao previa. Apenas DOT!';
GO

SELECT TOP 5
    ProductID,
    ProductName,
    VECTORPROPERTY(VECTOR_NORMALIZE(Embedding3Small, N'norm2'), N'Dimensions') AS DimAfterNorm,
    N'Magnitude = 1.0 apos normalizacao L2 (norma euclidiana unitaria)'  AS Propriedade
FROM lab.VectorProductCatalog
ORDER BY ProductID;
GO

/* -- Bloco didatico para atualizar toda tabela normalizada:
UPDATE lab.VectorProductCatalog
SET Embedding3Small = VECTOR_NORMALIZE(Embedding3Small, N'norm2')
WHERE Embedding3Small IS NOT NULL;
  -- Nao execute em um vetor que sera usado com cosine: nao necessario, nao melhora a metrica.
  -- Exclua isto se sua metrica for cosine (caso mais comum para embeddings texto).
*/

-- =================================================================================
-- PARTE 4/8: ENN (Exact) com VECTOR_DISTANCE + 3 MetricAS
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (02) PARTE 4/8: ENN — VECTOR_DISTANCE 3 Metricas';
PRINT '=========================================================';
GO

PRINT CHAR(13)+CHAR(10) + N'--- TABELA EXAME: Comparativo 3 metricas de distancia ---';
SELECT
    N'cosine'                                            AS Metrica,
    N'1 - cos(θ)'                                        AS Formula,
    N'0 (identico) a 2 (oposto)'                         AS Faixa,
    N'Padrao MICROSOFT para EMBEDDINGS DE TEXTO!'        AS QuandoUsar,
    N'Nao precisa normalizar previo!'                    AS Observacao
UNION ALL SELECT
    N'euclidean', N'SQRT(SUM((a - b)^2))', N'0 a +infinito',
    N'Dados espaciais/geometricos, vetores com magnitude significativa.',
    N'Indices DiskANN suportam. Normalizar ajuda performance.'
UNION ALL SELECT
    N'dot', N'-1 * SUM(a_i * b_i) como distancia', N'-inf a +inf',
    N'Somente se vetores JA FOREM NORMALIZADOS L2 = equivalente ao cosine.',
    N'Pior performance que cosine se esquecer de normalizar. CUIDADO!';
GO

-- --- Query de ENN real: "Encontrar produtos similares ao Mountain-100 Black, 42" ---
PRINT CHAR(13)+CHAR(10) + N'--- ENN Top 12 mais SEMANTICAMENTE proximos ao produto "Mountain-100 Black, 42" ---';
PRINT N'    (Nao precisa do nome estar escrito, a proximidade do vetor decide!)';
GO

DECLARE @QueryVec VECTOR(1536) = (
    SELECT TOP 1 Embedding3Small
    FROM lab.VectorProductCatalog
    WHERE ProductName LIKE N'Mountain-100 Black, 42'
);

SELECT TOP 12
    vpc.ProductID,
    vpc.ProductName,
    vpc.Category,
    vpc.Subcategory,
    vpc.ListPrice,
    -- Distancia = MENOR -> MELHOR (mais proximo)
    VECTOR_DISTANCE(N'cosine',    vpc.Embedding3Small, @QueryVec) AS CosineDistance,
    -- Similaridade = MAIOR -> MELHOR
    CAST(1.0 - VECTOR_DISTANCE(N'cosine', vpc.Embedding3Small, @QueryVec) AS DECIMAL(6,4)) AS CosineSimilarity,
    VECTOR_DISTANCE(N'euclidean', vpc.Embedding3Small, @QueryVec) AS EuclideanDistance,
    VECTOR_DISTANCE(N'dot',       vpc.Embedding3Small, @QueryVec) AS DotDistance
FROM lab.VectorProductCatalog vpc
WHERE vpc.Embedding3Small IS NOT NULL
ORDER BY CosineDistance ASC;    -- ASC = distancia MENOR = TOPO = MELHOR
GO

-- --- Exemplo: encontrar produtos similares a um capacete ---
PRINT CHAR(13)+CHAR(10) + N'--- ENN: Top 10 similares ao capacete Sport-100 ---';
DECLARE @HelmetVec VECTOR(1536) = (
    SELECT TOP 1 Embedding3Small
    FROM lab.VectorProductCatalog WHERE ProductName LIKE N'%Sport-100 Helmet%'
);

SELECT TOP 10
    ProductName,
    Category,
    Subcategory,
    ListPrice,
    CAST(1 - VECTOR_DISTANCE(N'cosine', Embedding3Small, @HelmetVec) AS DECIMAL(6,4)) AS SimilaridadeCos
FROM lab.VectorProductCatalog
WHERE Embedding3Small IS NOT NULL
ORDER BY SimilaridadeCos DESC;    -- DESC = maior similaridade = melhor
GO

-- =================================================================================
-- PARTE 5/8: ANN (Approximate) — DiskANN + VECTOR_SEARCH TVF
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (02) PARTE 5/8: ANN — VECTOR INDEX DiskANN + VECTOR_SEARCH';
PRINT '=========================================================';
GO

/*
  IMPORTANTE MS Learn (status 2026):
    CREATE VECTOR INDEX = preview. Requisitos para funcionar:
    1. No minimo 100 linhas com vetores NAO nulos.  (nosso catalogo ja tem!)
    2. No Azure SQL Database, Fabric SQL ou SQL Server 2025 com PREVIEW_FEATURES=ON:
         ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
    3. METRICA do indice == METRICA da query, senao FALLBACK SILENCIOSO para ENN!
*/

PRINT N'--- 5.1 Verificacao: quantas linhas temos? (>100 = minimo DiskANN) ---';
SELECT
    COUNT(*)                                                        AS TotalLinhas,
    CASE WHEN COUNT(*) >= 100 THEN N'SATISFAZ minimo 100 para DiskANN!'
         ELSE N'INSUFICIENTE: adicione linhas dummy.'
    END                                                             AS StatusMinimo
FROM lab.VectorProductCatalog;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 5.2 Bloco DIDATICO CREATE VECTOR INDEX DiskANN (preview) ---';
PRINT N'/*';
PRINT N'  -- Azure SQL / Fabric SQL: (direto)';
PRINT N'  CREATE VECTOR INDEX IX_VectorProductCatalog_Embedding';
PRINT N'      ON lab.VectorProductCatalog (Embedding3Small)';
PRINT N'      WITH ( METRIC = N''cosine'' );   -- ou euclidean, dot. APENAS 1.';
PRINT N'';
PRINT N'  -- SQL Server 2025 preview: requer PREVIEW_FEATURES = ON primeiro';
PRINT N'  ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;';
PRINT N'  CREATE VECTOR INDEX IX_VectorProductCatalog_Embedding';
PRINT N'      ON lab.VectorProductCatalog (Embedding3Small)';
PRINT N'      WITH ( METRIC = N''cosine'', TYPE = ''DiskANN'' );';
PRINT N'';
PRINT N'  -- Catalog view sys.vector_indexes';
PRINT N'  SELECT vector_index_type, distance_metric, state_desc, rebuild_count';
PRINT N'  FROM sys.vector_indexes';
PRINT N'  WHERE object_id = OBJECT_ID(N''lab.VectorProductCatalog'');';
PRINT N'*/';
GO

PRINT CHAR(13)+CHAR(10) + N'--- 5.3 Bloco DIDATICO VECTOR_SEARCH TVF + WITH APPROXIMATE ---';
PRINT N'/*';
PRINT N'  DECLARE @q VECTOR(1536) = (SELECT TOP 1 Embedding3Small FROM lab.VectorProductCatalog WHERE ProductName LIKE N''%Mountain-100 Black%'');';
PRINT N'';
PRINT N'  SELECT TOP (12) WITH APPROXIMATE   -- <- SOLICITA ANN por indice DiskANN';
PRINT N'      p.ProductID,';
PRINT N'      vs.distance AS CosineDist,';
PRINT N'      p.ProductName, p.Category, p.ListPrice';
PRINT N'  FROM VECTOR_SEARCH(';
PRINT N'      TABLE = lab.VectorProductCatalog AS p,';
PRINT N'      COLUMN = Embedding3Small,';
PRINT N'      SIMILAR_TO = @q,';
PRINT N'      METRIC = N''cosine''';
PRINT N'  ) AS vs';
PRINT N'  ORDER BY vs.distance;  -- ASC = menor distancia primeiro';
PRINT N'*/';
GO

-- ---------------------------------------------------------------------------------
-- 5.4 [OPCIONAL] rCTE gerar 100+ linhas VECTOR(4) dummy — se sua tabela do AdventureWorks for pequena
-- ---------------------------------------------------------------------------------
PRINT CHAR(13)+CHAR(10) + N'--- 5.4 [OPCIONAL / Referencia] Caso sua tabela tenha <100 linhas: rCTE VECTOR(4) ---';
PRINT N'/*';
PRINT N'  DROP TABLE IF EXISTS lab.VectorProductsMini;';
PRINT N'  CREATE TABLE lab.VectorProductsMini (';
PRINT N'      ProductID INT PRIMARY KEY,';
PRINT N'      ProductName NVARCHAR(200),';
PRINT N'      Description NVARCHAR(1000),';
PRINT N'      DescriptionVector VECTOR(4)';
PRINT N'  );';
PRINT N'';
PRINT N'  ;WITH Numeros AS (';
PRINT N'      SELECT 5 AS Numero';
PRINT N'      UNION ALL';
PRINT N'      SELECT Numero + 1 FROM Numeros WHERE Numero < 104';
PRINT N'  )';
PRINT N'  INSERT INTO lab.VectorProductsMini (ProductID, ProductName, Description, DescriptionVector)';
PRINT N'  SELECT';
PRINT N'      Numero,';
PRINT N'      CONCAT(N''Produto de teste '', Numero),';
PRINT N'      N''Vetor adicional para exercicio de indice aproximado.'',';
PRINT N'      CAST(N''[0.025, -0.038, 0.089, 0.120]'' AS VECTOR(4))';
PRINT N'  FROM Numeros';
PRINT N'  OPTION (MAXRECURSION 100);';
PRINT N'';
PRINT N'  -- Depois habilite preview e crie o indice em escala pequena (4 dims):';
PRINT N'  -- ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;';
PRINT N'  -- CREATE VECTOR INDEX IX_VPMini_DV ON lab.VectorProductsMini(DescriptionVector)';
PRINT N'  --     WITH ( METRIC = ''cosine'', TYPE = ''DiskANN'' );';
PRINT N'';
PRINT N'  DECLARE @q VECTOR(4) = CAST(N''[0.025, -0.038, 0.089, 0.120]'' AS VECTOR(4));';
PRINT N'  SELECT TOP (10) WITH APPROXIMATE';
PRINT N'      p.ProductID, p.ProductName, vs.distance AS DistanciaCosseno';
PRINT N'  FROM VECTOR_SEARCH(';
PRINT N'      TABLE = lab.VectorProductsMini AS p,';
PRINT N'      COLUMN = DescriptionVector,';
PRINT N'      SIMILAR_TO = @q,';
PRINT N'      METRIC = N''cosine''';
PRINT N'  ) AS vs';
PRINT N'  ORDER BY vs.distance;';
PRINT N'*/';
GO

-- =================================================================================
-- PARTE 6/8: ENN vs ANN — Fluxograma + tabela decisao EXAME
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (02) PARTE 6/8: ENN vs ANN — TABELA E FLUXOGRAMA';
PRINT '=========================================================';
GO

SELECT
    N'ENN (Exact Nearest Neighbor)'                                     AS Modo,
    N'SELECT TOP N ... ORDER BY VECTOR_DISTANCE(...) ASC'               AS Sintaxe,
    N'Compara TODAS as linhas, 100% exato. Top-K garantido.'           AS Precisao,
    N'O(N). Lento em tabelas grandes. 1s para 500 mil linhas.'          AS Latencia,
    N'Validacao (benchmark ground truth), tabelas pequenas (< 50 mil)'   AS QuandoUsar
UNION ALL SELECT
    N'ANN (Approximate)',
    N'TOP(N) WITH APPROXIMATE ... FROM VECTOR_SEARCH( ... METRIC=''...'')',
    N'~95-99% de recall vs ENN. Pode perder alguns vizinhos matematicamente ideais.',
    N'O(log N). Sub-segundo em MILHOES de linhas. DiskANN grafo.',
    N'PRODUCAO! > 50 mil linhas, UI de busca, RAG em escala.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> Fluxograma DECISAO (MS Learn Oficial):';
PRINT N'';
PRINT N'  Vector Query?';
PRINT N'    |';
PRINT N'    +--- Linhas < 50 mil? ----------------------------> ENN (VECTOR_DISTANCE ORDER BY)';
PRINT N'    |';
PRINT N'    +--- Linhas >= 50 mil?';
PRINT N'           |';
PRINT N'           +--- Anncio ANN com DiskANN criado + METRICA MATCH?  ---> SIM  -> ANN (rapido!)';
PRINT N'           +--- Anncio ou metrica errada? -------------------------------> Nao  -> FALLBACK SILENCIOSO p/ ENN (LENTO!)';
PRINT N'';
PRINT N'>>> Armadilha EXAME: FALLBACK SILENCIOSO! Criou indice METRIC=cosine mas query';
PRINT N'    usou ORDER BY VECTOR_DISTANCE(euclidean,...) ASC? Otimizador ignora DiskANN e';
PRINT N'    cai em ENN (scan completo). Nao avisa no plan! So mede latencia para saber.';
GO

-- =================================================================================
-- PARTE 7/8: Procedure usp_VectorProductSearch + Tratamentos
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (02) PARTE 7/8: Procedure + Tratamentos de Erro';
PRINT '=========================================================';
GO

CREATE OR ALTER PROCEDURE lab.usp_VectorProductSearch
    @ReferenceProductID INT = NULL,        -- ou passe @CustomQueryVec
    @CustomQueryVec     VECTOR(1536) = NULL,
    @Metric            NVARCHAR(20) = N'cosine',   -- cosine | euclidean | dot
    @TopN              INT = 10,
    @CategoryFilter    NVARCHAR(100) = NULL,
    @MinPrice          MONEY = NULL,
    @MaxPrice          MONEY = NULL,
    @MinSimilarity     DECIMAL(5,4) = 0.75          -- so retorna se >= 0.75
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @QueryVec VECTOR(1536);

    -- Validacao 1: precisa de ID ou vetor custom.
    IF @ReferenceProductID IS NULL AND @CustomQueryVec IS NULL
    BEGIN;
        THROW 51000, N'Deve fornecer @ReferenceProductID ou @CustomQueryVec.', 1;
        RETURN;
    END;

    -- Validacao 2: dimensao do vetor match
    IF @CustomQueryVec IS NOT NULL
       AND CAST(VECTORPROPERTY(@CustomQueryVec, N'Dimensions') AS INT) <> 1536
    BEGIN;
        THROW 51001, N'@CustomQueryVec precisa ter 1536 dimensoes (3-small). Dimension mismatch.', 1;
        RETURN;
    END;

    -- Resolver vetor alvo
    IF @CustomQueryVec IS NULL
        SELECT @QueryVec = Embedding3Small
        FROM lab.VectorProductCatalog WHERE ProductID = @ReferenceProductID;
    ELSE
        SET @QueryVec = @CustomQueryVec;

    -- Validacao 3: NULL
    IF @QueryVec IS NULL
    BEGIN;
        THROW 51002, N'Vetor alvo nulo. Verifique se @ReferenceProductID existe e tem Embedding3Small populado.', 1;
        RETURN;
    END;

    -- Query principal (ENN = portavel, sem precisar de preview ANN)
    SELECT TOP (@TopN)
        vpc.ProductID,
        vpc.ProductName,
        vpc.Category,
        vpc.Subcategory,
        vpc.ListPrice,
        CASE @Metric
            WHEN N'cosine'    THEN VECTOR_DISTANCE(N'cosine',    vpc.Embedding3Small, @QueryVec)
            WHEN N'euclidean' THEN VECTOR_DISTANCE(N'euclidean', vpc.Embedding3Small, @QueryVec)
            WHEN N'dot'       THEN VECTOR_DISTANCE(N'dot',       vpc.Embedding3Small, @QueryVec)
        END                                                             AS DistanceMetric,
        -- Similaridade so para cosine
        CASE @Metric WHEN N'cosine' THEN CAST(
            1.0 - VECTOR_DISTANCE(N'cosine', vpc.Embedding3Small, @QueryVec) AS DECIMAL(5,4))
            ELSE NULL END                                               AS CosineSimilarity,
        @ReferenceProductID                                             AS RefProductUsed
    FROM lab.VectorProductCatalog vpc
    WHERE vpc.Embedding3Small IS NOT NULL
      AND (@CategoryFilter IS NULL OR vpc.Category = @CategoryFilter)
      AND (@MinPrice       IS NULL OR vpc.ListPrice    >= @MinPrice)
      AND (@MaxPrice       IS NULL OR vpc.ListPrice    <= @MaxPrice)
      AND (@MinSimilarity  IS NULL
           OR (1.0 - VECTOR_DISTANCE(N'cosine', vpc.Embedding3Small, @QueryVec)) >= @MinSimilarity)
    ORDER BY
        CASE @Metric
            WHEN N'cosine'    THEN VECTOR_DISTANCE(N'cosine',    vpc.Embedding3Small, @QueryVec)
            WHEN N'euclidean' THEN VECTOR_DISTANCE(N'euclidean', vpc.Embedding3Small, @QueryVec)
            WHEN N'dot'       THEN VECTOR_DISTANCE(N'dot',       vpc.Embedding3Small, @QueryVec)
        END ASC;
END;
GO

PRINT N'--- Teste procedure: Top 8 similares ao produto Mountain-100 Black, 42 ---';
DECLARE @RefID INT = (SELECT TOP 1 ProductID FROM lab.VectorProductCatalog WHERE ProductName LIKE N'Mountain-100 Black, 42');
EXEC lab.usp_VectorProductSearch
    @ReferenceProductID = @RefID,
    @Metric             = N'cosine',
    @TopN               = 8,
    @MinSimilarity      = 0.70;
GO

PRINT CHAR(13)+CHAR(10) + N'--- Teste procedure com filtro Categoria = Components ---';
EXEC lab.usp_VectorProductSearch
    @ReferenceProductID = @RefID,
    @CategoryFilter     = N'Components',
    @TopN               = 6;
GO

-- =================================================================================
-- PARTE 8/8: Problemas Comuns + Questao Exame + Checklist
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (02) PARTE 8/8: PROBLEMAS + QUESTAO EXAME + CHECKLIST';
PRINT '=========================================================';
GO

PRINT N'--- 6 Problemas Comuns (MS Learn oficial) ---';
SELECT
    N'Erro: "Cannot use VECTOR_DISTANCE on NULL value"'   AS Problema,
    N'WHERE nao filtrou NULL, alguma linha tem vetor NULL.' AS Causa,
    N'WHERE ColunaVetor IS NOT NULL antes da funcao.         Sempre!'   AS Correcao
UNION ALL SELECT
    N'Erro dimension mismatch ao UPDATE vetor.',
    N'Coluna e VECTOR(1536) mas seu payload JSON tem 1535 elementos.',
    N'Garanta que modelo = 3-small → 1536. Inspecione VECTORPROPERTY(..., N''Dimensions'').'
UNION ALL SELECT
    N'ANN mais lento que ENN! (fallback silencioso)',
    N'Criou indice DiskANN METRIC=cosine, mas query usa VECTOR_DISTANCE(euclidean).',
    N'METRICA do indice deve bater COM a metrica da query. Verifique sys.vector_indexes.distance_metric.'
UNION ALL SELECT
    N'CREATE VECTOR INDEX erro: "Nao ha linhas suficientes".',
    N'Precisa no MINIMO 100 linhas com vetores NAO-NULOS.',
    N'INSERT mais linhas (dummy se necessario) antes de CREATE VECTOR INDEX.'
UNION ALL SELECT
    N'Resultados de DOT muito ruins (top 10 = aleatorios).',
    N'Usou DOT sem normalizar L2 os vetores. Produto escalar so funciona como cosine se |v|=1.',
    N'Usa metric = cosine! Ou UPDATE SET Col = VECTOR_NORMALIZE(Col, ''norm2'').'
UNION ALL SELECT
    N'Busca retorna o proprio produto query como #1 e voce quer "outros similares".',
    N'Sem filtro para excluir a referencia.',
    N'WHERE ProductID <> @ReferenceProductID ou HAVING Distance > 1E-6.';
GO

PRINT CHAR(13)+CHAR(10) + N'QUESTAO DP-800 EXAME (estilo oficial):';
PRINT CHAR(13)+CHAR(10) + N'Voce implementa busca vetorial num catalogo de 500 mil produtos no Azure SQL DB.';
PRINT N'A tabela tem coluna DescriptionVector VECTOR(1536). Voce cria:';
PRINT N'  CREATE VECTOR INDEX IX_DescVec ON dbo.Products(DescriptionVector) WITH (METRIC=''cosine'');';
PRINT N'Depois roda a query abaixo que ainda demora 2s. Qual a causa mais provavel?';
PRINT N'  SELECT TOP 20 ProductId FROM dbo.Products';
PRINT N'  ORDER BY VECTOR_DISTANCE(''euclidean'', DescriptionVector, @query) ASC;';
PRINT CHAR(13)+CHAR(10) + N'  A. Falta WITH APPROXIMATE;';
PRINT N'  B. METRICA do indice (cosine) != metrica da query (euclidean) → fallback ENN silencioso;';
PRINT N'  C. Tabela pequena, ANN nunca sera mais rapido que ENN;';
PRINT N'  D. VECTOR_DISTANCE precisa de indice full-text tambem;';
PRINT CHAR(13)+CHAR(10) + N'>>> GABARITO: B';
PRINT CHAR(13)+CHAR(10) + N'  A -> Errado. O principal aqui nao e sintaxe (ORDER BY VECTOR_DISTANCE = ENN anyway).';
PRINT N'  B -> Correto! Armadilha numero 1 do MS Learn. DiskANN = metrica fixa, so usa';
PRINT N'       ANN quando a metrica da query CASHA com a metrica do indice. Senao scan completo = ENN = lento.';
PRINT N'  C -> Errado. 500 mil linhas ANN sempre sera ordens de magnitude mais rapido que ENN.';
PRINT N'  D -> Errado. FTS e Vector Search sao independentes, nenhum requer o outro.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> CHECKLIST CONCLUSAO LAB 10-IS (02):';
SELECT N'[OK] Tabela VECTOR(n) materializada em AdventureWorks JOIN reais (297+ linhas)' UNION ALL
SELECT N'[OK] Dimensoes + tabela storage: 1536 × 4 bytes = 6KB / 3072×2 float16 preview' UNION ALL
SELECT N'[OK] Geracao vetores simulados por CATEGORIA (busca semantica demo sem API!)' UNION ALL
SELECT N'[OK] VECTORPROPERTY (Dimensions/BaseType) + VECTOR_NORMALIZE norm2' UNION ALL
SELECT N'[OK] 3 Metricas tabela: cosine (padrao texto!) / euclidean / dot' UNION ALL
SELECT N'[OK] ENN real com VECTOR_DISTANCE + Top-N por similaridade Mountain/Capacete' UNION ALL
SELECT N'[OK] ANN bloco didatico: CREATE VECTOR INDEX DiskANN preview + VECTOR_SEARCH TVF' UNION ALL
SELECT N'[OK] ENN vs ANN tabela comparativa + Fluxograma decisao com FALLBACK armadilha' UNION ALL
SELECT N'[OK] Procedure usp_VectorProductSearch (THROW em dim mismatch / NULL / minSim)' UNION ALL
SELECT N'[OK] 6 Problemas tabela + Questao exame Gabarito B.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> PROXIMO: Lab 10-IS 03 - Hybrid Search RRF (FTS + Vector + RRF).';
GO

-- =================================================================================================
-- PROXIMO PASSO: Revise a teoria em ../../../certification/10-intelligent-search/02-vector-search.md
-- =================================================================================================
