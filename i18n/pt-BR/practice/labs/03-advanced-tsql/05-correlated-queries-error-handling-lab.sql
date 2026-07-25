-- =================================================================================
-- DP-800 - LAB PRÁTICO: SUBQUERIES CORRELACIONADAS E TRATAMENTO AVANÇADO DE ERROS
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o uso de subqueries correlacionadas e padrões de resiliência de erro:
--   1. Subqueries Correlacionadas e a Armadilha do NOT IN com NULLs (vs NOT EXISTS)
--   2. Conversão Segura de Dados com TRY_CONVERT e TRY_PARSE (Validação sem CATCH)
--   3. Impacto de SET XACT_ABORT ON e Diagnóstico de Transações Condenadas (XACT_STATE = -1)
--   4. Transações Aninhadas, @@TRANCOUNT e Pontos de Salvamento (SAVE TRANSACTION)
--   5. Cenários Práticos de Projeto (Procedure Financeira em Lote com Savepoints e Rollback Parcial)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ProcessBatchWithSavepoints' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_ProcessBatchWithSavepoints;

DROP TABLE IF EXISTS lab.StagingData;
DROP TABLE IF EXISTS lab.LedgerEntries;
DROP TABLE IF EXISTS lab.Accounts;
GO

-- Estrutura de Tabelas para Teste
CREATE TABLE lab.Accounts (
    AccountID INT PRIMARY KEY,
    AccountHolder NVARCHAR(100) NOT NULL,
    Status NVARCHAR(20) NOT NULL DEFAULT 'Active'
);

CREATE TABLE lab.LedgerEntries (
    EntryID INT IDENTITY(1,1) PRIMARY KEY,
    AccountID INT NULL, -- Permite Nulo para testar a armadilha do NOT IN
    Amount DECIMAL(18,2) NOT NULL
);

CREATE TABLE lab.StagingData (
    RawID INT IDENTITY(1,1) PRIMARY KEY,
    RawValue NVARCHAR(50) NOT NULL
);
GO


-- =================================================================================
-- PARTE 1: SUBQUERIES CORRELACIONADAS E A ARMADILHA DO NOT IN COM NULLS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - SUBQUERY CORRELACIONADA: Subconsulta que referencia uma coluna da consulta externa (executa por linha externa).
--   - ARMADILHA DO NOT IN: Se o subconjunto retornado pelo `NOT IN` contiver QUALQUER valor NULL,
--     a comparação booleana resulta em `UNKNOWN` para todas as linhas, fazendo o SQL Server retornar ZERO linhas!
--   - RECOMENDAÇÃO: Sempre utilize `NOT EXISTS` em vez de `NOT IN`, pois o `NOT EXISTS` lida corretamente com NULLs.

INSERT INTO lab.Accounts (AccountID, AccountHolder, Status) VALUES (1, 'Alice', 'Active'), (2, 'Bob', 'Inactive'), (3, 'Charlie', 'Active');
INSERT INTO lab.LedgerEntries (AccountID, Amount) VALUES (1, 100.00), (NULL, 50.00); -- Inclui um registro NULL
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Teste do NOT IN com NULL no conjunto de retorno -> RETORNA ZERO LINHAS! (Comportamento incorreto esperado)
SELECT AccountID, AccountHolder
FROM lab.Accounts
WHERE AccountID NOT IN (SELECT AccountID FROM lab.LedgerEntries);
-- ^ Retorna 0 linhas por causa do NULL gravado em LedgerEntries!

-- 2. Teste com NOT EXISTS -> RETORNA AS CONTAS CORRETAS (Resiliente a NULLs)
SELECT a.AccountID, a.AccountHolder
FROM lab.Accounts a
WHERE NOT EXISTS (
    SELECT 1 FROM lab.LedgerEntries l 
    WHERE l.AccountID = a.AccountID
);
GO


-- =================================================================================
-- PARTE 2: CONVERSÃO SEGURA DE DADOS (TRY_CONVERT E TRY_PARSE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - TRY_CONVERT / TRY_CAST: Tenta converter o tipo de dado. Se falhar, retorna `NULL` sem interromper a execução nem disparar exceções.
--   - Evita a necessidade de envolver cada linha de importação de dados brutos em blocos TRY/CATCH.

INSERT INTO lab.StagingData (RawValue) VALUES ('100'), ('200'), ('TEXTO_INVALIDO'), ('2025-01-01');
GO

-- Filtrar apenas linhas com inteiros válidos sem gerar erro de conversão
SELECT 
    RawID, 
    RawValue, 
    TRY_CONVERT(INT, RawValue) AS ValorInteiroConvertido
FROM lab.StagingData
WHERE TRY_CONVERT(INT, RawValue) IS NOT NULL;
GO


-- =================================================================================
-- PARTE 3: IMPACTO DE SET XACT_ABORT ON E XACT_STATE()
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - SET XACT_ABORT ON: Para muitos erros de execução, encerra e reverte a transação inteira.
--     Ainda assim, consulte XACT_STATE() no CATCH; o estado observado depende do erro e do contexto.
--   - XACT_STATE() = -1: Indica uma "Doomed Transaction" (Transação Condenada). O SQL Server proíbe o COMMIT
--     e exige que o desenvolvedor execute um `ROLLBACK`.

-- -- [PONTO DE ATENÇÃO DP-800]
BEGIN TRY
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    INSERT INTO lab.Accounts (AccountID, AccountHolder) VALUES (10, 'Conta Teste');
    
    -- Inserção que causará erro de Chave Primária Duplicada
    INSERT INTO lab.Accounts (AccountID, AccountHolder) VALUES (10, 'Conta Duplicada');

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    PRINT 'ENTROU NO CATCH. Estado da Transação (XACT_STATE): ' + CAST(XACT_STATE() AS VARCHAR(10));
    
    IF XACT_STATE() <> 0
    BEGIN
        PRINT 'Existe uma transação ativa; executando ROLLBACK...';
        ROLLBACK TRANSACTION;
    END
END CATCH;
GO


-- =================================================================================
-- PARTE 4: TRANSAÇÕES ANINHADAS E SAVEPOINTS (SAVE TRANSACTION)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - SAVE TRANSACTION SavePointName: Cria um ponto de salvamento dentro da transação.
--   - ROLLBACK TRANSACTION SavePointName: Desfaz as alterações feitas APÓS o savepoint sem cancelar a transação externa pai.
--   - @@TRANCOUNT: Contagem de transações ativas.

BEGIN TRANSACTION; -- @@TRANCOUNT = 1
    INSERT INTO lab.Accounts (AccountID, AccountHolder) VALUES (100, 'Cliente Raiz');
    
    SAVE TRANSACTION PontoSalvamento1; -- Cria Savepoint
    
    INSERT INTO lab.Accounts (AccountID, AccountHolder) VALUES (101, 'Cliente Provisório');
    
    -- Desfaz apenas a inserção do Cliente Provisório
    ROLLBACK TRANSACTION PontoSalvamento1;
    
COMMIT TRANSACTION; -- @@TRANCOUNT volta para 0. O Cliente Raiz (100) é mantido!
GO

-- Verificar resultado: Apenas o Cliente 100 foi mantido
SELECT * FROM lab.Accounts WHERE AccountID IN (100, 101);
GO


-- =================================================================================
-- PARTE 5: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Processamento em Lote com Tratamento de Savepoint em Stored Procedure
-- Permite processar itens individuais salvando os válidos e revertendo itens individuais com erro via Savepoint.

CREATE PROCEDURE lab.usp_ProcessBatchWithSavepoints
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TranCount INT = @@TRANCOUNT;

    IF @TranCount = 0
        BEGIN TRANSACTION;
    ELSE
        SAVE TRANSACTION SP_BatchProc;

    BEGIN TRY
        -- Operações do lote...
        UPDATE lab.Accounts SET Status = 'Active' WHERE Status = 'Inactive';
        
        IF @TranCount = 0
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        -- Uma transação condenada não pode voltar a savepoint; ela exige rollback total.
        IF XACT_STATE() = -1
            ROLLBACK TRANSACTION;
        ELSE IF @TranCount = 0 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        ELSE IF @TranCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION SP_BatchProc;

        THROW;
    END CATCH;
END;
GO
