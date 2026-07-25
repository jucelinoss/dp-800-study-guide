-- =================================================================================
-- DP-800 - LAB PRÁTICO: SCALAR E TABLE-VALUED FUNCTIONS (UDFs, iTVF, mTVF E APPLY)
-- Banco de Dados: AdventureWorks2025 (ou similar)
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
--   6. Cenários Práticos de Projeto (Cálculo de Desconto Inline e Relatórios Hierárquicos)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_FormatCustomerName' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_FormatCustomerName;
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_GetCustomerOrdersInline' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_GetCustomerOrdersInline;
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'fn_GetCustomerOrdersMultiStatement' AND type IN ('FN', 'IF', 'TF'))
    DROP FUNCTION lab.fn_GetCustomerOrdersMultiStatement;

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
    OBJECTPROPERTY(object_id, 'IsDeterministic') AS IsDeterministic,
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
--     Continua menos transparente para o otimizador. No SQL Server 2025, consultas somente leitura elegíveis
--     podem usar interleaved execution para revisar a estimativa após materializar a mTVF; isso não transforma
--     a função em iTVF nem elimina todos os seus custos.

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


-- =================================================================================
-- PARTE 3: OPERADORES APPLY (CROSS APPLY VS OUTER APPLY)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CROSS APPLY: Funciona de forma análoga a um `INNER JOIN`. Executa a função de tabela para cada linha da
--     tabela à esquerda e retorna apenas as linhas em que a função produziu ao menos um resultado.
--   - OUTER APPLY: Funciona de forma análoga a um `LEFT JOIN`. Retorna todas as linhas da tabela à esquerda,
--     preenchendo com NULL nos campos da função quando ela não retornar registros.

-- Inserir dados de teste
INSERT INTO lab.Customers (FirstName, LastName) VALUES ('Alice', 'Smith'), ('Bob', 'Jones'), ('Charlie', 'Brown');
INSERT INTO lab.Orders (CustomerID, OrderDate) VALUES (1, '2025-01-10');
INSERT INTO lab.OrderItems (OrderID, ProductName, Quantity, UnitPrice) VALUES (1, 'Teclado', 1, 150.00);
GO

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

-- Comparação didática: habilite o Plano de Execução Atual (Ctrl+M) e compare a iTVF com a mTVF.
-- A iTVF é expandida na consulta; a mTVF retorna uma tabela materializada. Em SQL Server 2025,
-- uma consulta somente leitura pode mostrar interleaved execution e estimativa revisada para a mTVF.
SELECT c.CustomerID, c.FirstName, fn.OrderID, fn.TotalAmount
FROM lab.Customers AS c
OUTER APPLY lab.fn_GetCustomerOrdersMultiStatement(c.CustomerID) AS fn;
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

--- CENÁRIO 1: Cálculo de Desconto Progressivo Inline em Relatório de Vendas
-- Em vez de chamar uma função escalar dentro do SELECT em milhões de registros,
-- utiliza-se um Inline TVF combinado com CROSS APPLY para performance ideal.

SELECT 
    c.CustomerID,
    lab.fn_FormatCustomerName(c.FirstName, c.LastName) AS CustomerNameFormatted,
    ord.OrderID,
    ord.TotalAmount
FROM lab.Customers c
CROSS APPLY lab.fn_GetCustomerOrdersInline(c.CustomerID) ord;
GO
