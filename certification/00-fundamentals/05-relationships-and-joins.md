---
title: Relationships and JOINs
type: topic
tags: [sql-server, joins, relationships, foreign-key, fundamentals]
---

# Relationships and JOINs

## Overview

Relationships define which facts belong together; JOINs turn those related rows into one query result. Good JOINs start from a known cardinality and a deliberate choice about which unmatched rows must survive.

> [!abstract]
>
> - Join parent and child tables through their documented key relationship.
> - Choose `INNER`, `LEFT`, `RIGHT`, `FULL`, or `CROSS JOIN` from the required result, not habit.
> - Learn the `ON` versus `WHERE` distinction, `NULL` behavior, join multiplication, and multi-join traps.

> [!tip] What the Exam Tests
> Later DP-800 topics use JOINs in views, functions, security predicates, embedding-maintenance queries, and performance analysis. The crucial foundation is predicting row preservation and cardinality.

---

## Start with the relationship, not the syntax

The `StudyDB` model has a one-to-many relationship: one customer can have many orders; each order belongs to one customer.

```text
study.Customer                         study.SalesOrder
-------------------------------        --------------------------------
CustomerId (primary key)          1 ──< CustomerId (foreign key)
CustomerName                              SalesOrderId (primary key)
                                          OrderDate
                                          OrderTotal
```

The join predicate is therefore `o.CustomerId = c.CustomerId`. Do not join merely because two columns have similar names or the same data type. A correct predicate follows a business relationship and normally joins a foreign key to a primary or unique key.

```sql
SELECT c.CustomerName, o.SalesOrderId, o.OrderDate, o.OrderTotal
FROM study.Customer AS c
INNER JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId;
```

Aliases are not cosmetic. They make column ownership visible and avoid ambiguous names such as `CustomerId` appearing in both tables.

## The five basic JOIN types

| JOIN | Keeps matching rows | Keeps unmatched left rows | Keeps unmatched right rows | Typical question |
| :--- | :---: | :---: | :---: | :--- |
| `INNER JOIN` | Yes | No | No | Which customers have orders? |
| `LEFT [OUTER] JOIN` | Yes | Yes | No | Show every customer and any orders |
| `RIGHT [OUTER] JOIN` | Yes | No | Yes | Same idea, but preserve right table |
| `FULL [OUTER] JOIN` | Yes | Yes | Yes | Reconcile two lists |
| `CROSS JOIN` | Every combination | N/A | N/A | Generate a deliberate matrix |

`OUTER` is optional syntax: `LEFT JOIN` and `LEFT OUTER JOIN` mean the same thing. Prefer `LEFT JOIN` in new code because it reads naturally from the table you want to preserve.

### INNER JOIN: only matching facts

```sql
SELECT c.CustomerName, o.OrderDate, o.OrderTotal
FROM study.Customer AS c
INNER JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId;
```

If Carla has no order, she is not in this result. If an order's `CustomerId` cannot match a customer, it is not in this result either. With a foreign key that invalid child case should not occur, but an inner join still expresses the result rule clearly: only pairs that match.

### LEFT JOIN: preserve the question's starting set

```sql
SELECT c.CustomerName, o.OrderDate, o.OrderTotal
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
ORDER BY c.CustomerName, o.OrderDate;
```

Carla now appears once with `NULL` order columns. This is not a broken row; it communicates that no related order exists. Start from the entity the report must preserve, then put it on the left.

### RIGHT JOIN: legal but usually less readable

A right join preserves the right table. It can always be rewritten as a left join by swapping table order:

```sql
-- Prefer the equivalent LEFT JOIN form in new queries.
SELECT c.CustomerName, o.OrderDate
FROM study.SalesOrder AS o
LEFT JOIN study.Customer AS c
    ON c.CustomerId = o.CustomerId;
```

This convention makes multi-join queries easier to read because the preserved table appears first.

### FULL JOIN: find differences on both sides

`FULL JOIN` returns matches plus unmatched rows from both sources. It is valuable for reconciliation, such as comparing imported customer IDs with master customer IDs. It is less common in ordinary parent-child reports because they normally have one clear preserved side.

```sql
SELECT c.CustomerId AS customer_id,
       o.CustomerId AS order_customer_id
FROM study.Customer AS c
FULL JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId;
```

### CROSS JOIN: intentional Cartesian product

`CROSS JOIN` returns every left/right combination. If there are 3 colors and 4 sizes, it returns 12 rows — useful for a product-variant grid.

```sql
SELECT c.CustomerName, p.ProductName
FROM study.Customer AS c
CROSS JOIN study.Product AS p;
```

> [!warning] Common Mistake
> The old comma-separated `FROM Customer, Product` syntax can accidentally create a cross join when a predicate is forgotten. Use explicit `JOIN ... ON` syntax so relationships are visible.

## `ON` versus `WHERE`: the most important outer-join rule

`ON` says how rows are related and, for an outer join, which rows on the optional side count as a match. `WHERE` filters rows *after* the join result has been formed. They can look interchangeable for inner joins, but they are not interchangeable for outer joins.

Suppose you want every customer, with only July orders when they exist:

```sql
-- Correct: every customer is preserved.
SELECT c.CustomerName, o.OrderDate
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
   AND o.OrderDate >= '2026-07-01'
   AND o.OrderDate <  '2026-08-01';
```

Here the date predicate decides whether an order matches. A customer without a July order still has a preserved left-side row with `NULL` order columns.

```sql
-- Different result: customers without a July order disappear.
SELECT c.CustomerName, o.OrderDate
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
WHERE o.OrderDate >= '2026-07-01'
  AND o.OrderDate <  '2026-08-01';
```

The `WHERE` predicate rejects the `NULL` values introduced for unmatched orders, effectively turning this result into an inner join for the date condition.

> [!note] Rule of thumb
> Put relationship conditions in `ON`. Put filters for the preserved table in `WHERE`. Put filters for an optional table in `ON` when unmatched preserved rows must remain visible.

## `NULL` in JOIN predicates

An equality comparison involving `NULL` is unknown, not true. `NULL = NULL` does not match in a normal join predicate. This is usually correct: an unknown customer ID should not be treated as the same known customer.

```sql
-- Do not do this to force NULLs to match.
-- ON ISNULL(a.Code, 0) = ISNULL(b.Code, 0)
```

Applying a function to join columns can change semantics and make index use harder. First ask whether a nullable relationship is a modelling problem. If a special null-equals-null rule is truly required, express it explicitly and test it:

```sql
ON a.Code = b.Code
OR (a.Code IS NULL AND b.Code IS NULL)
```

This is a specialized business rule, not a default join pattern.

## Cardinality: predict the number of rows

JOINs combine rows; they do not automatically preserve a one-row-per-customer shape. Predict cardinality before trusting the result.

| Relationship | Expected result behavior |
| :--- | :--- |
| One customer → many orders | Customer repeats once per order |
| One order → one customer | Each order joins one customer |
| Many-to-many without proper bridge predicate | Rows can multiply unexpectedly |
| Duplicate parent key (bad data/model) | Child rows multiply for each duplicate parent |

```sql
SELECT c.CustomerName, o.SalesOrderId
FROM study.Customer AS c
INNER JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId;
```

If Ana has two orders, Ana should appear twice. That is not a duplicate error; the query's grain is **one row per order**. If the required grain is one row per customer, aggregate orders first or use `EXISTS` when only existence matters.

```sql
SELECT c.CustomerName, SUM(o.OrderTotal) AS total_spend
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
GROUP BY c.CustomerName;
```

Do not apply `DISTINCT` merely to conceal unexpected multiplication. Find the relationship and missing predicate that caused it.

## Multiple JOINs: each result feeds the next

Conceptually, a multi-join query combines two sources, then combines that result with the next source. Mixing outer and inner joins can unexpectedly discard rows preserved earlier.

```sql
-- A customer with no order can disappear at the second INNER JOIN.
SELECT c.CustomerName, o.SalesOrderId, p.ProductName
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
INNER JOIN study.Product AS p
    ON p.ProductId = o.SalesOrderId; -- illustrative only; use the real key in a real model
```

The inner join needs a non-null matching value from `o`; therefore the null-extended rows from the left join do not survive. If the report must retain every customer, the later optional relationship must also be left-joined, or the inner portion must be grouped separately before joining it to customers.

```sql
SELECT c.CustomerName, o.SalesOrderId
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId;
```

When writing three or more joins, state the desired grain and preserved table in a comment or in your own words before adding syntax. This catches most outer-join errors.

## Joins, `EXISTS`, and set operators

Several constructs can answer related questions, but their outputs differ.

| Need | Prefer | Why |
| :--- | :--- | :--- |
| Show columns from both entities | JOIN | Produces combined rows |
| Find customers with at least one order | `EXISTS` | Avoids repeating customer rows |
| Find customers with no order | `NOT EXISTS` or `EXCEPT` | Expresses absence clearly |
| Compare two compatible lists | `INTERSECT` / `EXCEPT` | Compares result rows, not side-by-side columns |

```sql
-- One row per qualifying customer, regardless of how many orders exist.
SELECT c.CustomerName
FROM study.Customer AS c
WHERE EXISTS (
    SELECT 1
    FROM study.SalesOrder AS o
    WHERE o.CustomerId = c.CustomerId
);
```

The subquery and set-operator mechanics are covered in [Lesson 04](./04-select-and-filter.md); this comparison helps you choose the correct result shape.

## Foreign keys and indexes

A foreign key protects referential integrity: it prevents an order from referring to a customer that does not exist. It does **not** automatically create an index on the child key column in SQL Server.

That is intentional. An index has write and storage costs, and the right choice depends on real JOIN, filter, and delete/update patterns. For a frequently queried `SalesOrder.CustomerId`, an index is often useful; design and measurement are covered in [Index fundamentals](./10-index-fundamentals.md) and the performance module.

## Practice questions

### 1. Preserving unmatched rows

Which JOIN returns every customer, including customers who have no orders?

A. `INNER JOIN`<br>
B. `LEFT JOIN` with `Customer` on the left<br>
C. `RIGHT JOIN` with `Customer` on the left<br>
D. `CROSS JOIN`

> [!success]- Answer
> **B.** A left join preserves every row from its left input. Place `Customer` on the left when customers are the required starting set.

### 2. Filter placement

You need every customer, but only orders after July 1 when present. Where should the order-date condition go?

A. In `WHERE` only<br>
B. In the `ON` clause of the `LEFT JOIN`<br>
C. In `ORDER BY`<br>
D. It does not matter

> [!success]- Answer
> **B.** A right-side filter in `ON` controls matches while preserving unmatched left-side customers. In `WHERE`, it removes null-extended rows.

### 3. Unexpected row counts

Ana has three orders. A customer-to-order inner join returns Ana three times. What is the most likely explanation?

A. SQL Server duplicated Ana by error<br>
B. The query grain is one row per order<br>
C. The primary key is necessarily broken<br>
D. `DISTINCT` must always be added

> [!success]- Answer
> **B.** The one-to-many relationship repeats the one-side customer for each matching many-side order. Aggregate or use `EXISTS` only if the desired result grain is one row per customer.

## Use Cases

- Display order facts beside customer facts.
- Find entities with or without related rows.
- Reconcile two lists with a full join or set operator.
- Build a report that preserves a parent entity even when children are absent.

## Common Issues & Errors

> [!warning] Common Mistake
> Forgetting an `ON` predicate or joining on non-unique unrelated columns can create a Cartesian multiplication. Verify the expected cardinality before running a query on large tables.

> [!warning] Common Mistake
> A `WHERE` condition on the optional side of a `LEFT JOIN` can undo the outer join. Move that condition to `ON` when preserved unmatched rows are required.

## Best Practices

- Use explicit ANSI `JOIN ... ON` syntax and meaningful aliases.
- Join documented primary/unique keys to foreign keys.
- State the intended result grain before writing the query.
- Prefer left joins over right joins for consistent reading direction.
- Avoid functions on join columns unless their semantics and performance impact are understood.

## Exam Tips

> [!tip] Exam Tips
> `INNER JOIN` preserves only matches; `LEFT JOIN` preserves the left input; `FULL JOIN` preserves both. Foreign keys enforce valid parent references but do not automatically index the child key. In an outer join, `ON` and `WHERE` have different row-preservation effects.

## Key Takeaways

- A correct JOIN begins with a correct relationship and expected cardinality.
- JOIN type decides which unmatched rows survive.
- `ON` defines matches; `WHERE` filters the completed join result.
- One-to-many relationships naturally repeat the one-side row at the child-row grain.

## Related Topics

- [Relational model and data types](./02-relational-model-and-data-types.md)
- [SELECT, filters, subqueries, and set operations](./04-select-and-filter.md)
- [Aggregation and grouping](./06-aggregation-and-grouping.md)
- [Index fundamentals](./10-index-fundamentals.md)

## Official Documentation

- [FROM and JOIN](https://learn.microsoft.com/sql/t-sql/queries/from-transact-sql)
- [Primary and foreign key constraints](https://learn.microsoft.com/sql/relational-databases/tables/primary-and-foreign-key-constraints)

---

**[← Previous](./04-select-and-filter.md) | [↑ Back to Section](./fundamentals.md) | [Lab: Aggregation](../../practice/labs/00-fundamentals/05-aggregation.sql) | [Next →](./06-aggregation-and-grouping.md)**
