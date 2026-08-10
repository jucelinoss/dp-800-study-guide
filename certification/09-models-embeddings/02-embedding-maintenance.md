---
title: Embedding Maintenance
type: study-material
tags:
  - dp-800
  - embeddings
  - change-tracking
  - embedding-maintenance
---

# Embedding Maintenance

## Overview

**Embeddings** stored in a vector column go stale when the source text changes. Maintaining embeddings means detecting when source data changes, re-generating embeddings for affected rows, and updating the vector column. Several approaches exist — each with different tradeoffs in complexity, latency, cost, and infrastructure requirements.

> [!abstract]
>
> - Covers when and how to regenerate embeddings: model changes, schema changes, data updates, and dirty tracking
> - Embeddings are point-in-time snapshots of text meaning — they go stale when the underlying text or model changes
> - Key exam topics: model version incompatibility, dirty tracking with a flag column, batch vs incremental refresh

> [!tip] What the Exam Tests
>
> - Changing embedding models requires **regenerating ALL embeddings** — vectors from different models are in different dimensional spaces and cannot be mixed
> - Dirty tracking: add an `EmbeddingDirty BIT DEFAULT 1` column; set to 0 after embedding; UPDATE sets back to 1 via trigger or app logic
> - Batch refresh = regenerate all at once (simple, offline); incremental = process only dirty rows (complex, online)

---

## Foundation: Embeddings Are Derived Data

An embedding is not the original business data; it is an artifact derived from text. When a title, description, language, permissions, or the embedding model itself changes, the old vector can no longer represent the content correctly. This misalignment is called **drift**.

A reliable lifecycle detects inserts, updates, and deletes; identifies affected chunks; regenerates vectors; and records when and with which model that happened. Use a dirty flag, timestamp, or watermark to make processing incremental and idempotent. A model, dimension, or text-format change usually requires a full re-embedding because the new vectors belong to a different vector space.

> [!important] Updating text is not enough
>
> Semantic search can still run with an old vector, but it will retrieve stale results. Embedding maintenance is therefore part of solution design, not an occasional cleanup task.

## Embedding Maintenance Methods Comparison

| Method | Latency | Complexity | Infrastructure | Best For |
| :--- | :--- | :--- | :--- | :--- |
| Table Triggers | Near real-time | Low | `None (in-DB)` | Small tables, low write volume |
| Change Tracking | Low (polling) | Medium | SQL Agent or scheduler | Moderate volume, batch-friendly |
| CDC | Medium (polling) | Medium | SQL Agent (on-prem) | Audit trail needed with embeddings |
| CES | Near real-time | Medium | Azure Event Hubs / Eventstream | SQL Server 2025, Azure SQL Database, or Azure SQL Managed Instance (preview) |
| Azure Functions SQL Trigger | Near real-time | Medium | Azure Functions + Change Tracking | Decoupled processing through polling |
| Azure Logic Apps | Minutes | Low | Logic Apps | Low-code, low-volume |
| Microsoft Foundry | Configurable | Low | Fabric/Foundry | Declarative AI pipeline |

---

## Method 1: Table Triggers

Triggers fire synchronously on INSERT/UPDATE, calling the embedding model immediately.

```sql
-- Requires an external model already registered
-- CREATE EXTERNAL MODEL [MyEmbeddingModel] ...

CREATE OR ALTER TRIGGER trg_Products_EmbedDescription
ON dbo.Products
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Only regenerate if the Description actually changed
    IF UPDATE(Description)
    BEGIN
        UPDATE p
        SET DescriptionEmbedding = AI_GENERATE_EMBEDDINGS(
            i.Description USE MODEL [MyEmbeddingModel]
        )
        FROM dbo.Products p
        INNER JOIN inserted i ON p.ProductId = i.ProductId;
    END;
END;
```

**Tradeoffs:**

- Simple — no external infrastructure
- Adds latency to every INSERT/UPDATE (synchronous API call)
- If the AI endpoint is unavailable, the write transaction fails
- Not suitable for high-volume write tables (each row = one API call)

---

## Method 2: Change Tracking (Batch Polling)

Change Tracking records which rows changed; a background job re-embeds them in batches.

```sql
-- Enable Change Tracking on the database and table
ALTER DATABASE MyDB SET CHANGE_TRACKING = ON
    (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON);

ALTER TABLE dbo.Products
ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);

-- Watermark table
CREATE TABLE dbo.EmbeddingWatermark (
    TableName    NVARCHAR(100) PRIMARY KEY,
    SyncVersion  BIGINT NOT NULL
);
INSERT INTO dbo.EmbeddingWatermark VALUES ('Products', CHANGE_TRACKING_CURRENT_VERSION());
```

```sql
-- Embedding maintenance job (runs on a schedule via SQL Agent or App Service)
DECLARE @last_version BIGINT;
SELECT @last_version = SyncVersion FROM dbo.EmbeddingWatermark WHERE TableName = 'Products';

-- Find products whose Description changed since last run
UPDATE p
SET DescriptionEmbedding = AI_GENERATE_EMBEDDINGS(
    p.Description USE MODEL [MyEmbeddingModel]
)
FROM dbo.Products p
INNER JOIN CHANGETABLE(CHANGES dbo.Products, @last_version) AS ct
    ON p.ProductId = ct.ProductId
CROSS APPLY (SELECT p.Description) p2(Description)
WHERE ct.SYS_CHANGE_COLUMNS IS NULL  -- all columns changed (no column tracking)
   OR CHANGE_TRACKING_IS_COLUMN_IN_MASK(
        COLUMNPROPERTY(OBJECT_ID('dbo.Products'), 'Description', 'ColumnId'),
        ct.SYS_CHANGE_COLUMNS) = 1;  -- specifically Description changed

-- Update watermark
UPDATE dbo.EmbeddingWatermark
SET SyncVersion = CHANGE_TRACKING_CURRENT_VERSION()
WHERE TableName = 'Products';
```

**Tradeoffs:**

- Decouples write performance from embedding generation
- Latency = polling interval (seconds to minutes)
- Resilient to AI endpoint failures (retry at next poll)
- Requires a scheduler (SQL Agent, Azure Automation, App Service WebJob)

---

## Method 3: CDC (Change Data Capture)

CDC captures before/after values; useful when you need to know what changed before updating the embedding.

```sql
-- After enabling CDC on the database and Products table...
DECLARE @from_lsn BINARY(10);
DECLARE @to_lsn   BINARY(10) = sys.fn_cdc_get_max_lsn();

SELECT @from_lsn = LastLSN FROM dbo.EmbeddingCDCWatermark WHERE TableName = 'dbo_Products';

-- Get only changed rows (net changes — final state)
WITH ChangedProducts AS (
    SELECT ProductId
    FROM cdc.fn_cdc_get_net_changes_dbo_Products(@from_lsn, @to_lsn, 'all')
    WHERE __$operation IN (2, 5)  -- INSERT or INSERT_OR_UPDATE
)
UPDATE p
SET DescriptionEmbedding = AI_GENERATE_EMBEDDINGS(
    p.Description USE MODEL [MyEmbeddingModel]
)
FROM dbo.Products p
INNER JOIN ChangedProducts cp ON p.ProductId = cp.ProductId;

-- Update CDC watermark
UPDATE dbo.EmbeddingCDCWatermark
SET LastLSN = @to_lsn
WHERE TableName = 'dbo_Products';
```

---

## Method 4: Azure Functions with SQL Trigger Binding

Azure Functions can listen for table changes and call the OpenAI API to regenerate embeddings asynchronously.

```csharp
[FunctionName("UpdateProductEmbeddings")]
public static async Task Run(
    [SqlTrigger("[dbo].[Products]", "SqlConnectionString")]
    IReadOnlyList<SqlChange<Product>> changes,
    [Sql("[dbo].[Products]", "SqlConnectionString")] IAsyncCollector<Product> productsOut,
    ILogger log)
{
    var openAiClient = new OpenAIClient(new Uri(openAiEndpoint), new AzureKeyCredential(apiKey));

    foreach (var change in changes.Where(c =>
        c.Operation == SqlChangeOperation.Insert || c.Operation == SqlChangeOperation.Update))
    {
        if (change.Item.Description == null) continue;

        var embeddings = await openAiClient.GetEmbeddingsAsync(
            new EmbeddingsOptions("text-embedding-3-small", new[] { change.Item.Description }));

        var updatedProduct = change.Item with
        {
            DescriptionEmbedding = embeddings.Value.Data[0].Embedding.ToArray()
        };

        // Write updated embedding back to SQL
        await productsOut.AddAsync(updatedProduct);
    }
}
```

**Tradeoffs:**

- Event-driven — near real-time with minimal polling overhead
- Infrastructure: requires Azure Functions deployment and configuration
- Resilient: Azure Functions handles retries on failure
- Can process changes in batches (multiple rows per trigger invocation)

---

## Method 5: CES (Change Event Streaming)

In SQL Server 2025, Azure SQL Database, and Azure SQL Managed Instance (preview), CES streams changes to Azure Event Hubs and can feed a Fabric Eventstream. A downstream pipeline or notebook can then re-generate embeddings.

```text
SQL Server 2025, Azure SQL Database, or Azure SQL Managed Instance (Products table)
    → CES (Change Event Streaming)
        → Fabric Eventstream
            → Fabric Notebook (Python)
                → Azure OpenAI: generate embedding
                → Write back to SQL Database
```

```python
# Fabric Notebook: process CES events and update embeddings
import openai
import pyodbc

for event in eventstream_batch:
    product_id = event["ProductId"]
    description = event["Description"]

    # Generate embedding
    response = openai.embeddings.create(
        model="text-embedding-3-small",
        input=description
    )
    embedding = response.data[0].embedding  # list of 1536 floats

    # Update the SQL Database
    cursor.execute(
        "UPDATE dbo.Products SET DescriptionEmbedding = ? WHERE ProductId = ?",
        (str(embedding), product_id)
    )
```

---

## Method 6: Azure Logic Apps

Logic Apps polls for changes on a schedule and calls the embedding API via an HTTP action.

```text
Logic App:
├── Trigger: Recurrence (every 5 minutes)
├── Action: SQL - Execute Stored Procedure → dbo.GetProductsNeedingEmbedding
├── For Each (products):
│   ├── Action: HTTP POST to Azure OpenAI embeddings endpoint
│   └── Action: SQL - Execute Query → UPDATE dbo.Products SET Embedding = ?
└── End
```

```sql
-- Stored procedure to find products needing embedding refresh
CREATE OR ALTER PROCEDURE dbo.GetProductsNeedingEmbedding
    @BatchSize INT = 50
AS
BEGIN
    SELECT TOP (@BatchSize)
        ProductId,
        Description
    FROM dbo.Products
    WHERE DescriptionEmbedding IS NULL
       OR DescriptionLastUpdated > EmbeddingGeneratedAt
    ORDER BY DescriptionLastUpdated ASC;
END;
```

---

## Method 7: Microsoft Foundry

**Microsoft Foundry** can be used as an external orchestration layer for embedding workflows. Depending on the selected Foundry service and pipeline components, you can configure a SQL source, model call, batching, retries, monitoring, and write-back. These capabilities are not a new SQL Database `AI_*` function and the exact steps depend on the selected service.

Treat this as an architecture option to compare with Change Tracking, CDC, CES, and triggers; verify the current DP-800 skills measured and the current Foundry documentation before relying on a specific feature.

### Architecture

```text
Foundry Project
├── Connections:
│   ├── SQL connection (Azure SQL DB / SQL DB in Fabric / on-prem via SHIR)
│   └── Embedding model deployment (text-embedding-3-small / -large / ada-002 legacy)
├── Pipeline / Flow:
│   ├── Source step:   SELECT ProductId, Description, LastUpdated
│   │                  FROM dbo.Products
│   │                  WHERE DescriptionEmbedding IS NULL
│   │                     OR LastUpdated > EmbeddingGeneratedAt
│   ├── Chunk step:    (optional) split long Description into N-token chunks
│   ├── Embed step:    POST chunks to the model deployment in batch
│   └── Sink step:     UPDATE dbo.Products SET DescriptionEmbedding = @vec,
│                                              EmbeddingGeneratedAt = SYSUTCDATETIME()
│                                          WHERE ProductId = @id
└── Trigger:
    ├── Scheduled (cron, recurrence)
    ├── Event-driven (Fabric Eventstream / Event Grid)
    └── On-demand (Foundry SDK / REST API)
```

### Step-by-step setup (typical)

1. **Create a Foundry project** in the Microsoft Foundry portal (<https://ai.azure.com/>). Pick a region close to your SQL endpoint to minimise embedding-call latency.
2. **Deploy the embedding model** — `text-embedding-3-small` (1 536 dims) is the standard choice; `text-embedding-3-large` (3 072 dims) for higher recall at higher cost; `ada-002` is legacy and rarely the right pick today.
3. **Add and authenticate a SQL connection** using the connection method supported by the selected Foundry service. Prefer managed identity or another secret-management mechanism where supported, and grant only the required database permissions.
4. **Author the pipeline** either via the visual editor or via a YAML flow definition. The minimum shape is the four steps above (source → chunk → embed → sink).
5. **Attach a trigger** — scheduled recurrence for batch-style refresh, or event-driven (via a Fabric Eventstream subscribed to CES from the source DB) for near-real-time.
6. **Deploy the pipeline** and configure retry/back-off, batching, and idempotent write-back according to the selected service.
7. **Monitor** via the Foundry project's built-in run-history pane — every run records source rows processed, tokens consumed, sink rows updated, and any per-row failures.

### When to choose Foundry

```text
Use Foundry when:
✓ You want NO code (declarative pipeline > triggers/jobs)
✓ Embedding maintenance is one of several AI workflows you're orchestrating
  (RAG indexing, batch scoring, evaluation) and you want them in one place
✓ You're already in the Foundry/Fabric ecosystem
✓ You need centralised monitoring, cost tracking, and audit per AI workflow
✓ The pipeline shape is "SQL → embed → SQL" (the most-supported template)

Avoid Foundry when:
✗ Sub-30-second latency required from source change → embedding write
  (use CES + Notebook, or table triggers, instead)
✗ Your embedding logic needs custom Python (rich text preprocessing,
  multi-modal inputs, custom chunking) — pipelines can call out, but
  at that point a Fabric Notebook is simpler
✗ Source is purely on-prem with no Self-Hosted Integration Runtime
✗ Compliance forbids cross-region data flow that Foundry's hosted
  embedding endpoint would create
```

### Foundry vs CES — the canonical comparison

Both Foundry and CES (Change Event Streaming) appear on the blueprint as named methods, and the exam loves to contrast them.

| Aspect | Microsoft Foundry | CES (Change Event Streaming) |
| :--- | :--- | :--- |
| **Source platform** | Depends on the selected Foundry connector and integration runtime | SQL Server 2025, Azure SQL Database, or Azure SQL Managed Instance (preview) |
| **Code required** | Depends on the selected pipeline components | Notebook code (Python) or Pipeline activities |
| **Trigger** | Schedule / event-driven / on-demand | Event-driven (push from CES) |
| **Latency** | Seconds to minutes (depending on trigger) | Near-real-time (push-based) |
| **Embedding logic** | Depends on the selected model/pipeline component | You write it in the Notebook or pipeline |
| **Monitoring** | Foundry run history (centralised) | Eventstream + Notebook job history (split) |
| **Best for** | Multi-workflow AI projects, batch + scheduled refresh, no-code teams | Change streaming to Event Hubs/Eventstream with a downstream consumer |

### What the exam will ask

> [!warning] Common Mistake
> "Microsoft Foundry **requires** Fabric" is an unsafe assumption. Check the connector and integration-runtime support of the selected Foundry service. CES is a separate preview feature for SQL Server 2025, Azure SQL Database, and Azure SQL Managed Instance; Fabric Eventstream can be one of its consumers.

> [!note] Mental model — Foundry vs the others
> **Foundry is the "credit card" option** — pay (in service cost + lock-in) for ergonomics. **CES is the "tap to pay"** — a push-based preview path through Event Hubs or Eventstream. **CDC/Change Tracking are "bank transfers"** — they work everywhere but you write the plumbing. **Triggers are "cash"** — immediate, but they add write latency.

```python
# Foundry handles the embedding call for you, but if you want to see what
# it does under the hood, this is approximately what the Embed step runs:
import requests

embedding = requests.post(
    "https://<your-foundry>.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01",
    headers={"api-key": "<managed-identity-token-from-foundry>"},
    json={"input": description}
).json()["data"][0]["embedding"]

# A configured Foundry pipeline can write back to SQL through its configured connection;
# required from you. The whole pipeline declaration is YAML or visual.
```

---

## Choosing an Approach

```mermaid
flowchart TD
    Start([Source text changes]) --> Vol{"High write volume<br/>> 1000 rows/min?"}
    Vol -- yes --> Batch["Batch approach:<br/><b>Change Tracking</b> or <b>CDC</b><br/>(decouple writes from embed cost)"]
    Vol -- no --> Plat{"Platform = SQL Database<br/>in Microsoft Fabric?"}
    Plat -- yes --> CES["<b>CES</b><br/>(push-based, zero infra)"]
    Plat -- no --> Lat{"Real-time latency<br/>required (< 30 s)?"}
    Lat -- yes --> AF["<b>Azure Functions</b><br/>SQL trigger binding"]
    Lat -- no --> LC{"Prefer no-code /<br/>low-code?"}
    LC -- yes --> Foundry["<b>Microsoft Foundry</b><br/>(declarative pipeline)<br/>or <b>Logic Apps</b>"]
    LC -- no --> CT["<b>Change Tracking</b><br/>with SQL Agent job"]
```

---

## Use Cases

- **Product catalog**: New products or description updates trigger embedding regeneration via Azure Functions
- **Document library**: Daily batch job using Change Tracking re-embeds documents modified since last run
- **Fabric data platform**: CES-driven pipeline automatically keeps Lakehouse embeddings in sync with SQL source

---

## Common Issues & Errors

| Issue | Cause | Fix |
| :--- | :--- | :--- |
| Trigger causes timeouts on bulk loads | Trigger fires per-row for large imports | Disable trigger during bulk load; use batch re-embedding afterward |
| Change Tracking min version exceeded | Sync version older than retention period | Do a full re-embed of all rows; reset watermark |
| Embedding drift undetected | Source text updated without regenerating embedding | Add `EmbeddingGeneratedAt` column and compare to `UpdatedAt` |
| Azure Functions not firing | Change Tracking not enabled or retention is too short | Enable Change Tracking on the database and table, configure retention, and grant the trigger's documented permissions |

---

## Exam Tips

> [!tip] Exam Tips
>
> - **Triggers**: Simplest but synchronous — adds AI API latency to every write; risky if endpoint is down
> - **Change Tracking**: Best for batch scenarios — decouple embedding from write path
> - **Azure Functions SQL trigger**: uses Change Tracking and polls for changes; it decouples processing but is not a push trigger
> - **CES**: preview push-based change streaming from SQL Server 2025, Azure SQL Database, or Azure SQL Managed Instance to Azure Event Hubs; a downstream Eventstream is optional
> - Always maintain a watermark (version or timestamp) to know which rows have been embedded

---

## Key Takeaways

- No single embedding maintenance method suits all scenarios — choose based on volume, latency, and infrastructure
- Synchronous approaches (triggers) have simplicity but risk tightly coupling writes to AI API availability
- Asynchronous batch approaches (Change Tracking, CDC) are more resilient but have higher embedding latency
- Use CES when its preview support and Event Hubs/Eventstream integration fit the architecture; it is not Fabric-only

---

## Related Topics

- [01-External Models](./01-external-models.md)
- [03-Chunking & Generation](./03-chunking-generation.md)
- [04-Change & Event Handling](../08-azure-services-integration/04-change-event-handling.md)

---

## Official Documentation

- [Azure Functions SQL Trigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-azure-sql-trigger)
- [Change Tracking](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-tracking-sql-server)
- [Change Event Streaming](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/change-event-streaming/overview)

---

**[← Previous](./01-external-models.md) | [↑ Back to Section](./models-embeddings.md) | [Lab: Embedding Maintenance](../../practice/labs/09-models-embeddings/02-embedding-maintenance-lab.sql) | [Next →](./03-chunking-generation.md)**
