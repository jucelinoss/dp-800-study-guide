---
title: Index Fundamentals
type: topic
tags: [sql-server, indexes, performance, fundamentals]
---

# Index Fundamentals

## Overview

An index is an auxiliary data structure that helps SQL Server locate rows with less work. The trade-off is clear: **better read performance** for queries that use the index, at the cost of **additional storage and write maintenance** on every insert, update, and delete.

> [!abstract]
>
> - A **clustered index** determines the table's physical row order; there can be at most one.
> - A **nonclustered index** is a separate structure; a table can have many.
> - Index choices must reflect real query patterns — creating indexes on every column slows writes and can confuse the optimizer.
> - Measure before and after: use `STATISTICS IO` and query plans to evaluate effectiveness.

> [!tip] What the Exam Tests
> This section establishes the mental model of what an index is and how it accelerates queries. Deep index design — columnstore, filtered indexes, compression, index maintenance — is covered in Section 01. Query plan analysis and index tuning belong to Section 06.

---

## Why indexes exist

Without an index, SQL Server must scan the entire table to find matching rows. This is called a **table scan** (heap) or **clustered index scan**. An index enables a **seek** — navigating a tree structure to quickly locate the relevant rows.

### B-tree diagram (conceptual)

```text
Root level:        [A–M]
                  /     \
Intermediate:  [A–F]   [G–M]
               /   \    /   \
Leaf:        [A][B][F] [G][K][M]   ← Each leaf entry points to a data row
```

**Seek:** Navigate root → intermediate → leaf to find specific values (fast).<br>
**Scan:** Read every leaf page from start to end (slow for large tables with selective queries).

> [!note] Mental model — index = book index
> Think of a nonclustered index like the index at the back of a book. To find all pages mentioning "clustered index", you look up the term in the index (seek) rather than reading every page (scan). A clustered index is like the page numbers themselves — the book is physically ordered by page number.

## Clustered vs Nonclustered

| Aspect | Clustered index | Nonclustered index |
| :--- | :--- | :--- |
| **Count per table** | At most one | Up to 999 |
| **Physical order** | Determines row storage order | Separate structure with key + row locator |
| **Leaf level** | Contains actual data rows | Contains key columns + bookmark to data row |
| **Default for PK?** | Yes (unless `NONCLUSTERED` is specified) | Only if PK is defined as nonclustered |
| **Table without one** | Called a **heap** | N/A |

### Clustered index

The clustered index defines the logical order of a table's data. If no clustered index exists, the table is a **heap** (unordered).

```sql
-- Default: primary key creates a clustered index
CREATE TABLE study.Customer (
    CustomerId int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Customer PRIMARY KEY,  -- creates clustered index
    CustomerName nvarchar(100) NOT NULL
);
```

```sql
-- Create a clustered index on a different column (for order-based access)
CREATE CLUSTERED INDEX IX_SalesOrder_OrderDate
    ON study.SalesOrder (OrderDate);
```

### Nonclustered index

A nonclustered index is a separate structure that stores the index key columns plus a **row locator** (pointer back to the full data row).

```sql
-- Nonclustered index to accelerate lookups by OrderDate
CREATE INDEX IX_SalesOrder_OrderDate
    ON study.SalesOrder (OrderDate);
```

### Inspecting indexes

```sql
-- See all indexes on a table
SELECT i.name                                   AS index_name,
       i.type_desc                              AS index_type,
       i.is_unique,
       i.is_primary_key,
       i.fill_factor
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'Sales.SalesOrderHeader')
ORDER BY i.type;
```

## Seeing the difference: STATISTICS IO

`SET STATISTICS IO ON` shows logical reads — pages read from the data cache. An index that reduces logical reads for a query is beneficial.

```sql
-- Before creating a targeted index
SET STATISTICS IO ON;

SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';
```

Note the `Table 'SalesOrderHeader'. Scan count N, logical reads M [...]` message. Then create an index and run the same query again:

```sql
-- Create a targeted index (idempotent)
DROP INDEX IF EXISTS IX_Lab_OrderDate ON Sales.SalesOrderHeader;
CREATE INDEX IX_Lab_OrderDate ON Sales.SalesOrderHeader (OrderDate);

-- Run the same query again — compare logical reads
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';

SET STATISTICS IO OFF;
```

> [!tip] Interpreting logical reads
> Lower logical reads usually mean less work. The exact reduction depends on data distribution, index selectivity, and the query. In the lab (Lab 09), the difference on AdventureWorks may be modest; the important skill is knowing *how* to measure and compare.

## Covering indexes — concept

An index is said to **cover** a query when all columns referenced in `SELECT`, `WHERE`, and `JOIN` are present in the index. When a query is fully covered, SQL Server can answer it entirely from the index without touching the data row — this eliminates the **key lookup** (also called a bookmark lookup).

```sql
-- Without covering: index on OrderDate, but TotalDue and SubTotal
-- require a key lookup back to the data row.
CREATE INDEX IX_Lab_OrderDate
    ON Sales.SalesOrderHeader (OrderDate);

-- With INCLUDE: the index now "covers" this specific query.
CREATE INDEX IX_Lab_OrderDate_Covering
    ON Sales.SalesOrderHeader (OrderDate)
    INCLUDE (TotalDue, SubTotal, TaxAmt);
```

The `INCLUDE` clause adds non-key columns at the leaf level only — they do not participate in index navigation (seek/scan) but make the index useful for more queries.

> [!warning] Common Mistake
> Adding every column of a table to an index is not a "covering strategy" — it is essentially duplicating the table. Choose `INCLUDE` columns sparingly, based on actual query patterns.

## Index trade-offs

Indexes accelerate reads at the cost of writes. Every index on a table must be maintained during `INSERT`, `UPDATE`, `DELETE`, and `MERGE` operations.

| Workload pattern | Benefit | Trade-off |
| :--- | :--- | :--- |
| Selective `WHERE` predicate | Seek to few rows | Extra write maintenance |
| JOIN on FK column | Faster nested loops join | Storage and maintenance |
| `ORDER BY` on indexed column | Avoid explicit sort | Index order must match sort order |
| Small table (< 1000 pages) | Often little benefit | Index may be unused, still maintained |
| Heavy OLTP writes | Risk of slow DML | Each index adds write cost |

### Fill factor (concept)

Fill factor reserves free space on index pages to reduce page splits during inserts. A fill factor of 80 means 20% free space per page. This is a **maintenance tuning** parameter covered in depth in Section 01.

```sql
-- Creating an index with fill factor (conceptual)
CREATE INDEX IX_Example ON Sales.SalesOrderHeader (OrderDate)
    WITH (FILLFACTOR = 80);
```

## When NOT to index

An index is not always the answer. Consider skipping an index when:

- **Table is small**: fewer than ~1000 pages; a scan is fast enough.
- **Write-heavy workload**: each index adds latency to every DML operation.
- **Low selectivity**: a column where most values are the same (e.g., a flag with 95% `true`) is unlikely to be useful as a leading index key.
- **Query returns most rows**: if a query reads 50%+ of the table, a scan may be more efficient than a seek + key lookup.

```sql
-- Poor index candidate: Gender column with low selectivity
-- CREATE INDEX IX_Employee_Gender ON HumanResources.Employee (Gender);
```

> [!warning] Common Mistake
> Creating an index for every column slows writes and leaves the optimizer with more choices, not better choices. Start from **real query patterns**, not column names.

## Check yourself

### 1. Clustered vs nonclustered

A table has a primary key on `CustomerId` (default clustered). You create a nonclustered index on `Email`. Where does the nonclustered index store its leaf-level row locator?

> [!success]- Answer
> The nonclustered index stores the clustered key (`CustomerId`) as the row locator. To find the full row, SQL Server uses the clustered key to navigate the clustered index. This is called a **key lookup**.

### 2. Logical reads

You run a query with `SET STATISTICS IO ON`. Before creating an index, the query reports 1,200 logical reads. After creating an index, it reports 150 logical reads. Is this a useful index for this query?

> [!success]- Answer
> Yes. A reduction from 1,200 to 150 logical reads means the index helped SQL Server find rows with less I/O. The index is beneficial for this query pattern.

### 3. Covering concept

What is the minimum needed for an index to "cover" a query that selects `OrderDate`, `TotalDue`, and `Status` from `Sales.SalesOrderHeader` where `OrderDate >= '2013-01-01'`?

> [!success]- Answer
> The index key should include `OrderDate` (for seek) and `INCLUDE TotalDue, Status` (to avoid key lookup). Since `Status` may already be in the clustered index, adding it to `INCLUDE` makes the index covering for this query.

### 4. Write cost

Why does adding a nonclustered index slow down inserts on the same table?

> [!success]- Answer
> Every insert must add a row to the table data *and* update every nonclustered index on the table. More indexes = more work per insert. This is the fundamental read/write trade-off of index design.

## Next steps

Index fundamentals are the base for two deeper DP-800 exam topics:

- **Index design and types** (Section 01) — columnstore, filtered indexes, index compression, and maintenance strategies.
- **Query plan analysis** (Section 06) — execution plans, index spools, missing index requests, and index tuning with `sys.dm_db_missing_index_details`.

## Use Cases

- Accelerate a daily sales report that filters by `OrderDate`.
- Speed up JOINs between large tables on foreign key columns.
- Avoid sorting overhead for queries with frequent `ORDER BY` on the same column.
- Enable unique constraint enforcement (unique index).

## Common Issues & Errors

> [!warning] Common Mistake
> An index on every column slows writes and may not help reads. Start with query patterns, not column names.

> [!warning] Common Mistake
> A primary key creates an index, but not necessarily a clustered one. Inspect the table definition rather than assuming.

> [!warning] Common Mistake
> Adding a function around an indexed column in the WHERE clause (e.g., `WHERE YEAR(OrderDate) = 2013`) can prevent index seek (non-SARG). Prefer range predicates: `WHERE OrderDate >= '2013-01-01' AND OrderDate < '2014-01-01'`.

## Best Practices

- Start with the query predicate, join, and sort requirements to identify index candidates.
- Measure with `SET STATISTICS IO ON` and actual execution plans before declaring an index beneficial.
- Use `INCLUDE` for non-key columns to avoid key lookups, but do not blindly include every column.
- Prefer range predicates (`col >= '2026-01-01' AND col < '2026-02-01'`) over function-wrapped columns for better index usage.
- Drop or disable unused indexes periodically; use `sys.dm_db_index_usage_stats` to find them.

## Exam Tips

> [!tip] Exam Tips
> Clustered vs nonclustered describes storage structure, not "fast" vs "slow." A nonclustered index can be faster than a clustered index for covering queries. Know the trade-off: read speed vs write cost. On the exam, you may be asked which index design best supports a given query pattern.

## Key Takeaways

- Indexes trade write/storage cost for potential read efficiency.
- A clustered index determines physical order; a nonclustered index is a separate structure.
- `STATISTICS IO` measures logical reads — the key metric for index benefit.
- Measure before and after; choose indexes from evidence, not habit.
- The covering index pattern eliminates key lookups by including all needed columns.

## Related Topics

- [Database Objects](../01-database-objects/database-objects.md)
- [Performance Optimization](../06-performance-optimization/performance-optimization.md)
- [Performance-monitoring-and-query-store](../08-azure-services-integration/07-performance-monitoring-and-query-store.md)
- [Aggregation and grouping](./06-aggregation-and-grouping.md)

## Official Documentation

- [SQL Server indexes](https://learn.microsoft.com/sql/relational-databases/indexes/indexes)
- [Clustered and nonclustered indexes](https://learn.microsoft.com/sql/relational-databases/indexes/clustered-and-nonclustered-indexes-described)
- [CREATE INDEX](https://learn.microsoft.com/sql/t-sql/statements/create-index-transact-sql)
- [SET STATISTICS IO](https://learn.microsoft.com/sql/t-sql/statements/set-statistics-io-transact-sql)

---

**[← Previous](./09-subqueries-and-ctes.md) | [↑ Back to Section](./fundamentals.md) | [Lab: Review and Cleanup](../../practice/labs/00-fundamentals/10-review-and-cleanup.sql) | [Next →](./11-pivot-unpivot.md)**
