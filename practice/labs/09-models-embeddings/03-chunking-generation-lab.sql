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
--   3. Sentence/paragraph chunking, token estimation, and per-chunk limits
--   4. Batch embedding generation through external models or REST
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
    EmbeddingVector VECTOR(1536) NULL,
    CONSTRAINT UQ_DocumentChunks UNIQUE (DocumentID, ChunkNumber)
);
GO

-- Insert large test document
INSERT INTO lab.SourceDocuments (Title, FullContent) VALUES 
(N'Bicycle Maintenance Manual',
 N'Preventive bicycle maintenance includes weekly tire-pressure checks, cleaning, and chain lubrication. ' +
 N'Disc brakes should be inspected to prevent premature pad wear. ' +
 N'Front suspension requires servicing after every 50 hours of intensive trail use. ' +
 N'Always keep saddle and handlebar bolts tightened to the manufacturer-recommended torque.');
GO


-- =================================================================================
-- PART 1: OVERLAPPING CHUNKING STRATEGY
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CHUNKING: Split large documents to avoid exceeding the model input limit (8191 tokens for text-embedding-3-small).
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
-- PART 2: SENTENCE CHUNKING
-- =================================================================================
-- Sentence or paragraph boundaries better preserve meaning than a fixed-size split.
-- The STRING_SPLIT ordinal is used here only for a simple demonstration; use a proper
-- language-aware parser when punctuation and abbreviations matter.

DROP TABLE IF EXISTS #SentenceChunks;

CREATE TABLE #SentenceChunks (
    DocumentID INT NOT NULL,
    ChunkNumber INT NOT NULL,
    ChunkText NVARCHAR(MAX) NOT NULL
);

INSERT INTO #SentenceChunks (DocumentID, ChunkNumber, ChunkText)
SELECT
    d.DocumentID,
    ROW_NUMBER() OVER (PARTITION BY d.DocumentID ORDER BY s.ordinal),
    TRIM(s.value) + N'.'
FROM lab.SourceDocuments AS d
CROSS APPLY STRING_SPLIT(d.FullContent, N'.', 1) AS s
WHERE LEN(TRIM(s.value)) > 10;

SELECT DocumentID, ChunkNumber, ChunkText
FROM #SentenceChunks
ORDER BY DocumentID, ChunkNumber;
GO


-- =================================================================================
-- PART 3: BATCH EMBEDDING GENERATION
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - BATCH GENERATION: Sends multiple chunks in a single HTTP JSON request to the Embeddings API.
--     Drastically reduces network overhead and processing time compared to per-row calls.

-- -- [DP-800 KEY POINT]
-- Build batch JSON payload for Azure OpenAI submission
DECLARE @BatchPayload NVARCHAR(MAX);

SELECT @BatchPayload = N'{"input": [' + 
    STRING_AGG('"' + STRING_ESCAPE(ChunkText, 'json') + '"', ',') WITHIN GROUP (ORDER BY ChunkID) +
    N']}'
FROM lab.DocumentChunks
WHERE EmbeddingVector IS NULL;

PRINT 'BATCH JSON PAYLOAD GENERATED SUCCESSFULLY:';
PRINT LEFT(@BatchPayload, 300) + '...';
GO

-- The payload above is suitable for a REST call accepting multiple inputs. STRING_ESCAPE
-- prevents invalid JSON when the text has quotes, line breaks, or special characters.

-- =================================================================================
-- PART 4: EXTERNAL MODEL AND REST GENERATION
-- =================================================================================
-- Prerequisite: create an EMBEDDINGS external model as shown in lab 01.
-- Uncomment the following examples only with a valid credential and endpoint.
/*
UPDATE dc
SET EmbeddingVector = AI_GENERATE_EMBEDDINGS(
    dc.ChunkText USE MODEL [AzureOpenAI_Embedding_Small]
)
FROM lab.DocumentChunks AS dc
WHERE dc.EmbeddingVector IS NULL;
*/
GO

-- Alternative for an embeddings REST endpoint. Convert the response JSON to VECTOR(1536)
-- before storing it in DocumentChunks.
/*
DECLARE @PayloadToSend NVARCHAR(MAX) =
(
    SELECT N'{"input": [' +
        STRING_AGG('"' + STRING_ESCAPE(ChunkText, 'json') + '"', ',')
            WITHIN GROUP (ORDER BY ChunkID) + N']}'
    FROM lab.DocumentChunks
    WHERE EmbeddingVector IS NULL
);

EXEC sp_invoke_external_rest_endpoint
    @method = N'POST',
    @url = N'https://my-openai-resource.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-10-21',
    @payload = @PayloadToSend,
    @credential = [AzureOpenAIApiKeyCred];
*/
GO

-- Verify chunks that are close to the 8191-token input limit.
SELECT ChunkID, EstimatedTokens, ChunkText
FROM lab.DocumentChunks
WHERE EstimatedTokens > 7500;
GO

-- =================================================================================
-- PART 5: PRACTICAL DESIGN SCENARIOS
-- =================================================================================

-- SCENARIO 1: Comparative Matrix of Chunking Strategies for RAG
-- Architecture decision guide for optimizing vector search.

SELECT 
    'Fixed-size chunking' AS Strategy,
    'Simple and predictable' AS Advantages,
    'Can split sentences and lose meaning' AS Disadvantages,
    'Structured documents or uniformly sized text' AS Recommendation
UNION ALL
SELECT 
    'Overlapping Chunking',
    'Preserves context across chunk boundaries',
    'Creates more chunks and increases vector storage',
    'Recommended default for most RAG applications'
UNION ALL
SELECT 
    'Sentence/Paragraph Chunking',
    'Complete semantic units',
    'Highly variable chunk sizes',
    'Articles, manuals, and Q&A knowledge bases';
GO
