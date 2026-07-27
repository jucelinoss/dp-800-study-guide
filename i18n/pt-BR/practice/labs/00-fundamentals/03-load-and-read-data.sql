-- ====================================================================
-- DP-800 Guia de Estudo — Laboratório 03: Carregar e Ler Dados
-- Banco de Dados: AdventureWorks2025 (ou AdventureWorks2022, etc.)
-- Objetivo: SELECT básico, WHERE, ORDER BY, TOP, OFFSET-FETCH
-- Pré-requisito: AdventureWorks deve estar restaurado em sua instância.
--   Download: https://learn.microsoft.com/sql/samples/adventureworks-install-configure
-- ====================================================================

-- NOTA DE CONFIGURAÇÃO: Se o AdventureWorks ainda não estiver instalado, restaure
-- o backup OLTP. O schema usado aqui é padrão em todas as versões do AdventureWorks.

-- Crie schema lab para nossos objetos temporários (executa uma vez)
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'lab')
    EXEC ('CREATE SCHEMA lab');
GO

-- Verifique se você está conectado ao banco de dados correto
SELECT DB_NAME() AS current_database;
GO

-- ====================================================================
-- SELECT básico com aliases de coluna
-- CONCEITO CHAVE: Aliases (AS) tornam os nomes das colunas de saída legíveis.
-- ====================================================================
-- ESPERADO: 19972 linhas (Person.Person tem ~20k pessoas)
SELECT TOP 10 FirstName,
              MiddleName,
              LastName
FROM Person.Person
ORDER BY LastName;
GO

-- [OBSERVE] MiddleName é NULL para algumas pessoas. NULL = desconhecido/ausente.

-- ====================================================================
-- WHERE com operadores de comparação
-- CONCEITO CHAVE: WHERE filtra linhas ANTES de serem retornadas.
-- ====================================================================
-- Produtos com ListPrice acima de $1.000
-- ESPERADO: ~200 produtos
SELECT ProductID, Name, ListPrice
FROM Production.Product
WHERE ListPrice > 1000
ORDER BY ListPrice DESC;
GO

-- Produtos em categorias específicas (lista IN)
-- ESPERADO: ~40 produtos nas categorias 1, 2, 3
SELECT ProductID, Name, ProductCategoryID
FROM Production.Product
WHERE ProductCategoryID IN (1, 2, 3)
ORDER BY ProductCategoryID, Name;
GO

-- ====================================================================
-- Filtrando intervalos de data (padrão SARG)
-- CONCEITO CHAVE: Use predicados de intervalo (col >= 'data' AND col < 'data')
-- em vez de envolver a coluna em uma função (YEAR(col) = 2013).
-- Predicados de intervalo são SARGáveis (podem usar busca de índice).
-- ====================================================================
-- ESPERADO: ~7k pedidos em 2013
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-01-01' AND OrderDate < '2014-01-01'
ORDER BY OrderDate;
GO

-- ====================================================================
-- Correspondência de padrão LIKE
-- CONCEITO CHAVE: LIKE com curinga inicial (%Bike%) pode ser lento.
-- Padrões de prefixo (Bike%) são mais rápidos quando a coluna é indexada.
-- ====================================================================
-- Encontre lojas com 'Bike' no nome
-- ESPERADO: ~150 lojas
SELECT BusinessEntityID, Name
FROM Sales.Store
WHERE Name LIKE N'%Bike%'
ORDER BY Name;
GO

-- Produtos começando com 'HL' (padrão de prefixo — mais eficiente)
SELECT ProductID, Name, ListPrice
FROM Production.Product
WHERE Name LIKE N'HL%'
ORDER BY Name;
GO

-- ====================================================================
-- ORDER BY e TOP
-- CONCEITO CHAVE: TOP sem ORDER BY retorna linhas arbitrárias.
-- Sempre especifique ORDER BY ao usar TOP para resultados determinísticos.
-- ====================================================================
-- Top 5 produtos mais caros
SELECT TOP 5 Name, ListPrice
FROM Production.Product
WHERE ListPrice > 0
ORDER BY ListPrice DESC;
GO

-- ====================================================================
-- OFFSET-FETCH (paginação)
-- CONCEITO CHAVE: OFFSET pula N linhas; FETCH NEXT retorna M linhas.
-- Funciona apenas com ORDER BY. Esta é a sintaxe padrão SQL de paginação.
-- ====================================================================
-- Página 3 de produtos (linhas 21-30), ordenados por nome
SELECT ProductID, Name, ListPrice
FROM Production.Product
ORDER BY Name
OFFSET 20 ROWS
FETCH NEXT 10 ROWS ONLY;
GO

-- ====================================================================
-- DISTINCT para eliminar duplicatas
-- CONCEITO CHAVE: DISTINCT remove linhas duplicadas do resultado.
-- NÃO é um substituto para GROUP BY adequado (veja Laboratório 05).
-- ====================================================================
-- Quantos títulos de cargo diferentes existem?
SELECT DISTINCT JobTitle
FROM HumanResources.Employee
ORDER BY JobTitle;
GO

-- [OBSERVE] DISTINCT se aplica a TODAS as colunas selecionadas juntas.
-- SELECT DISTINCT City, StateProvinceID significa combinações únicas de cidade+estado.

-- ====================================================================
-- WHERE com AND, OR e parênteses
-- CONCEITO CHAVE: AND tem precedência maior que OR. Use parênteses
-- para tornar a lógica explícita e evitar bugs sutis.
-- ====================================================================
-- Produtos que são vermelhos OU pretos, E têm preço de lista > 100
SELECT ProductID, Name, Color, ListPrice
FROM Production.Product
WHERE (Color = N'Red' OR Color = N'Black')
  AND ListPrice > 100
ORDER BY ListPrice DESC;
GO

-- Produtos em intervalo de tamanho específico
SELECT ProductID, Name, Size, ListPrice
FROM Production.Product
WHERE Size BETWEEN N'M' AND N'L'
ORDER BY Size;
GO

-- ====================================================================
-- Filtragem de NULL
-- CONCEITO CHAVE: NULL = desconhecido. Use IS NULL / IS NOT NULL,
-- nunca = NULL ou != NULL (esses sempre retornam UNKNOWN).
-- ====================================================================
-- Produtos com cor conhecida vs cor desconhecida
SELECT COUNT(*) AS TotalProducts FROM Production.Product;
SELECT COUNT(*) AS WithColor FROM Production.Product WHERE Color IS NOT NULL;
SELECT COUNT(*) AS NoColor FROM Production.Product WHERE Color IS NULL;
GO

-- ====================================================================
-- VERIFIQUE-SE:
-- 1. Escreva uma consulta que retorne produtos com "HL" no número do
--    produto (não no nome), ordenados por ListPrice decrescente.
-- 2. Retorne os 10 pedidos mais recentes (por OrderDate).
-- 3. Encontre todas as pessoas cujo sobrenome começa com 'S'.
-- 4. Use OFFSET-FETCH para retornar produtos 11-20 quando ordenados por Name.
-- ====================================================================
