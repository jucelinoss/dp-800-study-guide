-- =================================================================================
-- DP-800 - HANDS-ON LAB: DATABASE CONFIGURATIONS AND AUTOMATIC OPTIMIZATION
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/06-performance-optimization/01-database-configurations.md
--    Open the theory guide alongside this lab for conceptual context.
-- =================================================================================
-- CONFIGURATION NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates tuning database configurations for high performance:
--   1. Database Scoped Configurations: MAXDOP, PARAMETER_SNIFFING and CE
--   2. Query Store Configuration and Diagnostics (Activation and Plan Forcing with `sp_query_store_force_plan`)
--   3. Recommendation and Automatic Tuning Adjustment: Automatic Tuning (`sys.dm_db_tuning_recommendations`)
--   4. Memory Grants Diagnostics (Memory Grants in `sys.dm_exec_query_memory_grants`)
--   5. Practical Design Scenarios (Plan Regression Mitigation after Compatibility Upgrade)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup / restore lab default settings
-- WARNING: this changes database-scoped settings on the selected database.
-- Run in a disposable lab database or record the original values before testing.
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = ON;
GO


-- =================================================================================
-- PART 1: DATABASE SCOPED CONFIGURATIONS (MAXDOP AND PARAMETER SNIFFING)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - MAXDOP = 0: Allows using all available CPUs (default).
--   - MAXDOP = 1: Disables parallelism in the database.
--   - PARAMETER SNIFFING: Compiles the plan based on the first execution's parameters. If data is skewed,
--     this can generate suboptimal plans. Can be disabled via scope or mitigated with the `OPTION (OPTIMIZE FOR UNKNOWN)` hint.

-- -- [DP-800 EXAM TIP]
-- 1. Set MAXDOP at the database scope (e.g., limit to 4 vCores to avoid CPU exhaustion)
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 4;

-- 2. Query current scoped configurations
SELECT 
    configuration_id,
    name AS NomeConfiguracao,
    value AS ValorInstancia,
    value_for_secondary AS ValorSecundario
FROM sys.database_scoped_configurations
WHERE name IN ('MAXDOP', 'PARAMETER_SNIFFING', 'LEGACY_CARDINALITY_ESTIMATION');
GO


-- =================================================================================
-- PART 2: QUERY STORE CONFIGURATION AND EXECUTION PLAN FORCING
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - QUERY STORE: Native repository that captures query history, plans, and execution statistics.
--   - QUERY_CAPTURE_MODE = AUTO: Captures only relevant queries, avoiding storage overhead.
--   - sp_query_store_force_plan: Forces the optimizer to use a specific execution plan to prevent regressions.

-- 1. Enable and configure Query Store
ALTER DATABASE AdventureWorks2025
SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    MAX_STORAGE_SIZE_MB = 1024,
    INTERVAL_LENGTH_MINUTES = 60,
    QUERY_CAPTURE_MODE = AUTO,
    SIZE_BASED_CLEANUP_MODE = AUTO
);
GO

-- -- [DP-800 EXAM TIP]
-- 2. Query the top 5 most CPU-costly queries in Query Store
SELECT TOP 5
    q.query_id,
    qt.query_sql_text,
    qp.plan_id,
    qrs.avg_cpu_time AS TempoCpuMedio,
    qrs.count_executions AS QtdExecucoes
FROM sys.query_store_query_text qt
JOIN sys.query_store_query q ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan qp ON q.query_id = qp.query_id
JOIN sys.query_store_runtime_stats qrs ON qp.plan_id = qrs.plan_id
ORDER BY qrs.avg_cpu_time DESC;
GO

-- Find real query/plan IDs before forcing anything. Never copy arbitrary IDs from
-- an example: the plan must belong to the selected query and be retained by Query Store.
SELECT TOP (10)
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    qt.query_sql_text
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
ORDER BY q.query_id DESC, p.plan_id DESC;
GO

-- After selecting IDs from the result above, run a targeted force operation:
-- EXEC sys.sp_query_store_force_plan @query_id = <real_query_id>, @plan_id = <real_plan_id>;
GO


-- =================================================================================
-- PART 3: AUTOMATIC TUNING AND SYSTEM RECOMMENDATIONS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - AUTOMATIC TUNING: Azure SQL / SQL Server feature that detects regression and automatically forces the last good plan.
--   - sys.dm_db_tuning_recommendations: View that displays suggestions for index creation, deletion, and plan forcing.

-- Azure SQL Database/Azure SQL Managed Instance only. Do not treat this as a
-- portable server-level setting for every SQL Server installation.
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
GO

-- Query active automatic tuning recommendations
SELECT 
    name AS NomeRecomendacao,
    type AS TipoAcao,
    state AS EstadoRecomendacao,
    reason AS MotivoOtimizacao
FROM sys.dm_db_tuning_recommendations;
GO


-- =================================================================================
-- PART 4: MEMORY GRANTS DIAGNOSTICS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - MEMORY GRANTS: Memory reserved before running SORT or HASH JOIN operations.
--   - If the grant is insufficient, a spill to TempDB occurs. If excessive, memory pressure occurs on the instance.

-- Query queries currently waiting for or consuming memory grants
SELECT 
    session_id,
    request_id,
    scheduler_id,
    dop AS GrausParalelismo,
    requested_memory_kb / 1024.0 AS MemoriaSolicitadaMB,
    granted_memory_kb / 1024.0 AS MemoriaConcedidaMB,
    used_memory_kb / 1024.0 AS MemoriaUtilizadaMB,
    wait_time_ms AS TempoEsperaMemoriaMS
FROM sys.dm_exec_query_memory_grants;
GO


-- =================================================================================
-- PART 5: PRACTICAL DESIGN SCENARIOS
-- =================================================================================

--- SCENARIO 1: Compatibility Level Validation Matrix and Optimizer Features
-- Prepares the environment for safe Compatibility Level changes (e.g., migration to level 160).

SELECT 
    name AS BancoDados,
    compatibility_level AS NivelCompatibilidadeAtual,
    CASE compatibility_level
        WHEN 130 THEN 'SQL Server 2016 (Batch mode em agregados)'
        WHEN 140 THEN 'SQL Server 2017 (Adaptive Joins, Memory Grant Feedback)'
        WHEN 150 THEN 'SQL Server 2019 (Scalar UDF Inlining, Deferred Compilation)'
        WHEN 160 THEN 'SQL Server 2022 (PSP Optimization, DOP Feedback, CE Feedback)'
        ELSE 'Versão Anterior'
    END AS RecursosDisponiveis
FROM sys.databases
WHERE database_id = DB_ID();
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/06-performance-optimization/01-database-configurations.md
-- =================================================================================================
