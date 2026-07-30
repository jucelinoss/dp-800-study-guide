---
title: PIVOT and UNPIVOT
type: study-material
tags: [sql-server, tsql, pivot, unpivot, fundamentals]
---

# PIVOT and UNPIVOT

`PIVOT` and `UNPIVOT` reshape a table-valued expression. `PIVOT` turns distinct values from one column into output columns and performs an aggregate when needed. `UNPIVOT` performs the opposite shape change by turning columns into rows. [Microsoft Learn](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-using-pivot-and-unpivot?view=sql-server-ver17)

## Mental model

Suppose the source has one row per sale and a `QuarterName` column:

| Region | QuarterName | Amount |
| :--- | :--- | ---: |
| East | Q1 | 100 |
| East | Q2 | 120 |

`PIVOT` produces a wide report:

| Region | Q1 | Q2 |
| :--- | ---: | ---: |
| East | 100 | 120 |

`UNPIVOT` turns that wide report back into attribute/value rows. It is not a perfect inverse: `PIVOT` may aggregate multiple source rows, and `UNPIVOT` drops `NULL` values.

## PIVOT syntax

```sql
SELECT <grouping_columns>, [Q1], [Q2], [Q3], [Q4]
FROM
(
    SELECT Region, QuarterName, Amount
    FROM study.PivotSales
) AS source_data
PIVOT
(
    SUM(Amount)
    FOR QuarterName IN ([Q1], [Q2], [Q3], [Q4])
) AS pivot_data;
```

The source query should expose only the grouping columns, the pivot column, and the value column. Extra columns can unintentionally become grouping columns and change the output grain.

`IN ([Q1], [Q2], [Q3], [Q4])` is a static list. A value not present in the source still appears as a column, with `NULL` for groups that have no value. Dynamic PIVOT is required when the set of output columns is not known in advance.

## UNPIVOT syntax

```sql
SELECT SalesYear, Region, QuarterName, Amount
FROM study.PivotSalesWide
UNPIVOT
(
    Amount FOR QuarterName IN ([Q1], [Q2], [Q3], [Q4])
) AS unpivot_data;
```

The column names listed in `IN` become values in `QuarterName`; their cell values become `Amount`. `UNPIVOT` omits rows whose source cell is `NULL`, so missing quarters do not reappear as rows.

## PIVOT versus conditional aggregation

`PIVOT` is concise for a fixed cross-tabulation. Conditional aggregation is often easier to extend or debug:

```sql
SELECT
    SalesYear,
    Region,
    SUM(CASE WHEN QuarterName = N'Q1' THEN Amount END) AS Q1,
    SUM(CASE WHEN QuarterName = N'Q2' THEN Amount END) AS Q2,
    SUM(CASE WHEN QuarterName = N'Q3' THEN Amount END) AS Q3,
    SUM(CASE WHEN QuarterName = N'Q4' THEN Amount END) AS Q4
FROM study.PivotSales
GROUP BY SalesYear, Region;
```

Both approaches aggregate by the same grouping grain. Choose the form that makes the report contract easiest to read and maintain. Repeated `PIVOT`/`UNPIVOT` operators in one statement can affect performance; measure complex reports rather than assuming one shape is always faster.

## Common pitfalls

- `PIVOT` requires an aggregate such as `SUM`, `COUNT`, or `AVG`.
- A column accidentally left in the source query becomes an implicit grouping column.
- `NULL` in a pivoted value remains `NULL`; it is not automatically zero.
- `UNPIVOT` drops `NULL` cells.
- Column identifiers in `UNPIVOT` follow catalog collation rules; collation conflicts can require `COLLATE DATABASE_DEFAULT`.
- Repeated reshaping can make a query harder to optimize and maintain.

## Hands-on lab

Run [Lab 11 — PIVOT and UNPIVOT](../../practice/labs/00-fundamentals/11-pivot-unpivot.sql) after [Lab 01 — Create StudyDB](../../practice/labs/00-fundamentals/01-setup-studydb.sql).

The lab creates a disposable `study.PivotSales` table, produces a quarterly cross-tabulation, and unpivots the result to show why missing `NULL` quarters disappear.

## Official documentation

- [Using PIVOT and UNPIVOT](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-using-pivot-and-unpivot?view=sql-server-ver17)

---

**[← Previous](./10-index-fundamentals.md) | [↑ Back to Part 0](./fundamentals.md) | [Lab: PIVOT and UNPIVOT](../../practice/labs/00-fundamentals/11-pivot-unpivot.sql) | [Next →](./12-ready-for-dp800.md)**
