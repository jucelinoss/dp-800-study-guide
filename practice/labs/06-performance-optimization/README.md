---
title: Performance Optimization Labs
type: lab-guide
---

# Performance Optimization Labs

These scripts target SQL Server 2022+ and the AdventureWorks OLTP sample. Run them against a disposable lab database, not a shared or production database.

## Recommended order

1. `01-database-configurations-lab.sql`: database-scoped settings, Query Store, automatic tuning scope, and memory grants.
2. `02-transaction-isolation-concurrency-lab.sql`: row versioning and optimistic concurrency.
3. `03-query-performance-troubleshooting-lab.sql`: plans, statistics, parameter sniffing, and plan guides.

## Two-session concurrency exercise

The second lab contains diagnostics, but a blocking chain is observable only when two sessions overlap. Open two SSMS query windows connected to `AdventureWorks2025`.

Session A:

```sql
USE AdventureWorks2025;
BEGIN TRANSACTION;
UPDATE lab.InventoryStock SET Quantity = Quantity + 1 WHERE ItemID = 1;
-- Leave the transaction open.
```

Session B, first with RCSI disabled in a disposable copy:

```sql
USE AdventureWorks2025;
SELECT ItemID, Quantity FROM lab.InventoryStock WHERE ItemID = 1;
```

Run the blocking DMV from Part 3 in a third window, then execute `ROLLBACK` in Session A. Enable RCSI and repeat Session B. Compare the wait behavior, then repeat with an explicit `SNAPSHOT` transaction to observe transaction-level consistency.

## Cleanup

After the exercise, close all transactions and remove only the lab objects. Restore database options only if this database was dedicated to the lab:

```sql
USE master;
ALTER DATABASE AdventureWorks2025 SET READ_COMMITTED_SNAPSHOT OFF;
ALTER DATABASE AdventureWorks2025 SET ALLOW_SNAPSHOT_ISOLATION OFF;
```

Turning RCSI off also requires exclusive access; do not run the cleanup blindly on a shared database.

## Official references

- [Transaction locking and row versioning guide](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide)
- [Monitor performance by using Query Store](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
