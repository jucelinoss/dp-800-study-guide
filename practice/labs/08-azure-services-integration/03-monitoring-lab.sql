-- =================================================================================
-- DP-800 - HANDS-ON LAB: RESOURCE MONITORING AND DIAGNOSTICS WITH KQL AND DMVS
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and the other lab scripts, restore the AdventureWorks
-- (OLTP) database backup available at:
-- https://learn.microsoft.com/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates Azure SQL Database monitoring techniques:
--   1. Resource-consumption queries through DMVs (`sys.dm_db_resource_stats` and `sys.dm_exec_requests`)
--   2. Identification of dominant instance waits through `sys.dm_os_wait_stats`
--   3. Kusto Query Language (KQL) query patterns for Log Analytics
--   4. Azure Monitor alert configuration through Azure CLI (`az monitor metrics alert`)
--   5. Practical design scenarios (vCore/DTU exhaustion and deadlock investigation)
-- =================================================================================

USE AdventureWorks2025;
GO


-- =================================================================================
-- PART 1: NATIVE DMV-BASED RESOURCE DIAGNOSTICS IN THE DATABASE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - sys.dm_db_resource_stats: Returns CPU, I/O, and memory utilization percentages for Azure SQL Database every 15 seconds.
--   - sys.dm_exec_requests: Shows requests currently executing, including blocked sessions and CPU consumption.

-- 1. Query recent database resource consumption (latest 15-second samples)
SELECT TOP 10
    end_time AS HorarioAmostra,
    avg_cpu_percent AS PercentualCpuMedio,
    avg_data_io_percent AS PercentualIoDadosMedio,
    avg_log_write_percent AS PercentualIoLogMedio,
    avg_memory_usage_percent AS PercentualMemoriaMedio,
    xtp_storage_percent AS PercentualInMemoryOLTP
FROM sys.dm_db_resource_stats
ORDER BY end_time DESC;
GO

-- [DP-800 EXAM TIP]
-- 2. Query active requests with the highest execution or wait time
SELECT 
    r.session_id AS ID_Sessao,
    r.status AS StatusExecucao,
    r.command AS Comando,
    r.cpu_time AS TempoCPU_MS,
    r.total_elapsed_time AS DuracaoTotal_MS,
    r.wait_type AS TipoEspera,
    r.blocking_session_id AS BloqueadoPor,
    t.text AS QueryText
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID;
GO


-- =================================================================================
-- PART 2: KQL QUERIES FOR LOG ANALYTICS (AZURE MONITOR LOGS)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DIAGNOSTIC SETTINGS: Azure portal configuration that exports logs to a Log Analytics workspace.
--   - KQL (Kusto Query Language): The language used to query `AzureDiagnostics` and `AzureMetrics` tables.

-- [DP-800 EXAM TIP]
-- Example KQL script that extracts deadlock graphs captured in Log Analytics
/*
AzureDiagnostics
| where Category == "Deadlocks"
| where TimeGenerated >= ago(24h)
| project TimeGenerated, Resource, deadlock_xml_s
| order by TimeGenerated desc
*/

-- Example KQL script that identifies the most CPU-intensive queries
/*
AzureDiagnostics
| where Category == "QueryStoreRuntimeStatistics"
| project TimeGenerated, query_id_d, avg_cpu_time_d, count_executions_d, Resource
| top 10 by avg_cpu_time_d desc
*/
GO


-- =================================================================================
-- PART 3: PRACTICAL DESIGN SCENARIOS
-- =================================================================================

-- SCENARIO 1: Alert automation through Azure CLI (CLI command set)
-- Script that creates alert rules when CPU consumption exceeds 80% for five consecutive minutes.

SELECT 
    'az monitor metrics alert create' AS ComandoCLI,
    'HighCPU-Alert' AS NomeAlerta,
    '--condition "avg cpu_percent > 80"' AS CondicaoGatilho,
    '--window-size 5m --evaluation-frequency 1m' AS JanelaAvaliacao,
    'Envia notificacao por e-mail/webhook para o grupo DBA_Team' AS AcaoAutomacao;
GO
