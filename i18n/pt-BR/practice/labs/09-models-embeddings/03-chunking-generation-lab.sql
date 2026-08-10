-- =================================================================================
-- DP-800 - LAB PRATICO COMPLETO: CHUNKING E GERACAO DE EMBEDDINGS
-- Banco de Dados: AdventureWorks2025 (ou LT - Light)
-- =================================================================================
-- SEGURANÇA: Execute somente em um banco descartável. O script cria/remove objetos
-- de lab e usa textos sintéticos. Configure um external model e uma credencial de
-- teste antes de habilitar qualquer requisição externa.
-- OBJETIVOS DP-800 DOMINIO 3:
--   1. Tabela: quais colunas embedar? (Sim / Nao / As Vezes)
--   2. Combinar multiplas colunas com PREFIXO semanticos (JOIN AdventureWorks Prod/Cat)
--   3. Chunking de TAMANHO FIXO (sem overlap) + COM OVERLAP
--   4. Chunking baseado em SENTENCAS (dbo.SplitIntoSentences function)
--      + agrupamento ~4 sentencas por chunk
--   5. Tabela DocumentChunks ESTRUTURA IDEAL (constraints, indice filtrado, colunas)
--   6. Geracao: External Model + sp_invoke_external_rest_endpoint (codigo didatico)
--   7. JSON Batching (build payload + PARSE com OPENJSON em array data[i].embedding)
--   8. Estimativa de tokens + query de segurança > 7500 / limite 8192 por entrada
--   9. Calculo de Storage por coluna VECTOR(n) em milhoes de linhas
--  10. Tabela Problemas Comuns (6) + 5 Dicas Exame
-- =================================================================================
-- REFERENCIAS MS LEARN:
--   VECTOR Data Type:
--     https://learn.microsoft.com/en-us/sql/t-sql/data-types/vector-data-type
--   PREDICT:
--     https://learn.microsoft.com/en-us/sql/t-sql/queries/predict-transact-sql
--   Azure OpenAI Embeddings:
--     https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/embeddings
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/09-models-embeddings/03-chunking-generation.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================

USE AdventureWorks2025;
GO

-- =================================================================================
-- LIMPEZA PREVENTIVA
-- =================================================================================
DROP PROCEDURE IF EXISTS lab.usp_BuildTextToEmbedFromProductId;
DROP FUNCTION  IF EXISTS lab.SplitIntoSentences;
DROP TABLE IF EXISTS lab.DocumentChunks;
DROP TABLE IF EXISTS lab.SourceDocuments;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'lab')
    EXEC(N'CREATE SCHEMA lab AUTHORIZATION dbo;');
GO

PRINT '=========================================================';
PRINT '  LAB 09-ME (03) PARTE 1/8: QUAIS COLUNAS EMBEDAR E POR QUE';
PRINT '=========================================================';
GO

-- =================================================================================
-- PARTE 1: Tabela DECISAO - O que embedar, o que ignorar
-- =================================================================================
SELECT
    N'Descricao de produto em texto livre (review em linguagem natural)' AS TipoColuna,
    N'SIM' AS Embeder,
    N'Significado semantico alto, linguagem varia muito. Busca vetorial agrega MUITO valor.' AS Razao
UNION ALL SELECT
    N'Feedback de clientes, avaliacoes, comentarios de review',
    N'SIM',
    N'Linguagem livre, busca por intencao do usuario (ex: "quais usuarios reclamaram de freio?").'
UNION ALL SELECT
    N'Nome do produto / titulo curto',
    N'AS VEZES',
    N'Curto e literal. Muitas vezes Full-Text Search resolve. Combinar com Descricao antes de embedar.'
UNION ALL SELECT
    N'Codigo de status / Flags / Enums (Ex: Status = 1=Aprovado, 2=Cancelado)',
    N'NAO',
    N'Match exato (WHERE Status = 1) tem qualidade infinita vs embedding. Nao gaste tokens aqui.'
UNION ALL SELECT
    N'Valores numericos: preco, quantidade, peso, altura',
    N'NAO',
    N'Comparacao escalar SQL e BETWEEN / agregacoes sao incomparavelmente melhores.'
UNION ALL SELECT
    N'Datas: DataCompra, DataNascimento, UpdatedAt',
    N'NAO',
    N'Queries de range / DATEADD / DATETRUNC tem performance muito melhor e 100% corretas.'
UNION ALL SELECT
    N'Payload JSON completo (ex: AddressBlock)',
    N'AS VEZES',
    N'Extraia apenas campos relevantes. Ex: so concatene Rua + Cidade e nao a coluna JSON inteira. JSON_PATH!';
GO

-- =================================================================================
-- PARTE 2: Combinar Multiplas Colunas + PREFIXO (JOIN AdventureWorks!)
-- =================================================================================
-- REGRA DE QUALIDADE MICROSOFT (documentacao Azure Search Vector):
-- PREFIXAR cada campo de texto com "NomeCampo: " melhora em ~8-15% a qualidade
-- de recuperacao vs concatenação crua. O modelo aprende semantica por papel.

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (03) PARTE 2/8: COMBINAR COLUNAS + PREFIXO';
PRINT '=========================================================';
GO

-- Procedure auxiliar para demonstrar text-to-embed com AdventureWorks Dados REAIS
CREATE OR ALTER PROCEDURE lab.usp_BuildTextToEmbedFromProductId
    @ProductID INT = NULL   -- NULL = TOP 30
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        p.ProductID,
        p.Name                      AS ProductName,
        pc.Name                     AS Category,
        psc.Name                    AS Subcategory,
        CAST(p.ListPrice AS VARCHAR(15)) AS ListPrice_BRL,
        -- TextToEmbed FINAL (prefixado, concatenado) - o que vai pro modelo!
        CONCAT(
            N'Product: ',      p.Name,                            N'. ',
            N'Category: ',     pc.Name,                           N'. ',
            N'Subcategory: ',  psc.Name,                          N'. ',
            N'ListPrice: R$ ', CAST(p.ListPrice AS VARCHAR(15)), N'. ',
            N'Color: ',        ISNULL(p.Color, N'Nao informado'), N'. ',
            N'Description: ',  ISNULL(CAST(pd.Description AS NVARCHAR(1000)), N'Sem descricao.')
        ) AS TextToEmbed
    FROM Production.Product p
    INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
    INNER JOIN Production.ProductCategory pc     ON pc.ProductCategoryID = psc.ProductCategoryID
    LEFT JOIN Production.ProductModelProductDescriptionCulture pmpdc
           ON pmpdc.ProductModelID = p.ProductModelID AND pmpdc.CultureID = 'en'
    LEFT JOIN Production.ProductDescription pd ON pd.ProductDescriptionID = pmpdc.ProductDescriptionID
    WHERE p.ListPrice > 0
      AND (@ProductID IS NULL OR p.ProductID = @ProductID)
    ORDER BY p.ProductID
    OFFSET 0 ROWS FETCH NEXT (CASE WHEN @ProductID IS NULL THEN 30 ELSE 1 END) ROWS ONLY;
END;
GO

EXEC lab.usp_BuildTextToEmbedFromProductId;
GO

PRINT CHAR(13)+CHAR(10) + N'--- Regra de prefixacao: ERRADO vs CERTO ---';
SELECT N'Sem prefixo (ERRADO - qualidade inferior)'                                                                                 AS Modo,
       CONCAT(p.Name, N' ', pc.Name, N' ', ISNULL(CAST(pd.Description AS NVARCHAR(300)), N''))                                          AS Exemplo
FROM Production.Product p
INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
INNER JOIN Production.ProductCategory pc ON pc.ProductCategoryID = psc.ProductCategoryID
LEFT JOIN Production.ProductModelProductDescriptionCulture pmpdc
       ON pmpdc.ProductModelID = p.ProductModelID AND pmpdc.CultureID = 'en'
LEFT JOIN Production.ProductDescription pd ON pd.ProductDescriptionID = pmpdc.ProductDescriptionID
WHERE p.ProductID IN (776)
UNION ALL
SELECT N'Com prefixo semanticamente (CERTO - ~12% melhor recall segundo Azure Search Docs)',
       CONCAT(N'Product: ', p.Name, N'. Category: ', pc.Name, N'. Description: ', ISNULL(CAST(pd.Description AS NVARCHAR(300)), N''))
FROM Production.Product p
INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
INNER JOIN Production.ProductCategory pc ON pc.ProductCategoryID = psc.ProductCategoryID
LEFT JOIN Production.ProductModelProductDescriptionCulture pmpdc
       ON pmpdc.ProductModelID = p.ProductModelID AND pmpdc.CultureID = 'en'
LEFT JOIN Production.ProductDescription pd ON pd.ProductDescriptionID = pmpdc.ProductDescriptionID
WHERE p.ProductID IN (776);
GO

-- =================================================================================
-- PARTE 3: Setup Tabelas + CHUNKING 1 - TAMANHO FIXO (SEM OVERLAP)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (03) PARTE 3/8: CHUNKING TAMANHO FIXO (SEM OVERLAP)';
PRINT '=========================================================';
GO

-- --- ESTRUTURA IDEAL tabela SourceDocuments + DocumentChunks ---
CREATE TABLE lab.SourceDocuments (
    DocumentId   INT            NOT NULL IDENTITY(1,1) PRIMARY KEY,
    Title        NVARCHAR(500)  NOT NULL,
    Category     NVARCHAR(100)  NOT NULL DEFAULT N'Geral',
    FullContent  NVARCHAR(MAX)  NOT NULL,
    SourceUrl    NVARCHAR(1000) NULL,
    Author       NVARCHAR(200)  NULL,
    CreatedAt    DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt    DATETIME2      NOT NULL DEFAULT GETUTCDATE()
);
GO

-- --- ESTRUTURA IDEAL tabela chunks (O que Microsoft Learn recomenda!) ---
CREATE TABLE lab.DocumentChunks (
    ChunkId            INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    DocumentId         INT           NOT NULL FOREIGN KEY REFERENCES lab.SourceDocuments(DocumentId),
    ChunkNumber        INT           NOT NULL,
    ChunkStrategy      NVARCHAR(50)  NOT NULL,   -- 'FIXED' | 'FIXED-OVERLAP' | 'SENTENCE-BASED'
    ChunkStartChar     INT           NULL,       -- posicao inicial (tamanho fixo)
    ChunkEndChar       INT           NULL,       -- posicao final
    ChunkText          NVARCHAR(MAX) NOT NULL,
    EstimatedTokens    INT           NULL,
    EmbeddingModel     SYSNAME       NULL,       -- qual modelo gerou o vetor
    Embedding          VECTOR(1536)  NULL,
    EmbeddedAt         DATETIME2     NULL,
    -- Constraints chave para NAO gerar chunks duplicados
    CONSTRAINT UQ_DocumentChunks_DocNum UNIQUE (DocumentId, ChunkNumber, ChunkStrategy)
);
GO

-- Indice FILTRADO do Lab01 teoria: para encontrar linhas PENDENTES de embedding RAPIDO
CREATE INDEX IX_DocumentChunks_NeedsEmbedding
    ON lab.DocumentChunks (DocumentId, ChunkNumber)
    WHERE Embedding IS NULL;
GO

-- Carga de documentos longos (suficientes para testar chunking)
INSERT INTO lab.SourceDocuments (Title, Category, FullContent, Author) VALUES
(N'Manual Completo de Manutencao Preventiva de Bicicletas MTB e Speed', N'Manual',
 CONCAT(
 N'A manutencao preventiva de bicicletas de montanha e de estrada e fundamental para seguranca e desempenho. ',
 N'Comece sempre verificando a calibragem dos pneus. Para pneus de MTB use pressao entre 25 e 35 PSI, dependendo do terreno. ',
 N'Para bicicletas de estrada a pressao recomendada gira em torno de 80 a 110 PSI, ajustando conforme peso do ciclista. ',
 N'A corrente deve ser limpa e lubrificada pelo menos a cada 150 km ou semanalmente para uso frequente. ',
 N'Use desengraxante especifico, escove a corrente, enxague bem e seque antes de aplicar oleo ou cera lubrificante. ',
 N'Os freios a disco hidraulicos exigem atencao: verifique nivel do oleo a cada 3 meses e purgue o ar. ',
 N'Pastilhas de freio com menos de 2 mm de espessura devem ser substituidas imediatamente para evitar danos ao rotor. ',
 N'A suspensao dianteira precisa de revisao a cada 50 horas de uso em trilhas, ou anualmente para uso moderado. ',
 N'Confira a vedacao das bengalas, funcionamento do bloqueio e configuracao de retorno (rebound). ',
 N'Aperte parafusos de selim, guidao e mesa com chave dinamometrica respeitando torque do fabricante, tipicamente 5-8 Nm. ',
 N'Nunca lubrifique a roda livre com oleo de corrente - isso danifica os rolamentos internos. ',
 N'Para lubrificar a roda livre, use lubrificante especifico de rolamentos ou WD-40 Specialist. ',
 N'Cabo e bainha de freio e cambio devem ser trocados sempre que apresentarem oxido, atrito ou retardo no retorno. ',
 N'Aplicacao de teflon liquido nas bainhas reduz significativamente o peso de acionamento dos comandos. '
 ), N'Equipe TechAdventure'),
(N'Guia Completo de Seguranca em Trilhas de Mountain Bike para Iniciantes', N'Seguranca',
 CONCAT(
 N'Antes de qualquer trilha, verifique o clima e planeje seu percurso com aplicativos como Strava ou Komoot. ',
 N'Nunca saia sozinho em trilhas desconhecidas. Informe amigos ou familiares sobre horario previsto de retorno. ',
 N'O uso do capacete e OBRIGATORIO - nao economize neste item, escolha modelo com certificado CE ou CPSC. ',
 N'Recomendamos adicionalmente joelheira, cotoveleira e oculos de protecao para trilhas de nivel intermediario ou avancado. ',
 N'Carregue sempre um kit de emergencia: espátulas, câmara reserva, bomba de mao, CO2, multiferamenta e torniquete. ',
 N'Hidratacao: 500ml por hora de atividade moderada, 1L por hora em climas quentes. ',
 N'Alimentacao: gel de carboidrato a cada 45 minutos de esforzo para evitar o temido "muro do ciclista". ',
 N'Se estiver em duvida sobre uma passagem tecnica, desca e ande a pe. Queda custa caro que caminhar. ',
 N'Use roupas de tecido tecnico (DryFit) que secam rapido. Jeans e algodao sao extremamente perigosos apos quedas ou chuva. ',
 N'Em trilhas com vegetacao fechada use protetor solar fator 50 e repelente contra carrapatos. ',
 N'Mantenha distância segura de outros ciclistas: 3 segundos de espacamento em trilhas sinuosas. '
 ), N'Rodrigo SegurancaMTB');
GO

SELECT DocumentId, Title, Category, LEN(FullContent) AS TotalCaracteres
FROM lab.SourceDocuments;
GO

-- --- CHUNKING TAMANHO FIXO (sem overlap) CTE Recursiva ---
-- Documento sera dividido em chunks de 250 chars, sem sobreposicao.
PRINT CHAR(13)+CHAR(10) + N'--- 3.1 Chunking FIXO (sem overlap, 250 chars) ---';
GO

DECLARE @ChunkSize INT = 250;

WITH FixedChunks AS (
    SELECT
        DocumentId,
        1                                            AS ChunkNumber,
        1                                            AS StartPos,
        CAST(@ChunkSize AS INT)                      AS EndPos,
        CAST(LEFT(FullContent, @ChunkSize) AS NVARCHAR(MAX)) AS ChunkText,
        LEN(FullContent)                             AS TotalLen
    FROM lab.SourceDocuments

    UNION ALL

    SELECT
        fc.DocumentId,
        fc.ChunkNumber + 1,
        fc.EndPos + 1,
        fc.EndPos + @ChunkSize,
        SUBSTRING(sd.FullContent, fc.EndPos + 1, @ChunkSize),
        fc.TotalLen
    FROM FixedChunks fc
    INNER JOIN lab.SourceDocuments sd ON sd.DocumentId = fc.DocumentId
    WHERE fc.EndPos < fc.TotalLen
)
INSERT INTO lab.DocumentChunks
    (DocumentId, ChunkNumber, ChunkStrategy, ChunkStartChar, ChunkEndChar, ChunkText, EstimatedTokens)
SELECT
    DocumentId,
    ChunkNumber,
    N'FIXED',
    StartPos,
    CASE WHEN EndPos > TotalLen THEN TotalLen ELSE EndPos END,
    ChunkText,
    LEN(ChunkText) / 4       -- regra: 4 chars ~ 1 token
FROM FixedChunks
WHERE LEN(TRIM(ChunkText)) > 10
ORDER BY DocumentId, ChunkNumber
OPTION (MAXRECURSION 200);
GO

SELECT * FROM lab.DocumentChunks WHERE ChunkStrategy = 'FIXED' ORDER BY ChunkId;
GO

-- =================================================================================
-- PARTE 4: CHUNKING 2 - FIXO COM OVERLAP (regra dourada!)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (03) PARTE 4/8: CHUNKING COM OVERLAP (RECOMENDADO!)';
PRINT '=========================================================';
GO

DECLARE
    @ChunkSizeOvr INT = 250,
    @Overlap      INT = 60,   -- ~24% de overlap: bom custo/beneficio (Microsoft Learn recomenda 15-25%)
    @Step         INT = @ChunkSizeOvr - @Overlap;

WITH OverlapPositions AS (
    SELECT
        DocumentId,
        1                              AS StartPos,
        @ChunkSizeOvr                  AS ChunkSizeActual,
        LEN(FullContent)               AS TotalLen
    FROM lab.SourceDocuments

    UNION ALL

    SELECT
        op.DocumentId,
        op.StartPos + @Step,
        @ChunkSizeOvr,
        op.TotalLen
    FROM OverlapPositions op
    WHERE op.StartPos + @Step <= op.TotalLen
),
OverlapChunks AS (
    SELECT
        op.DocumentId,
        ROW_NUMBER() OVER (PARTITION BY op.DocumentId ORDER BY op.StartPos) AS ChunkNumber,
        op.StartPos,
        CASE WHEN op.StartPos + op.ChunkSizeActual - 1 > op.TotalLen
             THEN op.TotalLen
             ELSE op.StartPos + op.ChunkSizeActual - 1 END AS EndPos,
        SUBSTRING(sd.FullContent, op.StartPos, op.ChunkSizeActual) AS ChunkText
    FROM OverlapPositions op
    INNER JOIN lab.SourceDocuments sd ON sd.DocumentId = op.DocumentId
)
INSERT INTO lab.DocumentChunks
    (DocumentId, ChunkNumber, ChunkStrategy, ChunkStartChar, ChunkEndChar, ChunkText, EstimatedTokens)
SELECT
    DocumentId,
    ChunkNumber,
    N'FIXED-OVERLAP',
    StartPos,
    EndPos,
    ChunkText,
    LEN(ChunkText) / 4
FROM OverlapChunks
WHERE LEN(TRIM(ChunkText)) > 10
ORDER BY DocumentId, ChunkNumber
OPTION (MAXRECURSION 500);
GO

SELECT
    ChunkStrategy,
    DocumentId,
    ChunkNumber,
    ChunkStartChar,
    ChunkEndChar,
    EstimatedTokens,
    LEFT(ChunkText, 80) + N'...' AS ChunkPreview
FROM lab.DocumentChunks
WHERE ChunkStrategy = 'FIXED-OVERLAP'
ORDER BY DocumentId, ChunkNumber;
GO

PRINT CHAR(13)+CHAR(10) + N'>>> POR QUE OVERLAP? (Questao recorrente no exame!)';
PRINT N'    Sem overlap: informacao em uma fronteira de chunks pode ser "partida ao meio".';
PRINT N'    Ex: Chunk 1 termina com "...calibragem recomendada de" e Chunk 2 comeca com "pneu e 25 PSI".';
PRINT N'    A pergunta "Quantos PSI?" pode NAO ser recuperada, pois nenhum chunk tem o contexto completo.';
PRINT N'    Com overlap: os ultimos 60 chars do Chunk 1 aparecem de novo no comeco do Chunk 2.';
PRINT N'    Custo: ~15-25% mais chunks (e portanto +25% storage/custo de API).';
PRINT N'    Beneficio: +15-30% de recall de recuperacao (vale muito a pena na maioria dos RAGs).';
GO

-- =================================================================================
-- PARTE 5: CHUNKING 3 - BASEADO EM SENTENCAS (com function + agrupamento 4/chunk)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (03) PARTE 5/8: CHUNKING POR SENTENCAS';
PRINT '=========================================================';
GO

-- --- 5.1 Function SplitIntoSentences (regex simples, NLP real = Azure Functions) ---
CREATE OR ALTER FUNCTION lab.SplitIntoSentences(@text NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN
(
    WITH SentenceSplit AS (
        SELECT
            LTRIM(RTRIM(REPLACE(value, CHAR(10), N' '))) AS Sentence,
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL))     AS SentenceNumber
        FROM (
            -- Substituimos terminadores conhecidos por um separador uniforme: '|'
            SELECT value = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(value, N'?', N'?|'), N'!', N'!|'), N'.', N'.|'), CHAR(13) + CHAR(10), N' '), N'  ', N' ')
            FROM STRING_SPLIT(@text, N'|')
        ) q
        WHERE LEN(LTRIM(RTRIM(value))) > 10
    )
    SELECT SentenceNumber, Sentence + CASE WHEN RIGHT(Sentence, 1) NOT IN (N'.', N'?', N'!') THEN N'.' ELSE N'' END AS Sentence
    FROM SentenceSplit
);
GO

-- Teste da function
SELECT N'Testando SplitIntoSentences no Doc 1' AS Info;
SELECT SentenceNumber, Sentence
FROM lab.SplitIntoSentences((SELECT FullContent FROM lab.SourceDocuments WHERE DocumentId = 1));
GO

-- --- 5.2 Agrupar ~4 sentencas por chunk (Chunking Semantico) ---
PRINT CHAR(13)+CHAR(10) + N'--- 5.2 Agrupamento de 4 sentencas/chunk (SENTENCE-BASED) ---';
GO

WITH AllSentencesPerDoc AS (
    SELECT
        d.DocumentId,
        s.SentenceNumber,
        s.Sentence
    FROM lab.SourceDocuments d
    CROSS APPLY lab.SplitIntoSentences(d.FullContent) s
),
SentencesWithChunkGroup AS (
    SELECT
        DocumentId,
        SentenceNumber,
        Sentence,
        -- 4 sentencas por chunk = CEILING(numero / 4.0)
        CEILING(1.0 * ROW_NUMBER() OVER (
            PARTITION BY DocumentId
            ORDER BY SentenceNumber
        ) / 4.0) AS ChunkGroup
    FROM AllSentencesPerDoc
)
INSERT INTO lab.DocumentChunks
    (DocumentId, ChunkNumber, ChunkStrategy, ChunkText, EstimatedTokens)
SELECT
    DocumentId,
    ChunkGroup                                                        AS ChunkNumber,
    N'SENTENCE-BASED'                                                 AS ChunkStrategy,
    STRING_AGG(Sentence, N' ')
        WITHIN GROUP (ORDER BY SentenceNumber)                        AS ChunkText,
    LEN(STRING_AGG(Sentence, N' ') WITHIN GROUP (ORDER BY SentenceNumber)) / 4
FROM SentencesWithChunkGroup
GROUP BY DocumentId, ChunkGroup
ORDER BY DocumentId, ChunkGroup;
GO

SELECT DocumentId, ChunkNumber, EstimatedTokens,
       LEFT(ChunkText, 120) + N'...' AS PreviewChunkText
FROM lab.DocumentChunks
WHERE ChunkStrategy = N'SENTENCE-BASED'
ORDER BY DocumentId, ChunkNumber;
GO

-- --- Comparativo final das 3 estrategias ---
PRINT CHAR(13)+CHAR(10) + N'--- Comparativo 3 estrategias (muitas questoes de exame comparam!) ---';
SELECT
    N'Fixed-size (tamanho fixo sem overlap)' AS Estrategia,
    N'Muito simples, previsivel'              AS Pros,
    N'Corta sentencas no meio, semantica quebrada.' AS Contras,
    N'Docs tecnicos altamente estruturados (JSON / XML / logs), docs pequenos.' AS MelhorPara
UNION ALL SELECT
    N'Fixed COM overlap (padrao 15-25%)',
    N'Melhora recall em fronteiras. Ainda simples e previsivel.',
    N'+15-25% de chunks = +25% storage/custo API.',
    N'>>> PADRAO RECOMENDADO para 90% dos RAGs genericos e documentos longos.'
UNION ALL SELECT
    N'Sentence / Paragraph-based',
    N'Unidades semanticamente completas. Nao corta frases no meio.',
    N'Tamanho de chunks varia muito (100-2000 tokens). Ruim para equalizar busca.',
    N'Artigos longos, base de conhecimento FAQ, Q&A, avaliacoes e reviews de clientes.'
UNION ALL SELECT
    N'Paragrafo-based (por quebra de linha / \n\n)',
    N'Quebras naturais do autor do documento.',
    N'Paragrafos muito longos = chunk gigante, paragrafo muito curto = informacao insuficiente.',
    N'Conteudo web, documentacao de API, blogs com formato markdown bem definido.';
GO

-- =================================================================================
-- PARTE 6: GERACAO DE EMBEDDINGS (External Model + REST)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (03) PARTE 6/8: GERACAO DE EMBEDDINGS';
PRINT '=========================================================';
GO

-- --- 6.1 Atualizacao via EXTERNAL MODEL (bloco didatico) ---
PRINT N'--- 6.1 Via AI_GENERATE_EMBEDDINGS (external model EMBEDDINGS) ---';
PRINT N'/*';
PRINT N'  UPDATE dc';
PRINT N'  SET';
PRINT N'      Embedding      = AI_GENERATE_EMBEDDINGS( dc.ChunkText USE MODEL [lab].[AzureOpenAI_Embedding3Small] ),';
PRINT N'      EmbeddingModel = N''text-embedding-3-small'',';
PRINT N'      EmbeddedAt     = SYSUTCDATETIME()';
PRINT N'  FROM lab.DocumentChunks dc';
PRINT N'  WHERE dc.Embedding IS NULL;       -- <- apenas pendentes (via indice filtrado!)';
PRINT N'*/';
GO

-- --- 6.2 sp_invoke_external_rest_endpoint (chamada REST inline para UM chunk) ---
PRINT CHAR(13)+CHAR(10) + N'--- 6.2 Via sp_invoke_external_rest_endpoint (chunk unico, parse JSON) ---';
PRINT N'/*';
PRINT N'  DECLARE @chunk NVARCHAR(MAX) = (SELECT TOP 1 ChunkText FROM lab.DocumentChunks WHERE Embedding IS NULL);';
PRINT N'  DECLARE @url NVARCHAR(1000) = N''https://SEURECURSO.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01'';';
PRINT N'  DECLARE @payload NVARCHAR(MAX) = (SELECT @chunk AS input FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);';
PRINT N'  DECLARE @resp NVARCHAR(MAX);';
PRINT N'';
PRINT N'  EXEC sp_invoke_external_rest_endpoint';
PRINT N'      @url=@url, @method=N''POST'', @credential=[AzureOpenAIApiCred],';
PRINT N'      @payload=N''{"input": '' + QUOTENAME(@chunk, N''"'') + N''}'', @response=@resp OUTPUT, @timeout=30, @retry_count=2;';
PRINT N'';
PRINT N'  -- extracao do vetor: data[0].embedding';
PRINT N'  DECLARE @vec NVARCHAR(MAX) = JSON_QUERY(@resp, N''$.result.data[0].embedding'');';
PRINT N'  UPDATE TOP (1) lab.DocumentChunks';
PRINT N'     SET Embedding = CAST(@vec AS VECTOR(1536)), EmbeddedAt = SYSUTCDATETIME()';
PRINT N'   WHERE Embedding IS NULL;';
PRINT N'*/';
GO

-- =================================================================================
-- PARTE 7: JSON BATCHING (multiplos chunks em 1 chamada) + OPENJSON parse
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (03) PARTE 7/8: BATCH JSON + OPENJSON PARSE DE RESPOSTA';
PRINT '=========================================================';
GO

-- --- 7.1 Montar payload batch (ate 2048 inputs por chamada!) ---
DECLARE @BatchSize INT = 4;

PRINT N'--- 7.1 Montar payload BATCH (4 chunks em 1 chamada API, reduziu round-trips!) ---';
DECLARE @InputsBatch NVARCHAR(MAX);
SELECT @InputsBatch = (
    SELECT N'input' = JSON_QUERY('["' + STRING_AGG(STRING_ESCAPE(ChunkText, 'json'), '","') + '"]')
    FROM (
        SELECT TOP (@BatchSize) ChunkId, ChunkText
        FROM lab.DocumentChunks
        WHERE Embedding IS NULL
        ORDER BY ChunkId
    ) Q
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
);
-- Forma alternativa mais direta sem sub-query aninhada:
SET @InputsBatch = NULL;
SELECT @InputsBatch = N'{"input": [' +
    STRING_AGG(N'"' + STRING_ESCAPE(ChunkText, 'json') + N'"', N',') + N']}'
FROM (SELECT TOP (@BatchSize) ChunkId, ChunkText FROM lab.DocumentChunks WHERE Embedding IS NULL ORDER BY ChunkId) q;

PRINT N'Payload Batch (truncado em 300 chars):';
PRINT LEFT(ISNULL(@InputsBatch, N'[ja geramos todos os embeddings!]'), 300);
GO

-- --- 7.2 Parsear Resposta Batch com OPENJSON (IMPORTANTE para o exame!) ---
PRINT CHAR(13)+CHAR(10) + N'--- 7.2 PARSE batch response com OPENJSON (ate 2048 embeddings de uma vez!) ---';
PRINT N'';
PRINT N'Supondo que a API do Azure OpenAI retornou isto como @batchResponse: ';

DECLARE @SimulatedBatchResponse NVARCHAR(MAX) = N'{
  "response": {"status": {"http": {"code":200,"description":"OK"}}},
  "result": {
    "object": "list",
    "model": "text-embedding-3-small",
    "data": [
      {"index":0, "object":"embedding", "embedding":[0.12,-0.03, 0.05, 0.001]},
      {"index":1, "object":"embedding", "embedding":[0.22, 0.11,-0.30, 0.09]},
      {"index":2, "object":"embedding", "embedding":[0.01,-0.02, 0.80, 0.04]},
      {"index":3, "object":"embedding", "embedding":[0.00, 0.00,-0.50, 0.99]}
    ],
    "usage": {"prompt_tokens": 891, "total_tokens": 891}
  }
}';

PRINT N'>>> Etapa 1: extrair usage com JSON_VALUE (escalares)';
SELECT
    JSON_VALUE(@SimulatedBatchResponse, N'$.response.status.http.code') AS StatusHttp,
    JSON_VALUE(@SimulatedBatchResponse, N'$.result.model')              AS ModelUsed,
    JSON_VALUE(@SimulatedBatchResponse, N'$.result.usage.prompt_tokens') AS PromptTokens,
    JSON_VALUE(@SimulatedBatchResponse, N'$.result.usage.total_tokens')  AS TotalTokens;
GO

DECLARE @SimulatedBatchResponse NVARCHAR(MAX) = N'{
  "response": {"status": {"http": {"code":200,"description":"OK"}}},
  "result": {
    "object": "list",
    "model": "text-embedding-3-small",
    "data": [
      {"index":0, "object":"embedding", "embedding":[0.12,-0.03, 0.05, 0.001]},
      {"index":1, "object":"embedding", "embedding":[0.22, 0.11,-0.30, 0.09]},
      {"index":2, "object":"embedding", "embedding":[0.01,-0.02, 0.80, 0.04]},
      {"index":3, "object":"embedding", "embedding":[0.00, 0.00,-0.50, 0.99]}
    ],
    "usage": {"prompt_tokens": 891, "total_tokens": 891}
  }
}';

PRINT CHAR(13)+CHAR(10) + N'>>> Etapa 2: OPENJSON em $.result.data[] -> expandir linhas (cada chunk!)';
PRINT N'    Em producao: Join com tabela DocumentChunks via ChunkIdRowNumber = $.index e UPDATE.';
SELECT
    idx                             AS BatchIndex,
    object_type                     AS Tipo,
    LEFT(embedding_json, 80) + N'...' AS VetorPreviewTruncado,
    N'CAST(embedding_json AS VECTOR(1536)) e UPDATE dc SET Embedding = ...' AS Acao
FROM OPENJSON(JSON_QUERY(@SimulatedBatchResponse, N'$.result.data'))
WITH (
    idx         INT           N'$.index',
    object_type NVARCHAR(50)  N'$.object',
    embedding_json NVARCHAR(MAX) N'$.embedding' AS JSON  -- AS JSON = use JSON_QUERY internamente!
) AS ParsedBatch;
GO

-- =================================================================================
-- PARTE 8: Estimativa TOKENS + Storage Calculation + Problemas Comuns + Dicas
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (03) PARTE 8/8: TOKENS, STORAGE, PROBLEMAS, DICAS EXAME';
PRINT '=========================================================';
GO

--- 8.1 Estimativa + verificacao chunk oversized (> 7500 tokens / margem segura) ---
SELECT
    ChunkStrategy,
    MIN(EstimatedTokens)             AS MinTokens,
    AVG(EstimatedTokens)             AS AvgTokens,
    MAX(EstimatedTokens)             AS MaxTokens,
    COUNT(*)                         AS TotalChunks
FROM lab.DocumentChunks
GROUP BY ChunkStrategy;
GO

PRINT CHAR(13)+CHAR(10) + N'--- 8.1 Verificacao: chunks potencialmente longos (> 7500 tokens) ---';
SELECT ChunkId, DocumentId, ChunkStrategy, EstimatedTokens, LEN(ChunkText) AS Caracteres,
       N'>>> Precisa ser re-chunkado antes de chamar a API!' AS Acao
FROM lab.DocumentChunks
WHERE EstimatedTokens > 7500;    -- Limite 8192 por entrada; mantenha margem operacional
GO

-- --- 8.2 Calculo de STORAGE: custo por milhao de linhas ---
PRINT CHAR(13)+CHAR(10) + N'--- 8.2 Calculo Storage por Modelo (muito cai no exame!) ---';
SELECT
    N'text-embedding-ada-002'            AS Modelo,
    1536                                 AS Dimensoes,
    1536 * 4                             AS BytesPorLinha_KB,
    CAST((1536*4)/1024.0 AS DECIMAL(10,3)) AS KB_PorLinha,
    CAST(1000000 * (1536*4) / 1024.0 / 1024.0 AS INT) AS MB_PorMilhaoLinhas,
    CAST(1000000 * (1536*4) / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS GB_PorMilhaoLinhas
UNION ALL SELECT
    N'text-embedding-3-small', 1536, 1536*4,
    CAST(1536*4/1024.0 AS DECIMAL(10,3)),
    CAST(1000000*(1536*4)/1024.0/1024.0 AS INT),
    CAST(1000000*(1536*4)/1024.0/1024.0/1024.0 AS DECIMAL(10,2))
UNION ALL SELECT
    N'text-embedding-3-large', 3072, 3072*4,
    CAST(3072*4/1024.0 AS DECIMAL(10,3)),
    CAST(1000000*(3072*4)/1024.0/1024.0 AS INT),
    CAST(1000000*(3072*4)/1024.0/1024.0/1024.0 AS DECIMAL(10,2));
GO

-- --- 8.3 Tabela Problemas Comuns 6 (exame sempre pede!) ---
PRINT CHAR(13)+CHAR(10) + N'--- 8.3 Problemas Comuns x Causa x Correcao (MS Learn oficial) ---';
SELECT
    N'Token limit exceeded (HTTP 400)' AS Problema,
    N'Chunk muito grande. Input > 8192 tokens por entrada.' AS Causa,
    N'Reduza chunk size, adicione validacao LEN/4 antes da chamada, verifique tamanho maximo.' AS Correcao
UNION ALL SELECT
    N'Embeddings retornam NULL apos UPDATE',
    N'Erro do PREDICT / AI_GENERATE_EMBEDDINGS foi silenciosamente suprimido no lote.',
    N'Teste 1 linha unica antes de rodar o lote. Verifique logs sys.dm_exec_* / credenciais.'
UNION ALL SELECT
    N'Baixa qualidade de recuperacao (retorna chunks irrelevantes)',
    N'Chunks muito grandes (>800 tokens) OU cortados no meio de uma ideia.',
    N'Reduza tamanho chunk e adicione overlap 15-25%. Use sentence-based.'
UNION ALL SELECT
    N'Batch muito lento (horas para milhoes de linhas)',
    N'Uma chamada API por linha (cursor!).',
    N'Use JSON batching 100-2048 inputs por chamada. UPDATE em set-based SEM CURSOR.'
UNION ALL SELECT
    N'Inchaco de storage (disco cheio do nada!)',
    N'Usa 3-large (3072) sem necessidade. Esqueceu overlap aumenta storage.',
    N'Padrao = 3-small (1536). Upgrade para 3-large so se medir recall insuficiente.'
UNION ALL SELECT
    N'Resultados de busca inconsistentes entre dias',
    N'Mistura de vetores de modelos diferentes na mesma coluna.',
    N'Nunca misture! Modelo trocou? Re-embed 100% da tabela. Tenha ModelVersionUsed na tabela.';
GO

-- --- 8.4 Dicas Finais para o Exame DP-800 ---
PRINT CHAR(13)+CHAR(10) + N'--- 5 DICAS FINAIS DP-800 (chunking e geracao!) ---';
PRINT N'';
PRINT N'  1. Limite de tokens do modelo! Embeddings = 8192 tokens por entrada. Textos grandes = CHUNKING.';
PRINT N'     Regra de bolso: 4 chars ~ 1 token.';
PRINT N'';
PRINT N'  2. Overlap 15-25% na questao = resposta mais correta. Por que? Evita perda de contexto nas';
PRINT N'     fronteiras de chunks.';
PRINT N'';
PRINT N'  3. VECTOR(1536) -> 1536 floats × 4 bytes = 6KB/linha. VECTOR(3072) = 12KB/linha.';
PRINT N'     Milhoes de linhas? Planeje storage no design! Cai no exame.';
PRINT N'';
PRINT N'  4. SEMPRE armazene o ChunkText junto ao Embedding. Um vetor sem o texto original = inutil no RAG!';
PRINT N'     (o LLM precisa do texto para elaborar a resposta, o vetor so serve para buscar).';
PRINT N'';
PRINT N'  5. AI_GENERATE_EMBEDDINGS(text USE MODEL ...) = interface correta para EXTERNAL MODEL.';
PRINT N'     Nao use PREDICT para embeddings baseados em external model hoje.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> CHECKLIST CONCLUSAO LAB 09-ME (03):';
SELECT N'[OK] Tabela de decicao de colunas a embedar (7 tipos)' UNION ALL
SELECT N'[OK] Combinar multiplas colunas AdventureWorks com PREFIXO semantico' UNION ALL
SELECT N'[OK] 3 estrategias: FIXO, FIXO-OVERLAP, SENTENCE-BASED (implementadas em SQL!)' UNION ALL
SELECT N'[OK] Estrutura DocumentChunks ideal + UNIQUE + INDICE FILTRADO WHERE Embedding IS NULL' UNION ALL
SELECT N'[OK] 2 modos geracao: AI_GENERATE_EMBEDDINGS + sp_invoke_external_rest_endpoint' UNION ALL
SELECT N'[OK] JSON Batching build payload e OPENJSON parse $.data[] com index para update' UNION ALL
SELECT N'[OK] Verificacao tokens > 7500 + calculo storage 1536 vs 3072 x milhoes linhas' UNION ALL
SELECT N'[OK] 6 problemas comuns + 5 dicas finais do exame DP-800.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> FIM DOS 3 LABS DE 09-ME (Models & Embeddings).';
PRINT N'    Proximo modulo: 10-Intelligent Search (FTS, Vector Search, Hybrid RRF).';
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/09-models-embeddings/03-chunking-generation.md
-- =================================================================================================
