---
title: Integrity Rules
type: topic
tags: [sql-server, constraints, keys, fundamentals]
---

# Integrity Rules

## Overview

Constraints keep invalid data out of the database, regardless of which application submits it. They are the first line of defense for a trustworthy relational model — a **database-side safeguard** that cannot be bypassed by buggy application code, ad-hoc scripts, or data imports.

> [!abstract]
>
> - `PRIMARY KEY` uniquely identifies a row and enforces non-nullability.
> - `FOREIGN KEY` requires a matching parent row.
> - `UNIQUE`, `CHECK`, `DEFAULT`, and `NOT NULL` express local column- and table-level rules.
> - Constraints are named so that errors are understandable at the application layer.

> [!tip] What the Exam Tests
> Constraints, sequences, identity columns, and their operational consequences appear in the Database Objects section. On the DP-800 exam, expect scenario-based questions about constraint violations, cascading actions, and the interaction between `CHECK` and `NULL`.

---

## PRIMARY KEY

Every table should have a primary key. It enforces two rules simultaneously: **uniqueness** and **non-nullability**.

```sql
-- Single-column primary key (clustered by default)
CREATE TABLE study.Customer (
    CustomerId   int IDENTITY(1,1) NOT NULL,
    CustomerName nvarchar(100) NOT NULL,
    CONSTRAINT PK_Customer PRIMARY KEY (CustomerId)
);
```

```sql
-- Composite primary key (two or more columns)
CREATE TABLE study.OrderItem (
    SalesOrderId int NOT NULL,
    ProductId    int NOT NULL,
    Quantity     smallint NOT NULL,
    CONSTRAINT PK_OrderItem PRIMARY KEY (SalesOrderId, ProductId)
);
```

> [!note]
> In SQL Server, a primary key creates a **unique clustered index** by default. This is a storage choice, not a requirement. You can specify `NONCLUSTERED` in the constraint definition. The conceptual model: a primary key is a logical constraint; the index is a physical implementation detail.

```sql
-- Primary key with nonclustered index
CREATE TABLE study.Example (
    Id int NOT NULL,
    CONSTRAINT PK_Example PRIMARY KEY NONCLUSTERED (Id)
);
```

### Diagram: PK in the relational model

```text
study.Customer                         study.SalesOrder
-------------------------------        ---------------------------------
| PK  CustomerId       int   |──┐     | PK  SalesOrderId     int      |
|     CustomerName nvarchar(100)|     | FK  CustomerId       int      |
|     Email      nvarchar(320)|     |     OrderDate         date     |
-------------------------------     |     OrderTotal        decimal  |
                                     ---------------------------------
```

## FOREIGN KEY

A foreign key guarantees that a value in the child table has a matching value in the parent's primary key or unique constraint. It prevents orphan rows.

```sql
-- Foreign key at table creation
CREATE TABLE study.SalesOrder (
    SalesOrderId int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_SalesOrder PRIMARY KEY,
    CustomerId   int NOT NULL,
    OrderDate    date NOT NULL,
    CONSTRAINT FK_SalesOrder_Customer
        FOREIGN KEY (CustomerId) REFERENCES study.Customer(CustomerId)
);
```

Attempting to insert a child row with a non-existent parent value raises error 547:

```sql
-- ERROR 547: FK violation
INSERT INTO study.SalesOrder (CustomerId, OrderDate, OrderTotal)
VALUES (999, '2026-07-01', 10.00);
-- Msg 547: The INSERT statement conflicted with the FOREIGN KEY constraint.
```

> [!warning] Common Mistake
> A foreign key does **not** automatically create an index on the child column. The FK protects referential integrity; an index on the child key is a separate performance decision.

### ON DELETE and ON UPDATE

| Action | Effect on child rows when parent is deleted |
| :--- | :--- |
| `NO ACTION` (default) | Delete fails with FK error |
| `CASCADE` | Child rows are deleted automatically |
| `SET NULL` | Child FK is set to `NULL` (column must be nullable) |
| `SET DEFAULT` | Child FK is set to its default value |

```sql
ALTER TABLE study.SalesOrder
ADD CONSTRAINT FK_SalesOrder_Customer_Cascade
    FOREIGN KEY (CustomerId) REFERENCES study.Customer(CustomerId)
    ON DELETE CASCADE;
```

> [!warning] Common Mistake
> `CASCADE` can chain across multiple tables. SQL Server restricts cascading to a maximum of 75 levels. Design carefully to avoid unintended mass deletions.

## UNIQUE constraint

A `UNIQUE` constraint ensures that no two rows have the same value in the specified column(s). Unlike a primary key, a unique constraint **allows one `NULL`** in SQL Server.

```sql
CREATE TABLE study.Customer (
    CustomerId   int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Customer PRIMARY KEY,
    CustomerName nvarchar(100) NOT NULL,
    Email        nvarchar(320) NULL
        CONSTRAINT UQ_Customer_Email UNIQUE
);
```

| Feature | PRIMARY KEY | UNIQUE |
| :--- | :--- | :--- |
| Uniqueness enforced | Yes | Yes |
| NULL allowed | No | One NULL in SQL Server |
| Default index | Clustered (typically) | Nonclustered |
| Per table | One | Multiple |

```sql
-- Composite UNIQUE: each combination of values must be unique
CREATE TABLE lab.ProductCategory (
    ProductId  int NOT NULL,
    CategoryId int NOT NULL,
    CONSTRAINT UQ_ProductCategory UNIQUE (ProductId, CategoryId)
);
```

## CHECK constraint

A `CHECK` constraint validates that a value in a single row satisfies a Boolean expression.

```sql
CREATE TABLE study.Product (
    ProductId   int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Product PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    UnitPrice   decimal(10,2) NOT NULL
        CONSTRAINT CK_Product_UnitPrice CHECK (UnitPrice >= 0)
);
```

Attempting to insert an invalid value:

```sql
-- ERROR: CHECK constraint violation
INSERT INTO study.Product (ProductName, UnitPrice)
VALUES (N'Invalid price', -5.00);
-- Msg 547: The INSERT statement conflicted with the CHECK constraint.
```

### CHECK and NULL — the UNKNOWN trap

A `CHECK` constraint passes when its predicate evaluates to **TRUE or UNKNOWN**. Since a comparison with `NULL` produces `UNKNOWN`, a `NULL` value passes a `CHECK` even when the predicate would fail for a real value.

```sql
-- This passes because NULL >= 0 evaluates to UNKNOWN, not FALSE
CREATE TABLE #TestCheck (
    Val decimal(10,2) NULL CHECK (Val >= 0)
);
INSERT INTO #TestCheck (Val) VALUES (NULL);  -- succeeds
INSERT INTO #TestCheck (Val) VALUES (-5.00); -- fails
DROP TABLE #TestCheck;
```

If a column must never contain a negative value *and* never be missing, combine `CHECK` with `NOT NULL`.

> [!note] Mental model — the bouncer
> Think of each constraint as a **bouncer at a club**. The `PRIMARY KEY` bouncer checks ID (unique + required). The `FOREIGN KEY` bouncer verifies you are on a guest list (parent exists). The `CHECK` bouncer enforces dress code (value valid). The `UNIQUE` bouncer ensures no one else has the same VIP pass. The `DEFAULT` bouncer hands you a drink if you do not specify one. The `NOT NULL` bouncer checks that a field is filled in — no blank entries allowed.

## DEFAULT constraint

A `DEFAULT` applies a value when an `INSERT` statement omits the column.

```sql
CREATE TABLE study.Customer (
    CustomerId   int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Customer PRIMARY KEY,
    CustomerName nvarchar(100) NOT NULL,
    IsActive     bit NOT NULL
        CONSTRAINT DF_Customer_IsActive DEFAULT (1),
    CreatedDate  date NOT NULL
        CONSTRAINT DF_Customer_CreatedDate DEFAULT (CAST(SYSDATETIME() AS date))
);
```

```sql
-- Uses default for IsActive and CreatedDate
INSERT INTO study.Customer (CustomerName) VALUES (N'Ana Silva');
-- IsActive = 1, CreatedDate = today

-- Does NOT use default for IsActive; stores NULL instead
INSERT INTO study.Customer (CustomerName, IsActive)
VALUES (N'Bruno Costa', NULL);
-- IsActive = NULL, not 1
```

> [!warning] Common Mistake
> Explicitly inserting `NULL` into a column with a `DEFAULT` does **not** invoke the default. The default applies only when the column is omitted from the `INSERT` column list.

## NOT NULL

`NOT NULL` is the simplest constraint: it rejects any row that would leave the column null.

```sql
CREATE TABLE study.Product (
    ProductId   int IDENTITY(1,1) NOT NULL,
    ProductName nvarchar(100) NOT NULL,  -- every product MUST have a name
    Description nvarchar(500) NULL       -- description is optional
);
```

Guidelines for deciding nullability:

| Column characteristic | Nullable? |
| :--- | :--- |
| Business fact always known | `NOT NULL` |
| Value genuinely unknown at insert time | `NULL` allowed |
| Foreign key in a child table | Usually `NOT NULL` |
| Optional attribute (middle name, suffix) | `NULL` allowed |
| Will be populated later in a workflow | Can be `NULL` during interim state |

## ALTER TABLE with CHECK / NOCHECK

When adding a constraint to an existing table, SQL Server by default validates existing data (`WITH CHECK`). Use `WITH NOCHECK` to skip validation (useful when you know existing data is clean, or when applying a new rule only to future data).

```sql
-- Default: validates ALL existing rows (fails if any violate)
ALTER TABLE study.SalesOrder WITH CHECK
ADD CONSTRAINT CK_SalesOrder_Total CHECK (OrderTotal >= 0);

-- Skip validation of existing rows (new rule applies to new data only)
ALTER TABLE study.SalesOrder WITH NOCHECK
ADD CONSTRAINT CK_SalesOrder_Total CHECK (OrderTotal >= 0);
```

> [!warning] Common Mistake
> A constraint added with `WITH NOCHECK` is marked as **not trusted**. The query optimizer may not use it for cardinality estimation, which can affect performance. Query `sys.check_constraints` to see the `is_not_trusted` flag.

```sql
SELECT name, is_not_trusted
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID(N'study.SalesOrder');
```

## Check yourself

### 1. Foreign key violation

You try to insert a `SalesOrder` with `CustomerId = 999` in a table where no customer has that ID. What error do you get? How would you catch it gracefully in T-SQL?

> [!success]- Answer
> Error 547: foreign key constraint violation. Catch it with `BEGIN TRY...BEGIN CATCH` and inspect `ERROR_NUMBER()`:
>
> ```sql
> BEGIN TRY
>     INSERT INTO study.SalesOrder (CustomerId, OrderDate, OrderTotal)
>     VALUES (999, '2026-07-01', 10.00);
> END TRY
> BEGIN CATCH
>     IF ERROR_NUMBER() = 547
>         PRINT 'FK violation: CustomerId does not exist.';
> END CATCH;
> ```

### 2. CHECK and NULL

What happens when you insert `NULL` into a column defined as `CHECK (Value > 0)` and the column is nullable?

> [!success]- Answer
> The insert **succeeds**. A comparison with `NULL` evaluates to `UNKNOWN`, which is not `FALSE`. The `CHECK` constraint only rejects rows where the predicate evaluates to `FALSE`. Add `NOT NULL` to the column if a missing value should also be rejected.

### 3. UNIQUE and NULL

How many `NULL` values can a `UNIQUE` constraint accept in SQL Server?

> [!success]- Answer
> One `NULL`. SQL Server treats `NULL` as a distinct value for uniqueness purposes. If the column is nullable, a single row with `NULL` is allowed; a second row with `NULL` would violate the constraint.

### 4. DEFAULT misunderstanding

You create a column `IsActive bit NOT NULL DEFAULT (1)` and then run:

```sql
INSERT INTO study.Customer (CustomerName, IsActive) VALUES (N'Test', NULL);
```

What is the value of `IsActive` for the new row?

> [!success]- Answer
> `NULL`. The `DEFAULT` only applies when the column is **omitted** from the `INSERT` column list. Explicitly passing `NULL` inserts `NULL` — and since the column is `NOT NULL`, this insert **fails**.

## Next steps

Constraints are the building blocks of reliable database design. Build on this foundation in later sections:

- **Sequences and identity** → Section 01 — Database Objects
- **Temporal tables** → Section 02 — Programmability Objects
- **Ledger tables** → Section 02 — Programmability Objects
- **Index design** → Section 01 — Database Objects (filtered, columnstore)

## Use Cases

- Prevent orders referencing non-existent customers (FK).
- Prevent negative prices or quantities (CHECK).
- Ensure unique email addresses per user (UNIQUE).
- Automatically set audit timestamps on insert (DEFAULT).

## Common Issues & Errors

> [!warning] Common Mistake
> A foreign key does not automatically create an index on the child column. The FK protects referential integrity; the index is a separate performance decision.

> [!warning] Common Mistake
> A `CHECK` passes when the result is `UNKNOWN` (i.e., when the column is `NULL`). Combine with `NOT NULL` if invalid and missing are both unacceptable.

> [!warning] Common Mistake
> Explicitly inserting `NULL` does not invoke a `DEFAULT`. The default only fires when the column is omitted from the insert column list.

> [!warning] Common Mistake
> Removing a constraint is `ALTER TABLE ... DROP CONSTRAINT`. There is no `DISABLE CONSTRAINT` in standard SQL Server (you can `NOCHECK` for FK/CHECK in some scenarios). Do not change the constraint to "let bad data in" — fix the data instead.

## Best Practices

- Name all constraints so that production error messages are meaningful.
- Put durable business rules in constraints when they can be expressed declaratively.
- Always test constraint violations with `BEGIN TRY...BEGIN CATCH` during development.
- Use `WITH CHECK` (the default) when adding constraints to existing data.
- Prefer `NO ACTION` over `CASCADE` unless you have a clear business reason for cascading deletes.

## Exam Tips

> [!tip] Exam Tips
> A primary key enforces uniqueness and non-nullability; a unique constraint allows one `NULL` in SQL Server. The default index for a primary key is clustered. A foreign key does not create an index. `CHECK` and `NULL` interact via three-valued logic: `UNKNOWN` is not `FALSE`.

## Key Takeaways

- Constraints protect data at the database boundary — they cannot be bypassed.
- Relationships are enforced with foreign keys; uniqueness with primary keys and unique constraints.
- `CHECK` uses three-valued logic: pass if TRUE or UNKNOWN, fail only if FALSE.
- `DEFAULT` fires on omission, not on explicit `NULL`.
- Name constraints to make errors self-documenting.

## Related Topics

- [Index fundamentals](./10-index-fundamentals.md)
- [Database Objects](../01-database-objects/database-objects.md)
- [Change data safely](./07-change-data-safely.md)
- [Relationships and JOINs](./05-relationships-and-joins.md)

## Official Documentation

- [Primary and foreign key constraints](https://learn.microsoft.com/sql/relational-databases/tables/primary-and-foreign-key-constraints)
- [CHECK constraint](https://learn.microsoft.com/sql/relational-databases/tables/check-constraints)
- [UNIQUE constraint](https://learn.microsoft.com/sql/relational-databases/tables/unique-constraints)
- [DEFAULT constraint](https://learn.microsoft.com/sql/relational-databases/tables/default-constraints)

---

**[← Previous](./07-change-data-safely.md) | [↑ Back to Section](./fundamentals.md) | [Lab: Integrity Rules](../../practice/labs/00-fundamentals/08-integrity-rules.sql) | [Next →](./09-subqueries-and-ctes.md)**
