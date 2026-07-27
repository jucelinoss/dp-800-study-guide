---
title: Ready for the DP-800 Study Path
type: topic
tags: [dp-800, fundamentals, roadmap]
---

# Ready for the DP-800 Study Path

## Overview

You are ready to start the exam-mapped guide when you can model a small relational problem, query it, and make changes safely. The rest of the guide builds on these skills rather than repeating them.

> [!abstract]
>
> - Part 0 is preparation, not a DP-800 exam domain.
> - Section 01 is your next destination.
> - Use the diagnostic below to decide whether to advance or revisit a specific lesson.

> [!tip] What the Exam Tests
> The exam tests advanced database design, security, deployment, and AI-enabled features; it assumes these basic T-SQL skills.

---

## Readiness checklist

- [ ] I can explain a database, schema, table, row, column, primary key, and foreign key.
- [ ] I can create a table with appropriate basic types, `IDENTITY`, and a `DEFAULT`.
- [ ] I can write `SELECT`, `WHERE`, `ORDER BY`, JOIN, and `GROUP BY` queries.
- [ ] I know that `NULL` requires `IS NULL` or `IS NOT NULL`.
- [ ] I preview an `UPDATE` or `DELETE` with `SELECT` and understand `ROLLBACK`.
- [ ] I understand why constraints and indexes exist, even if I have not mastered their advanced forms.

## A practical readiness check

You do not need to memorize every syntax variant. You are ready when you can work from a short business question to a correct, explainable query or table definition.

Try this without copying an earlier answer:

1. Explain the one-to-many relationship between `Customer` and `SalesOrder`, including where the foreign key belongs.
2. Create a product table with a generated key, a required name, a non-negative exact price, and a default active flag.
3. Return every customer with their total spend, including customers without orders as zero.
4. Return customers who have no orders, using `NOT EXISTS`.
5. Preview and roll back a price change for a known product.

| If this was difficult | Revisit | What to master |
| :--- | :--- | :--- |
| Relationship and foreign key | [Lesson 02](./02-relational-model-and-data-types.md), [Lesson 05](./05-relationships-and-joins.md) | Cardinality, JOIN predicates, row preservation |
| Table definition | [Lesson 02](./02-relational-model-and-data-types.md), [Lesson 03](./03-create-and-load-data.md) | Types, `IDENTITY`, `DEFAULT`, constraints |
| Customer total | [Lesson 05](./05-relationships-and-joins.md), [Lesson 06](./06-aggregation-and-grouping.md) | Left joins, result grain, `COUNT`/`SUM` and `NULL` |
| Missing-order query | [Lesson 04](./04-select-and-filter.md) | Correlated `NOT EXISTS` and `NULL` behavior |
| Safe change | [Lesson 07](./07-change-data-safely.md) | Preview, transaction, `ROLLBACK` |

## Start the exam-mapped path intentionally

Start with [01 — Database Objects](../01-database-objects/database-objects.md). It assumes you can already create and query ordinary tables, then moves into the DP-800 scope: index design, specialized table types, JSON, constraints, sequences, and partitioning.

Do not skip directly to the AI chapters just because they sound more aligned to the certification. Vector, RAG, and external-model scenarios still require correct tables, joins, security, and query reasoning.

## Where each skill continues

| Foundation | Continue in |
| :--- | :--- |
| Tables, keys, constraints, indexes | [01 — Database Objects](../01-database-objects/database-objects.md) |
| CTEs and query logic | [03 — Advanced T-SQL](../03-advanced-tsql/advanced-tsql.md) |
| Transactions and concurrency | [06 — Performance Optimization](../06-performance-optimization/performance-optimization.md) |
| AI-enabled queries | [09–11 — AI Capabilities](../09-models-embeddings/models-embeddings.md) |

## Keep using your sandbox

`StudyDB` remains useful after Part 0. Before running an unfamiliar example from a later module, isolate the smallest reproducible version in that database. Use a new schema or clearly named table to avoid colliding with the beginner labs, inspect the data before DML, and clean up only objects you created.

This approach turns later examples into experiments rather than copy-paste exercises. When a result surprises you, reduce the table to a few rows and write down the expected result before rerunning the query.

## Use Cases

- Decide whether to start Section 01 or revisit an earlier lesson.

## Common Issues & Errors

> [!warning] Common Mistake
> Do not wait to master every SQL Server feature before beginning DP-800. Move on once you can work through this checklist.

> [!warning] Common Mistake
> Treating Part 0 as exam content can distort study time. Its purpose is to remove friction from the exam-mapped modules, not to replace their feature-specific practice.

## Best Practices

- Keep `StudyDB` as a safe sandbox for testing examples from later modules.
- Revisit one prerequisite lesson at a time when a later concept exposes a gap; do not restart the whole path unnecessarily.

## Exam Tips

> [!tip] Exam Tips
> Use this Part 0 to reduce cognitive load, then spend your exam preparation time on the DP-800 blueprint topics.

## Key Takeaways

- You now have the prerequisite vocabulary and habits for the guide.
- You can diagnose a gap by skill and return directly to its lesson.
- The next exam-mapped section is Database Objects.

## Related Topics

- [DP-800 overview](../dp-800-overview.md)

## Official Documentation

- [DP-800 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/dp-800)

---

**[← Previous](./10-index-fundamentals.md) | [↑ Back to Section](./fundamentals.md) | [Start Section 01 →](../01-database-objects/database-objects.md)**
