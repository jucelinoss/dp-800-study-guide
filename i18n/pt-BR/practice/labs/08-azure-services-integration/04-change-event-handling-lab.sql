-- =================================================================================
-- DP-800 - LAB PRÁTICO: REPLICAÇÃO E CAPTURA DE EVENTOS (CDC VS CHANGE TRACKING)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra as duas estratégias de captura de alteração de dados no SQL Server:
--   1. Change Data Capture (CDC): Habilitação, Tabelas de Captura e consulta de imagens Antes/Depois
--   2. Incremental Watermarking com Log Sequence Numbers (LSN)
--   3. Change Tracking (CT): Habilitação leve e consultas com `CHANGETABLE(CHANGES ...)`
--   4. Comparativo de Arquitetura CDC vs CT vs Event Grid / Fabric Change Event Streaming
--   5. Cenários Práticos de Projeto (Fila de Integração para Azure Functions e Logic Apps)
-- ATENÇÃO: CDC e Change Tracking alteram o banco. Execute em uma base descartável
-- com permissões adequadas e leia a seção de limpeza ao final.
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/08-azure-services-integration/04-change-event-handling.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.InventoryCT;
DROP TABLE IF EXISTS lab.CDCWatermark;
GO

-- Tabela para Teste de Change Tracking (CT)
CREATE TABLE lab.InventoryCT (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    ItemName NVARCHAR(100) NOT NULL,
    Price DECIMAL(18,2) NOT NULL
);
GO

INSERT INTO lab.InventoryCT (ItemName, Price) VALUES 
(N'Teclado Mecanico', 250.00),
(N'Mouse Sem Fio', 120.00);
GO


-- =================================================================================
-- PARTE 1: CHANGE DATA CAPTURE (CDC) - IMAGENS DE ANTES E DEPOIS COM LSN
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CDC: Captura as alterações em nível de linha incluindo o valor antigo (Antes) e novo (Depois).
--   - OPERAÇÕES (__$operation): 1 = DELETE, 2 = INSERT, 3 = UPDATE (Antes), 4 = UPDATE (Depois).
--   - LSN: Log Sequence Number usado para controle incremental de leitura (Watermarking).

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Habilitar CDC no nível de banco de dados
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_cdc_enabled = 0)
    EXEC sys.sp_cdc_enable_db;
GO

-- 2. Habilitar CDC em uma tabela específica
IF NOT EXISTS
(
    SELECT 1 FROM sys.tables
    WHERE object_id = OBJECT_ID(N'lab.InventoryCT')
      AND is_tracked_by_cdc = 1
)
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'lab',
        @source_name = N'InventoryCT',
        @role_name = NULL,
        @supports_net_changes = 1;
GO

-- 3. Estruturação de Tabela de Controle de Leitura Incremental (Watermarking)
CREATE TABLE lab.CDCWatermark (
    TableName NVARCHAR(100) PRIMARY KEY,
    LastProcessedLSN BINARY(10) NOT NULL,
    LastUpdated DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
GO


-- =================================================================================
-- PARTE 2: CHANGE TRACKING (CT) - RASTREAMENTO LEVE SEM IMAGEM ANTERIOR
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CHANGE TRACKING: Rastreia apenas QUE uma linha mudou e qual foi a operação (I, U, D).
--     Não consome armazenamento extra gravando os valores antigos. Padrão usado pelo Trigger SQL das Azure Functions.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Habilitar Change Tracking no Banco de Dados (Retenção de 2 dias com Auto Cleanup)
ALTER DATABASE AdventureWorks2025 
SET CHANGE_TRACKING = ON 
(CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON);
GO

-- 2. Habilitar Change Tracking na Tabela
IF NOT EXISTS
(
    SELECT 1 FROM sys.change_tracking_tables
    WHERE object_id = OBJECT_ID(N'lab.InventoryCT')
)
    ALTER TABLE lab.InventoryCT
    ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
GO

-- 3. Capturar a versão inicial de sincronização
DECLARE @SyncVersion BIGINT = CHANGE_TRACKING_CURRENT_VERSION();
PRINT 'Versao Atual de Sincronizacao: ' + CAST(@SyncVersion AS VARCHAR);

-- Fazer alterações na tabela para gerar alterações rastreadas
UPDATE lab.InventoryCT SET Price = 280.00 WHERE ItemID = 1;
INSERT INTO lab.InventoryCT (ItemName, Price) VALUES (N'Headset USB', 190.00);

-- O CDC é assíncrono: aguarde o capture job processar o log antes da consulta.
WAITFOR DELAY '00:00:05';

-- 5. Ler as alterações capturadas (a opção abaixo inclui imagem anterior e posterior)
DECLARE @CdcFromLSN BINARY(10) = sys.fn_cdc_get_min_lsn(N'lab_InventoryCT');
DECLARE @CdcToLSN BINARY(10) = sys.fn_cdc_get_max_lsn();

SELECT *
FROM cdc.fn_cdc_get_all_changes_lab_InventoryCT(@CdcFromLSN, @CdcToLSN, N'all update old');

-- 4. Consultar linhas alteradas a partir do ponto de sincronização
SELECT 
    ct.ItemID,
    ct.SYS_CHANGE_OPERATION AS TipoOperacao, -- I = Insert, U = Update, D = Delete
    ct.SYS_CHANGE_VERSION AS VersaoAlteracao,
    inv.ItemName,
    inv.Price
FROM CHANGETABLE(CHANGES lab.InventoryCT, @SyncVersion) AS ct
LEFT JOIN lab.InventoryCT inv ON inv.ItemID = ct.ItemID;
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz Comparativa CDC vs Change Tracking para o Exame DP-800
-- Guia de decisão de arquitetura para integração e ETL.

SELECT 
    'Change Data Capture (CDC)' AS Tecnologia,
    'SIM (Imagens de Antes e Depois)' AS GravaValorAntigo,
    'Médio (Tabelas de captura dedicadas)' AS SobrecargaArmazenamento,
    'ETL para Data Warehouse, Auditoria Completa e Synapse/Fabric' AS CasoDeUsoIdeal
UNION ALL
SELECT 
    'Change Tracking (CT)',
    'NÃO (Apenas ID da Linha e Tipo de Operação)',
    'Baixo / Mínimo',
    'Sincronização com Clientes Mobile, Azure Functions Trigger Binding';
GO

-- =================================================================================================
-- LIMPEZA OPCIONAL (execute somente em uma base descartável):
-- ALTER TABLE lab.InventoryCT DISABLE CHANGE_TRACKING;
-- ALTER DATABASE AdventureWorks2025 SET CHANGE_TRACKING = OFF;
-- EXEC sys.sp_cdc_disable_table @source_schema = N'lab', @source_name = N'InventoryCT', @capture_instance = N'lab_InventoryCT';
-- EXEC sys.sp_cdc_disable_db;
-- DROP TABLE IF EXISTS lab.CDCWatermark;
-- DROP TABLE IF EXISTS lab.InventoryCT;
-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/08-azure-services-integration/04-change-event-handling.md
-- =================================================================================================
