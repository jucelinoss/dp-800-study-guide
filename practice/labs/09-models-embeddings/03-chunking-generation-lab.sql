-- =================================================================================
-- DP-800 - PRACTICAL LAB: TEXT CHUNKING AND EMBEDDING GENERATION
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates preparing large documents for semantic search (RAG):
--   1. Structuring the Documents Table and DocumentChunks
--   2. Fixed-Size Chunking with Overlap (Overlapping Chunking via Recursive CTE)
--   3. Token Estimation and Per-Chunk Size Limiting
--   4. Batch Embedding Generation
--   5. Practical Design Scenarios (Preparation for Vector RAG Search)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.DocumentChunks;
DROP TABLE IF EXISTS lab.SourceDocuments;
GO

-- Main Documents and Chunks table structure
CREATE TABLE lab.SourceDocuments (
    DocumentID INT IDENTITY(1,1) PRIMARY KEY,
    Title NVARCHAR(200) NOT NULL,
    FullContent NVARCHAR(MAX) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);

CREATE TABLE lab.DocumentChunks (
    ChunkID INT IDENTITY(1,1) PRIMARY KEY,
    DocumentID INT NOT NULL REFERENCES lab.SourceDocuments(DocumentID),
    ChunkNumber INT NOT NULL,
    ChunkText NVARCHAR(MAX) NOT NULL,
    EstimatedTokens INT NULL,
    EmbeddingVector NVARCHAR(MAX) NULL, -- Vector serialized as JSON
    CONSTRAINT UQ_DocumentChunks UNIQUE (DocumentID, ChunkNumber)
);
GO

-- Insert large test document
INSERT INTO lab.SourceDocuments (Title, FullContent) VALUES 
(N'Manual de Manutencao de Bicicletas', 
 N'A manutencao preventiva de bicicletas inclui a verificacao semanal da pressao dos pneus, limpeza e lubrificacao da corrente. ' +
 N'Os freios a disco devem ser inspecionados para evitar o desgaste prematuro das pastilhas. ' +
 N'A suspensao dianteira necessita de revisao a cada 50 horas de uso intenso em trilhas. ' +
 N'Mantenha sempre os parafusos do selim e do guidao apertados com o torque recomendado pelo fabricante.');
GO


-- =================================================================================
-- PART 1: OVERLAPPING CHUNKING STRATEGY
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CHUNKING: Split large documents to avoid exceeding the model's token limit (e.g., 8192 for text-embedding-3-small).
--   - OVERLAP: Keeps the last N words/characters at the start of the next chunk to preserve context.

-- -- [DP-800 KEY POINT]
DECLARE @ChunkSize INT = 150; -- Size of each chunk in characters
DECLARE @Overlap INT = 40;   -- Number of overlapping characters
DECLARE @Step INT = @ChunkSize - @Overlap; -- Step size (110)

WITH SequencePositions AS (
    SELECT 
        DocumentID,
        1 AS StartPos,
        LEN(FullContent) AS TotalLen
    FROM lab.SourceDocuments
    
    UNION ALL
    
    SELECT 
        sp.DocumentID,
        sp.StartPos + @Step,
        sp.TotalLen
    FROM SequencePositions sp
    WHERE sp.StartPos + @Step <= sp.TotalLen
),
GeneratedChunks AS (
    SELECT 
        sp.DocumentID,
        ROW_NUMBER() OVER (PARTITION BY sp.DocumentID ORDER BY sp.StartPos) AS ChunkNumber,
        SUBSTRING(d.FullContent, sp.StartPos, @ChunkSize) AS ChunkText
    FROM SequencePositions sp
    JOIN lab.SourceDocuments d ON d.DocumentID = sp.DocumentID
)
INSERT INTO lab.DocumentChunks (DocumentID, ChunkNumber, ChunkText, EstimatedTokens)
SELECT 
    DocumentID,
    ChunkNumber,
    ChunkText,
    LEN(ChunkText) / 4 -- Rough estimate: ~4 characters per token
FROM GeneratedChunks
WHERE LEN(TRIM(ChunkText)) > 10
OPTION (MAXRECURSION 500);
GO

-- Query generated overlapping chunks
SELECT ChunkID, DocumentID, ChunkNumber, EstimatedTokens, ChunkText 
FROM lab.DocumentChunks;
GO


-- =================================================================================
-- PART 2: BATCH EMBEDDING GENERATION
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - BATCH GENERATION: Sends multiple chunks in a single HTTP JSON request to the Embeddings API.
--     Drastically reduces network overhead and processing time compared to per-row calls.

-- -- [DP-800 KEY POINT]
-- Build batch JSON payload for Azure OpenAI submission
DECLARE @BatchPayload NVARCHAR(MAX);

SELECT @BatchPayload = N'{"input": [' + 
    STRING_AGG('"' + REPLACE(ChunkText, '"', '\"') + '"', ',') WITHIN GROUP (ORDER BY ChunkID) + 
    N']}'
FROM lab.DocumentChunks
WHERE EmbeddingVector IS NULL;

PRINT 'PAYLOAD JSON DE LOTE GERADO COM SUCESSO:';
PRINT LEFT(@BatchPayload, 300) + '...';
GO


-- =================================================================================
-- PART 3: PRACTICAL DESIGN SCENARIOS
-- =================================================================================

-- SCENARIO 1: Comparative Matrix of Chunking Strategies for RAG
-- Architecture decision guide for optimizing vector search.

SELECT 
    'Fixed-Size Chunking' AS Estrategia,
    'Simples e previsivel' AS Vantagens,
    'Pode cortar frases ao meio perdendo sentido' AS Desvantagens,
    'Documentos estruturados ou de tamanho homogêneo' AS Recomendacao
UNION ALL
SELECT 
    'Overlapping Chunking',
    'Preserva o contexto entre as bordas dos fragmentos',
    'Gera mais chunks aumentando o armazenamento de vetores',
    'Padrao recomendado para a maioria das aplicacoes RAG'
UNION ALL
SELECT 
    'Sentence/Paragraph Chunking',
    'Unidades semânticas perfeitas e completas',
    'Tamanho de fragmento altamente variavel',
    'Artigos, manuais e bases de conhecimento de Q&A';
GO
