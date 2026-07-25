# 📘 Architecture Transition Guide: SQL Server (RDBMS) to Microsoft Fabric

> **Goal**: Relate familiar SQL Server concepts—T-SQL, constraints, indexes,
> stored procedures, RLS, and identity—to Microsoft Fabric capabilities such as
> OneLake, Fabric Warehouse, Lakehouse, Fabric SQL Database, and Direct Lake.

---

## 📌 The Paradigm Shift

| Architecture concept | SQL Server (traditional RDBMS) | Microsoft Fabric |
| :--- | :--- | :--- |
| **Base architecture** | Monolithic, active-passive, scale-up | Unified SaaS platform with scale-out engines |
| **Data format** | Proprietary `.mdf` and `.ndf` files, 8-KB pages | OneLake with open Delta Lake and Parquet formats |
| **Query engines** | One T-SQL engine for OLTP and OLAP | Warehouse T-SQL, Spark, KQL, and Power BI |
| **BI integration** | Import or DirectQuery | Direct Lake over OneLake data where supported |
| **Operational database** | SQL Server engine | Fabric SQL Database for supported workloads |
| **Concurrency** | Connections and lock manager | Distributed engine and Delta optimistic concurrency patterns |

---

## 🛠️ Feature Mapping: SQL Server vs. Microsoft Fabric

### 1. T-SQL Engine and Code Compatibility

* **SQL Server** provides the full T-SQL surface, including stored procedures,
  DDL, DML, CTEs, window functions, triggers, and cursors.
* **Fabric** provides different T-SQL capabilities by workload. Warehouse and
  SQL analytics endpoints support set-based analytics features such as
  `SELECT`, `JOIN`, CTEs, views, and procedures, but availability must be
  verified for the target Fabric workload rather than assumed from SQL Server.

### 2. Data Integrity and Constraints

* **SQL Server** enforces constraints synchronously during writes.
* **Fabric Warehouse and Lakehouse** use workload-specific support; primary and
  foreign keys can be informational rather than enforced. **Fabric SQL
  Database** has a different, operational SQL surface. Confirm the feature
  matrix before moving integrity logic.

### 3. Sequential Keys (`IDENTITY`)

* **SQL Server** uses `IDENTITY(1,1)` and `SEQUENCE` with atomic counters.
* **Distributed Fabric workloads** can allocate values across compute nodes;
  identity values should not be treated as a business sequence or a gapless
  ordering mechanism.

### 4. Read Optimization: B-Trees vs. File Layout

* **SQL Server** uses B-trees and columnstore indexes over database pages.
* **Fabric lake-centric workloads** benefit from Parquet layout, V-Order where
  applicable, and file-level statistics/data skipping instead of B-tree design.

### 5. BI Consumption: Import, DirectQuery, and Direct Lake

* **SQL Server** commonly serves Power BI through import or DirectQuery.
* **Direct Lake**, where available, lets Power BI use OneLake data without the
  conventional import copy or DirectQuery translation path. Validate refresh,
  security, and feature behavior for the chosen Fabric item.

### 6. Data Security

* **SQL Server** offers T-SQL Row-Level Security, Dynamic Data Masking, and
  granular `GRANT`/`DENY` permissions.
* **Fabric support varies by workload.** Model security at the SQL endpoint,
  semantic model, and OneLake layers deliberately; do not assume an SQL Server
  security feature automatically propagates to every Fabric engine.

### 7. Ingestion and Processing: SSIS vs. Fabric Data Factory

* **SQL Server** commonly uses SSIS for local ETL packages.
* **Fabric** offers Data Factory pipelines, Dataflows Gen2, notebooks, and
  mirroring for supported sources to OneLake.

---

## 🎯 Migration Strategy for SQL Server Developers

1. Retain T-SQL where the selected Fabric workload supports it, but validate
   syntax and behavior against that workload's documentation.
2. Replace physical database-maintenance assumptions (`REBUILD INDEX`,
   filegroups, `tempdb` tuning) with capacity, file-layout, and workload design.
3. Use OneLake deliberately to reduce unnecessary copies, while preserving
   appropriate ownership, governance, and security boundaries.
