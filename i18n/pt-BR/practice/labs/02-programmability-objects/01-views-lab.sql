-- =================================================================================
-- DP-800 - LAB PRÁTICO: VIEWS (SIMPLES, INDEXADAS, SCHEMABINDING E CHECK OPTION)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/02-programmability-objects/01-views.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a criação, otimização e regras de integridade em Views no SQL Server:
--   1. Views Atualizáveis (Updatable Views) e a opção WITH CHECK OPTION
--   2. Integridade de Esquema com WITH SCHEMABINDING
--   3. Views Indexadas (Materialized Views) e o hint WITH (NOEXPAND)
--   4. Restrições de Determinismo (bloqueio de GETDATE, NEWID) em Views Indexadas
--   5. Limitações de Views (ORDER BY e OUTER JOIN em indexed views)
--   6. Diagnóstico de problemas comuns, SET options e melhores práticas
--   7. Cenários Práticos de Projeto (Dashboards Otimizados e Camadas de Segurança)
-- =================================================================================

USE AdventureWorks2025;
GO

-- [PONTO DE ATENÇÃO DP-800] Estas sete opções são exigidas para criar, manter e usar
-- índices em views. Uma conexão com valores incompatíveis pode falhar em DML ou ignorar
-- o índice da view no plano de execução.
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- Crie um schema isolado para que o lab não altere objetos do AdventureWorks.
IF SCHEMA_ID(N'lab') IS NULL
    EXEC(N'CREATE SCHEMA lab');
GO
-- Limpeza preventiva caso rode o script mais de uma vez
IF EXISTS (SELECT *
           FROM   sys.views
           WHERE  name = 'vw_OrderSummaryIndexed'
                  AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_OrderSummaryIndexed;

IF EXISTS (SELECT *
           FROM   sys.views
           WHERE  name = 'vw_OrderSummaryIndexed_BadCount'
                  AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_OrderSummaryIndexed_BadCount;

IF EXISTS (SELECT *
           FROM   sys.views
           WHERE  name = 'vw_ActiveCustomers'
                  AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_ActiveCustomers;

IF EXISTS (SELECT *
           FROM   sys.views
           WHERE  name = 'vw_BoundProducts'
                  AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_BoundProducts;

IF EXISTS (SELECT *
           FROM   sys.views
           WHERE  name = 'vw_NonDeterministicView'
                  AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_NonDeterministicView;

IF EXISTS (SELECT *
           FROM   sys.views
           WHERE  name = 'vw_OuterJoinIndexed'
                  AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_OuterJoinIndexed;

IF EXISTS (SELECT *
           FROM   sys.views
           WHERE  name = 'vw_NullableSumIndexed'
                  AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_NullableSumIndexed;

IF EXISTS (SELECT *
           FROM   sys.views
           WHERE  name = 'vw_InvalidOrderBy'
                  AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_InvalidOrderBy;

IF EXISTS (SELECT *
           FROM   sys.views
           WHERE  name = 'vw_DailyCustomerRevenueIndexed'
                  AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_DailyCustomerRevenueIndexed;

IF EXISTS (SELECT *
           FROM   sys.views
           WHERE  name = 'vw_ActiveCustomerRevenueIndexed'
                  AND schema_id = SCHEMA_ID('lab'))
    DROP VIEW lab.vw_ActiveCustomerRevenueIndexed;

DROP TABLE IF EXISTS lab.Orders;

DROP TABLE IF EXISTS lab.NullableOrders;

DROP TABLE IF EXISTS lab.Customers;

DROP TABLE IF EXISTS lab.Products;

-- Tabelas base para testes
CREATE TABLE lab.Customers
(
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    IsActive BIT NOT NULL DEFAULT 1
);

CREATE TABLE lab.Orders
(
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL,
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES lab.Customers(CustomerID)
);

CREATE TABLE lab.Products
(
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL
);
GO


-- =================================================================================
-- PARTE 1: UPDATABLE VIEWS E A CLÁUSULA WITH CHECK OPTION
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - UPDATABLE VIEWS: Views que permitem operações DML (INSERT, UPDATE, DELETE) refletidas na tabela base.
--     Cada comando DML deve modificar colunas de apenas UMA tabela base e não conter agregações,
--     DISTINCT, TOP ou GROUP BY. Uma view com JOIN ainda pode permitir UPDATE de colunas de uma única tabela.
--   - WITH CHECK OPTION: Cláusula que impede que inserções ou atualizações feitas através da view violem
--     o predicado de filtragem (cláusula WHERE) da própria view. Sem ela, um INSERT de uma linha que não atende
--     ao filtro é gravado na tabela base, mas "desaparece" da visão da view (linhas fantasmas).

-- 1. Criar uma View Atualizável com WITH CHECK OPTION
CREATE VIEW lab.vw_ActiveCustomers
AS
    SELECT CustomerID, CustomerName, IsActive
    FROM lab.Customers
    WHERE IsActive = 1
WITH CHECK OPTION; -- Impede DML de clientes inativos por esta view
GO

-- Inserir cliente ativo pela view (Sucesso!)
INSERT INTO lab.vw_ActiveCustomers
    (CustomerName, IsActive)
VALUES
    ('Cliente Ativo 1', 1);

-- DML através da view: UPDATE afeta diretamente a tabela lab.Customers.
UPDATE lab.vw_ActiveCustomers
SET CustomerName = 'Cliente Ativo 1 - Atualizado'
WHERE CustomerName = 'Cliente Ativo 1';

SELECT CustomerID, CustomerName, IsActive
FROM lab.Customers
WHERE CustomerName = 'Cliente Ativo 1 - Atualizado';

-- DML através da view: DELETE também é encaminhado à única tabela base.
INSERT INTO lab.vw_ActiveCustomers
    (CustomerName, IsActive)
VALUES
    ('Cliente para Excluir', 1);

DELETE FROM lab.vw_ActiveCustomers
WHERE CustomerName = 'Cliente para Excluir';

SELECT CustomerID, CustomerName
FROM lab.Customers
WHERE CustomerName = 'Cliente para Excluir';
-- Resultado esperado: nenhuma linha.
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- Teste de Violação: Tentar inserir um cliente INATIVO (IsActive = 0) através da view
-- Com WITH CHECK OPTION, a operação é abortada imediatamente com o erro 550.
BEGIN TRY
    INSERT INTO lab.vw_ActiveCustomers
    (CustomerName, IsActive)
VALUES
    ('Cliente Inativo Tentativa', 0);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO WITH CHECK OPTION: ' + ERROR_MESSAGE();
    -- Erro: "The attempted insert or update failed because the target view specifies WITH CHECK OPTION..."
END CATCH;
GO


-- =================================================================================
-- PARTE 2: SCHEMA BINDING (WITH SCHEMABINDING)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - WITH SCHEMABINDING: Acopla a view às tabelas base. Impede que as tabelas ou colunas referenciadas
--     sejam alteradas ou apagadas via ALTER TABLE / DROP TABLE enquanto a view existir.
--   - REQUISITOS DE SCHEMABINDING:
--     1. Todas as tabelas referenciadas devem usar nomes de duas partes (ex: `lab.Products`, não apenas `Products`).
--     2. O uso de `SELECT *` é expressamente PROIBIDO (todas as colunas devem ser declaradas).

CREATE VIEW lab.vw_BoundProducts
WITH
    SCHEMABINDING
AS
    SELECT ProductID, ProductName, UnitPrice
    FROM lab.Products;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- Teste de Proteção DDL: Tentar remover a coluna ProductName da tabela base Products
-- O SQL Server bloqueia a alteração devido ao acoplamento de esquema (erro 3729).
BEGIN TRY
    ALTER TABLE lab.Products DROP COLUMN ProductName;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO SCHEMABINDING (DDL BLOCK): ' + ERROR_MESSAGE();
    -- Erro: "Cannot DROP COLUMN 'ProductName' because it is being used by object 'vw_BoundProducts'..."
END CATCH;
GO


-- =================================================================================
-- PARTE 3: INDEXED VIEWS (MATERIALIZED VIEWS) E HINT WITH (NOEXPAND)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - INDEXED VIEW: Uma view cujo conjunto de resultados é fisicamente gravado e atualizado em disco.
--     Transforma a view virtual em uma estrutura fisicamente materializada através de um índice.
--   - REQUISITOS OBRIGATÓRIOS PARA INDEXAR UMA VIEW:
--     1. Deve ser criada com a opção `WITH SCHEMABINDING`.
--     2. O PRIMEIRO índice criado na view DEVE ser um `UNIQUE CLUSTERED INDEX`.
--     3. Em consultas com `GROUP BY`, é obrigatório incluir a função de contagem `COUNT_BIG(*)`.
--     4. Proibido o uso de OUTER JOINs, CTEs, subqueries, DISTINCT, TOP ou funções não-determinísticas.
--   - HINT WITH (NOEXPAND): No SQL Server Standard, força a consulta direta da view indexada.
--     No Azure SQL Database e Azure SQL Managed Instance, o otimizador pode usar indexed views automaticamente;
--     o hint continua útil quando se quer demonstrar ou exigir acesso direto ao índice materializado.

-- [PONTO DE ATENÇÃO DP-800] ERRO ESPERADO: COUNT(*) não pode ser usado em uma
-- view indexada com GROUP BY. Criamos a versão incorreta apenas para observar a falha.
CREATE VIEW lab.vw_OrderSummaryIndexed_BadCount
WITH
    SCHEMABINDING
AS
    SELECT
        CustomerID,
        COUNT(*) AS TotalOrders,
        SUM(TotalAmount) AS TotalSpent
    FROM lab.Orders
    GROUP BY CustomerID;
GO

BEGIN TRY
    CREATE UNIQUE CLUSTERED INDEX CIX_vw_OrderSummaryIndexed_BadCount
    ON lab.vw_OrderSummaryIndexed_BadCount(CustomerID);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO COUNT_BIG: ' + ERROR_MESSAGE();
    -- A mensagem informa que COUNT_BIG deve substituir COUNT em uma indexed view agrupada.
END CATCH;
GO

DROP VIEW lab.vw_OrderSummaryIndexed_BadCount;
GO

-- 1. Criar a View correta com Schemabinding e COUNT_BIG(*)
CREATE VIEW lab.vw_OrderSummaryIndexed
WITH
    SCHEMABINDING
AS
    SELECT
        CustomerID,
        COUNT_BIG(*) AS TotalOrders,
        SUM(TotalAmount) AS TotalSpent
    FROM lab.Orders
    GROUP BY CustomerID;
GO

-- Popular dados para materializar
INSERT INTO lab.Customers
    (CustomerName, IsActive)
VALUES
    ('Cliente A', 1),
    ('Cliente B', 1);
INSERT INTO lab.Orders
    (CustomerID, OrderDate, TotalAmount)
VALUES
    (1, '2025-01-01', 500.00),
    (1, '2025-01-02', 300.00);
GO

-- 2. Materializar a View criando o UNIQUE CLUSTERED INDEX (Requisito obrigatório)
CREATE UNIQUE CLUSTERED INDEX CIX_vw_OrderSummaryIndexed
ON lab.vw_OrderSummaryIndexed(CustomerID);
GO

-- Confirme que o índice clustered único materializou o resultado da view.
SELECT name, type_desc, is_unique
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'lab.vw_OrderSummaryIndexed');
GO

-- [PONTO DE ATENÇÃO DP-800] A view indexada não fica desatualizada após DML:
-- o SQL Server mantém seu índice durante a alteração da tabela base.
INSERT INTO lab.Orders
    (CustomerID, OrderDate, TotalAmount)
VALUES
    (1, '2025-01-03', 50.00);
GO

SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_OrderSummaryIndexed
WHERE CustomerID = 1;
-- Resultado esperado: TotalOrders = 3 e TotalSpent = 850.00.
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 3. Consulta com o hint WITH (NOEXPAND). Habilite o Plano de Execução Atual (Ctrl + M)
-- e compare esta consulta com a consulta idêntica sem o hint logo abaixo.
-- No SQL Server Standard, NOEXPAND é necessário para consultar diretamente o índice da view.
-- No Azure SQL Database e Azure SQL Managed Instance, o otimizador pode usar a view automaticamente.
SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_OrderSummaryIndexed WITH (NOEXPAND)
WHERE CustomerID = 1;
GO

SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_OrderSummaryIndexed
WHERE CustomerID = 1;
GO


-- =================================================================================
-- PARTE 4: LIMITAÇÕES DE VIEWS E INDEXED VIEWS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - ORDER BY não define a ordenação de uma view; a consulta externa deve conter ORDER BY.
--   - Uma indexed view não pode conter OUTER JOIN, CTE, subquery, DISTINCT, TOP, APPLY ou self-join.
--   - Views regulares podem ter JOINs, mas INSERT e DELETE não são permitidos quando há mais de uma tabela base.

-- [PONTO DE ATENÇÃO DP-800] ORDER BY sem TOP em uma definição de view regular falha.
-- Usamos SQL dinâmico porque CREATE VIEW precisa ser a primeira instrução do batch.
BEGIN TRY
    EXEC(N'
        CREATE VIEW lab.vw_InvalidOrderBy
        AS
        SELECT CustomerID, CustomerName
        FROM lab.Customers
        ORDER BY CustomerName;');
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO ORDER BY EM VIEW: ' + ERROR_MESSAGE();
END CATCH;
GO

-- OUTER JOIN pode existir em uma view regular, mas impede a criação do índice na view.
CREATE VIEW lab.vw_OuterJoinIndexed
WITH
    SCHEMABINDING
AS
    SELECT
        c.CustomerID,
        c.CustomerName,
        o.OrderID
    FROM lab.Customers AS c
        LEFT JOIN lab.Orders AS o
        ON o.CustomerID = c.CustomerID;
GO

BEGIN TRY
    CREATE UNIQUE CLUSTERED INDEX CIX_vw_OuterJoinIndexed
    ON lab.vw_OuterJoinIndexed(CustomerID, OrderID);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO OUTER JOIN EM INDEXED VIEW: ' + ERROR_MESSAGE();
END CATCH;
GO

DROP VIEW lab.vw_OuterJoinIndexed;
GO


-- =================================================================================
-- PARTE 5: RESTRIÇÕES DE DETERMINISMO EM VIEWS INDEXADAS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DETERMINISMO: Funções determinísticas sempre retornam o mesmo valor para os mesmos parâmetros (ex: `ROUND`, `DATEADD`).
--   - NÃO-DETERMINISMO: Funções como `GETDATE()`, `NEWID()`, `RAND()` variam a cada execução.
--   - O SQL Server proíbe a criação de índices em views que contenham funções não-determinísticas.

CREATE VIEW lab.vw_NonDeterministicView
WITH
    SCHEMABINDING
AS
    SELECT CustomerID, CustomerName, GETDATE() AS QueryDate
    FROM lab.Customers;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- Tentativa de indexar view com GETDATE() -> Falha na criação do índice (Erro 2601/1949)
BEGIN TRY
    CREATE UNIQUE CLUSTERED INDEX CIX_vw_NonDeterministicView
    ON lab.vw_NonDeterministicView(CustomerID);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO NÃO-DETERMINISMO (GETDATE): ' + ERROR_MESSAGE();
    -- Erro: "Cannot create index on view... because it uses non-deterministic function 'GETDATE'..."
END CATCH;
GO


-- =================================================================================
-- PARTE 6: SET OPTIONS, PROBLEMAS COMUNS E MELHORES PRÁTICAS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - As seis opções ANSI/aritméticas devem estar ON e NUMERIC_ROUNDABORT deve estar OFF.
--   - Um SUM de expressão anulável não pode ser usado na definição de uma indexed view.
--   - Use os catálogos sys.views e sys.indexes para confirmar schema binding e materialização.

-- 1. Verificar os SET options efetivos da sessão antes de criar/manter indexed views.
SELECT
    SESSIONPROPERTY(N'ANSI_NULLS') AS ANSI_NULLS,
    SESSIONPROPERTY(N'ANSI_PADDING') AS ANSI_PADDING,
    SESSIONPROPERTY(N'ANSI_WARNINGS') AS ANSI_WARNINGS,
    SESSIONPROPERTY(N'ARITHABORT') AS ARITHABORT,
    SESSIONPROPERTY(N'CONCAT_NULL_YIELDS_NULL') AS CONCAT_NULL_YIELDS_NULL,
    SESSIONPROPERTY(N'QUOTED_IDENTIFIER') AS QUOTED_IDENTIFIER,
    SESSIONPROPERTY(N'NUMERIC_ROUNDABORT') AS NUMERIC_ROUNDABORT;
-- Resultado esperado: os seis primeiros valores são 1; NUMERIC_ROUNDABORT é 0.
GO

-- [PONTO DE ATENÇÃO DP-800] Mudar uma opção obrigatória bloqueia DML na tabela participante.
SET NUMERIC_ROUNDABORT ON;
GO

BEGIN TRY
    INSERT INTO lab.Orders
    (CustomerID, OrderDate, TotalAmount)
VALUES
    (1, '2025-01-04', 1.00);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO SET OPTION: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Restaure a opção imediatamente para que os próximos comandos e reexecuções funcionem.
SET NUMERIC_ROUNDABORT OFF;
GO

-- 2. SUM sobre uma coluna anulável impede a criação do índice na view.
CREATE TABLE lab.NullableOrders
(
    NullableOrderID INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_NullableOrders PRIMARY KEY,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2) NULL
);
GO

INSERT INTO lab.NullableOrders
    (CustomerID, TotalAmount)
VALUES
    (1, 10.00),
    (1, NULL);
GO

CREATE VIEW lab.vw_NullableSumIndexed
WITH
    SCHEMABINDING
AS
    SELECT
        CustomerID,
        COUNT_BIG(*) AS TotalOrders,
        SUM(TotalAmount) AS TotalSpent
    FROM lab.NullableOrders
    GROUP BY CustomerID;
GO

BEGIN TRY
    CREATE UNIQUE CLUSTERED INDEX CIX_vw_NullableSumIndexed
    ON lab.vw_NullableSumIndexed(CustomerID);
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO SUM ANULÁVEL: ' + ERROR_MESSAGE();
    -- Correção, quando NULL representar zero: SUM(ISNULL(TotalAmount, 0)).
END CATCH;
GO

DROP VIEW lab.vw_NullableSumIndexed;
DROP TABLE lab.NullableOrders;
GO

-- 3. Diagnóstico: confirme a melhor prática de schema binding e o índice materializado.
SELECT
    s.name AS SchemaName,
    v.name AS ViewName,
    OBJECTPROPERTYEX(v.object_id, N'IsSchemaBound') AS IsSchemaBound,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    i.is_unique AS IsUnique
FROM sys.views AS v
    JOIN sys.schemas AS s
    ON s.schema_id = v.schema_id
    LEFT JOIN sys.indexes AS i
    ON i.object_id = v.object_id
        AND i.index_id > 0
WHERE v.object_id IN
(
    OBJECT_ID(N'lab.vw_BoundProducts'),
    OBJECT_ID(N'lab.vw_OrderSummaryIndexed')
)
ORDER BY v.name, i.index_id;
GO


-- =================================================================================
-- PARTE 7: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

-- Uma indexed view faz diferença quando a MESMA agregação/join é lida muitas vezes,
-- as tabelas base são grandes e o custo adicional em cada INSERT/UPDATE/DELETE é aceitável.
-- Ela não "zera" o tempo de consulta: troca parte do processamento de leitura por espaço em
-- disco e trabalho de manutenção síncrona no DML das tabelas base.

-- CENÁRIO 1: Ranking em dashboard executivo de e-commerce
-- Problema: a cada atualização do painel, uma consulta varre vendas para calcular o total
-- por cliente. Com milhões de pedidos, o GROUP BY compete por CPU e leituras lógicas.
-- Por que a view ajuda: o total por cliente já está pré-calculado no índice clustered de
-- vw_OrderSummaryIndexed e a consulta lê apenas os grupos materializados.
-- Bom perfil: muitas leituras do dashboard e volume de alterações moderado.

SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_OrderSummaryIndexed WITH (NOEXPAND)
WHERE TotalSpent > 100.00
ORDER BY TotalSpent DESC;
GO

-- Compare no plano de execução com a agregação feita na tabela base. Em uma carga real,
-- espere ver a segunda consulta processar todas as linhas qualificadas de lab.Orders,
-- enquanto a primeira busca o índice da view. O resultado deve ser idêntico.
SET STATISTICS IO, TIME ON;
GO

SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_OrderSummaryIndexed WITH (NOEXPAND)
WHERE TotalSpent > 100.00;

SELECT CustomerID, COUNT_BIG(*) AS TotalOrders, SUM(TotalAmount) AS TotalSpent
FROM lab.Orders
GROUP BY CustomerID
HAVING SUM(TotalAmount) > 100.00;
GO

SET STATISTICS IO, TIME OFF;
GO

-- CENÁRIO 2: Monitoramento intradiário de receita e volume por cliente
-- Problema: uma central de operações atualiza, a cada poucos segundos, cartões como
-- "receita do dia", "quantidade de pedidos" e alertas de queda de vendas.
-- Por que a view ajuda: uma mesma agregação por cliente e data deixa de ser recalculada
-- repetidamente. O índice permite localizar diretamente um dia e um cliente.
-- Bom perfil: painéis de leitura intensa; o número de pedidos por alteração é menor que
-- o número de leituras dos indicadores.
CREATE VIEW lab.vw_DailyCustomerRevenueIndexed
WITH SCHEMABINDING
AS
    SELECT
        o.CustomerID,
        o.OrderDate,
        COUNT_BIG(*) AS TotalOrders,
        SUM(o.TotalAmount) AS DailyRevenue
    FROM lab.Orders AS o
    GROUP BY o.CustomerID, o.OrderDate;
GO

CREATE UNIQUE CLUSTERED INDEX CIX_vw_DailyCustomerRevenueIndexed
ON lab.vw_DailyCustomerRevenueIndexed(CustomerID, OrderDate);
GO

-- Esta consulta é típica de um endpoint que alimenta um cartão de dashboard.
SELECT CustomerID, OrderDate, TotalOrders, DailyRevenue
FROM lab.vw_DailyCustomerRevenueIndexed WITH (NOEXPAND)
WHERE CustomerID = 1
  AND OrderDate >= '2025-01-01'
  AND OrderDate < '2025-02-01'
ORDER BY OrderDate;
GO

-- CENÁRIO 3: Segmentação de clientes ativos para CRM e atendimento
-- Problema: vários serviços consultam continuamente o valor e o número de compras dos
-- clientes ativos. A consulta original junta Customers a Orders e depois agrega.
-- Por que a view ajuda: materializa tanto o INNER JOIN quanto a agregação. Uma mudança em
-- IsActive ou em um pedido atualiza o resultado automaticamente.
-- Bom perfil: poucas alterações de status e muitas leituras de segmentos/rankings.
CREATE VIEW lab.vw_ActiveCustomerRevenueIndexed
WITH SCHEMABINDING
AS
    SELECT
        c.CustomerID,
        COUNT_BIG(*) AS TotalOrders,
        SUM(o.TotalAmount) AS TotalSpent
    FROM lab.Customers AS c
    INNER JOIN lab.Orders AS o
        ON o.CustomerID = c.CustomerID
    WHERE c.IsActive = 1
    GROUP BY c.CustomerID;
GO

CREATE UNIQUE CLUSTERED INDEX CIX_vw_ActiveCustomerRevenueIndexed
ON lab.vw_ActiveCustomerRevenueIndexed(CustomerID);
GO

-- Exemplo: campanha para clientes ativos com alto valor acumulado.
SELECT CustomerID, TotalOrders, TotalSpent
FROM lab.vw_ActiveCustomerRevenueIndexed WITH (NOEXPAND)
WHERE TotalSpent >= 500.00
ORDER BY TotalSpent DESC;
GO

-- CENÁRIO 4: Quando NÃO usar uma indexed view
-- Uma tela administrativa consultada uma vez por dia, ou uma tabela de pedidos que recebe
-- muitos INSERTs/UPDATEs por segundo, tende a não justificar o custo de manutenção do
-- índice da view. Em cada DML em lab.Orders, o SQL Server precisa manter também:
--   * CIX_vw_OrderSummaryIndexed;
--   * CIX_vw_DailyCustomerRevenueIndexed; e
--   * CIX_vw_ActiveCustomerRevenueIndexed.
-- Nesses casos, avalie primeiro índices nas tabelas base, cache de aplicação, tabela de
-- resumo atualizada em lote ou uma solução analítica separada. Valide sempre com plano
-- real e SET STATISTICS IO, TIME, comparando leitura economizada versus latência de escrita.

-- RESUMO DE DECISÃO
-- Caso                                      | Indexed view costuma ser adequada?
-- Dashboard com agregação repetida          | Sim: pré-calcula GROUP BY/SUM/COUNT_BIG.
-- Consulta frequente de join + agregação    | Sim: quando atende as restrições de definição.
-- Relatório esporádico                      | Geralmente não: o custo de manutenção prevalece.
-- OLTP com escrita muito intensa            | Geralmente não: cada DML mantém todos os índices.
-- Lógica com OUTER JOIN, TOP ou GETDATE()   | Não: não pode compor uma indexed view.
GO

-- =================================================================================
-- MANUTENÇÃO E LIMPEZA (OPCIONAL)
-- =================================================================================
/*
DROP VIEW IF EXISTS lab.vw_NonDeterministicView;
DROP VIEW IF EXISTS lab.vw_ActiveCustomerRevenueIndexed;
DROP VIEW IF EXISTS lab.vw_DailyCustomerRevenueIndexed;
DROP VIEW IF EXISTS lab.vw_OrderSummaryIndexed;
DROP VIEW IF EXISTS lab.vw_ActiveCustomers;
DROP VIEW IF EXISTS lab.vw_BoundProducts;
DROP TABLE IF EXISTS lab.Orders;
DROP TABLE IF EXISTS lab.Customers;
DROP TABLE IF EXISTS lab.Products;
*/


-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/02-programmability-objects/01-views.md
-- =================================================================================================
-- =================================================================================================
-- REFERÊNCIAS OFICIAIS DO MICROSOFT LEARN
-- =================================================================================================
-- CREATE VIEW, views atualizáveis e WITH CHECK OPTION:
-- https://learn.microsoft.com/pt-br/sql/t-sql/statements/create-view-transact-sql?view=sql-server-ver17
-- Views indexadas, SCHEMABINDING, opções SET obrigatórias e NOEXPAND:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/views/create-indexed-views?view=sql-server-ver17
-- Sintaxe de CREATE INDEX e opções de índice:
-- https://learn.microsoft.com/pt-br/sql/t-sql/statements/create-index-transact-sql?view=sql-server-ver17
