-- =================================================================================
-- DP-800 - LAB PRÁTICO: DYNAMIC DATA MASKING (DDM) E ROW-LEVEL SECURITY (RLS)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o controle de acesso dinâmico no nível de colunas e linhas:
--   1. Dynamic Data Masking (DDM): Funções default(), email(), partial() e random()
--   2. Controle da Permissão UNMASK em Nível de Tabela e Coluna
--   3. Row-Level Security (RLS): Inline TVF com WITH SCHEMABINDING e SESSION_CONTEXT
--   4. RLS Block Predicates (AFTER INSERT, AFTER UPDATE) para evitar vazamento de gravação
--   5. Cenários Práticos de Projeto (Isolamento Multi-Tenant em SaaS de E-Commerce)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.security_policies WHERE name = 'TenantIsolationPolicy')
    DROP SECURITY POLICY TenantIsolationPolicy;

IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_TenantSecurityPredicate' AND schema_id = SCHEMA_ID('Security'))
    DROP FUNCTION Security.fn_TenantSecurityPredicate;

IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'Security')
    DROP SCHEMA Security;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'TenantAppUser')
    DROP USER TenantAppUser;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'SupportUser')
    DROP USER SupportUser;

DROP TABLE IF EXISTS lab.TenantOrders;
GO

-- Criar Schema de Segurança para Predicados do RLS
CREATE SCHEMA Security;
GO

-- Estrutura de Tabela com DDM e RLS para Teste
CREATE TABLE lab.TenantOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    TenantID INT NOT NULL,
    CustomerName NVARCHAR(100) NOT NULL,
    CustomerEmail NVARCHAR(100) MASKED WITH (FUNCTION = 'email()') NOT NULL,
    CreditCard NVARCHAR(20) MASKED WITH (FUNCTION = 'partial(0, "XXXX-XXXX-XXXX-", 4)') NOT NULL,
    OrderAmount DECIMAL(18,2) MASKED WITH (FUNCTION = 'default()') NOT NULL
);
GO

-- Inserir dados de teste de múltiplos Tenants
INSERT INTO lab.TenantOrders (TenantID, CustomerName, CustomerEmail, CreditCard, OrderAmount) VALUES 
(100, 'Alice Silva', 'alice@empresaA.com', '4532111122223333', 1500.00),
(100, 'Bob Santos', 'bob@empresaA.com', '5412888899990000', 850.50),
(200, 'Charlie Lima', 'charlie@empresaB.com', '3782444455556666', 3200.00);
GO


-- =================================================================================
-- PARTE 1: DYNAMIC DATA MASKING (DDM) E PERMISSÃO UNMASK
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DDM (Dynamic Data Masking): Oculta dados de colunas sensíveis em tempo de consulta para usuários não autorizados.
--   - DDM NÃO É CRIPTOGRAFIA: Os dados no disco continuam em texto claro. DBAs e usuários com `UNMASK` veem o valor real.
--   - UNMASK PERMISSION: Pode ser concedida em nível de tabela ou coluna individual (SQL 2022+).

-- 1. Criar usuário de suporte sem a permissão UNMASK
CREATE USER SupportUser WITHOUT LOGIN;
GRANT SELECT ON lab.TenantOrders TO SupportUser;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Consultar como Usuário de Suporte (Valores mascarados retornados)
EXECUTE AS USER = 'SupportUser';
GO

SELECT OrderID, TenantID, CustomerName, CustomerEmail, CreditCard, OrderAmount
FROM lab.TenantOrders;
GO

REVERT;
GO

-- 3. Conceder permissão UNMASK no nível de coluna para o Email apenas
GRANT UNMASK ON lab.TenantOrders(CustomerEmail) TO SupportUser;
GO

-- Verificar se o Email é exibido real enquanto o Cartão e Valor continuam mascarados
EXECUTE AS USER = 'SupportUser';
GO

SELECT OrderID, CustomerEmail, CreditCard FROM lab.TenantOrders;
GO

REVERT;
GO


-- =================================================================================
-- PARTE 2: ROW-LEVEL SECURITY (RLS - FILTER E BLOCK PREDICATES)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - RLS (Row-Level Security): Oculta linhas inteiras com base no resultado de uma Inline TVF com `WITH SCHEMABINDING`.
--   - FILTER PREDICATE: Filtra silenciosamente as linhas retornadas em SELECT, UPDATE e DELETE.
--   - BLOCK PREDICATE: Bloqueia operações de inserção/atualização que violariam o isolamento (ex: `AFTER INSERT`).
--   - SESSION_CONTEXT: Contexto de sessão de leitura única configurado pela aplicação via `sp_set_session_context`.

-- 1. Criar Usuário da Aplicação
CREATE USER TenantAppUser WITHOUT LOGIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON lab.TenantOrders TO TenantAppUser;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Criar Função de Predicado de Segurança com SCHEMABINDING
CREATE FUNCTION Security.fn_TenantSecurityPredicate (@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
    SELECT 1 AS fn_result
    WHERE @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT)
       OR USER_NAME() = 'dbo'
);
GO

-- 3. Criar Política de Segurança RLS com FILTER e BLOCK Predicates
CREATE SECURITY POLICY TenantIsolationPolicy
ADD FILTER PREDICATE Security.fn_TenantSecurityPredicate(TenantID) ON lab.TenantOrders,
ADD BLOCK PREDICATE Security.fn_TenantSecurityPredicate(TenantID) ON lab.TenantOrders AFTER INSERT
WITH (STATE = ON);
GO


-- =================================================================================
-- PARTE 3: TESTANDO O ISOLAMENTO MULTI-TENANT VIA SESSION_CONTEXT
-- =================================================================================

-- 1. Simular a Aplicação conectando como Tenant 100
EXECUTE AS USER = 'TenantAppUser';
GO

-- Configurar o contexto de sessão como Tenant 100
EXEC sp_set_session_context @key = N'TenantID', @value = 100, @read_only = 1;

-- O usuário verá APENAS os registros do Tenant 100 (Silencioso; sem mensagens de erro)
SELECT OrderID, TenantID, CustomerName FROM lab.TenantOrders;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Testar o BLOCK PREDICATE (Inserção inválida para o Tenant 200 estando no contexto do Tenant 100)
BEGIN TRY
    INSERT INTO lab.TenantOrders (TenantID, CustomerName, CustomerEmail, CreditCard, OrderAmount)
    VALUES (200, 'Tentativa Invasao', 'hack@test.com', '0000111122223333', 10.00);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO RLS BLOCK PREDICATE: ' + ERROR_MESSAGE();
    -- Erro: "The attempted operation failed because the target object 'TenantOrders' has a security policy..."
END CATCH;
GO

REVERT;
GO


-- =================================================================================
-- PARTE 4: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Consulta de Auditoria de Políticas RLS e Colunas Mascaradas no Banco
-- Permite que auditores de segurança validem todas as políticas ativas no servidor.

SELECT 
    sp.name AS NomePolitica,
    sp.is_enabled AS PoliticaAtiva,
    spr.predicate_type_desc AS TipoPredicado,
    o.name AS TabelaProtegida,
    spr.predicate_definition AS ExpressaoPredicado
FROM sys.security_policies sp
JOIN sys.security_predicates spr ON sp.object_id = spr.object_id
JOIN sys.objects o ON spr.target_object_id = o.object_id;

SELECT 
    o.name AS Tabela,
    c.name AS Coluna,
    mc.masking_function AS FuncaoMascaramento
FROM sys.masked_columns mc
JOIN sys.objects o ON mc.object_id = o.object_id
JOIN sys.columns c ON mc.object_id = c.object_id AND mc.column_id = c.column_id;
GO
