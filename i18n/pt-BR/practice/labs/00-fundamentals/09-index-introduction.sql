-- ====================================================================
-- DP-800 Guia de Estudo — Laboratório 09: Introdução a Índices
-- Banco de Dados: AdventureWorks2025
-- Objetivo: STATISTICS IO, CREATE INDEX, medir antes/depois, covering
-- Pré-requisito: Laboratórios 01-08 (padrões DML e consulta)
-- ====================================================================

-- ====================================================================
-- PARTE 1: Meça a linha de base (sem índice direcionado)
-- CONCEITO CHAVE: STATISTICS IO mostra leituras lógicas — páginas lidas do cache.
-- Menos leituras lógicas geralmente significa menos trabalho para a consulta.
-- ====================================================================
SET STATISTICS IO ON;

-- [OBSERVE] Anote as leituras lógicas na aba Mensagens.
-- Sem um índice direcionado, o SQL Server pode escanear a tabela inteira.
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';
GO

-- [NOTA] Anote o número de leituras lógicas da aba Mensagens.
-- Se a tabela for pequena, a diferença pode ser modesta, mas a
-- técnica de medição é o que importa.

-- ====================================================================
-- PARTE 2: Crie um índice direcionado (idempotente)
-- CONCEITO CHAVE: DROP INDEX IF EXISTS torna o script seguro para reexecutar.
-- ====================================================================
DROP INDEX IF EXISTS IX_Lab_SalesOrderHeader_OrderDate
    ON Sales.SalesOrderHeader;
GO

CREATE INDEX IX_Lab_SalesOrderHeader_OrderDate
    ON Sales.SalesOrderHeader (OrderDate);
GO

PRINT 'Índice IX_Lab_SalesOrderHeader_OrderDate criado.';
GO

-- ====================================================================
-- PARTE 3: Meça com o novo índice
-- CONCEITO CHAVE: Compare leituras lógicas com a linha de base acima.
-- Um índice bem utilizado deve mostrar menos leituras lógicas.
-- ====================================================================
-- Execute a mesma consulta novamente
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';
GO

-- [OBSERVE] Compare as leituras lógicas da aba Mensagens
-- com as da PARTE 1. A redução é o benefício do índice.

SET STATISTICS IO OFF;
GO

-- ====================================================================
-- PARTE 4: Inspecione metadados do índice
-- CONCEITO CHAVE: sys.indexes mostra todos os índices em uma tabela incluindo
-- aqueles criados por restrições (PK, UNIQUE).
-- ====================================================================
SELECT i.name          AS index_name,
       i.type_desc     AS index_type,
       i.is_unique,
       i.is_primary_key,
       i.fill_factor
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'Sales.SalesOrderHeader')
ORDER BY i.type;
GO

-- [OBSERVE] Você deve ver o índice PK clusterizado e o novo
-- índice não clusterizado. Note que type_desc os distingue.

-- ====================================================================
-- PARTE 5: Clusterizado vs não clusterizado na prática
-- CONCEITO CHAVE: O índice clusterizado define a ordem física das linhas.
-- Um índice não clusterizado aponta de volta para a chave clusterizada.
-- ====================================================================
-- Consulta que se beneficia do índice clusterizado (scan em ordem PK)
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
ORDER BY SalesOrderID;
GO

-- Consulta que se beneficia do índice não clusterizado que criamos
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';
GO

-- ====================================================================
-- PARTE 6: Covering index (conceito)
-- CONCEITO CHAVE: Quando TODAS as colunas na consulta estão no índice,
-- o SQL Server pode responder apenas do índice (sem Key Lookup).
-- ====================================================================
-- Crie um índice que cubra esta consulta específica
DROP INDEX IF EXISTS IX_Lab_Covering_Test
    ON Sales.SalesOrderHeader;
GO

CREATE INDEX IX_Lab_Covering_Test
    ON Sales.SalesOrderHeader (OrderDate)
    INCLUDE (TotalDue, SubTotal, TaxAmt);
GO

PRINT 'Covering index IX_Lab_Covering_Test criado.';
GO

-- Meça: esta consulta pode ser respondida inteiramente do índice
SET STATISTICS IO ON;

SELECT OrderDate, TotalDue, SubTotal, TaxAmt
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';
GO

SET STATISTICS IO OFF;
GO

-- [OBSERVE] As colunas INCLUDE são armazenadas no nível folha mas
-- não participam da navegação do índice. Elas existem apenas para fazer
-- o índice "cobrir" a consulta e evitar key lookups.

-- ====================================================================
-- PARTE 7: Impacto do índice em escritas (conceitual)
-- CONCEITO CHAVE: Cada índice adiciona custo a INSERT, UPDATE, DELETE.
-- ====================================================================
-- Crie uma tabela temporária com e sem índices para demonstrar
CREATE TABLE #TestWrite (
    Id    INT NOT NULL,
    Value NVARCHAR(100) NOT NULL
);

-- Insira 1000 linhas em uma tabela SEM índices
DECLARE @i INT = 1;
WHILE @i <= 1000
BEGIN
    INSERT INTO #TestWrite (Id, Value)
    VALUES (@i, N'Row ' + CAST(@i AS NVARCHAR(10)));
    SET @i = @i + 1;
END;
PRINT 'Inseridas 1000 linhas em heap (sem índices).';

-- Agora adicione um índice
CREATE INDEX IX_TestWrite_Id ON #TestWrite (Id);

-- Insira mais 1000 linhas (mais lento devido à manutenção do índice)
SET @i = 1001;
WHILE @i <= 2000
BEGIN
    INSERT INTO #TestWrite (Id, Value)
    VALUES (@i, N'Row ' + CAST(@i AS NVARCHAR(10)));
    SET @i = @i + 1;
END;
PRINT 'Inseridas mais 1000 linhas na tabela indexada.';

DROP TABLE IF EXISTS #TestWrite;
GO

-- [OBSERVE] O segundo insert é mais lento porque cada linha também deve
-- ser escrita no índice IX_TestWrite_Id. Mais índices = escritas mais lentas.

-- ====================================================================
-- Limpeza dos índices do laboratório
-- CONCEITO CHAVE: Remova os índices criados neste laboratório para que não
-- afetem laboratórios futuros ou planos de consulta de produção.
-- ====================================================================
DROP INDEX IF EXISTS IX_Lab_SalesOrderHeader_OrderDate
    ON Sales.SalesOrderHeader;
DROP INDEX IF EXISTS IX_Lab_Covering_Test
    ON Sales.SalesOrderHeader;
GO

PRINT 'Índices do laboratório limpos. Veja o Laboratório 09 para fundamentos de índices.';
GO

-- ====================================================================
-- VERIFIQUE-SE:
-- 1. Crie um índice para acelerar uma consulta filtrando por DueDate.
-- 2. Use sys.indexes para verificar se um índice é clusterizado ou não clusterizado.
-- 3. O que acontece com as leituras lógicas quando você adiciona um covering index?
-- 4. Por que cada índice adicional diminui as operações de INSERT?
-- ====================================================================
