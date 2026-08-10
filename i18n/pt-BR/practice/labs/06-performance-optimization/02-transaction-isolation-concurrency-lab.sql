-- =================================================================================
-- DP-800 - LAB PRÁTICO: NÍVEIS DE ISOLAMENTO E CONCORRÊNCIA (RCSI, SNAPSHOT, DEADLOCKS)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/06-performance-optimization/02-transaction-isolation-concurrency.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o gerenciamento de concorrência e isolamento no SQL Server:
--   1. Níveis de Isolamento: READ COMMITTED vs READ_COMMITTED_SNAPSHOT (RCSI) e SNAPSHOT
--   2. Concorrência Otimista com a Coluna `ROWVERSION` (Detecção de Conflitos sem Locks)
--   3. Configuração de Lock Escalation (`ALTER TABLE SET (LOCK_ESCALATION = AUTO)`)
--   4. Diagnóstico de Bloqueios e Deadlocks (Erro 1205) no Extended Events `system_health`
--   5. Cenários Práticos de Projeto (Eliminação de Reader/Writer Blocking em OLTP)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
-- ATENÇÃO: habilitar RCSI/SNAPSHOT altera o comportamento do banco inteiro.
-- Use uma base descartável e consulte as instruções de limpeza no README.md.
DROP TABLE IF EXISTS lab.InventoryStock;
GO

-- Estrutura de Tabela para Teste
CREATE TABLE lab.InventoryStock (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    ItemName NVARCHAR(100) NOT NULL,
    Quantity INT NOT NULL,
    RowVer ROWVERSION NOT NULL -- Usado para concorrência otimista
);
GO

INSERT INTO lab.InventoryStock (ItemName, Quantity) VALUES 
(N'Monitor 27 Polegadas', 50),
(N'Cadeira Ergonomica', 20);
GO


-- =================================================================================
-- PARTE 1: NÍVEIS DE ISOLAMENTO (RCSI VS SNAPSHOT)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - READ COMMITTED (Padrão Pessimista): Leitores bloqueiam escritores e escritores bloqueiam leitores.
--   - READ_COMMITTED_SNAPSHOT (RCSI): Habilitado no nível do banco de dados. Leitores usam o TempDB Version Store sem bloquear escritores.
--   - SNAPSHOT ISOLATION: Habilitado no banco (`ALLOW_SNAPSHOT_ISOLATION ON`) e ativado por transação (`SET TRANSACTION ISOLATION LEVEL SNAPSHOT`).

-- 1. Ativar RCSI no banco para reduzir bloqueios entre leitores e escritores em OLTP
-- Este ALTER DATABASE precisa de acesso exclusivo enquanto a opção é alterada.
ALTER DATABASE AdventureWorks2025 SET READ_COMMITTED_SNAPSHOT ON;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Ativar permissão para isolamento de Snapshot na aplicação
ALTER DATABASE AdventureWorks2025 SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

-- 3. Executar transação sob nível SNAPSHOT (Garante visão consistente do início da transação)
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;

SELECT ItemID, ItemName, Quantity FROM lab.InventoryStock WHERE ItemID = 1;

COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED; -- Restaurar nível padrão
GO


-- =================================================================================
-- PARTE 2: CONCORRÊNCIA OTIMISTA COM ROWVERSION (DESCONECTADA SEM LOCKS)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - ROWVERSION (timestamp): Incrementado automaticamente a cada UPDATE na linha.
--   - PATTERN: Lê a linha e guarda o `RowVer`. Na hora do UPDATE, valida `WHERE ItemID = @id AND RowVer = @originalVer`.
--   - SE @@ROWCOUNT = 0: Significa que outro usuário modificou a linha no meio do processo!

DECLARE @ItemID INT = 1;
DECLARE @CurrentQty INT;
DECLARE @OriginalRowVer BINARY(8);

-- 1. Leitura sem manter locks abertos
SELECT 
    @CurrentQty = Quantity,
    @OriginalRowVer = RowVer
FROM lab.InventoryStock
WHERE ItemID = @ItemID;

-- 2. Simular alteração e aplicar UPDATE otimista
-- -- [PONTO DE ATENÇÃO DP-800]
UPDATE lab.InventoryStock
SET Quantity = @CurrentQty - 1
WHERE ItemID = @ItemID AND RowVer = @OriginalRowVer;

IF @@ROWCOUNT = 0
BEGIN
    PRINT 'CONFLITO DE CONCORRÊNCIA DETECTADO: O registro foi alterado por outro usuário!';
END
ELSE
BEGIN
    PRINT 'Atualização realizada com sucesso!';
END
GO


-- =================================================================================
-- PARTE 3: LOCK ESCALATION E DIAGNÓSTICO DE BLOQUEIOS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - LOCK ESCALATION: Quando uma consulta acumula ~5.000 locks de linha/página, o SQL Server tenta converter para lock de tabela inteira.
--   - LOCK_ESCALATION = AUTO: Para tabelas particionadas, escala apenas até a partição, evitando travar a tabela inteira.

-- Configurar Lock Escalation para AUTO (Melhor opção para tabelas particionadas)
ALTER TABLE lab.InventoryStock SET (LOCK_ESCALATION = AUTO);
GO

-- Consultar o modo de Lock Escalation da tabela
SELECT name, lock_escalation_desc
FROM sys.tables
WHERE name = 'InventoryStock';
GO

-- Consultar bloqueios ativos na instância via DMVs
SELECT 
    r.blocking_session_id AS SessaoBloqueadora,
    r.session_id AS SessaoBloqueada,
    r.wait_type AS TipoEspera,
    r.wait_time / 1000.0 AS TempoEsperaSegundos,
    t.text AS QueryTexto
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id > 0;
GO


-- =================================================================================
-- PARTE 4: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Consulta de Extração de Deadlocks no Extended Events `system_health`
-- Utilizado para investigar grafos de deadlock (Erro 1205) capturados no buffer nativo.

WITH DeadlockCTE AS (
    SELECT CAST(target_data AS XML) AS TargetData
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address
    WHERE s.name = 'system_health'
      AND t.target_name = 'ring_buffer'
)
SELECT 
    XEvent.value('@timestamp', 'DATETIME2') AS DataHoraDeadlock,
    XEvent.query('.') AS GrafoDeadlockXML
FROM DeadlockCTE
CROSS APPLY TargetData.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS DeadlockTable(XEvent);
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/06-performance-optimization/02-transaction-isolation-concurrency.md
-- =================================================================================================
