-- =================================================================================
-- DP-800 - LAB PRÁTICO: SEGURANÇA E IMPACTO DE FERRAMENTAS AUXILIADAS POR IA
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/04-ai-assisted-tools/01-ai-security-impact.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra práticas de segurança ao utilizar ferramentas assistidas por IA (Copilot):
--   1. Descoberta e Classificação de Dados Sensíveis (PII) via `sys.sensitivity_classifications`
--   2. Aplicação de Rótulos de Sensibilidade com `ADD SENSITIVITY CLASSIFICATION`
--   3. Validação Pre-Execution e Execução em Sandbox com Restrições (`EXECUTE AS USER`)
--   4. Rastreabilidade e Auditoria de Código Gerado por IA via Tags e Extended Events
--   5. Cenários Práticos de Projeto (Pipeline de Auditoria para Código Sugerido por IA)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'ai_sandbox_user')
    DROP USER ai_sandbox_user;

DROP TABLE IF EXISTS lab.CustomerPII;
GO

-- Estrutura de Tabela com Dados PII para Teste
CREATE TABLE lab.CustomerPII (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FullName NVARCHAR(100) NOT NULL,
    SSN VARCHAR(11) NOT NULL,
    CreditCard VARCHAR(16) NOT NULL,
    Email NVARCHAR(100) NOT NULL
);
GO


-- =================================================================================
-- PARTE 1: DESCOBERTA E CLASSIFICAÇÃO DE DADOS SENSÍVEIS (PII / PURVIEW)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CLASSIFICAÇÃO ANTES DA IA: Antes de habilitar ferramentas assistidas por IA no editor,
--     deve-se classificar colunas contendo PII/dados financeiros para evitar o envio inadvertido ao modelo.
--   - ADD SENSITIVITY CLASSIFICATION: Adiciona rótulos de sensibilidade nativos do SQL Server / Azure SQL.
--   - sys.sensitivity_classifications: Visão de catálogo que lista todas as colunas classificadas.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Aplicar classificação de sensibilidade nas colunas críticas de PII
ADD SENSITIVITY CLASSIFICATION TO lab.CustomerPII.SSN
WITH (LABEL = 'Confidential', LABEL_ID = '33221100-0000-0000-0000-000000000000', INFORMATION_TYPE = 'National ID', INFORMATION_TYPE_ID = '11223344-0000-0000-0000-000000000000', RANK = HIGH);

ADD SENSITIVITY CLASSIFICATION TO lab.CustomerPII.CreditCard
WITH (LABEL = 'Highly Confidential', LABEL_ID = '44332211-0000-0000-0000-000000000000', INFORMATION_TYPE = 'Credit Card', INFORMATION_TYPE_ID = '22334455-0000-0000-0000-000000000000', RANK = CRITICAL);
GO

-- 2. Consultar o catálogo de classificação de sensibilidade (Purview Integration)
SELECT
    schema_name(o.schema_id) AS SchemaName,
    o.name                   AS TableName,
    c.name                   AS ColumnName,
    sc.information_type_name AS TipoInformacao,
    sc.label_name            AS RotuloSensibilidade,
    sc.rank_desc             AS NivelRisco
FROM sys.sensitivity_classifications sc
JOIN sys.objects o ON sc.major_id = o.object_id
JOIN sys.columns c ON sc.major_id = c.object_id AND sc.minor_id = c.column_id
WHERE o.name = 'CustomerPII';
GO


-- =================================================================================
-- PARTE 2: EXECUÇÃO EM SANDBOX COM MENOR PRIVILÉGIO (EXECUTE AS USER)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - NUNCA EXECUTAR CÓDIGO DA IA COM PRIVILÉGIOS DE OWNER OU SYSADMIN SEM REVISÃO:
--     A IA pode sugerir instruções `SELECT *` em colunas PII ou acidentalmente modificar schemas.
--   - PADRÃO DE SANDBOX: Criação de um usuário sem login com permissões restritas e negação explícita (`DENY SELECT`) em tabelas sensíveis.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Criar Usuário Sandbox
CREATE USER ai_sandbox_user WITHOUT LOGIN;
GRANT SELECT ON SCHEMA::lab TO ai_sandbox_user;
DENY SELECT ON lab.CustomerPII TO ai_sandbox_user; -- Nega acesso a dados PII
GO

-- 2. Testar execução de código sugerido pela IA dentro do contexto Sandbox
EXECUTE AS USER = 'ai_sandbox_user';
GO

BEGIN TRY
    -- Tentativa de rodar uma consulta sugerida pela IA sobre a tabela PII
    SELECT CustomerID, FullName, SSN FROM lab.CustomerPII;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO NO SANDBOX: ' + ERROR_MESSAGE();
    -- Erro esperado: "The SELECT permission was denied on the object 'CustomerPII'..."
END CATCH;
GO

REVERT; -- Retorna ao contexto original
GO


-- =================================================================================
-- PARTE 3: RASTREABILIDADE E TAGGING DE CÓDIGO GERADO POR IA
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - TAGGING DE IA: Adição padronizada de comentários no cabeçalho de procedimentos (`-- AI-GENERATED: ...`).
--   - EXTENDED EVENTS: Sessão de rastreamento para auditar instruções T-SQL executadas contendo marcadores de IA.

-- 1. Exemplo de Procedure rastreável gerada via sugestão de IA
-- AI-GENERATED: 2026-07-21 | Tool: GitHub Copilot | Reviewer: dev@contoso.com
CREATE OR ALTER PROCEDURE lab.usp_GetSafeCustomerData
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CustomerID, FullName, Email 
    FROM lab.CustomerPII
    WHERE CustomerID = @CustomerID;
END;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Criar Sessão de Extended Events para auditoria de scripts gerados por IA
IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = 'AuditAIGeneratedSQL')
    DROP EVENT SESSION [AuditAIGeneratedSQL] ON SERVER;
GO

CREATE EVENT SESSION [AuditAIGeneratedSQL]
ON SERVER
ADD EVENT sqlserver.sql_batch_completed (
    WHERE sqlserver.sql_text LIKE N'%AI-GENERATED%'
)
ADD TARGET package0.ring_buffer (SET max_memory = 4096)
WITH (STARTUP_STATE = OFF);
GO


-- =================================================================================
-- PARTE 4: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Pipeline de Mapeamento de Risco PII antes da ativação do Copilot
-- Varre o esquema em busca de nomes de colunas suscetíveis à vazamentos antes de disponibilizar o workspace.

SELECT 
    t.TABLE_SCHEMA,
    t.TABLE_NAME,
    c.COLUMN_NAME,
    c.DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS c
JOIN INFORMATION_SCHEMA.TABLES t ON c.TABLE_SCHEMA = t.TABLE_SCHEMA AND c.TABLE_NAME = t.TABLE_NAME
WHERE t.TABLE_TYPE = 'BASE TABLE'
  AND (
        c.COLUMN_NAME LIKE '%ssn%'
     OR c.COLUMN_NAME LIKE '%credit%'
     OR c.COLUMN_NAME LIKE '%password%'
     OR c.COLUMN_NAME LIKE '%salary%'
  )
ORDER BY t.TABLE_SCHEMA, t.TABLE_NAME;
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/04-ai-assisted-tools/01-ai-security-impact.md
-- =================================================================================================
