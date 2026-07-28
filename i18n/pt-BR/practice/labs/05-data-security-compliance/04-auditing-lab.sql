-- =================================================================================
-- DP-800 - LAB PRÁTICO: AUDITORIA DE BANCO DE DADOS (SQL AUDIT E SPECIFICATIONS)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/05-data-security-compliance/04-auditing.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a configuração de auditoria nativa no SQL Server:
--   1. Criação de Server Audit com especificações de arquivo e tratamento de falha (ON_FAILURE)
--   2. Criação de Database Audit Specification com grupos de ação (BATCH_COMPLETED_GROUP)
--   3. Leitura e análise dos logs de auditoria via `sys.fn_get_audit_file`
--   4. Uso de Auditorias Customizadas do Usuário via `sp_audit_write`
--   5. Cenários Práticos de Projeto (Rastreamento de Consultas em Tabelas de Salários e Auditoria de Compliance)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.database_audit_specifications WHERE name = 'LabDatabaseAuditSpec')
    ALTER DATABASE AUDIT SPECIFICATION LabDatabaseAuditSpec WITH (STATE = OFF);

IF EXISTS (SELECT * FROM sys.database_audit_specifications WHERE name = 'LabDatabaseAuditSpec')
    DROP DATABASE AUDIT SPECIFICATION LabDatabaseAuditSpec;

IF EXISTS (SELECT * FROM sys.server_audits WHERE name = 'LabServerAudit')
    ALTER SERVER AUDIT LabServerAudit WITH (STATE = OFF);

IF EXISTS (SELECT * FROM sys.server_audits WHERE name = 'LabServerAudit')
    DROP SERVER AUDIT LabServerAudit;

DROP TABLE IF EXISTS lab.AuditTestTable;
GO

-- Estrutura de Tabela para Teste
CREATE TABLE lab.AuditTestTable (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    DataValue NVARCHAR(100) NOT NULL
);
GO


-- =================================================================================
-- PARTE 1: CRIAÇÃO DO SERVER AUDIT E DATABASE AUDIT SPECIFICATION
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - SERVER AUDIT: Define ONDE os registros de auditoria serão salvos (Arquivo, Log de Eventos do Windows, etc).
--   - ON_FAILURE: `CONTINUE` (permite continuar se falhar o log - prioriza disponibilidade) ou `SHUTDOWN` (para o SQL Server - prioriza segurança).
--   - BATCH_COMPLETED_GROUP: O grupo de ação crítico para capturar o texto completo das instruções SQL (inclusive SELECTs).

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Criar Server Audit gravando em diretório (ou usando Application Log)
CREATE SERVER AUDIT LabServerAudit
TO APPLICATION_LOG -- Usando Application Log para portabilidade nos testes de lab
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
GO

-- Ativar o Server Audit
ALTER SERVER AUDIT LabServerAudit WITH (STATE = ON);
GO

-- 2. Criar Database Audit Specification para capturar SELECT e DML na tabela de teste
CREATE DATABASE AUDIT SPECIFICATION LabDatabaseAuditSpec
FOR SERVER AUDIT LabServerAudit
ADD (SELECT, INSERT, UPDATE, DELETE ON lab.AuditTestTable BY PUBLIC),
ADD (USER_DEFINED_AUDIT_GROUP) -- Permite registrar eventos customizados via sp_audit_write
WITH (STATE = ON);
GO


-- =================================================================================
-- PARTE 2: SIMULAÇÃO DE EVENTOS DE AUDITORIA E REGISTRO CUSTOMIZADO
-- =================================================================================

-- 1. Executar operações monitoradas
INSERT INTO lab.AuditTestTable (DataValue) VALUES ('Teste Audit 1'), ('Teste Audit 2');
SELECT * FROM lab.AuditTestTable;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Registrar evento customizado do desenvolvedor via sp_audit_write
EXEC sp_audit_write 
    @user_defined_id = 50001,
    @succeeded = 1,
    @user_defined_message = N'Ação critica de exportacao executada pela aplicacao.';
GO


-- =================================================================================
-- PARTE 3: LEITURA E CONSULTA DE LOGS DE AUDITORIA VIA SYS.FN_GET_AUDIT_FILE
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - sys.fn_get_audit_file: Função de tabela utilizada para ler arquivos de log `.sqlaudit`.
--   - Em ambientes Azure SQL gravando em Storage Account ou Log Analytics, as consultas utilizam KQL (Kusto Query Language).

-- Exemplo conceitual de leitura de logs em disco
SELECT 
    event_time,
    action_id,
    succeeded,
    session_server_principal_name AS LoginUsuario,
    database_name AS BancoDados,
    object_name AS ObjetoAcessado,
    statement AS TextoConsultaSQL
FROM sys.fn_get_audit_file('C:\AuditLogs\*.sqlaudit', DEFAULT, DEFAULT)
ORDER BY event_time DESC;
GO


-- =================================================================================
-- PARTE 4: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Inspeção das Especificações de Auditoria Ativas no Servidor
-- Utilizado por consultores e auditores de segurança para validar a cobertura de conformidade (GDPR/LGPD).

SELECT 
    sa.name AS ServerAuditName,
    sa.status_desc AS StatusAuditoria,
    sa.audit_destination_desc AS DestinoLogs,
    das.name AS DatabaseSpecName,
    das.is_state_enabled AS EspecificacaoAtiva
FROM sys.server_audits sa
LEFT JOIN sys.database_audit_specifications das ON sa.server_audit_guid = das.server_audit_guid;
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/05-data-security-compliance/04-auditing.md
-- =================================================================================================
