---
title: Change Data Safely
type: topic
tags: [sql-server, dml, transactions, fundamentals]
---

# Change Data Safely

## Overview

`UPDATE` and `DELETE` are essential but potentially broad. Review the target rows and use a transaction when practicing or making a consequential change.

> [!abstract]
>
> - `UPDATE` changes existing values; `DELETE` removes rows.
> - Use the same predicate in a preview `SELECT` first.
> - `BEGIN TRAN`, `COMMIT`, and `ROLLBACK` make a unit of work explicit.

> [!tip] What the Exam Tests
> DP-800 develops this foundation into isolation levels, blocking, deadlocks, triggers, and change capture.

---

## Preview, then change

```sql
BEGIN TRAN;

SELECT *
FROM study.Product
WHERE ProductName = N'Pen';

UPDATE study.Product
SET UnitPrice = 2.25
WHERE ProductName = N'Pen';

ROLLBACK; -- replace with COMMIT only after verifying the result
```

## The non-negotiable rule: SELECT first

Before writing a destructive or corrective statement, write the exact `SELECT` that identifies its target. Verify the database, the row count, the key values, and the old values. Only then replace `SELECT` with `UPDATE` or `DELETE`, keeping the `FROM`/JOIN and `WHERE` logic unchanged.

```sql
-- 1. Confirm context.
SELECT DB_NAME() AS current_database;

-- 2. Preview the exact targets and values.
SELECT ProductId, ProductName, UnitPrice
FROM study.Product
WHERE ProductName = N'Notebook';

-- 3. Change exactly the rows just reviewed.
UPDATE study.Product
SET UnitPrice = 13.50
WHERE ProductName = N'Notebook';
```

For an important operation, do steps 2 and 3 inside the same short transaction. A preview done hours earlier is not a guarantee that data has not changed in the meantime.

| Check before DML | Why it matters |
| :--- | :--- |
| Database and schema | Prevents changing the wrong environment/object |
| Predicate and JOIN | Prevents a broad or incorrectly related target set |
| Row count | Exposes a surprising number of affected rows |
| Primary keys | Lets you identify exactly which rows will change |
| Old values | Lets you verify the new values and recover logically if needed |

> [!warning] A successful statement is not proof of correctness
> SQL Server can successfully update 10,000 unintended rows. The affected-row message only confirms execution, not that the predicate expressed the intended business rule.

## The DML safety loop

Use the same predicate in a `SELECT` before every consequential `UPDATE` or `DELETE`. Then inspect affected rows, change them inside a short transaction, inspect again, and choose `COMMIT` or `ROLLBACK`.

```sql
BEGIN TRAN;

SELECT SalesOrderId, OrderTotal
FROM study.SalesOrder
WHERE CustomerId = 1;

UPDATE study.SalesOrder
SET OrderTotal = OrderTotal * 0.90
WHERE CustomerId = 1;

SELECT SalesOrderId, OrderTotal
FROM study.SalesOrder
WHERE CustomerId = 1;

ROLLBACK;
```

`ROLLBACK` reverses uncommitted work in the transaction. `COMMIT` makes it durable. Keep the transaction short: open transactions can hold locks and block other sessions.

### A reviewable transaction template

```sql
SET XACT_ABORT ON;
BEGIN TRAN;

SELECT ProductId, ProductName, UnitPrice
FROM study.Product
WHERE ProductName LIKE N'Old%';

UPDATE study.Product
SET IsDiscontinued = 1
OUTPUT inserted.ProductId, inserted.IsDiscontinued
WHERE ProductName LIKE N'Old%';

-- Inspect the OUTPUT and a follow-up SELECT.
-- COMMIT;
ROLLBACK;
```

`SET XACT_ABORT ON` is a helpful default in many scripts: certain runtime errors end and roll back the transaction rather than leaving it open. It does not replace understanding errors or testing a script. In the learning labs, leave `ROLLBACK` active until the result is unquestionably correct.

## UPDATE and DELETE are set operations

One statement can affect many rows; SQL is not implicitly one-row-at-a-time. That is powerful and hazardous.

```sql
-- Update every matching row, not only the first visible one.
UPDATE study.Product
SET IsDiscontinued = 1
WHERE ProductName LIKE N'Old%';

-- Delete only the intended rows.
DELETE FROM study.Product
WHERE IsDiscontinued = 1;
```

`DELETE` removes selected rows and can be rolled back within an open transaction. `TRUNCATE TABLE` removes all rows much more broadly and has different restrictions; it is not a substitute for a predicate-based delete. Do not use either as a casual cleanup command.

### All-at-once semantics

Assignments in one `UPDATE` read the original row values; their written order is not procedural.

```sql
-- If col1 is 100 and col2 is 0, result is col1 = 110 and col2 = 100.
UPDATE dbo.Example
SET col1 = col1 + 10,
    col2 = col1
WHERE ExampleId = 1;
```

Do not expect `col2` to receive the newly updated `col1`. Use an explicit expression when that is the desired rule. This set-based behavior is one reason a preview query is safer than trying to reason about an update row by row.

## UPDATE and DELETE with JOINs

T-SQL lets an update or delete use related tables to identify targets. This is powerful enough to require an extra rule: run the exact JOIN and filters as a `SELECT` first, including the target table's key and the source value that will be used.

```sql
-- Preview first: one target row must have one intended source value.
SELECT p.ProductId, p.UnitPrice, s.NewPrice
FROM study.Product AS p
INNER JOIN study.ProductPriceStage AS s
    ON s.ProductId = p.ProductId;

-- Only after review.
UPDATE p
SET UnitPrice = s.NewPrice
FROM study.Product AS p
INNER JOIN study.ProductPriceStage AS s
    ON s.ProductId = p.ProductId;
```

If multiple stage rows match one product, the update can be nondeterministic: SQL Server is not required to warn you which source value will win. Enforce one source row per target with a key, aggregate/rank the source first, or reject duplicates before the update.

```sql
-- Preview duplicates in a staging source.
SELECT ProductId, COUNT(*) AS matching_source_rows
FROM study.ProductPriceStage
GROUP BY ProductId
HAVING COUNT(*) > 1;
```

The same preview-first rule applies to `DELETE` with a join. Use an explicit target alias so it is obvious which table will lose rows.

## DELETE versus TRUNCATE TABLE

| Characteristic | `DELETE` | `TRUNCATE TABLE` |
| :--- | :--- | :--- |
| Filter with `WHERE` | Yes | No |
| Scope | Selected rows or all rows | All rows (or specified partitions) |
| Identity counter | Does not reset it | Resets it |
| Typical permission | `DELETE` | `ALTER` |
| Referenced by foreign key | May delete rows if referential rules allow | Cannot truncate a referenced table |
| Use case | Targeted removal | Intentional complete reset of an eligible disposable table |

Both are destructive. `TRUNCATE` is not "DELETE but faster" when you need to preserve some rows, inspect individual targets, or keep the identity sequence. Large `DELETE` operations can create substantial log activity and locking; production batching and retention design are performance topics, but the beginner takeaway is to plan large deletions rather than run them interactively.

## INSERT safely too

The same discipline applies to inserts: inspect the source query, name target columns, and verify generated/default values after the load.

```sql
-- Preview the source first.
SELECT ProductName, UnitPrice
FROM study.ProductArchive
WHERE UnitPrice >= 10.00;

INSERT INTO study.Product (ProductName, UnitPrice)
OUTPUT inserted.ProductId, inserted.ProductName
SELECT ProductName, UnitPrice
FROM study.ProductArchive
WHERE UnitPrice >= 10.00;
```

When a table has a default, omitting the column requests that default; explicitly inserting `NULL` does not. Avoid `SET IDENTITY_INSERT` in ordinary application loads. It is a specialized migration/recovery tool that requires exclusive care and must be turned off after use.

## Capture what changed

`OUTPUT` can return affected rows for review or auditing:

```sql
UPDATE study.Product
SET UnitPrice = UnitPrice * 1.05
OUTPUT inserted.ProductId,
       deleted.UnitPrice AS old_price,
       inserted.UnitPrice AS new_price
WHERE ProductName = N'Notebook';
```

`deleted` represents the pre-change row and `inserted` represents the post-change row. It is useful for verification; full auditing and triggers are later topics.

> [!warning] Common Mistake
> An update joined to a source that has multiple matches for one target can be nondeterministic. First run the join as `SELECT` and prove the source supplies at most one intended value per target row.

## Use Cases

- Correct a small batch of rows with an auditable review step.
- Safely experiment in a lab without recreating the database.

## Common Issues & Errors

> [!warning] Common Mistake
> An `UPDATE` or `DELETE` without `WHERE` affects every row in its target table.

## Best Practices

- Run the preview `SELECT` with the exact DML predicate.
- Keep transactions short; open transactions can block other work.

## Exam Tips

> [!tip] Exam Tips
> A transaction provides atomicity: its changes are committed together or rolled back together.

## Key Takeaways

- Read the target first.
- Commit only after you have verified the intended change.

## Related Topics

- [Integrity rules](./08-integrity-rules.md)
- [Performance Optimization](../06-performance-optimization/performance-optimization.md)

## Official Documentation

- [Transactions](https://learn.microsoft.com/sql/t-sql/language-elements/transactions-transact-sql)

---

**[← Previous](./06-aggregation-and-grouping.md) | [↑ Back to Section](./fundamentals.md) | [Lab: Safe DML](../../practice/labs/00-fundamentals/07-safe-dml.sql) | [Next →](./08-integrity-rules.md)**
