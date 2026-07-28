-- ====================================================================
-- DP-800 Guia de Estudo — Laboratório 06: Subconsultas e CTEs
-- Banco de Dados: AdventureWorks2025
-- Objetivo: Derived tables, CTEs, temp tables, table variables
-- Pré-requisito: Laboratórios 01-05 (conceitos de AGREGAÇÃO necessários)
-- ====================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/00-fundamentals/06-aggregation-and-grouping.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.

-- ====================================================================
-- Derived table: subconsulta no FROM com alias obrigatório
-- CONCEITO CHAVE: Uma derived table é uma visão inline. Ela deve ter um alias.
-- Diferente de uma CTE, não pode ser referenciada mais de uma vez na instrução.
-- ====================================================================
-- Produtos com quantidade total vendida > 100
-- ESPERADO: ~200 produtos
SELECT dt.ProductID, dt.ProductName, dt.TotalSold
FROM (
    SELECT p.ProductID,
           p.Name AS ProductName,
           SUM(sod.OrderQty) AS TotalSold
    FROM Production.Product AS p
    INNER JOIN Sales.SalesOrderDetail AS sod
        ON sod.ProductID = p.ProductID
    GROUP BY p.ProductID, p.Name
) AS dt
WHERE dt.TotalSold > 100
ORDER BY dt.TotalSold DESC;
GO

-- ====================================================================
-- CTE simples
-- CONCEITO CHAVE: WITH define uma expressão nomeada para a próxima instrução.
-- O nome da CTE está disponível apenas na instrução imediatamente após ela.
-- ====================================================================
WITH ProductSales AS (
    SELECT p.ProductID,
           p.Name AS ProductName,
           SUM(sod.OrderQty) AS TotalSold
    FROM Production.Product AS p
    INNER JOIN Sales.SalesOrderDetail AS sod
        ON sod.ProductID = p.ProductID
    GROUP BY p.ProductID, p.Name
)
SELECT ProductID, ProductName, TotalSold
FROM ProductSales
WHERE TotalSold > 100
ORDER BY TotalSold DESC;
GO

-- [OBSERVE] A versão CTE é mais legível que a versão derived table
-- para a mesma pergunta de negócio. A CTE separa a lógica (o que é
-- ProductSales?) do filtro (WHERE TotalSold > 100).

-- ====================================================================
-- Múltiplas CTEs (separadas por vírgula)
-- CONCEITO CHAVE: CTEs podem referenciar CTEs anteriores na mesma cláusula WITH.
-- ====================================================================
WITH
ProductSales AS (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
),
HighSellers AS (
    SELECT ps.ProductID, p.Name, ps.TotalSold
    FROM ProductSales AS ps
    INNER JOIN Production.Product AS p
        ON p.ProductID = ps.ProductID
    WHERE ps.TotalSold > 500
)
SELECT Name, TotalSold
FROM HighSellers
ORDER BY TotalSold DESC;
GO

-- [OBSERVE] HighSellers depende de ProductSales. A vírgula separa
-- as definições das CTEs. Cada uma constrói sobre a anterior.

-- ====================================================================
-- CTE vs derived table: mesma consulta, dois estilos
-- CONCEITO CHAVE: CTEs são preferidas para legibilidade, especialmente com
-- múltiplas etapas. Os planos de execução são tipicamente idênticos.
-- ====================================================================
-- Derived table: aninhada, mais difícil de ler
SELECT d.CustomerID, d.TotalSpend
FROM (
    SELECT CustomerID, SUM(TotalDue) AS TotalSpend
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
) AS d
WHERE d.TotalSpend > 5000;
GO

-- CTE: mais plana, mais fácil de ler
WITH CustomerSpend AS (
    SELECT CustomerID, SUM(TotalDue) AS TotalSpend
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
)
SELECT CustomerID, TotalSpend
FROM CustomerSpend
WHERE TotalSpend > 5000;
GO

-- ====================================================================
-- Tabela temporária local (#Temp)
-- CONCEITO CHAVE: #Temp persiste pela sessão. Pode ter índices.
-- Bom para reutilizar resultados intermediários entre múltiplas instruções.
-- ====================================================================
-- Crie uma tabela temporária para armazenar pedidos de alto valor
CREATE TABLE #HighValueOrders (
    SalesOrderID INT NOT NULL PRIMARY KEY,
    TotalDue     DECIMAL(18,2) NOT NULL
);

-- Popule-a
INSERT INTO #HighValueOrders (SalesOrderID, TotalDue)
SELECT SalesOrderID, TotalDue
FROM Sales.SalesOrderHeader
WHERE TotalDue > 5000;

-- Use-a em consultas
SELECT COUNT(*) AS HighValueCount FROM #HighValueOrders;
SELECT AVG(TotalDue) AS AvgHighValue FROM #HighValueOrders;

-- Limpe explicitamente
DROP TABLE IF EXISTS #HighValueOrders;
GO

-- [OBSERVE] Diferente de uma CTE, #HighValueOrders pode ser consultada em
-- múltiplos lotes. A tabela temporária é descartada quando a sessão termina,
-- mas limpeza explícita é um bom hábito.

-- ====================================================================
-- Table variable (@TableVar)
-- CONCEITO CHAVE: Escopo limitado ao lote/procedure. Mais leve que #Temp,
-- mas não tem estatísticas (otimizador assume 1 linha).
-- ====================================================================
DECLARE @SelectedProducts TABLE (
    ProductID INT NOT NULL PRIMARY KEY,
    Name      NVARCHAR(50) NOT NULL,
    ListPrice DECIMAL(18,2) NOT NULL
);

INSERT INTO @SelectedProducts (ProductID, Name, ListPrice)
SELECT ProductID, Name, ListPrice
FROM Production.Product
WHERE ListPrice > 500;

-- Consulte a table variable
SELECT COUNT(*) AS ExpensiveProducts FROM @SelectedProducts;
SELECT AVG(ListPrice) AS AvgPrice FROM @SelectedProducts;
GO

-- [OBSERVE] @SelectedProducts é automaticamente limpa no final
-- do lote (após GO). É ideal para pequenos conjuntos de consulta.

-- ====================================================================
-- CTE + INTO #Temp (combinando estilos)
-- CONCEITO CHAVE: Use CTE para legibilidade, então persista em uma tabela temporária
-- quando precisar reutilizar o resultado entre múltiplas instruções.
-- ====================================================================
WITH ProductSales AS (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
)
SELECT p.ProductID, p.Name, ps.TotalSold
INTO #ProductSalesReport
FROM ProductSales AS ps
INNER JOIN Production.Product AS p
    ON p.ProductID = ps.ProductID;

-- Agora reutilize #ProductSalesReport em múltiplas consultas
SELECT COUNT(*) AS HighSellers FROM #ProductSalesReport WHERE TotalSold > 500;
SELECT AVG(TotalSold) AS AvgSold FROM #ProductSalesReport;

-- Limpe
DROP TABLE IF EXISTS #ProductSalesReport;
GO

-- ====================================================================
-- Armadilha NOT IN com NULL (demonstração com tabela temporária)
-- CONCEITO CHAVE: NOT IN retorna zero linhas se o resultado da subconsulta
-- contiver qualquer NULL. Use NOT EXISTS por segurança.
-- ====================================================================
CREATE TABLE #TestNull (CustomerID INT NULL);
INSERT INTO #TestNull VALUES (1), (NULL);

-- Isso retorna ZERO linhas por causa do NULL!
SELECT CustomerID FROM Sales.Customer
WHERE CustomerID NOT IN (SELECT CustomerID FROM #TestNull);

-- Isso funciona corretamente (NOT EXISTS lida com NULL com segurança)
SELECT CustomerID FROM Sales.Customer AS c
WHERE NOT EXISTS (
    SELECT 1 FROM #TestNull AS t
    WHERE t.CustomerID = c.CustomerID
);

DROP TABLE IF EXISTS #TestNull;
GO

-- ====================================================================
-- VERIFIQUE-SE:
-- 1. Reescreva a consulta derived table no topo deste laboratório como uma CTE.
-- 2. Use uma CTE para encontrar os top 5 produtos por receita
--    (SUM(UnitPrice * OrderQty) em SalesOrderDetail).
-- 3. Quando você escolheria uma #TempTable em vez de uma CTE?
-- 4. Crie uma table variable contendo pedidos de alto valor de hoje
--    (TotalDue > 5000) e consulte-a.
-- ====================================================================

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/00-fundamentals/06-aggregation-and-grouping.md
-- =================================================================================================
