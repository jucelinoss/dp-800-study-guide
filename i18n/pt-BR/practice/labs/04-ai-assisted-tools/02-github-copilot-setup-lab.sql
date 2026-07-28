-- =================================================================================
-- DP-800 - LAB PRÁTICO: GITHUB COPILOT, COPILOT IN FABRIC E REGRAS DE PROJETO
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/04-ai-assisted-tools/02-github-copilot-setup.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra validações e boas práticas ao incorporar o GitHub Copilot no projeto:
--   1. Correção de Padrões Inseguros Gerados por IA: Substituição de Concatenação por `sp_executesql`
--   2. Conformidade com Instruções Repositórias (`.github/copilot-instructions.md`)
--   3. Validação Pre-Production de Scripts T-SQL Sugeridos
--   4. Estruturação Padrão de Stored Procedures (SET NOCOUNT ON, THROW, TRY/CATCH)
--   5. Cenários Práticos de Projeto (Checklist de Code Review para Sugestões da IA)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SearchProductsSecure' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_SearchProductsSecure;

DROP TABLE IF EXISTS lab.ProductsCatalog;
GO

-- Estrutura de Tabela para Teste
CREATE TABLE lab.ProductsCatalog (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Category NVARCHAR(50) NOT NULL,
    Price DECIMAL(18,2) NOT NULL
);
GO

INSERT INTO lab.ProductsCatalog (ProductName, Category, Price) VALUES 
('Notebook Pro', 'Eletrônicos', 4500.00),
('Mouse Sem Fio', 'Acessórios', 150.00),
('Teclado Mecânico', 'Acessórios', 350.00);
GO


-- =================================================================================
-- PARTE 1: VALIDAÇÃO DE SQL DINÂMICO SUGERIDO PELA IA (INSEGURO VS SEGURO)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - RISCO DE SQL INJECTION EM IA: Modelos de linguagem podem sugerir concatenações diretas de string ao gerar SQL dinâmico.
--   - PADRÃO SEGURO: Utilizar `sp_executesql` repassando parâmetros tipados.

DECLARE @CategoryInput NVARCHAR(100) = N'Acessórios';

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Padrão Inseguro (Frequentemente sugerido pela IA): Concatenação de Strings
-- DECLARE @sqlInseguro NVARCHAR(MAX) = N'SELECT * FROM lab.ProductsCatalog WHERE Category = ''' + @CategoryInput + N'''';
-- EXEC(@sqlInseguro); -- VULNERÁVEL A SQL INJECTION!

-- 2. Padrão Seguro (Obrigatório em produção): sp_executesql parametrizado
DECLARE @sqlSeguro NVARCHAR(MAX) = N'SELECT ProductID, ProductName, Price FROM lab.ProductsCatalog WHERE Category = @CategoryParam';
EXEC sp_executesql 
    @stmt = @sqlSeguro,
    @params = N'@CategoryParam NVARCHAR(50)',
    @CategoryParam = @CategoryInput;
GO


-- =================================================================================
-- PARTE 2: CONFORMIDADE COM REGRAS DO ARCHIVO .GITHUB/COPILOT-INSTRUCTIONS.MD
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - COPILOT INSTRUCTIONS: Arquivo localizado na raiz em `.github/copilot-instructions.md`.
--     Define regras como: obrigatoriedade de `SET NOCOUNT ON`, uso de `THROW` em vez de `RAISERROR`,
--     prefixos de esquema de 2 partes (`lab.TableName`) e gerenciamento estrito de transações em CATCH.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Stored Procedure estruturada em 100% de conformidade com o guia institucional
CREATE PROCEDURE lab.usp_SearchProductsSecure
    @CategoryName NVARCHAR(50)
AS
BEGIN
    -- Regra 1: SET NOCOUNT ON obrigatório
    SET NOCOUNT ON;

    -- Regra 2: Estrutura de erro robusta com TRY/CATCH e THROW
    BEGIN TRY
        IF @CategoryName IS NULL OR LEN(TRIM(@CategoryName)) = 0
            -- Regra 3: Uso de THROW em vez de RAISERROR
            THROW 50001, 'O nome da categoria não pode ser nulo ou vazio.', 1;

        -- Regra 4: Nomes de tabela com 2 partes (lab.ProductsCatalog)
        SELECT 
            ProductID,
            ProductName,
            Category,
            Price
        FROM lab.ProductsCatalog
        WHERE Category = @CategoryName;
    END TRY
    BEGIN CATCH
        -- Tratamento e re-envio do erro mantendo detalhes originais
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Testar execução válida
EXEC lab.usp_SearchProductsSecure @CategoryName = N'Eletrônicos';
GO

-- Testar execução com erro tratado via THROW
BEGIN TRY
    EXEC lab.usp_SearchProductsSecure @CategoryName = N'';
END TRY
BEGIN CATCH
    PRINT 'ERRO DE CAPTURA DO COPILOT INSTRUCTIONS: ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Checklist de Validação Pre-Production para Sugestões de IA
-- Executa testes de estresse e auditoria de tipos antes de aprovar o PR do código sugerido.

SELECT 
    p.name AS ProcedureName,
    m.definition AS StatementText,
    CASE 
        WHEN m.definition LIKE '%EXEC(%' OR m.definition LIKE '%EXECUTE(%' THEN 'VULNERÁVEL (Dynamic SQL Bruto)'
        WHEN m.definition LIKE '%RAISERROR%' THEN 'DEPRECADO (Usar THROW)'
        WHEN m.definition NOT LIKE '%SET NOCOUNT ON%' THEN 'AVISO (Falta SET NOCOUNT ON)'
        ELSE 'CONFORME'
    END AS StatusConformidadeCopilot
FROM sys.procedures p
JOIN sys.sql_modules m ON p.object_id = m.object_id
WHERE p.schema_id = SCHEMA_ID('lab');
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/04-ai-assisted-tools/02-github-copilot-setup.md
-- =================================================================================================
