-- ====================================================================
-- DP-800 Guia de Estudo — Laboratório 08: Regras de Integridade
-- Banco de Dados: AdventureWorks2025
-- Objetivo: Violações FK, UNIQUE, CHECK, comportamento DEFAULT, ON DELETE
-- Pré-requisito: Laboratórios 01-07 (padrões DML)
-- ====================================================================

-- Crie schema lab se não existir (idempotente)
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'lab')
    EXEC ('CREATE SCHEMA lab');
GO

-- ====================================================================
-- Violação FK com TRY/CATCH
-- CONCEITO CHAVE: Uma FOREIGN KEY previne inserir uma linha filha quando a
-- chave pai não existe. O erro 547 é levantado.
-- ====================================================================
-- Isso sucede porque CustomerID 1 existe
SELECT CustomerID, AccountNumber FROM Sales.Customer WHERE CustomerID = 1;

BEGIN TRY
    -- Isso FALHARÁ porque CustomerID 99999 não existe
    INSERT INTO Sales.SalesOrderHeader (
        RevisionNumber, OrderDate, DueDate, ShipDate,
        CustomerID, BillToAddressID, ShipToAddressID,
        ShipMethodID
    )
    VALUES (
        1, GETDATE(), GETDATE(), GETDATE(),
        99999, 1, 1, 1
    );
END TRY
BEGIN CATCH
    PRINT 'ERRO FK ESPERADO: ' + ERROR_MESSAGE();
    PRINT 'ERROR_NUMBER: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10));
    -- 547 = violação de chave estrangeira
END CATCH;
GO

-- [OBSERVE] O bloco TRY/CATCH previne que o erro pare a execução
-- do script. Em produção, você lidaria com isso graciosamente.

-- ====================================================================
-- Violação de restrição UNIQUE
-- CONCEITO CHAVE: Uma restrição UNIQUE rejeita valores não-nulos duplicados.
-- Um NULL é permitido por coluna no SQL Server.
-- ====================================================================
CREATE TABLE #TestUnique (
    Email NVARCHAR(100) NOT NULL UNIQUE
);

INSERT INTO #TestUnique (Email) VALUES (N'test@example.com');

BEGIN TRY
    INSERT INTO #TestUnique (Email) VALUES (N'test@example.com');
END TRY
BEGIN CATCH
    PRINT 'VIOLAÇÃO UNIQUE: ' + ERROR_MESSAGE();
    PRINT 'ERROR_NUMBER: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10));
    -- 2627 = violação de restrição unique
END CATCH;
GO

-- Teste comportamento NULL: apenas um NULL permitido
CREATE TABLE #TestNullUnique (Val INT NULL UNIQUE);
INSERT INTO #TestNullUnique (Val) VALUES (NULL);  -- sucede (primeiro NULL)
BEGIN TRY
    INSERT INTO #TestNullUnique (Val) VALUES (NULL);  -- falha (segundo NULL)
END TRY
BEGIN CATCH
    PRINT 'Segundo NULL rejeitado por UNIQUE: ' + ERROR_MESSAGE();
END CATCH;

DROP TABLE #TestUnique;
DROP TABLE #TestNullUnique;
GO

-- ====================================================================
-- Violação de restrição CHECK
-- CONCEITO CHAVE: CHECK rejeita valores onde o predicado avalia para FALSE.
-- ====================================================================
CREATE TABLE #TestCheck (
    ProductName NVARCHAR(100) NOT NULL,
    ListPrice   DECIMAL(10,2) NOT NULL CHECK (ListPrice >= 0)
);

-- Isso sucede
INSERT INTO #TestCheck (ProductName, ListPrice) VALUES (N'Valid Product', 19.99);

BEGIN TRY
    -- Isso falha: preço negativo
    INSERT INTO #TestCheck (ProductName, ListPrice) VALUES (N'Bad Product', -5.00);
END TRY
BEGIN CATCH
    PRINT 'VIOLAÇÃO CHECK: ' + ERROR_MESSAGE();
END CATCH;

DROP TABLE #TestCheck;
GO

-- ====================================================================
-- CHECK + comportamento NULL (UNKNOWN != FALSE)
-- CONCEITO CHAVE: Um CHECK passa quando o predicado é TRUE ou UNKNOWN.
-- Comparação NULL produz UNKNOWN, então NULL passa no CHECK.
-- ====================================================================
CREATE TABLE #TestCheckNull (
    Val DECIMAL(10,2) NULL CHECK (Val >= 0)
);

-- Isso passa porque NULL >= 0 é UNKNOWN, não FALSE
INSERT INTO #TestCheckNull (Val) VALUES (NULL);
PRINT 'NULL passou no CHECK (UNKNOWN != FALSE)';

BEGIN TRY
    INSERT INTO #TestCheckNull (Val) VALUES (-5.00);
END TRY
BEGIN CATCH
    PRINT 'VIOLAÇÃO CHECK: ' + ERROR_MESSAGE();
END CATCH;

DROP TABLE #TestCheckNull;
GO

-- ====================================================================
-- DEFAULT vs INSERT NULL
-- CONCEITO CHAVE: DEFAULT é acionado apenas quando a coluna é OMITIDA da
-- lista de colunas do INSERT. Passar NULL explicitamente insere NULL.
-- ====================================================================
CREATE TABLE #TestDefault (
    Id        INT IDENTITY(1,1) PRIMARY KEY,
    Status    NVARCHAR(20) NOT NULL DEFAULT (N'Active'),
    CreatedAt DATETIME2 NOT NULL DEFAULT (SYSDATETIME())
);

-- Omita Status e CreatedAt — ambos usam DEFAULT
INSERT INTO #TestDefault (Id) VALUES (DEFAULT);  -- usa DEFAULT do IDENTITY
PRINT 'Insert 1: Status e CreatedAt usaram defaults.';

-- Inserir explicitamente NULL em uma coluna NOT NULL — FALHARÁ
-- INSERT INTO #TestDefault (Status) VALUES (NULL);  -- descomente para ver erro

-- Insert com valor explícito não-nulo (default NÃO é usado)
INSERT INTO #TestDefault (Status, CreatedAt) VALUES (N'Inactive', '2026-01-01');
PRINT 'Insert 2: valores explícitos usados, defaults ignorados.';

SELECT * FROM #TestDefault;
DROP TABLE #TestDefault;
GO

-- ====================================================================
-- ON DELETE CASCADE (conceitual — tabela de laboratório)
-- CONCEITO CHAVE: CASCADE automaticamente exclui linhas filhas quando o pai
-- é excluído. Use com cuidado — pode encadear através de múltiplas tabelas.
-- ====================================================================
CREATE TABLE lab.Parent (
    ParentId INT NOT NULL PRIMARY KEY,
    Name     NVARCHAR(50) NOT NULL
);

CREATE TABLE lab.Child (
    ChildId  INT NOT NULL PRIMARY KEY,
    ParentId INT NOT NULL,
    Value    NVARCHAR(50) NOT NULL,
    CONSTRAINT FK_Child_Parent
        FOREIGN KEY (ParentId) REFERENCES lab.Parent(ParentId)
        ON DELETE CASCADE
);

INSERT INTO lab.Parent (ParentId, Name) VALUES (1, N'Group A');
INSERT INTO lab.Child (ChildId, ParentId, Value) VALUES (1, 1, N'Item 1');
INSERT INTO lab.Child (ChildId, ParentId, Value) VALUES (2, 1, N'Item 2');

-- Verifique que tanto pais quanto filhos existem
SELECT 'Antes de excluir:', p.Name, c.Value
FROM lab.Parent AS p
INNER JOIN lab.Child AS c ON c.ParentId = p.ParentId;

-- Exclua o pai — filho é cascateado
DELETE FROM lab.Parent WHERE ParentId = 1;

-- Verifique: tanto pai quanto filhos desapareceram
SELECT 'Após excluir:', COUNT(*) AS ParentCount FROM lab.Parent;
SELECT 'Após excluir:', COUNT(*) AS ChildCount FROM lab.Child;

-- Limpeza
DROP TABLE IF EXISTS lab.Child;
DROP TABLE IF EXISTS lab.Parent;
GO

-- ====================================================================
-- VERIFIQUE-SE:
-- 1. O que acontece quando você insere NULL em uma coluna CHECK (col > 0)
--    que é anulável? E se a coluna for NOT NULL?
-- 2. Crie uma restrição UNIQUE em uma tabela temporária, insira um valor,
--    então tente inserir o mesmo valor novamente. Capture o erro.
-- 3. Explique a diferença entre DEFAULT sendo acionado vs não sendo acionado.
-- 4. O que ON DELETE CASCADE faz? Por que deve ser usado com cuidado?
-- ====================================================================
