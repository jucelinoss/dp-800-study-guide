-- =================================================================================
-- DP-800 - LAB PRATICO COMPLETO: FULL-TEXT SEARCH (Busca Linguistica)
-- Banco de Dados: AdventureWorks2025 (ou LT - Light)
-- =================================================================================
-- OBJETIVOS DP-800 DOMINIO 3 Intelligent Search:
--   1. Conceitos: FTS vs LIKE / Indice invertido (tabela comparativa)
--   2. Criar FULLTEXT CATALOG + FULLTEXT INDEX em tabela materializada AdventureWorks
--   3. CHANGE_TRACKING AUTO vs MANUAL vs OFF (tabela)
--   4. STOPLIST: SYSTEM vs customizada + impacto
--   5. CONTAINS: termo, prefixo, frase, AND/OR/NOT, NEAR, FORMSOF(INFLECTIONAL/THESAURUS), ISABOUT
--   6. FREETEXT: linguagem natural, auto inflexao, OR logico
--   7. CONTAINSTABLE e FREETEXTTABLE: RANK 0-1000, TOP N
--   8. Idiomas (sys.fulltext_languages) + LCIDs
--   9. Procedure usp_FtsProductSearch reutilizavel com AdventureWorks
--  10. Tabela 6 Problemas Comuns + 4 tabelas comparativas exame
--  11. Questao estilo exame (4 alternativas + gabarito comentado)
-- =================================================================================
-- REFERENCIAS MS LEARN:
--   Full-Text Search (SQL Server):
--     https://learn.microsoft.com/en-us/sql/relational-databases/search/full-text-search
--   CONTAINS (T-SQL):
--     https://learn.microsoft.com/en-us/sql/t-sql/queries/contains-transact-sql
--   FREETEXTTABLE:
--     https://learn.microsoft.com/en-us/sql/relational-databases/system-functions/freetexttable-transact-sql
-- =================================================================================
-- REFERENCIA TEORICA: ../../../certification/10-intelligent-search/01-fulltext-search.md
--    Abra o guia teorico junto com este laboratorio para contexto conceitual.

USE AdventureWorks2025;
GO

-- =================================================================================
-- LIMPEZA PREVENTIVA (nao falha se objeto nao existir)
-- =================================================================================
IF EXISTS (SELECT * FROM sys.fulltext_indexes
           WHERE object_id = OBJECT_ID(N'lab.FtsProductDocs'))
    DROP FULLTEXT INDEX ON lab.FtsProductDocs;

IF EXISTS (SELECT * FROM sys.fulltext_catalogs WHERE name = N'AW_ProductFtsCatalog')
    DROP FULLTEXT CATALOG AW_ProductFtsCatalog;

IF EXISTS (SELECT * FROM sys.fulltext_stoplists WHERE name = N'AW_CustomStopList')
    DROP FULLTEXT STOPLIST AW_CustomStopList;

DROP PROCEDURE IF EXISTS lab.usp_FtsProductSearch;
DROP TABLE IF EXISTS lab.FtsProductDocs;
GO

CREATE SCHEMA IF NOT EXISTS lab AUTHORIZATION dbo;
GO

-- =================================================================================
-- PARTE 1/8: FTS vs LIKE — Conceitos, tabela decisao, por que FTS?
-- =================================================================================
PRINT '=========================================================';
PRINT '  LAB 10-IS (01) PARTE 1/8: FTS vs LIKE — Por que indice invertido?';
PRINT '=========================================================';
GO

SELECT
    N'LIKE ''%termo%'''                         AS Modo,
    N'Scan completo de tabela / indice (Table Scan)' AS ComoFunciona,
    N'Rapido para tabelas pequenas'               AS Vantagens,
    N'Nao entende linguagem. Nao aceita flexoes verbais.'   AS Desvantagens,
    N'SQL Server Express (padrao)'                 AS Requisito
UNION ALL SELECT
    N'Full-Text Search (FTS)',
    N'Indice invertido: palavra -> (docId, posicoes)',
    N'Entende idioma, flexoes, stopwords, proximidade. Sub-segundo em milhoes de linhas.',
    N'Requer catalogo + indice FTS separado. Setup inicial leve.',
    N'Todas as edicoes exceto LocalDB. Azure SQL DB = nativo.'
UNION ALL SELECT
    N'Semantic Search (Extensao FTS)',
    N'FTS + model estatistico (SSB: Semantic Search Database)',
    N'Extrai termos-chave, encontra documentos "semelhantes" semanticamente.',
    N'Requer Feature Pack instalado + SSB. Caiu em desuso Microsoft.';
GO

PRINT CHAR(13)+CHAR(10) + N'--- Caso de uso AdventureWorks: buscar produtos por nome + descricao ---';
PRINT N'--- LIKE = O(linhas) pois %wildcard% nao aproveita indice B-tree. ---';
PRINT N'--- FTS  = O(log N) busca no indice invertido. ---';
GO

-- Demonstracao LIKE (sem necessidade de setup, funciona em qualquer tabela)
SELECT TOP 20
    ProductID, Name, ProductNumber, ListPrice
FROM Production.Product
WHERE Name LIKE N'%Mountain%'
   OR Name LIKE N'%Bike%'
   OR Name LIKE N'%Sport%';
GO

-- =================================================================================
-- PARTE 2/8: Setup — Criar tabela AW materializada + CATALOG + FTS INDEX
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (01) PARTE 2/8: SETUP FTS EM DADOS ADVENTUREWORKS REAIS';
PRINT '=========================================================';
GO

-- Tabela materializada com NOME REAL + DESCRICAO + CATEGORIA = base da busca
SELECT
    p.ProductID,
    CAST(p.Name AS NVARCHAR(200))            AS ProductName,
    CAST(psc.Name AS NVARCHAR(100))          AS Subcategory,
    CAST(pc.Name AS NVARCHAR(100))           AS Category,
    CAST(ISNULL(pd.Description, N'') +
         N' Color: ' + ISNULL(p.Color, N'N/A') +
         N' Size: '  + ISNULL(p.Size,  N'N/A') +
         N' Weight: ' + ISNULL(CAST(p.Weight AS VARCHAR(20)), N'N/A') + 'kg.'
      AS NVARCHAR(MAX))                       AS SearchDocument,
    CAST(p.ListPrice AS MONEY)                AS ListPrice,
    CAST(N'Product: ' + p.Name + N'. Category: ' + pc.Name + N'. Subcategory: ' + psc.Name + N'. '
         + ISNULL(pd.Description, N'') AS NVARCHAR(MAX)) AS PrefixedDocument,
    CONSTRAINT PK_lab_FtsProductDocs PRIMARY KEY CLUSTERED (ProductID)
INTO lab.FtsProductDocs
FROM Production.Product p
INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
INNER JOIN Production.ProductCategory pc     ON pc.ProductCategoryID = psc.ProductCategoryID
LEFT JOIN Production.ProductModelProductDescriptionCulture pmpdc
       ON pmpdc.ProductModelID = p.ProductModelID AND pmpdc.CultureID = 'en'
LEFT JOIN Production.ProductDescription pd ON pd.ProductDescriptionID = pmpdc.ProductDescriptionID
WHERE p.ListPrice > 0;
GO

SELECT COUNT(*) AS TotalProdutosIndexados,
       MIN(ListPrice) AS PrecoMin,
       CAST(AVG(ListPrice) AS INT) AS PrecoMedio,
       MAX(ListPrice) AS PrecoMax
FROM lab.FtsProductDocs;
GO

-- --- 2.1 FULLTEXT CATALOG (container logico) ---
CREATE FULLTEXT CATALOG AW_ProductFtsCatalog
    WITH ACCENT_SENSITIVITY = ON
    AS DEFAULT;
GO

PRINT N'--- sys.fulltext_catalogs (metadados do catalogo) ---';
SELECT name, is_default, accent_sensitivity, status
FROM sys.fulltext_catalogs
WHERE name = N'AW_ProductFtsCatalog';
GO

-- --- 2.2 STOPLIST customizada ---
CREATE FULLTEXT STOPLIST AW_CustomStopList FROM SYSTEM STOPLIST;
GO
ALTER FULLTEXT STOPLIST AW_CustomStopList ADD N'product'  LANGUAGE 'English';   -- palavra muito generica
ALTER FULLTEXT STOPLIST AW_CustomStopList ADD N'item'     LANGUAGE 'English';
ALTER FULLTEXT STOPLIST AW_CustomStopList ADD N'color'    LANGUAGE 'English';
GO

PRINT N'--- Top 20 stopwords do sistema nao foram removidas, adicionamos 3 custom ---';
SELECT TOP 20 stopword, language_id
FROM sys.fulltext_stopwords
WHERE stoplist_id = FULLTEXTSTOPLISTID(N'AW_CustomStopList')
ORDER BY stopword;
GO

-- --- 2.3 CREATE FULLTEXT INDEX (requer PK unica) ---
PRINT N'>>> Ponto EXAME: Full-Text Index EXIGE indice UNICO de coluna unica nao-nulo.';
PRINT N'    Normalmente a chave primaria clusterizada. NAO pode indice composto.';
GO

CREATE FULLTEXT INDEX ON lab.FtsProductDocs (
    ProductName      LANGUAGE 'English',    -- LCID 1033
    Subcategory      LANGUAGE 'English',
    Category         LANGUAGE 'English',
    SearchDocument   LANGUAGE 'English'     -- principal
)
KEY INDEX PK_lab_FtsProductDocs
ON AW_ProductFtsCatalog
WITH (
    CHANGE_TRACKING = AUTO,   -- AUTO vs MANUAL vs OFF
    STOPLIST = AW_CustomStopList
);
GO

-- --- 2.4 CHANGE_TRACKING Comparativo (sempre cai no exame!) ---
PRINT CHAR(13)+CHAR(10) + N'--- Tabela EXAME: CHANGE_TRACKING 3 opcoes ---';
SELECT
    N'AUTO'                                         AS Modo,
    N'SQL rastreia mudancas em tempo real (assincrono leve)' AS Comportamento,
    N'Padrao recomendado. Apropiado para 99% dos casos.'    AS QuandoUsar
UNION ALL SELECT
    N'MANUAL',
    N'SQL marca mudancas, mas NAO atualiza indice. Voce chama START UPDATE POPULATION.',
    N'Altas cargas de escrita em horario de pico. Atualiza a noite via job Agent.'
UNION ALL SELECT
    N'OFF',
    N'Nenhuma mudanca rastreada. Apenas FULL POPULATION reconstroi tudo.',
    N'Tabelas estaticas, arquivos historicos imutaveis, ambientes de testes pontuais.';
GO

-- --- Aguarda population inicial (assincrona) ---
WAITFOR DELAY '00:00:03';
GO

PRINT N'--- Catalogo: PopulateStatus 0 = Idle (OK) ---';
SELECT FULLTEXTCATALOGPROPERTY(N'AW_ProductFtsCatalog', 'PopulateStatus') AS PopulateStatus,
       CASE FULLTEXTCATALOGPROPERTY(N'AW_ProductFtsCatalog', 'PopulateStatus')
           WHEN 0 THEN N'Idle (pronto para consultar!)'
           WHEN 1 THEN N'Full population em progresso...'
           WHEN 5 THEN N'Throttled (recursos compartilhados)'
           ELSE N'Ver documentacao FULLTEXTCATALOGPROPERTY'
       END AS StatusDesc;
GO

-- =================================================================================
-- PARTE 3/8: CONTAINS — Busca Precisa (7 variantes)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (01) PARTE 3/8: CONTAINS — 7 Variantes de Busca Precisa';
PRINT '=========================================================';
GO

PRINT N'--- 3.1 Termo simples ---';
SELECT TOP 15 ProductID, ProductName, Category, Subcategory, ListPrice
FROM lab.FtsProductDocs
WHERE CONTAINS(SearchDocument, N'wireless')
ORDER BY ListPrice DESC;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 3.2 Multiplas colunas com (col1, col2) ---';
SELECT TOP 15 ProductID, ProductName, Subcategory
FROM lab.FtsProductDocs
WHERE CONTAINS((ProductName, Subcategory), N'mountain')
ORDER BY ProductName;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 3.3 Todas as colunas indexadas com * ---';
SELECT TOP 10 ProductID, ProductName, Category
FROM lab.FtsProductDocs
WHERE CONTAINS(*, N'tube OR tire OR brake')
ORDER BY Category, ProductName;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 3.4 Prefixo ("comput*") + Frase exata ("sport 100s") ---';
PRINT N'>>> Ponto EXAME: Frases e prefixos EXIGEM aspas DUPLAS internas: "".';
PRINT N'    Aspas simples externas (T-SQL) + aspas duplas internas (FTS) = ""xxx""';
GO

SELECT ProductID, ProductName, Subcategory, ListPrice
FROM lab.FtsProductDocs
WHERE CONTAINS(ProductName, N'"Mountain*" OR "Road*"')
ORDER BY ProductName;
GO

-- Frase EXATA
SELECT ProductID, ProductName, LEFT(SearchDocument, 100) + N'...' AS DocPreview
FROM lab.FtsProductDocs
WHERE CONTAINS(SearchDocument, N'"designed for road"')
ORDER BY ProductName;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 3.5 Booleanos: AND, OR, AND NOT ---';
SELECT TOP 20 ProductID, ProductName, Category, ListPrice
FROM lab.FtsProductDocs
WHERE CONTAINS(SearchDocument, N'frame AND aluminum AND NOT steel')
ORDER BY ListPrice DESC;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 3.6 NEAR — Proximidade de palavras (ate N palavras de distancia) ---';
PRINT N'Sintaxe: NEAR( (termoA, termoB), max_distancia, ordem_booleana )';
GO

-- NEAR(A,B) dentro de 8 palavras, sem ordem
SELECT TOP 15 ProductID, ProductName, LEFT(SearchDocument, 80) + N'...' AS Preview
FROM lab.FtsProductDocs
WHERE CONTAINS(SearchDocument, N'NEAR((bike, performance), 8)')
ORDER BY ListPrice DESC;
GO

-- NEAR ORDENADO TRUE: primeiro "mountain" depois "frame" max 12 palavras
SELECT TOP 15 ProductID, ProductName
FROM lab.FtsProductDocs
WHERE CONTAINS(SearchDocument, N'NEAR((mountain, frame), 12, TRUE)')
ORDER BY ProductID;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 3.7 FORMSOF INFLECTIONAL + THESAURUS ---';
PRINT N'>>> INFLECTIONAL = conjuga verbos e pluraliza substantivos automaticamente.';
PRINT N'    connect -> connects, connected, connecting, connected, etc.';
GO

SELECT TOP 15 ProductID, ProductName, LEFT(SearchDocument, 80) + N'...' AS DocPreview
FROM lab.FtsProductDocs
WHERE CONTAINS(SearchDocument, N'FORMSOF(INFLECTIONAL, perform)')
ORDER BY ProductName;
GO

PRINT N'>>> FORMSOF(THESAURUS, ...) — depende de arquivo XML do idioma.';
PRINT N'    Por exemplo: "fast" -> quick, rapid, speedy. Requer XML manual.';
GO

PRINT CHAR(13)+CHAR(10) + N'--- 3.8 ISABOUT — PESO ponderado para ranking (usado com CONTAINSTABLE!) ---';
PRINT N'    Termo com WEIGHT(0.9) vale mais que termo WEIGHT(0.1).';
GO

-- =================================================================================
-- PARTE 4/8: FREETEXT — Linguagem Natural
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (01) PARTE 4/8: FREETEXT — Linguagem Natural (Recall)';
PRINT '=========================================================';
GO

PRINT N'>>> FREETEXT automaticamente: 1) Remove stopwords, 2) OR logico entre palavras,';
PRINT N'    3) Aplica flexoes, 4) Expande thesaurus se configurado.';
GO

-- Busca "como se fosse humano digitando na barra de busca"
SELECT TOP 20
    ProductID, ProductName, Category, Subcategory, ListPrice
FROM lab.FtsProductDocs
WHERE FREETEXT( (ProductName, SearchDocument), N'lightweight mountain bike for women' )
ORDER BY ListPrice;
GO

-- Outros exemplos
SELECT TOP 15 ProductID, ProductName, Subcategory, ListPrice
FROM lab.FtsProductDocs
WHERE FREETEXT(SearchDocument, N'durable crankset for competitive race')
ORDER BY ListPrice DESC;
GO

PRINT CHAR(13)+CHAR(10) + N'--- TABELA EXAME SEMPRE CAI: CONTAINS vs FREETEXT ---';
SELECT
    N'CONTAINS'                                   AS Predicado,
    N'PRECISAO / Baixo recall'                    AS Objetivo,
    N'Termo, prefixo, frase, NEAR, booleano, FORMSOF, ISABOUT' AS Suporta,
    N'UI de busca com filtros / campos de e-commerce tecnico'  AS QuandoUsar
UNION ALL SELECT
    N'FREETEXT',
    N'RECALL / Menor precisao',
    N'Apenas frase em linguagem natural. Sem prefixo, sem NEAR.',
    N'Caixa de busca global em sites, Wikipedia, CMS (Wordpress tipo).'
UNION ALL SELECT
    N'CONTAINSTABLE',
    N'=CONTAINS + retorna tabela com [KEY] e [RANK]',
    N'Tudo que CONTAINS suporta, + TOP N e JOIN com dados reais.',
    N'Sempre que voce quiser ORDENAR por relevancia (UI search bar).'
UNION ALL SELECT
    N'FREETEXTTABLE',
    N'=FREETEXT + retorna tabela com [KEY] e [RANK]',
    N'Tudo FREETEXT suporta, + LANGUAGE ID e TOP_N.',
    N'Busca unificada de conhecimento, FAQ, help desk.';
GO

-- =================================================================================
-- PARTE 5/8: CONTAINSTABLE / FREETEXTTABLE — Ranking
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (01) PARTE 5/8: TABLE Fn + RANK (0 a 1000)';
PRINT '=========================================================';
GO

PRINT N'>>> [RANK] = 0 ate 1000 (maior = mais relevante). Nao ha "nota maxima".';
PRINT N'    Rank E RELATIVO ao conjunto retornado naquela query. Nao comparavel com vetores!';
GO

-- --- FREETEXTTABLE com TOP_N (limita 50 antes do JOIN) ---
SELECT TOP 20
    ft.[RANK]          AS RelevanciaRelativa,
    p.ProductID,
    p.ProductName,
    p.Category,
    p.ListPrice
FROM FREETEXTTABLE(
    lab.FtsProductDocs,
    (ProductName, SearchDocument),
    N'carbon road bike for racing competition',
    LANGUAGE 1033,
    50
) AS ft
INNER JOIN lab.FtsProductDocs p ON p.ProductID = ft.[KEY]
WHERE ft.[RANK] > 100    -- filtro minimo de relevancia
ORDER BY ft.[RANK] DESC;
GO

PRINT CHAR(13)+CHAR(10) + N'--- CONTAINSTABLE + ISABOUT ponderado ---';
SELECT TOP 20
    ct.[RANK]      AS RankFts,
    p.ProductID,
    p.ProductName,
    p.ListPrice,
    N'ISABOUT(pedal WEIGHT(0.9), axle WEIGHT(0.5), lock WEIGHT(0.2))' AS Expressao
FROM CONTAINSTABLE(
    lab.FtsProductDocs,
    SearchDocument,
    N'ISABOUT(pedal WEIGHT(0.9), axle WEIGHT(0.5), lock WEIGHT(0.2))',
    50
) AS ct
INNER JOIN lab.FtsProductDocs p ON p.ProductID = ct.[KEY]
ORDER BY ct.[RANK] DESC, ListPrice DESC;
GO

-- =================================================================================
-- PARTE 6/8: Idiomas + Manutencao do Indice
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (01) PARTE 6/8: IDIOMAS (LCIDs) + MANUTENCAO';
PRINT '=========================================================';
GO

PRINT N'--- sys.fulltext_languages: LCIDs suportados pela instancia ---';
SELECT TOP 12 lcid, name AS Linguagem
FROM sys.fulltext_languages
WHERE name IN (N'English', N'Portuguese', N'Spanish', N'French', N'German', N'Japanese')
ORDER BY lcid;
GO

-- --- Manutencao: MANUAL -> update population -> AUTO ---
PRINT CHAR(13)+CHAR(10) + N'--- Demonstracao MANUAL UPDATE POPULATION (DP-800 teste!) ---';
ALTER FULLTEXT INDEX ON lab.FtsProductDocs SET CHANGE_TRACKING MANUAL;
GO

INSERT INTO lab.FtsProductDocs (ProductID, ProductName, Subcategory, Category, SearchDocument, PrefixedDocument, ListPrice)
VALUES (-100, N'Test Manual FTS Update', N'Test SubCat', N'Test Category',
        N'Zebra xylophone unicorn product test keywords for manual population.',
        N'Product: Test Manual FTS Update. Category: Test Category.', 123.45);
GO

ALTER FULLTEXT INDEX ON lab.FtsProductDocs START UPDATE POPULATION;
GO
WAITFOR DELAY '00:00:01';
ALTER FULLTEXT INDEX ON lab.FtsProductDocs SET CHANGE_TRACKING AUTO;
GO

SELECT COUNT(*) AS LinhasExistem FROM lab.FtsProductDocs WHERE ProductID = -100;
-- Nao consegue remover via DELETE pois e uma tabela materializada, so truncamos depois
GO

-- --- FULL POPULATION vs INCREMENTAL (tabela conceitual) ---
SELECT
    N'FULL POPULATION'                                AS Modo,
    N'Reconstrói TODO indice invertido do zero.'      AS OQueFaz,
    N'O(N*palavras). Lento em tabelas grandes.'      AS Performance,
    N'Apos criacao, corrompido, restore de backup.'   AS QuandoUsar
UNION ALL SELECT
    N'INCREMENTAL POPULATION',
    N'Pega timestamp de ultima populacao, processa so linhas novas/alteradas.',
    N'O(alteracoes). Rapido.',
    N'Tabelas com CHANGE_TRACKING MANUAL ou rastreamento por timestamp.'
UNION ALL SELECT
    N'UPDATE POPULATION',
    N'Processa fila de mudancas acumuladas do MANUAL.',
    N'Rapido, pega apenas o delta acumulado desde ultimo update.',
    N'Sempre que terminar o dia e for usar CHANGE_TRACKING MANUAL.';
GO

-- =================================================================================
-- PARTE 7/8: Procedure Reutilizavel + 6 Problemas Comuns + Dicas Exame
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (01) PARTE 7/8: PROCEDURE usp_FtsProductSearch + PROBLEMAS';
PRINT '=========================================================';
GO

CREATE OR ALTER PROCEDURE lab.usp_FtsProductSearch
    @SearchMode     NVARCHAR(20) = N'FREETEXT',   -- 'CONTAINS' | 'FREETEXT' | 'TABLE'
    @Query          NVARCHAR(1000),
    @CategoryFilter NVARCHAR(100) = NULL,
    @MinPrice       MONEY = NULL,
    @MaxPrice       MONEY = NULL,
    @TopN           INT = 20,
    @LangId         INT = 1033                   -- 1033 = English
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX) = N'';

    IF @SearchMode = N'FREETEXT'
    BEGIN
        SELECT TOP (@TopN)
            ProductID, ProductName, Category, Subcategory, ListPrice,
            LEFT(SearchDocument, 120) + N'...' AS DocPreview
        FROM lab.FtsProductDocs
        WHERE FREETEXT((ProductName, SearchDocument), @Query, LANGUAGE @LangId)
          AND (@CategoryFilter IS NULL OR Category = @CategoryFilter)
          AND (@MinPrice       IS NULL OR ListPrice >= @MinPrice)
          AND (@MaxPrice       IS NULL OR ListPrice <= @MaxPrice)
        ORDER BY ListPrice ASC;
    END
    ELSE IF @SearchMode = N'CONTAINS'
    BEGIN
        SELECT TOP (@TopN)
            ProductID, ProductName, Category, Subcategory, ListPrice,
            LEFT(SearchDocument, 120) + N'...' AS DocPreview
        FROM lab.FtsProductDocs
        WHERE CONTAINS((ProductName, SearchDocument), @Query)
          AND (@CategoryFilter IS NULL OR Category = @CategoryFilter)
          AND (@MinPrice       IS NULL OR ListPrice >= @MinPrice)
          AND (@MaxPrice       IS NULL OR ListPrice <= @MaxPrice)
        ORDER BY ListPrice ASC;
    END
    ELSE IF @SearchMode = N'TABLE'     -- RANK ordenado
    BEGIN
        SELECT TOP (@TopN)
            ft.[RANK] AS RelevanciaRelativa,
            p.ProductID, p.ProductName, p.Category, p.Subcategory, p.ListPrice
        FROM FREETEXTTABLE(lab.FtsProductDocs, (ProductName, SearchDocument), @Query, @LangId, 200) ft
        INNER JOIN lab.FtsProductDocs p ON p.ProductID = ft.[KEY]
        WHERE (@CategoryFilter IS NULL OR p.Category = @CategoryFilter)
          AND (@MinPrice       IS NULL OR p.ListPrice >= @MinPrice)
          AND (@MaxPrice       IS NULL OR p.ListPrice <= @MaxPrice)
        ORDER BY ft.[RANK] DESC;
    END
END;
GO

PRINT N'--- Teste procedure: modo TABLE (ranked), categoria Bikes ---';
EXEC lab.usp_FtsProductSearch
    @SearchMode     = N'TABLE',
    @Query          = N'aluminum mountain bike entry level',
    @CategoryFilter = N'Bikes',
    @MinPrice       = 500,
    @MaxPrice       = 1500,
    @TopN           = 10;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 6 Problemas Comuns (DP-800 cai SEMPRE tabela desta) ---';
SELECT
    N'Erro: "No full-text index installed on table..."' AS Erro,
    N'Rodou CONTAINS/FREETEXT sem ter criado CREATE FULLTEXT INDEX.' AS Causa,
    N'CREATE FULLTEXT INDEX ... KEY INDEX PK_Tabela ON CatalogoName;'   AS Correcao
UNION ALL SELECT
    N'Query retorna ZERO resultados onde devia retornar muitos.',
    N'Termo de busca e uma STOPWORD (ex: "product" removido da stoplist custom).',
    N'SELECT * FROM sys.fulltext_stopwords WHERE stopword = N''seu_termo''; remova da stoplist.'
UNION ALL SELECT
    N'Linhas recém INSERIDAS nao aparecem no resultado do FTS (1-2 minutos atraso).',
    N'CHANGE_TRACKING = MANUAL ou CHANGE_RETENTION alto; assincrono.',
    N'Troque para AUTO, ou execute ALTER FULLTEXT INDEX START UPDATE POPULATION manualmente.'
UNION ALL SELECT
    N'FORMSOF(INFLECTIONAL) nao encontra "running" quando busco "run"',
    N'Coluna FTS foi criada com LANGUAGE errado (Neutro 0 ao inves de 1033 English).',
    N'Drop e recria FULLTEXT INDEX com LANGUAGE ''English'' ou 1033.'
UNION ALL SELECT
    N'CONTAINS frase da erro de sintaxe (Msg 7630).',
    N'Esqueceu aspas DUPLAS internas: use ''"minha frase"'' nao ''minha frase''.',
    N'Frase sempre: CONTAINS(col, ''"noise cancelling"'')'
UNION ALL SELECT
    N'FREETEXTTABLE retorna RANK todos 0 (sem ranking).',
    N'Muito poucas linhas no indice (<50) ou consulta contem so stopwords.',
    N'Adicione mais dados. Teste em tabelas com >500 linhas para ranking com calibracao real.';
GO

-- =================================================================================
-- PARTE 8/8: Questao Estilo Exame + Checklist Conclusao
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 10-IS (01) PARTE 8/8: QUESTAO EXAME + CHECKLIST';
PRINT '=========================================================';
GO

PRINT CHAR(13)+CHAR(10) + N'QUESTAO DP-800 EXAME (estilo oficial):';
PRINT CHAR(13)+CHAR(10) + N'Voce e DBA AdventureWorks. A equipe de e-commerce quer implementar';
PRINT N'uma barra de busca onde usuarios digitam frases em linguagem natural,';
PRINT N'ex: "mountain bike barata". O resultado deve ser ordenado por relevancia';
PRINT N'(RANK) e deve conter join com preco e categoria. Qual abordagem CERTA?';
PRINT CHAR(13)+CHAR(10) + N'  A. SELECT * FROM Production.Product WHERE Name LIKE ''%mountain%bike%barata%'';';
PRINT N'  B. WHERE CONTAINS(ProductName, ''mountain AND bike AND barata'') + ORDER BY ListPrice;';
PRINT N'  C. JOIN FREETEXTTABLE(..., ''mountain bike barata'', 1033, 200) ft ON [KEY] = Id ORDER BY [RANK] DESC;';
PRINT N'  D. FORMSOF(THESAURUS, ''mountain'') no WHERE sem TABLE function;';
PRINT CHAR(13)+CHAR(10) + N'>>> GABARITO: C';
PRINT CHAR(13)+CHAR(10) + N'  A -> Errado. LIKE % nao aproveita indice, scan completo. Nao tem RANK.';
PRINT N'  B -> Errado. CONTAINS nao retorna RANK, so booleano. Sem ordenacao por relevancia.';
PRINT N'  C -> Correto. FREETEXTTABLE linguagem natural + retorna RANK para ORDER BY DESC + TOP N. ';
PRINT N'       Faz JOIN com dados reais para expor preco/categoria. Padrao Microsoft Learn oficial.';
PRINT N'  D -> Errado. Thesaurus depende de XML externo + ainda falta a variante TABLE para RANK.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> CHECKLIST CONCLUSAO LAB 10-IS (01):';
SELECT N'[OK] Conceitos Indice Invertido: FTS vs LIKE tabela comparativa' UNION ALL
SELECT N'[OK] Setup Completo em AW2025: CATALOG, STOPLIST custom, CHANGE_TRACKING AUTO.' UNION ALL
SELECT N'[OK] 3 modos CHANGE_TRACKING: AUTO / MANUAL / OFF tabela exame.' UNION ALL
SELECT N'[OK] 7 variantes CONTAINS: termo, prefixo, frase, booleano, NEAR, FORMSOF, ISABOUT.' UNION ALL
SELECT N'[OK] FREETEXT linguagem natural: auto stopwords, OR, inflexoes.' UNION ALL
SELECT N'[OK] FREETEXTTABLE/CONTAINSTABLE: RANK(0-1000), TOP N, JOIN com AW.' UNION ALL
SELECT N'[OK] Idiomas: sys.fulltext_languages LCIDs 1033 English, 1046 PT-BR.' UNION ALL
SELECT N'[OK] 3 Populacoes: FULL vs INCREMENTAL vs UPDATE tabela comparativa.' UNION ALL
SELECT N'[OK] Procedure reutilizavel usp_FtsProductSearch (contem/table/freetext).' UNION ALL
SELECT N'[OK] 6 Problemas Comuns tabela, Questao exame, Gabarito comentado.';
GO

-- =================================================================================
-- LIMPEZA FINAL (opcional para aluno estudar tabela)
-- =================================================================================
DELETE FROM lab.FtsProductDocs WHERE ProductID < 0;
GO

PRINT CHAR(13)+CHAR(10) + N'>>> PROXIMO: Lab 10-IS 02 - Vector Search (VECTOR_DISTANCE, ANN DiskANN).';
GO

-- =================================================================================================
-- PROXIMO PASSO: Revise a teoria em ../../../certification/10-intelligent-search/01-fulltext-search.md
-- =================================================================================================
