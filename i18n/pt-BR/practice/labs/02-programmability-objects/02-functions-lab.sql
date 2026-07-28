-- =================================================================================
-- DP-800 - LAB PRÁTICO: SCALAR E TABLE-VALUED FUNCTIONS (UDFs, iTVF, mTVF E APPLY)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/02-programmability-objects/02-functions.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a implementação e otimização de funções no SQL Server:
--   1. Funções Escalares (Scalar UDFs) e verificação de Inlining (sys.sql_modules)
--   2. Inline Table-Valued Functions (iTVF) vs Multi-Statement TVFs (mTVF)
--   3. Impacto de Desempenho e Cardinalidade (Visibilidade pelo Otimizador)
--   4. Operadores CROSS APPLY e OUTER APPLY com Funções de Tabela
--   5. Schemabinding e Teste de Determinismo via OBJECTPROPERTY
--   6. Benchmark com milhões de linhas: iTVF + CROSS APPLY, mTVF e Scalar UDF
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva. Os labs de Views e Functions compartilham as tabelas lab.Orders e
-- lab.Customers; remova primeiro as views com SCHEMABINDING que podem impedir o DROP TABLE.
DROP VIEW IF EXISTS lab.vw_ActiveCustomerRevenueIndexed;
DROP VIEW IF EXISTS lab.vw_DailyCustomerRevenueIndexed;
DROP VIEW IF EXISTS lab.vw_OrderSummaryIndexed;
DROP VIEW IF EXISTS lab.vw_OrderSummaryIndexed_BadCount;
DROP VIEW IF EXISTS lab.vw_OuterJoinIndexed;
DROP VIEW IF EXISTS lab.vw_NonDeterministicView;

IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_FormatCustomerName' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_FormatCustomerName;
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_GetCustomerOrdersInline' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_GetCustomerOrdersInline;
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_GetCustomerOrdersMultiStatement' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_GetCustomerOrdersMultiStatement;
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_GetCustomerLifetimeTotalScalar' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_GetCustomerLifetimeTotalScalar;

DROP TABLE IF EXISTS lab.OrderItems;
DROP TABLE IF EXISTS lab.Orders;
DROP TABLE IF EXISTS lab.Customers;
GO

-- Estrutura de Tabelas para Teste
CREATE TABLE lab.Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL
);

CREATE TABLE lab.Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    Status NVARCHAR(20) NOT NULL DEFAULT 'Active'
);

CREATE TABLE lab.OrderItems (
    ItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductName NVARCHAR(100) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL
);
GO


-- =================================================================================
-- PARTE 1: SCALAR FUNCTIONS E VERIFICAÇÃO DE INLINING
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - SCALAR FUNCTION (Função Escalar): Retorna um único valor. Historicamente força execução RBAR
--     (Row-By-Agonizing-Row) linha a linha, impedindo a paralelização da consulta.
--   - SCALAR UDF INLINING (SQL Server 2019+): Recurso do Intelligent Query Processing que converte
--     automaticamente certas funções escalares em expressões relacionais inline durante a compilação.

-- 1. Criar uma Função Escalar com SCHEMABINDING
CREATE FUNCTION lab.fn_FormatCustomerName (
    @FirstName NVARCHAR(50),
    @LastName NVARCHAR(50)
)
RETURNS NVARCHAR(105)
WITH SCHEMABINDING
AS
BEGIN
    RETURN UPPER(LTRIM(RTRIM(@LastName))) + ', ' + LTRIM(RTRIM(@FirstName));
END;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- Verificação de elegibilidade para inlining via sys.sql_modules (SQL Server 2019+).
-- is_inlineable = 1 indica que a definição é elegível; o otimizador ainda decide por consulta
-- se fará o inlining. Para confirmar a ocorrência, examine o plano XML: uma UDF inlined não
-- tem o nó <UserDefinedFunction>.
SELECT 
    name,
    OBJECTPROPERTY(o.object_id, 'IsDeterministic') AS IsDeterministic,
    sm.is_inlineable
FROM sys.objects o
JOIN sys.sql_modules sm ON o.object_id = sm.object_id
WHERE o.name = 'fn_FormatCustomerName';
GO


-- =================================================================================
-- PARTE 2: INLINE TVF (iTVF) VS MULTI-STATEMENT TVF (mTVF)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - INLINE TVF (iTVF): Retorna o resultado de um único comando `SELECT`. É transparente para o otimizador,
--     que a expande como uma View Parametrizada, permitindo estatísticas precisas e execução paralela.
--   - MULTI-STATEMENT TVF (mTVF): Popula explicitamente uma variável de tabela (`@Result TABLE`) em múltiplas etapas.
--     Continua menos transparente para o otimizador. A partir do SQL Server 2017 com compatibilidade 140,
--     a execução intercalada (*interleaved execution*) pode pausar a otimização, executar a mTVF e usar sua
--     contagem real de linhas para otimizar os operadores posteriores (por exemplo, JOIN e memory grant).
--     Ela exige uma consulta elegível, não torna a função uma iTVF e não elimina todos os seus custos.

-- 1. Criar Inline TVF (Recomendado para Performance)
CREATE FUNCTION lab.fn_GetCustomerOrdersInline (@CustomerID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
    SELECT 
        o.OrderID,
        o.OrderDate,
        o.Status,
        SUM(oi.Quantity * oi.UnitPrice) AS TotalAmount
    FROM lab.Orders o
    JOIN lab.OrderItems oi ON o.OrderID = oi.OrderID
    WHERE o.CustomerID = @CustomerID
    GROUP BY o.OrderID, o.OrderDate, o.Status
);
GO

-- 2. Criar Multi-Statement TVF (Black Box para o Otimizador)
CREATE FUNCTION lab.fn_GetCustomerOrdersMultiStatement (@CustomerID INT)
RETURNS @Result TABLE (
    OrderID INT,
    OrderDate DATE,
    Status NVARCHAR(20),
    TotalAmount DECIMAL(18,2)
)
AS
BEGIN
    INSERT INTO @Result
    SELECT 
        o.OrderID,
        o.OrderDate,
        o.Status,
        SUM(oi.Quantity * oi.UnitPrice)
    FROM lab.Orders o
    JOIN lab.OrderItems oi ON o.OrderID = oi.OrderID
    WHERE o.CustomerID = @CustomerID
    GROUP BY o.OrderID, o.OrderDate, o.Status;
    
    RETURN;
END;
GO

-- 3. Preparar dados para comparar as duas funções com a mesma consulta chamadora.
-- Charlie fica sem pedidos de propósito: isso também será usado na demonstração de APPLY.
INSERT INTO lab.Customers (FirstName, LastName)
VALUES ('Alice', 'Smith'), ('Bob', 'Jones'), ('Charlie', 'Brown');
INSERT INTO lab.Orders (CustomerID, OrderDate)
VALUES (1, '2025-01-10');
INSERT INTO lab.OrderItems (OrderID, ProductName, Quantity, UnitPrice)
VALUES (1, 'Teclado', 1, 150.00);
GO

-- 4. Comparação didática de desempenho: habilite o Plano de Execução Atual (Ctrl+M).
-- As duas consultas retornam o mesmo resultado. A iTVF é expandida no plano; a mTVF
-- retorna uma tabela materializada. Com compatibilidade 140+ e consulta elegível, a mTVF
-- pode ter a estimativa revisada por execução intercalada, sem expor sua lógica interna.
SELECT c.CustomerID, c.FirstName, fn.OrderID, fn.TotalAmount
FROM lab.Customers AS c
OUTER APPLY lab.fn_GetCustomerOrdersInline(c.CustomerID) AS fn;
GO

SELECT c.CustomerID, c.FirstName, fn.OrderID, fn.TotalAmount
FROM lab.Customers AS c
OUTER APPLY lab.fn_GetCustomerOrdersMultiStatement(c.CustomerID) AS fn;
GO


-- =================================================================================
-- PARTE 3: OPERADORES APPLY (CROSS APPLY VS OUTER APPLY)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CROSS APPLY: Funciona de forma análoga a um `INNER JOIN`. Executa a função de tabela para cada linha da
--     tabela à esquerda e retorna apenas as linhas em que a função produziu ao menos um resultado.
--   - OUTER APPLY: Funciona de forma análoga a um `LEFT JOIN`. Retorna todas as linhas da tabela à esquerda,
--     preenchendo com NULL nos campos da função quando ela não retornar registros.

-- -- [PONTO DE ATENÇÃO DP-800]
-- CROSS APPLY: Charlie não tem pedidos, portanto NÃO APARECE no resultado
SELECT c.CustomerID, c.FirstName, fn.OrderID, fn.TotalAmount
FROM lab.Customers c
CROSS APPLY lab.fn_GetCustomerOrdersInline(c.CustomerID) fn;

-- OUTER APPLY: Charlie APARECE no resultado com campos nulos (preserva a linha pai)
SELECT c.CustomerID, c.FirstName, fn.OrderID, fn.TotalAmount
FROM lab.Customers c
OUTER APPLY lab.fn_GetCustomerOrdersInline(c.CustomerID) fn;
GO


-- =================================================================================
-- PARTE 4: SCHEMABINDING E TESTE DE DETERMINISMO VIA OBJECTPROPERTY
-- =================================================================================

-- Testando a verificação de determinismo com OBJECTPROPERTY
SELECT 
    OBJECTPROPERTY(OBJECT_ID('lab.fn_FormatCustomerName'), 'IsDeterministic') AS IsDeterministic;
GO


-- =================================================================================
-- PARTE 5: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

-- CENÁRIO 1: Benchmark de alta volumetria — iTVF + CROSS APPLY vs. mTVF e Scalar UDF
-- Objetivo: comparar três formas de obter o total de pedidos por cliente com o MESMO resultado:
--   A. Recomendada: iTVF com CROSS APPLY. A lógica interna participa do plano chamador.
--   B. Evitar em alta volumetria: mTVF com CROSS APPLY. A função é invocada por cliente e
--      materializa uma variável de tabela; o plano externo não enxerga sua lógica.
--   C. Evitar em consultas orientadas a conjuntos: Scalar UDF não-inlined, executada por cliente.
--
-- AVISO: a configuração padrão insere aproximadamente 1.000.000 de pedidos e 2.000.000
-- de itens. Ajuste as duas variáveis se o ambiente tiver pouco espaço, log ou tempo de CPU.
-- Execute em um banco de laboratório; esta carga apaga os objetos lab no início do script.

DECLARE @BenchmarkCustomerCount INT = 100000;
DECLARE @OrdersPerCustomer INT = 10;
DECLARE @FirstBenchmarkCustomerID INT = CONVERT(INT, IDENT_CURRENT(N'lab.Customers')) + 1;

-- Gera clientes de forma set-based. sys.all_objects é usado apenas como fonte de números.
;WITH Numbers AS
(
    SELECT TOP (@BenchmarkCustomerCount)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Number
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
)
INSERT INTO lab.Customers (FirstName, LastName)
SELECT
    CONCAT(N'Cliente', Number),
    CONCAT(N'Benchmark', Number)
FROM Numbers;

-- Cada cliente novo recebe @OrdersPerCustomer pedidos: 100.000 x 10 = 1.000.000 por padrão.
INSERT INTO lab.Orders (CustomerID, OrderDate, Status)
SELECT
    c.CustomerID,
    DATEADD(DAY, -((c.CustomerID * @OrdersPerCustomer + n.OrderSequence) % 730), CONVERT(DATE, '2025-12-31')),
    N'Active'
FROM lab.Customers AS c
CROSS JOIN
(
    SELECT TOP (@OrdersPerCustomer)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS OrderSequence
    FROM sys.all_objects
) AS n
WHERE c.CustomerID >= @FirstBenchmarkCustomerID;

-- Dois itens por pedido: 2.000.000 de itens para a configuração padrão.
INSERT INTO lab.OrderItems (OrderID, ProductName, Quantity, UnitPrice)
SELECT
    o.OrderID,
    CONCAT(N'Produto ', i.ItemSequence),
    i.ItemSequence,
    CONVERT(DECIMAL(18,2), 10.00 * i.ItemSequence)
FROM lab.Orders AS o
CROSS JOIN (VALUES (1), (2)) AS i(ItemSequence)
WHERE o.CustomerID >= @FirstBenchmarkCustomerID;
GO

-- Índices alinhados aos predicados e joins das TVFs. Crie-os APÓS a carga para evitar
-- manter índices durante os milhões de INSERTs.
CREATE INDEX IX_Orders_CustomerID_OrderID
ON lab.Orders (CustomerID, OrderID)
INCLUDE (OrderDate, Status);

CREATE INDEX IX_OrderItems_OrderID
ON lab.OrderItems (OrderID)
INCLUDE (Quantity, UnitPrice);
GO

-- Atualize estatísticas para que a iTVF tenha informação representativa ao ser expandida.
UPDATE STATISTICS lab.Orders IX_Orders_CustomerID_OrderID;
UPDATE STATISTICS lab.OrderItems IX_OrderItems_OrderID;

SELECT
    (SELECT COUNT_BIG(*) FROM lab.Customers) AS Customers,
    (SELECT COUNT_BIG(*) FROM lab.Orders) AS Orders,
    (SELECT COUNT_BIG(*) FROM lab.OrderItems) AS OrderItems;
GO

-- Scalar UDF propositalmente não-inlined: é usada somente para demonstrar o custo RBAR.
-- INLINE = OFF requer SQL Server 2019+; remova essa opção apenas se estiver em versão anterior.
CREATE FUNCTION lab.fn_GetCustomerLifetimeTotalScalar (@CustomerID INT)
RETURNS DECIMAL(38,2)
WITH SCHEMABINDING, INLINE = OFF
AS
BEGIN
    DECLARE @Total DECIMAL(38,2);

    SELECT @Total = SUM(oi.Quantity * oi.UnitPrice)
    FROM lab.Orders AS o
    INNER JOIN lab.OrderItems AS oi
        ON oi.OrderID = o.OrderID
    WHERE o.CustomerID = @CustomerID;

    RETURN @Total;
END;
GO

-- Habilite o Plano de Execução Atual (Ctrl+M). Rode cada consulta pelo menos duas vezes
-- e alterne a ordem entre as execuções: a primeira inclui aquecimento de cache. Compare:
--   * CPU e leituras lógicas nas mensagens de STATISTICS IO/TIME;
--   * linhas estimadas x reais; e
--   * presença de Table-valued function / UserDefinedFunction no plano.
-- Cada consulta retorna apenas UMA linha de resumo para que o envio de 100.000 linhas ao
-- SSMS não mascare o custo do banco. A e B devem retornar o mesmo número de pedidos e total.
SET STATISTICS IO, TIME ON;
GO

-- FASE 1 — COMPARATIVO PRINCIPAL: iTVF x mTVF com aproximadamente 1 milhão de pedidos.
-- A. RECOMENDADA: a iTVF é expandida e o otimizador pode escolher o plano para o conjunto inteiro.
SELECT
    COUNT_BIG(*) AS OrdersReturned,
    SUM(ord.TotalAmount) AS GrandTotal
FROM lab.Customers AS c
CROSS APPLY lab.fn_GetCustomerOrdersInline(c.CustomerID) AS ord
WHERE c.CustomerID >= 4
OPTION (RECOMPILE);
GO

-- B. NÃO RECOMENDADA EM ALTA VOLUMETRIA: mesmo resultado, mas uma mTVF é chamada por cliente.
-- No plano, observe a estimativa do operador Table-valued function e quantas execuções ele recebe.
SELECT
    COUNT_BIG(*) AS OrdersReturned,
    SUM(ord.TotalAmount) AS GrandTotal
FROM lab.Customers AS c
CROSS APPLY lab.fn_GetCustomerOrdersMultiStatement(c.CustomerID) AS ord
WHERE c.CustomerID >= 4
OPTION (RECOMPILE);
GO

-- FASE 2 — REFERÊNCIA ADICIONAL: Scalar UDF não-inlined em modo RBAR.
-- C. Mesmo GrandTotal, mas a função escalar é invocada uma vez para cada cliente novo.
SELECT
    COUNT_BIG(*) AS CustomersProcessed,
    SUM(lab.fn_GetCustomerLifetimeTotalScalar(c.CustomerID)) AS GrandTotal
FROM lab.Customers AS c
WHERE c.CustomerID >= 4
OPTION (RECOMPILE);
GO

SET STATISTICS IO, TIME OFF;
GO


-- =================================================================================
-- MANUTENÇÃO E LIMPEZA (OPCIONAL)
-- =================================================================================
/*
-- Execute este bloco ao terminar o laboratório. A ordem preserva a remoção das
-- dependências schema-bound antes das tabelas compartilhadas entre os labs.
DROP VIEW IF EXISTS lab.vw_ActiveCustomerRevenueIndexed;
DROP VIEW IF EXISTS lab.vw_DailyCustomerRevenueIndexed;
DROP VIEW IF EXISTS lab.vw_OrderSummaryIndexed;
DROP VIEW IF EXISTS lab.vw_OrderSummaryIndexed_BadCount;
DROP VIEW IF EXISTS lab.vw_OuterJoinIndexed;
DROP VIEW IF EXISTS lab.vw_NonDeterministicView;

DROP FUNCTION IF EXISTS lab.fn_GetCustomerLifetimeTotalScalar;
DROP FUNCTION IF EXISTS lab.fn_GetCustomerOrdersMultiStatement;
DROP FUNCTION IF EXISTS lab.fn_GetCustomerOrdersInline;
DROP FUNCTION IF EXISTS lab.fn_FormatCustomerName;

DROP TABLE IF EXISTS lab.OrderItems;
DROP TABLE IF EXISTS lab.Orders;
DROP TABLE IF EXISTS lab.Customers;
*/


-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/02-programmability-objects/02-functions.md
-- =================================================================================================
-- =================================================================================================
-- REFERÊNCIAS OFICIAIS DO MICROSOFT LEARN
-- =================================================================================================
-- CREATE FUNCTION, UDFs escalares, iTVFs, mTVFs e SCHEMABINDING:
-- https://learn.microsoft.com/pt-br/sql/t-sql/statements/create-function-transact-sql?view=sql-server-ver17
-- Inlining de UDF escalar e validação pelo plano:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/user-defined-functions/scalar-udf-inlining?view=sql-server-ver17
-- Execução intercalada para TVFs de múltiplas instruções:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/performance/intelligent-query-processing-details?view=sql-server-ver17
-- Operadores APPLY:
-- https://learn.microsoft.com/pt-br/sql/t-sql/queries/from-transact-sql?view=sql-server-ver17
