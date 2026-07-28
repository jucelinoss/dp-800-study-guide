---
title: Views
type: study-material
tags:
  - dp-800
  - views
  - indexed-views
  - schema-binding
---

# Views

## Overview

Views are stored SELECT statements that act as virtual tables. SQL Server supports standard views, schema-bound views, and indexed (materialized) views — each with different performance and maintenance characteristics.

> [!note] Platform scope
> The indexed-view guidance in this chapter applies to SQL Server, Azure SQL Database, Azure SQL Managed Instance, and SQL database in Microsoft Fabric. Azure Synapse Analytics does not support `SCHEMABINDING`, updatable views, or DML triggers on views.

> [!abstract]
>
> - Covers standard views, indexed views, and updatable views
> - Views are virtual tables; indexed views materialize results with a unique clustered index
> - Key exam topics: indexed view requirements (SCHEMABINDING + UNIQUE CLUSTERED INDEX), updatable view rules, WITH CHECK OPTION

> [!tip] What the Exam Tests
>
> - Indexed views require `WITH SCHEMABINDING` on the view AND a `UNIQUE CLUSTERED INDEX` on it — both are mandatory
> - `WITH CHECK OPTION` ensures INSERT/UPDATE through a view stays within the view's WHERE clause filter
> - Non-deterministic functions (GETDATE, NEWID) are forbidden in indexed views

---

## Creating Views

```sql
-- Standard view
CREATE VIEW dbo.vw_ActiveCustomers AS
SELECT CustomerId, Name, Email, CreatedAt
FROM dbo.Customers
WHERE IsActive = 1;

-- View with multiple tables
CREATE VIEW dbo.vw_OrderSummary AS
SELECT
    o.OrderId,
    c.Name       AS CustomerName,
    o.OrderDate,
    SUM(oi.Quantity * oi.UnitPrice) AS TotalAmount
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
JOIN dbo.OrderItems oi ON oi.OrderId = o.OrderId
GROUP BY o.OrderId, c.Name, o.OrderDate;
```

---

## Schema Binding

`WITH SCHEMABINDING` binds the view to its underlying tables, preventing schema changes that would break the view. It is required for indexed views.

> [!note]
> `SCHEMABINDING` is not supported by Azure Synapse Analytics.

```sql
CREATE VIEW dbo.vw_ProductPricing
WITH SCHEMABINDING AS
SELECT
    p.ProductId,
    p.Name,
    p.Price,
    c.CategoryName
FROM dbo.Products p
JOIN dbo.Categories c ON c.CategoryId = p.CategoryId;
```

With `SCHEMABINDING`:

- Cannot DROP or ALTER underlying tables/columns referenced by the view while binding is active
- Must use two-part names (`dbo.TableName`) — `SELECT *` is not allowed
- Blocks `DROP TABLE` and column modifications on referenced objects
- Two-part naming (`dbo.TableName`) is required; unqualified names are rejected

> [!warning] Common Mistake
> You cannot create an indexed view without first creating the view WITH SCHEMABINDING. SCHEMABINDING prevents the underlying tables from being modified in ways that would break the view — it must come first.

---

## Indexed Views (Materialized Views)

An **indexed view** has a unique clustered index created on it, which physically stores the result set on disk. This makes it functionally equivalent to a materialized view in other database systems.

```sql
-- Create indexed view
CREATE VIEW dbo.vw_OrderSummary
WITH SCHEMABINDING
AS
SELECT CustomerID,
       COUNT_BIG(*) AS OrderCount,
       SUM(ISNULL(TotalAmount, 0)) AS TotalSpent
FROM dbo.Orders
GROUP BY CustomerID;
GO

-- Materialize the view
CREATE UNIQUE CLUSTERED INDEX IX_vw_OrderSummary
ON dbo.vw_OrderSummary(CustomerID);
```

**Requirements for indexed views:**

- `WITH SCHEMABINDING` is mandatory
- First index must be `UNIQUE CLUSTERED`
- Required session options (6 ON, 1 OFF): `ANSI_NULLS`, `ANSI_PADDING`, `ANSI_WARNINGS`, `ARITHABORT`, `CONCAT_NULL_YIELDS_NULL`, `QUOTED_IDENTIFIER` set to `ON`, and `NUMERIC_ROUNDABORT` set to `OFF`
- Deterministic expressions only; `GETDATE()`, `NEWID()`, and `RAND()` are not allowed
- Base tables must be in the same database and have the same owner as the view
- No `OUTER JOIN`, `APPLY`, self-joins, `HAVING`, subqueries, CTEs, `DISTINCT`, `TOP`, or set operators such as `UNION ALL`
- `AVG`, `MIN`, `MAX`, and several other aggregates are not allowed; a nullable input to `SUM` must be made non-nullable with `ISNULL`
- `COUNT_BIG(*)` required when using `GROUP BY` — `COUNT(*)` is not allowed

### Required SET Options Breakdown (6 ONs, 1 OFF)

The fixed values ensure that indexed views can be maintained and produce consistent results. They are required when the base tables and view are created, when the view index is created, when DML changes a participating table, and when the optimizer uses the view index.

| SET option | Required value | Default server value | Default OLE DB / ODBC value | Default DB-Library value |
| :--- | :---: | :---: | :---: | :---: |
| `ANSI_NULLS` | `ON` | `ON` | `ON` | `OFF` |
| `ANSI_PADDING` | `ON` | `ON` | `ON` | `OFF` |
| `ANSI_WARNINGS` | `ON` | `ON` | `ON` | `OFF` |
| `ARITHABORT` | `ON` | `OFF` | `OFF` | `OFF` |
| `CONCAT_NULL_YIELDS_NULL` | `ON` | `ON` | `ON` | `OFF` |
| `QUOTED_IDENTIFIER` | `ON` | `ON` | `ON` | `OFF` |
| `NUMERIC_ROUNDABORT` | `OFF` | `OFF` | `OFF` | `OFF` |

> [!tip] Connection defaults
> For OLE DB or ODBC connections, Microsoft Learn states that `ARITHABORT` is the only setting that must be changed. Do not assume this is true for every driver, tool, or application configuration. Setting `ANSI_WARNINGS` to `ON` also implicitly sets `ARITHABORT` to `ON`.

> [!warning] When SET Options Are Required
> All 7 options must be configured correctly:
> 1. When creating the view (`CREATE VIEW`) and index (`CREATE UNIQUE CLUSTERED INDEX`).
> 2. Whenever DML (`INSERT`, `UPDATE`, `DELETE`) modifies data in any referenced base table.
> 3. When the query optimizer considers using the indexed view.

**Query optimizer behavior:**

- SQL Server Enterprise can consider an indexed view automatically, even when the view is not referenced directly.
- SQL Server Standard requires `WITH (NOEXPAND)` when querying the indexed view directly.
- Azure SQL Database and Azure SQL Managed Instance can use indexed views automatically without `NOEXPAND`.

```sql
SELECT ProductId, TotalRevenue
FROM dbo.vw_SalesByProduct WITH (NOEXPAND)
WHERE ProductId = 42;
```

---

## Updatable Views

Views can support DML when the engine can trace the modification unambiguously to one base table. A view with joins can therefore support an `UPDATE` of columns from one underlying table; a multi-table view cannot be used for `INSERT` or `DELETE`.

```sql
CREATE VIEW dbo.vw_ActiveCustomers
AS
SELECT CustomerID, Name, Email
FROM dbo.Customers
WHERE IsActive = 1
WITH CHECK OPTION; -- Prevents inserting inactive customers via view
```

**Rules for DML through a view:**

- Each DML statement must modify columns from only one base table
- No aggregate functions (`SUM`, `COUNT`, `AVG`, etc.)
- No computed target columns, `DISTINCT`, `GROUP BY`, or `HAVING`
- Columns being modified must map directly to base table columns
- `TOP` cannot be combined with `WITH CHECK OPTION` in the view definition

**WITH CHECK OPTION** ensures that any row inserted or updated through the view still satisfies the view's WHERE clause. Without it, you could insert a row that immediately disappears from the view.

**INSTEAD OF triggers** can make otherwise non-updatable views (multi-table joins, aggregations) accept DML by intercepting the operation and executing custom logic:

```sql
-- UPDATE through a simple updatable view
UPDATE dbo.vw_ActiveProducts SET Price = 19.99 WHERE ProductId = 5;
```

Use `INSTEAD OF` triggers on views for complex update logic involving multiple base tables.

---

## View Limitations

| Limitation | Detail |
|---|---|
| ORDER BY | Do not use it to define result order. With `TOP` in a view definition it chooses rows for `TOP`; callers still need their own `ORDER BY`. |
| Subqueries in FROM | Allowed in regular views; indexed views cannot use them |
| CTEs | Regular views can use CTEs; indexed views cannot |
| DISTINCT | Allowed in regular views; not in indexed views |
| Outer joins | Allowed in regular views; not in indexed views |
| System tables | Can be referenced; schema changes may silently break the view |

---

## Use Cases

- **Security**: Expose only certain columns/rows to users without table access
- **Simplification**: Encapsulate complex joins for reuse across queries
- **Indexed views**: Pre-compute aggregations for reporting dashboards
- **Updatable abstraction**: Expose a filtered subset of a table while enforcing constraints via `WITH CHECK OPTION`

---

## Common Issues & Errors

| Issue | Cause | Resolution |
| :--- | :--- | :--- |
| Cannot drop table | View uses `SCHEMABINDING` | Drop the view first, or use `ALTER VIEW` to remove schemabinding |
| Indexed view not used | SQL Server Standard query omitted `NOEXPAND`, or required SET options are incorrect | Add `WITH (NOEXPAND)` when querying directly on SQL Server Standard; check SET options |
| View metadata is stale | A non-schema-bound base object changed | Run `sp_refreshview` where applicable; indexed views are maintained when base-table DML runs |
| Index creation fails | Non-deterministic function in view | Replace `GETDATE()`, `NEWID()`, etc. with deterministic alternatives |
| DML through view fails | View spans multiple tables or has aggregation | Use `INSTEAD OF` trigger or target base table directly |

---

## Best Practices

- Always use `WITH SCHEMABINDING` for views that will be indexed or used in critical production queries to prevent accidental schema drift.
- Use `WITH CHECK OPTION` on filtered views to enforce data integrity when allowing DML through the view.
- Prefix view names with `vw_` or `v_` to distinguish them from base tables in queries and object browsers.
- Avoid `SELECT *` in view definitions — explicitly list columns so that adding columns to the base table does not silently change the view's output.
- On SQL Server Standard, use `WITH (NOEXPAND)` when you query an indexed view directly; validate the actual plan and SET options on every target platform.

---

## Exam Tips

> [!tip] Exam Tips
>
> - Indexed views require `WITH SCHEMABINDING` and a `UNIQUE CLUSTERED` index as the first index
> - `COUNT_BIG(*)` is required in grouped indexed views — `COUNT(*)` is not allowed
> - On SQL Server Standard, use `WITH (NOEXPAND)` when querying an indexed view directly; Azure SQL Database and Azure SQL Managed Instance can use it automatically
> - Non-deterministic functions (`GETDATE()`, `NEWID()`, `RAND()`) block index creation on a view
> - `WITH CHECK OPTION` prevents DML that would cause rows to fall outside the view's filter — without it, "disappearing rows" can occur after insert/update

---

## Key Takeaways

- Views are virtual — no data stored (unless indexed)
- `SCHEMABINDING` prevents accidental schema changes and enables indexing
- Indexed views materialize query results and can dramatically speed up aggregation queries
- `WITH CHECK OPTION` enforces that DML through a view keeps rows visible through the same view

---

## Practice Questions

**Practice Question**

A developer creates a view with `WITH SCHEMABINDING` and tries to add a unique clustered index on it, but receives an error. Which condition is MOST likely causing the failure?

A. The view references a column with a non-deterministic function like GETDATE()

B. The view uses an INNER JOIN between two tables

C. The view's SELECT list includes the primary key column

D. The underlying table has a columnstore index

> [!success]- Answer
> **A — The view references a column with a non-deterministic function like GETDATE()**
>
> Indexed views require all functions to be deterministic (same output for same input). GETDATE(), NEWID(), RAND() are non-deterministic and prevent index creation. INNER JOINs (B) are allowed in indexed views. Including the PK (C) is fine. Columnstore indexes (D) on the base table do not affect view indexability.

---

## Related Topics

- [02-Functions](./02-functions.md)
- [03-Stored Procedures](./03-stored-procedures.md)
- [Views Lab](../../practice/labs/02-programmability-objects/01-views-lab.sql)

---

## Official Documentation

- [Views (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/views/views)
- [Create Indexed Views](https://learn.microsoft.com/en-us/sql/relational-databases/views/create-indexed-views)

---

**[↑ Back to Section](./programmability-objects.md) | [Lab: Views](../../practice/labs/02-programmability-objects/01-views-lab.sql) | [Next →](./02-functions.md)**
