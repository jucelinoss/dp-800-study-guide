-- =================================================================================
-- DP-800 - LAB PRÁTICO: TRIGGERS (AFTER, INSTEAD OF, DDL E MULTI-ROW HANDLING)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a criação, otimização e regras de execução de Triggers no SQL Server:
--   1. DML AFTER Triggers e o uso correto das tabelas virtuais inserted e deleted
--   2. O Erro Clássico de Manipulação de Linha Única vs Suporte a Operações Multi-Linha
--   3. INSTEAD OF Triggers em Views Multi-Tabelas
--   4. DDL Triggers a nível de Banco de Dados e análise da função EVENTDATA()
--   5. Regras de Ordem de Execução (sp_settriggerorder) e Recursividade
--   6. Cenários Práticos de Projeto (Trilha de Auditoria em Lote e Prevenção de DDL Não Autorizado)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_AuditProducts_MultiRow')
    DROP TRIGGER lab.trg_AuditProducts_MultiRow;
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_vw_OrderCustomerDetails_Insert')
    DROP TRIGGER lab.trg_vw_OrderCustomerDetails_Insert;
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_PreventTableDrop' AND parent_class = 0)
    DROP TRIGGER trg_PreventTableDrop ON DATABASE;

IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_OrderCustomerDetails' AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_OrderCustomerDetails;

DROP TABLE IF EXISTS lab.ProductAuditLog;
DROP TABLE IF EXISTS lab.Products;
DROP TABLE IF EXISTS lab.Orders;
DROP TABLE IF EXISTS lab.Customers;
GO


-- Estrutura de Tabelas para Teste
CREATE TABLE lab.Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Price DECIMAL(18,2) NOT NULL
);

CREATE TABLE lab.ProductAuditLog (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    ActionType NVARCHAR(20) NOT NULL,
    OldPrice DECIMAL(18,2) NULL,
    NewPrice DECIMAL(18,2) NULL,
    ChangedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
    ChangedBy NVARCHAR(128) DEFAULT SUSER_SNAME()
);

CREATE TABLE lab.Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) UNIQUE NOT NULL
);

CREATE TABLE lab.Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL
);
GO


-- =================================================================================
-- PARTE 1: AFTER TRIGGERS E SUPORTE A OPERAÇÕES MULTI-LINHA (SET-BASED)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - TABELAS VIRTUAIS inserted E deleted:
--     * INSERT: inserted contém as novas linhas inseridas. deleted fica vazia.
--     * DELETE: deleted contém as linhas removidas. inserted fica vazia.
--     * UPDATE: inserted contém os novos valores; deleted contém os valores antigos antes da alteração.
--   - ERRO CLÁSSICO DE SINGLE-ROW ASSUMPTION: Escrever a trigger usando `SELECT @val = col FROM inserted`.
--     Se um único comando `UPDATE` alterar 1.000 linhas de uma vez, a trigger é disparada APENAS UMA VEZ.
--     Variáveis escalares capturam apenas UMA linha aleatória, ignorando as outras 999!
--   - REGRA OBRIGATÓRIA: Triggers DML DEVEM usar lógica baseada em conjuntos (JOIN com inserted/deleted).

-- -- [PONTO DE ATENÇÃO DP-800]
-- Trigger escrita de forma robusta e compatível com Multi-Row DML
CREATE TRIGGER lab.trg_AuditProducts_MultiRow
ON lab.Products
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Captura TODAS as linhas afetadas no UPDATE usando JOIN entre inserted e deleted
    INSERT INTO lab.ProductAuditLog (ProductID, ActionType, OldPrice, NewPrice)
    SELECT 
        i.ProductID,
        'UPDATE',
        d.Price AS OldPrice,
        i.Price AS NewPrice
    FROM inserted i
    JOIN deleted d ON i.ProductID = d.ProductID
    WHERE i.Price <> d.Price; -- Grava apenas se o preço realmente mudou
END;
GO

-- Teste Multi-Linha: Atualizando múltiplos produtos em uma única instrução SQL
INSERT INTO lab.Products (ProductName, Price) VALUES ('Produto A', 10.00), ('Produto B', 20.00), ('Produto C', 30.00);

-- UPDATE em lote que afeta 3 linhas de uma vez
UPDATE lab.Products 
SET Price = Price * 1.10;
GO

-- Verifique que o audit log registrou TODAS as 3 alterações perfeitamente!
SELECT * FROM lab.ProductAuditLog;
GO


-- =================================================================================
-- PARTE 2: INSTEAD OF TRIGGERS EM VIEWS MULTI-TABELAS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - INSTEAD OF TRIGGER: Intercepta a instrução DML e executa o código do corpo da trigger EM VEZ DO comando original.
--   - USO EM VIEWS: Views que unem múltiplas tabelas (JOINs) não aceitam INSERT direto. A trigger INSTEAD OF
--     permite desmembrar os dados da tabela virtual `inserted` e realizar o roteamento manual para cada tabela base.

-- 1. View unindo Clientes e Pedidos (Não aceita INSERT direto)
CREATE VIEW lab.vw_OrderCustomerDetails
AS
SELECT o.OrderID, o.TotalAmount, c.CustomerName, c.Email
FROM lab.Orders o
JOIN lab.Customers c ON o.CustomerID = c.CustomerID;
GO

-- 2. Criar Trigger INSTEAD OF INSERT na View
CREATE TRIGGER lab.trg_vw_OrderCustomerDetails_Insert
ON lab.vw_OrderCustomerDetails
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Insere o cliente na tabela base se ele ainda não existir
    INSERT INTO lab.Customers (CustomerName, Email)
    SELECT DISTINCT i.CustomerName, i.Email
    FROM inserted i
    WHERE NOT EXISTS (SELECT 1 FROM lab.Customers c WHERE c.Email = i.Email);

    -- Insere o pedido associando ao CustomerID correspondente
    INSERT INTO lab.Orders (CustomerID, TotalAmount)
    SELECT c.CustomerID, i.TotalAmount
    FROM inserted i
    JOIN lab.Customers c ON c.Email = i.Email;
END;
GO

-- Teste: Inserindo um registro direto na View Multi-Tabela!
INSERT INTO lab.vw_OrderCustomerDetails (CustomerName, Email, TotalAmount)
VALUES ('Daniela Souza', 'daniela@email.com', 850.00);

-- Verifique os dados roteados para as tabelas base
SELECT * FROM lab.Customers WHERE Email = 'daniela@email.com';
SELECT * FROM lab.Orders;
GO


-- =================================================================================
-- PARTE 3: DDL TRIGGERS E A FUNÇÃO EVENTDATA()
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DDL TRIGGER: Disparada por eventos de definição de dados (`CREATE_TABLE`, `ALTER_TABLE`, `DROP_TABLE`).
--     Pode ter escopo de banco (`ON DATABASE`) ou de servidor (`ON ALL SERVER`).
--   - EVENTDATA(): Função interna que retorna um documento XML com os detalhes do evento DDL disparado
--     (nome do objeto, tipo do evento, usuário que executou e o texto T-SQL exato).

-- -- [PONTO DE ATENÇÃO DP-800]
-- DDL Trigger a nível de banco para bloquear e auditar DROP TABLE
CREATE TRIGGER trg_PreventTableDrop
ON DATABASE
FOR DROP_TABLE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EventData XML = EVENTDATA();
    DECLARE @ObjectName NVARCHAR(200) = @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(200)');
    DECLARE @LoginName NVARCHAR(200) = @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(200)');

    PRINT 'BLOQUEIO DDL: A exclusão da tabela ' + @ObjectName + ' foi bloqueada pelo usuário ' + @LoginName;
    ROLLBACK; -- Cancela o comando DROP TABLE
END;
GO

-- Teste: Tentar apagar uma tabela protegida (Deve falhar e fazer ROLLBACK)
BEGIN TRY
    DROP TABLE lab.Products;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO DDL TRIGGER: ' + ERROR_MESSAGE();
    -- Erro: "The transaction ended in the trigger. The batch has been aborted."
END CATCH;
GO

-- O bloqueio foi demonstrado. Desabilite a trigger para que ela não impeça operações
-- posteriores no banco de estudo; habilite-a novamente se quiser repetir o teste.
DISABLE TRIGGER trg_PreventTableDrop ON DATABASE;
GO


-- =================================================================================
-- PARTE 4: ORDENAÇÃO DE DISPARO (SP_SETTRIGGERORDER)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - sp_settriggerorder: Permite definir explicitamente qual trigger executa em PRIMEIRO ('First')
--     ou em ÚLTIMO ('Last') lugar quando existem múltiplas triggers atreladas ao mesmo evento na tabela.

EXEC sp_settriggerorder 
    @triggername = 'lab.trg_AuditProducts_MultiRow',
    @order = 'First',
    @stmttype = 'UPDATE';
GO

-- =================================================================================================
-- REFERÊNCIAS OFICIAIS DO MICROSOFT LEARN
-- =================================================================================================
-- CREATE TRIGGER e gatilhos AFTER e INSTEAD OF:
-- https://learn.microsoft.com/pt-br/sql/t-sql/statements/create-trigger-transact-sql?view=sql-server-ver17
-- Tabelas lógicas inserted e deleted:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/triggers/use-the-inserted-and-deleted-tables?view=sql-server-ver17
-- Gatilhos DDL e EVENTDATA():
-- https://learn.microsoft.com/pt-br/sql/relational-databases/triggers/ddl-triggers?view=sql-server-ver17
-- Ordem de execução de gatilhos com sp_settriggerorder:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/system-stored-procedures/sp-settriggerorder-transact-sql?view=sql-server-ver17
