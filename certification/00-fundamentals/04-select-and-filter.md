---
title: SELECT, Filters, Subqueries, and Set Operations
type: topic
tags: [sql-server, select, where, subquery, set-operations, fundamentals]
---

# SELECT, Filters, Subqueries, and Set Operations

## Overview

`SELECT` is T-SQL's language for asking questions of data. A query can shape columns, filter rows, compare one result to another, and combine compatible results without changing stored data.

> [!abstract]
>
> - Master the query shape: projection, source, predicates, grouping, and ordering.
> - Use scalar, multi-row, correlated, and derived-table subqueries appropriately.
> - Use `EXISTS`, `IN`, `UNION`, `INTERSECT`, and `EXCEPT` to express set-based questions.

> [!tip] Scope boundary
> CTEs, temporary tables, and table variables are intermediate-result structures. They belong in [Lesson 09](./09-subqueries-and-ctes.md), where their lifetime and scope can be taught without duplicating query syntax.

---

## A query is a question over sets

Tables represent sets of rows; a query describes the result set wanted from them. SQL Server decides how to execute that description.

```sql
SELECT p.ProductName,
       p.UnitPrice,
       p.UnitPrice * 1.10 AS price_with_tax
FROM study.Product AS p
WHERE p.IsDiscontinued = 0
ORDER BY price_with_tax DESC, p.ProductName ASC;
```

`price_with_tax` is calculated in the result; it does not update `UnitPrice`. The simplified logical processing order explains many query rules:

```text
FROM / JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → TOP/OFFSET
```

| Clause | Purpose | Example |
| :--- | :--- | :--- |
| `FROM` | Choose source rows | `FROM study.Product AS p` |
| `WHERE` | Filter individual rows | `WHERE UnitPrice >= 10` |
| `GROUP BY` | Define summary grain | one result per customer |
| `HAVING` | Filter completed groups | total spend >= 100 |
| `SELECT` | Shape output columns | name, price, calculation |
| `ORDER BY` | Sort final result | highest price first |

## Projection, aliases, and filters

Select only columns that the result needs. `SELECT *` is fine for one-off exploration, but a durable query should not silently change when a table gains a column or expose fields the caller does not need.

```sql
SELECT CustomerId, CustomerName, Email
FROM study.Customer;
```

Use aliases for readable output and unambiguous multi-table queries. `DISTINCT` removes duplicate complete result rows; it is not a repair for an incorrect JOIN.

```sql
SELECT DISTINCT CustomerId
FROM study.SalesOrder;
```

`WHERE` keeps only rows whose condition is true:

| Pattern | Example |
| :--- | :--- |
| comparison | `UnitPrice >= 20` |
| membership | `CustomerId IN (1, 3, 5)` |
| inclusive range | `UnitPrice BETWEEN 10 AND 20` |
| text pattern | `ProductName LIKE N'A%'` |
| missing value | `Email IS NULL` |

```sql
SELECT ProductName, UnitPrice
FROM study.Product
WHERE IsDiscontinued = 0
  AND UnitPrice BETWEEN 5.00 AND 50.00
  AND ProductName NOT LIKE N'%used%'
ORDER BY UnitPrice DESC;
```

Use parentheses whenever `AND` and `OR` mix:

```sql
WHERE IsActive = 1
  AND (Email IS NULL OR Email LIKE N'%@example.test')
```

For a `datetime2` column, use a half-open date range so every time on the last day is included:

```sql
WHERE CreatedAt >= '2026-07-01'
  AND CreatedAt <  '2026-08-01'
```

## Sort, limit, and page results

Rows have no promised order without `ORDER BY`. `TOP` without it means any matching rows.

```sql
SELECT TOP (5) ProductName, UnitPrice
FROM study.Product
ORDER BY UnitPrice DESC, ProductName ASC;
```

Use `OFFSET`/`FETCH` only with a stable order:

```sql
SELECT ProductId, ProductName
FROM study.Product
ORDER BY ProductId
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
```

## Subqueries: query inside query

A subquery provides an outer query with a value, a set, an existence test, or a result usable as a source.

| Form | Returns | Use it for |
| :--- | :--- | :--- |
| Scalar subquery | One value | Compare a row to an average or maximum |
| Multi-row subquery | One-column set | Membership with `IN` |
| `EXISTS` subquery | Existence | Whether a related row is present |
| Derived table | Rows and columns | Query an already-shaped result |

### Scalar subquery

```sql
SELECT SalesOrderId, CustomerId, OrderTotal
FROM study.SalesOrder
WHERE OrderTotal > (
    SELECT AVG(OrderTotal)
    FROM study.SalesOrder
);
```

The inner query must return one value. If it returns multiple rows in a scalar context, SQL Server raises an error.

### `IN`: membership in a set

```sql
SELECT CustomerName
FROM study.Customer
WHERE CustomerId IN (
    SELECT CustomerId
    FROM study.SalesOrder
    WHERE OrderTotal >= 20.00
);
```

Read it as "customers whose ID belongs to the set of customers with a qualifying order." Duplicates in the inner result do not change membership.

### `EXISTS` and correlated subqueries

`EXISTS` is best when the question is "does at least one related row exist?" The query is correlated because the inner query references the current outer customer.

```sql
SELECT c.CustomerId, c.CustomerName
FROM study.Customer AS c
WHERE EXISTS (
    SELECT 1
    FROM study.SalesOrder AS o
    WHERE o.CustomerId = c.CustomerId
);
```

`SELECT 1` is conventional; `EXISTS` cares only whether the inner query produces a row. Use `NOT EXISTS` for customers with no orders:

```sql
SELECT c.CustomerId, c.CustomerName
FROM study.Customer AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM study.SalesOrder AS o
    WHERE o.CustomerId = c.CustomerId
);
```

> [!warning] `NOT IN` and `NULL`
> If the inner result of `NOT IN` contains `NULL`, the predicate can become unknown for every outer row. Prefer `NOT EXISTS` for anti-relationship questions unless `NULL` is excluded deliberately.

### Derived tables

A derived table is a subquery in `FROM`; it must have an alias.

```sql
SELECT totals.CustomerId, totals.TotalSpend
FROM (
    SELECT CustomerId, SUM(OrderTotal) AS TotalSpend
    FROM study.SalesOrder
    GROUP BY CustomerId
) AS totals
WHERE totals.TotalSpend >= 100.00;
```

Use a derived table for a small one-statement step. A CTE expresses the same kind of logical step with a name; Lesson 09 explains its scope.

## Set operators: combine compatible results

Set operators stack results vertically. The two queries must return the same number of columns with compatible types and matching meaning.

| Operator | Meaning | Duplicates |
| :--- | :--- | :--- |
| `UNION` | Row in either result | Removed |
| `UNION ALL` | Row in either result | Kept |
| `INTERSECT` | Row in both results | Removed |
| `EXCEPT` | Row in first but not second | Removed |

```sql
-- Customers who have either an order or a recorded email.
SELECT CustomerId
FROM study.SalesOrder
UNION
SELECT CustomerId
FROM study.Customer
WHERE Email IS NOT NULL;

-- Customers in the customer list who have not placed an order.
SELECT CustomerId
FROM study.Customer
EXCEPT
SELECT CustomerId
FROM study.SalesOrder;
```

Use `UNION ALL` when retaining duplicates is intentional or results are known to be disjoint; it avoids the duplicate-removal work of `UNION`. `INTERSECT` is useful for the overlap of two lists.

### Set operator versus JOIN

```text
JOIN:  customer columns + order columns  → wider rows
UNION: rows from result A + result B     → taller result
```

Use a JOIN to display a customer beside their orders. Use a set operator to merge or compare compatible lists.

## Where CTEs, temp tables, and table variables fit

The structure should match how long an intermediate result is needed.

| Structure | Lifetime | Appropriate use |
| :--- | :--- | :--- |
| Subquery / derived table | One statement | Small local query step |
| CTE | One following statement | Named, readable logical step |
| Table variable (`@T`) | Current batch/procedure/function | Small scoped procedural set |
| Local temp table (`#T`) | Current session | Reuse intermediate rows across statements |
| Global temp table (`##T`) | Shared while it exists | Avoid by default; shared scope is risky |

Lesson 04 owns the query vocabulary. [Lesson 09](./09-subqueries-and-ctes.md) owns the lifetime, scope, and choice between CTE, temp table, and table variable. This prevents CTE theory from being repeated in both chapters.

## Practice questions

### 1. Group filtering

Which clause filters groups after `SUM(OrderTotal)` is calculated?

A. `WHERE`<br>
B. `HAVING`<br>
C. `ORDER BY`<br>
D. `DISTINCT`

> [!success]- Answer
> **B. `HAVING`** filters grouped results; `WHERE` filters input rows before grouping.

### 2. Missing relationships

Which pattern most directly returns customers with no orders?

A. `CustomerId <> NULL`<br>
B. `INNER JOIN SalesOrder`<br>
C. `NOT EXISTS (SELECT 1 FROM SalesOrder WHERE ...)`<br>
D. `UNION ALL`

> [!success]- Answer
> **C.** `NOT EXISTS` expresses the absence of a related row and avoids `NOT IN`'s `NULL` behavior.

### 3. List difference

Which operator returns distinct rows present in the first result but not in the second?

A. `UNION ALL`<br>
B. `INTERSECT`<br>
C. `EXCEPT`<br>
D. `CROSS JOIN`

> [!success]- Answer
> **C. `EXCEPT`** returns first-result minus second-result rows.

## Use Cases

- Inspect exact rows before an `UPDATE` or `DELETE`.
- Compare each row with a calculated benchmark using a scalar subquery.
- Find entities that have or lack related rows with `EXISTS`/`NOT EXISTS`.
- Merge or compare compatible lists with set operators.

## Common Issues & Errors

> [!warning] Common Mistake
> Without `ORDER BY`, SQL Server can return rows in any order. `TOP` without `ORDER BY` therefore returns arbitrary rows.

> [!warning] Common Mistake
> `DISTINCT` and `UNION` can hide bad joins or unexpected duplicate data. Understand the source before removing duplicates.

## Best Practices

- Select required columns only and give calculated values clear aliases.
- Parenthesize mixed `AND`/`OR` conditions.
- Use `EXISTS` when the question is about existence, not inner values.
- Use `UNION ALL` only when duplicates are intentionally preserved.
- Keep one-statement logic in a subquery or CTE; introduce temporary structures only when their lifetime is needed.

## Exam Tips

> [!tip] Exam Tips
> `WHERE` filters rows and `HAVING` filters groups. `EXISTS` tests whether a correlated subquery returns any row. `UNION` removes duplicates, `UNION ALL` preserves them, `INTERSECT` finds common rows, and `EXCEPT` finds rows only in the first result.

## Key Takeaways

- `SELECT` describes a result and does not change stored data.
- Subquery shape must match whether the outer query needs a value, a set, or existence.
- Set operators stack compatible results; JOINs combine columns from related rows.
- CTEs, temp tables, and table variables are covered as intermediate structures in Lesson 09.

## Related Topics

- [Relationships and JOINs](./05-relationships-and-joins.md)
- [Aggregation and grouping](./06-aggregation-and-grouping.md)
- [Subqueries and CTEs](./09-subqueries-and-ctes.md)
- [Advanced T-SQL](../03-advanced-tsql/advanced-tsql.md)

## Official Documentation

- [SELECT](https://learn.microsoft.com/sql/t-sql/queries/select-transact-sql)
- [Subqueries](https://learn.microsoft.com/sql/relational-databases/performance/subqueries)
- [EXISTS](https://learn.microsoft.com/sql/t-sql/language-elements/exists-transact-sql)
- [UNION, EXCEPT, and INTERSECT](https://learn.microsoft.com/sql/t-sql/language-elements/set-operators-union-transact-sql)

---

**[← Previous](./03-create-and-load-data.md) | [↑ Back to Section](./fundamentals.md) | [Next →](./05-relationships-and-joins.md)**
