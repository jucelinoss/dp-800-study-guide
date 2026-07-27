---
title: SQL Server Foundations Workbook
type: workbook
tags: [sql-server, tsql, fundamentals, practice]
---

# SQL Server Foundations Workbook

This workbook is the self-contained, practical companion to Part 0. Read it while executing the scripts in [`practice/labs/00-fundamentals/`](../../practice/labs/00-fundamentals/). It deliberately stops before specialized table types, stored procedures, query plans, and AI features; those are covered in the exam-mapped sections.

> [!abstract]
>
> - Learn the mental model before memorizing keywords.
> - Build one small sales database and interrogate it from several angles.
> - Use the check-yourself exercises before moving to Section 01.

> [!tip] How to use this workbook
>
> Run a code block only after reading it. Change one value, rerun it, and predict the result before looking at the output. That small habit is how syntax becomes understanding.

---

## 1. The database mental model

Think of a database as a carefully governed collection of related facts. A spreadsheet can contain columns named `Customer`, `Order`, and `Product`, but a relational database separates each kind of fact into its own table and connects the tables with values called keys.

```text
SQL Server instance
└── StudyDB database
    └── study schema
        ├── Customer table
        ├── Product table
        └── SalesOrder table
```

The distinction matters:

| Term | Meaning | Example |
| :--- | :--- | :--- |
| Instance | Running SQL Server engine | `localhost` or `SERVER01\SQLEXPRESS` |
| Database | A contained collection of objects and data | `StudyDB` |
| Schema | Namespace that groups database objects | `study` or `dbo` |
| Table | A named collection of similarly shaped rows | `study.Customer` |
| Column | One attribute stored for each row | `CustomerName` |
| Row | One record | one customer |

Use a two-part name such as `study.Customer`. SQL Server can resolve a one-part name such as `Customer`, but explicit schema names avoid ambiguity and become essential in real databases.

### Entities, attributes, and relationships

An **entity** is something the business wants to remember: a customer, product, or order. An **attribute** is a fact about one entity: a customer has a name and email; an order has a date and total. A **relationship** expresses how entities connect: each order belongs to one customer; one customer can have zero, one, or many orders.

This is why `CustomerName` should not be copied into every order row. If a name changes, one customer row changes. Repeating it in every order risks inconsistent history and wasted storage.

> [!note] Mental model — tables
> A table is not merely a grid. It is a contract: every row represents the same kind of thing, and every column has one consistent meaning.

### Keys

A **primary key** uniquely identifies a row. `CustomerId = 1` means one specific customer, regardless of whether two people share the same name. A **foreign key** stores a primary-key value from another table, allowing an order to point to its customer.

```text
Customer                          SalesOrder
------------------------          --------------------------
CustomerId  (primary key) <-----  CustomerId (foreign key)
CustomerName                      SalesOrderId (primary key)
                                  OrderDate
```

Do not confuse a key with a visible label. A product name can be edited and can be duplicated. Numeric or generated identifiers are often used as stable surrogate keys, while a `UNIQUE` constraint protects a natural business identifier such as an email address when that rule applies.

## 2. Data types and missing information

Every column needs a data type. It tells SQL Server what the value means, how it can be compared, and how much space it may use.

| Need | Recommended starting type | Why |
| :--- | :--- | :--- |
| Whole-number identifier or count | `int` | Exact integer values |
| Very large count | `bigint` | Larger integer range |
| Price, amount, percentage | `decimal(p, s)` | Exact fixed precision |
| Short or long text | `nvarchar(n)` | Unicode text |
| Date only | `date` | No accidental time portion |
| Date and time | `datetime2` | Precise modern date/time type |
| Yes/no fact | `bit` | Stores 0, 1, or `NULL` |

`decimal(10, 2)` means up to ten digits total, with two digits after the decimal separator. It is suitable for the toy prices in `StudyDB`; it is not a universal money design. Choose precision based on the largest valid business value and its required scale.

### `NULL`: unknown, absent, or not applicable

`NULL` is a marker for missing information. It is not `0`, `''`, nor the word `'NULL'`. This changes filtering because SQL uses three-valued logic: a comparison can be true, false, or unknown. A row whose email is `NULL` does not satisfy `Email = 'ana@example.test'`, but it also does not satisfy `Email <> 'ana@example.test'`.

```sql
-- Correct: test the presence of a value.
SELECT CustomerName
FROM study.Customer
WHERE Email IS NULL;

-- Incorrect: equality does not test NULL.
SELECT CustomerName
FROM study.Customer
WHERE Email = NULL;
```

Use `NOT NULL` when the business cannot create a valid row without that attribute. Do not use an invented placeholder such as `unknown@example.test` merely to avoid `NULL`; it pretends that a value is known when it is not.

### Check yourself

1. Should an order date be `nvarchar(20)` or `date`? Why?
2. Is an empty string the same fact as an unknown email address?
3. What must a predicate use to find missing values?

<details>
<summary>Answers</summary>

1. `date`, because it carries date semantics and supports reliable date comparisons.
2. No. An empty string is a known text value with no characters; `NULL` means the value is not known or does not apply.
3. `IS NULL`.

</details>

## 3. Define structure before data

DDL (data definition language) creates or changes objects. DML (data manipulation language) works with rows. The order is important: first define the contract, then load facts that conform to it.

```sql
CREATE TABLE study.Product (
    ProductId int IDENTITY(1, 1) NOT NULL,
    ProductName nvarchar(100) NOT NULL,
    UnitPrice decimal(10, 2) NOT NULL,
    CreatedAt datetime2 NOT NULL DEFAULT sysdatetime(),
    CONSTRAINT PK_Product PRIMARY KEY (ProductId),
    CONSTRAINT CK_Product_UnitPrice CHECK (UnitPrice >= 0)
);
```

Read this definition slowly:

- `IDENTITY(1, 1)` asks SQL Server to generate values beginning at 1 and increasing by 1. It does **not** promise gap-free numbers.
- `NOT NULL` rejects missing values.
- `DEFAULT sysdatetime()` supplies a value only when an insert omits the column.
- The primary-key and check constraints protect rules at the database boundary.

The order of columns in a table is not a contract for application code. Always name columns in an `INSERT` statement.

```sql
INSERT INTO study.Product (ProductName, UnitPrice)
VALUES (N'Notebook', 12.50);
```

The `N` prefix marks a Unicode string literal. It is a useful habit when inserting into `nvarchar` columns.

> [!warning] Common Mistake
> `DROP TABLE` removes both a table definition and its data. In a learning database it can be convenient; in a shared or production database it is a destructive operation that needs deliberate change control.

## 3.5 Choose an edition for learning

Before installing SQL Server, distinguish the engine edition from the query tool. SSMS is a client application; it can connect to all three editions below. The edition is the engine's feature, capacity, and licence package.

| Edition | Licence and intended use | Main strengths | Main constraint |
| :--- | :--- | :--- | :--- |
| Express | Free; small production applications are permitted | Lightweight local database, basic T-SQL, free distribution | Capacity limits and no SQL Server Agent |
| Developer / Enterprise Developer | Free; development and testing only | Enterprise-level feature surface for learning and test | Cannot serve a production workload |
| Enterprise | Paid; production | Highest scale and Enterprise production capabilities | Requires the appropriate paid licence |

### Express is small by design

Express is enough to run the early labs: tables, constraints, DML, JOINs, aggregation, and basic indexes all work. It is a sensible choice for a small desktop application or a learner who only needs core SQL.

Do not mistake it for a full-scale test platform. In SQL Server 2025, Express is limited to the lesser of one socket or four cores, about 1.4 GB of buffer-pool memory, and 50 GB for a relational database. It also has no SQL Server Agent, so scheduled SQL Agent jobs cannot be practiced on Express. These restrictions can change across major versions; SQL Server 2022, for example, has different database-size limits.

### Developer is the recommended study environment

Developer gives a learner the Enterprise feature surface without a purchase price. It is the right default for the complete DP-800 path because later modules may need features, scale, or operational tooling that are unavailable or less representative in Express.

The trade-off is legal, not technical: Developer must be used only for development and test. A personal study laptop, a local development machine, and a disposable test VM are appropriate. A server processing a company's live orders is not.

SQL Server 2025 calls the equivalent edition **Enterprise Developer**. Earlier releases call it simply **Developer**. SQL Server 2025 also offers **Standard Developer**, which mirrors Standard Edition rather than Enterprise; this workbook's advice about "Developer" refers to Enterprise Developer/the historical Developer edition.

### Enterprise is for licensed production

Enterprise is the paid edition designed for organizations that need its production scale and Enterprise-only capabilities. It is not necessary for this study guide: Enterprise Developer lets you learn the compatible feature set. Conversely, a production environment cannot use Developer as a free replacement for Enterprise.

> [!warning] Do not choose by price alone
> Express being free does not make it equivalent to Developer, and Developer being free does not make it legal for production. Choose based on both workload requirements and licence rights.

### A simple choice

| Your situation | Recommended edition |
| :--- | :--- |
| Learn the full DP-800 path locally | Developer / Enterprise Developer |
| Learn basic T-SQL or build a tiny, limited application | Express |
| Run a real workload requiring Enterprise capabilities | Properly licensed Enterprise |

## 4. Read data in a predictable order

The most useful query shape is easy to say aloud:

```text
SELECT columns
FROM source
WHERE row conditions
GROUP BY grouping columns
HAVING group conditions
ORDER BY final order
```

You do not always use every clause. The conceptual processing order, however, explains many surprises: `WHERE` filters rows before grouping, while `ORDER BY` sorts the final result.

```sql
SELECT p.ProductName AS product_name,
       p.UnitPrice AS unit_price
FROM study.Product AS p
WHERE p.UnitPrice >= 5.00
  AND p.ProductName LIKE N'%note%'
ORDER BY p.UnitPrice DESC, p.ProductName ASC;
```

### Predicates you will use often

| Predicate | Meaning | Example |
| :--- | :--- | :--- |
| `=` / `<>` | Equal / not equal | `IsActive = 1` |
| `AND` | Both conditions must be true | price and status |
| `OR` | Either condition may be true | two cities |
| `IN` | Matches one member of a list | `Status IN ('New', 'Paid')` |
| `BETWEEN` | Inclusive lower and upper bounds | `BETWEEN 10 AND 20` |
| `LIKE` | Pattern match | `N'A%'` |
| `IS NULL` | Missing information | `Email IS NULL` |

`LIKE N'%note%'` finds text containing `note`; `%` means any number of characters and `_` means exactly one character. It is not a replacement for full-text search, which you will meet later in the guide.

Parentheses make a mixed condition unambiguous:

```sql
WHERE IsActive = 1
  AND (Email IS NULL OR Email LIKE N'%@example.test')
```

`DISTINCT` removes duplicate result combinations. If you need it unexpectedly, inspect the JOIN or data model first; it can hide an incorrect relationship predicate.

### Check yourself

Write a query that returns active customers without an email, sorted by name. Then explain why `ORDER BY` is needed even if the current output already looks alphabetical.

<details>
<summary>One answer</summary>

```sql
SELECT CustomerName
FROM study.Customer
WHERE IsActive = 1
  AND Email IS NULL
ORDER BY CustomerName;
```

Without `ORDER BY`, SQL Server does not promise a stable row order.
</details>

## 5. Combine facts with JOINs

JOINs put related rows side by side. Begin by identifying the table whose rows you want to preserve, then choose the join type.

| Join | Returns | Typical question |
| :--- | :--- | :--- |
| `INNER JOIN` | Only matches from both sides | Which customers have orders? |
| `LEFT JOIN` | All left rows; matching right rows when available | Which customers, including those with no orders? |
| `RIGHT JOIN` | All right rows | Usually rewrite as a left join for readability |
| `FULL OUTER JOIN` | Matches plus unmatched rows from both sides | Reconcile two lists |
| `CROSS JOIN` | Every left/right combination | Generate a deliberate matrix |

```sql
SELECT c.CustomerName, o.OrderDate, o.OrderTotal
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
ORDER BY c.CustomerName, o.OrderDate;
```

When Carla has no order, the `LEFT JOIN` returns Carla and fills `o.OrderDate` and `o.OrderTotal` with `NULL`. That is expected information: no matching right-side row exists.

### The filter-placement trap

Suppose you want every customer but only orders from July. This is subtly different:

```sql
-- Keeps every customer; non-July orders simply do not match.
SELECT c.CustomerName, o.OrderDate
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
   AND o.OrderDate >= '2026-07-01';

-- Removes customers without a qualifying order.
SELECT c.CustomerName, o.OrderDate
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
WHERE o.OrderDate >= '2026-07-01';
```

The second query filters after the join and rejects rows where `o.OrderDate` is `NULL`; it behaves like an inner join for that condition.

> [!warning] Common Mistake
> Never join tables merely because both have a column called `Id`. Join the documented relationship, normally foreign key to primary key.

## 6. Summarize without losing meaning

Aggregation turns many rows into a smaller summary. First state the question's grain: "one row per customer", "one row per month", or "one value for the entire database".

```sql
SELECT o.CustomerId,
       COUNT(*) AS order_count,
       SUM(o.OrderTotal) AS total_spend,
       AVG(o.OrderTotal) AS average_order
FROM study.SalesOrder AS o
GROUP BY o.CustomerId
HAVING SUM(o.OrderTotal) >= 20.00;
```

Every selected expression must either describe the group (`CustomerId`) or reduce the group (`SUM`, `COUNT`, `AVG`, `MIN`, `MAX`). SQL Server rejects a bare `OrderDate` here because one customer can have many different dates.

`COUNT(*)` counts rows. `COUNT(Email)` counts only rows where `Email` is not `NULL`. This is useful, but choose deliberately.

`COALESCE(SUM(o.OrderTotal), 0.00)` turns the `NULL` sum of a customer with no orders into an explicit zero for display. It does not change the underlying data.

### `WHERE` versus `HAVING`

Use `WHERE` for an individual order condition, such as only July orders. Use `HAVING` for a condition on the computed customer group, such as customers whose sum is at least 20.

```sql
SELECT CustomerId, SUM(OrderTotal) AS july_total
FROM study.SalesOrder
WHERE OrderDate >= '2026-07-01'
  AND OrderDate < '2026-08-01'
GROUP BY CustomerId
HAVING SUM(OrderTotal) >= 20.00;
```

The half-open date range is safer than ending at a late-night timestamp when a column includes time.

## 7. Change data safely

`INSERT`, `UPDATE`, and `DELETE` alter state. The universal safety habit is simple: turn the predicate into a `SELECT`, inspect the exact rows, then make the change in a transaction when a rollback window is useful.

```sql
BEGIN TRAN;

SELECT ProductId, ProductName, UnitPrice
FROM study.Product
WHERE ProductName = N'Pen';

UPDATE study.Product
SET UnitPrice = 2.25
WHERE ProductName = N'Pen';

SELECT ProductId, ProductName, UnitPrice
FROM study.Product
WHERE ProductName = N'Pen';

ROLLBACK;
```

`ROLLBACK` undoes the uncommitted work in this transaction. Replace it with `COMMIT` only when you have reviewed the outcome and the transaction contains exactly what you intended.

### Transactions are boundaries

A transaction groups operations that must succeed or fail together. Consider moving money from one balance to another: recording only the subtraction would leave incorrect data. Transactions are also important for concurrency, but isolation levels, blocking, and deadlocks belong to the performance section.

> [!warning] Common Mistake
> A transaction left open can lock data and block other sessions. Keep the work and the time between `BEGIN TRAN` and `COMMIT`/`ROLLBACK` short.

## 8. Put integrity rules in the database

Applications make mistakes, scripts get rerun, and new tools may write to the same database. Constraints protect the data regardless of the entry point.

| Constraint | Rule it enforces | Example |
| :--- | :--- | :--- |
| `PRIMARY KEY` | unique, non-null row identity | one `CustomerId` per customer |
| `FOREIGN KEY` | parent row must exist | order has a real customer |
| `NOT NULL` | fact is required | product name |
| `UNIQUE` | no repeated business value | email if business rules require uniqueness |
| `CHECK` | row-level predicate | price cannot be negative |
| `DEFAULT` | omitted column gets a value | creation timestamp |

```sql
ALTER TABLE study.SalesOrder
ADD CONSTRAINT FK_SalesOrder_Customer
    FOREIGN KEY (CustomerId)
    REFERENCES study.Customer(CustomerId);
```

A foreign key does not make an order mandatory for every customer. It means that *if* an order has a `CustomerId`, the referenced customer must exist. Optionality comes from whether the child column permits `NULL`, but do not make it nullable unless an order without a customer makes business sense.

Constraints reject invalid writes early. That is a feature, not an inconvenience: an error at insert time is easier to repair than corrupt data discovered months later.

## 9. Break complex queries into named steps

A subquery is nested inside another statement. It is useful when one query produces the set or value needed by another.

```sql
SELECT CustomerId, OrderTotal
FROM study.SalesOrder
WHERE OrderTotal > (
    SELECT AVG(OrderTotal)
    FROM study.SalesOrder
);
```

A CTE (common table expression) gives an intermediate query a name for the *single statement that immediately follows it*.

```sql
WITH CustomerTotals AS (
    SELECT CustomerId, SUM(OrderTotal) AS TotalSpend
    FROM study.SalesOrder
    GROUP BY CustomerId
)
SELECT c.CustomerName, ct.TotalSpend
FROM CustomerTotals AS ct
INNER JOIN study.Customer AS c
    ON c.CustomerId = ct.CustomerId
WHERE ct.TotalSpend >= 20.00;
```

The CTE has not created a table, view, or cache that you can use in the next batch. It is a readability tool. The optimizer chooses how to execute the entire statement; do not assume a CTE is automatically faster or slower than a subquery.

### Choosing a form

- Use a simple subquery when it makes the predicate immediately readable.
- Use a CTE when naming a step makes a multi-step query easier to review.
- Use a physical table only when the task truly needs persisted data; that decision is beyond this prerequisite path.

## 10. Indexes: useful copies with a cost

SQL Server stores table rows and can maintain additional structures called indexes. An index is useful when it helps locate a small relevant set instead of reading many rows. It consumes storage and must be maintained during inserts, updates, and deletes.

```sql
CREATE INDEX IX_SalesOrder_OrderDate
    ON study.SalesOrder (OrderDate);
```

This index may help date-filtered or date-ordered queries. Whether it actually helps depends on data volume, selectivity, statistics, and the rest of the query. An index on every column is not a strategy.

| Type | Beginner mental model | Important limit |
| :--- | :--- | :--- |
| Clustered index | Primary physical rowstore arrangement | One per table |
| Nonclustered index | Separate lookup structure with key values | Many are possible, but each has a cost |

Primary keys create an index by default. The exact clustered/nonclustered choice is configurable, so inspect the definition rather than assuming every primary key is clustered.

> [!note] Mental model — indexes
> An index resembles a book's index: it helps you find a topic quickly, but someone must update it when the book's contents change.

Detailed index design, included columns, columnstore, JSON indexes, and execution-plan analysis begin in the next sections.

## 11. Capstone: answer a business question

Use the `StudyDB` data to write a report with one row per customer. It must show the customer name, number of orders, total spend, and include customers who have never ordered. Sort highest spend first and display zero rather than `NULL` for no orders.

<details>
<summary>One solution</summary>

```sql
SELECT c.CustomerName,
       COUNT(o.SalesOrderId) AS order_count,
       COALESCE(SUM(o.OrderTotal), 0.00) AS total_spend
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
GROUP BY c.CustomerName
ORDER BY total_spend DESC, c.CustomerName ASC;
```

`LEFT JOIN` retains every customer; `COUNT(o.SalesOrderId)` returns zero for a customer with no matching orders; `SUM` needs `COALESCE` because the sum of no matched values is `NULL`.
</details>

## 12. Before moving on

You do not need to memorize every keyword. You do need to be able to explain the choices in your code and detect unsafe or ambiguous queries.

- [ ] I can distinguish an instance, database, schema, table, column, and row.
- [ ] I can choose basic types and handle `NULL` deliberately.
- [ ] I can create a table, insert rows, and read a filtered, ordered result.
- [ ] I can select an appropriate JOIN and explain its unmatched rows.
- [ ] I can state the grouping level of an aggregate query and choose `WHERE` or `HAVING`.
- [ ] I preview DML and know when to use `ROLLBACK`.
- [ ] I can explain how keys and constraints protect data.
- [ ] I know that indexes trade maintenance cost for potential read efficiency.

If any answer is uncertain, repeat the relevant lab and alter the sample data to observe the result. When the checklist feels comfortable, continue to [01 — Database Objects](../01-database-objects/database-objects.md).

## Related Topics

- [Part 0 learning path](./fundamentals.md)
- [Database Objects](../01-database-objects/database-objects.md)
- [Advanced T-SQL](../03-advanced-tsql/advanced-tsql.md)

---

**[← Back to Part 0](./fundamentals.md) | [Start Section 01 →](../01-database-objects/database-objects.md)**
