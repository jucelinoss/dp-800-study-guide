-- ====================================================================
-- DP-800 Guia de Estudo — Laboratório 04: JOINs
-- Banco de Dados: AdventureWorks2025
-- Objetivo: INNER, LEFT, RIGHT, CROSS JOIN, self-join, multi-join
-- Pré-requisito: Laboratórios 01-03 (não obrigatório, mas contexto recomendado)
-- ====================================================================

-- ====================================================================
-- INNER JOIN: apenas linhas correspondentes de ambos os lados
-- CONCEITO CHAVE: Ambos os lados devem corresponder. Linhas sem correspondência são excluídas.
-- ====================================================================
-- ESPERADO: ~31k linhas (uma por pedido)
SELECT soh.SalesOrderID,
       soh.OrderDate,
       c.AccountNumber
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c
    ON c.CustomerID = soh.CustomerID;
GO

-- [OBSERVE] Todo pedido tem um cliente (FK garante isso), então INNER JOIN
-- retorna todos os pedidos. Se um cliente tivesse sido excluído, esse pedido não
-- apareceria — mas a FK previne pedidos órfãos.

-- ====================================================================
-- LEFT JOIN: preserva todas as linhas da tabela esquerda
-- CONCEITO CHAVE: Todos os produtos sobrevivem, mesmo que nunca pedidos.
-- Colunas do lado direito não correspondidas aparecem como NULL.
-- ====================================================================
-- ESPERADO: Todos os 504 produtos, alguns com NULL na data de venda
SELECT p.ProductID, p.Name, MAX(sod.ModifiedDate) AS LastSale
FROM Production.Product AS p
LEFT JOIN Sales.SalesOrderDetail AS sod
    ON sod.ProductID = p.ProductID
GROUP BY p.ProductID, p.Name
ORDER BY LastSale DESC;
GO

-- [OBSERVE] Produtos nunca vendidos têm NULL em LastSale. O LEFT JOIN
-- os preservou. Se fosse INNER JOIN, produtos não vendidos estariam ausentes.

-- ====================================================================
-- RIGHT JOIN: preserva todas as linhas da tabela direita
-- CONCEITO CHAVE: RIGHT JOIN é menos comum. Geralmente reescreva como LEFT JOIN
-- trocando a ordem das tabelas para consistência.
-- ====================================================================
-- Mesmo que a consulta anterior, mas com sintaxe RIGHT JOIN
SELECT p.ProductID, p.Name, MAX(sod.ModifiedDate) AS LastSale
FROM Sales.SalesOrderDetail AS sod
RIGHT JOIN Production.Product AS p
    ON sod.ProductID = p.ProductID
GROUP BY p.ProductID, p.Name
ORDER BY LastSale DESC;
GO

-- [OBSERVE] RIGHT JOIN preserva a tabela direita (Product). O resultado
-- é idêntico ao LEFT JOIN acima. A maioria dos desenvolvedores prefere LEFT JOIN
-- para legibilidade.

-- ====================================================================
-- CROSS JOIN: toda combinação (produto cartesiano)
-- CONCEITO CHAVE: Sem cláusula ON. Cada linha da esquerda corresponde a cada linha
-- da direita. Use deliberadamente — nunca acidentalmente.
-- ====================================================================
-- ATENÇÃO: Isso retorna 504 × 3 = 1512 linhas
SELECT p.Name AS Product, c.Name AS Category
FROM Production.Product AS p
CROSS JOIN Production.ProductCategory AS c;
GO

-- [OBSERVE] CROSS JOIN é útil para gerar combinações (ex.:
-- todos os produtos × todas as lojas). Sem um filtro WHERE, ele multiplica.

-- CROSS JOIN com filtro WHERE para demonstrar uso seguro
SELECT p.Name AS Product, c.Name AS Category
FROM Production.Product AS p
CROSS JOIN Production.ProductCategory AS c
WHERE p.ProductCategoryID = c.ProductCategoryID;
GO

-- [OBSERVE] Adicionar um WHERE transformou isto em um INNER JOIN equivalente.
-- Sempre prefira sintaxe explícita JOIN...ON para evitar produtos cartesianos acidentais.

-- ====================================================================
-- Self-join: mesma tabela, aliases diferentes
-- CONCEITO CHAVE: Útil para hierarquias (gerente → funcionário, categoria → pai).
-- ====================================================================
-- Funcionários e seus gerentes usando hierarquia OrganizationNode.
-- GetAncestor(1) retorna o nó pai um nível acima.
SELECT emp.JobTitle AS Employee,
       mgr.LoginID  AS ManagerLogin
FROM HumanResources.Employee AS emp
LEFT JOIN HumanResources.Employee AS mgr
    ON emp.OrganizationNode.GetAncestor(1) = mgr.OrganizationNode;
GO

-- [OBSERVE] O CEO não tem gerente (NULL). Este padrão de self-join
-- funciona para qualquer hierarquia de lista de adjacência.

-- ====================================================================
-- Multi-join: 3+ tabelas
-- CONCEITO CHAVE: Cada JOIN combina o resultado anterior com uma nova tabela.
-- Misturar INNER e OUTER joins pode descartar linhas inesperadamente (veja teoria).
-- ====================================================================
-- Pedido → Cliente → Território
-- ESPERADO: ~31k linhas (mesmo que INNER JOIN acima, mas com nome do território)
SELECT soh.SalesOrderID,
       soh.OrderDate,
       c.AccountNumber,
       st.Name AS Territory
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c
    ON c.CustomerID = soh.CustomerID
INNER JOIN Sales.SalesTerritory AS st
    ON st.TerritoryID = c.TerritoryID;
GO

-- [OBSERVE] A consulta flui: pedidos → clientes → territórios.
-- Cada INNER JOIN requer uma correspondência, então apenas clientes com um território sobrevivem.

-- Multi-join com LEFT JOIN para preservar todos os pedidos
-- ESPERADO: ~31k linhas, Territory pode ser NULL se cliente não tem território
SELECT soh.SalesOrderID,
       soh.OrderDate,
       c.AccountNumber,
       st.Name AS Territory
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c
    ON c.CustomerID = soh.CustomerID
LEFT JOIN Sales.SalesTerritory AS st
    ON st.TerritoryID = c.TerritoryID;
GO

-- [OBSERVE] Misturando INNER e LEFT JOIN: pedidos são correspondidos a clientes
-- (INNER), mas um território ausente não remove a linha (LEFT).

-- ====================================================================
-- ON vs WHERE em outer joins
-- CONCEITO CHAVE: ON controla quais linhas correspondem; WHERE filtra o resultado.
-- Para outer joins, mover uma condição de ON para WHERE pode mudar a preservação
-- de linhas (removendo linhas estendidas com NULL).
-- ====================================================================
-- LEFT JOIN: filtrar no ON (preserva todos os produtos)
SELECT p.Name, sod.SalesOrderID
FROM Production.Product AS p
LEFT JOIN Sales.SalesOrderDetail AS sod
    ON sod.ProductID = p.ProductID
   AND sod.OrderQty > 10
ORDER BY p.Name;
GO

-- Mesma consulta: filtrar no WHERE (remove produtos sem detalhe de pedido correspondente)
SELECT p.Name, sod.SalesOrderID
FROM Production.Product AS p
LEFT JOIN Sales.SalesOrderDetail AS sod
    ON sod.ProductID = p.ProductID
WHERE sod.OrderQty > 10
ORDER BY p.Name;
GO

-- [OBSERVE] A primeira consulta mantém TODOS os produtos (NULL se sem correspondência ou qty <= 10).
-- A segunda consulta remove produtos que não corresponderam — efetivamente um INNER JOIN.

-- ====================================================================
-- VERIFIQUE-SE:
-- 1. Liste todos os clientes e sua data do último pedido
--    (inclua clientes SEM pedidos — use AccountNumber).
-- 2. Encontre produtos que nunca foram vendidos
--    (LEFT JOIN + verificação de WHERE NULL em SalesOrderDetail).
-- 3. Quais territórios de venda não têm clientes?
--    (Sales.SalesTerritory LEFT JOIN Sales.Customer).
-- 4. Escreva uma consulta self-join para encontrar subcategorias de produto e suas
--    categorias pai (ProductSubcategory LEFT JOIN consigo mesma, ou
--    junte ProductSubcategory a ProductCategory).
-- ====================================================================
