---
title: Change and Event Handling
type: study-material
tags:
  - dp-800
  - cdc
  - change-tracking
  - azure-functions
  - ces
---

# Change and Event Handling

## Overview

Reacting to data changes is fundamental to building event-driven systems. SQL Server and Azure SQL offer several mechanisms at different granularities: **Change Tracking** (did a row change?), **CDC** (changes stored in capture tables), and **CES** (Change Event Streaming to Azure Event Hubs). These feed downstream systems via Azure Functions SQL trigger binding, Logic Apps, Fabric Eventstream, or direct streaming.

> [!abstract]
>
> - Covers Change Data Capture (CDC) and Change Tracking (CT): what changed, when, and how to consume it
> - CDC and CT both track data changes but differ in detail captured and infrastructure required
> - Key exam topics: CDC vs CT differences, CDC agent dependency, CT lightweight use cases

> [!tip] What the Exam Tests
>
> - **CDC**: can expose before/after values with `all update old`; requires SQL Server Agent on SQL Server and Azure SQL Managed Instance; stores changes in capture tables; used for ETL/replication
> - **Change Tracking**: captures only that a row changed (row ID + operation); no Agent required; used for sync scenarios where you only need to know *what* changed, not *how*
> - CDC has latency (agent job); CT is synchronous (committed with the transaction)

---

## Change Data Capture (CDC)

**Change Data Capture (CDC)** records detailed `INSERT`, `UPDATE`, and `DELETE`
changes made to tables. It captures which row changed, which operation occurred,
and the values before and after the change.

CDC reads the transaction log asynchronously and stores events in capture tables
that mirror the source table columns. Functions such as
`cdc.fn_cdc_get_all_changes...` and `cdc.fn_cdc_get_net_changes...` expose that
history to consumers.

Use CDC when you need history or the changed values, for example for incremental
ETL, data warehouses, auditing, replication, and integration with external
systems. Because it preserves more information, it uses more storage and
processing than Change Tracking.

### Enabling CDC

```sql
-- Enable CDC on the database
EXEC sys.sp_cdc_enable_db;

-- Verify
SELECT is_cdc_enabled FROM sys.databases WHERE name = DB_NAME();

-- Enable CDC on a specific table
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name   = N'Orders',
    @role_name     = N'cdc_reader',  -- db_role that can read CDC tables; NULL = no role check
    @supports_net_changes = 1;       -- 1 = also capture net changes

-- Verify CDC-enabled tables
SELECT source_schema, source_name, capture_instance, has_drop_pending
FROM cdc.change_tables;
```

### Querying CDC Changes

CDC functions return the change records within an LSN (Log Sequence Number) range:

```sql
-- Get the current LSN range
DECLARE @from_lsn BINARY(10) = sys.fn_cdc_get_min_lsn('dbo_Orders');
DECLARE @to_lsn   BINARY(10) = sys.fn_cdc_get_max_lsn();

-- Query all changes (INSERT=2, UPDATE before=3, UPDATE after=4, DELETE=1)
SELECT
    sys.fn_cdc_map_lsn_to_time(__$start_lsn) AS ChangeTime,
    CASE __$operation
        WHEN 1 THEN 'DELETE'
        WHEN 2 THEN 'INSERT'
        WHEN 3 THEN 'UPDATE_BEFORE'
        WHEN 4 THEN 'UPDATE_AFTER'
    END AS Operation,
    OrderId,
    CustomerId,
    Status,
    TotalAmount
FROM cdc.fn_cdc_get_all_changes_dbo_Orders(@from_lsn, @to_lsn, 'all update old')
ORDER BY __$start_lsn;
```

```sql
-- Net changes (only the final state, even if a row was updated multiple times)
SELECT
    CASE __$operation
        WHEN 1 THEN 'DELETE'
        WHEN 5 THEN 'INSERT_OR_UPDATE'  -- net change combines updates
    END AS Operation,
    OrderId,
    Status
FROM cdc.fn_cdc_get_net_changes_dbo_Orders(@from_lsn, @to_lsn, 'all with merge');
```

### LSN-Based Incremental Processing

An **LSN (Log Sequence Number)** is a sequential identifier used by CDC to
order changes captured from the transaction log. A watermark is the persisted
LSN that records how far the pipeline has processed the data. On the next run,
the pipeline reads only the following interval instead of scanning the entire
table again.

The flow is:

```text
1. Read the last processed LSN
2. Capture the current LSN as the run boundary
3. Read and process changes between both points
4. Update the watermark only after successful processing
```

```sql
-- Store the last processed LSN in a control table
CREATE TABLE dbo.CDCWatermark (
    TableName   NVARCHAR(100) PRIMARY KEY,
    LastLSN     BINARY(10)    NOT NULL
);

-- Insert initial watermark
INSERT INTO dbo.CDCWatermark VALUES ('dbo_Orders', sys.fn_cdc_get_min_lsn('dbo_Orders'));

-- Incremental processing pattern
DECLARE @last_lsn BINARY(10);
DECLARE @current_lsn BINARY(10) = sys.fn_cdc_get_max_lsn();

SELECT @last_lsn = LastLSN FROM dbo.CDCWatermark WHERE TableName = 'dbo_Orders';

-- Process only new changes since last run
SELECT * FROM cdc.fn_cdc_get_all_changes_dbo_Orders(@last_lsn, @current_lsn, 'all')
WHERE __$start_lsn > @last_lsn;  -- exclude the last processed LSN

-- Update watermark after successful processing
UPDATE dbo.CDCWatermark
SET LastLSN = @current_lsn
WHERE TableName = 'dbo_Orders';
```

For example, if the stored watermark is LSN 100 and the run finds changes up to
LSN 120, it processes 101–120 and stores 120 as the new watermark. Changes
created after `@current_lsn` was captured are left for the next run.

The watermark must advance only after the destination load succeeds. If the
run fails before the `UPDATE`, the next attempt reads the same interval again.
This may process a change more than once, but it prevents data loss; therefore,
the destination should be idempotent or use a transaction with key/LSN control.

`fn_cdc_get_all_changes` returns every change in the interval. With
`all update old`, an update is returned as a before image (`3`) and an after
image (`4`). `fn_cdc_get_net_changes` returns only the row's final state within
the interval. With `all with merge`, `__$operation = 5` means insert or update
without distinguishing between them. This reduces volume but does not preserve
every intermediate change.

---

## Change Tracking

**Change Tracking (CT)** is a lighter alternative to CDC. It records that a row
changed, the operation (`I`, `U`, or `D`), and the change version, but it does
not store the row's before and after values.

To obtain current data, the application queries the source table using the
primary key returned by `CHANGETABLE`. If a row is updated several times, CT
does not preserve every intermediate step; it is intended to identify rows that
need synchronization.

Use CT for synchronization between databases and applications, cache refreshes,
simple replication, and scenarios where only the current state matters. It has
lower storage and processing overhead, but it does not replace CDC for auditing
or detailed history.

### Enabling Change Tracking

```sql
-- Enable at database level
ALTER DATABASE MyDB SET CHANGE_TRACKING = ON
    (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON);

-- Enable on specific table
ALTER TABLE dbo.Products
ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);

-- Verify
SELECT * FROM sys.change_tracking_databases;
SELECT * FROM sys.change_tracking_tables;
```

### Querying Change Tracking

```sql
-- Get initial synchronization version
DECLARE @sync_version BIGINT = CHANGE_TRACKING_CURRENT_VERSION();

-- ... (initial full load) ...

-- Later: get changes since @sync_version
SELECT
    ct.OrderId,
    ct.SYS_CHANGE_OPERATION,   -- I=Insert, U=Update, D=Delete
    ct.SYS_CHANGE_VERSION,
    o.Status,
    o.TotalAmount
FROM CHANGETABLE(CHANGES dbo.Orders, @sync_version) AS ct
LEFT JOIN dbo.Orders o ON o.OrderId = ct.OrderId  -- NULL for deletes
ORDER BY ct.SYS_CHANGE_VERSION;

-- Update the sync version after processing
SET @sync_version = CHANGE_TRACKING_CURRENT_VERSION();
```

**Change Tracking vs CDC:**

| Feature | Change Tracking | CDC |
| :--- | :--- | :--- |
| Before image (old values) | No | `Yes` |
| After image (new values) | No (join to table) | Yes |
| Column-level granularity | Which columns (optional) | Full row |
| Storage overhead | Low | Medium |
| Retention | Configurable (days) | Until cleanup job runs |
| Use case | Sync, replication | Audit, ETL, streaming |

Practical rule: use **CDC** when you need to know what changed and what the
values were; use **CT** when you only need to discover which rows must be
synchronized. CDC and CT can be enabled at the same time in the same database.

### Choosing by volume and scenario

The ranges below are **planning heuristics**, not SQL Server limits. The real
decision also depends on row size, change rate per minute, latency requirements,
retention period, and consumer capacity.

| Approximate scenario | Recommended mechanism | Reason |
| :--- | :--- | :--- |
| Up to 10,000 changes per run, periodic synchronization, and current state is enough | CT | Lower storage and operational cost; the application retrieves current rows by primary key. |
| 10,000 to 1 million changes per run, with ETL or a need for history | CDC | Supports LSN-based windows and preserves operations plus before/after values. |
| More than 1 million changes per run or high daily volume | CDC with batching, watermarking, and, where appropriate, `net changes` | Controls backlog and source load; evaluate partitioning, retention, and parallel consumers. |
| Cache synchronization, mobile application, or replica that only needs rows to reload | CT | The consumer receives changed keys and reads current state without storing full history. |
| Auditing, compliance, event reconstruction, or integrations requiring `before`/`after` | CDC | Detailed history is required; CT cannot recover intermediate values. |
| Low latency and a continuous high-volume event flow | CDC or CES, depending on the platform | CDC supports LSN-based polling; CES is better suited when event streaming is required. |

#### High-volume considerations

- With **CDC**, monitor the lag between produced and consumed LSNs, capture-table size, and history retention.
- With **CT**, set retention longer than the worst expected interval between synchronizations. If a consumer falls behind the retention window, a full reload is required.
- For both mechanisms, process in batches, persist the watermark only after success, and make the destination idempotent to support retries.
- If only final state matters, `fn_cdc_get_net_changes` can reduce data volume; if every intermediate event matters, use `fn_cdc_get_all_changes`.

> [!warning] Common Mistake
> CDC and Change Tracking are often confused. CDC = captures the actual data values before and after change (heavier, requires Agent). CT = captures only that a change happened to a row (lightweight, no Agent). If the scenario requires knowing the old value of a column, the answer is CDC, not CT.

---

## Azure Functions SQL Trigger Binding

The Azure Functions SQL trigger binding monitors a SQL table and fires a function whenever rows are inserted, updated, or deleted. It uses Change Tracking internally.

### Function Definition (C#)

```csharp
// Triggered when dbo.Orders changes
[Function("ProcessOrderChanges")]
public static async Task Run(
    [SqlTrigger("[dbo].[Orders]", "SqlConnectionString")]
    IReadOnlyList<SqlChange<Order>> changes,
    FunctionContext context)
{
    ILogger log = context.GetLogger("ProcessOrderChanges");
    foreach (SqlChange<Order> change in changes)
    {
        Order order = change.Item;
        log.LogInformation($"Change: {change.Operation} OrderId={order.OrderId} Status={order.Status}");

        switch (change.Operation)
        {
            case SqlChangeOperation.Insert:
                await ProcessNewOrder(order);
                break;
            case SqlChangeOperation.Update:
                await ProcessOrderUpdate(order);
                break;
            case SqlChangeOperation.Delete:
                // order.OrderId is populated; other fields may be null
                await HandleOrderDeletion(order.OrderId);
                break;
        }
    }
}
```

### local.settings.json for SQL Trigger

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "SqlConnectionString": "Server=myserver.database.windows.net;Database=MyDB;Authentication=Active Directory Default;"
  }
}
```

Change Tracking must be enabled on the database and target table. The trigger
creates internal state and lease tables in the `az_func` schema. `db_owner` is
one broad way to grant access, but production deployments should use the
documented least-privilege permissions. New projects should prefer the isolated
worker model; the in-process model reaches end of support on November 10, 2026.

---

## Change Event Streaming (CES) to Azure Event Hubs and Microsoft Fabric

CES is a preview feature for SQL Server 2025, Azure SQL Database, and Azure SQL Managed Instance. It streams table changes to **Azure Event Hubs** over AMQP or Kafka. Microsoft Fabric Eventstream can consume those events through Event Hubs and route them to Lakehouse, KQL Database, or other destinations.

```text
SQL Server 2025 / Azure SQL → CES → Azure Event Hubs → Fabric Eventstream → Lakehouse / KQL Database

Configuration outline:
1. Create an Azure Event Hubs namespace and event hub
2. Enable CES in the source database
3. Create a streaming group with credentials and destination
4. Add the tables to be streamed
```

CES works in near-real-time and delivers change events with:

- Table name, operation type (Insert/Update/Delete)
- Current and, depending on the event, previous row values
- Commit LSN and timestamp
- JSON or Avro serialization

CES does not perform an initial snapshot: it streams only changes that occur
after CES is enabled. SQL Server 2025 requires the `FULL` recovery model and
the corresponding preview database configuration. CES cannot be enabled on a
database that already uses CDC.

---

## Azure Logic Apps for Change Handling

Logic Apps can poll for changes using a Recurrence trigger and a SQL connector:

```text
Logic App workflow:
├── Trigger: Recurrence (every 1 minute)
├── Action: SQL Server - Execute Stored Procedure
│         → dbo.GetUnprocessedChanges
│         (returns rows from a change queue table)
├── For Each: Process each changed row
│   ├── Action: Send email / HTTP POST / Service Bus message
│   └── Action: SQL Server - Execute Query (mark row as processed)
└── End
```

```sql
-- Change queue table pattern (used with Logic Apps polling)
CREATE TABLE dbo.ChangeQueue (
    ChangeId     INT          NOT NULL IDENTITY(1,1),
    TableName    NVARCHAR(100) NOT NULL,
    Operation    CHAR(1)      NOT NULL,  -- I, U, D
    RecordId     INT          NOT NULL,
    ChangedAt    DATETIME2    NOT NULL DEFAULT GETUTCDATE(),
    Processed    BIT          NOT NULL DEFAULT 0,
    ProcessedAt  DATETIME2    NULL
);

-- Trigger to populate the queue
CREATE TRIGGER trg_Orders_AfterInsertUpdate
ON dbo.Orders
AFTER INSERT, UPDATE
AS
BEGIN
    INSERT INTO dbo.ChangeQueue (TableName, Operation, RecordId)
    SELECT 'Orders',
           CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN 'U' ELSE 'I' END,
           OrderId
    FROM inserted;
END;

-- Get unprocessed changes (called by Logic App)
CREATE OR ALTER PROCEDURE dbo.GetUnprocessedChanges
    @BatchSize INT = 100
AS
BEGIN
    WITH Batch AS (
        SELECT TOP (@BatchSize) ChangeId, TableName, Operation, RecordId, ChangedAt
        FROM dbo.ChangeQueue
        WHERE Processed = 0
        ORDER BY ChangeId
    )
    UPDATE Batch
    SET Processed = 1, ProcessedAt = GETUTCDATE()
    OUTPUT DELETED.ChangeId, DELETED.TableName, DELETED.Operation,
           DELETED.RecordId, DELETED.ChangedAt;
END;
```

---

## Use Cases

- **CDC for data warehouse ETL**: Capture all row changes for incremental loading into Synapse or Fabric Lakehouse
- **Change Tracking for mobile sync**: Sync only changed rows to mobile clients since their last connection
- **Azure Functions SQL trigger**: Real-time event processing — update a search index, send notifications, or trigger downstream workflows whenever orders change
- **CES with Fabric Eventstream**: Stream SQL changes through Azure Event Hubs to Lakehouse, KQL Database, or other downstream workloads
- **Logic Apps polling**: Low-code integration with change data for alerting and notification workflows

---

## Common Issues & Errors

| Issue | Cause | Fix |
| :--- | :--- | :--- |
| CDC capture job not running | SQL Agent not running (on-prem/MI) | Start SQL Agent; on Azure SQL Database, capture and cleanup are managed by the platform |
| `@from_lsn` returns NULL | CDC not enabled or no data yet | Verify `sp_cdc_enable_db` and `sp_cdc_enable_table` ran successfully |
| Change Tracking retention exceeded | Sync version too old | Use `CHANGE_TRACKING_MIN_VALID_VERSION()` to validate; do full resync if needed |
| SQL trigger function not firing | Change Tracking not enabled or insufficient `az_func` permissions | Enable CT on the database and table; grant the documented least-privilege permissions |
| CES not available | Unsupported platform, destination, configuration, or preview limitation | Verify SQL Server 2025/Azure SQL Database/Azure SQL Managed Instance, Azure Event Hubs, recovery model, and current CES limitations |

---

## Exam Tips

> [!tip] Exam Tips
>
> - **CDC**: Captures changes in capture tables; use `all update old` when before AND after values are required; requires SQL Agent on SQL Server/MI or managed capture on Azure SQL Database
> - **Change Tracking**: Only tracks that a row changed; no before image; lighter weight; requires join to get current values
> - **Azure Functions SQL trigger**: Uses Change Tracking under the hood — enables it automatically on the source table
> - **CES**: Streams to Azure Event Hubs; Fabric Eventstream can consume the events; it requires destination, credentials, streaming-group, and table configuration
> - `SYS_CHANGE_OPERATION` values: `I` = Insert, `U` = Update, `D` = Delete
> - CDC `__$operation` values: `1` = Delete, `2` = Insert, `3` = Update (before), `4` = Update (after)

---

## Key Takeaways

- CDC provides retained change history and can expose before/after images with the appropriate query option; Change Tracking provides lightweight sync capability
- Azure Functions SQL trigger is the easiest way to react to SQL changes in real-time from application code
- CES streams SQL changes to Azure Event Hubs, which can feed Fabric Eventstream and downstream Fabric workloads
- LSN-based watermarking is the standard pattern for incremental CDC-based ETL

---

## Related Topics

- [03-Monitoring](./03-monitoring.md)
- [02-Embedding Maintenance](../09-models-embeddings/02-embedding-maintenance.md)
- [02-Transaction Isolation & Concurrency](../06-performance-optimization/02-transaction-isolation-concurrency.md)

---

## Official Documentation

- [CDC in SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-data-capture-sql-server)
- [Change Tracking](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-tracking-sql-server)
- [Azure Functions SQL Trigger Binding](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-azure-sql-trigger)
- [Change Event Streaming (CES)](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/change-event-streaming/overview)
- [Stream SQL change events to Fabric Eventstream](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/stream-sql-change-events-to-eventstream)

---

**[← Previous](./03-monitoring.md) | [↑ Back to Section](./azure-services-integration.md) | [Lab: Change Event Handling](../../practice/labs/08-azure-services-integration/04-change-event-handling-lab.sql)**
