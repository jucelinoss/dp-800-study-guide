---
title: JSON Columns and Indexes
type: study-material
tags:
  - dp-800
  - json
  - json-columns
  - indexes
---

# JSON Columns and Indexes

## Overview

SQL Server can store JSON text in `varchar` or `nvarchar` columns. Azure SQL Database and Azure SQL Managed Instance also make the native `json` type generally available under the SQL Server 2025 or Always-up-to-date update policy; in SQL Server 2025 (17.x), that type remains preview. This chapter focuses on choosing the storage model, enforcing valid documents, and indexing JSON-backed attributes efficiently.

> [!abstract]
>
> - Choose between relational columns, `nvarchar` JSON documents, and the native `json` type.
> - Enforce valid JSON at the database boundary and decide which JSON attributes require relational access paths.
> - Index frequently queried JSON properties with computed columns; use the JSON-functions chapter to read and transform documents.

> [!tip] What the Exam Tests
>
> - A JSON document is not a replacement for relational columns that need keys, constraints, joins, and frequent filtering.
> - `ISJSON` and `CHECK` constraints protect document validity; they do not prove every business property is present.
> - Computed-column indexes make a frequently filtered JSON attribute accessible to ordinary B-tree indexing.

---

## Storing JSON Data

```sql
-- Traditional approach: store JSON in nvarchar column
CREATE TABLE dbo.Products (
    ProductId   int             NOT NULL PRIMARY KEY,
    Name        nvarchar(200)   NOT NULL,
    Attributes  nvarchar(max)   NULL  -- JSON stored here
    CHECK (ISJSON(Attributes) = 1)    -- Validate on insert/update
);

-- Native json type: generally available in eligible Azure SQL services;
-- preview in SQL Server 2025 (17.x).
CREATE TABLE dbo.Events (
    EventId     int     NOT NULL PRIMARY KEY CLUSTERED,
    Payload     json    NULL
);
```

## Accessing stored documents

The storage decision and the query decision are separate. Store a flexible attribute set in `Attributes`, then use the appropriate T-SQL JSON function to extract, shred, filter, build, or modify its contents. Those functions, JSON paths, `OPENJSON`, path modes, and `FOR JSON` belong to [JSON Functions](../03-advanced-tsql/02-json-functions.md).

For this chapter, the important connection is that an access pattern determines the index design. If a query repeatedly filters by `$.color`, expose that scalar property as a computed column and index it rather than expecting SQL Server to efficiently search an unindexed document expression.

---

## JSON Indexes

To efficiently filter or sort on JSON properties, create a computed column and index it:

```sql
-- Create a computed column for the JSON property
ALTER TABLE dbo.Products
ADD Color AS JSON_VALUE(Attributes, '$.color');

-- Index the computed column
CREATE INDEX IX_Products_Color ON dbo.Products (Color);

-- Query now uses the index
SELECT * FROM dbo.Products WHERE Color = 'blue';
```

The standard computed-column approach works with JSON text and the native
`json` type. SQL Server 2025 (17.x) Preview also introduces `CREATE JSON
INDEX` for a native `json` column. A JSON index requires a clustered primary
key and is currently preview-only in SQL Server:

```sql
CREATE JSON INDEX IX_Events_Payload
ON dbo.Events (Payload)
FOR ('$.userId');
```

---

## JSON Computed Columns for Indexing

**Problem:** On a table without a suitable standard index or JSON index, filtering with `JSON_VALUE` can require scanning the table.

> [!note] Table Scan vs Clustered Index Scan Equivalency
> Filtering on a `JSON_VALUE(...)` expression without a suitable index can force the engine to inspect every row and evaluate the expression.
>
> - **Heap table (no PK)**: Produces a **Table Scan** operator.
> - **Clustered Index table (with PK)**: Produces a **Clustered Index Scan** operator.
>
> Functionally and performance-wise, **Table Scan** and **Clustered Index Scan** are equivalent in this context: both require a 100% full physical scan of every data page in the table. DBA terminology often uses "Table Scan" generically for any expensive 100% full table scan in contrast to a targeted **Index Seek**.

**Solution:** Extract the JSON property into a computed column, then create an
index on that column when it meets SQL Server's computed-column indexability
requirements. A `PERSISTED` column physically stores the expression result and
can be chosen when that storage/write trade-off is appropriate; it is not a
universal prerequisite for indexing.

```sql
-- Add a computed column extracting from JSON
ALTER TABLE Orders
ADD ShipCountry AS JSON_VALUE(ShippingJSON, '$.country') PERSISTED;

-- Index the computed column
CREATE INDEX IX_Orders_ShipCountry ON Orders(ShipCountry);

-- Query now uses the index (optimizer treats JSON_VALUE(...) as the computed column)
SELECT OrderID, TotalAmount
FROM Orders
WHERE JSON_VALUE(ShippingJSON, '$.country') = 'US';

-- Filtered index on computed column for sparse values
CREATE INDEX IX_Orders_UK_Country
ON Orders(ShipCountry, TotalAmount)
WHERE ShipCountry = 'UK';
```

---

## Use Cases

- **Product catalogs**: Variable attribute sets per product type stored as JSON
- **Event sourcing**: Event payloads with flexible schemas
- **API integration**: Store and query REST API responses directly in SQL
- **Configuration tables**: Application settings as structured JSON

---

## Common Issues & Errors

| Issue | Cause | Resolution |
| :--- | :--- | :--- |
| Slow JSON queries | No index on a frequently queried JSON property | Create a computed column + index on the property |
| `ISJSON` returns 0 | Malformed JSON in the column | Add CHECK constraint on insert; validate at application layer |
| JSON query returns an unexpected result | Wrong path, mode, or function for the expected shape | Review path modes and `JSON_VALUE` versus `JSON_QUERY` in [02-JSON Functions](../03-advanced-tsql/02-json-functions.md) |

---

## Best Practices

- Add `CHECK (ISJSON(col) = 1)` to `nvarchar` columns that must contain valid JSON.
- Keep frequently filtered, joined, constrained, or security-sensitive attributes in relational columns when possible.
- Use a computed column and an index when one JSON scalar is repeatedly searched.
- Shred JSON into relational columns at ingestion when the values need durable relational access; keep JSON for flexible or rarely queried attributes.
- Use the functions chapter to choose extraction, path-mode, and serialization behavior.

---

## Exam Tips

> [!tip] Exam Tips
>
> - Choose JSON storage only for flexible or document-shaped attributes; keep strongly relational facts relational.
> - `ISJSON` validates document syntax, while additional rules are needed for required business properties.
> - To filter efficiently on a JSON scalar, expose it through a computed column and index it.
> - Function behavior (`JSON_VALUE`, `OPENJSON`, strict/lax paths, and JSON output) is tested in [JSON Functions](../03-advanced-tsql/02-json-functions.md).

---

## Key Takeaways

- JSON text can be stored in `varchar` or `nvarchar`; the native `json` type has platform-specific availability.
- Valid JSON syntax is a storage-integrity concern; JSON functions are a query concern.
- Computed-column indexes provide an ordinary relational access path to a frequently queried JSON scalar.
- Function, path, parsing, and serialization patterns live in [JSON Functions](../03-advanced-tsql/02-json-functions.md).

---

## Practice Question

A table has a JSON column `Metadata` and a query filters on `JSON_VALUE(Metadata, '$.region') = 'EU'`. The query is slow with a full table scan. What is the BEST solution?

A. Use FOR JSON PATH to reformat the data

B. Add a computed column on `JSON_VALUE(Metadata, '$.region')` and index it

C. Switch to OPENJSON for better performance

D. Enable JSON path strict mode

> [!success]- Answer
> **B — Add a computed column on `JSON_VALUE(Metadata, '$.region')` and index it**
>
> The optimizer cannot use an ordinary B-tree index on an unexposed JSON path expression. A computed column exposes the extracted value, and an index on that column can support the predicate when the expression and query are compatible. OPENJSON (C) is for shredding arrays and doesn't help filter performance. Strict mode (D) changes error behavior, not query speed.

---

## Related Topics

- [02-JSON Functions in Advanced T-SQL](../03-advanced-tsql/02-json-functions.md)
- [01-Tables & Indexes](./01-tables-indexes.md)

---

## Official Documentation

- [JSON Data in SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server)
- [JSON indexes](https://learn.microsoft.com/en-us/sql/relational-databases/json/index-json-data)
- [CREATE JSON INDEX (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-json-index-transact-sql)

---

**[← Previous](./02-specialized-tables.md) | [↑ Back to Section](./database-objects.md) | [Lab: JSON Columns and Indexes](../../practice/labs/01-database-objects/03-json-columns-lab.sql) | [Next →](./04-constraints-sequences.md)**
