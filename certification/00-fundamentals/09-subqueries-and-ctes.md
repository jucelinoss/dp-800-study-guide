---
title: CTEs and Temporary Query Structures
type: topic
tags: [sql-server, cte, temp-table, table-variable, derived-table, fundamentals]
---

# CTEs and Temporary Query Structures

## Overview

When a query needs an intermediate result — to simplify a multi-step calculation, reuse rows across statements, or break a complex problem into readable parts — SQL Server offers several temporary structures. Choosing the right one depends on scope, reusability, and performance characteristics.

> [!abstract]
>
> - Use a **derived table** (subquery in `FROM`) for a one-step inline result.
> - Use a **CTE** to name a logical step and improve readability in a single statement.
> - Use a **local temporary table** when several statements need the same intermediate rows.
> - Use a **table variable** for a small, scoped procedural dataset; neither is a performance shortcut.

> [!tip] What the Exam Tests
> Subqueries (scalar, multi-valued), `EXISTS`, `NOT IN`, and set operators are covered in [Lesson 04](./04-select-and-filter.md). This lesson builds the bridge to advanced query design: recursive CTEs, `APPLY`, and complex analytic patterns in Section 03.

---

## Derived tables

A **derived table** is a subquery in the `FROM` clause. It must have an alias and is visible only in the statement that defines it.

```sql
-- Derived table: subquery in FROM with required alias
SELECT dt.ProductID, dt.TotalSold
FROM (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
) AS dt
WHERE dt.TotalSold > 100;
```

**Limitations:**

- Cannot be referenced more than once in the same statement.
- Cannot be used in recursive queries.
- Nesting derived tables reduces readability.

```sql
-- Nested derived tables (hard to read — prefer CTE)
SELECT SalesOrderID, TotalDue
FROM (
    SELECT SalesOrderID, TotalDue,
           ROW_NUMBER() OVER (ORDER BY TotalDue DESC) AS rn
    FROM Sales.SalesOrderHeader
) AS ranked
WHERE ranked.rn <= 5;
```

## Common Table Expressions (CTEs)

A CTE gives a query result a temporary name for the statement that follows it. Unlike a derived table, a CTE can be referenced multiple times in the same statement and supports recursion.

```sql
-- Simple CTE
WITH ProductSales AS (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
)
SELECT p.Name, ps.TotalSold
FROM ProductSales AS ps
INNER JOIN Production.Product AS p ON p.ProductID = ps.ProductID
WHERE ps.TotalSold > 100
ORDER BY ps.TotalSold DESC;
```

### Multiple CTEs

Separate CTE definitions with a comma. Each CTE can reference the ones defined before it.

```sql
WITH
ProductSales AS (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
),
HighSellers AS (
    SELECT ProductID, TotalSold
    FROM ProductSales
    WHERE TotalSold > 1000
)
SELECT p.Name, hs.TotalSold
FROM HighSellers AS hs
INNER JOIN Production.Product AS p ON p.ProductID = hs.ProductID
ORDER BY hs.TotalSold DESC;
```

> [!warning] Common Mistake
> A CTE is not a temporary table — it is a **logical expression** that the optimizer inlines into the outer query. Referencing the same CTE twice in a statement may cause the underlying query to execute twice (no automatic materialization).

## CTEs vs derived tables

The same business question expressed both ways:

```sql
-- Derived table style
SELECT dt.CustomerID, dt.TotalSpend
FROM (
    SELECT CustomerID, SUM(TotalDue) AS TotalSpend
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
) AS dt
WHERE dt.TotalSpend > 5000;

-- CTE style
WITH CustomerSpend AS (
    SELECT CustomerID, SUM(TotalDue) AS TotalSpend
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
)
SELECT CustomerID, TotalSpend
FROM CustomerSpend
WHERE TotalSpend > 5000;
```

**When to choose which:**

| Factor | CTE | Derived table |
| :--- | :--- | :--- |
| Readability | Clearer, especially with multiple steps | Can become deeply nested |
| Multiple references | Can reference the same CTE more than once | Must repeat the subquery |
| Recursion | Supports recursive queries | No recursion |
| Scope | Single statement | Single statement |

## Local temp tables (#Temp)

A local temporary table is a physical table in `tempdb` that persists for the duration of the session. It supports indexes, statistics, and all T-SQL DML.

```sql
-- Create a local temp table with a primary key
CREATE TABLE #HighValueOrders (
    SalesOrderID INT NOT NULL PRIMARY KEY,
    TotalDue     DECIMAL(18,2) NOT NULL
);

-- Insert into it
INSERT INTO #HighValueOrders (SalesOrderID, TotalDue)
SELECT SalesOrderID, TotalDue
FROM Sales.SalesOrderHeader
WHERE TotalDue > 5000;

-- Use it in subsequent statements
SELECT COUNT(*) AS HighValueCount FROM #HighValueOrders;

-- Clean up explicitly
DROP TABLE IF EXISTS #HighValueOrders;
```

**Characteristics:**

- Visible only to the creating session (no other sessions can see `#HighValueOrders`).
- Automatically dropped when the session ends, but explicitly dropping is better practice.
- Can have indexes, constraints, and statistics like a regular table.
- Supports `INSERT`, `UPDATE`, `DELETE`, `MERGE`.

> [!warning] Common Mistake
> A `#TempTable` is session-scoped. Avoid `##GlobalTempTable` (double `#`) by default — global temp tables are visible to all sessions and create naming collisions and hidden dependencies.

## Table variables (@TableVar)

A table variable is scoped to the batch, procedure, or function that declares it. It is lighter than a temp table but has limitations.

```sql
DECLARE @SelectedProducts TABLE (
    ProductID INT NOT NULL PRIMARY KEY,
    ListPrice DECIMAL(18,2) NOT NULL
);

INSERT INTO @SelectedProducts (ProductID, ListPrice)
SELECT ProductID, ListPrice
FROM Production.Product
WHERE ListPrice > 500;

SELECT COUNT(*) AS ExpensiveProducts FROM @SelectedProducts;
```

**Limitations vs temp tables:**

| Feature | #TempTable | @TableVariable |
| :--- | :--- | :--- |
| Scope | Session | Batch / procedure |
| Statistics | Yes (can rebuild) | No (cardinality estimate = 1 row) |
| Indexes | Yes (after creation) | Only primary key / unique at declaration |
| Transactions | Logged (can rollback) | Logged (but less logging in tempdb) |
| When to use | Larger datasets, many rows | Small lookup sets, procedural scope |

> [!note] Mental model — CTE = spreadsheet formula, #Temp = physical scratchpad
> A CTE is like a named formula in a spreadsheet: it recalculates each time you reference it. A temp table is like writing intermediate results onto a scrap of paper that sits on your desk (session) until you clean it up.

## Choosing the right structure

| Need | Choose | Reason |
| :--- | :--- | :--- |
| Name one query step in one statement | CTE | Cleanest syntax, no persistence |
| Same intermediate result used 2+ times in one query | CTE | Reference by name, but beware re-execution |
| Reuse rows across statements in same session | `#TempTable` | Persists between batches |
| Small lookup set in a procedure | `@TableVariable` | Limited scope, auto-cleanup |
| Recursive hierarchy (org chart, BOM) | Recursive CTE | Only recursive option in T-SQL |
| Pass table-valued parameter to a function | `@TableVariable` | Required for TVP |

```sql
-- When you need BOTH a CTE (readability) and persistence (reuse):
-- 1. Define the logic in a CTE
-- 2. Insert results into a temp table
-- 3. Query the temp table multiple times

WITH ProductSales AS (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
)
SELECT p.ProductID, p.Name, ps.TotalSold
INTO #ProductSalesReport
FROM ProductSales AS ps
INNER JOIN Production.Product AS p ON p.ProductID = ps.ProductID;

-- Now reuse #ProductSalesReport across multiple queries
SELECT COUNT(*) FROM #ProductSalesReport WHERE TotalSold > 100;
SELECT AVG(TotalSold) FROM #ProductSalesReport;

DROP TABLE IF EXISTS #ProductSalesReport;
```

## Check yourself

### 1. CTE or derived table?

Write a query that returns the top 5 products by total sales amount using a CTE. Use the AdventureWorks schema: `Sales.SalesOrderDetail` (UnitPrice, OrderQty) and `Production.Product` (Name).

> [!success]- Answer
>
> ```sql
> WITH ProductRevenue AS (
>     SELECT sod.ProductID,
>            SUM(sod.UnitPrice * sod.OrderQty) AS Revenue
>     FROM Sales.SalesOrderDetail AS sod
>     GROUP BY sod.ProductID
> )
> SELECT TOP 5 p.Name, pr.Revenue
> FROM ProductRevenue AS pr
> INNER JOIN Production.Product AS p ON p.ProductID = pr.ProductID
> ORDER BY pr.Revenue DESC;
> ```

### 2. Multiple CTEs

You need orders with total > 5000 AND customers who placed those orders. Write a query using two CTEs (one for high-value orders, one joining to Customer).

> [!success]- Answer
>
> ```sql
> WITH HighValueOrders AS (
>     SELECT SalesOrderID, CustomerID, TotalDue
>     FROM Sales.SalesOrderHeader
>     WHERE TotalDue > 5000
> ),
> CustomerHighValue AS (
>     SELECT c.CustomerID, c.AccountNumber, hvo.TotalDue
>     FROM Sales.Customer AS c
>     INNER JOIN HighValueOrders AS hvo ON hvo.CustomerID = c.CustomerID
> )
> SELECT * FROM CustomerHighValue
> ORDER BY TotalDue DESC;
> ```

### 3. #Temp vs @TableVar

When would you choose a local temporary table over a table variable?

> [!success]- Answer
> Choose `#TempTable` when: (a) the intermediate result has more than ~100 rows and needs accurate statistics for the optimizer; (b) you need secondary indexes; (c) the data must persist across multiple batches in the same session. Choose `@TableVariable` for small lookup sets (10–50 rows) within a single procedure where auto-cleanup is convenient.

### 4. CTE materialization

A CTE is referenced twice in a query. Does SQL Server materialize the result once or execute it twice?

> [!success]- Answer
> SQL Server may execute the CTE definition **twice** (once per reference). A CTE is a logical expression, not a materialized result. If the definition is expensive and referenced multiple times, consider inserting into a `#TempTable` instead.

## Next steps

- **Recursive CTEs** (Section 03) — navigate hierarchies like org charts and bill-of-materials.
- **`APPLY` operator** (Section 03) — apply a right-side expression to each row of the left input.
- **Views and table-valued functions** (Section 02) — encapsulate CTE-like logic into reusable database objects.

## Use Cases

- Decompose a complex analytic query into named, readable steps.
- Prepare intermediate datasets for multiple follow-up queries in a session.
- Hold a small reference set (currency codes, status lookups) in a procedure.
- Generate a reporting summary from detailed transaction data.

## Common Issues & Errors

> [!warning] Common Mistake
> A CTE must be immediately followed by the statement that uses it. Its name is not available to the next batch or to a separate `GO` boundary.

> [!warning] Common Mistake
> `#TempTable` is visible only in its creating session. Avoid `##GlobalTempTable` — shared scope creates collisions and hidden dependencies.

> [!warning] Common Mistake
> Table variables have **no statistics**. For large datasets (1000+ rows), the optimizer assumes 1 row, which can lead to poor query plans. Use `#TempTable` for larger intermediate results.

## Best Practices

- Use names that describe the result, not the implementation (`ProductSales`, not `CTE1`).
- Choose the clearest form first, then measure before changing a query for performance.
- Explicitly `DROP TABLE` temp tables when they are no longer needed.
- For reporting queries with multiple references to the same subquery, prefer inserting into a temp table to avoid repeated execution.

## Exam Tips

> [!tip] Exam Tips
> A CTE and a derived table are both logical query expressions — neither persists data by itself. A CTE can be recursive; a derived table cannot. Temp tables and table variables give intermediate rows a longer, scoped lifetime. Know the scope boundaries: CTE = one statement, #Temp = session, @TableVar = batch/procedure.

## Key Takeaways

- CTEs name one-statement logic; temp tables and table variables give intermediate rows a longer, scoped lifetime.
- Use the smallest structure that expresses the task clearly.
- CTEs are not materialized by default — referencing a CTE twice may execute its definition twice.
- Table variables lack statistics; use temp tables for larger intermediate datasets.

## Related Topics

- [SELECT, filters, subqueries, and set operations](./04-select-and-filter.md)
- [Advanced T-SQL](../03-advanced-tsql/advanced-tsql.md)
- [Performance Optimization](../06-performance-optimization/performance-optimization.md)
- [Database Objects](../01-database-objects/database-objects.md)

## Official Documentation

- [WITH common table expression](https://learn.microsoft.com/sql/t-sql/queries/with-common-table-expression-transact-sql)
- [CREATE TABLE (temporary)](https://learn.microsoft.com/sql/t-sql/statements/create-table-transact-sql)
- [Table variables](https://learn.microsoft.com/sql/t-sql/language-elements/declare-local-variable-transact-sql)
- [Derived tables](https://learn.microsoft.com/sql/t-sql/queries/from-using-pivotal-and-unpivotal)

---

**[← Previous](./08-integrity-rules.md) | [↑ Back to Section](./fundamentals.md) | [Lab: Index Introduction](../../practice/labs/00-fundamentals/09-index-introduction.sql) | [Next →](./10-index-fundamentals.md)**
