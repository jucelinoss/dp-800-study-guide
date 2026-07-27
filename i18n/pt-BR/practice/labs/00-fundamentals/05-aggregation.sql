-- ====================================================================
-- DP-800 Guia de Estudo — Laboratório 05: Agregação e GROUP BY
-- Banco de Dados: AdventureWorks2025
-- Objetivo: COUNT, SUM, AVG, MIN, MAX, GROUP BY, HAVING, agg condicional
-- Pré-requisito: Laboratório 04 (familiaridade com schema AdventureWorks)
-- ====================================================================

-- ====================================================================
-- Visão geral das funções de agregação
-- CONCEITO CHAVE: Todas as agregações exceto COUNT(*) ignoram valores NULL.
-- Todas as agregações retornam uma única linha quando usadas sem GROUP BY.
-- ====================================================================
-- ESTATÍSTICAS GERAIS no SalesOrderHeader (~31k linhas)
SELECT COUNT(*)              AS TotalOrders,
       COUNT(ShipDate)       AS ShippedOrders,    -- ignora NULL ShipDate
       COUNT(DISTINCT CustomerID) AS UniqueCustomers,
       MIN(TotalDue)         AS SmallestOrder,
       MAX(TotalDue)         AS LargestOrder,
       AVG(TotalDue)         AS AvgOrderValue,
       SUM(TotalDue)         AS GrandTotal
FROM Sales.SalesOrderHeader;
GO

-- [OBSERVE] ShippedOrders < TotalOrders porque alguns pedidos têm NULL ShipDate.
-- COUNT(DISTINCT CustomerID) conta clientes únicos, ignorando NULLs.

-- ====================================================================
-- Variações de COUNT
-- CONCEITO CHAVE: COUNT(*) vs COUNT(col) vs COUNT(DISTINCT col)
-- ====================================================================
SELECT COUNT(*)              AS AllRows,           -- 31465
       COUNT(ShipDate)       AS WithShipDate,      -- menos (NULL excluído)
       COUNT(DISTINCT CustomerID) AS UniqueCust     -- clientes únicos não-nulos
FROM Sales.SalesOrderHeader;
GO

-- ====================================================================
-- GROUP BY coluna única
-- CONCEITO CHAVE: Uma linha de resultado por valor único da coluna GROUP BY.
-- ====================================================================
-- ESPERADO: Uma linha por território (~10 linhas)
SELECT st.Name AS Territory,
       COUNT(soh.SalesOrderID) AS OrderCount,
       SUM(soh.TotalDue)       AS TotalSales,
       AVG(soh.TotalDue)       AS AvgOrderValue
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c
    ON c.CustomerID = soh.CustomerID
INNER JOIN Sales.SalesTerritory AS st
    ON st.TerritoryID = c.TerritoryID
GROUP BY st.Name
ORDER BY TotalSales DESC;
GO

-- [OBSERVE] O grão: "uma linha por território". Cada agregação resume
-- todos os pedidos dentro daquele território.

-- ====================================================================
-- GROUP BY composto (múltiplas colunas)
-- CONCEITO CHAVE: Uma linha por combinação única das colunas de agrupamento.
-- ====================================================================
-- ESPERADO: ~500 linhas (combinações ano × produto)
SELECT YEAR(soh.OrderDate)   AS OrderYear,
       p.Name                AS ProductName,
       SUM(sod.OrderQty)     AS TotalSold,
       SUM(sod.LineTotal)    AS TotalRevenue
FROM Sales.SalesOrderDetail AS sod
INNER JOIN Production.Product AS p
    ON p.ProductID = sod.ProductID
INNER JOIN Sales.SalesOrderHeader AS soh
    ON soh.SalesOrderID = sod.SalesOrderID
GROUP BY YEAR(soh.OrderDate), p.Name
ORDER BY OrderYear, TotalRevenue DESC;
GO

-- [OBSERVE] Esta consulta tem grão: "uma linha por combinação ano + produto".
-- Cada linha informa quanto de um produto foi vendido em um ano específico.

-- ====================================================================
-- HAVING para filtrar grupos
-- CONCEITO CHAVE: WHERE filtra linhas ANTES do agrupamento.
-- HAVING filtra grupos APÓS a agregação.
-- ====================================================================
-- Territórios com valor médio de pedido > $1.000
SELECT st.Name AS Territory,
       COUNT(soh.SalesOrderID) AS OrderCount,
       AVG(soh.TotalDue)       AS AvgOrderValue
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c
    ON c.CustomerID = soh.CustomerID
INNER JOIN Sales.SalesTerritory AS st
    ON st.TerritoryID = c.TerritoryID
WHERE soh.OrderDate >= '2013-01-01'           -- filtra linhas primeiro
GROUP BY st.Name
HAVING AVG(soh.TotalDue) > 1000              -- filtra grupos depois
ORDER BY AvgOrderValue DESC;
GO

-- ====================================================================
-- LEFT JOIN + agregação (lidando com NULLs)
-- CONCEITO CHAVE: COUNT(ChildID) retorna corretamente zero para pais sem correspondência.
-- COUNT(*) contaria a linha estendida com NULL como 1, o que é errado.
-- ====================================================================
-- Todos os produtos com quantidade total vendida (incluindo não vendidos)
SELECT p.ProductID,
       p.Name,
       COUNT(sod.ProductID) AS SaleCount,    -- 0 se nunca vendido
       COALESCE(SUM(sod.OrderQty), 0) AS TotalQty
FROM Production.Product AS p
LEFT JOIN Sales.SalesOrderDetail AS sod
    ON sod.ProductID = p.ProductID
GROUP BY p.ProductID, p.Name
ORDER BY TotalQty DESC;
GO

-- [OBSERVE] Produtos com NULL em SaleCount nunca aparecem porque COUNT
-- de uma coluna estendida com NULL é 0, não NULL. COALESCE lida com SUM retornando NULL.

-- ====================================================================
-- Agregação condicional usando CASE
-- CONCEITO CHAVE: SUM(CASE WHEN ... THEN 1 ELSE 0 END) conta condições.
-- SUM(CASE WHEN ... THEN value ELSE 0 END) soma condicionalmente.
-- ====================================================================
-- Por cliente: total de pedidos, pedidos grandes (> $1.000) e total de pedidos grandes
SELECT TOP 10
    CustomerID,
    COUNT(*) AS AllOrders,
    SUM(CASE WHEN TotalDue > 1000 THEN 1 ELSE 0 END) AS LargeOrders,
    SUM(CASE WHEN TotalDue > 1000 THEN TotalDue ELSE 0 END) AS LargeOrdersTotal
FROM Sales.SalesOrderHeader
GROUP BY CustomerID
ORDER BY LargeOrders DESC;
GO

-- [OBSERVE] Agregação condicional responde múltiplas perguntas em uma passada.
-- Sem CASE, você precisaria de consultas separadas com filtros WHERE.

-- ====================================================================
-- GROUP BY com expressões (não apenas colunas simples)
-- CONCEITO CHAVE: Você pode agrupar por expressões calculadas como YEAR() ou LEFT().
-- ====================================================================
-- Produtos agrupados pela primeira letra do número do produto
SELECT LEFT(ProductNumber, 1) AS ProductSeries,
       COUNT(*)               AS ProductCount,
       AVG(ListPrice)         AS AvgPrice
FROM Production.Product
GROUP BY LEFT(ProductNumber, 1)
ORDER BY ProductSeries;
GO

-- ====================================================================
-- Armadilhas comuns de agregação demonstradas
-- CONCEITO CHAVE: Sempre verifique o comportamento de NULL e o grão.
-- ====================================================================

-- Armadilha 1: AVG ignora NULL, o que pode baixar a média inesperadamente.
-- Compare AVG de uma coluna com e sem NULLs.
CREATE TABLE #TestAvg (Val INT NULL);
INSERT INTO #TestAvg VALUES (10), (20), (NULL);
SELECT AVG(Val) AS AvgWithoutNullHandling,   -- 15 (ignora NULL)
       AVG(ISNULL(Val, 0)) AS AvgWithNullAsZero  -- 10 (trata NULL como 0)
FROM #TestAvg;
DROP TABLE #TestAvg;
GO

-- Armadilha 2: GROUP BY sem colunas suficientes causa erros.
-- Correto: adicione colunas não agregadas ao GROUP BY
SELECT CustomerID,
       YEAR(OrderDate) AS OrderYear,
       COUNT(*) AS OrderCount
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-01-01' AND OrderDate < '2014-01-01'
GROUP BY CustomerID, YEAR(OrderDate)
ORDER BY CustomerID, OrderYear;
GO

-- ====================================================================
-- VERIFIQUE-SE:
-- 1. Quantos produtos têm ListPrice > $100?
-- 2. Qual categoria de produto tem a maior média de ListPrice?
--    (Dica: junte Production.Product a Production.ProductSubcategory
--     a Production.ProductCategory)
-- 3. Conte pedidos por ano, mostrando apenas anos com > 5.000 pedidos.
-- 4. Escreva uma agregação condicional que conte produtos vermelhos, azuis e pretos
--    separadamente em uma consulta.
-- ====================================================================
