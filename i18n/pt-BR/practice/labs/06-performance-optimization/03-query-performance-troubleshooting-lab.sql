-- =================================================================================
-- DP-800 - LAB PRÁTICO: DIAGNÓSTICO E RESOLUÇÃO DE PROBLEMAS DE PERFORMANCE EM CONSULTAS
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra técnicas de análise e otimização de consultas T-SQL:
--   1. Análise de Planos de Execução com `SET STATISTICS IO, TIME ON` e `SET STATISTICS XML ON`
--   2. Identificação de Operadores Custosos (Key Lookups e conversão para Covered Indexes)
--   3. Resolução de Parameter Sniffing (`OPTION (RECOMPILE)` vs `OPTION (OPTIMIZE FOR UNKNOWN)`)
--   4. Uso de Plan Guides (`sp_create_plan_guide`) para injetar dicas em códigos de ORM/Terceiros
--   5. Diagnóstico de Fragmentação e Manutenção de Índices (REORGANIZE vs REBUILD)
--   6. Cenários Práticos de Projeto (Manutenção Preventiva de Estatísticas com `sys.dm_db_stats_properties`)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.plan_guides WHERE name = N'PG_FixParameterSniffing')
    EXEC sp_control_plan_guide N'DROP', N'PG_FixParameterSniffing';

IF EXISTS (SELECT * FROM sys.indexes WHERE name = N'IX_PerfTest_Covered' AND object_id = OBJECT_ID('lab.PerfTestOrders'))
    DROP INDEX IX_PerfTest_Covered ON lab.PerfTestOrders;

DROP TABLE IF EXISTS lab.PerfTestOrders;
GO

-- Estrutura de Tabela para Teste de Otimização
CREATE TABLE lab.PerfTestOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL,
    OrderStatus NVARCHAR(20) NOT NULL
);
GO

-- Popular massa de dados simulada
INSERT INTO lab.PerfTestOrders (CustomerID, OrderDate, TotalAmount, OrderStatus) VALUES 
(1001, '2025-01-01', 500.00, 'Completed'),
(1001, '2025-01-02', 1200.00, 'Completed'),
(1002, '2025-01-03', 300.00, 'Pending'),
(1003, '2025-01-04', 1500.00, 'Completed');
GO

CREATE INDEX IX_PerfTestOrders_Customer ON lab.PerfTestOrders(CustomerID);
GO


-- =================================================================================
-- PARTE 1: KEY LOOKUP E CRIAÇÃO DE COVERED INDEX (ÍNDICE COBERTO)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - KEY LOOKUP: Ocorre quando o índice não-agrupado contêm as colunas do filtro (`WHERE`), mas NÃO contêm
--     as colunas da lista de seleção (`SELECT`). O SQL Server precisa buscar o restante das colunas na tabela principal.
--   - SOLUÇÃO: Criar um Covered Index (Índice Coberto) adicionando as colunas retornadas na cláusula `INCLUDE`.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Ativar estatísticas de I/O e tempo para diagnóstico
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- Consulta que dispara Key Lookup (Filtra por CustomerID mas busca TotalAmount e OrderStatus)
SELECT CustomerID, TotalAmount, OrderStatus 
FROM lab.PerfTestOrders 
WHERE CustomerID = 1001;
GO

-- 2. Eliminar o Key Lookup criando um Covered Index com INCLUDE
CREATE NONCLUSTERED INDEX IX_PerfTest_Covered 
ON lab.PerfTestOrders(CustomerID)
INCLUDE (TotalAmount, OrderStatus);
GO

-- Re-executar a consulta (Agora executa como Index Seek direto e puro no índice coberto)
SELECT CustomerID, TotalAmount, OrderStatus 
FROM lab.PerfTestOrders 
WHERE CustomerID = 1001;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO


-- =================================================================================
-- PARTE 2: MITIGAÇÃO DE PARAMETER SNIFFING (RECOMPILE VS OPTIMIZE FOR UNKNOWN)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - OPTION (RECOMPILE): Força a recompilação a cada execução. Ideal para relatórios de lote infrequentes.
--   - OPTION (OPTIMIZE FOR UNKNOWN): Compila com estatísticas médias genéricas sem recompilar todas as vezes.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Exemplo de procedimento protegido contra Parameter Sniffing
CREATE OR ALTER PROCEDURE lab.usp_GetOrdersByCustomer
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Opção ideal para OLTP de alta frequência: compilação com estatísticas médias
    SELECT OrderID, CustomerID, TotalAmount
    FROM lab.PerfTestOrders
    WHERE CustomerID = @CustomerID
    OPTION (OPTIMIZE FOR (@CustomerID UNKNOWN));
END;
GO


-- =================================================================================
-- PARTE 3: PLAN GUIDES PARA CÓDIGO INALTERÁVEL DE TERCEIROS / ORM
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PLAN GUIDE: Associa uma dica de otimização (`hints`) a uma instrução SQL cujo código fonte NÃO pode ser modificado.
--   - REQUISITO: O texto da instrução T-SQL no Plan Guide deve coincidir EXACTAMENTE com o texto enviado pela aplicação.

-- 1. Criar um Plan Guide para injetar a dica OPTIMIZE FOR UNKNOWN em uma instrução ORM
EXEC sp_create_plan_guide
    @name = N'PG_FixParameterSniffing',
    @stmt = N'SELECT OrderID, CustomerID, TotalAmount FROM lab.PerfTestOrders WHERE CustomerID = @CustIDParam',
    @type = N'SQL',
    @module_or_batch = NULL,
    @params = N'@CustIDParam INT',
    @hints = N'OPTION (OPTIMIZE FOR (@CustIDParam UNKNOWN))';
GO

-- 2. Consultar o catálogo de Plan Guides ativos
SELECT name, scope_type_desc, is_disabled
FROM sys.plan_guides
WHERE name = N'PG_FixParameterSniffing';
GO


-- =================================================================================
-- PARTE 4: MANUTENÇÃO DE ESTATÍSTICAS E ANÁLISE DE FRAGMENTAÇÃO DE ÍNDICES
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - sys.dm_db_stats_properties: Exibe a quantidade de modificações (`modification_counter`) desde a última atualização.
--   - REORGANIZE: Recomendado para fragmentação entre 5% e 30% (operação online leve).
--   - REBUILD: Recomendado para fragmentação > 30% (reconstrói a estrutura física e atualiza estatísticas com FULLSCAN).

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Verificar a atualização das estatísticas e o número de modificações acumuladas
SELECT 
    OBJECT_NAME(s.object_id) AS NomeTabela,
    s.name AS NomeEstatistica,
    sp.last_updated AS UltimaAtualizacao,
    sp.rows AS TotalLinhas,
    sp.rows_sampled AS LinhasAmostradas,
    sp.modification_counter AS ContadorModificacoes
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID('lab.PerfTestOrders');
GO

-- 2. Atualizar estatísticas da tabela com amostragem total (FULLSCAN)
UPDATE STATISTICS lab.PerfTestOrders WITH FULLSCAN;
GO


-- =================================================================================
-- PARTE 5: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Consulta de Diagnóstico de Consultas Mais Custosas via DMVs
-- Identifica as 5 consultas com maior tempo de CPU acumulado na instância.

SELECT TOP 5
    qs.total_worker_time / qs.execution_count / 1000.0 AS TempoCpuMedioMS,
    qs.total_elapsed_time / qs.execution_count / 1000.0 AS DuracaoMediaMS,
    qs.execution_count AS TotalExecucoes,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
         ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS InstrucaoSQL
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY TempoCpuMedioMS DESC;
GO
