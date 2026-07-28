---
title: JSON Functions
type: study-material
tags:
  - dp-800
  - json
  - json-functions
  - openjson
  - for-json
---

# JSON Functions

## Overview

SQL Server provides a comprehensive set of JSON functions for reading, constructing, modifying, and filtering JSON data. These are heavily tested in DP-800 given the exam's focus on semi-structured data and AI payloads. This chapter covers the operational side of JSON; choose the column type, persistent validation rule, and index strategy in [03-JSON Columns](../01-database-objects/03-json-columns.md).

> [!abstract]
>
> - Deep-dive into all T-SQL JSON functions: extraction, modification, parsing, and serialization
> - JSON functions query and transform JSON documents stored in supported JSON-capable columns
> - Key exam topics: JSON_VALUE vs JSON_QUERY, OPENJSON WITH clause, FOR JSON PATH vs AUTO, lax vs strict

> [!tip] What the Exam Tests
>
> - `JSON_VALUE` = scalar value only; `JSON_QUERY` = object or array fragment; if path points to object, JSON_VALUE returns NULL
> - `OPENJSON` without WITH = generic (key/value/type rows); with WITH = typed columns matching JSON structure
> - `FOR JSON PATH` with dot-notation column aliases (`name AS 'product.name'`) creates nested JSON; `FOR JSON AUTO` infers from table aliases

---

## Reading JSON

### JSON_VALUE — Scalar Extraction

```sql
DECLARE @json nvarchar(max) = N'{
    "customer": {
        "id": 42,
        "name": "Alice",
        "tier": "gold"
    },
    "tags": ["vip", "loyal"],
    "score": 9.5
}';

SELECT
    JSON_VALUE(@json, '$.customer.id')     AS CustomerId,   -- '42'
    JSON_VALUE(@json, '$.customer.name')   AS Name,         -- 'Alice'
    JSON_VALUE(@json, '$.tags[0]')         AS FirstTag,     -- 'vip'
    JSON_VALUE(@json, '$.score')           AS Score;        -- '9.5'
-- Returns NULL if path not found (default: lax mode)
-- Returns error in strict mode: JSON_VALUE(@json, 'strict $.missing')
```

### JSON_QUERY — Object/Array Extraction

```sql
SELECT
    JSON_QUERY(@json, '$.customer')    AS CustomerObject,  -- full JSON object
    JSON_QUERY(@json, '$.tags')        AS TagsArray;       -- full JSON array
-- Returns NULL for scalar values (use JSON_VALUE for those)
```

> [!warning] Common Mistake
> `JSON_VALUE(col, '$.product.specs')` silently returns NULL when `specs` is an object — this is lax mode default behavior. In strict mode, it would throw an error. The exam often presents both behaviors as answer choices: know which is default (lax = NULL, not error).

### OPENJSON — Parse to Rows

`OPENJSON` requires database compatibility level 130 or higher (unless the
relevant database-scoped configuration enables it at lower levels).

```sql
-- Default: key-value pairs
SELECT [key], [value], [type]
FROM OPENJSON(@json, '$.customer');
-- Returns: id/42/2, name/Alice/1, tier/gold/1

-- Typed output with WITH
SELECT id, name, tier
FROM OPENJSON(@json, '$.customer')
WITH (
    id      int             '$.id',
    name    nvarchar(100)   '$.name',
    tier    nvarchar(20)    '$.tier'
);

-- Parse an array
SELECT value AS Tag
FROM OPENJSON(@json, '$.tags');
```

**OPENJSON type values:**

| Value | JSON Type |
| :--- | :--- |
| 0 | null |
| 1 | string |
| 2 | `number` |
| 3 | true/false |
| 4 | array |
| 5 | object |

---

## Building JSON

### JSON_OBJECT

```sql
-- Build a JSON object
SELECT JSON_OBJECT(
    'id'   : CustomerId,
    'name' : Name,
    'email': Email
) AS CustomerJson
FROM dbo.Customers;
```

### JSON_ARRAY

```sql
-- Build a JSON array
SELECT JSON_ARRAY(1, 'two', NULL, GETDATE());
-- [1,"two",null,"2025-06-15T10:00:00"]
```

### JSON_ARRAYAGG

`JSON_ARRAYAGG` is generally available in Azure SQL Database, Azure SQL Managed
Instance under eligible update policies, and Fabric SQL workloads; it is preview
in SQL Server 2025 (17.x).

```sql
-- Aggregate rows into a JSON array grouped by category
SELECT
    CategoryId,
    JSON_ARRAYAGG(Name ORDER BY Name) AS ProductNames
FROM dbo.Products
GROUP BY CategoryId;

-- Aggregate full JSON objects into an array
SELECT
    OrderId,
    JSON_ARRAYAGG(
        JSON_OBJECT('sku': Sku, 'qty': Quantity, 'price': UnitPrice)
        ORDER BY LineNumber
    ) AS LineItemsJson
FROM dbo.OrderLines
GROUP BY OrderId;
```

### JSON_OBJECTAGG

`JSON_OBJECTAGG` has the same current availability as `JSON_ARRAYAGG`: generally
available in the eligible Azure and Fabric services, and preview in SQL Server
2025 (17.x).

```sql
-- Aggregate key-value pairs into a single JSON object
-- Useful for pivoting attribute tables into JSON documents
SELECT
    ProductId,
    JSON_OBJECTAGG(AttributeName: AttributeValue) AS Attributes
FROM dbo.ProductAttributes
GROUP BY ProductId;
-- Example output: {"color":"red","size":"L","weight":"1.2kg"}

-- Combine with JSON_OBJECTAGG for config tables
SELECT JSON_OBJECTAGG(ConfigKey: ConfigValue) AS AppConfig
FROM dbo.AppSettings
WHERE IsActive = 1;
-- Output: {"MaxRetries":"3","Timeout":"30","Environment":"prod"}
```

### FOR JSON PATH

```sql
-- Convert query results to JSON
SELECT
    c.CustomerId,
    c.Name,
    o.OrderId,
    o.TotalAmount
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerId = c.CustomerId
FOR JSON PATH, ROOT('customers');

-- Output:
-- {"customers":[{"CustomerId":1,"Name":"Alice","OrderId":101,"TotalAmount":99.99},...]}
```

### FOR JSON AUTO

```sql
-- Auto-nesting based on table aliases
SELECT c.Name, o.OrderId
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerId = c.CustomerId
FOR JSON AUTO;
-- Nests Orders under Customers automatically
```

---

## Modifying JSON

### JSON_MODIFY

```sql
DECLARE @json nvarchar(max) = N'{"name":"Alice","score":7}';

-- Update existing value
SET @json = JSON_MODIFY(@json, '$.score', 9.5);

-- Add new property
SET @json = JSON_MODIFY(@json, '$.tier', 'gold');

-- In lax mode (the default), NULL deletes an existing property.
SET @json = JSON_MODIFY(@json, '$.tier', NULL);

-- Append to array
SET @json = JSON_MODIFY(@json, 'append $.tags', 'vip');
```

---

## Filtering with JSON

### JSON_CONTAINS (SQL Server 2025 (17.x) Preview)

```sql
-- Check if an array contains a value
SELECT * FROM dbo.Products
WHERE JSON_CONTAINS(Tags, '"sale"') = 1;

-- Check nested path
SELECT * FROM dbo.Events
WHERE JSON_CONTAINS(Payload, '{"status":"active"}', '$.user') = 1;
```

### ISJSON — Validation

```sql
SELECT * FROM dbo.Products
WHERE ISJSON(Attributes) = 1;  -- 1 = valid JSON, 0 = invalid

-- ISJSON with type (SQL 2022+)
WHERE ISJSON(Attributes, OBJECT) = 1   -- must be a JSON object
WHERE ISJSON(Tags, ARRAY) = 1          -- must be a JSON array
```

---

## JSON Path Expressions and Modes

| Expression | Returns |
| :--- | :--- |
| `$.property` | Top-level property |
| `$.a.b` | Nested property |
| `$.array[0]` | First element of array |
| `$.array[*]` | All array elements; preview, native `json` input, and supported JSON functions only |
| `lax $.missing` | `NULL if missing (default)` |
| `strict $.missing` | Error if missing |

Path mode defaults to `lax` in JSON path expressions. Prefix with `strict` to
convert a missing-path result into an error — useful for validation queries.

Array wildcards (`[*]`), ranges, and `last` are SQL Server 2025 (17.x) Preview
features. They require native `json` input and are supported by `JSON_QUERY`,
`JSON_PATH_EXISTS`, and `JSON_CONTAINS`; use `OPENJSON` to expand JSON text
arrays into rows.

### Choose the mode deliberately

Use `lax` when a property is optional and a missing value should simply become
`NULL`. Use `strict` when a query or ingestion step requires a property and a
missing path must stop processing instead of being mistaken for an unknown
value.

```sql
-- Optional attribute: missing discount becomes NULL.
SELECT JSON_VALUE(Payload, '$.discountCode') AS DiscountCode
FROM dbo.Events;

-- Required attribute during ingestion: missing order id raises an error.
SELECT JSON_VALUE(JsonData, 'strict $.orderId') AS OrderId
FROM dbo.EventStaging;
```

`strict` changes error behavior only. It is not a persistent table rule and
does not replace a `CHECK` constraint for documents written to a column.

---

## Nested JSON with CROSS APPLY

Use `CROSS APPLY OPENJSON` to shred nested arrays within JSON documents into
a flat relational result set.

```sql
-- Order JSON with nested line items array
DECLARE @orders NVARCHAR(MAX) = '[
    {"id": 1, "customer": "Alice", "items": [{"sku":"A1","qty":2},{"sku":"B2","qty":1}]},
    {"id": 2, "customer": "Bob",   "items": [{"sku":"C3","qty":5}]}
]';

-- Shred orders, then shred each items array
SELECT o.id, o.customer, li.sku, li.qty
FROM OPENJSON(@orders)
WITH (
    id       INT             '$.id',
    customer NVARCHAR(100)   '$.customer',
    items    NVARCHAR(MAX)   '$.items' AS JSON
) o
CROSS APPLY OPENJSON(o.items)
WITH (sku NVARCHAR(20) '$.sku', qty INT '$.qty') li;
```

The `AS JSON` flag in the `WITH` clause tells OPENJSON to return the nested
array as a raw JSON fragment rather than a string, enabling the second
`CROSS APPLY OPENJSON` call on it.

---

## JSON Access and Execution Plans

JSON functions are ordinary expressions from the optimizer's perspective. The
function chosen and where it appears in the query influence how many documents
SQL Server has to inspect, how many rows are produced, and whether an existing
access path can be used. Always inspect the **actual execution plan** and the
runtime measurements for the data volume in question; an operator is a result
of the whole query, statistics, and available indexes—not a guarantee of a
particular JSON function.

| Access form | Typical plan consequence | Practical implication |
| :--- | :--- | :--- |
| `JSON_VALUE(Document, '$.status')` in `WHERE` without a matching access path | SQL Server can need to scan candidate rows and evaluate the function for each | Cost grows with the candidate set; filter with a selective relational predicate first when available |
| Same `JSON_VALUE` expression with a matching indexed computed column | The optimizer can use the computed-column index; the plan can show an Index Seek and, when needed columns are absent, a Key Lookup | Keep the expression, path, and data type compatible with the computed-column definition; include projected columns only after measuring |
| `JSON_QUERY` in the select list | Extracts a fragment for rows that reach that part of the plan; it does not create a scalar search key by itself | Use it to return objects/arrays, not as the primary access path for selective filtering |
| `OPENJSON` / `CROSS APPLY OPENJSON` | Turns an object or array into one or more relational rows; each expanded array can multiply rows before joins, aggregates, and sorts | Restrict the outer rows and the JSON path before shredding; project only the fields required with `WITH` |
| `FOR JSON` | Formats the final relational result as JSON | Apply filters, joins, ordering, and pagination to the relational result before serialization |

### Matching a computed-column access path

The indexed computed column is defined in the storage chapter, but the query
does not have to name that column. When the `JSON_VALUE` expression in the
query is equivalent to its definition, SQL Server can recognize the match and
use the index if it is beneficial.

```sql
-- The table has a computed column defined as:
-- ShipCountry AS JSON_VALUE(ShippingJSON, '$.country')
-- and an index on ShipCountry.

SELECT OrderID, TotalAmount
FROM dbo.Orders
WHERE JSON_VALUE(ShippingJSON, '$.country') = N'US';
```

An actual plan can use an **Index Seek** on the computed-column index, followed
by a **Key Lookup** when `OrderID` and `TotalAmount` are not available in that
index. If those columns are frequently returned by this query, test an index
that includes them; do not add included columns solely to force a plan shape.
Changing the JSON path, wrapping the expression in a different conversion, or
using a different collation can prevent the expression from matching the index.

### Shredding: row expansion is the key cost

`OPENJSON` is the right tool when the consumer needs relational rows, but it is
not a filter index. In a `CROSS APPLY`, every qualifying outer row can yield
zero, one, or many inner rows. For example, 1,000 orders with 20 items each
can become roughly 20,000 rows before a later `JOIN`, `GROUP BY`, or `ORDER BY`.
That larger intermediate result can increase CPU, memory grants, sorts, and
join work.

```sql
-- Prefer restricting orders before expanding their item arrays.
SELECT o.OrderID, item.Sku, item.Qty
FROM dbo.Orders AS o
CROSS APPLY OPENJSON(o.OrderJson, '$.items')
WITH (
    Sku nvarchar(20) '$.sku',
    Qty int          '$.qty'
) AS item
WHERE o.OrderDate >= '2026-01-01'
  AND JSON_VALUE(o.OrderJson, '$.status') = N'Closed';
```

The optimizer is free to choose the physical order of operations, so the text
order of predicates is not a guarantee. The durable improvement is an access
path for the selective relational or JSON predicate, plus a narrow `OPENJSON`
projection. Use the actual plan to compare estimated and actual rows around
the `APPLY`, then address the predicate or data model rather than assuming a
JSON-specific operator is always the bottleneck.

### A small measurement routine

```sql
SET STATISTICS IO, TIME ON;
-- Execute the candidate query with the actual execution plan enabled in SSMS
-- or Azure Data Studio, then compare logical reads, CPU, elapsed time,
-- estimated versus actual rows, seeks/scans, lookups, and sort spills.
SET STATISTICS IO, TIME OFF;
```

For the computed-column definition and index choices, see
[03-JSON Columns](../01-database-objects/03-json-columns.md). Microsoft Learn
documents that a query using the same `JSON_VALUE` expression can use an
equivalent computed-column index when possible.

---

## Validation While Querying or Loading

`ISJSON` lets a query distinguish malformed input from valid documents. Use it
at a staging boundary before parsing a batch. First identify rejected rows with
`lax` paths; after they are removed or corrected, use `strict` paths in the
load query so an unexpected missing property stops the load.

### ETL validation — detect invalid or incomplete rows

```sql
-- Validate required JSON properties during bulk load
SELECT src.RowID, src.JsonData
FROM StagingTable src
WHERE ISJSON(src.JsonData) = 0                               -- invalid JSON
   OR JSON_VALUE(src.JsonData, '$.id')   IS NULL             -- missing required field
   OR JSON_VALUE(src.JsonData, '$.name') IS NULL;

-- Count valid vs invalid JSON rows
SELECT
    SUM(CASE WHEN ISJSON(JsonData) = 1 THEN 1 ELSE 0 END) AS ValidCount,
    SUM(CASE WHEN ISJSON(JsonData) = 0 THEN 1 ELSE 0 END) AS InvalidCount
FROM StagingTable;

-- After the rejected rows are handled, require the property in the load.
SELECT JSON_VALUE(JsonData, 'strict $.id') AS Id
FROM StagingTable
WHERE ISJSON(JsonData) = 1;
```

For `CHECK (ISJSON(...))`, required-document rules, and type choices at write
time, return to [03-JSON Columns](../01-database-objects/03-json-columns.md).

---

## Practical Patterns

```sql
-- Expand JSON array column into rows
SELECT p.ProductId, t.Tag
FROM dbo.Products p
CROSS APPLY OPENJSON(p.Tags) WITH (Tag nvarchar(50) '$') AS t;

-- Build AI prompt payload as JSON
SELECT JSON_OBJECT(
    'model'     : 'gpt-4o',
    'messages'  : JSON_QUERY(JSON_ARRAY(
        JSON_OBJECT('role': 'system', 'content': 'You are a helpful assistant.'),
        JSON_OBJECT('role': 'user',   'content': @UserQuestion)
    ))
) AS RequestPayload;
```

---

## Use Cases

- **Storing flexible attributes**: Product metadata, event payloads, configuration
- **API response storage**: Cache raw API responses and query them with JSON functions
- **RAG pipelines**: Convert query results to JSON for LLM prompts using `FOR JSON`
- **Data exchange**: Import/export data in JSON format for microservices

---

## Common Issues & Errors

| Issue | Cause | Resolution |
| :--- | :--- | :--- |
| `JSON_VALUE` returns NULL | Path not found (lax mode) | Verify the path; use `strict` to get an error instead |
| `JSON_QUERY` returns NULL on scalar | Scalar values need `JSON_VALUE` | Use `JSON_VALUE` for strings/numbers, `JSON_QUERY` for objects/arrays |
| `FOR JSON` produces unexpected nesting | Column naming causes auto-nesting | Use explicit aliases or `FOR JSON PATH` with dot notation |
| `CROSS APPLY OPENJSON` returns no rows | Nested column not declared `AS JSON` | Add `AS JSON` flag to the nested array column in the outer `WITH` clause |
| `JSON_OBJECTAGG` / `JSON_ARRAYAGG` not found | Feature is not available on the current SQL Server/Azure platform | Check the current platform availability; use `FOR JSON` when the aggregate functions are unavailable |

---

## Best Practices

- Keep table storage, persistent `ISJSON` constraints, and JSON access-path design in [03-JSON Columns](../01-database-objects/03-json-columns.md).
- Prefer `OPENJSON` with a typed `WITH` clause over repeated `JSON_VALUE` calls — it parses the document once and produces strongly-typed columns in a single pass.
- Use `strict` path mode in validation and ETL queries so missing required fields surface as errors rather than silent NULLs.
- Use the JSON extraction functions here to shape a query; follow the computed-column and index guidance in the JSON-columns chapter when that extraction becomes a recurring access path.
- Treat `OPENJSON` as a row-expanding relational operator: filter the outer input, project a narrow `WITH` schema, and verify row counts in the actual plan.
- Use `JSON_OBJECTAGG` / `JSON_ARRAYAGG` where the target platform supports them; they compose cleanly inside larger `SELECT` statements without subqueries.

---

## Exam Tips

> [!tip] Exam Tips
>
> - `JSON_VALUE` = scalar → string; `JSON_QUERY` = objects/arrays → JSON fragment
> - `OPENJSON` with `WITH` clause provides strongly-typed output — preferred for structured parsing
> - `FOR JSON PATH` gives explicit control; `FOR JSON AUTO` infers nesting from aliases
> - `JSON_ARRAYAGG` and `JSON_OBJECTAGG` are preview in SQL Server 2025 (17.x), but generally available in eligible Azure SQL and Fabric services
> - Default path mode is `lax` (returns NULL on missing path); `strict` raises an error — critical for exam scenario questions about error behavior

---

## Practice Questions

**Practice Question**

A query uses `JSON_VALUE(col, '$.address.city')` but some rows have no `address` property. What is returned for those rows by default?

A. An empty string ''

B. NULL

C. An error is raised

D. The string 'null'

> [!success]- Answer
> **B — NULL**
>
> JSON_VALUE uses lax mode by default. In lax mode, if the path doesn't exist or the value is JSON null, it returns SQL NULL — no error is raised. To raise an error for missing paths, use `JSON_VALUE(col, 'strict $.address.city')`. Note: JSON `null` (lowercase) maps to SQL NULL in JSON_VALUE.

---

## Key Takeaways

- Two read functions: `JSON_VALUE` (scalar) and `JSON_QUERY` (object/array)
- `OPENJSON` is the most versatile — converts JSON to relational rows
- `FOR JSON` converts relational results to JSON — essential for RAG prompt building
- `JSON_OBJECTAGG` / `JSON_ARRAYAGG` aggregate rows directly into JSON where the target platform supports them
- `CROSS APPLY OPENJSON` with `AS JSON` is the pattern for shredding nested arrays
- Access method affects the plan: matching computed-column indexes can avoid broad scans, while `OPENJSON` can multiply rows

---

## Related Topics

- [03-JSON Columns](../01-database-objects/03-json-columns.md)
- [02-RAG Prompts and Responses](../11-rag/02-prompts-and-responses.md)

---

## Official Documentation

## Mock-detail syntax: output wrappers

`FOR JSON PATH` is the predictable contract for API output. `ROOT` adds a named
outer object and `WITHOUT_ARRAY_WRAPPER` removes the default outer array for one
object. `WITH ARRAY_WRAPPER` belongs to `JSON_QUERY` with JSON path expressions
that can match multiple values; it is not a `FOR JSON` output option. Do not
confuse the output-clause options with JSON path syntax; test the exact
SQL Server/Azure SQL version before using preview features.

- [JSON Functions (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/json-functions-transact-sql)
- [OPENJSON (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql)
- [FOR JSON (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/json/format-query-results-as-json-with-for-json-sql-server)
- [JSON path expressions](https://learn.microsoft.com/en-us/sql/relational-databases/json/json-path-expressions-sql-server)
- [JSON aggregate functions](https://learn.microsoft.com/en-us/sql/t-sql/functions/json-arrayagg-transact-sql)
- [JSON_CONTAINS (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/json-contains-transact-sql)
- [Index JSON data](https://learn.microsoft.com/en-us/sql/relational-databases/json/index-json-data)

---

**[← Previous](./01-ctes-window-functions.md) | [↑ Back to Section](./advanced-tsql.md) | [Lab: JSON Functions](../../practice/labs/03-advanced-tsql/02-json-functions-lab.sql) | [Next →](./03-regex-fuzzy-matching.md)**
