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
-- NOTA SOBRE SET OPTIONS E QUERY HINTS:
--   - `SET NOCOUNT ON` suprime mensagens como "(10 linhas afetadas)"; não suprime result sets
--     nem erros. É recomendado na maioria das procedures para reduzir tráfego desnecessário.
--   - `SET XACT_ABORT ON` faz erros de execução encerrarem e reverterem a transação atual. É útil
--     em DML multi-etapa, mas não substitui TRY/CATCH, XACT_STATE() e THROW para tratar/propagar erros.
--   - `OPTION (RECOMPILE)` e `OPTION (OPTIMIZE FOR ...)` são query hints: atuam na compilação de uma
--     instrução específica. Use-os após observar plano, cardinalidade, CPU e leituras; não como padrão.
--   - Outros hints (por exemplo, MAXDOP, FORCESEEK e USE HINT) são intervenções pontuais e podem
--     causar regressão quando os dados mudam. Prefira índices, estatísticas e T-SQL sargável primeiro.
-- NOTA SOBRE CÓDIGOS THROW:
--   - `THROW numero, mensagem, state` cria erros de aplicação. O número deve ser >= 50000; neste
--     lab, a faixa 51000 identifica regras de negócio/validação da procedure.
--   - O `state` (0 a 255) permite distinguir pontos de origem do mesmo erro. Aqui usamos 1 por
--     simplicidade. No CATCH, consulte ERROR_NUMBER(), ERROR_MESSAGE() e ERROR_STATE().
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
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SearchOrdersSniffed' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_SearchOrdersSniffed;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_SearchOrdersOptimizeForUnknown' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_SearchOrdersOptimizeForUnknown;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_ReadOrdersAsOwner' AND schema_id = SCHEMA_ID('lab'))
    DROP PROCEDURE lab.usp_ReadOrdersAsOwner;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = N'lab_ProcedureReader')
    DROP USER lab_ProcedureReader;

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

-- Índices que tornam os exemplos de consulta por cliente e de itens por pedido realistas.
CREATE INDEX IX_Orders_CustomerID ON lab.Orders (CustomerID);
CREATE INDEX IX_OrderItems_OrderID ON lab.OrderItems (OrderID) INCLUDE (Quantity, UnitPrice);
GO


-- =================================================================================
-- PARTE 1: PARÂMETROS OUTPUT E TABLE-VALUED PARAMETERS (TVP)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - OUTPUT PARAMETERS: Permitem retornar valores individuais de volta para o chamador da procedure.
--     Requer a palavra-chave `OUTPUT` tanto na assinatura da procedure quanto na chamada `EXEC`.
--   - TABLE-VALUED PARAMETERS (TVP): Permite passar uma tabela inteira, com várias linhas, como parâmetro
--     para uma procedure. É útil para operações em lote, como enviar todos os itens de um pedido em uma
--     única chamada, sem executar a procedure uma vez por item.
--     Requisito: o formato das colunas é criado via `CREATE TYPE`; na assinatura, o TVP deve ser
--     obrigatoriamente `READONLY`. A procedure pode ler @Items e gravar seus dados nas tabelas reais,
--     mas não pode alterar diretamente as linhas do próprio @Items.

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
    -- Evita mensagens de contagem a cada INSERT/UPDATE, sem ocultar os SELECTs de resultado.
    SET NOCOUNT ON;
    -- Em uma operação com várias escritas, erros de execução anulam a transação ativa.
    -- TRY/CATCH abaixo ainda decide o ROLLBACK e propaga o erro ao chamador.
    SET XACT_ABORT ON;

    -- Validações antes de alterar qualquer tabela: um pedido sem itens ou com valores inválidos
    -- não deve criar um cabeçalho parcialmente persistido.
    IF NOT EXISTS (SELECT 1 FROM @Items)
        -- 51010: TVP sem linhas; o chamador deve enviar pelo menos um item.
        THROW 51010, 'O lote de itens não pode estar vazio.', 1;

    IF EXISTS (SELECT 1 FROM @Items WHERE Quantity <= 0 OR UnitPrice < 0)
        -- 51011: valores de negócio inválidos no TVP.
        THROW 51011, 'Quantidade deve ser positiva e preço não pode ser negativo.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Inserir cabeçalho do pedido
        INSERT INTO lab.Orders (CustomerID, TotalAmount)
        VALUES (@CustomerID, 0);

        SET @NewOrderID = CONVERT(INT, SCOPE_IDENTITY());

        -- Inserir itens do lote vindos do TVP
        INSERT INTO lab.OrderItems (OrderID, ProductName, Quantity, UnitPrice)
        SELECT @NewOrderID, ProductName, Quantity, UnitPrice
        FROM @Items;

        -- Atualizar o valor total do pedido
        UPDATE lab.Orders
        SET TotalAmount =
        (
            SELECT SUM(Quantity * UnitPrice)
            FROM lab.OrderItems
            WHERE OrderID = @NewOrderID
        )
        WHERE OrderID = @NewOrderID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
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

-- [PONTO DE ATENÇÃO DP-800] O TVP vazio falha antes de criar um cabeçalho de pedido.
BEGIN TRY
    DECLARE @EmptyItems lab.OrderItemTableType;
    DECLARE @UnexpectedOrderID INT;
    EXEC lab.usp_ProcessOrderBatch
        @CustomerID = 101,
        @Items = @EmptyItems,
        @NewOrderID = @UnexpectedOrderID OUTPUT;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO TVP VAZIO: ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PARTE 2: DYNAMIC SQL SEGURO: SP_EXECUTESQL VS EXEC(@SQL)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - EXEC(@sql): Quando concatena valores externos, não os parametriza e expõe a aplicação a SQL INJECTION.
--     Textos diferentes também tendem a fragmentar o cache de planos.
--   - SP_EXECUTESQL: Parametriza valores, favorece reuso de planos e evita injeção nesses valores.
--     Identificadores dinâmicos ainda exigem lista branca e QUOTENAME().
--   - QUOTENAME(): Função essencial para sanitizar nomes dinâmicos de objetos (tabelas/colunas).

CREATE PROCEDURE lab.usp_SearchOrdersDynamic
    @CustomerID INT = NULL,
    @MinAmount DECIMAL(18,2) = NULL,
    @SortColumn SYSNAME = N'OrderDate',
    @SortDirection VARCHAR(4) = 'DESC'
AS
BEGIN
    -- Boa prática para procedures: reduz mensagens "n linhas afetadas" enviadas ao cliente.
    SET NOCOUNT ON;

    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @ParamDef NVARCHAR(500);
    DECLARE @OrderBy NVARCHAR(300);

    -- Valores podem ser parâmetros; identificadores precisam de lista branca e QUOTENAME.
    IF @SortColumn NOT IN (N'OrderID', N'OrderDate', N'TotalAmount')
        -- 51020: identificador fora da lista branca (inclusive tentativa de injeção).
        THROW 51020, 'Coluna de ordenação inválida.', 1;

    IF @SortDirection NOT IN ('ASC', 'DESC')
        -- 51021: direção de ordenação inválida.
        THROW 51021, 'Direção de ordenação inválida.', 1;

    SET @OrderBy = QUOTENAME(@SortColumn) + N' ' + @SortDirection;
    SET @Sql = N'SELECT OrderID, CustomerID, OrderDate, TotalAmount FROM lab.Orders WHERE 1=1';

    IF @CustomerID IS NOT NULL
        SET @Sql += N' AND CustomerID = @CustID';

    IF @MinAmount IS NOT NULL
        SET @Sql += N' AND TotalAmount >= @MinAmt';

    SET @Sql += N' ORDER BY ' + @OrderBy + N';';

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
EXEC lab.usp_SearchOrdersDynamic
    @CustomerID = 101,
    @MinAmount = 100.00,
    @SortColumn = N'TotalAmount',
    @SortDirection = 'DESC';

-- Identificadores não podem ser parametrizados; uma lista branca bloqueia a tentativa de injeção.
BEGIN TRY
    EXEC lab.usp_SearchOrdersDynamic @SortColumn = N'OrderID; DROP TABLE lab.Orders;--';
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO IDENTIFICADOR DINÂMICO: ' + ERROR_MESSAGE();
END CATCH;
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
    -- Mantém apenas os result sets úteis para o chamador, sem mensagens de contagem intermediárias.
    SET NOCOUNT ON;
    -- Complementa o TRY/CATCH: erros de execução em DML multi-etapa tornam a transação inválida
    -- ou a revertem; XACT_STATE() no CATCH decide se ainda há algo a desfazer.
    SET XACT_ABORT ON;

    IF @Amount <= 0
        -- 51001: valor de transferência inválido.
        THROW 51001, 'O valor da transferência deve ser maior que zero.', 1;

    IF @FromAccount = @ToAccount
        -- 51002: origem e destino não podem ser a mesma conta.
        THROW 51002, 'A conta de origem deve ser diferente da conta de destino.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Debitar somente se a conta existir e houver saldo. O predicado na própria
        -- atualização evita saldo negativo mesmo com concorrência.
        UPDATE lab.BankAccounts
        SET Balance = Balance - @Amount
        WHERE AccountID = @FromAccount
          AND Balance >= @Amount;

        IF @@ROWCOUNT <> 1
            -- 51000: a conta de origem não existe ou não possui saldo suficiente.
            THROW 51000, 'Conta de origem inexistente ou saldo insuficiente.', 1;

        -- 2. Creditar apenas uma conta existente.
        UPDATE lab.BankAccounts
        SET Balance = Balance + @Amount
        WHERE AccountID = @ToAccount;

        IF @@ROWCOUNT <> 1
            -- 51003: conta de destino inexistente; o CATCH reverte o débito já realizado.
            THROW 51003, 'Conta de destino inexistente.', 1;

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

-- Confirme que o rollback preservou os saldos originais.
SELECT AccountID, AccountHolder, Balance
FROM lab.BankAccounts
ORDER BY AccountID;
GO


-- =================================================================================
-- PARTE 4: PARAMETER SNIFFING E RECOMPILAÇÃO
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PARAMETER SNIFFING: Ocorre quando a procedure compila o plano de execução baseado no PRIMEIRO parâmetro
--     recebido. Se o primeiro parâmetro for atípico (ex: busca poucas linhas), o plano salvo pode ser péssimo para buscas de volume alto.
--   - SOLUÇÕES PARA PARAMETER SNIFFING:
--     1. `OPTION (OPTIMIZE FOR (@Param UNKNOWN))`: Instrui o otimizador a usar a estatística média.
--        Pode estabilizar o plano, mas precisa ser validada contra a carga real.
--     2. `OPTION (RECOMPILE)` na query específica: Recompila o plano apenas naquela execução sem afetar a procedure inteira.
--     3. `WITH RECOMPILE` na criação da procedure: Força recompilação completa a cada chamada (alto custo de CPU).

-- Massa propositalmente assimétrica: o cliente 9001 tem 50.000 pedidos e o 9002 tem apenas um.
-- Com o índice não-cobridor por CustomerID, o plano seletivo pode favorecer seeks/lookups,
-- enquanto uma chamada de alto volume pode preferir um acesso diferente. O plano exato depende
-- da versão e do ambiente; compare o Plano de Execução Atual (Ctrl+M), não apenas custos percentuais.
;WITH Numbers AS
(
    SELECT TOP (50000)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Number
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
)
INSERT INTO lab.Orders (CustomerID, OrderDate, TotalAmount)
SELECT 9001, DATEADD(DAY, -(Number % 365), SYSUTCDATETIME()), 50.00
FROM Numbers;

INSERT INTO lab.Orders (CustomerID, OrderDate, TotalAmount)
VALUES (9002, SYSUTCDATETIME(), 50.00);

UPDATE STATISTICS lab.Orders IX_Orders_CustomerID;
GO

-- Sem hint: a primeira execução pode deixar em cache um plano otimizado para o parâmetro recebido.
CREATE PROCEDURE lab.usp_SearchOrdersSniffed
    @CustomerID INT
AS
BEGIN
    -- NOCOUNT não afeta as linhas retornadas pelo SELECT; apenas as mensagens de contagem.
    SET NOCOUNT ON;

    SELECT OrderID, CustomerID, TotalAmount
    FROM lab.Orders
    WHERE CustomerID = @CustomerID;
END;
GO

-- Plano médio: ignora o valor específico ao compilar e usa a distribuição estatística média.
CREATE PROCEDURE lab.usp_SearchOrdersOptimizeForUnknown
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT OrderID, CustomerID, TotalAmount
    FROM lab.Orders
    WHERE CustomerID = @CustomerID
    OPTION (OPTIMIZE FOR (@CustomerID UNKNOWN));
END;
GO

-- Recompilação somente na instrução sensível. A procedure continua reutilizável para
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

-- COMO VALIDAR:
--   1. No SSMS, habilite o Plano de Execução Atual (Ctrl+M) ANTES de executar este bloco.
--   2. Compare as leituras lógicas e CPU na aba Messages após cada PRINT.
--   3. No plano, compare linhas Estimated x Actual e o tipo de acesso a lab.Orders.
-- O script acabou de recriar as procedures, então a primeira execução de usp_SearchOrdersSniffed
-- compila e armazena seu plano em cache sem precisar limpar o cache global do servidor.
SET STATISTICS IO, TIME ON;
GO

-- 1. PARAMETER SNIFFING: 9002 (1 linha) compila o plano; 9001 (50.000 linhas) reutiliza-o.
PRINT 'TESTE 1 - Plano cacheado: compile para CustomerID 9002 e reuse para CustomerID 9001.';
EXEC lab.usp_SearchOrdersSniffed @CustomerID = 9002;
EXEC lab.usp_SearchOrdersSniffed @CustomerID = 9001;

-- 2. OPTIMIZE FOR UNKNOWN: ambos usam um plano médio, independente do valor compilado.
PRINT 'TESTE 2 - OPTIMIZE FOR UNKNOWN: compare o plano médio para os dois extremos.';
EXEC lab.usp_SearchOrdersOptimizeForUnknown @CustomerID = 9002;
EXEC lab.usp_SearchOrdersOptimizeForUnknown @CustomerID = 9001;

-- 3. RECOMPILE: cada chamada compila um plano específico para sua cardinalidade atual.
PRINT 'TESTE 3 - RECOMPILE: cada CustomerID recebe compilação própria; compare CPU de compilação e leituras.';
EXEC lab.usp_SearchOrdersRecompile @CustomerID = 9002;
EXEC lab.usp_SearchOrdersRecompile @CustomerID = 9001;

SET STATISTICS IO, TIME OFF;
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

    SELECT TOP (10) OrderID, CustomerID, OrderDate, TotalAmount
    FROM lab.Orders
    ORDER BY OrderID DESC;
END;
GO

-- Usuário sem login para demonstrar menor privilégio dentro do banco de laboratório.
CREATE USER lab_ProcedureReader WITHOUT LOGIN;
DENY SELECT ON lab.Orders TO lab_ProcedureReader;
GRANT EXECUTE ON lab.usp_ReadOrdersAsOwner TO lab_ProcedureReader;

EXECUTE AS USER = N'lab_ProcedureReader';
GO

-- Acesso direto é negado, mas a procedure executa sob o contexto do proprietário.
BEGIN TRY
    SELECT TOP (1) OrderID, CustomerID
    FROM lab.Orders;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO SELECT DIRETO: ' + ERROR_MESSAGE();
END CATCH;

EXEC lab.usp_ReadOrdersAsOwner;
GO

REVERT;
GO


-- =================================================================================
-- PARTE 6: COMPOSIÇÃO DE STORED PROCEDURES
-- =================================================================================
-- Uma procedure pode chamar outra, mas evite cadeias profundas (ProcA -> ProcB -> ProcC)
-- usadas apenas para fragmentar SQL. Prefira uma procedure orquestradora curta e procedures
-- internas com responsabilidades coesas e reutilizáveis.
--
-- REGRAS PRÁTICAS:
--   1. A procedure EXTERNA é dona da transação: ela inicia e decide COMMIT ou ROLLBACK.
--   2. Procedures INTERNAS participam da transação existente e não devem emitir COMMIT
--      indiscriminadamente. Em caso de erro, propagam com THROW para a orquestradora.
--   3. Todas devem acessar as tabelas em uma ordem consistente para reduzir deadlocks.
--   4. Mantenha a profundidade pequena e evite recursão; SQL Server limita o aninhamento
--      de procedures a 32 níveis.
--   5. Para reutilizar apenas uma consulta, considere View, iTVF ou CTE antes de criar outra procedure.
--
-- Padrão recomendado:
-- usp_ProcessarPedido (orquestradora; BEGIN TRAN / COMMIT / ROLLBACK)
--   ├─ usp_ValidarPagamento (interna; sem COMMIT)
--   ├─ usp_GravarPedido     (interna; sem COMMIT)
--   └─ usp_RegistrarAuditoria (interna; sem COMMIT)


-- =================================================================================
-- PARTE 7: CHECKLIST DE BOAS PRÁTICAS PARA STORED PROCEDURES
-- =================================================================================
-- Esta seção separa práticas DENTRO da procedure das práticas FORA dela. Nem toda procedure
-- precisa de transação, XACT_ABORT ou hints: aplique apenas o que o contrato e a carga exigirem.
--
-- DENTRO DA PROCEDURE
--   [ ] Comece com SET NOCOUNT ON para evitar mensagens de contagem desnecessárias.
--   [ ] Defina um contrato claro: nomes de parâmetros explícitos, tipos corretos, valores aceitos,
--       result sets esperados, OUTPUT/RETURN e códigos THROW documentados.
--   [ ] Valide entradas antes de alterar dados; para TVPs, valide vazio, duplicidade e regras de negócio.
--   [ ] Use operações set-based, predicados sargáveis e colunas explícitas; evite SELECT * e cursores/RBAR
--       sem justificativa mensurável.
--   [ ] Em DML com várias etapas que precisam ser atômicas, use TRY/CATCH, transação curta, XACT_STATE()
--       no CATCH e THROW. Considere SET XACT_ABORT ON para erros de execução; ele não substitui o CATCH.
--   [ ] Parametrize valores em SQL dinâmico com sp_executesql; para nomes de objetos, use lista branca e
--       QUOTENAME. Revise todo uso de EXEC/EXECUTE/sp_executesql quanto a injeção.
--   [ ] Use OPTION(RECOMPILE), OPTIMIZE FOR e demais hints somente com evidência de plano, I/O, CPU e
--       cardinalidade. Registre o motivo e reavalie após mudanças de dados.
--       Evidência mínima: Plano de Execução Real com diferença relevante entre Estimated Rows e Actual Rows;
--       SET STATISTICS IO, TIME ON mostrando leituras/CPU excessivas; lentidão reproduzível para determinados
--       parâmetros; e estatísticas atualizadas. Procure também Key Lookups repetitivos, Nested Loops para
--       muitas linhas, scans excessivos ou spills em Sort/Hash antes de escolher um hint.
--   [ ] Se uma procedure chama outra, a orquestradora controla COMMIT/ROLLBACK; internas não fazem COMMIT
--       autônomo e propagam falhas com THROW.
--
-- FORA DA PROCEDURE
--   [ ] Conceda EXECUTE ao chamador, não SELECT/INSERT/UPDATE amplo nas tabelas. EXECUTE AS deve usar o
--       principal com o menor privilégio necessário; valide efeitos em auditoria e Row-Level Security.
--   [ ] Crie e mantenha índices e estatísticas para filtros, joins e ordenações usados pela procedure.
--       Valide o plano real com parâmetros seletivos e não seletivos, sobretudo após alterações de volume.
--   [ ] Trate a procedure como uma API: versão compatível, contrato de retorno estável e chamadas sempre
--       parametrizadas na aplicação. Não concatene entrada externa antes de chamar SQL dinâmico.
--   [ ] Teste sucesso, entradas inválidas, TVP vazio, rollback, concorrência/deadlock e permissões de um
--       usuário de menor privilégio. Monitore duração, CPU, leituras, erros e regressões de plano.
--   [ ] Faça deploy com CREATE OR ALTER, revisão de permissões e plano de rollback; não dependa de hints
--       para compensar ausência de índices, estatísticas ou modelagem adequada.
--
-- Fontes oficiais Microsoft Learn:
--   CREATE PROCEDURE: https://learn.microsoft.com/sql/t-sql/statements/create-procedure-transact-sql
--   SET NOCOUNT: https://learn.microsoft.com/sql/t-sql/statements/set-nocount-transact-sql
--   TRY/CATCH e XACT_STATE: https://learn.microsoft.com/sql/t-sql/language-elements/try-catch-transact-sql
--   EXECUTE AS: https://learn.microsoft.com/sql/t-sql/statements/execute-as-transact-sql
--   SQL dinâmico seguro: https://learn.microsoft.com/sql/connect/ado-net/sql/writing-secure-dynamic-sql


-- =================================================================================
-- PARTE 8: PREVENÇÃO DE SQL INJECTION EM STORED PROCEDURES
-- =================================================================================
-- Uma procedure NÃO é automaticamente imune a SQL injection. SQL estático com parâmetros tipados
-- é seguro porque o valor é tratado como dado; o risco reaparece quando texto externo é concatenado
-- e executado por EXEC/EXECUTE ou sp_executesql.
--
-- 1. PREFIRA SQL ESTÁTICO: o parâmetro nunca se torna parte do código SQL.
--    SELECT OrderID FROM lab.Orders WHERE CustomerID = @CustomerID;
--
-- 2. NUNCA concatene valores recebidos do usuário (VULNERÁVEL):
--    SET @Sql = N'SELECT * FROM lab.Orders WHERE CustomerID = ' + @Entrada;
--    EXEC(@Sql);
--
-- 3. Em SQL DINÂMICO, parametrize os valores com sp_executesql (SEGURO):
--    SET @Sql = N'SELECT * FROM lab.Orders WHERE CustomerID = @CustomerID;';
--    EXEC sys.sp_executesql @Sql, N'@CustomerID INT', @CustomerID = @Entrada;
--
-- 4. Nomes de tabelas, colunas e direção de ORDER BY NÃO podem ser parâmetros. Para eles:
--    * aceite somente uma lista branca de valores permitidos;
--    * aplique QUOTENAME() em identificadores; e
--    * valide ASC/DESC explicitamente, sem concatenar texto livre.
--    A usp_SearchOrdersDynamic deste lab demonstra esse padrão.
--
-- 5. FORA DO CÓDIGO: a aplicação também deve enviar parâmetros tipados; conceda apenas EXECUTE
--    ao usuário da aplicação e revise todo uso de EXEC, EXECUTE e sp_executesql. Menor privilégio
--    reduz o impacto caso uma falha de validação ocorra.
--
-- Fonte oficial: https://learn.microsoft.com/sql/connect/ado-net/sql/writing-secure-dynamic-sql

-- =================================================================================================
-- REFERÊNCIAS OFICIAIS DO MICROSOFT LEARN
-- =================================================================================================
-- CREATE PROCEDURE, parâmetros OUTPUT e WITH RECOMPILE:
-- https://learn.microsoft.com/pt-br/sql/t-sql/statements/create-procedure-transact-sql?view=sql-server-ver17
-- Parâmetros do tipo tabela (TVPs):
-- https://learn.microsoft.com/pt-br/sql/relational-databases/programming/table-valued-parameters?view=sql-server-ver17
-- sp_executesql e SQL dinâmico parametrizado:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/system-stored-procedures/sp-executesql-transact-sql?view=sql-server-ver17
-- TRY/CATCH, THROW e XACT_STATE:
-- https://learn.microsoft.com/pt-br/sql/t-sql/language-elements/try-catch-transact-sql?view=sql-server-ver17
-- EXECUTE AS:
-- https://learn.microsoft.com/pt-br/sql/t-sql/statements/execute-as-transact-sql?view=sql-server-ver17
-- Planos sensíveis a parâmetros e parameter sniffing:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/performance/parameter-sensitive-plan-optimization?view=sql-server-ver17
