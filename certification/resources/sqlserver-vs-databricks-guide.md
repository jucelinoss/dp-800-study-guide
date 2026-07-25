# 📘 Architecture Transition Guide: SQL Server (RDBMS) to Databricks (Lakehouse)

> **Goal**: Connect familiar SQL Server concepts (constraints, identity,
> indexes, graph tables, JSON, stored procedures, and locks) to their
> equivalents and operating models in Databricks, Apache Spark, and Delta Lake.

---

## 📌 The Paradigm Shift

| Architecture concept | SQL Server (traditional RDBMS) | Databricks / Spark (lakehouse) |
| :--- | :--- | :--- |
| **Base architecture** | Monolithic, active-passive, scale-up | Distributed, multi-node Spark, scale-out |
| **Compute and storage** | Coupled; server is continuously running | Decoupled; cloud storage and on-demand clusters |
| **Data approach** | Schema-on-write; strict ETL before persistence | Schema-on-read plus schema-on-write in a medallion architecture |
| **Integrity guarantee** | Synchronous row-level validation and locks | Validation in the ETL pipeline and informational constraints |
| **Data access** | Clustered/nonclustered B-trees | Data skipping, Z-ordering, and liquid clustering |
| **Concurrency** | Lock manager: shared and exclusive locks | Optimistic concurrency control (OCC) |

---

## 🛠️ Feature Mapping: SQL Server vs. Databricks

### 1. Data Integrity and Constraints (`PRIMARY KEY`, `FOREIGN KEY`, `CHECK`)

* **SQL Server** validates `PRIMARY KEY` and `FOREIGN KEY` synchronously during
  `INSERT` and `UPDATE`; a violation aborts the transaction.
* **Databricks / Delta Lake**:
  * **`CHECK` and `NOT NULL`** are enforced at the Delta Lake table level.
  * **`PRIMARY KEY` and `FOREIGN KEY` informational constraints** in Unity
    Catalog are metadata. They can help optimization but do not reject writes.
  * **Practice**: enforce referential quality in Silver and Gold pipelines with
    Delta Live Tables expectations or quarantine rules.

### 2. Sequential Key Generators (`IDENTITY` and `SEQUENCE`)

* **SQL Server** uses `IDENTITY(1,1)` or `SEQUENCE` to generate atomic values.
* **Databricks / Delta Lake** supports `GENERATED ALWAYS AS IDENTITY`, but
  distributed allocation does not guarantee contiguous values. For distributed
  pipelines, use `uuid()` or deterministic hashes such as
  `md5(concat(colA, colB))` when appropriate.

### 3. Read Optimization: B-Trees vs. Data Skipping and Liquid Clustering

* **SQL Server** uses B-trees and columnstore indexes to locate rows.
* **Databricks / Delta Lake** optimizes file layout instead:
  * **Data skipping** uses Parquet-file statistics such as minimum and maximum
    values to avoid reading irrelevant files.
  * **Liquid clustering** dynamically reorganizes data files for common
    multidimensional filters without rigid partitioning.

### 4. Semi-Structured Processing (`JSON`)

* **SQL Server** offers `JSON_VALUE`, `OPENJSON`, and `JSON_QUERY` over
  `NVARCHAR` or `JSON` columns where supported.
* **Databricks** offers `from_json()`, `to_json()`, `schema_of_json()`, and
  field-access syntax. Its `VARIANT` type supports dynamic JSON structures.

### 5. Graphs and Network Analysis (`AS NODE`, `AS EDGE`)

* **SQL Server** has native graph tables and T-SQL `MATCH()` and
  `SHORTEST_PATH()`.
* **Databricks** uses GraphFrames (PySpark) and GraphX for distributed graph
  workloads such as PageRank, shortest path, connected components, triangle
  count, and label propagation.

### 6. Programmability: Stored Procedures and Triggers vs. Notebooks and CDF

* **SQL Server** uses T-SQL stored procedures and `AFTER`/`INSTEAD OF` triggers.
* **Databricks** uses versioned Python, PySpark, or SQL notebooks/modules;
  Delta Lake Change Data Feed (CDF) exposes row-level changes for reactive and
  streaming pipelines; Delta Live Tables can maintain materialized views.

### 7. Transactions and Concurrency (ACID and Locks)

* **SQL Server** uses lock-based concurrency or row-versioning isolation such
  as RCSI and snapshot isolation.
* **Databricks** uses OCC backed by the Delta transaction log (`_delta_log`).
  Reads do not block writers; conflicting writes are retried or fail with a
  concurrency exception when they affect the same files.

---

## 🎯 Transition Strategy

1. Replace **write-time guarantees** with explicit **pipeline quality** rules
   across Bronze and Silver layers.
2. Replace B-tree design with intentional **Delta file layout** and liquid
   clustering for expected filters.
3. Replace imperative T-SQL procedures with tested, versioned PySpark/DLT
   pipeline modules where distributed processing is required.
4. Prefer a hybrid architecture when appropriate: Databricks handles large
   scale ETL and AI workloads, while SQL Server or a data mart serves
   low-latency operational workloads and dashboards.
