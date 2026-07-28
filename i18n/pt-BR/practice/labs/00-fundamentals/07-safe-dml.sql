-- ====================================================================
-- DP-800 Guia de Estudo — Laboratório 07: DML Seguro
-- Banco de Dados: AdventureWorks2025
-- Objetivo: UPDATE, DELETE, cláusula OUTPUT, transações, @@ROWCOUNT
-- Pré-requisito: Laboratórios 01-06 (familiaridade com schema AdventureWorks)
-- ====================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/00-fundamentals/07-change-data-safely.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.

-- ATENÇÃO: Este laboratório usa BEGIN TRAN / ROLLBACK para prevenir alterações
-- permanentes. Substitua ROLLBACK por COMMIT apenas quando pretender salvar.

-- ====================================================================
-- UPDATE com transação: SELECT primeiro, depois UPDATE
-- CONCEITO CHAVE: Sempre pré-visualize as linhas que você alterará dentro de uma
-- transação para que possa ROLLBACK se as linhas erradas forem afetadas.
-- ====================================================================
BEGIN TRAN;
    -- Passo 1: Pré-visualize as linhas que serão alteradas
    SELECT ProductID, Name, ListPrice
    FROM Production.Product
    WHERE Name LIKE N'%HL Road%';

    -- Passo 2: Aplique a alteração (aumento de 5% no preço)
    UPDATE Production.Product
    SET ListPrice = ListPrice * 1.05
    WHERE Name LIKE N'%HL Road%';

    -- Passo 3: Verifique a alteração (leia seus próprios dados não confirmados)
    SELECT ProductID, Name, ListPrice
    FROM Production.Product
    WHERE Name LIKE N'%HL Road%';

    -- Passo 4: Imprima quantas linhas foram afetadas
    PRINT 'Linhas atualizadas: ' + CAST(@@ROWCOUNT AS NVARCHAR(10));
ROLLBACK;  -- Desfaz a alteração. Substitua por COMMIT quando pronto para persistir.
GO

-- [OBSERVE] Após ROLLBACK, os dados voltam ao estado original.
-- Sempre verifique se você selecionou as linhas corretas antes de UPDATE.

-- ====================================================================
-- DELETE com transação
-- CONCEITO CHAVE: O mesmo padrão SELECT-primeiro se aplica. DELETE é registrado
-- no log e pode ser revertido dentro de uma transação.
-- ====================================================================
BEGIN TRAN;
    -- Pré-visualize linhas a excluir (um subconjunto de endereços)
    SELECT TOP 5 AddressID, AddressLine1, City
    FROM Person.Address
    WHERE City = N'Paris'
    ORDER BY AddressID;

    -- Exclua apenas um endereço específico (por segurança)
    DELETE FROM Person.Address
    WHERE AddressID = 1;  -- Pode falhar devido a restrições FK

    PRINT 'Linhas excluídas: ' + CAST(@@ROWCOUNT AS NVARCHAR(10));

    -- Verifique o que resta
    SELECT AddressID, AddressLine1, City
    FROM Person.Address
    WHERE City = N'Paris';
ROLLBACK;
GO

-- [OBSERVE] Se o DELETE falhar devido a uma restrição FK (erro 547),
-- a transação ainda está ativa. Use BEGIN TRY/CATCH em produção.

-- ====================================================================
-- @@ROWCOUNT para verificar linhas afetadas
-- CONCEITO CHAVE: @@ROWCOUNT retorna o número de linhas afetadas pela
-- ÚLTIMA instrução. Verifique após cada DML para confirmar a intenção.
-- ====================================================================
BEGIN TRAN;
    -- Atualize um produto conhecido
    UPDATE Production.Product
    SET ListPrice = ListPrice * 1.10
    WHERE ProductID = 750;

    -- Verifique quantas linhas mudaram
    IF @@ROWCOUNT = 0
        PRINT 'AVISO: Nenhuma linha atualizada. Verifique sua cláusula WHERE.';
    ELSE IF @@ROWCOUNT = 1
        PRINT 'OK: 1 linha atualizada como esperado.';
    ELSE
        PRINT 'INESPERADO: ' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + ' linhas atualizadas.';
ROLLBACK;
GO

-- ====================================================================
-- Cláusula OUTPUT para capturar alterações
-- CONCEITO CHAVE: OUTPUT retorna os valores antigos (deleted) e novos (inserted).
-- Útil para logs de auditoria, controle de alterações ou confirmação.
-- ====================================================================
BEGIN TRAN;
    -- Atualize preço com OUTPUT
    UPDATE Production.Product
    SET ListPrice = ListPrice * 1.10
    OUTPUT deleted.ProductID,
           deleted.Name,
           deleted.ListPrice AS OldPrice,
           inserted.ListPrice AS NewPrice
    WHERE ProductID = 750;
ROLLBACK;
GO

-- [OBSERVE] A cláusula OUTPUT mostra os valores antes e depois na
-- grade de resultados. Não há necessidade de um SELECT separado para verificar.

-- OUTPUT com DELETE
BEGIN TRAN;
    -- Exclua uma linha de detalhe de pedido com OUTPUT
    DELETE FROM Sales.SalesOrderDetail
    OUTPUT deleted.SalesOrderDetailID,
           deleted.ProductID,
           deleted.OrderQty,
           deleted.LineTotal
    WHERE SalesOrderDetailID = 1;
ROLLBACK;
GO

-- ====================================================================
-- DELETE vs TRUNCATE
-- CONCEITO CHAVE: DELETE registra cada linha (pode ter WHERE, pode reverter).
-- TRUNCATE registra minimamente (sem WHERE, reseta identity, mais rápido).
-- ====================================================================
CREATE TABLE #Demo (
    Id    INT IDENTITY(1,1) PRIMARY KEY,
    Value NVARCHAR(10)
);

INSERT INTO #Demo (Value) VALUES ('A'), ('B'), ('C');

-- DELETE com WHERE (registrado por linha)
DELETE FROM #Demo WHERE Value = 'B';
PRINT 'Após DELETE: ' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + ' linha(s) excluída(s).';

-- TRUNCATE (registro mínimo, reset de identity)
TRUNCATE TABLE #Demo;
PRINT 'Após TRUNCATE: tabela vazia, contador de identity resetado.';

-- Verifique: próximo insert recebe ID = 1 (não 4)
INSERT INTO #Demo (Value) VALUES ('D');
SELECT * FROM #Demo;

DROP TABLE IF EXISTS #Demo;
GO

-- [OBSERVE] Após TRUNCATE, o contador IDENTITY é resetado.
-- Após DELETE, o contador continua de onde parou.

-- ====================================================================
-- BEGIN TRY / CATCH para segurança de DML
-- CONCEITO CHAVE: Envolva DML em TRY/CATCH para lidar com erros graciosamente.
-- ====================================================================
BEGIN TRY
    BEGIN TRAN;
        -- Cause intencionalmente uma violação de FK
        DELETE FROM Sales.Customer WHERE CustomerID = 1;
    COMMIT;
END TRY
BEGIN CATCH
    ROLLBACK;
    PRINT 'ERRO: ' + ERROR_MESSAGE();
    PRINT 'Transação revertida. Nenhum dado foi danificado.';
END CATCH;
GO

-- ====================================================================
-- VERIFIQUE-SE:
-- 1. Atualize o ListPrice de um produto específico em 10% dentro de uma transação
--    e reverta. Use OUTPUT para capturar os preços antigo e novo.
-- 2. Explique por que você deve sempre executar SELECT antes de DELETE ou UPDATE.
-- 3. Qual é a diferença entre DELETE e TRUNCATE em termos de
--    registro, suporte a WHERE e reset de identity?
-- 4. Escreva um bloco TRY/CATCH em torno de um UPDATE que pode falhar.
-- ====================================================================

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/00-fundamentals/07-change-data-safely.md
-- =================================================================================================
