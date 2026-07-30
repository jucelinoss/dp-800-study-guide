---
title: SQL Server Fundamentals for DP-800
type: category
tags: [dp-800, sql-server, tsql, fundamentals]
status: complete
---

# Part 0 — SQL Server Fundamentals

This optional prerequisite path is for learners who are new to relational databases or T-SQL. It is not a separate DP-800 exam domain; it gives you the vocabulary and hands-on habits needed before Section 01.

> [!abstract]
>
> - Build and query a small relational database safely.
> - Learn the SQL concepts assumed by the DP-800 material.
> - Complete the labs in order; they share the `StudyDB` database.

> [!tip] Start here if you cannot yet create a table, write a JOIN, and explain a primary key.
> Experienced SQL developers can skim the checklist and go directly to [Section 01](../01-database-objects/database-objects.md).

## What Part 0 is — and is not

Part 0 is a self-contained SQL Server and T-SQL prerequisite course. It teaches the language and data-model habits assumed by the DP-800 material; it does not claim to map directly to an exam domain or replace the exam-mapped sections.

| Part 0 gives you | Continue later for |
| :--- | :--- |
| Core relational modelling and data types | Specialized tables, JSON, partitioning, sequences |
| Complete read-query vocabulary | Window functions, regex, graph queries, advanced T-SQL |
| Safe DDL/DML and constraints | Security, concurrency, deployment, and monitoring |
| Basic index trade-offs | Query plans, DMVs, Query Store, and production tuning |

## Learning path

> [!info] Deep-dive companion
> Read the [SQL Server Foundations Workbook](./00-foundations-workbook.md) alongside the lessons below. It explains every core concept in depth, includes check-yourself exercises and solutions, and uses only this repository's `StudyDB` labs.

| Step | Topic | Outcome |
| :---: | :--- | :--- |
| 00 | [Foundations Workbook](./00-foundations-workbook.md) | Self-contained lesson and capstone |
| 01 | [SQL Server and tools](./01-sql-server-and-tools.md) | Connect with SSMS or VS Code |
| 02 | [Relational model and data types](./02-relational-model-and-data-types.md) | Model rows, columns, keys, and `NULL` |
| 03 | [Create and load data](./03-create-and-load-data.md) | Use safe DDL and inserts |
| 04 | [SELECT, filters, subqueries, and set operations](./04-select-and-filter.md) | Compose complete read queries |
| 05 | [Relationships and JOINs](./05-relationships-and-joins.md) | Combine related tables |
| 06 | [Aggregation](./06-aggregation-and-grouping.md) | Summarize correctly |
| 07 | [Change data safely](./07-change-data-safely.md) | Use transactions with DML |
| 08 | [Integrity rules](./08-integrity-rules.md) | Protect valid data |
| 09 | [CTEs and temporary query structures](./09-subqueries-and-ctes.md) | Name and reuse intermediate results |
| 10 | [Index fundamentals](./10-index-fundamentals.md) | Understand read/write trade-offs |
| 11 | [PIVOT and UNPIVOT](./11-pivot-unpivot.md) | Reshape long and wide result sets |
| 12 | [Ready for DP-800](./12-ready-for-dp800.md) | Choose your next module |

## Recommended study rhythm

1. Read the corresponding lesson before running its lab.
2. Run the lab in `StudyDB`, then modify one value or predicate and predict the result.
3. Complete the lesson's practice questions without looking at the answer first.
4. At the end of each study session, explain one concept aloud in plain language; if you cannot, revisit the example.
5. Use Lesson 11 to diagnose gaps before moving to Section 01.

> [!note]
> The numbered labs are intentionally progressive. Run `01-setup-studydb.sql` first. If your experiments leave the data in an unknown state, rerun that setup script and continue from the relevant lab.

## Labs

Run the scripts in [`practice/labs/00-fundamentals/`](../../practice/labs/00-fundamentals/). Start with `01-setup-studydb.sql`; later scripts can be safely rerun because they use the same disposable `StudyDB` database.

## Key Concepts

- A **table** stores rows of one entity; a **relationship** connects entities through keys.
- `SELECT` reads data; DDL defines objects; DML inserts, changes, or removes rows.
- A transaction lets you review a change and choose `COMMIT` or `ROLLBACK`.
- A query has an intended **grain**: the meaning of one output row. State it before adding JOINs or aggregates.
- Temporary structures solve a lifetime problem; use a CTE, table variable, or temp table only when its scope is required.

## Related Resources

- [Database Objects](../01-database-objects/database-objects.md)
- [Advanced T-SQL](../03-advanced-tsql/advanced-tsql.md)
- [Hands-on Labs](../resources/labs/labs.md)

---

**[↑ DP-800 study path](../dp-800-overview.md) | [Next →](./01-sql-server-and-tools.md)**
