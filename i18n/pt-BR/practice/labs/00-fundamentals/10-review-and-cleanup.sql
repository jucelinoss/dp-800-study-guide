-- ====================================================================
-- DP-800 Guia de Estudo — Laboratório 10: Revisão Final e Limpeza
-- Banco de Dados: AdventureWorks2025
-- Objetivo: Revisão de agregação multi-join + CTE bônus
-- ====================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/00-fundamentals/10-index-fundamentals.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.

-- ====================================================================
-- REVISÃO FINAL: Agregação multi-join
-- Pergunta de negócio: "Mostre cada território com vendas totais, contagem de
-- pedidos e valor médio do pedido, ordenados por vendas totais decrescente."
-- ====================================================================
SELECT st.Name AS Territory,
       COUNT(soh.SalesOrderID) AS OrderCount,
       SUM(soh.TotalDue)       AS TotalSales,
       AVG(soh.TotalDue)       AS AvgOrderValue
FROM Sales.SalesTerritory AS st
INNER JOIN Sales.Customer AS c
    ON c.TerritoryID = st.TerritoryID
INNER JOIN Sales.SalesOrderHeader AS soh
    ON soh.CustomerID = c.CustomerID
GROUP BY st.Name
ORDER BY TotalSales DESC;
GO

-- [OBSERVE] Esta consulta combina 3 JOINs + agregação. Cada território
-- aparece uma vez (grão = território), com estatísticas de pedido agregadas.

-- ====================================================================
-- BÔNUS: Mesma consulta com CTE
-- CONCEITO CHAVE: Uma CTE torna a lógica de múltiplas etapas mais fácil de ler.
-- ====================================================================
WITH TerritorySales AS (
    SELECT c.TerritoryID,
           COUNT(soh.SalesOrderID) AS OrderCount,
           SUM(soh.TotalDue)       AS TotalSales,
           AVG(soh.TotalDue)       AS AvgOrderValue
    FROM Sales.Customer AS c
    INNER JOIN Sales.SalesOrderHeader AS soh
        ON soh.CustomerID = c.CustomerID
    GROUP BY c.TerritoryID
)
SELECT st.Name AS Territory,
       ts.OrderCount,
       ts.TotalSales,
       ts.AvgOrderValue
FROM TerritorySales AS ts
INNER JOIN Sales.SalesTerritory AS st
    ON st.TerritoryID = ts.TerritoryID
ORDER BY ts.TotalSales DESC;
GO

-- [OBSERVE] A CTE separa a lógica de agregação do SELECT final
-- com nomes de território. Isso é mais fácil de ler e depurar.

-- ====================================================================
-- O que você aprendeu na Parte 0 — Fundamentos:
-- ====================================================================
-- 1. Criar banco de dados, schema, tabelas com restrições (Labs 01-02 / StudyDB)
-- 2. SELECT, WHERE, ORDER BY, TOP com dados reais (Lab 03 / AdventureWorks)
-- 3. INNER JOIN, LEFT JOIN, CROSS JOIN, self-join (Lab 04)
-- 4. Agregação: COUNT, SUM, AVG, GROUP BY, HAVING (Lab 05)
-- 5. Derived tables, CTEs, temp tables, table variables (Lab 06)
-- 6. DML seguro com transações, OUTPUT, @@ROWCOUNT (Lab 07)
-- 7. Regras de integridade: PK, FK, UNIQUE, CHECK, DEFAULT (Lab 08)
-- 8. Fundamentos de índices: seek vs scan, STATISTICS IO (Lab 09)

PRINT 'Parabéns! Você completou a Parte 0 — Fundamentos.';
PRINT 'Você está pronto para prosseguir para as seções do exame DP-800.';
GO

-- ====================================================================
-- LIMPEZA OPCIONAL: Excluir StudyDB (se não for mais necessário)
-- Remova os comentários abaixo para excluir o banco de dados StudyDB.
-- ====================================================================
-- USE master;
-- GO
-- IF DB_ID(N'StudyDB') IS NOT NULL
-- BEGIN
--     ALTER DATABASE StudyDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
--     DROP DATABASE StudyDB;
-- END;
-- GO
-- PRINT 'StudyDB foi removido.';
-- GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/00-fundamentals/10-index-fundamentals.md
-- =================================================================================================
