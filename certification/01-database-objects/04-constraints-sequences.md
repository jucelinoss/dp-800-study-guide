---
title: Constraints and Sequences
type: study-material
tags:
  - dp-800
  - constraints
  - primary-key
  - foreign-key
  - sequences
---

# Constraints and Sequences

## Overview

Constraints enforce data integrity at the database level. SQL Server supports PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK, and DEFAULT constraints. SEQUENCES provide database-wide, shareable, non-identity number generators.

> [!abstract]
>
> - Covers PRIMARY KEY, FOREIGN KEY, CHECK, DEFAULT, UNIQUE constraints, and SEQUENCE objects
> - Constraints enforce data integrity at the database level; sequences provide independent number generation
> - Key exam topics: SEQUENCE vs IDENTITY, constraint types and enforcement timing

> [!tip] What the Exam Tests
>
> - `SEQUENCE` is **independent of any table** — can be shared across tables, cycled, and reset with `ALTER SEQUENCE`
> - `IDENTITY` is **column-bound** — cannot be shared, cannot be reset cleanly without DBCC, increments only upward
> - `CHECK` constraints can reference multiple columns in the same row; `FOREIGN KEY` enforces referential integrity across tables

---

## ⚖️ Decision Matrix: SEQUENCE vs IDENTITY

| Feature / Requirement | SEQUENCE | IDENTITY |
| :--- | :--- | :--- |
| **Object Scope** | Database-level independent object | Table column-bound |
| **Shared Across Tables?** | **YES** | **NO** |
| **Get Value Before INSERT?** | **YES** (`NEXT VALUE FOR`) | **NO** (Only post-INSERT via `SCOPE_IDENTITY()`) |
| **Cycling (`CYCLE`) / Easy Reset** | **YES** (`ALTER SEQUENCE ... RESTART`) | Requires `DBCC CHECKIDENT` |
| **High Concurrency Batch Performance** | High with `CACHE 1000` | Potential latch contention under high concurrency |

---

> [!warning] ARCHITECTURAL WARNING & DP-800: Incremental Keys (Surrogate Keys) Do NOT Guarantee Business Integrity!
> 
> Simply defining an `IDENTITY` or `SEQUENCE` as a `PRIMARY KEY` **does NOT prevent real-world business entity duplication** in the table.
> 
> * **The Pitfall**: The SQL Server engine guarantees uniqueness for incremental numbers (`ID = 1`, `ID = 2`), but will happily accept two rows containing identical Social Security Numbers (SSN), Tax IDs, or Emails under different artificial IDs.
> * **Impact on MERGE & ETL Pipelines**: If an ETL process joins on artificial keys (`MERGE ... ON Target.ID = Source.ID`), it fails to detect existing business entities when incoming source records contain new or null IDs, causing duplicate entity creation.
> * **Best Practice Architectural Pattern**:
>   1. Use Incremental Keys (`IDENTITY`/`SEQUENCE`) as **Surrogate Primary Keys** to optimize physical storage layout and relational JOIN performance.
>   2. **ALWAYS enforce a `UNIQUE CONSTRAINT` or `UNIQUE INDEX` on Natural / Business Keys** (e.g., `UNIQUE (SSN)` or `UNIQUE (TenantID, TaxID)`).
>   3. In massive ETL pipelines, employ a deterministic load-control hash column (`RowHash`) backed by a `UNIQUE INDEX` to reject duplicate entity ingestions.

---

## 💡 Enterprise Real-World Use Cases

### 🚀 1. Real-World Scenarios for `SEQUENCE`
* **Scenario A: Multi-Channel Strict Fiscal Invoicing (`NO CACHE`)**:
  * *Problem*: `OnlineSales`, `PosSales`, and `CorporateSales` write to separate tables, but tax authorities demand a single unified, gap-free invoice sequence.
  * *Solution*: Create a shared `SEQUENCE` with `NO CACHE` and assign it as the `DEFAULT` value for all three tables.
* **Scenario B: Round-Robin Queue Distribution (`CYCLE`)**:
  * *What is a Round-Robin Queue?*: Round-Robin is a classic circular scheduling algorithm that distributes workloads or items equally among a fixed set of resources (e.g., $N$ servers, $N$ support teams, or $N$ partitions) in a continuous loop: `1 ➔ 2 ➔ 3 ➔ 1 ➔ 2 ➔ 3...`
  * *Problem*: Rotate incoming support tickets evenly across 3 team queues (`Team 1, 2, 3`).
  * *Solution*: Create a `SEQUENCE` with `MINVALUE 1 MAXVALUE 3 CYCLE`. Upon reaching `MAXVALUE 3`, the `CYCLE` modifier automatically rolls the sequence generator back to `MINVALUE 1`.
* **Scenario C: Mass Parallel ETL Key Allocation (`sp_sequence_get_range`)**:
  * *Problem*: An ETL process needs to pre-allocate 50,000 primary keys in memory prior to parallel bulk inserting.
  * *Solution*: Execute `sp_sequence_get_range @range_size = 50000`.

### 🏢 2. Real-World Scenarios for `IDENTITY`
* **Scenario A: Standard Surrogate Key in Isolated Transactional Tables**:
  * *Problem*: Simple unique primary key for internal JOINs in `AuditLogs` or `OrderItems`.
  * *Solution*: `ProductID INT IDENTITY(1,1) PRIMARY KEY`.
* **Scenario B: Staging Table Reseed (`DBCC CHECKIDENT`)**:
  * *Problem*: Reset identity sequence back to 1 after clearing a staging table during test runs.
  * *Solution*: Run `DBCC CHECKIDENT('lab.StagingTable', RESEED, 0)`.

### 🛡️ 3. Real-World Scenarios for Constraints
* **PRIMARY KEY NONCLUSTERED + CLUSTERED on Date**:
  * *Problem*: High-ingestion log table encounters last-page insert contention if PK is a clustered GUID.
  * *Solution*: Create `PRIMARY KEY NONCLUSTERED (LogID)` and place `CLUSTERED INDEX` on `LogDate`.
* **COMPOSITE PRIMARY KEY (in N:M Tables like `UserRoles (UserID, RoleID)`)**:
  * *Problem*: Many-to-many relationship table `UserRoles (UserID, RoleID)`.
  * *Solution*: `CONSTRAINT PK_UserRoles PRIMARY KEY (UserID, RoleID)`. Prevents duplicate role assignment and physically groups user profiles together on disk.
  * *Difference between Composite PK vs UNIQUE (UserID, RoleID)*:
    * The **Composite PK** defaults to creating a **`CLUSTERED INDEX`**, physically storing all roles for a given `UserID` side-by-side on the same data page. A query `WHERE UserID = 10` reads 100% of that user's permissions in a single I/O page read!
    * Using a standalone **UNIQUE Constraint** (or a surrogate key `UserRoleID IDENTITY` + `UNIQUE`) would create a **`NONCLUSTERED INDEX`**, leaving the main data in Heap format with user permissions scattered across disk pages, triggering unnecessary *Key Lookups*.
    * Additionally, the **Composite PK** strictly forbids `NULL` values on both key columns (mandatory for junction tables) and eliminates unnecessary storage overhead from artificial IDs.
* **FOREIGN KEY with `ON DELETE CASCADE`**:
  * *Problem*: Deleting a shopping cart session automatically purges associated cart items.
  * *Solution*: `CONSTRAINT FK_CartItems FOREIGN KEY (CartID) REFERENCES Carts(CartID) ON DELETE CASCADE`.
* **FOREIGN KEY with `ON DELETE SET NULL`**:
  * *Problem*: Deleting a sales employee preserves past sales records while setting `EmployeeID = NULL`.
  * *Solution*: `CONSTRAINT FK_Orders_Employee FOREIGN KEY (EmployeeID) REFERENCES Employees(EmployeeID) ON DELETE SET NULL`.
* **FILTERED UNIQUE INDEX (`WHERE Column IS NOT NULL`)**:
  * *Problem*: National IDs are mandatory for citizens but NULL for foreign customers, while preventing duplicate IDs.
  * *Solution*: `CREATE UNIQUE NONCLUSTERED INDEX UIX_SSN ON Customers(SSN) WHERE SSN IS NOT NULL`.
* **MULTI-COLUMN CHECK CONSTRAINT (`EndDate >= StartDate`)**:
  * *Problem*: Enforce business rule preventing contract end date from being earlier than start date.
  * *Solution*: `CONSTRAINT CK_ContractDates CHECK (EndDate >= StartDate)`.
* **DEFAULT CONSTRAINT with `SYSUTCDATETIME()`**:
  * *Problem*: Standardize global UTC timestamps regardless of client server timezone settings.
  * *Solution*: `CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()`.

---

## 🛡️ Quick Guide: Constraint Types (PK, FK, UK, DF, CHECK)

| Constraint | Primary Purpose | Allows NULL? | Default Index Created | Max Per Table |
| :--- | :--- | :--- | :--- | :--- |
| **PRIMARY KEY (PK)** | Uniquely identifies each row | **NO** (Requires `NOT NULL`) | Unique Clustered Index | Exactly **1** |
| **FOREIGN KEY (FK)** | Enforces referential integrity with parent table | **YES** | None (Manual index recommended) | Multiple |
| **UNIQUE (UK)** | Prevents duplicate values in non-PK columns | **YES** (Only 1 `NULL` by default) | Unique Nonclustered Index | Multiple |
| **DEFAULT (DF)** | Supplies fallback value if omitted in INSERT | N/A | None | 1 per Column |
| **CHECK (CHK)** | Evaluates boolean expression per row | **YES** (Passes if `UNKNOWN`) | None | Multiple |

> [!IMPORTANT]
> **DP-800 Deep Dive — How `CHECK Constraints` Work**  
> 
> `CHECK Constraints` enforce domain integrity by evaluating boolean expressions during `INSERT` and `UPDATE` operations. They have 5 core characteristics:
> 
> **1. Boolean Evaluation Mechanism**:  
> Every time a statement attempts to write or alter a row, SQL Server evaluates the logical expression defined in the constraint. Validation can target a single column (`Age >= 18`), multiple values (`Status IN ('active', 'pending')`), or compare columns within the same row (`DeliveryDate >= OrderDate`).
> 
> **2. Three-Valued Logic & `NULL` Handling**:  
> SQL Server utilizes Three-Valued Logic: `TRUE`, `FALSE`, and `UNKNOWN` (Null/Unknown).  
> * **Golden Rule**: A `CHECK Constraint` **ONLY REJECTS** a write if the expression evaluates to strictly **`FALSE`**.  
> * If the expression evaluates to `TRUE`, the write is **accepted**.  
> * If the expression evaluates to **`UNKNOWN`** (which occurs when evaluating any expression against `NULL`), the write **PASSES**!  
> 
> **Truth Table in Practice (`CHECK (Age >= 18)`)**:  
> | Value Inserted into `Age` | Expression Evaluation (`Age >= 18`) | Boolean Result | Does SQL Server accept the write? |
> | :--- | :--- | :--- | :--- |
> | `25` | `25 >= 18` | `TRUE` | ✅ **YES** (Operation completed successfully) |
> | `15` | `15 >= 18` | `FALSE` | ❌ **NO** (Triggers Violation Error Msg 547) |
> | `NULL` | `NULL >= 18` | `UNKNOWN` | ✅ **YES** (Write permitted without error!) |
> 
> *Exam Takeaway*: A `CHECK constraint` by itself **does NOT prevent `NULL` values**. To disallow nulls on a check-validated column, specify `NOT NULL` on the column definition or explicitly include `AND Column IS NOT NULL` in the predicate.
> 
> **3. No Physical Index Creation**:  
> Unlike `PRIMARY KEY` (which creates a Clustered index by default) or `UNIQUE` (which creates a Nonclustered index), a `CHECK constraint` **does not create any physical index** on disk. It is a purely logical CPU instruction evaluated during transactions.
> 
> **4. Multiple Constraints per Table**:  
> A single table can have multiple `CHECK constraints` enforcing distinct business rules (e.g., email format via `LIKE '%@%'`, non-negative balances, date range validation).
> 
> **5. Scope Restrictions & Limitations**:  
> * A `CHECK constraint` can only reference columns within the **same row of the same table**.  
> * **Subqueries are NOT allowed** (`SELECT ... FROM another_table`). To enforce cross-table integrity, use `FOREIGN KEY`, Triggers, or Indexed Views.  
> * **Non-deterministic system functions** (like `GETDATE()`) without fixed row parameters cannot be referenced directly.

---

## ⚖️ UNIQUE CONSTRAINT vs UNIQUE INDEX (Key Differences)

In SQL Server, creating a `UNIQUE CONSTRAINT` under the hood creates a nonclustered `UNIQUE INDEX` to enforce uniqueness. However, key functional differences exist:

| Feature / Capability | UNIQUE CONSTRAINT | UNIQUE INDEX |
| :--- | :--- | :--- |
| **Primary Focus** | **Logical Integrity / Relational Modeling** | **Performance, Tuning & Advanced Indexing** |
| **Filter Support (`WHERE`)** | ❌ **NO**. Cannot use `WHERE` clauses. | ✅ **YES**. Allows `WHERE Column IS NOT NULL` (Filtered Index for multiple NULLs). |
| **Included Columns (`INCLUDE`)** | ❌ **NO**. Cannot specify `INCLUDE` columns. | ✅ **YES**. Allows `INCLUDE (ColA, ColB)` (Covering Index to eliminate Key Lookups). |
| **Maintenance & Compression Options** | Limited parameters upon creation. | Full options (`DATA_COMPRESSION`, `FILLFACTOR`, `ONLINE = ON`). |
| **Metadata Visibility** | Appears in `sys.key_constraints` and `sys.indexes`. | Appears only in `sys.indexes`. |

---

## Constraint Types

### PRIMARY KEY

```sql
-- 1. Single column - Clustered by default
CREATE TABLE dbo.Customers (
    CustomerId  int NOT NULL IDENTITY(1,1) PRIMARY KEY,
    Name        nvarchar(100) NOT NULL
);

-- 2. Table-level (Composite or Named)
CREATE TABLE dbo.OrderItems (
    OrderId     int NOT NULL,
    ProductId   int NOT NULL,
    Quantity    int NOT NULL,
    CONSTRAINT PK_OrderItems PRIMARY KEY (OrderId, ProductId)
);

-- 3. Nonclustered Primary Key (Allows Clustered Index on another column, e.g., Date)
CREATE TABLE dbo.LogEntries (
    LogId       uniqueidentifier NOT NULL DEFAULT NEWID(),
    LogDate     datetime2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
    Message     nvarchar(max) NOT NULL,
    CONSTRAINT PK_LogEntries PRIMARY KEY NONCLUSTERED (LogId)
);
```

#### 📌 When to Use Each PRIMARY KEY Type?

| Primary Key Type | When to Use (Architectural Use Case) | SQL Server Architectural Advantage |
| :--- | :--- | :--- |
| **1. Single-Column Clustered PK (`IDENTITY` / `SEQUENCE`)** | Standard OLTP tables representing a single entity (`Customers`, `Products`). | Places the `CLUSTERED INDEX` on an auto-incrementing key, ensuring sequential end-of-page inserts without *page splits*. |
| **2. Composite PK (`PRIMARY KEY (ColA, ColB)`)** | Many-to-Many junction tables (`OrderItems`, `UserRoles`). | Enforces pair uniqueness and **physically groups rows on disk** by the lead column (`OrderId`/`UserId`), optimizing range queries like `WHERE OrderId = X`. |
| **3. Nonclustered PK (`PRIMARY KEY NONCLUSTERED`)** | High-ingestion log/audit tables using random GUIDs (`NEWID()`) or where range queries target date columns. | **Frees up the `CLUSTERED INDEX` for another column** (e.g., `LogDate`), avoiding heavy index fragmentation and *page splits* caused by random GUIDs. |

- Only one per table; columns must be NOT NULL

### FOREIGN KEY

```sql
CREATE TABLE dbo.Orders (
    OrderId     int NOT NULL PRIMARY KEY,
    CustomerId  int NOT NULL,
    CONSTRAINT FK_Orders_Customers
        FOREIGN KEY (CustomerId) REFERENCES dbo.Customers (CustomerId)
        ON DELETE NO ACTION
        ON UPDATE CASCADE
);
```

**Referential actions:**

| Action | On DELETE | On UPDATE |
| :--- | :--- | :--- |
| `NO ACTION` (default) | Error if child rows exist | Error if referenced key changes |
| `CASCADE` | `Delete child rows` | Update child FK values |
| `SET NULL` | Set FK to NULL | Set FK to NULL |
| `SET DEFAULT` | Set FK to column default | Set FK to column default |

### UNIQUE

```sql
-- Unique constraint (allows one NULL)
ALTER TABLE dbo.Customers
ADD CONSTRAINT UQ_Customers_Email UNIQUE (Email);

-- Unique index (equivalent, but more options)
CREATE UNIQUE NONCLUSTERED INDEX UIX_Customers_Email
ON dbo.Customers (Email)
WHERE Email IS NOT NULL;  -- Filtered: exclude NULLs
```

### CHECK

```sql
CREATE TABLE dbo.Products (
    ProductId   int             NOT NULL PRIMARY KEY,
    Price       decimal(10,2)   NOT NULL,
    Quantity    int             NOT NULL,
    Status      varchar(20)     NOT NULL,
    CONSTRAINT CHK_Products_Price    CHECK (Price > 0),
    CONSTRAINT CHK_Products_Quantity CHECK (Quantity >= 0),
    CONSTRAINT CHK_Products_Status   CHECK (Status IN ('active', 'discontinued', 'pending'))
);

-- NOT FOR REPLICATION: Prevents constraint check during replication synchronization
ALTER TABLE dbo.Products ADD CONSTRAINT CHK_Products_SKU
    CHECK (ProductId > 0) NOT FOR REPLICATION;
```

> [!NOTE]
> **DP-800 Deep Dive — How does `NOT FOR REPLICATION` work?**  
> The **`NOT FOR REPLICATION`** clause disables constraint validation (or trigger execution) exclusively during data replication processes (*Transactional Replication* or *Merge Replication*).
> 
> **1. The Problem it Solves**:  
> When an application modifies data on the primary server (*Publisher*), SQL Server validates constraints. When the transaction replicates to the subscriber (*Subscriber*), re-evaluating the same rules introduces CPU overhead and potential synchronization errors. With `NOT FOR REPLICATION`, SQL Server on the Subscriber assumes data was already validated on the Publisher and writes it directly.
> 
> **2. Execution Behavior by Actor**:
> * **Regular Applications & Users**: `CHECK constraint` is **enforced normally**.
> * **Replication Agent**: Constraint evaluation is **bypassed**, persisting replicated rows directly.
> 
> **3. Applicable Objects**:
> * **`CHECK Constraints`**: Bypasses logical checks on Subscribers.
> * **`FOREIGN KEY Constraints`**: Prevents FK failures on Subscribers if Parent/Child rows replicate out-of-order.
> * **`IDENTITY` Columns**: `IDENTITY(1,1) NOT FOR REPLICATION` allows the agent to insert original Publisher keys (`IDENTITY_INSERT`) without auto-incrementing.
> * **`TRIGGERS` (`AFTER` / `INSTEAD OF`)**: `CREATE TRIGGER ... NOT FOR REPLICATION` prevents double-firing audit/integration triggers on Subscribers.
> 
> **4. Exam Distinction (`NOT FOR REPLICATION` vs `WITH NOCHECK`)**:
> * `NOT FOR REPLICATION`: Rule **remains active** for regular users/apps, bypassing only the Replication Agent (`sys.check_constraints.is_not_for_replication = 1`).
> * `WITH NOCHECK`: Disables validation for **ALL** users/operations, marking the constraint as *untrusted* (`is_not_trusted = 1`).

### DEFAULT

```sql
CREATE TABLE dbo.AuditLog (
    LogId       int             NOT NULL IDENTITY PRIMARY KEY,
    EventType   nvarchar(50)    NOT NULL,
    CreatedAt   datetime2(0)    NOT NULL DEFAULT GETUTCDATE(),
    CreatedBy   nvarchar(128)   NOT NULL DEFAULT SUSER_SNAME(),
    IsProcessed bit             NOT NULL DEFAULT 0
);
```

---

## Disabling and Enabling Constraints

```sql
-- Disable FK during bulk load
ALTER TABLE dbo.Orders NOCHECK CONSTRAINT FK_Orders_Customers;

-- Re-enable and verify existing data (Note the double CHECK keywords!)
-- 1st CHECK (WITH CHECK): Validates existing data.
-- 2nd CHECK (CHECK CONSTRAINT): Action to ENABLE the constraint.
ALTER TABLE dbo.Orders WITH CHECK CHECK CONSTRAINT FK_Orders_Customers;

-- Disable all triggers on a table
ALTER TABLE dbo.Orders DISABLE TRIGGER ALL;
```

---

## ⚡ Impact of Constraints & Sequences on Execution Plans & Performance (MS Learn)

In SQL Server, constraints and key generators do not merely enforce data integrity — they provide **vital metadata directly to the Query Optimizer (QO)**. The QO uses this metadata to simplify execution plans, eliminate unnecessary I/O, and accurately estimate cardinality.

Conversely, misconfigured or poorly designed constraints can introduce **severe write overhead, lock/page contention (PAGELATCH), and full table scans**.

---

### 1. `PRIMARY KEY`

* **How it Helps Execution Plans**:
  * **Contradiction Elimination**: A query with an impossible predicate like `WHERE ProductId = 10 AND ProductId = 20` prompts the QO to produce an instant **`Constant Scan`** operator with 0 estimated rows, performing 0 disk/logical reads.
  * **FK Join Elimination**: In an `INNER JOIN` between a child table and a parent table with a PK, if the query selects only child columns (or the key itself), the QO completely removes the JOIN operator from the final plan.
  * **Exact Cardinality Estimation**: Because PK equality density is `1 / N`, the QO estimates with 100% precision that the lookup will return **at most 1 row**. This prevents excessive/insufficient **Memory Grants** and avoids TempDB spills.
  * **Default Clustered Index**: Defines physical data ordering on disk for high-performance range scans.

* **How it Hurts / Overhead**:
  * **Write Overhead & Fragmentation**: Every `INSERT`, `UPDATE` on PK, or `DELETE` requires updating the B-Tree index. Using non-sequential PKs (e.g., `NEWID()`) causes severe **Page Splits** and index fragmentation.
  * **Last-Page Insert Contention (`PAGELATCH_EX`)**: High-concurrency inserts using `IDENTITY(1,1)` on multi-core hardware can cause thread contention on the last leaf page of the index (`PAGELATCH_EX`).

> [!TIP] Tuning & DP-800 Exam Tip: What is the optimal `FILLFACTOR` for `UNIQUEIDENTIFIER` (GUID) PKs?
> 
> The appropriate **`FILLFACTOR`** for a `UNIQUEIDENTIFIER` Primary Key depends on **HOW** the GUIDs are generated:
> 
> 1. **Random GUIDs (`NEWID()` or `Guid.NewGuid()` in application code)**:
>    * **Optimal `FILLFACTOR`**: **70% to 80%** (leaving **20% to 30% free space** per 8KB page upon `REBUILD`).
>    * *Why*: Random GUIDs cause mid-index inserts (*Random Inserts*). If pages are 100% full (`FILLFACTOR = 100`), **every insert forces a Page Split** (splitting 8KB pages in half), causing log write bursts (`WRITELOG`), severe physical fragmentation, and high I/O. Free space of 20%-30% absorbs new writes until the next index maintenance window.
> 
> 2. **Sequential GUIDs (`NEWSEQUENTIALID()`)**:
>    * **Optimal `FILLFACTOR`**: **100% (or 0 - Default)**.
>    * *Why*: `NEWSEQUENTIALID()` generates GUIDs in ascending order (based on MAC address and timestamp). Inserts always occur at the end of the index (*Sequential Append*), eliminating mid-page splits.
> 
> 3. **Best Architectural Practice**:
>    * Whenever possible, avoid using random GUIDs as a `PRIMARY KEY CLUSTERED`. The optimal design is to use an `IDENTITY` or `BIGINT` as the **Clustered PK**, and create a **`UNIQUE NONCLUSTERED INDEX`** on the `UNIQUEIDENTIFIER` column.

---

### 2. `FOREIGN KEY`

* **How it Helps Execution Plans**:
  * **Redundant Join Elimination**: If the FK is **trusted (`is_not_trusted = 0`)**, the QO can eliminate unnecessary JOINs to parent tables in views/complex queries when parent columns are omitted from `SELECT`.
  * **Star Join Optimization**: Trusted FKs in Star Schemas allow automatic creation of Bitmap filters to accelerate Fact-Dimension joins.

* **How it Hurts / Overhead**:
  * **FK Lookups**: Every `INSERT`/`UPDATE` on a child table probes the parent table. A `DELETE` on a parent probes the child table.
  * **Missing FK Index Penalty**: SQL Server **does NOT automatically create indexes** on child FK columns. Deleting a parent row triggers a **full Table Scan / Index Scan on the child table** to check for orphans, risking lock escalation and severe latency.
  * **Untrusted FK Penalty (`is_not_trusted = 1`)**: FKs created with `WITH NOCHECK` or re-enabled without `WITH CHECK` are marked `is_not_trusted = 1`. **The QO disables Join Elimination**, treating the FK only as a write-check rule with zero read optimization benefits!

---

### 3. `UNIQUE CONSTRAINT` / `UNIQUE INDEX`

* **How it Helps Execution Plans**:
  * **Aggregate Removal (`GROUP BY` / `DISTINCT`)**: A query with `SELECT DISTINCT SSN FROM Employees` or `GROUP BY SSN` allows the QO to **eliminate Stream/Hash Aggregate operators**, saving CPU and memory.
  * **Join Operator Selection**: Knowing uniqueness is guaranteed, the QO prefers **`Nested Loops`** over memory-intensive `Hash Joins`.

* **How it Hurts / Overhead**:
  * **Validation Cost**: Requires B-Tree navigation before committing each insert/update.
  * **Storage Overhead**: Creates a Nonclustered Index, consuming disk space and Buffer Pool RAM.

---

### 4. `CHECK CONSTRAINT`

* **How it Helps Execution Plans**:
  * **Predicate Contradiction Elimination**: A table with `CHECK (Amount > 0)` queried via `SELECT * FROM Orders WHERE Amount = -50` generates a **`Constant Scan` (0 disk I/O)**.
  * **Partition Elimination in Partitioned Views**: In `UNION ALL` Partitioned Views, `CHECK` constraints on boundary columns allow the QO to skip non-relevant physical tables completely.

* **How it Hurts / Overhead**:
  * **CPU Expression Evaluation**: Complex expressions (`LIKE` regex, logical operators) run per row on writes.
  * **Untrusted Check Penalty**: Checks marked `is_not_trusted = 1` disable contradiction elimination, forcing physical table scans even for impossible predicates.

---

### 5. `DEFAULT CONSTRAINT`

* **How it Helps Execution Plans**: Ensures columns contain valid values rather than `NULL`, improving column statistics accuracy and avoiding non-sargable functions like `ISNULL()` in queries.
* **How it Hurts / Overhead**: Non-deterministic default functions (`NEWID()`, `CRYPT_GEN_RANDOM()`) add CPU overhead per inserted row.

---

### 6. Key Generators: `IDENTITY` vs `SEQUENCE`

| Feature | Performance Benefit | Performance Overhead / Penalty |
| :--- | :--- | :--- |
| **`IDENTITY`** | • In-memory generation with light internal locks (`SCH_M_CURR`).<br>• Extremely low storage footprint (`INT` / `BIGINT`). | • **`PAGELATCH_EX` Contention**: Heavy concurrent inserts contend for the last leaf page.<br>• Cannot obtain the ID **prior** to `INSERT`. |
| **`SEQUENCE`** | • Pre-fetches IDs **before `INSERT`** (`NEXT VALUE FOR`), enabling high-speed Bulk Inserts.<br>• **`CACHE N`**: Pre-allocates range in RAM, eliminating disk access during key generation. | • **Severe `NOCACHE` Bottleneck**: Setting `NOCACHE` forces a **synchronous disk write** to `sysseqobj` on every single call (`WRITELOG` waits).<br>• Gap loss on unexpected server restarts when `CACHE` is enabled (by design). |

---

## SEQUENCES

A **SEQUENCE** is a schema-bound object that generates a sequence of numeric values, independent of any table — useful when the same sequence must be shared across tables.

```sql
-- Create a sequence
CREATE SEQUENCE dbo.OrderNumberSeq
    AS int
    START WITH 10000
    INCREMENT BY 1
    MINVALUE 10000
    MAXVALUE 99999
    CYCLE
    CACHE 50;

-- Use the sequence
INSERT INTO dbo.Orders (OrderId, CustomerId)
VALUES (NEXT VALUE FOR dbo.OrderNumberSeq, 1);

-- Get current value without incrementing
SELECT current_value FROM sys.sequences
WHERE name = 'OrderNumberSeq';

-- Use as default in table
CREATE TABLE dbo.Invoices (
    InvoiceId   int NOT NULL DEFAULT (NEXT VALUE FOR dbo.OrderNumberSeq) PRIMARY KEY,
    Amount      decimal(10,2) NOT NULL
);
```

> [!warning] Common Mistake
> IDENTITY and SEQUENCE both generate sequential numbers, but IDENTITY cannot be shared across tables and is tied to a specific column. If the exam scenario requires a shared counter across multiple tables, the answer is SEQUENCE.

> [!warning] DP-800 Exam Gotchas: `MERGE` Statement Rules with `SEQUENCE` & Business Keys
> 
> * **Syntax Restriction (Msg 11742)**: Calling `NEXT VALUE FOR` directly inside the `VALUES (...)` clause of a `MERGE ... WHEN NOT MATCHED THEN INSERT` statement is **prohibited by T-SQL**. You MUST define the `SEQUENCE` as a `DEFAULT` constraint on the target table column (`ColName INT NOT NULL DEFAULT (NEXT VALUE FOR dbo.MySeq)`). In the `MERGE` statement, omit the sequence column from the `INSERT` column list (or pass `DEFAULT`).
> * **Duplicate Source Keys (Msg 2627)**: The `MERGE` statement evaluates `Source` rows against `Target` state at the start of statement execution. If the `Source` subquery contains duplicate join keys (e.g. `TX-102` twice in a `UNION ALL` subquery while `Target` is empty), `MERGE` will attempt to insert both rows into `Target`, triggering `Msg 2627 (Violation of UNIQUE KEY constraint)`.
> * **ETL Architectural Pattern**: Process different ingestion sources/channels sequentially (e.g., Batch 1 E-Commerce, then Batch 2 Store) or deduplicate the `Source` subquery using `ROW_NUMBER() OVER (PARTITION BY BusinessKey ORDER BY ...)` prior to executing `MERGE`. This guarantees `WHEN MATCHED` correctly updates existing entities without wasting `SEQUENCE` IDs.

**SEQUENCE vs IDENTITY comparison:**

| Aspect | IDENTITY | SEQUENCE |
| :--- | :--- | :--- |
| Scope | Single table | `Schema-wide, multi-table` |
| Start/restart | Cannot restart easily | `ALTER SEQUENCE ... RESTART` |
| Caching | No | Yes (`CACHE n`) — faster but gaps on crash |
| Use in SELECT | No | `NEXT VALUE FOR` in any query |
| Transaction rollback | No gap recovery | No gap recovery (same) |

---

## CHECK Constraint Patterns

CHECK constraints can encode complex business rules beyond simple comparisons. Key patterns include multi-column checks, pattern matching with LIKE, and deferred validation.

- **Multi-column CHECK**: The expression can reference any columns in the same row, enabling cross-column business rules
- **LIKE patterns**: Use `[0-9]`, `[A-Z]`, and `%`/`_` wildcards to validate string formats
- **Deterministic functions only**: Non-deterministic functions (e.g., `GETDATE()`, `RAND()`) are not allowed in CHECK expressions
- **NOT FOR REPLICATION**: Skips the constraint during replication agent operations; constraint still fires for normal user writes
- **WITH NOCHECK**: Adds the constraint without scanning existing rows — useful for large tables but marks the constraint as "not trusted"

```sql
-- Pattern validation
ALTER TABLE Customers ADD CONSTRAINT CK_Phone
    CHECK (Phone LIKE '[0-9][0-9][0-9]-[0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]');

-- Multi-column: end date must be after start date
ALTER TABLE Projects ADD CONSTRAINT CK_ProjectDates
    CHECK (EndDate IS NULL OR EndDate > StartDate);

-- Add without validating existing data
ALTER TABLE Orders WITH NOCHECK ADD CONSTRAINT CK_Positive
    CHECK (TotalAmount > 0);

-- Check if constraint is trusted (validated)
SELECT name, is_not_trusted FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('Orders');
```

A constraint added with `WITH NOCHECK` sets `is_not_trusted = 1` in `sys.check_constraints`. The query optimizer cannot use an untrusted constraint for plan optimizations. To trust it, run `ALTER TABLE ... WITH CHECK CHECK CONSTRAINT ...`.

---

## Cascading Referential Actions

ON DELETE and ON UPDATE actions define what happens to child rows when a parent row is deleted or its key is changed.

| Action | Behavior |
| :--- | :--- |
| `NO ACTION` | Raises an error; transaction rolls back if child rows exist |
| `CASCADE` | Automatically deletes or updates matching child rows |
| `SET NULL` | Sets the FK column(s) to NULL (columns must be nullable) |
| `SET DEFAULT` | `Sets the FK column(s) to their defined default value` |

**Circular reference limitation**: SQL Server does not allow `CASCADE` in a referential cycle. Self-referencing tables or mutual FK cycles must use `NO ACTION` and handle deletes manually (e.g., set ManagerID to NULL before deleting the manager row).

**Multi-level chains**: CASCADE fires recursively. A delete on a grandparent table can cascade through two or more child tables automatically, which can delete more rows than expected.

```sql
-- CASCADE: delete child rows when parent is deleted
ALTER TABLE OrderItems
ADD CONSTRAINT FK_OrderItems_Orders
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID)
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

-- SET NULL: nullify FK when parent deleted (column must be nullable)
ALTER TABLE Employees
ADD CONSTRAINT FK_Employees_Manager
    FOREIGN KEY (ManagerID) REFERENCES Employees(EmployeeID)
    ON DELETE SET NULL;
```

---

## Sequence Cycling and Caching

Beyond basic creation, sequences support fine-grained control over cycling behavior and in-memory caching.

- **CYCLE / NO CYCLE**: When the sequence reaches MAXVALUE, `CYCLE` wraps back to MINVALUE; `NO CYCLE` raises an error instead
- **CACHE n**: Pre-allocates `n` values in memory, reducing disk I/O per call; SQL Server writes the "next batch start" to disk, not each individual value
- **NO CACHE**: Every `NEXT VALUE FOR` call writes to disk — no gaps, but higher I/O overhead
- **Gap behavior**: On a server restart, all in-memory cached values are lost. The sequence resumes at the start of the next uncached batch, creating a gap equal to the unused portion of the cache
- **RESTART WITH**: Resets the current position to any valid value; useful for testing or re-seeding

```sql
-- Sequence with cycling and caching
CREATE SEQUENCE dbo.OrderSeq
    AS INT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9999999
    CYCLE
    CACHE 50;

-- Reset sequence
ALTER SEQUENCE dbo.OrderSeq RESTART WITH 1;

-- Peek at next value without incrementing
SELECT current_value FROM sys.sequences WHERE name = 'OrderSeq';

-- Use sequence in default
ALTER TABLE Orders ADD CONSTRAINT DF_OrderID DEFAULT (NEXT VALUE FOR dbo.OrderSeq) FOR OrderID;
```

---

## UNIQUE Constraints vs UNIQUE Indexes

A UNIQUE constraint and a unique index are nearly identical in SQL Server — the constraint is implemented as a unique non-clustered index behind the scenes.

| Feature | UNIQUE Constraint | Filtered UNIQUE Index |
| :--- | :--- | :--- |
| Allows NULLs | One NULL per column | `Multiple NULLs (NULLs excluded from index)` |
| Syntax | `ADD CONSTRAINT ... UNIQUE` | `CREATE UNIQUE INDEX ... WHERE col IS NOT NULL` |
| Visible in SSMS | As a constraint | As an index |

- A UNIQUE constraint permits exactly **one NULL** because SQL Server considers a second NULL a duplicate
- A **filtered unique index** with `WHERE col IS NOT NULL` excludes NULLs entirely, allowing multiple NULL values in the column

```sql
-- Filtered unique index: multiple NULLs allowed, non-NULLs must be unique
CREATE UNIQUE NONCLUSTERED INDEX UIX_Employees_NationalID
ON dbo.Employees (NationalID)
WHERE NationalID IS NOT NULL;
```

---

## Use Cases

- **PRIMARY KEY**: Every table should have one — defines entity identity
- **FOREIGN KEY**: Enforce referential integrity between related tables
- **CHECK**: Enforce domain rules (valid statuses, positive values, date ranges)
- **SEQUENCE**: Invoice numbers, order numbers shared across multiple tables

---

## Common Issues & Errors

| Error | Cause | Resolution |
| :--- | :--- | :--- |
| FK violation on INSERT | Referenced row doesn't exist | Insert parent row first; or disable FK temporarily |
| Duplicate key on INSERT | UNIQUE or PK violation | Check for existing values; use `MERGE` or upsert |
| CHECK constraint violation | Value fails the condition | Validate at application layer before insert |
| SEQUENCE cache gap | Server restart with CACHE | `Use `NO CACHE` for sequential gaps (slower)` |
| `Msg 11742` (MERGE with SEQUENCE) | Direct `NEXT VALUE FOR` call inside `MERGE ... VALUES (...)` | Define `SEQUENCE` as `DEFAULT` constraint on target table and omit column from `INSERT` |
| Cascade cycle error | FK chain creates a cycle | Use `NO ACTION` on one FK; handle deletes in code |
| Untrusted constraint | Added with `WITH NOCHECK` | Re-validate with `WITH CHECK CHECK CONSTRAINT` |

---

## Best Practices

- Always name constraints explicitly (`CONSTRAINT PK_...`, `CONSTRAINT FK_...`) rather than relying on system-generated names — improves maintainability and scripting
- Prefer `WITH CHECK CHECK CONSTRAINT` when re-enabling disabled constraints to ensure existing data is validated and the constraint is trusted
- Use `WITH NOCHECK` only during large bulk migrations; immediately validate and trust the constraint afterward
- Avoid `CASCADE DELETE` on wide FK chains — explicit deletes in stored procedures are easier to audit and debug
- Use `NO CACHE` sequences only when gaps are truly unacceptable; the performance cost can be significant at high insert rates

---

## Exam Tips

> [!tip] Exam Tips
>
> - `PRIMARY KEY` creates a clustered index by default — can be overridden with `NONCLUSTERED`
> - `UNIQUE` allows one NULL value per column; a filtered unique index can exclude NULLs entirely
> - `CHECK` constraints added with `WITH NOCHECK` are marked `is_not_trusted = 1` — the optimizer ignores them for plan simplification
> - `SEQUENCE` can `CYCLE` (wrap around) and `CACHE` values for performance; cached values are lost on server restart
> - `CASCADE` cannot be used in a circular FK reference — SQL Server raises an error at constraint creation time
> - `NOT FOR REPLICATION` on CHECK and FK constraints prevents them from firing during replication agent operations

---

## Key Takeaways

- Constraints enforce data integrity at the database engine level — not just at the application
- FOREIGN KEY referential actions (`CASCADE`, `SET NULL`, `SET DEFAULT`) control child row behavior
- SEQUENCES are more flexible than IDENTITY but require explicit `NEXT VALUE FOR`
- CHECK constraints added without validation (`WITH NOCHECK`) are untrusted and ignored by the optimizer

---

## Practice Question

**Practice Question**

A sequence with CACHE 50 has a current value of 450. After a SQL Server restart, the next value returned is 501. Why?

A. The sequence CYCLE option reset it to the start

B. The cached values (451-500) were lost when the server restarted

C. The sequence was altered with RESTART WITH 501

D. A concurrent transaction consumed values 451-500

> [!success]- Answer
> **B — The cached values (451-500) were lost when the server restarted**
>
> When a sequence uses CACHE, SQL Server pre-allocates a batch of values in memory. If the server restarts before all cached values are used, those values are lost and the sequence resumes after the last cached batch. This is by design for performance — use NO CACHE if gaps are unacceptable.

---

## Related Topics

- [01-Tables & Indexes](./01-tables-indexes.md)
- [05-Partitioning](./05-partitioning.md)

---

## Official Documentation

- [Constraints (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/tables/unique-constraints-and-check-constraints)
- [CREATE SEQUENCE (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-sequence-transact-sql)

---

**[← Previous](./03-json-columns.md) | [↑ Back to Section](./database-objects.md) | [Lab: Constraints and Sequences](../../practice/labs/01-database-objects/04-constraints-sequences-lab.sql) | [Next →](./05-partitioning.md)**
