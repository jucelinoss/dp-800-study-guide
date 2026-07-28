-- =================================================================================
-- DP-800 - LAB PRÁTICO: CONFIGURAÇÕES DE BANCO DE DADOS E OTIMIZAÇÃO AUTOMÁTICA
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/06-performance-optimization/01-database-configurations.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o ajuste de configurações de banco de dados para alta performance:
--   1. Configurações no Escopo do Banco de Dados: MAXDOP, PARAMETER_SNIFFING e CE
--   2. Configuração e Diagnóstico do Query Store (Ativação e Forçamento de Planos com `sp_query_store_force_plan`)
--   3. Recomendação e Ajuste de Automatismos: Automatic Tuning (`sys.dm_db_tuning_recommendations`)
--   4. Diagnóstico de Concessões de Memória (Memory Grants em `sys.dm_exec_query_memory_grants`)
--   5. Cenários Práticos de Projeto (Mitigação de Regressão de Plano após Atualização de Compatibilidade)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva / restauração das configurações padrão do laboratório
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = ON;
GO


-- =================================================================================
-- PARTE 1: DATABASE SCOPED CONFIGURATIONS (MAXDOP E PARAMETER SNIFFING)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - MAXDOP = 0: Permite utilizar todas as CPUs disponíveis (padrão).
--   - MAXDOP = 1: Desativa o paralelismo no banco de dados.
--   - PARAMETER SNIFFING: Compila o plano com base nos parâmetros da primeira execução. Se os dados forem assimétricos,
--     isso pode gerar planos subótimos. Pode ser desativado via escopo ou mitigado com a dica `OPTION (OPTIMIZE FOR UNKNOWN)`.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Definir o MAXDOP no escopo do banco de dados (ex: limite de 4 vCores para evitar exaustão de CPU)
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 4;

-- 2. Consultar as configurações de escopo vigentes
SELECT 
    configuration_id,
    name AS NomeConfiguracao,
    value AS ValorInstancia,
    value_for_secondary AS ValorSecundario
FROM sys.database_scoped_configurations
WHERE name IN ('MAXDOP', 'PARAMETER_SNIFFING', 'LEGACY_CARDINALITY_ESTIMATION');
GO


-- =================================================================================
-- PARTE 2: CONFIGURAÇÃO DO QUERY STORE E FORÇAMENTO DE PLANO DE EXECUÇÃO
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - QUERY STORE: Repositório nativo que captura histórico de consultas, planos e estatísticas de execução.
--   - QUERY_CAPTURE_MODE = AUTO: Captura apenas consultas relevantes, evitando sobrecarga de armazenamento.
--   - sp_query_store_force_plan: Força o otimizador a utilizar um plano de execução específico para prevenir regressões.

-- 1. Ativar e configurar o Query Store
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

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Consultar as 5 consultas mais custosas por CPU no Query Store
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

-- Exemplo conceitual de forçamento de plano
-- EXEC sp_query_store_force_plan @query_id = 10, @plan_id = 15;
GO


-- =================================================================================
-- PARTE 3: AUTOMATIC TUNING E RECOMENDAÇÕES DO SISTEMA
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - AUTOMATIC TUNING: Recurso do Azure SQL / SQL Server que detecta regressão e força automaticamente o último bom plano.
--   - sys.dm_db_tuning_recommendations: Visão que exibe sugestões de criação de índices, exclusão e forçamento de plano.

-- Ativar forçamento automático do último bom plano
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
GO

-- Consultar recomendações ativas de tuning automático
SELECT 
    name AS NomeRecomendacao,
    type AS TipoAcao,
    state AS EstadoRecomendacao,
    reason AS MotivoOtimizacao
FROM sys.dm_db_tuning_recommendations;
GO


-- =================================================================================
-- PARTE 4: DIAGNÓSTICO DE CONCESSÕES DE MEMÓRIA (MEMORY GRANTS)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - MEMORY GRANTS: Memória reservada antes de rodar operações de SORT ou HASH JOIN.
--   - Se a concessão for insuficiente, ocorre "spill" para o TempDB. Se for excessiva, ocorre pressão de memória na instância.

-- Consultar consultas atualmente aguardando ou consumindo concessões de memória
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
-- PARTE 5: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz de Validação do Nível de Compatibilidade e Recursos do Otimizador
-- Prepara o ambiente para alteração segura de Compatibility Level (ex: migração para nível 160).

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
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/06-performance-optimization/01-database-configurations.md
-- =================================================================================================
