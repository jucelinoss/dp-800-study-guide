---
title: Aggregation and Grouping
type: topic
tags: [sql-server, group-by, aggregate, fundamentals]
---

# Aggregation and Grouping

## Overview

Aggregate functions summarize multiple rows into a single value. `GROUP BY` defines the grouping grain — the level at which each summary is calculated — while `HAVING` filters groups after aggregation.

> [!abstract]
>
> - `COUNT`, `SUM`, `AVG`, `MIN`, and `MAX` each handle `NULL` values differently.
> - Every column in `SELECT` that is not an aggregate must appear in `GROUP BY`.
> - `WHERE` filters rows before grouping; `HAVING` filters groups after grouping.
> - Conditional aggregation with `CASE` avoids multiple passes over the same data.

> [!tip] What the Exam Tests
> Aggregation is the foundation for window functions, analytic queries, and reporting patterns tested throughout the DP-800 exam. Understand grain, `NULL` behavior, and the `WHERE`/`HAVING` distinction before moving to advanced topics.

---

## The aggregate functions

SQL Server provides five basic aggregate functions. Every one ignores `NULL` values except `COUNT(*)`, which counts rows regardless of `NULL` content.

| Function | Syntax example | What it returns | NULL behavior |
| :--- | :--- | :--- | :--- |
| `COUNT(*)` | `COUNT(*)` | Number of input rows | Counts all rows |
| `COUNT(column)` | `COUNT(ShipDate)` | Number of non-null values in the column | Ignores `NULL` |
| `COUNT(DISTINCT column)` | `COUNT(DISTINCT CustomerID)` | Number of distinct non-null values | Ignores `NULL` |
| `SUM` | `SUM(TotalDue)` | Sum of non-null values | Ignores `NULL`; empty set returns `NULL` |
| `AVG` | `AVG(TotalDue)` | Mean of non-null values | Ignores `NULL`; empty set returns `NULL` |
| `MIN` | `MIN(OrderDate)` | Lowest (earliest / smallest) value | Ignores `NULL` |
| `MAX` | `MAX(OrderDate)` | Highest (latest / largest) value | Ignores `NULL` |

```sql
-- Basic aggregates over SalesOrderHeader (~31k rows)
SELECT COUNT(*)              AS AllRows,
       COUNT(ShipDate)       AS ShippedRows,
       COUNT(DISTINCT CustomerID) AS UniqueCustomers,
       MIN(TotalDue)         AS SmallestOrder,
       MAX(TotalDue)         AS LargestOrder,
       AVG(TotalDue)         AS AvgOrderValue,
       SUM(TotalDue)         AS GrandTotal
FROM Sales.SalesOrderHeader;
```

> [!note] `COUNT_BIG`
> SQL Server also offers `COUNT_BIG`, which returns `bigint` instead of `int`. Use it when row counts may exceed 2.1 billion. The syntax and `NULL` behavior are identical to `COUNT`.

## GROUP BY and result grain

### One row per what?

Before writing a `GROUP BY`, complete the sentence: **"I need one row per \_\_\_\_."** The answer defines the grouping set.

| Question | Grain | GROUP BY |
| :--- | :--- | :--- |
| "Total sales per customer" | One row per customer | `GROUP BY CustomerID` |
| "Average price per product category" | One row per category | `GROUP BY Category` |
| "Order count per year" | One row per year | `GROUP BY YEAR(OrderDate)` |

### Composite GROUP BY

When you group by more than one expression, the grain becomes **one row per unique combination** of those expressions.

```sql
-- One row per year + territory combination
SELECT YEAR(soh.OrderDate)          AS OrderYear,
       st.Name                      AS Territory,
       COUNT(soh.SalesOrderID)      AS OrderCount,
       SUM(soh.TotalDue)            AS TotalSales
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c         ON c.CustomerID = soh.CustomerID
INNER JOIN Sales.SalesTerritory AS st  ON st.TerritoryID = c.TerritoryID
GROUP BY YEAR(soh.OrderDate), st.Name
ORDER BY OrderYear, TotalSales DESC;
```

> [!warning] Common Mistake
> Adding a non-aggregated column to the `SELECT` list without including it in `GROUP BY` raises an error. Example: adding `OrderDate` to a customer-level query fails because one customer can have many dates. Either change the grain or use `MIN(OrderDate)` / `MAX(OrderDate)`.

### GROUP BY with expressions

SQL Server allows grouping by expressions such as `YEAR(OrderDate)` or `LEFT(ProductNumber, 2)`, not just bare column names. The same expression must appear in `SELECT` for readability.

```sql
-- Group by a calculated expression
SELECT LEFT(ProductNumber, 2) AS ProductSeries,
       COUNT(*)               AS ProductCount,
       AVG(ListPrice)         AS AvgPrice
FROM Production.Product
GROUP BY LEFT(ProductNumber, 2)
ORDER BY ProductSeries;
```

## DISTINCT vs GROUP BY

Both `DISTINCT` and `GROUP BY` can eliminate duplicate rows, but they serve different purposes.

| Purpose | Use |
| :--- | :--- |
| Remove duplicates without aggregation | `SELECT DISTINCT` |
| Summarize groups with aggregates | `GROUP BY` |
| List unique combinations | `SELECT DISTINCT` or `GROUP BY` (style preference) |

```sql
-- DISTINCT: list unique combinations only
SELECT DISTINCT CustomerID, TerritoryID
FROM Sales.Customer;

-- GROUP BY: same unique combinations, but allows aggregates
SELECT CustomerID, TerritoryID, COUNT(*) AS RowCount
FROM Sales.Customer
GROUP BY CustomerID, TerritoryID;
```

`DISTINCT` does not aggregate. If you need `SUM`, `AVG`, or `COUNT` per group, you must use `GROUP BY`.

## WHERE vs HAVING

The logical query processing order is:

1. `FROM` / `JOIN`
2. `WHERE`
3. `GROUP BY`
4. `HAVING`
5. `SELECT`
6. `ORDER BY`

`WHERE` filters individual rows **before** grouping. `HAVING` filters groups **after** aggregation. Filtering early with `WHERE` is clearer and usually reduces work.

```sql
-- WHERE filters rows, HAVING filters groups
SELECT CustomerID,
       COUNT(*) AS OrderCount,
       SUM(TotalDue) AS TotalSpend
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-01-01'          -- discard old rows before grouping
  AND OrderDate < '2014-01-01'
GROUP BY CustomerID
HAVING SUM(TotalDue) >= 1000;           -- keep only high-spending customers
```

> [!note] Mental model — grain
> Think of grain as the answer to: "What does one row in my result represent?" Before writing `GROUP BY`, say it aloud: "One row per \_\_\_\_." This habit prevents many aggregation errors.

## Conditional aggregation

Conditional aggregation uses `CASE` expressions inside aggregate functions to count or sum rows that satisfy a condition — all in a single pass over the data.

```sql
-- Conditional aggregation: compare methods
SELECT CustomerID,
       COUNT(*)                                            AS AllOrders,
       SUM(CASE WHEN TotalDue > 1000 THEN 1 ELSE 0 END)   AS LargeOrders,
       SUM(CASE WHEN TotalDue > 1000 THEN TotalDue ELSE 0 END) AS LargeOrdersTotal,
       AVG(CASE WHEN TotalDue > 1000 THEN TotalDue END)   AS LargeOrdersAvg
FROM Sales.SalesOrderHeader
GROUP BY CustomerID;
```

Compare this with the alternative: a `WHERE` clause plus a separate query for each condition. Conditional aggregation is more efficient because it scans the data once.

> [!tip]
> `CASE` is an expression, not a control-flow statement. Inside an aggregate, `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` acts as a conditional counter.

## Common aggregation pitfalls

### 1. NULL in SUM/AVG

`SUM` and `AVG` ignore `NULL` values, but they do not treat them as zero. If all rows in a group have `NULL`, the result is `NULL`, not zero.

```sql
SELECT CustomerID,
       SUM(TotalDue) AS TotalSpend,          -- NULL if no rows
       COALESCE(SUM(TotalDue), 0.00) AS TotalSpendSafe
FROM Sales.SalesOrderHeader
GROUP BY CustomerID;
```

### 2. COUNT(*) vs COUNT(column)

`COUNT(*)` counts rows. `COUNT(column)` counts non-null values. They return different numbers when the column is nullable.

```sql
SELECT COUNT(*)       AS AllRows,         -- 31465
       COUNT(ShipDate) AS WithShipDate,    -- fewer, because NULL ShipDate exists
       COUNT(CustomerID) AS WithCustomerID -- same as COUNT(*) since CustomerID is NOT NULL
FROM Sales.SalesOrderHeader;
```

### 3. Non-aggregated column without GROUP BY

A `SELECT` list with aggregates and bare columns without `GROUP BY` is allowed only when all bare columns are functionally dependent on the grouping — but SQL Server generally does not detect functional dependence. Add every non-aggregated column to `GROUP BY`.

```sql
-- WRONG: OrderDate is not in GROUP BY and not aggregated
-- SELECT CustomerID, OrderDate, SUM(TotalDue)
-- FROM Sales.SalesOrderHeader
-- GROUP BY CustomerID;

-- RIGHT: either aggregate the date or include it in GROUP BY
SELECT CustomerID,
       MAX(OrderDate) AS LastOrderDate,
       SUM(TotalDue) AS TotalSpend
FROM Sales.SalesOrderHeader
GROUP BY CustomerID;
```

### 4. LEFT JOIN + aggregation

When aggregating after a `LEFT JOIN`, remember that the non-preserved side produces `NULL`-extended rows for unmatched parents. `COUNT(ChildID)` correctly returns zero; `COUNT(*)` counts the null-extended row as one.

```sql
-- Correct: count orders per customer (including zero)
SELECT c.CustomerID,
       COUNT(soh.SalesOrderID) AS OrderCount,
       COALESCE(SUM(soh.TotalDue), 0.00) AS TotalSpend
FROM Sales.Customer AS c
LEFT JOIN Sales.SalesOrderHeader AS soh ON soh.CustomerID = c.CustomerID
GROUP BY c.CustomerID;
```

## Check yourself

### 1. NULL and COUNT

What is the difference between `COUNT(*)` and `COUNT(ShipDate)` when `ShipDate` is nullable?

> [!success]- Answer
> `COUNT(*)` returns the total number of rows. `COUNT(ShipDate)` returns only the number of rows where `ShipDate` is not null. If 100 rows exist but 10 have a null `ShipDate`, `COUNT(*)` = 100 and `COUNT(ShipDate)` = 90.

### 2. WHERE vs HAVING

Can you filter groups using `WHERE`? Can you filter individual rows using `HAVING`?

> [!success]- Answer
> No to both. `WHERE` operates on individual rows **before** grouping and cannot reference aggregate results. `HAVING` operates on groups **after** aggregation and cannot filter individual pre-grouping rows without also including them in the group.

### 3. Conditional aggregation

Write a query that returns each product with total quantity sold and total quantity sold in orders over $1,000.

> [!success]- Answer
>
> ```sql
> SELECT sod.ProductID,
>        SUM(sod.OrderQty) AS TotalQty,
>        SUM(CASE WHEN soh.TotalDue > 1000 THEN sod.OrderQty ELSE 0 END) AS LargeOrderQty
> FROM Sales.SalesOrderDetail AS sod
> INNER JOIN Sales.SalesOrderHeader AS soh ON soh.SalesOrderID = sod.SalesOrderID
> GROUP BY sod.ProductID;
> ```

### 4. LEFT JOIN grain

You `LEFT JOIN` Customer to SalesOrderHeader and then `GROUP BY CustomerID`. What does one result row represent? What happens if you `COUNT(*)` instead of `COUNT(SalesOrderID)`?

> [!success]- Answer
> One row per customer. `COUNT(*)` would count the null-extended row for customers with no orders (returning 1 instead of 0), which is misleading. Always `COUNT(ChildID)` for child counts in left-join aggregations.

## Next steps

Aggregation is the gateway to more advanced analytic patterns:

- **Window functions** (Section 03) — calculate aggregates like running totals or moving averages without collapsing rows.
- **`ROLLUP` / `CUBE` / `GROUPING SETS`** (Section 03) — produce multiple grouping levels in a single query.
- **`OVER` with `PARTITION BY`** (Section 03) — aggregate within a group while preserving detail rows.

## Use Cases

- Generate summary reports: total sales by region by year.
- Identify outliers: customers with unusually high or low order counts.
- Calculate proportions: percentage of total sales per product category.
- Data quality checks: count nulls, duplicates, or missing date ranges.

## Common Issues & Errors

> [!warning] Common Mistake
> `COUNT(column)` ignores `NULL` values; `COUNT(*)` counts rows. Always choose the one that matches the intent.

> [!warning] Common Mistake
> Adding a non-aggregated column to `SELECT` without putting it in `GROUP BY` causes an error. Either aggregate it or add it to `GROUP BY`.

> [!warning] Common Mistake
> `WHERE` on an aggregate expression is invalid. Use `HAVING` to filter after grouping.

## Best Practices

- State the grain before writing `GROUP BY`: "One row per \_\_\_\_."
- Filter early with `WHERE` to reduce the number of rows that must be grouped.
- Use `COALESCE` around `SUM`/`AVG` when a `NULL` result would be misleading.
- Prefer conditional aggregation (`SUM(CASE ...)`) over multiple queries.
- Give aggregate expressions descriptive aliases (`TotalSales`, not `SUM(TotalDue)`).

## Exam Tips

> [!tip] Exam Tips
> Understand grain: every exam aggregation question rewards knowing what one result row represents. `GROUP BY` collapses rows; window functions (Section 03) calculate related values while preserving each row.

## Key Takeaways

- Aggregates summarize sets; `GROUP BY` defines the set boundary.
- `WHERE` filters rows before aggregation; `HAVING` filters groups after.
- `COUNT(*)` counts rows; `COUNT(column)` counts non-null values.
- Conditional aggregation with `CASE` is a single-pass technique.
- `NULL` behavior differs by aggregate function — know the table.

## Related Topics

- [SELECT, filters, subqueries, and set operations](./04-select-and-filter.md)
- [Relationships and JOINs](./05-relationships-and-joins.md)
- [Subqueries and CTEs](./09-subqueries-and-ctes.md)
- [Advanced T-SQL](../03-advanced-tsql/advanced-tsql.md)

## Official Documentation

- [GROUP BY](https://learn.microsoft.com/sql/t-sql/queries/select-group-by-transact-sql)
- [Aggregate functions](https://learn.microsoft.com/sql/t-sql/functions/aggregate-functions-transact-sql)
- [HAVING](https://learn.microsoft.com/sql/t-sql/queries/select-having-transact-sql)
- [CASE](https://learn.microsoft.com/sql/t-sql/language-elements/case-transact-sql)

---

**[← Previous](./05-relationships-and-joins.md) | [↑ Back to Section](./fundamentals.md) | [Next →](./07-change-data-safely.md)**
