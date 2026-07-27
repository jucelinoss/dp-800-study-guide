---
title: Create and Load Data
type: topic
tags: [sql-server, ddl, dml, fundamentals]
---

# Create and Load Data

## Overview

Before an application can query data, someone must define a dependable structure and load valid rows into it. This chapter explains the first lifecycle: create a database and schema, create tables, then insert and inspect data predictably.

> [!abstract]
>
> - DDL defines database objects; DML inserts and later changes their rows.
> - `CREATE TABLE` is a data contract, not just a list of columns.
> - Explicit column lists, generated keys, defaults, and result checks make loading repeatable.

> [!tip] What the Exam Tests
> DP-800 expects you to understand tables, schemas, DDL and DML before it extends them with specialized objects, deployment projects, and advanced database design.

---

## DDL and DML: two kinds of change

**Data definition language (DDL)** creates or changes the structure: databases, schemas, tables, constraints, and indexes. **Data manipulation language (DML)** works with the rows inside that structure.

| Statement | Category | What changes |
| :--- | :--- | :--- |
| `CREATE DATABASE` | DDL | A new database container |
| `CREATE SCHEMA` | DDL | A namespace for objects |
| `CREATE TABLE` | DDL | A table definition |
| `ALTER TABLE` | DDL | An existing definition |
| `DROP TABLE` | DDL | Removes table and its data |
| `INSERT` | DML | Adds rows |
| `UPDATE` | DML | Changes existing rows |
| `DELETE` | DML | Removes rows |

DDL is not automatically harmless. A `DROP` or an incompatible `ALTER` can make data unavailable. DML is not automatically safer: an `UPDATE` or `DELETE` without a correct predicate can affect every row. Part 0 begins with safe creation and loading; the transaction discipline for changes appears in [Change data safely](./07-change-data-safely.md).

## Create a disposable learning database

The labs use a database called `StudyDB`. Keep learning objects out of `master`, which SQL Server uses for system-level metadata.

```sql
USE master;
GO

CREATE DATABASE StudyDB;
GO

USE StudyDB;
GO

CREATE SCHEMA study;
GO
```

`GO` is a batch separator understood by clients such as SSMS; it is not a T-SQL statement sent to SQL Server. It is useful after `CREATE DATABASE` because the next command must connect to the newly created database.

Check context before running a script that creates objects:

```sql
SELECT DB_NAME() AS current_database,
       SCHEMA_NAME() AS default_schema;
```

> [!warning] Common Mistake
> `CREATE DATABASE StudyDB` fails if it already exists. In a lesson, read the setup lab and decide whether to reuse, reset, or use a different name; do not blindly drop an existing database.

## Read a `CREATE TABLE` definition as a contract

This table says what a valid product row must contain.

```sql
CREATE TABLE study.Product (
    ProductId int IDENTITY(1, 1) NOT NULL,
    ProductName nvarchar(100) NOT NULL,
    UnitPrice decimal(12, 2) NOT NULL,
    IsDiscontinued bit NOT NULL CONSTRAINT DF_Product_IsDiscontinued DEFAULT (0),
    CreatedAt datetime2 NOT NULL CONSTRAINT DF_Product_CreatedAt DEFAULT (sysdatetime()),
    CONSTRAINT PK_Product PRIMARY KEY (ProductId),
    CONSTRAINT CK_Product_UnitPrice CHECK (UnitPrice >= 0)
);
```

| Definition piece | Meaning | Why it exists |
| :--- | :--- | :--- |
| `study.Product` | Schema-qualified table name | Avoids ambiguity and groups the object |
| `ProductId int` | Whole-number identifier | Efficient stable key |
| `IDENTITY(1, 1)` | Generate values: start 1, increment 1 | Avoids hand-assigned IDs for normal inserts |
| `NOT NULL` | A value is required | Rejects incomplete rows |
| `DEFAULT (0)` | Fill omitted value with zero/false | Gives a predictable initial state |
| `PRIMARY KEY` | Unique, non-null row identity | Protects identity and supports relationships |
| `CHECK` | Row must meet a predicate | Rejects nonsensical negative price |

Constraint names such as `PK_Product` and `CK_Product_UnitPrice` are intentional. When an insert fails, a meaningful name tells you which rule was violated. The next chapters discuss constraints and keys more deeply; here, recognize that a table should protect its basic truths from its first row.

### `IDENTITY` is a generator, not a row count

`IDENTITY(1, 1)` generates a value when an insert omits that column. It does not guarantee consecutive values. A failed insert, rollback, delete, or concurrent activity can leave gaps, and that is normal.

```sql
INSERT INTO study.Product (ProductName, UnitPrice)
VALUES (N'Notebook', 12.50);

SELECT ProductId, ProductName, UnitPrice
FROM study.Product;
```

Do not use an identity value as proof of how many rows exist, and do not reuse deleted identity values as a business rule. The key identifies a row; it is not an invoice number, a ranking, or a promise of chronology.

### Defaults apply only when a column is omitted

This insert lets SQL Server apply both defaults:

```sql
INSERT INTO study.Product (ProductName, UnitPrice)
VALUES (N'Pen', 2.00);
```

This insert explicitly stores `NULL` and therefore does **not** request a default. It fails because `IsDiscontinued` is `NOT NULL`:

```sql
-- INSERT INTO study.Product (ProductName, UnitPrice, IsDiscontinued)
-- VALUES (N'Pencil', 1.50, NULL);
```

The distinction matters: a default is not a replacement for `NULL` in every situation. It is a value SQL Server supplies when the statement does not provide one.

## Insert rows deliberately

Always specify target columns. It documents intent, survives harmless column-order changes, and makes it clear which defaults or identity values are being requested.

```sql
INSERT INTO study.Product (ProductName, UnitPrice)
VALUES
    (N'Notebook', 12.50),
    (N'Pen', 2.00),
    (N'Backpack', 45.00);
```

SQL Server validates every row against the table definition. The following statements fail for useful reasons:

```sql
-- Required ProductName is missing.
-- INSERT INTO study.Product (UnitPrice) VALUES (10.00);

-- CHECK constraint rejects a negative price.
-- INSERT INTO study.Product (ProductName, UnitPrice) VALUES (N'Invalid', -5.00);
```

The error is evidence that the database contract works. Correct the data or reconsider the rule; do not remove a constraint merely to make an invalid load succeed.

### Inspect what was loaded

An `INSERT` message reports an affected-row count, but inspect representative data too:

```sql
SELECT ProductId,
       ProductName,
       UnitPrice,
       IsDiscontinued,
       CreatedAt
FROM study.Product
ORDER BY ProductId;
```

Verify generated key values, defaults, data types, and row count. Do this before building queries that depend on the data; a mistake is cheapest to correct immediately after it is introduced.

## Insert from another query

`INSERT ... SELECT` loads rows produced by a query. The target columns still need to line up with the selected expressions by position and compatible type.

```sql
CREATE TABLE study.ProductArchive (
    ProductName nvarchar(100) NOT NULL,
    UnitPrice decimal(12, 2) NOT NULL
);
GO

INSERT INTO study.ProductArchive (ProductName, UnitPrice)
SELECT ProductName, UnitPrice
FROM study.Product
WHERE IsDiscontinued = 1;
```

This is a common pattern for migrations and staging, but ask three questions before using it:

1. Does the source query return exactly the intended rows?
2. Are the target types and required columns compatible?
3. Can it be rerun safely, or will it duplicate rows?

For an initial seed script, a rerun can create duplicates. A later module covers deployment and repeatable database projects; for now, make the behavior visible and keep sample loads small.

### Capture generated values with `OUTPUT`

When an application inserts one or more rows, it often needs the generated keys. `OUTPUT` returns values from the affected rows without issuing a separate lookup.

```sql
INSERT INTO study.Product (ProductName, UnitPrice)
OUTPUT inserted.ProductId, inserted.ProductName
VALUES (N'Highlighter', 3.75);
```

`inserted` is a logical table available to DML statements. In an `INSERT`, it contains the newly inserted versions of rows. `OUTPUT` is safer and clearer for multi-row inserts than guessing which identity was generated.

## Creating a table from a query

`SELECT INTO` creates a new table and loads a query result in one operation.

```sql
SELECT ProductName, UnitPrice
INTO study.ProductPriceSnapshot
FROM study.Product;
```

This is useful for disposable exploration, but it copies the selected columns and data — not the full table contract. Primary keys, foreign keys, check constraints, indexes, triggers, permissions, and defaults do not automatically come along.

| Need | Prefer |
| :--- | :--- |
| Quick disposable copy for exploration | `SELECT INTO` |
| Known, governed table design | `CREATE TABLE`, then `INSERT ... SELECT` |
| Repeatable application schema | Versioned database project/migration, covered later |

> [!warning] Common Mistake
> A table made with `SELECT INTO` can look correct in a simple `SELECT`, while silently lacking the keys and checks that protect the original. Treat it as a new table that needs its own design review.

## Loading from files: keep the boundary explicit

Real systems frequently receive CSV and other files. The beginner principle is more important than memorizing a bulk-load command: do not treat external text as trusted database rows.

Use a staging approach:

```text
File or external source
        ↓
Staging table (inspect, validate, convert)
        ↓
Target table (keys, types, and constraints enforced)
```

A staging table may initially hold incoming values as text so that invalid dates or amounts can be identified. After validating with explicit conversions such as `TRY_CONVERT`, load clean rows into the typed target. Bulk import mechanics, permissions, and high-volume performance are outside this introductory chapter; the essential habit is validating before the final insert.

## Make small structural changes carefully

`ALTER TABLE` changes an existing definition. Adding an optional column is simpler than adding a required column to a populated table because existing rows need a valid value.

```sql
ALTER TABLE study.Product
ADD SupplierCode nvarchar(30) NULL;
```

For a new required column in an existing table, decide what valid value older rows should receive. Do not add `NOT NULL` until a trustworthy backfill or default has been designed. In a production system, such changes should be reviewed, tested, and deployed through a controlled process.

## A repeatable seed workflow

For the Part 0 labs, use this workflow whenever you add data:

1. Confirm the current database with `SELECT DB_NAME()`.
2. Read the table definition and constraints.
3. Insert a small, named set of rows.
4. Query those rows explicitly and inspect generated/default values.
5. Record whether the script may be rerun safely.

That last step prevents a common beginner problem: a script "works" twice but produces two copies of the seed data. A production-quality strategy may use a natural key and an upsert-like approach, but that introduces concurrency and design choices beyond this lesson. For now, reset `StudyDB` with the setup lab when you want a clean state.

## Practice exercises

### 1. Read the contract

For the `study.Product` table above, which values can a basic insert omit?

A. `ProductId` only<br>
B. `ProductId`, `IsDiscontinued`, and `CreatedAt`<br>
C. `ProductName` and `UnitPrice`<br>
D. Every column

> [!success]- Answer
> **B.** `ProductId` is generated by `IDENTITY`; `IsDiscontinued` and `CreatedAt` have defaults. `ProductName` and `UnitPrice` are `NOT NULL` without defaults, so the insert must provide them.

### 2. Make a valid load

Write an insert for a product named `Desk Lamp` costing `29.90` that requests the default values for the other columns.

> [!success]- Answer
>
> ```sql
> INSERT INTO study.Product (ProductName, UnitPrice)
> VALUES (N'Desk Lamp', 29.90);
> ```
>
> The explicit column list both omits the identity and allows the defaults to apply.

### 3. Choose a creation pattern

You need a throwaway copy of two columns for an exploratory query. Which pattern is appropriate, and what must you remember afterward?

> [!success]- Answer
> `SELECT INTO` is appropriate for the disposable copy. Remember that it does not reproduce keys, constraints, indexes, defaults, or permissions from the source table.

## Use Cases

- Create the `StudyDB` schema and tables used by Part 0 labs.
- Seed a predictable development dataset and inspect the values SQL Server generated.
- Copy a selected result into a disposable exploratory table while understanding its limits.

## Common Issues & Errors

> [!warning] Common Mistake
> Omitting the target-column list in `INSERT` ties the script to physical table order and makes defaults, identity behavior, and later schema changes harder to understand.

> [!warning] Common Mistake
> A default is not applied when the statement explicitly supplies `NULL`. Required columns still reject `NULL`.

## Best Practices

- Use schema-qualified names and explicit column lists.
- Give constraints meaningful names and verify rows immediately after loading.
- Keep exploratory `SELECT INTO` tables separate from governed source tables.
- Treat imported files as untrusted input; validate and convert before loading a final table.
- Keep learning work in `StudyDB`, never in `master`.

## Exam Tips

> [!tip] Exam Tips
> DDL changes metadata; DML changes rows. `IDENTITY` generates values but does not guarantee gap-free numbering. `SELECT INTO` copies selected data and columns, not the original table's keys, constraints, indexes, or permissions.

## Key Takeaways

- Design and create the table contract before loading data.
- Explicit inserts document intent and let identity/default behavior work predictably.
- Verify loads, generated values, and rerun behavior immediately.
- A quick copy is not a governed clone of the original table.

## Related Topics

- [Relational model and data types](./02-relational-model-and-data-types.md)
- [Change data safely](./07-change-data-safely.md)
- [Integrity rules](./08-integrity-rules.md)
- [Database Objects](../01-database-objects/database-objects.md)

## Official Documentation

- [CREATE TABLE](https://learn.microsoft.com/sql/t-sql/statements/create-table-transact-sql)
- [INSERT](https://learn.microsoft.com/sql/t-sql/statements/insert-transact-sql)
- [OUTPUT clause](https://learn.microsoft.com/sql/t-sql/queries/output-clause-transact-sql)
- [SELECT INTO](https://learn.microsoft.com/sql/t-sql/queries/select-into-clause-transact-sql)

---

**[← Previous](./02-relational-model-and-data-types.md) | [↑ Back to Section](./fundamentals.md) | [Next →](./04-select-and-filter.md)**
