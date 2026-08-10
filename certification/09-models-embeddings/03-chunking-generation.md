---
title: Chunking and Embedding Generation
type: study-material
tags:
  - dp-800
  - chunking
  - embeddings
  - vector
---

# Chunking and Embedding Generation

## Overview

Before generating embeddings, you must decide which columns to embed and how to prepare the text. For long documents, you must also chunk the text into segments that fit within the model's token limit. The **chunking strategy** significantly affects retrieval quality. After chunking, embeddings are generated via an external model call and stored in a vector column.

> [!abstract]
>
> - Covers chunking strategies for preparing documents for embedding: fixed-size, semantic, and overlap
> - Documents must be split into chunks before embedding because models have token limits
> - Key exam topics: fixed vs semantic chunking trade-offs, overlap purpose, chunk size effects on retrieval quality

> [!tip] What the Exam Tests
>
> - **Fixed-size chunking**: split every N tokens; simple and predictable; may split mid-sentence
> - **Semantic chunking**: split on sentence/paragraph boundaries; better context preservation; more complex
> - **Overlap**: include last M tokens of previous chunk in the start of next chunk — prevents losing context at boundaries

---

## Foundations: Retrieval, RAG, and Context

A semantic-search application has two phases. During **indexing**, it selects text, splits documents when needed, generates embeddings, and stores vectors with text and metadata. During **retrieval**, it generates an embedding for the question and looks for the nearest chunks. In RAG (*Retrieval-Augmented Generation*), those retrieved chunks are sent as context to a chat model that drafts the answer. The embedding model retrieves; the chat model responds.

Chunking exists because long documents can exceed a model's token limit and because retrieving a whole document often brings too many irrelevant topics. A chunk should preserve enough of an idea to answer a question while remaining specific enough for search to find the right passage. Always store `ChunkText`, the document identifier, ordering, source, model version, and filter metadata; a vector without its original text is not useful RAG context.

Evaluate a strategy with real questions: does the expected answer appear among the first results? Does the passage have enough context? Did a split cut an important idea? Before changing models, review selected text, chunk boundaries, overlap, and metadata filters — these factors often affect retrieval quality more than increasing vector dimensions.

## Identifying Which Columns to Embed

Not every column needs an embedding. Choose columns where semantic search would provide value:

| Column Type | Embed? | Reason |
| :--- | :--- | :--- |
| Free-text description | Yes | Natural language, high semantic content |
| Customer review / feedback | Yes | Varied language, intent-based search |
| Product name | Sometimes | Short; full-text may suffice |
| Status codes / enums | No | Better handled by exact match |
| Numeric values | No | Use scalar comparison |
| Dates | No | Range queries are better |
| JSON payloads | Sometimes | Extract relevant fields first |

### Combining Multiple Columns

When multiple columns contribute to the semantic meaning, concatenate them before embedding:

```sql
-- Create a text representation that combines relevant fields
SELECT
    ProductId,
    -- Combine name, category, and description into one string for embedding
    CONCAT(
        'Product: ', ProductName, '. ',
        'Category: ', CategoryName, '. ',
        'Description: ', Description
    ) AS TextToEmbed
FROM dbo.Products p
JOIN dbo.Categories c ON p.CategoryId = c.CategoryId;
```

> [!note] Quality Tip
>
> Prefixing each field with its name (e.g., `"Product: "`, `"Category: "`) helps the embedding model understand the semantics of each part. This improves retrieval quality compared to plain concatenation without prefixes.

---

## Chunking Strategies

Embedding limits are provider- and model-specific; do not assume one token limit for every embedding model. Check the deployed model's documentation and leave headroom for the request. `AI_GENERATE_CHUNKS` measures `CHUNK_SIZE` in characters, not tokens, so validate the resulting chunks against the model's token limit before generating embeddings.

`AI_GENERATE_CHUNKS` is a table-valued function available in SQL Server 2025, Azure SQL Database, Azure SQL Managed Instance with the Always-up-to-date policy, and SQL database in Microsoft Fabric. It requires database compatibility level 170 or higher. Its native `CHUNK_TYPE` currently supports `FIXED`; sentence-, paragraph-, and semantic-based strategies in this document are application/T-SQL implementations, not additional values for `CHUNK_TYPE`.

### Fixed-Size Chunking

Split text into fixed character or token counts:

```sql
-- Fixed-size chunking using a recursive CTE (every 500 characters)
WITH DocumentChunks AS (
    SELECT
        DocumentId,
        1 AS ChunkNumber,
        LEFT(Content, 500) AS ChunkText,
        LEN(Content) AS TotalLength
    FROM dbo.Documents

    UNION ALL

    SELECT
        dc.DocumentId,
        dc.ChunkNumber + 1,
        SUBSTRING(d.Content, (dc.ChunkNumber * 500) + 1, 500),
        dc.TotalLength
    FROM DocumentChunks dc
    JOIN dbo.Documents d ON d.DocumentId = dc.DocumentId
    WHERE (dc.ChunkNumber * 500) < dc.TotalLength
)
INSERT INTO dbo.DocumentChunks (DocumentId, ChunkNumber, ChunkText)
SELECT DocumentId, ChunkNumber, ChunkText
FROM DocumentChunks
WHERE ChunkText <> ''
OPTION (MAXRECURSION 1000);
```

### Overlapping Chunking

Overlapping chunks preserve context across boundaries and improve retrieval recall at the cost of more storage and API calls:

```sql
-- Overlapping chunking: 500 char chunks, 100 char overlap
-- Chunk 1: chars 1-500
-- Chunk 2: chars 401-900  (overlaps last 100 of chunk 1)
-- Chunk 3: chars 801-1300
DECLARE @ChunkSize INT = 500;
DECLARE @Overlap   INT = 100;
DECLARE @Step      INT = @ChunkSize - @Overlap;  -- = 400

WITH Positions AS (
    SELECT
        DocumentId,
        1 AS StartPos,
        LEN(Content) AS TotalLen
    FROM dbo.Documents

    UNION ALL

    SELECT
        p.DocumentId,
        p.StartPos + @Step,
        p.TotalLen
    FROM Positions p
    WHERE p.StartPos + @Step <= p.TotalLen
),
Chunks AS (
    SELECT
        p.DocumentId,
        ROW_NUMBER() OVER (PARTITION BY p.DocumentId ORDER BY p.StartPos) AS ChunkNumber,
        SUBSTRING(d.Content, p.StartPos, @ChunkSize) AS ChunkText
    FROM Positions p
    JOIN dbo.Documents d ON d.DocumentId = p.DocumentId
)
INSERT INTO dbo.DocumentChunks (DocumentId, ChunkNumber, ChunkText)
SELECT DocumentId, ChunkNumber, ChunkText
FROM Chunks
WHERE LEN(TRIM(ChunkText)) > 10
OPTION (MAXRECURSION 2000);
```

### Sentence-Based Chunking

Split on sentence boundaries to preserve semantic units:

```sql
-- Simple sentence splitting on period+space patterns
-- For production, use an Azure Function or Python for proper NLP sentence splitting
CREATE OR ALTER FUNCTION dbo.SplitIntoSentences (@text NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN (
    WITH SentenceSplit AS (
        SELECT value AS Sentence,
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS SentenceNum
        FROM STRING_SPLIT(REPLACE(REPLACE(@text, '. ', '.|'), '? ', '?|'), '|')
        WHERE LEN(TRIM(value)) > 5
    )
    SELECT Sentence, SentenceNum FROM SentenceSplit
);
```

```sql
-- Group sentences into chunks of ~3-5 sentences
-- (Production implementations typically use Python/Azure Functions for this)
WITH SentencesWithChunk AS (
    SELECT
        d.DocumentId,
        s.Sentence,
        s.SentenceNum,
        CEILING(s.SentenceNum / 4.0) AS ChunkNumber  -- ~4 sentences per chunk
    FROM dbo.Documents d
    CROSS APPLY dbo.SplitIntoSentences(d.Content) s
)
INSERT INTO dbo.DocumentChunks (DocumentId, ChunkNumber, ChunkText)
SELECT
    DocumentId,
    ChunkNumber,
    STRING_AGG(Sentence, ' ') WITHIN GROUP (ORDER BY SentenceNum) AS ChunkText
FROM SentencesWithChunk
GROUP BY DocumentId, ChunkNumber;
```

### Chunking Strategy Comparison

| Strategy | Pros | Cons | Best For |
| :--- | :--- | :--- | :--- |
| Fixed-size | Simple, predictable | May cut mid-sentence | Technical docs, long text |
| Overlapping | Better boundary recall | More chunks, higher cost | General documents |
| Sentence-based | Semantically coherent | Variable chunk size | Articles, reviews, Q&A |
| Paragraph-based | Natural breaks | Very variable size | Web content, documentation |

---

## Generating Embeddings

### Table Structure for Chunked Documents

```sql
-- Documents table
CREATE TABLE dbo.Documents (
    DocumentId   INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    Title        NVARCHAR(500) NOT NULL,
    Content      NVARCHAR(MAX) NOT NULL,
    SourceUrl    NVARCHAR(1000) NULL,
    CreatedAt    DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt    DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);

-- Document chunks with embeddings
CREATE TABLE dbo.DocumentChunks (
    ChunkId       INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    DocumentId    INT           NOT NULL REFERENCES dbo.Documents(DocumentId),
    ChunkNumber   INT           NOT NULL,
    ChunkText     NVARCHAR(MAX) NOT NULL,
    TokenCount    INT           NULL,         -- estimated token count
    Embedding     VECTOR(1536)  NULL,         -- text-embedding-3-small
    EmbeddedAt    DATETIME2     NULL,
    CONSTRAINT UQ_DocumentChunks UNIQUE (DocumentId, ChunkNumber)
);

CREATE INDEX IX_DocumentChunks_EmbeddingNull
    ON dbo.DocumentChunks (DocumentId) WHERE Embedding IS NULL;
```

### Generating Embeddings via External Model

```sql
-- Generate embeddings for all unembedded chunks
UPDATE dc
SET
    Embedding  = AI_GENERATE_EMBEDDINGS(
        dc.ChunkText USE MODEL [MyEmbeddingModel]
    ),
    EmbeddedAt = GETUTCDATE()
FROM dbo.DocumentChunks AS dc
WHERE dc.Embedding IS NULL;
```

### Generating Embeddings via sp_invoke_external_rest_endpoint

For environments without an external model definition, call a compatible embeddings endpoint directly:

```sql
-- Generate embedding for a single chunk via REST
DECLARE @chunk_text NVARCHAR(MAX) = 'Azure SQL supports vector search for semantic similarity.';
DECLARE @response   NVARCHAR(MAX);
DECLARE @embedding  NVARCHAR(MAX);

DECLARE @payload NVARCHAR(MAX) = N'{"input": ' + QUOTENAME(@chunk_text, '"') + '}';

EXEC sp_invoke_external_rest_endpoint
    @url     = 'https://myopenai.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01',
    @method  = 'POST',
    @headers = '{"Content-Type":"application/json"}',
    @payload = @payload,
    @credential = [MyAzureOpenAICredential],
    @response = @response OUTPUT;

-- Extract the embedding array from the JSON response
SET @embedding = JSON_QUERY(@response, '$.result.data[0].embedding');

-- Store as VECTOR
UPDATE dbo.DocumentChunks
SET Embedding = CAST(@embedding AS VECTOR(1536)),
    EmbeddedAt = GETUTCDATE()
WHERE ChunkId = 1;
```

### Batch Embedding with JSON Batching

For efficiency, batch multiple texts in a single API call:

```sql
-- Batch embedding: choose a batch size supported by the provider and deployment
DECLARE @batch_size INT = 100;

-- Build input array for batch
DECLARE @inputs NVARCHAR(MAX);
SELECT @inputs = '[' +
    STRING_AGG('"' + REPLACE(ChunkText, '"', '\"') + '"', ',')
    WITHIN GROUP (ORDER BY ChunkId)
    + ']'
FROM (SELECT TOP (@batch_size) ChunkId, ChunkText
      FROM dbo.DocumentChunks WHERE Embedding IS NULL) batch;

DECLARE @payload NVARCHAR(MAX) = N'{"input": ' + @inputs + '}';
DECLARE @response NVARCHAR(MAX);

EXEC sp_invoke_external_rest_endpoint
    @url     = 'https://myopenai.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01',
    @method  = 'POST',
    @headers = '{"Content-Type":"application/json"}',
    @payload = @payload,
    @credential = [MyAzureOpenAICredential],
    @response = @response OUTPUT;

-- Parse the batch response and update the table
-- Each response item has index, embedding array
-- In practice this is easier to do in a stored procedure with OPENJSON
```

### Token Estimation

Before calling the API, estimate token counts to avoid exceeding the limit documented for the selected model:

```sql
-- Rough token estimate: ~4 characters per token for English text
UPDATE dbo.DocumentChunks
SET TokenCount = LEN(ChunkText) / 4
WHERE TokenCount IS NULL;

-- Flag chunks that may be too long; 7500 is an example threshold, not a universal limit
SELECT ChunkId, DocumentId, ChunkNumber, LEN(ChunkText) AS CharCount, TokenCount
FROM dbo.DocumentChunks
WHERE TokenCount > 7500;  -- Adjust to the selected model's documented limit
```

---

## Use Cases

- **Document search**: Chunk product manuals, knowledge base articles, or support documents; embed each chunk; retrieve the most relevant chunks for a user query
- **Product catalog**: Embed concatenated product name + description for semantic product search
- **Customer reviews**: Embed each review for sentiment clustering and semantic similarity
- **Q&A pairs**: Embed both questions and answers separately for best retrieval quality

---

## Common Issues & Errors

| Issue | Cause | Fix |
| :--- | :--- | :--- |
| `Token limit exceeded` | Chunk text too long | Reduce chunk size; add token estimation check before embedding |
| Embeddings are `NULL` after update | AI_GENERATE_EMBEDDINGS error silently swallowed | Test AI_GENERATE_EMBEDDINGS on a single row first; check error logs |
| Poor retrieval quality | Chunks too large or split mid-sentence | Use smaller chunks with overlap, or sentence-based splitting |
| Very slow batch embedding | One API call per row | Use a set-based `AI_GENERATE_EMBEDDINGS` update or provider-supported batch REST calls |
| Storage bloat | 1536 floats × 4 bytes × millions of rows | Choose dimensions based on measured quality; SQL Server 2025 also supports `float16` vectors as a preview feature |

### What the `float16` preview feature means

By default, `VECTOR(n)` stores each component as a 32-bit floating-point value (`float32`), so `VECTOR(1536)` requires approximately 1536 × 4 = 6,144 bytes (about 6 KB) for the vector payload of one row. SQL Server 2025 also supports the optional half-precision base type, `VECTOR(1536, float16)`: each component uses 16 bits (2 bytes), reducing the vector payload to approximately 3 KB. Across one million rows, that is roughly 6 GB with `float32` versus 3 GB with `float16`, before row, index, and transaction-log overhead.

> [!note] Precision, quantization, and dimensions are different concepts
>
> Changing `float32` to `float16` reduces the precision and storage size of each component, but keeps the same number of dimensions. This is not the same as conventional vector quantization, such as converting values to `int8`, binary codes, or product-quantization codes. It is also not dimensionality reduction, which changes the number of components—for example, from 1,536 to 768. In short: `VECTOR(1536)` defines how many dimensions exist; `float32`/`float16` defines how each dimension is represented.

This is a preview feature, not a separate embedding model. Enable it at database scope only in an environment where you are testing it:

```sql
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

CREATE TABLE dbo.DocumentEmbeddingsFloat16
(
    DocumentId INT PRIMARY KEY,
    Embedding VECTOR(1536, float16) NULL
);
```

The trade-off is precision: `float16` represents numbers less precisely than `float32`. It can be useful for approximate semantic search when storage and memory matter, but measure recall and ranking quality with representative queries before adopting it. Keep the same base type and dimensions for the vectors used in a distance calculation; mixed `float32`/`float16` vector operations and implicit conversion between those base types are not supported in the current preview. The preview may also require changes before production use, so do not treat it as a stable production contract without validating the target SQL Server version and update level.

---

## Exam Tips

> [!tip] Exam Tips
>
> - Embedding models have a **provider-specific token limit** — chunk text before embedding and validate token counts
> - **Overlapping chunks** improve recall at chunk boundaries — use when retrieval quality matters more than cost
> - `VECTOR(1536)` stores 1536 floats × 4 bytes = 6KB per row — plan storage accordingly
> - Always store the `ChunkText` alongside the embedding — it's needed to assemble the context for the LLM
> - `AI_GENERATE_EMBEDDINGS(text USE MODEL ...)` generates a vector through an embedding external model

---

## Key Takeaways

- Choose columns to embed based on semantic search value — free text, descriptions, reviews are good candidates
- Chunk long documents before embedding — fixed-size with overlap is a safe default
- Store chunks in a separate table with `ChunkText`, `DocumentId`, `ChunkNumber`, and `Embedding` columns
- Generate embeddings with `AI_GENERATE_EMBEDDINGS` (external model) or `sp_invoke_external_rest_endpoint` (REST call)

---

## Related Topics

- [01-External Models](./01-external-models.md)
- [02-Embedding Maintenance](./02-embedding-maintenance.md)
- [02-Vector Search](../10-intelligent-search/02-vector-search.md)
- [03-Hybrid Search & RRF](../10-intelligent-search/03-hybrid-search-rrf.md)

---

## Official Documentation

- [VECTOR Data Type](https://learn.microsoft.com/en-us/sql/t-sql/data-types/vector-data-type)
- [AI_GENERATE_CHUNKS](https://learn.microsoft.com/en-us/sql/t-sql/functions/ai-generate-chunks-transact-sql)
- [AI_GENERATE_EMBEDDINGS](https://learn.microsoft.com/en-us/sql/t-sql/functions/ai-generate-embeddings-transact-sql)
- [Vector Search and Vector Indexes](https://learn.microsoft.com/en-us/sql/sql-server/ai/vectors)
- [sp_invoke_external_rest_endpoint](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-invoke-external-rest-endpoint-transact-sql)
- [Azure OpenAI Embeddings](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/embeddings)

---

**[← Previous](./02-embedding-maintenance.md) | [↑ Back to Section](./models-embeddings.md) | [Lab: Chunking and Generation](../../practice/labs/09-models-embeddings/03-chunking-generation-lab.sql)**
