---
title: Stored Procedures
type: study-material
tags:
  - dp-800
  - stored-procedures
  - t-sql
  - execute-as
---

> [!info] 🗺️ Quick Navigation Index
>
> - 📍 [1. Overview](#overview)
> - 📍 [2. Stored Procedure Development](#creating-stored-procedures)
>   - 🔹 [Creating Stored Procedures](#creating-stored-procedures)
>   - 🔹 [Output Parameters](#output-parameters)
>   - 🔹 [Table-Valued Parameters](#table-valued-parameters)
>   - 🔹 [Error Handling](#error-handling)
> - 📍 [3. Advanced Architecture, Security & Performance](#execute-as--security-context)
>   - 🔹 [EXECUTE AS — Security Context](#execute-as--security-context)
>   - 🔹 [Recompilation and Plan Caching](#recompilation)
>   - 🔹 [sp_executesql for Dynamic SQL](#sp_executesql-for-dynamic-sql)
>   - 🔹 [Natively Compiled Stored Procedures](#natively-compiled-stored-procedures)
> - 📍 [4. Practical Application & Summary](#use-cases)
>   - 🔹 [Use Cases](#use-cases)
>   - 🔹 [Common Issues](#common-issues--errors)
>   - 🔹 [Best Practices & Exam Tips](#best-practices)
>   - 🔹 [Practice Question](#practice-question)

---

# Stored Procedures

## Overview

Stored procedures are precompiled T-SQL batches stored in the database. They support parameters (input, output, table-valued), error handling, transaction control, and security context switching.

> [!abstract]
>
> - Covers stored procedure creation, parameters (INPUT/OUTPUT), dynamic SQL, error handling, and execution context
> - Stored procedures encapsulate logic, support plan reuse, and can use EXECUTE AS for security context
> - Key exam topics: sp_executesql vs EXEC for dynamic SQL, TRY/CATCH with XACT_STATE, OUTPUT parameters

> [!tip] What the Exam Tests
>
> - `sp_executesql` is parameterized (prevents SQL injection + enables plan reuse); `EXEC(@sql)` is not parameterized
> - OUTPUT parameters pass values back to the caller; declared with `@param datatype OUTPUT` in both definition and call
> - In a CATCH block: `XACT_STATE() = -1` means the transaction is uncommittable — you MUST ROLLBACK before doing anything else

---

## Creating Stored Procedures

```sql
CREATE PROCEDURE dbo.usp_GetCustomerOrders
    @CustomerId  int,
    @StartDate   date = NULL,
    @EndDate     date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        o.OrderId,
        o.OrderDate,
        o.TotalAmount
    FROM dbo.Orders o
    WHERE o.CustomerId = @CustomerId
      AND (@StartDate IS NULL OR o.OrderDate >= @StartDate)
      AND (@EndDate   IS NULL OR o.OrderDate <= @EndDate)
    ORDER BY o.OrderDate DESC;
END;
GO

-- Execute
EXEC dbo.usp_GetCustomerOrders @CustomerId = 42, @StartDate = '2025-01-01';
```

---

## Output Parameters

```sql
CREATE PROCEDURE dbo.usp_CreateOrder
    @CustomerId  int,
    @OrderId     int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Orders (CustomerId, OrderDate)
    VALUES (@CustomerId, GETUTCDATE());

    SET @OrderId = SCOPE_IDENTITY();
END;
GO

-- Execute with OUTPUT
DECLARE @NewOrderId int;
EXEC dbo.usp_CreateOrder @CustomerId = 1, @OrderId = @NewOrderId OUTPUT;
SELECT @NewOrderId AS NewOrderId;
```

---

## Table-Valued Parameters

```sql
-- Create the table type
CREATE TYPE dbo.OrderItemList AS TABLE (
    ProductId   int             NOT NULL,
    Quantity    int             NOT NULL,
    UnitPrice   decimal(10,2)   NOT NULL
);
GO

-- Use it in a procedure
CREATE PROCEDURE dbo.usp_InsertOrderItems
    @OrderId    int,
    @Items      dbo.OrderItemList READONLY -- Must be READONLY
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.OrderItems (OrderId, ProductId, Quantity, UnitPrice)
    SELECT @OrderId, ProductId, Quantity, UnitPrice
    FROM @Items;
END;
GO
```

> [!important] TVPs must be READONLY
>
> - Table-valued parameters (TVPs) must **always be passed as READONLY** to a stored procedure.
> - You cannot modify TVP rows directly inside the procedure with `UPDATE`, `INSERT`, or `DELETE`.

---

## Error Handling

```sql
CREATE PROCEDURE dbo.usp_TransferFunds
    @FromAccountId  int,
    @ToAccountId    int,
    @Amount         decimal(18,2)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE dbo.Accounts SET Balance -= @Amount WHERE AccountId = @FromAccountId;
        UPDATE dbo.Accounts SET Balance += @Amount WHERE AccountId = @ToAccountId;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;  -- Re-raise the error to the caller
    END CATCH;
END;
GO
```

**Error functions in CATCH:**

| Function | Returns |
| :--- | :--- |
| `ERROR_NUMBER()` | SQL error number |
| `ERROR_MESSAGE()` | `Error description` |
| `ERROR_SEVERITY()` | Severity level (1-25) |
| `ERROR_STATE()` | Error state |
| `ERROR_LINE()` | Line number where error occurred |
| `ERROR_PROCEDURE()` | Procedure name |

---

## EXECUTE AS — Security Context

`EXECUTE AS` changes the security context for the procedure's execution:

```sql
-- Execute as a specific user
CREATE PROCEDURE dbo.usp_GetSensitiveData
WITH EXECUTE AS 'ReportUser'
AS
BEGIN
    SELECT * FROM dbo.SensitiveTable;  -- runs as ReportUser
END;

-- Execute as the procedure owner (schema owner)
CREATE PROCEDURE dbo.usp_CrossSchemaQuery
WITH EXECUTE AS OWNER
AS
BEGIN
    SELECT * FROM OtherSchema.Table1;
END;
```

**EXECUTE AS options:** `CALLER` (default; inherits the caller's context), `SELF` (the object's current creator or owner), `OWNER` (the procedure schema owner), and `'username'` (a specific user).

> [!warning] EXECUTE AS CALLER vs. OWNER vs. USER
>
> - **CALLER (default):** Executes with the privileges of the principal calling the procedure.
> - **OWNER:** Executes with the permissions of the object's schema owner; useful to bridge broken ownership chains without exposing base tables.
> - **'username':** Executes as a specific user; requires `IMPERSONATE` permission on that user.

---

## Recompilation

```sql
-- Force recompile once (for parameter-sensitive queries)
EXEC dbo.usp_GetCustomerOrders @CustomerId = 42 WITH RECOMPILE;

-- Force recompile every execution (for highly variable data)
CREATE PROCEDURE dbo.usp_VariableQuery
WITH RECOMPILE
AS ...
```

> [!tip] Exam tip: sniffing vs. recompile
>
> - When only one query within a procedure has highly variable cardinality, use `OPTION(RECOMPILE)` on that query rather than recompiling the entire procedure with `WITH RECOMPILE`. This avoids unnecessary CPU consumption.

---

## sp_executesql for Dynamic SQL

Use **`sp_executesql`** instead of `EXEC(@sql)` for parameterization, plan caching, and SQL injection prevention.

**Why sp_executesql over EXEC(@sql):**

- **Parameterization** — values passed as parameters, not concatenated into the string
- **Plan caching** — same statement hash is reused across calls with different parameter values
- **SQL injection prevention** — user input cannot alter the query structure

**Syntax:** `EXEC sp_executesql @stmt, N'@param1 type, @param2 type', @param1 = value, @param2 = value`

**When you must use dynamic SQL:** dynamic column/table names, dynamic ORDER BY, runtime-determined object names

```sql
-- Unsafe: concatenation = SQL injection risk + no plan reuse
DECLARE @sql NVARCHAR(MAX);
SET @sql = 'SELECT * FROM Orders WHERE CustomerID = ' + @CustomerID;
EXEC(@sql);  -- BAD: no parameterization

-- Safe: sp_executesql with parameters
SET @sql = 'SELECT * FROM Orders WHERE CustomerID = @CustID';
EXEC sp_executesql
    @sql,
    N'@CustID INT',
    @CustID = @CustomerID;  -- GOOD: parameterized, plan cacheable

-- Dynamic table name (must still sanitize)
DECLARE @TableName NVARCHAR(128) = N'Orders';
-- Validate against sys.objects first!
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = @TableName AND type = 'U')
    THROW 50001, 'Invalid table name', 1;
SET @sql = 'SELECT COUNT(*) FROM ' + QUOTENAME(@TableName);
EXEC sp_executesql @sql;
```

> [!warning] Common Mistake
> Using EXEC(@sql) with concatenated user input is a SQL injection vulnerability. Always use sp_executesql with parameters for dynamic SQL. The exam tests this distinction both as a security question and as a performance question (plan reuse).

---

## Natively Compiled Stored Procedures

Natively compiled stored procedures are compiled to machine code at creation time, providing extreme performance for OLTP workloads on In-Memory OLTP tables.

**Requirements:**

- `WITH NATIVE_COMPILATION` — compiles to native machine code
- `SCHEMABINDING` — required; prevents schema changes to referenced objects
- References only memory-optimized tables

**Limitations:**

- Limited T-SQL surface area: no temp tables, no cursors, limited JOIN types
- No `TRY/CATCH` — replaced by `ATOMIC` blocks
- No `EXEC` or dynamic SQL within the procedure

**ATOMIC blocks** replace `TRY/CATCH` and wrap all statements in an implicit transaction that either fully commits or fully rolls back.

```sql
CREATE PROCEDURE dbo.usp_InsertOrder
    @CustomerID INT,
    @TotalAmount DECIMAL(18,2)
WITH NATIVE_COMPILATION, SCHEMABINDING
AS
BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'English')
    INSERT INTO dbo.OrdersMemoryOptimized (CustomerID, TotalAmount, OrderDate)
    VALUES (@CustomerID, @TotalAmount, GETUTCDATE());
END;
```

---

## Procedure Plan Caching and Recompilation

SQL Server compiles a query plan on the first execution and caches it for reuse. **Parameter sniffing** means the cached plan is optimized for the first parameter values seen.

**When parameter sniffing is problematic:**

- First call uses an atypical (e.g., low-volume) parameter value
- Resulting plan is poor for subsequent calls with high-volume parameters
- Symptoms: fast for some inputs, slow for others with no schema changes

### Diagnosis: evidence before applying hints

Parameter sniffing is a hypothesis, not an automatic conclusion. Before using `OPTION(RECOMPILE)`, `OPTIMIZE FOR`, or another hint, gather evidence that separates it from stale statistics, a missing index, or a non-sargable predicate:

- **Actual execution plan:** compare `Estimated Rows` with `Actual Rows`, especially in operators downstream of the parameter filter. Large, repeatable variances suggest that compilation cardinality does not represent the current call.
- **I/O and CPU:** use `SET STATISTICS IO, TIME ON` with selective and nonselective parameters. Record logical reads, CPU, and elapsed time; compare equivalent calls rather than relying only on the plan's percentage cost.
- **Repeatable pattern:** confirm that slowness changes with the parameter or with the call that compiled the cached plan. A one-off incident could be a cold cache, blocking, resource waits, or concurrent activity.
- **Statistics and access:** confirm that relevant statistics are current and inspect repeated `Key Lookups`, `Nested Loops` over many rows, excessive scans, and `Sort`/`Hash` spills. Fix the index, statistics, or query before locking in a hint.

Only after this diagnosis should you choose the smallest intervention that resolves the symptom and record the reason. Reassess the decision when data volume or distribution changes.

**Solutions:**

| Option | Behavior | Cost |
| :--- | :--- | :--- |
| `OPTION(RECOMPILE)` | Recompile this query every execution | High — no plan reuse |
| `OPTIMIZE FOR (value)` | Compile plan for a specific value | Low — one plan, may not fit all |
| `OPTIMIZE FOR UNKNOWN` | `Use average statistics, not sniffed value` | Low — balanced plan |
| Local variable trick | Assign param to local var before use | Low — breaks sniffing, less sharing |
| `WITH RECOMPILE` on proc | Recompile entire procedure every call | High — use sparingly |

```sql
-- OPTION(RECOMPILE) on specific query
SELECT * FROM Orders WHERE CustomerID = @CustomerID
OPTION(RECOMPILE);

-- OPTIMIZE FOR specific value
SELECT * FROM Orders WHERE CustomerID = @CustomerID
OPTION(OPTIMIZE FOR (@CustomerID = 12345));

-- OPTIMIZE FOR UNKNOWN (use average statistics)
SELECT * FROM Orders WHERE CustomerID = @CustomerID
OPTION(OPTIMIZE FOR (@CustomerID UNKNOWN));
```

---

## Use Cases

- **Encapsulation**: Hide complex logic behind a simple interface
- **Security**: Grant `EXECUTE` on procedure without table access (ownership chaining)
- **Performance**: Compiled once, reused; reduce network round-trips
- **Transactions**: Wrap multi-step operations in a single transaction

---

## Common Issues & Errors

| Issue | Cause | Resolution |
| :--- | :--- | :--- |
| Parameter sniffing | Cached plan optimized for first parameter value | Use `OPTION (RECOMPILE)` or `OPTIMIZE FOR` |
| Nested transaction issues | Committing a savepoint vs outer transaction | Track `@@TRANCOUNT`; use `SAVE TRANSACTION` for nested |
| `SET NOCOUNT ON` missing | Verbose row count messages sent to client | Always add `SET NOCOUNT ON` in procedures |
| SQL injection via dynamic SQL | User input concatenated into query string | Use `sp_executesql` with parameters; use `QUOTENAME` for object names. |
| Natively compiled proc errors | Using unsupported T-SQL features | Check In-Memory OLTP supported surface area docs |

---

## Best Practices

- Always include `SET NOCOUNT ON` to suppress row-count messages and reduce network overhead.
- Use `sp_executesql` for all dynamic SQL; never concatenate user input directly into query strings.
- Prefer `THROW` over `RAISERROR` for re-raising errors — it preserves the original error number and message.
- Use `SCOPE_IDENTITY()` rather than `@@IDENTITY` to avoid cross-trigger identity confusion.
- Add `EXECUTE AS` with least-privilege context when procedures access objects outside the caller's normal permissions.

---

## Exam Tips

> [!tip] Exam Tips
>
> - `THROW` re-raises errors with full fidelity; `RAISERROR` is the older alternative
> - `SCOPE_IDENTITY()` returns the last identity inserted in the **current scope** (safer than `@@IDENTITY`)
> - Table-valued parameters must be declared `READONLY` in the procedure signature
> - `sp_executesql` enables plan reuse for dynamic SQL; `EXEC(@sql)` does not parameterize
> - Natively compiled procedures require `ATOMIC` blocks instead of `TRY/CATCH`
> - `OPTIMIZE FOR UNKNOWN` is the safest general fix for parameter sniffing — avoids extreme plans

---

## Key Takeaways

- Stored procedures support input, output, and table-valued parameters.
- Implement robust transactional logic with `TRY/CATCH` blocks and `THROW`.
- `EXECUTE AS` enables strict access-control patterns without direct permissions on base tables.
- Parameter sniffing can make execution times unstable; selective recompilation or average distribution statistics can address the inconsistency.

---

## Practice Question

A stored procedure that searches orders by `CustomerID` performs well for almost every search, but is extremely slow for one customer with a very high sales volume. Analysis shows that the cached execution plan was generated on its first call for a customer with very low activity. Which is the BEST approach to permanently address this performance inconsistency?

A. Add `WITH RECOMPILE` to the stored procedure definition.

B. Add the `OPTION(OPTIMIZE FOR (@CustomerID UNKNOWN))` hint to the query.

C. Rebuild all physical indexes associated with the `Orders` table.

D. Modify the internal code to run the search using `EXEC` instead of `sp_executesql`.

> [!success]- Answer
> **B — Add the `OPTION(OPTIMIZE FOR (@CustomerID UNKNOWN))` hint to the query**
>
> This scenario describes a classic *parameter sniffing* problem. `OPTIMIZE FOR UNKNOWN` instructs the optimizer to disregard the input value during compilation and use average record-distribution statistics, producing a balanced plan for any customer. Adding `WITH RECOMPILE` to the procedure (A) would force full recompilation on every execution and incur excessive CPU overhead. Rebuilding indexes (C) or changing the execution command (D) does not address cached-plan parameter sniffing.

---

## Related Topics

- [02-Functions](./02-functions.md)
- [04-Triggers](./04-triggers.md)
- [05-Correlated Queries & Error Handling](../03-advanced-tsql/05-correlated-queries-error-handling.md)

---

## Official Documentation

## Inspect a procedure result contract

Use `sys.sp_describe_first_result_set` when a caller needs metadata for the first
result set without executing the procedure's business operation.

```sql
EXEC sys.sp_describe_first_result_set
    @tsql = N'EXEC Sales.uspGetWhereUsedProductID @StartProductID = 1, @CheckDate = NULL';
```

This is useful for integration validation and generated clients. It describes only
the first result set and can fail when SQL Server cannot statically determine the
result shape, for example with some dynamic SQL paths.

- [Stored Procedures (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/stored-procedures/stored-procedures-database-engine)
- [EXECUTE AS (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/execute-as-transact-sql)
- [sp_executesql (Transact-SQL)](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-executesql-transact-sql)
- [Natively Compiled Stored Procedures](https://learn.microsoft.com/en-us/sql/relational-databases/in-memory-oltp/natively-compiled-stored-procedures)

---

**[← Previous](./02-functions.md) | [↑ Back to Section](./programmability-objects.md) | [Next →](./04-triggers.md)**
