-- =================================================================================
-- DP-800 - LAB PRÁTICO: STORED PROCEDURES (sp_executesql, OUTPUT, TVP, TRY/CATCH E EXECUTE AS)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a criação, parametrização e tratamento de erros em Stored Procedures:
--   1. Parâmetros de Saída (OUTPUT Parameters) e Tabelas como Parâmetro (Table-Valued Parameters - TVP)
--   2. SQL Dinâmico Seguro: sp_executesql vs EXEC(@sql) (Injeção de SQL e Reuso de Plano)
--   3. Tratamento Avançado de Erros e Transações (TRY/CATCH, THROW e XACT_STATE)
--   4. Parameter Sniffing e Recompilação (OPTION (OPTIMIZE FOR UNKNOWN) e WITH RECOMPILE)
--   5. Contexto de Segurança (EXECUTE AS OWNER / CALLER)
--   6. Cenários Práticos de Projeto (Processamento em Lote de Pedidos com Transação Protegida)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_CreateOrderWithOutput' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_CreateOrderWithOutput;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ProcessOrderBatch' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_ProcessOrderBatch;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SearchOrdersDynamic' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_SearchOrdersDynamic;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SafeTransactionTransfer' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_SafeTransactionTransfer;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SearchOrdersRecompile' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_SearchOrdersRecompile;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ReadOrdersAsOwner' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_ReadOrdersAsOwner;

IF EXISTS (SELECT * FROM sys.types WHERE name = 'OrderItemTableType' AND schema_id = SCHEMA_ID('lab'))
    DROP TYPE lab.OrderItemTableType;

DROP TABLE IF EXISTS lab.BankAccounts;
DROP TABLE IF EXISTS lab.OrderItems;
DROP TABLE IF EXISTS lab.Orders;
GO

-- Estrutura de Tabelas para Teste
CREATE TABLE lab.Orders (
    OrderID INT IDENTITY(1000,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    TotalAmount DECIMAL(18,2) NOT NULL DEFAULT 0.00
);

CREATE TABLE lab.OrderItems (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductName NVARCHAR(100) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL,
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderID) REFERENCES lab.Orders(OrderID)
);

CREATE TABLE lab.BankAccounts (
    AccountID INT PRIMARY KEY,
    AccountHolder NVARCHAR(100) NOT NULL,
    Balance DECIMAL(18,2) NOT NULL
);
GO


-- =================================================================================
-- PARTE 1: PARÂMETROS OUTPUT E TABLE-VALUED PARAMETERS (TVP)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - OUTPUT PARAMETERS: Permitem retornar valores individuais de volta para o chamador da procedure.
--     Requer a palavra-chave `OUTPUT` tanto na assinatura da procedure quanto na chamada `EXEC`.
--   - TABLE-VALUED PARAMETERS (TVP): Permite passar tabelas inteiras como parâmetro para uma procedure.
--     Requisito: O tipo de tabela deve ser criado via `CREATE TYPE` e declarado obrigatoriamente como `READONLY` na procedure.

-- 1. Criar um Table Type (TVP)
CREATE TYPE lab.OrderItemTableType AS TABLE (
    ProductName NVARCHAR(100) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL
);
GO

-- 2. Procedure que utiliza OUTPUT Parameter e TVP READONLY
CREATE PROCEDURE lab.usp_ProcessOrderBatch
    @CustomerID INT,
    @Items lab.OrderItemTableType READONLY, -- Obrigatoriamente READONLY
    @NewOrderID INT OUTPUT                 -- Parâmetro de Retorno
AS
BEGIN
    SET NOCOUNT ON;

    -- Inserir cabeçalho do pedido
    INSERT INTO lab.Orders (CustomerID, TotalAmount)
    VALUES (@CustomerID, 0);

    SET @NewOrderID = SCOPE_IDENTITY();

    -- Inserir itens do lote vindos do TVP
    INSERT INTO lab.OrderItems (OrderID, ProductName, Quantity, UnitPrice)
    SELECT @NewOrderID, ProductName, Quantity, UnitPrice
    FROM @Items;

    -- Atualizar o valor total do pedido
    UPDATE lab.Orders
    SET TotalAmount = (SELECT SUM(Quantity * UnitPrice) FROM lab.OrderItems WHERE OrderID = @NewOrderID)
    WHERE OrderID = @NewOrderID;
END;
GO

-- Executando a procedure com TVP e capturando o OUTPUT
DECLARE @ItemsBatch lab.OrderItemTableType;
INSERT INTO @ItemsBatch (ProductName, Quantity, UnitPrice)
VALUES ('Monitor 4K', 1, 450.00), ('Mouse Sem Fio', 2, 25.00);

DECLARE @CreatedOrderID INT;
EXEC lab.usp_ProcessOrderBatch 
    @CustomerID = 101, 
    @Items = @ItemsBatch, 
    @NewOrderID = @CreatedOrderID OUTPUT;

SELECT @CreatedOrderID AS OrderIDGerado;
SELECT * FROM lab.Orders WHERE OrderID = @CreatedOrderID;
SELECT * FROM lab.OrderItems WHERE OrderID = @CreatedOrderID;
GO


-- =================================================================================
-- PARTE 2: DYNAMIC SQL SEGURO: SP_EXECUTESQL VS EXEC(@SQL)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - EXEC(@sql): Concatena strings brutas. NÃO parametriza consultas, expõe a aplicação a SQL INJECTION
--     e impede o reuso do plano de execução no cache.
--   - SP_EXECUTESQL: Executa SQL dinâmico parametrizado. Evita injeção de SQL e reaproveita planos de execução.
--   - QUOTENAME(): Função essencial para sanitizar nomes dinâmicos de objetos (tabelas/colunas).

CREATE PROCEDURE lab.usp_SearchOrdersDynamic
    @CustomerID INT = NULL,
    @MinAmount DECIMAL(18,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @ParamDef NVARCHAR(500);

    SET @Sql = N'SELECT OrderID, CustomerID, TotalAmount FROM lab.Orders WHERE 1=1';

    IF @CustomerID IS NOT NULL
        SET @Sql += N' AND CustomerID = @CustID';

    IF @MinAmount IS NOT NULL
        SET @Sql += N' AND TotalAmount >= @MinAmt';

    -- Definição dos parâmetros para o sp_executesql
    SET @ParamDef = N'@CustID INT, @MinAmt DECIMAL(18,2)';

    -- -- [PONTO DE ATENÇÃO DP-800]
    -- Execução segura com sp_executesql parametrizado
    EXEC sp_executesql 
        @stmt = @Sql, 
        @params = @ParamDef, 
        @CustID = @CustomerID, 
        @MinAmt = @MinAmount;
END;
GO

-- Teste de busca dinâmica
EXEC lab.usp_SearchOrdersDynamic @CustomerID = 101, @MinAmount = 100.00;
GO


-- =================================================================================
-- PARTE 3: TRATAMENTO DE ERROS E TRANSAÇÕES (TRY/CATCH, THROW E XACT_STATE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - XACT_STATE(): Retorna 1 (transação comitável), 0 (sem transação) ou -1 (transação não-comitável/condenada).
--   - Se XACT_STATE() = -1, o SQL Server PROÍBE qualquer COMMIT. É OBRIGATÓRIO executar ROLLBACK.
--   - THROW: Comando moderno para relançar erros preservando o número original da exceção (substitui RAISERROR).

INSERT INTO lab.BankAccounts VALUES (1, 'Conta Origem', 1000.00), (2, 'Conta Destino', 500.00);
GO

CREATE PROCEDURE lab.usp_SafeTransactionTransfer
    @FromAccount INT,
    @ToAccount INT,
    @Amount DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- Recomendado para garantir rollback automático em erros fatais

    BEGIN TRANSACTION;
    BEGIN TRY
        -- 1. Debitar saldo
        UPDATE lab.BankAccounts
        SET Balance = Balance - @Amount
        WHERE AccountID = @FromAccount;

        -- Validar se o saldo ficou negativo (Dispara erro de negócio)
        IF (SELECT Balance FROM lab.BankAccounts WHERE AccountID = @FromAccount) < 0
            THROW 51000, 'Saldo insuficiente para concluir a transferência.', 1;

        -- 2. Creditar saldo
        UPDATE lab.BankAccounts
        SET Balance = Balance + @Amount
        WHERE AccountID = @ToAccount;

        COMMIT TRANSACTION;
        PRINT 'Transferência realizada com sucesso!';
    END TRY
    BEGIN CATCH
        -- -- [PONTO DE ATENÇÃO DP-800]
        -- Verificação de XACT_STATE() no CATCH
        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        PRINT 'ERRO NA TRANSAÇÃO: ' + ERROR_MESSAGE();
        THROW; -- Relança o erro para a aplicação chamadora
    END CATCH;
END;
GO

-- Teste de transferência com saldo insuficiente (Falha e Rollback Seguro)
BEGIN TRY
    EXEC lab.usp_SafeTransactionTransfer @FromAccount = 1, @ToAccount = 2, @Amount = 5000.00;
END TRY
BEGIN CATCH
    PRINT 'CAPTURADO PELA APLICAÇÃO: ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PARTE 4: PARAMETER SNIFFING E RECOMPILAÇÃO
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PARAMETER SNIFFING: Ocorre quando a procedure compila o plano de execução baseado no PRIMEIRO parâmetro
--     recebido. Se o primeiro parâmetro for atípico (ex: busca poucas linhas), o plano salvo pode ser péssimo para buscas de volume alto.
--   - SOLUÇÕES PARA PARAMETER SNIFFING:
--     1. `OPTION (OPTIMIZE FOR (@Param UNKNOWN))`: Instruções para o otimizador usar a estatística média (Mais recomendada).
--     2. `OPTION (RECOMPILE)` na query específica: Recompila o plano apenas naquela execução sem afetar a procedure inteira.
--     3. `WITH RECOMPILE` na criação da procedure: Força recompilação completa a cada chamada (alto custo de CPU).

-- Exemplo com recompilação apenas na instrução sensível. A procedure continua reutilizável para
-- outros comandos, enquanto esta consulta compila para o valor atual de @CustomerID.
CREATE PROCEDURE lab.usp_SearchOrdersRecompile
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT OrderID, CustomerID, TotalAmount
    FROM lab.Orders
    WHERE CustomerID = @CustomerID
    OPTION (RECOMPILE);
END;
GO

EXEC lab.usp_SearchOrdersRecompile @CustomerID = 101;
GO


-- =================================================================================
-- PARTE 5: CONTEXTO DE SEGURANÇA (EXECUTE AS OWNER)
-- =================================================================================
-- EXECUTE AS OWNER permite expor uma operação controlada sem conceder SELECT direto na tabela
-- ao chamador. Em produção, conceda apenas EXECUTE na procedure e mantenha o princípio do menor privilégio.
CREATE PROCEDURE lab.usp_ReadOrdersAsOwner
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT OrderID, CustomerID, OrderDate, TotalAmount
    FROM lab.Orders;
END;
GO

EXEC lab.usp_ReadOrdersAsOwner;
GO
GO
