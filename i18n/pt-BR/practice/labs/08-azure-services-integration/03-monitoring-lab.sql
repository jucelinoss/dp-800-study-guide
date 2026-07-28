-- =================================================================================
-- DP-800 - LAB PRÁTICO: MONITORAMENTO DE RECURSOS E DIAGNÓSTICO COM KQL E DMVS
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra técnicas de monitoramento no Azure SQL Database:
--   1. Consulta de Consumo de Recursos via DMVs (`sys.dm_db_resource_stats` e `sys.dm_exec_requests`)
--   2. Identificação de Waists Dominantes na Instância via `sys.dm_os_wait_stats`
--   3. Estruturação de Consultas Kusto Query Language (KQL) para Log Analytics
--   4. Configuração de Alertas do Azure Monitor via Azure CLI (`az monitor metrics alert`)
--   5. Cenários Práticos de Projeto (Investigação de Exaustão de vCores / DTUs e Deadlocks)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/08-azure-services-integration/03-monitoring.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================

USE AdventureWorks2025;
GO


-- =================================================================================
-- PARTE 1: DIAGNÓSTICO DE RECURSOS NATIVO VIA DMVS NO BANCO DE DADOS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - sys.dm_db_resource_stats: Retorna a porcentagem de uso de CPU, I/O e memória a cada 15 segundos para o Azure SQL DB.
--   - sys.dm_exec_requests: Exibe todas as requisições em execução no momento, identificando sessões bloqueadas e CPU consumida.

-- 1. Consultar consumo recente de recursos do banco de dados (Últimas amostras de 15s)
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

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Consultar as consultas ativas com maior tempo de execução ou espera
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
-- PARTE 2: CONSULTAS KQL PARA LOG ANALYTICS (LOGS DO AZURE MONITOR)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DIAGNOSTIC SETTINGS: Configuração no portal Azure para exportar logs para um Log Analytics Workspace.
--   - KQL (Kusto Query Language): Linguagem usada para consultar tabelas `AzureDiagnostics` e `AzureMetrics`.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Exemplo de Script KQL para extrair Grafos de Deadlock capturados no Log Analytics (Consulta KQL)
/*
AzureDiagnostics
| where Category == "Deadlocks"
| where TimeGenerated >= ago(24h)
| project TimeGenerated, Resource, deadlock_xml_s
| order by TimeGenerated desc
*/

-- Exemplo de Script KQL para identificar consultas mais custosas por CPU
/*
AzureDiagnostics
| where Category == "QueryStoreRuntimeStatistics"
| project TimeGenerated, query_id_d, avg_cpu_time_d, count_executions_d, Resource
| top 10 by avg_cpu_time_d desc
*/
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Automação de Alertas via Azure CLI (CLI Command Set)
-- Script para criar regras de alerta caso o consumo de CPU ultrapasse 80% por 5 minutos consecutivos.

SELECT 
    'az monitor metrics alert create' AS ComandoCLI,
    'HighCPU-Alert' AS NomeAlerta,
    '--condition "avg cpu_percent > 80"' AS CondicaoGatilho,
    '--window-size 5m --evaluation-frequency 1m' AS JanelaAvaliacao,
    'Envia notificacao por e-mail/webhook para o grupo DBA_Team' AS AcaoAutomacao;
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/08-azure-services-integration/03-monitoring.md
-- =================================================================================================
