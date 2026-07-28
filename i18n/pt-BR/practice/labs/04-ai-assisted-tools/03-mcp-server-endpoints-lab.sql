-- =================================================================================
-- DP-800 - LAB PRÁTICO: ENDPOINTS DE SERVIDORES MCP (MODEL CONTEXT PROTOCOL)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/04-ai-assisted-tools/03-mcp-server-endpoints.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a configuração de segurança e inspeção para Servidores MCP (Model Context Protocol):
--   1. Criação de Conta de Menor Privilégio dedicada para Servidores MCP (`mcp_service_user`)
--   2. Concessão de Permissões de Descoberta de Esquema (`VIEW DEFINITION` e `SELECT`)
--   3. Bloqueio de Acesso a Tabelas Críticas/Financeiras via `DENY SELECT`
--   4. Simulação das Consultas de Leitura e Descoberta de Metadados executadas por ferramentas MCP
--   5. Cenários Práticos de Projeto (Script de Auditoria de Permissões de Endpoints MCP)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'mcp_service_user')
    DROP USER mcp_service_user;

DROP TABLE IF EXISTS lab.FinancialRecords;
DROP TABLE IF EXISTS lab.PublicCatalog;
GO

-- Estruturas de Tabelas para Teste
CREATE TABLE lab.PublicCatalog (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    ItemName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(255) NULL
);

CREATE TABLE lab.FinancialRecords (
    RecordID INT IDENTITY(1,1) PRIMARY KEY,
    AccountCode NVARCHAR(50) NOT NULL,
    Balance DECIMAL(18,2) NOT NULL
);
GO


-- =================================================================================
-- PARTE 1: CONFIGURAÇÃO DA CONTA DE SERVIÇO MCP (PRINCIPIO DO MENOR PRIVILÉGIO)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - RISCO DE CREDENCIAIS ELEVADAS NO MCP: O servidor MCP executa todas as consultas sob o contexto
--     da credencial informada na string de conexão (ex: `.vscode/mcp.json`).
--   - SE A CONTA FOR DB_OWNER: O assistente de IA pode acidentalmente executar instruções DDL ou DML nocivas.
--   - PADRÃO EXIGIDO: Conta dedicada sem login nativo (`WITHOUT LOGIN`) ou Managed Identity com acesso estritamente de leitura.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Criar usuário dedicado para conexão do Servidor MCP
CREATE USER mcp_service_user WITHOUT LOGIN;

-- 2. Conceder permissão de inspeção de definições de esquemas (Leitura de catálogo)
GRANT VIEW DEFINITION ON SCHEMA::lab TO mcp_service_user;
GRANT SELECT ON SCHEMA::lab TO mcp_service_user;

-- 3. Bloquear expressamente tabelas sensíveis de finanças/PII
DENY SELECT ON lab.FinancialRecords TO mcp_service_user;
GO


-- =================================================================================
-- PARTE 2: SIMULAÇÃO DE CONSULTAS DE DESCOBERTA EXECUTADAS PELO SERVIDOR MCP
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - Quando o Copilot se conecta via MCP, ele executa consultas no repositório de metadados do SQL Server
--     para construir a árvore de objetos e entender o contexto em tempo real.

EXECUTE AS USER = 'mcp_service_user';
GO

-- 1. Simulação: Servidor MCP descobrindo tabelas visíveis no esquema
SELECT 
    t.TABLE_SCHEMA,
    t.TABLE_NAME,
    t.TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_SCHEMA = 'lab';

-- 2. Simulação: Servidor MCP lendo metadados de colunas para enriquecer os prompts
SELECT 
    c.COLUMN_NAME,
    c.DATA_TYPE,
    c.CHARACTER_MAXIMUM_LENGTH,
    c.IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = 'lab' AND c.TABLE_NAME = 'PublicCatalog';

-- -- [PONTO DE ATENÇÃO DP-800]
-- 3. Teste de Acesso à Tabela Protegida (Deve falhar)
BEGIN TRY
    SELECT * FROM lab.FinancialRecords;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO MCP LEAST-PRIVILEGE: ' + ERROR_MESSAGE();
    -- Erro esperado: "The SELECT permission was denied on the object 'FinancialRecords'..."
END CATCH;
GO

REVERT; -- Voltar ao contexto original
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Auditoria de Segurança para Contas de Conexão MCP em Ambientes Dev/Staging
-- Garante que nenhuma conta configurada em ferramentas MCP possui privilégios de escrita ou alteração de schema.

SELECT 
    dp.name AS PrincipalName,
    dp.type_desc AS PrincipalType,
    pe.permission_name AS PermissaoConcedida,
    pe.state_desc AS EstadoPermissao,
    o.name AS ObjetoAfetado
FROM sys.database_permissions pe
JOIN sys.database_principals dp ON pe.grantee_principal_id = dp.principal_id
LEFT JOIN sys.objects o ON pe.major_id = o.object_id
WHERE dp.name = 'mcp_service_user';
GO

--- CENÁRIO 2: Inventário de governança MCP
SELECT N'Descoberta de schema' AS Proposito, N'VIEW DEFINITION' AS EscopoMinimo, N'Metadados somente leitura; auditar chamador e parâmetros' AS Governanca
UNION ALL SELECT N'Consulta de catálogo', N'SELECT em view aprovada', N'Excluir dados sensíveis; registrar resultado e correlation ID'
UNION ALL SELECT N'Ação DDL/DML', N'Não concedida por padrão', N'Exigir identidade separada, aprovação e controle de mudança em produção';
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/04-ai-assisted-tools/03-mcp-server-endpoints.md
-- =================================================================================================
