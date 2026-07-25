-- =================================================================================
-- DP-800 - LAB PRÁTICO: PERMISSÕES EM NÍVEL DE OBJETO E ACESSO SEGURO (RBAC / IMPERSONATION)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o gerenciamento de permissões, controle de acesso e contexto:
--   1. Hierarquia de Permissões: GRANT, DENY e a Regra de Precedência (DENY sempre vence)
--   2. Diferença entre REVOKE e DENY (REVOKE apenas remove a regra explicita)
--   3. Roles Customizadas (RBAC) e Usuários Contidos (Contained Database Users)
--   4. Impersonação de Contexto com `EXECUTE AS USER` e `REVERT`
--   5. Cadeia de Propriedade (Ownership Chaining) e solução para quebras com `WITH EXECUTE AS OWNER`
--   6. Cenários Práticos de Projeto (Auditoria de Permissões Efetivas via sys.fn_my_permissions)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_GetSalaryReport' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_GetSalaryReport;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'JuniorAnalyst')
    DROP USER JuniorAnalyst;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'FinancialRole')
    DROP ROLE FinancialRole;

DROP TABLE IF EXISTS lab.SalaryData;
GO

-- Criar Tabela de Teste
CREATE TABLE lab.SalaryData (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeName NVARCHAR(100) NOT NULL,
    Salary DECIMAL(18,2) NOT NULL
);
GO

INSERT INTO lab.SalaryData (EmployeeName, Salary) VALUES 
('Alice Smith', 12000.00),
('Bob Jones', 8500.00);
GO


-- =================================================================================
-- PARTE 1: REGRAS DE PRECEDÊNCIA (DENY VS GRANT E O PAPEL DO REVOKE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DENY VENCE GRANT: Se um usuário receber `GRANT` diretamente ou por role, mas receber um `DENY` explícito, o acesso é BLOQUEADO.
--   - REVOKE NÃO É DENY: `REVOKE` apenas remove a concessão prévia. Se o usuário herdar acesso por uma role, ele continuará acessando!

-- 1. Criar Role Financeira e Usuário
CREATE ROLE FinancialRole;
GRANT SELECT ON lab.SalaryData TO FinancialRole;

CREATE USER JuniorAnalyst WITHOUT LOGIN;
ALTER ROLE FinancialRole ADD MEMBER JuniorAnalyst;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Conceder DENY explícito no usuário (Sobrepõe a permissão herdada da Role)
DENY SELECT ON lab.SalaryData TO JuniorAnalyst;
GO

-- 3. Testar acesso (Falha esperada por causa do DENY)
EXECUTE AS USER = 'JuniorAnalyst';
GO

BEGIN TRY
    SELECT * FROM lab.SalaryData;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO DENY PRECEDENCE: ' + ERROR_MESSAGE();
    -- Erro: "The SELECT permission was denied on the object 'SalaryData'..."
END CATCH;
GO

REVERT;
GO

-- 4. Testar o REVOKE (Remove o DENY explícito do usuário, permitindo voltar a herdar o GRANT da Role)
REVOKE DENY SELECT ON lab.SalaryData FROM JuniorAnalyst;
GO

EXECUTE AS USER = 'JuniorAnalyst';
GO

-- Agora a consulta funciona pois o DENY foi removido via REVOKE
SELECT EmployeeID, EmployeeName FROM lab.SalaryData;
GO

REVERT;
GO


-- =================================================================================
-- PARTE 2: OWNERSHIP CHAINING (CADEIA DE PROPRIEDADE E EXECUTE AS OWNER)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - OWNERSHIP CHAINING (Cadeia Intacta): Quando a Procedure e a Tabela têm o mesmo dono (`dbo`), o SQL Server
--     NÃO verifica permissões de SELECT na tabela para quem executa a Procedure.
--   - CADEIA QUEBRADA: Se a tabela e a procedure tiverem donos/esquemas com proprietários diferentes, a cadeia quebra.
--   - SOLUÇÃO: Declarar a procedure com `WITH EXECUTE AS OWNER`.

-- Removemos a permissão direta de SELECT na tabela do usuário
REVOKE SELECT ON lab.SalaryData FROM FinancialRole;
REVOKE SELECT ON lab.SalaryData FROM JuniorAnalyst;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- Procedimento com EXECUTE AS OWNER para encapsular o acesso à tabela restrita
CREATE PROCEDURE lab.usp_GetSalaryReport
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT EmployeeID, EmployeeName, Salary FROM lab.SalaryData;
END;
GO

GRANT EXECUTE ON lab.usp_GetSalaryReport TO JuniorAnalyst;
GO

-- O usuário executa a Procedure com sucesso sem ter acesso direto de SELECT na tabela
EXECUTE AS USER = 'JuniorAnalyst';
GO

EXEC lab.usp_GetSalaryReport;
GO

REVERT;
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Consulta de Auditoria de Permissões Efetivas do Usuário Logado
-- Utiliza a função do sistema sys.fn_my_permissions para mapear todos os privilégios ativos.

EXECUTE AS USER = 'JuniorAnalyst';
GO

SELECT * FROM sys.fn_my_permissions('lab.SalaryData', 'OBJECT');
SELECT * FROM sys.fn_my_permissions('lab.usp_GetSalaryReport', 'OBJECT');
GO

REVERT;
GO
