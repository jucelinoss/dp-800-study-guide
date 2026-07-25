-- =================================================================================
-- DP-800 - LAB PRÁTICO: CONSTRAINTS E SEQUENCES
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a aplicação prática de regras de integridade (constraints) e
-- geradores de sequências numéricas (sequences) no SQL Server, abordando:
--   1. Chaves Únicas: UNIQUE Constraint (1 NULL) vs Unique Index Filtrado (N NULLs)
--   2. Check Constraints e confiabilidade do otimizador (Trusted vs Untrusted)
--   3. Chaves Estrangeiras e Ações Referenciais em Cascata (CASCADE, SET NULL)
--   4. Sequences vs Identity: Geradores compartilhados, Caches e comportamento de Gaps
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva caso rode o script mais de uma vez
DROP TABLE IF EXISTS lab.InvoiceItems;
DROP TABLE IF EXISTS lab.Invoices;
DROP TABLE IF EXISTS lab.Orders;
DROP TABLE IF EXISTS lab.CustomersUnique;
DROP TABLE IF EXISTS lab.ProductsCheck;
DROP TABLE IF EXISTS lab.SystemAuditLogs;
DROP TABLE IF EXISTS lab.OrderDetailsConsolidated;
DROP TABLE IF EXISTS lab.CustomersConsolidated;
DROP TABLE IF EXISTS lab.OrderItemsComposite;
DROP TABLE IF EXISTS lab.EmployeesHierarchy;
DROP TABLE IF EXISTS lab.Projects;
DROP TABLE IF EXISTS lab.IdentityMetadataDemo;
DROP TABLE IF EXISTS lab.BadCustomers;
DROP TABLE IF EXISTS lab.GoodCustomers;
DROP TABLE IF EXISTS lab.EtlDeduplicationStaging;
DROP TABLE IF EXISTS lab.ConsolidatedSalesDW;
DROP TABLE IF EXISTS lab.OnlineSalesStaging;
DROP TABLE IF EXISTS lab.StoreSalesStaging;
DROP SEQUENCE IF EXISTS lab.DocumentNumberSeq;
DROP SEQUENCE IF EXISTS lab.FiscalInvoiceSeq;
DROP SEQUENCE IF EXISTS lab.CycleSeq;
DROP SEQUENCE IF EXISTS lab.BulkEtlSeq;
DROP SEQUENCE IF EXISTS lab.GlobalSalesSeq;
GO


-- =================================================================================
-- PARTE 1: UNIQUE CONSTRAINT VS UNIQUE INDEX FILTRADO (O DESAFIO DOS NULLS)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - UNIQUE CONSTRAINT (Restrição de Unicidade): Garante que todos os valores de uma coluna sejam exclusivos.
--     No SQL Server, de acordo com o padrão ANSI, o valor NULL é tratado como um valor ordinário. Por isso,
--     uma UNIQUE constraint permite a inserção de apenas um único registro com valor nulo (NULL). 
--     Qualquer tentativa subsequente de inserir NULL falhará com erro de violação de chave.
--   - UNIQUE INDEX FILTRADO: Um índice de unicidade não-clusterizado que inclui um predicado de filtro
--     (ex: `WHERE PersonalEmail IS NOT NULL`). Permite ignorar as linhas com valores nulos na verificação.
--     Com isso, podemos ter múltiplos registros nulos ao mesmo tempo, mantendo a regra de unicidade estrita
--     apenas nos campos que forem de fato preenchidos.

-- 0. Garantir limpeza da tabela antes de criar (Idempotência)
DROP TABLE IF EXISTS lab.CustomersUnique;

CREATE TABLE lab.CustomersUnique (
    CustomerID INT IDENTITY PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    -- Colunas para testes de unicidade
    GovernmentID VARCHAR(20) NULL,
    PersonalEmail VARCHAR(100) NULL
);
GO

-- 1. Aplicando uma UNIQUE CONSTRAINT clássica em GovernmentID
ALTER TABLE lab.CustomersUnique
ADD CONSTRAINT UQ_CustomersUnique_GovernmentID UNIQUE (GovernmentID);
GO

-- Teste: Inserir dois clientes com IDs diferentes (Sucesso)
INSERT INTO lab.CustomersUnique (CustomerName, GovernmentID) VALUES ('Alice', '12345'), ('Bob', '67890');

-- Teste: Inserir o primeiro cliente com NULL (Sucesso)
INSERT INTO lab.CustomersUnique (CustomerName, GovernmentID) VALUES ('Charlie', NULL);

-- Teste: Inserir o SEGUNDO cliente com NULL (Falha devido à Unique Constraint!)
BEGIN TRY
    INSERT INTO lab.CustomersUnique (CustomerName, GovernmentID) VALUES ('David', NULL);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO UNIQUE CONSTRAINT: ' + ERROR_MESSAGE();
    -- Mensagem: "Violation of UNIQUE KEY constraint..."
END CATCH;
GO

-- 2. Solução para aceitar Nulos Múltiplos: UNIQUE INDEX FILTRADO
-- Primeiro removemos a constraint antiga
ALTER TABLE lab.CustomersUnique DROP CONSTRAINT UQ_CustomersUnique_GovernmentID;
GO

-- Criamos um Unique Index que ignora valores nulos (WHERE Column IS NOT NULL)
CREATE UNIQUE NONCLUSTERED INDEX UIX_CustomersUnique_PersonalEmail
ON lab.CustomersUnique(PersonalEmail)
WHERE PersonalEmail IS NOT NULL;
GO

-- Teste: Inserir vários clientes com e-mail NULO (Sucesso!)
INSERT INTO lab.CustomersUnique (CustomerName, PersonalEmail) VALUES ('Daniel', NULL);
INSERT INTO lab.CustomersUnique (CustomerName, PersonalEmail) VALUES ('Eva', NULL);

-- Teste: Inserir clientes com e-mails repetidos (Falha de Unicidade esperada)
INSERT INTO lab.CustomersUnique (CustomerName, PersonalEmail) VALUES ('Frank', 'frank@email.com');
BEGIN TRY
    INSERT INTO lab.CustomersUnique (CustomerName, PersonalEmail) VALUES ('Grace', 'frank@email.com');
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO UNIQUE INDEX FILTRADO: ' + ERROR_MESSAGE();
    -- Mensagem: "Cannot insert duplicate key row..."
END CATCH;
GO


-- =================================================================================
-- PARTE 2: CHECK CONSTRAINTS E A FLAG TRUSTED (CONFIABILIDADE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CHECK CONSTRAINT: Restrição lógica aplicada a colunas para garantir que todos os dados inseridos ou
--     atualizados atendam a uma regra lógica/condição booleana (ex: `Price > 0`).
--   - ESTADO NOT FOR REPLICATION / NOCHECK: Permite desabilitar temporariamente a validação de uma restrição 
--     (ex: durante cargas massivas de dados ou replicação). Isso marca a constraint como `is_not_trusted = 1`.
--   - TRUSTED VS UNTRUSTED CONSTRAINTS: Uma constraint confiável (`is_not_trusted = 0`) garante matematicamente
--     ao otimizador que nenhuma linha viola a regra. O otimizador usa essa garantia para simplificar planos
--     (ex: se a query filtra `WHERE Price = -10` e a constraint garante `Price > 0`, a engine pula a leitura da tabela).
--     Se for `untrusted` (não confiável), o SQL Server ignora essa otimização e lê a tabela mesmo assim.
--   - REATIVAÇÃO COM WITH CHECK: Para tornar uma constraint confiável novamente, reative-a usando a instrução
--     `WITH CHECK CHECK CONSTRAINT`. Apenas usar `CHECK CONSTRAINT` reativa a regra para novas linhas, mas
--     mantém o estado `is_not_trusted` (pois os dados antigos não foram verificados).

CREATE TABLE lab.ProductsCheck (
    ProductID INT IDENTITY PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Price DECIMAL(18,2) NULL,
    CONSTRAINT CK_ProductsCheck_Price CHECK (Price > 0)
);
GO

-- 2. Desabilitar a constraint para uma carga em massa rápida (Bulk Load)
ALTER TABLE lab.ProductsCheck NOCHECK CONSTRAINT CK_ProductsCheck_Price;
GO

-- Inserir dados inconsistentes enquanto está desabilitada (Price negativo)
INSERT INTO lab.ProductsCheck (ProductName, Price) VALUES ('Produto Grátis/Brinde', -10.00);
GO

-- 3. Reabilitar SEM validar o histórico (NOCHECK)
-- O SQL Server aceitará a reativação, mas a marcará como NÃO CONFIÁVEL (is_not_trusted = 1)
ALTER TABLE lab.ProductsCheck WITH NOCHECK CHECK CONSTRAINT CK_ProductsCheck_Price;
GO

-- Verificar se a constraint está marcada como confiável
-- Se is_not_trusted = 1, o otimizador não confia nos dados para otimizar planos de execução.
SELECT name, is_not_trusted, is_disabled 
FROM sys.check_constraints 
WHERE name = 'CK_ProductsCheck_Price';
GO

-- 4. Como reabilitar CORRETAMENTE para torná-la confiável novamente:
-- Primeiro ajustamos o dado inconsistente
UPDATE lab.ProductsCheck SET Price = 1.00 WHERE Price < 0;

-- Agora aplicamos a validação de todos os dados históricos com WITH CHECK
ALTER TABLE lab.ProductsCheck WITH CHECK CHECK CONSTRAINT CK_ProductsCheck_Price;
GO

-- Verifique a flag novamente (Deve estar is_not_trusted = 0)
SELECT name, is_not_trusted, is_disabled 
FROM sys.check_constraints 
WHERE name = 'CK_ProductsCheck_Price';
GO


-- =================================================================================
-- PARTE 3: FOREIGN KEY E AÇÕES REFERENCIAIS (CASCADE E SET NULL)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - FOREIGN KEY (Chave Estrangeira): Constraint que estabelece um link lógico de integridade
--     entre registros de duas tabelas, exigindo que o valor da coluna filha exista previamente na coluna
--     chave primária da tabela pai.
--   - CASCADE (Em Cascata): Ação referencial que propaga a exclusão ou atualização de um registro na tabela pai
--     automaticamente para todas as linhas filhas vinculadas.
--   - SET NULL / SET DEFAULT: Ações referenciais que definem a coluna de chave estrangeira nas tabelas filhas
--     como `NULL` (ou para o valor `DEFAULT` configurado) caso a linha correspondente na tabela pai seja deletada/alterada.
--   - NO ACTION (Padrão): Rejeita a exclusão ou alteração na tabela pai se houverem registros filhos vinculados.
--   - PREVENÇÃO DE CICLOS E CAMINHOS MÚLTIPLOS: O SQL Server proíbe a criação de constraints com `ON DELETE/UPDATE CASCADE` 
--     se o caminho de exclusões puder gerar referências cíclicas (loops circulares) ou se houver caminhos de propagação
--     múltiplos redundantes para a mesma tabela. Isso visa evitar loops de exclusão infinitos e comportamentos imprevisíveis.

-- 1. Criar Tabela Pai (Invoices/Faturas)
DROP TABLE IF EXISTS lab.InvoiceItems;
DROP TABLE IF EXISTS lab.Invoices;

CREATE TABLE lab.Invoices (
    InvoiceID INT NOT NULL PRIMARY KEY,
    InvoiceDate DATE NOT NULL
);

-- 2. Criar Tabela Filho (InvoiceItems) com regras ON DELETE
CREATE TABLE lab.InvoiceItems (
    ItemID INT IDENTITY PRIMARY KEY,
    InvoiceID INT NOT NULL,
    Description NVARCHAR(100) NOT NULL,
    -- CASCADE: Apaga as linhas filhas se a linha pai for excluída
    CONSTRAINT FK_InvoiceItems_Invoices 
        FOREIGN KEY (InvoiceID) REFERENCES lab.Invoices(InvoiceID)
        ON DELETE CASCADE
);
GO

-- 3. Inserir dados de teste
INSERT INTO lab.Invoices (InvoiceID, InvoiceDate) VALUES (1001, GETDATE());
INSERT INTO lab.InvoiceItems (InvoiceID, Description) VALUES (1001, 'Item A'), (1001, 'Item B');
GO

-- Verificar registros antes da exclusão
SELECT * FROM lab.Invoices;
SELECT * FROM lab.InvoiceItems;

-- 4. Excluir a Fatura Pai (Deleta automaticamente os Itens Filho devido ao CASCADE)
DELETE FROM lab.Invoices WHERE InvoiceID = 1001;
GO

-- Verifique que os itens filhos foram excluídos automaticamente!
SELECT * FROM lab.InvoiceItems;
GO


-- =================================================================================
-- PARTE 4: SEQUENCES VS IDENTITY (ESCONDO CACHE E MULTI-TABELA)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - IDENTITY (Identidade): Propriedade de coluna geradora de números sequenciais locais vinculada
--     exclusivamente a uma tabela específica (ex: `ID INT IDENTITY(1,1)`).
--   - SEQUENCE: Um objeto de gerador numérico autônomo criado a nível de esquema. Pode ser referenciado
--     por múltiplas tabelas simultaneamente (ex: usando `NEXT VALUE FOR schema.SequenceName`) e permite
--     obter o próximo número do fluxo sequencial antes de executar uma inserção na tabela (via `NEXT VALUE FOR`).
--   - CACHE EM SEQUENCIAIS: Recurso de performance que pré-aloca faixas de números na memória RAM (ex: `CACHE 20`)
--     para evitar I/O constante em disco a cada insert. 
--   - COMPORTAMENTO DE GAPS (Lacunas): Se o serviço do SQL Server sofrer um reinício forçado, queda de energia
--     ou crash, todos os números que estavam pré-alocados no CACHE mas ainda não foram consolidados nas tabelas
--     serão perdidos definitivamente, criando "buracos" (gaps) na sequência. `NO CACHE` reduz apenas as
--     lacunas causadas por valores ainda em cache; não garante contiguidade absoluta em rollbacks ou valores não usados.

-- 1. Criar uma Sequence com Cache
DROP SEQUENCE IF EXISTS lab.DocumentNumberSeq;
CREATE SEQUENCE lab.DocumentNumberSeq
    AS INT
    START WITH 1000
    INCREMENT BY 1
    CACHE 10; -- Pré-aloca 10 números em memória RAM
GO

-- 2. Usando a Sequence em tabelas diferentes
-- IMPORTANTE: Para recriar lab.Invoices, é necessário remover primeiro a tabela filha lab.InvoiceItems
-- criada na Parte 3, que possui uma Foreign Key apontando para lab.Invoices.
DROP TABLE IF EXISTS lab.InvoiceItems;
DROP TABLE IF EXISTS lab.Invoices;
DROP TABLE IF EXISTS lab.Orders;

CREATE TABLE lab.Invoices (
    InvoiceID INT NOT NULL DEFAULT (NEXT VALUE FOR lab.DocumentNumberSeq) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL
);

CREATE TABLE lab.Orders (
    OrderID INT NOT NULL DEFAULT (NEXT VALUE FOR lab.DocumentNumberSeq) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL
);
GO

-- 3. Inserindo registros e gerando numeração na mesma sequência!
INSERT INTO lab.Invoices (CustomerName) VALUES ('Cliente A'); -- Pega o valor 1000
INSERT INTO lab.Orders (CustomerName) VALUES ('Cliente B');   -- Pega o valor 1001
INSERT INTO lab.Invoices (CustomerName) VALUES ('Cliente C'); -- Pega o valor 1002

-- Verifique que a numeração é integrada entre as tabelas
SELECT 'Faturas' AS Origem, InvoiceID AS ID, CustomerName FROM lab.Invoices
UNION ALL
SELECT 'Pedidos' AS Origem, OrderID AS ID, CustomerName FROM lab.Orders;
GO

-- 4. Reiniciando ou alterando o valor atual da Sequence
ALTER SEQUENCE lab.DocumentNumberSeq RESTART WITH 2000;
GO

-- Insere novo registro após o restart
INSERT INTO lab.Invoices (CustomerName) VALUES ('Cliente D'); -- Pega o valor 2000
SELECT * FROM lab.Invoices;
GO


-- =================================================================================
-- PARTE 5: CENÁRIOS PRÁTICOS ADICIONAIS (PK NONCLUSTERED, SET DEFAULT E NO CACHE)
-- =================================================================================

-- 1. Tabela de Auditoria utilizando PRIMARY KEY NONCLUSTERED
-- O Clustered Index é colocado em LogDate para otimizar pesquisas por intervalo de datas
DROP TABLE IF EXISTS lab.SystemAuditLogs;
CREATE TABLE lab.SystemAuditLogs (
    LogID UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
    LogDate DATETIME2 DEFAULT SYSUTCDATETIME() NOT NULL,
    LogMessage NVARCHAR(255) NOT NULL,
    -- PK Não-Clusterizada
    CONSTRAINT PK_SystemAuditLogs PRIMARY KEY NONCLUSTERED (LogID)
);

-- Index Clusterizado baseado na Data do Log (Para varredura rápida por período)
CREATE CLUSTERED INDEX CIX_SystemAuditLogs_LogDate ON lab.SystemAuditLogs(LogDate);
GO

-- Teste de inserção no log
INSERT INTO lab.SystemAuditLogs (LogMessage) VALUES ('Usuário admin efetuou login'), ('Sistema de backup iniciado');
SELECT * FROM lab.SystemAuditLogs ORDER BY LogDate;
GO

-- 2. Sequence com a opção NO CACHE (reduz lacunas por valores em cache após reinícios)
DROP SEQUENCE IF EXISTS lab.FiscalInvoiceSeq;
CREATE SEQUENCE lab.FiscalInvoiceSeq
    AS INT
    START WITH 1
    INCREMENT BY 1
    NO CACHE; -- Persiste o valor atual a cada solicitação; há custo adicional de I/O
GO

SELECT NEXT VALUE FOR lab.FiscalInvoiceSeq AS ProximaNotaFiscal;
SELECT NEXT VALUE FOR lab.FiscalInvoiceSeq AS ProximaNotaFiscal;
GO

-- [PONTO DE ATENÇÃO DP-800] Mesmo com NO CACHE, NEXT VALUE FOR é consumido fora da transação.
-- O rollback abaixo não devolve o número 3; a próxima chamada retorna 4.
BEGIN TRANSACTION;
DECLARE @NumeroReservado INT = NEXT VALUE FOR lab.FiscalInvoiceSeq;
SELECT @NumeroReservado AS NumeroConsumidoAntesDoRollback;
ROLLBACK TRANSACTION;

SELECT NEXT VALUE FOR lab.FiscalInvoiceSeq AS ProximoNumeroAposRollback;
GO


-- =================================================================================
-- PARTE 6: DEMONSTRAÇÃO CONSOLIDADA DOS 5 TIPOS DE CONSTRAINTS E SEQUENCE VS IDENTITY
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PRIMARY KEY (PK): Identifica unicamente a linha; obriga NOT NULL; cria Clustered Index por padrão.
--   - FOREIGN KEY (FK): Integridade referencial com tabela pai; aceita NULL; desabilitável com NOCHECK.
--   - UNIQUE (UK): Garante unicidade secundária; aceita apenas 1 NULL por padrão (ou múltiplos via índice filtrado).
--   - DEFAULT (DF): Fornece valor padrão automático se a coluna for omitida no INSERT.
--   - CHECK (CHK): Valida regra lógica booleana sobre a linha (aceita se for TRUE ou UNKNOWN/NULL).

-- 1. Criar Tabela Consolidada com as 5 Constraints (PK, FK, UK, DF, CHECK)
DROP TABLE IF EXISTS lab.OrderDetailsConsolidated;
DROP TABLE IF EXISTS lab.CustomersConsolidated;

CREATE TABLE lab.CustomersConsolidated (
    CustomerID INT PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL
);

CREATE TABLE lab.OrderDetailsConsolidated (
    DetailID    INT IDENTITY(1,1),      -- 1. IDENTITY local
    CustomerID  INT         NOT NULL,   -- 2. FK apontando para a tabela de Clientes
    TaxNumber   VARCHAR(20) NULL,       -- 3. UNIQUE (Número Fiscal Secundário)
    OrderStatus VARCHAR(20) NULL CONSTRAINT DF_OrderDetails_Status DEFAULT ('Pendente'), -- 4. DEFAULT
    OrderQty    INT NOT NULL,           -- 5. CHECK
    UnitPrice   DECIMAL(10,2) NOT NULL,
    
    -- Definições explícitas das restrições
    CONSTRAINT PK_OrderDetailsConsolidated PRIMARY KEY CLUSTERED (DetailID),
    CONSTRAINT FK_OrderDetails_Customers FOREIGN KEY (CustomerID) REFERENCES lab.CustomersConsolidated(CustomerID),
    CONSTRAINT UQ_OrderDetails_TaxNumber UNIQUE (TaxNumber),
    CONSTRAINT CK_OrderDetails_QtyPositive CHECK (OrderQty > 0 AND UnitPrice >= 0.00)
);
GO

-- 2. Testar Inserção Válida (Todas as 5 constraints satisfeitas)
INSERT INTO lab.CustomersConsolidated (CustomerID, CustomerName) VALUES (1, 'Cliente Teste Matriz');

INSERT INTO lab.OrderDetailsConsolidated (CustomerID, TaxNumber, OrderQty, UnitPrice)
VALUES (1, 'TAX-998877', 5, 100.00);

-- Verifique que o OrderStatus recebeu o valor 'Pendente' via DEFAULT constraint
SELECT DetailID, CustomerID, TaxNumber, OrderStatus, OrderQty, UnitPrice 
FROM lab.OrderDetailsConsolidated;
GO

-- 3. Teste de Violações de Cada Constraint (Pegadinhas DP-800 com BEGIN TRY...CATCH)

-- 3.a Teste de Violação de FOREIGN KEY (CustomerID 999 não existe na tabela pai)
BEGIN TRY
    INSERT INTO lab.OrderDetailsConsolidated (CustomerID, TaxNumber, OrderQty, UnitPrice)
    VALUES (999, 'TAX-000000', 1, 50.00);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO 1 (FK Violation): ' + ERROR_MESSAGE();
END CATCH;

-- 3.b Teste de Violação de UNIQUE CONSTRAINT (TaxNumber 'TAX-998877' já cadastrado)
BEGIN TRY
    INSERT INTO lab.OrderDetailsConsolidated (CustomerID, TaxNumber, OrderQty, UnitPrice)
    VALUES (1, 'TAX-998877', 2, 30.00);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO 2 (UK Violation): ' + ERROR_MESSAGE();
END CATCH;

-- 3.c Teste de Violação de CHECK CONSTRAINT (OrderQty = -5 viola a regra OrderQty > 0)
BEGIN TRY
    INSERT INTO lab.OrderDetailsConsolidated (CustomerID, TaxNumber, OrderQty, UnitPrice)
    VALUES (1, 'TAX-111111', -5, 10.00);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO 3 (CHECK Violation): ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PARTE 7: RECURSOS AVANÇADOS DA TEORIA (PK COMPOSTA, CHECK MULTI-COLUNAS, CYCLE E IDENTITY METADATA)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PK COMPOSTA: Chave primária formada por 2 ou mais colunas (ex: Tabela de Associação N:M).
--   - FK AUTORREFERENCIADA: Tabela que aponta para sua própria chave primária (ex: Árvore Hierárquica de Funcionários/Gerentes).
--   - FK ON DELETE SET DEFAULT: Quando o pai é excluído, a FK do filho assume o valor DEFAULT (ex: Cliente Anônimo ID 0).
--   - CHECK MULTI-COLUNAS: Restrição que compara duas ou mais colunas da MESMA linha (ex: `EndDate >= StartDate`).
--   - SEQUENCE CYCLE: Quando o valor limite MAXVALUE é atingido, a sequência reinicia automaticamente no MINVALUE.
--   - FUNÇÕES E METADADOS IDENTITY: 
--       * `SCOPE_IDENTITY()`: Retorna o último ID gerado no escopo e sessão atual (Seguro contra Triggers).
--       * `@@IDENTITY`: Retorna o último ID gerado na sessão inteira (Pode retornar o ID gerado dentro de uma Trigger em outra tabela!).
--       * `IDENT_CURRENT('Tabela')`: Retorna o último ID gerado em qualquer sessão para uma tabela específica.
--       * `DBCC CHECKIDENT`: Redefine o valor atual do ponteiro do IDENTITY.

-- 1. Primary Key Composta (Tabela de Itens de Pedido N:M)
DROP TABLE IF EXISTS lab.OrderItemsComposite;
CREATE TABLE lab.OrderItemsComposite (
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    CONSTRAINT PK_OrderItemsComposite PRIMARY KEY (OrderID, ProductID)
);
GO

INSERT INTO lab.OrderItemsComposite (OrderID, ProductID, Quantity) VALUES (101, 1, 2), (101, 2, 5);
-- Tentar inserir item duplicado no mesmo pedido (Falha na PK Composta)
BEGIN TRY
    INSERT INTO lab.OrderItemsComposite (OrderID, ProductID, Quantity) VALUES (101, 1, 10);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO PK COMPOSTA: ' + ERROR_MESSAGE();
END CATCH;
GO

-- 2. Foreign Key Autorreferenciada (Hierarquia de Funcionários)
DROP TABLE IF EXISTS lab.EmployeesHierarchy;
CREATE TABLE lab.EmployeesHierarchy (
    EmployeeID INT PRIMARY KEY,
    EmployeeName NVARCHAR(100) NOT NULL,
    ManagerID INT NULL CONSTRAINT FK_Employees_Manager REFERENCES lab.EmployeesHierarchy(EmployeeID)
);
GO

INSERT INTO lab.EmployeesHierarchy (EmployeeID, EmployeeName, ManagerID) VALUES (1, 'CEO Carlos', NULL);
INSERT INTO lab.EmployeesHierarchy (EmployeeID, EmployeeName, ManagerID) VALUES (2, 'Diretora Ana', 1); -- Ana responde para Carlos (1)
INSERT INTO lab.EmployeesHierarchy (EmployeeID, EmployeeName, ManagerID) VALUES (3, 'Dev Bruno', 2);    -- Bruno responde para Ana (2)

SELECT e.EmployeeName AS Funcionario, ISNULL(m.EmployeeName, 'Sem Gerente') AS Gerente
FROM lab.EmployeesHierarchy e
LEFT JOIN lab.EmployeesHierarchy m ON e.ManagerID = m.EmployeeID;
GO

-- 3. Check Constraint Multi-Colunas (Comparando 2 campos da mesma linha)
DROP TABLE IF EXISTS lab.Projects;
CREATE TABLE lab.Projects (
    ProjectID INT IDENTITY PRIMARY KEY,
    ProjectName NVARCHAR(100) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    CONSTRAINT CK_Projects_Dates CHECK (EndDate >= StartDate)
);
GO

INSERT INTO lab.Projects (ProjectName, StartDate, EndDate) VALUES ('Projeto Alfa', '2026-01-01', '2026-06-30');

-- Teste de violação: Data final anterior à data inicial (Falha no CHECK multi-colunas)
BEGIN TRY
    INSERT INTO lab.Projects (ProjectName, StartDate, EndDate) VALUES ('Projeto Inválido', '2026-06-01', '2026-01-01');
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO CHECK MULTI-COLUNAS: ' + ERROR_MESSAGE();
END CATCH;
GO

-- 4. Sequence com recurso CYCLE (Gera valores 1, 2, 3, 1, 2, 3...)
DROP SEQUENCE IF EXISTS lab.CycleSeq;
CREATE SEQUENCE lab.CycleSeq
    AS TINYINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 3
    CYCLE; -- Reinicia automaticamente ao atingir 3
GO

SELECT NEXT VALUE FOR lab.CycleSeq AS Val1, NEXT VALUE FOR lab.CycleSeq AS Val2, NEXT VALUE FOR lab.CycleSeq AS Val3;
SELECT NEXT VALUE FOR lab.CycleSeq AS ValCycle1, NEXT VALUE FOR lab.CycleSeq AS ValCycle2; -- Reiniciou no 1 e 2!
GO

-- 5. Funções de Metadados IDENTITY (SCOPE_IDENTITY vs @@IDENTITY vs DBCC CHECKIDENT)
DROP TABLE IF EXISTS lab.IdentityMetadataDemo;
CREATE TABLE lab.IdentityMetadataDemo (
    ID INT IDENTITY(100, 5) PRIMARY KEY,
    ValueText NVARCHAR(50)
);
GO

INSERT INTO lab.IdentityMetadataDemo (ValueText) VALUES ('Inserção 1');

SELECT 
    SCOPE_IDENTITY() AS LastScopeIdentity,   -- 100
    @@IDENTITY AS LastGlobalIdentity,        -- 100
    IDENT_CURRENT('lab.IdentityMetadataDemo') AS IdentCurrentTable; -- 100

-- Redefinindo o ponteiro do IDENTITY com DBCC CHECKIDENT (Reseed para 500)
DBCC CHECKIDENT ('lab.IdentityMetadataDemo', RESEED, 500);

INSERT INTO lab.IdentityMetadataDemo (ValueText) VALUES ('Inserção Pós-Reseed');
SELECT * FROM lab.IdentityMetadataDemo;
GO


-- =================================================================================
-- PARTE 8: ALOCAÇÃO EM LOTE DE SEQUÊNCIAS VIA sp_sequence_get_range (DESEMPENHO ETL)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - sp_sequence_get_range: Procedure armazenada do sistema que reserva um bloco/faixa inteiro de números
--     de uma SEQUENCE em uma única chamada. Isso é ideal para aplicações de ingestão de dados em massa (ETL)
--     que precisam gerar as chaves primárias na memória da aplicação antes de enviar um BULK INSERT concorrente.

DROP SEQUENCE IF EXISTS lab.BulkEtlSeq;
CREATE SEQUENCE lab.BulkEtlSeq
    AS INT
    START WITH 100000
    INCREMENT BY 1;
GO

DECLARE 
    @FirstValue SQL_VARIANT,
    @LastValue SQL_VARIANT,
    @CycleCount INT,
    @SequenceIncrement SQL_VARIANT,
    @MinSeqValue SQL_VARIANT,
    @MaxSeqValue SQL_VARIANT;

-- Reservar um bloco de 1.000 IDs de uma só vez para o processo de ETL
EXEC sys.sp_sequence_get_range
    @sequence_name = N'lab.BulkEtlSeq',
    @range_size = 1000,
    @range_first_value = @FirstValue OUTPUT,
    @range_last_value = @LastValue OUTPUT,
    @range_cycle_count = @CycleCount OUTPUT,
    @sequence_increment = @SequenceIncrement OUTPUT,
    @sequence_min_value = @MinSeqValue OUTPUT,
    @sequence_max_value = @MaxSeqValue OUTPUT;

SELECT 
    @FirstValue AS PrimeirosID_Reservado,
    @LastValue AS UltimoID_Reservado,
    'O processo de ETL agora possui os IDs 100000 até 100999 pré-alocados na memória!' AS StatusAlocacao;
GO


-- =================================================================================
-- PARTE 9: A ARMADILHA DA CHAVE INCREMENTAL VS CHAVE NEGOCIAL (BUSINESS KEY)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - ARMADILHA DA SURROGATE KEY: Uma chave `IDENTITY` ou `SEQUENCE` apenas garante a unicidade do número ID artificial.
--     Ela NÃO impede que duas linhas contenham a mesma entidade real de negócio (ex: dois clientes com o mesmo CPF).
--   - SOLUÇÃO DE ARQUITETURA:
--     1. Manter o IDENTITY como Surrogate PK para performance física de JOINs.
--     2. Criar uma UNIQUE CONSTRAINT na Chave Negocial (Business Key / Natural Key) (ex: `UNIQUE (CPF)`).
--     3. Para cargas em lote (ETL/ELT), usar uma coluna computada com Hash da Linha (`RowHash`) indexada.

-- 1. DEMONSTRAÇÃO DO ERRO: Tabela sem UNIQUE na Chave Negocial (Aceita duplicatas de negócio!)
DROP TABLE IF EXISTS lab.BadCustomers;
CREATE TABLE lab.BadCustomers (
    CustomerID INT IDENTITY PRIMARY KEY, -- O SQL Server garante que CustomerID seja único (1, 2)
    CPF VARCHAR(14) NOT NULL,
    CustomerName NVARCHAR(100) NOT NULL
);
GO

-- Inserindo o MESMO CLIENTE duas vezes (Sucesso no banco, mas DADO CORROMPIDO / DUPLICADO no negócio!)
INSERT INTO lab.BadCustomers (CPF, CustomerName) VALUES ('123.456.789-00', 'João Silva');
INSERT INTO lab.BadCustomers (CPF, CustomerName) VALUES ('123.456.789-00', 'João Silva'); -- Gerou CustomerID = 2 para a mesma pessoa!

SELECT * FROM lab.BadCustomers; -- Duas linhas idênticas com IDs diferentes!
GO

-- 2. SOLUÇÃO CORRETA: Tabela com Surrogate PK + UNIQUE Constraint na Chave Negocial (CPF)
DROP TABLE IF EXISTS lab.GoodCustomers;
CREATE TABLE lab.GoodCustomers (
    CustomerID INT IDENTITY PRIMARY KEY, -- Surrogate Key para JOINs de alta performance
    CPF VARCHAR(14) NOT NULL,            -- Business Key
    CustomerName NVARCHAR(100) NOT NULL,
    -- Impede a duplicação da entidade real de negócio!
    CONSTRAINT UQ_GoodCustomers_CPF UNIQUE (CPF)
);
GO

INSERT INTO lab.GoodCustomers (CPF, CustomerName) VALUES ('123.456.789-00', 'João Silva');

-- Segunda tentativa com o mesmo CPF (Bloqueada com sucesso pela UNIQUE Constraint!)
BEGIN TRY
    INSERT INTO lab.GoodCustomers (CPF, CustomerName) VALUES ('123.456.789-00', 'João Silva');
END TRY
BEGIN CATCH
    PRINT 'BLOQUEIO DE DUPLICIDADE NEGOCIAL: ' + ERROR_MESSAGE();
END CATCH;
GO

-- 3. PADRÃO AVANÇADO DE ETL: Controle de Carga com Hash de Deduplicação (RowHash)
DROP TABLE IF EXISTS lab.EtlDeduplicationStaging;
CREATE TABLE lab.EtlDeduplicationStaging (
    StagingID INT IDENTITY PRIMARY KEY,
    TenantID INT NOT NULL,
    DocumentNumber VARCHAR(20) NOT NULL,
    RawData NVARCHAR(MAX) NOT NULL,
    -- Coluna computada com Hash da combinação única da carga
    RowHash AS HASHBYTES('SHA2_256', CONCAT(TenantID, '|', DocumentNumber)) PERSISTED
);

CREATE UNIQUE NONCLUSTERED INDEX UIX_EtlDeduplication_RowHash 
ON lab.EtlDeduplicationStaging(RowHash);
GO

-- Carga inicial
INSERT INTO lab.EtlDeduplicationStaging (TenantID, DocumentNumber, RawData) 
VALUES (10, 'DOC-998877', N'{"status": "processed"}');

-- Tentativa de re-ingestão do mesmo registro no pipeline ETL (Rejeitada pelo Hash!)
BEGIN TRY
    INSERT INTO lab.EtlDeduplicationStaging (TenantID, DocumentNumber, RawData) 
    VALUES (10, 'DOC-998877', N'{"status": "duplicated"}');
END TRY
BEGIN CATCH
    PRINT 'DUPLICATA DE CARGA ETL REJEITADA PELO HASH: ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PARTE 10: MERGE COM SEQUENCE EM TABELAS MÚLTIPLAS (O PADRÃO CORRETO DE INTEGRATlON)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - O PROBLEMA DA SEQUENCE NO MERGE: Se duas tabelas de origem (ex: `OnlineSales` e `StoreSales`) consomem
--     da mesma SEQUENCE, o ID gerado (ex: 1001 na Online e 1002 na Loja) é puramente arbitrário.
--   - ERRO COMUM: Tentar fazer `MERGE ON Target.SequenceID = Source.SequenceID`. Isso NUNCA dará MATCH,
--     gerando duplicatas da mesma venda ou atualizações no registro errado!
--   - SOLUÇÃO DE ARQUITETURA:
--     1. O `MERGE` DEVE ser feito ON `Target.BusinessKey = Source.BusinessKey` (ex: `CPF + DataVenda` ou `NumNotaFiscal`).
--     2. A SEQUENCE deve ser atribuída SOMENTE no bloco `WHEN NOT MATCHED THEN INSERT (ID = NEXT VALUE FOR Seq, ...)`.

-- 1. Criar a Sequence compartilhada e as tabelas de Origem (E-Commerce e Loja Física)
DROP TABLE IF EXISTS lab.ConsolidatedSalesDW;
DROP TABLE IF EXISTS lab.OnlineSalesStaging;
DROP TABLE IF EXISTS lab.StoreSalesStaging;
DROP SEQUENCE IF EXISTS lab.GlobalSalesSeq;

CREATE SEQUENCE lab.GlobalSalesSeq AS INT START WITH 5000 INCREMENT BY 1 NO CACHE;
GO

CREATE TABLE lab.OnlineSalesStaging (
    TransactionCode VARCHAR(30) PRIMARY KEY, -- Chave Negocial Natural
    CustomerCPF VARCHAR(14) NOT NULL,
    Amount DECIMAL(10,2) NOT NULL
);

CREATE TABLE lab.StoreSalesStaging (
    TransactionCode VARCHAR(30) PRIMARY KEY, -- Chave Negocial Natural
    CustomerCPF VARCHAR(14) NOT NULL,
    Amount DECIMAL(10,2) NOT NULL
);

-- Tabela Consolidada (Data Warehouse / DW)
-- [PONTO DE ATENÇÃO DP-800]: Para usar SEQUENCE no MERGE, ela DEVE ser definida como DEFAULT constraint na tabela!
CREATE TABLE lab.ConsolidatedSalesDW (
    GlobalSalesID INT NOT NULL DEFAULT (NEXT VALUE FOR lab.GlobalSalesSeq) PRIMARY KEY,
    TransactionCode VARCHAR(30) UNIQUE NOT NULL, -- Chave Negocial Natural com UNIQUE Constraint!
    CustomerCPF VARCHAR(14) NOT NULL,
    Amount DECIMAL(10,2) NOT NULL,
    LastUpdated DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

-- Inserir vendas de origens diferentes (Staging de Canais Distintos)
INSERT INTO lab.OnlineSalesStaging VALUES ('TX-101', '111.111.111-11', 150.00), ('TX-102', '222.222.222-22', 300.00);
INSERT INTO lab.StoreSalesStaging VALUES ('TX-102', '222.222.222-22', 350.00), ('TX-103', '333.333.333-33', 500.00); -- TX-102 com novo valor e TX-103 inédita
GO

-- 2. EXECUTAR O MERGE LOTE 1 (Carga do E-Commerce - OnlineSalesStaging)
-- As transações TX-101 e TX-102 são novas -> O DEFAULT dispara o NEXT VALUE FOR da SEQUENCE (IDs 5000 e 5001)
MERGE lab.ConsolidatedSalesDW AS Target
USING lab.OnlineSalesStaging AS Source
ON Target.TransactionCode = Source.TransactionCode
WHEN MATCHED THEN 
    UPDATE SET Target.Amount = Source.Amount, Target.LastUpdated = SYSUTCDATETIME()
WHEN NOT MATCHED THEN 
    INSERT (TransactionCode, CustomerCPF, Amount)
    VALUES (Source.TransactionCode, Source.CustomerCPF, Source.Amount);
GO

-- Verifique a carga inicial no DW (IDs 5000 e 5001 gerados)
SELECT * FROM lab.ConsolidatedSalesDW;
GO

-- 3. EXECUTAR O MERGE LOTE 2 (Carga da Loja Física - StoreSalesStaging)
-- [PONTO DE ATENÇÃO DP-800]: 
-- - TX-102 JÁ EXISTE: Dispara WHEN MATCHED -> Atualiza Amount para 350.00 SEM consumir novo ID da SEQUENCE!
-- - TX-103 É NOVA: Dispara WHEN NOT MATCHED -> Insere com o próximo ID (5002) da SEQUENCE!
MERGE lab.ConsolidatedSalesDW AS Target
USING lab.StoreSalesStaging AS Source
ON Target.TransactionCode = Source.TransactionCode
WHEN MATCHED THEN 
    UPDATE SET Target.Amount = Source.Amount, Target.LastUpdated = SYSUTCDATETIME()
WHEN NOT MATCHED THEN 
    INSERT (TransactionCode, CustomerCPF, Amount)
    VALUES (Source.TransactionCode, Source.CustomerCPF, Source.Amount);
GO

-- Resultado Final: TX-102 foi atualizada para 350.00 preservando o ID 5001 (sem desperdício de IDs),
-- e TX-103 recebeu o novo ID 5002!
SELECT GlobalSalesID, TransactionCode, CustomerCPF, Amount, LastUpdated FROM lab.ConsolidatedSalesDW;
GO
