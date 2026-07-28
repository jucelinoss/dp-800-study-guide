-- =============================================================================
-- DP-800 - LAB PRÁTICO: FUNÇÕES JSON COM ADVENTUREWORKS2025
-- Pré-requisito: AdventureWorks2025; OPENJSON exige compatibilidade 130+.
-- O script cria/altera somente objetos lab.JsonFunctions....
-- Objetivo: extrair, validar, decompor, modificar e serializar documentos JSON.
-- Habilite o plano REAL nas Partes 3 e 6; anote linhas estimadas/reais, leituras,
-- CPU, memória e operadores. Modelagem e índices são aprofundados no Lab 01.
-- =============================================================================

USE AdventureWorks2025;
GO

-- Obrigatórias para o índice em coluna computada da Parte 6.
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
IF SCHEMA_ID(N'lab') IS NULL EXEC(N'CREATE SCHEMA lab');
GO
DROP TABLE IF EXISTS lab.JsonFunctionsStage;
DROP TABLE IF EXISTS lab.JsonFunctionsOrders;
DROP TABLE IF EXISTS lab.JsonFunctionsClientes;
DROP TABLE IF EXISTS lab.JsonFunctionsMapping;
DROP TABLE IF EXISTS lab.JsonFunctionsProductAttributes;
DROP PROCEDURE IF EXISTS lab.usp_JsonFunctionsProjection;
GO

CREATE TABLE lab.JsonFunctionsOrders
(
    SalesOrderID int NOT NULL CONSTRAINT PK_JsonFunctionsOrders PRIMARY KEY,
    OrderDate datetime NOT NULL,
    OrderDocument nvarchar(max) NOT NULL,
    CONSTRAINT CK_JsonFunctionsOrders_Document CHECK (ISJSON(OrderDocument) = 1)
);
GO

-- PARTE 1: CONSTRUIR DOCUMENTOS A PARTIR DE PEDIDOS, PRODUTOS E ENDEREÇOS REAIS
-- O documento representa uma visão de integração. As tabelas AdventureWorks são
-- a fonte de verdade e não são alteradas; o objeto lab torna o lab repetível.
INSERT INTO lab.JsonFunctionsOrders (SalesOrderID, OrderDate, OrderDocument)
SELECT TOP (1000) h.SalesOrderID, h.OrderDate,
    (
        SELECT h.SalesOrderNumber AS [order.number], st.Name AS [territory.name],
               a.City AS [shipping.city],
               JSON_QUERY((
                    SELECT p.ProductNumber AS [sku], p.Name AS [name],
                           d.OrderQty AS [qty], d.UnitPrice AS [price]
                    FROM Sales.SalesOrderDetail AS d
                    JOIN Production.Product AS p ON p.ProductID = d.ProductID
                    WHERE d.SalesOrderID = h.SalesOrderID FOR JSON PATH
               )) AS [items]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )
FROM Sales.SalesOrderHeader AS h
JOIN Sales.SalesTerritory AS st ON st.TerritoryID = h.TerritoryID
JOIN Person.Address AS a ON a.AddressID = h.ShipToAddressID
ORDER BY h.SalesOrderID;

-- Linha controlada para comparar CROSS APPLY e OUTER APPLY com array vazio.
INSERT INTO lab.JsonFunctionsOrders (SalesOrderID, OrderDate, OrderDocument)
VALUES (-1, GETDATE(), N'{"order":{"number":"LAB-EMPTY"},"territory":{"name":"Lab"},"items":[]}');
GO

-- Resultado esperado: 1.001 documentos; o pedido -1 existe apenas para expor a
-- diferença semântica entre CROSS APPLY (remove a linha) e OUTER APPLY (preserva).
SELECT COUNT(*) AS Documentos,
       SUM(CASE WHEN SalesOrderID = -1 THEN 1 ELSE 0 END) AS DocumentosComArrayVazio
FROM lab.JsonFunctionsOrders;
GO

-- PARTE 2: JSON_VALUE, JSON_QUERY, CAMINHOS E LAX/STRICT
-- JSON_VALUE serve valores escalares e retorna nvarchar(4000). JSON_QUERY devolve
-- objetos/arrays. Resultado esperado: WrongScalar = NULL e ItemsArray contém [].
SELECT TOP (5)
    JSON_VALUE(OrderDocument, '$.order.number') AS OrderNumber,
    JSON_VALUE(OrderDocument, '$.shipping.city') AS ShipCity,
    JSON_VALUE(OrderDocument, '$.items') AS WrongScalar,
    JSON_QUERY(OrderDocument, '$.items') AS ItemsArray
FROM lab.JsonFunctionsOrders WHERE SalesOrderID > 0;

DECLARE @doc nvarchar(max) = N'{"customer":{"name":"Ada"},"address line":"One"}';
SELECT JSON_VALUE(@doc, '$."address line"') AS QuotedKey,
       JSON_VALUE(@doc, 'lax $.missing') AS LaxMissing;
BEGIN TRY
    SELECT JSON_VALUE(@doc, 'strict $.missing') AS StrictMissing;
END TRY
BEGIN CATCH
    PRINT N'Erro strict esperado: ' + ERROR_MESSAGE();
END CATCH;
GO
-- JSON_VALUE retorna nvarchar(4000); use OPENJSON para escalar maior que esse limite.
-- Em produção, strict é adequado quando a propriedade é contratual; em ingestão,
-- primeiro faça triagem em lax para não interromper o lote inteiro no primeiro erro.

-- PARTE 3: OPENJSON PADRÃO/WITH/AS JSON E APPLY
-- OPENJSON padrão revela key/value/type. WITH projeta tipos e paths; AS JSON
-- preserva um objeto/array para uma segunda etapa de parsing.
DECLARE @oneOrder nvarchar(max) =
    (SELECT TOP (1) OrderDocument FROM lab.JsonFunctionsOrders WHERE SalesOrderID > 0);
SELECT [key], [value], [type] FROM OPENJSON(@oneOrder);
SELECT OrderNumber, Territory, Items
FROM OPENJSON(@oneOrder)
WITH (OrderNumber nvarchar(25) '$.order.number', Territory nvarchar(50) '$.territory.name',
      Items nvarchar(max) '$.items' AS JSON);

SELECT o.SalesOrderID, item.Sku, item.Qty, item.Price
FROM lab.JsonFunctionsOrders AS o
CROSS APPLY OPENJSON(o.OrderDocument, '$.items')
WITH (Sku nvarchar(25) '$.sku', Qty int '$.qty', Price money '$.price') AS item
WHERE o.SalesOrderID IN (-1, 43659);
SELECT o.SalesOrderID, item.Sku, item.Qty
FROM lab.JsonFunctionsOrders AS o
OUTER APPLY OPENJSON(o.OrderDocument, '$.items')
WITH (Sku nvarchar(25) '$.sku', Qty int '$.qty') AS item
WHERE o.SalesOrderID IN (-1, 43659);
GO
-- Compare os dois resultados: CROSS APPLY não retorna SalesOrderID = -1; OUTER
-- APPLY o preserva com valores NULL no lado interno. Para cada pedido externo,
-- OPENJSON pode multiplicar linhas: filtre pedidos antes do APPLY quando possível.

-- PARTE 4: TRIAR STAGING COM LAX E CARREGAR COM STRICT
-- Não aplique strict diretamente a dados possivelmente inválidos: um único texto
-- malformado interrompe a instrução. A primeira consulta separa rejeitos; a segunda
-- só lê documentos já aprovados e com os campos obrigatórios presentes.
CREATE TABLE lab.JsonFunctionsStage (RowId int IDENTITY PRIMARY KEY, JsonData nvarchar(max) NULL);
INSERT INTO lab.JsonFunctionsStage (JsonData)
VALUES (N'{"id":1,"name":"valid"}'), (N'{"id":2}'), (N'{"id":');
SELECT RowId, JsonData FROM lab.JsonFunctionsStage
WHERE ISJSON(JsonData) = 0 OR JSON_VALUE(JsonData, '$.id') IS NULL
   OR JSON_VALUE(JsonData, '$.name') IS NULL;
SELECT JSON_VALUE(JsonData, 'strict $.id') AS Id,
       JSON_VALUE(JsonData, 'strict $.name') AS Name
FROM lab.JsonFunctionsStage
WHERE ISJSON(JsonData) = 1 AND JSON_VALUE(JsonData, '$.name') IS NOT NULL;
GO

-- PARTE 5: JSON_MODIFY E SAÍDA JSON, SEM ALTERAR OBJETOS ADVENTUREWORKS
-- JSON_MODIFY retorna um novo documento; a tabela não é atualizada nesta parte.
-- Resultado esperado: cidade é mascarada no resultado e temporary não aparece.
SELECT TOP (3) SalesOrderID,
    JSON_MODIFY(JSON_MODIFY(OrderDocument, '$.shipping.city', N'Redacted'),
                '$.temporary', NULL) AS SafeProjection
FROM lab.JsonFunctionsOrders;
SELECT TOP (3) h.SalesOrderID AS [order.id], h.OrderDate AS [order.date],
    p.FirstName AS [customer.firstName], p.LastName AS [customer.lastName]
FROM Sales.SalesOrderHeader AS h
JOIN Sales.Customer AS c ON c.CustomerID = h.CustomerID
LEFT JOIN Person.Person AS p ON p.BusinessEntityID = c.PersonID
FOR JSON PATH, ROOT('orders');
SELECT TOP (3) h.SalesOrderID, d.SalesOrderDetailID, d.OrderQty
FROM Sales.SalesOrderHeader AS h JOIN Sales.SalesOrderDetail AS d ON d.SalesOrderID = h.SalesOrderID
FOR JSON AUTO;
GO
-- PATH controla o contrato com aliases pontilhados (order.id); AUTO deriva a forma
-- da consulta. Para contratos de API, PATH é normalmente mais previsível.

-- PARTE 5B: PONTOS DE ATENÇÃO DE JSON_MODIFY E RECURSOS RECENTES
-- Em lax (padrão), atribuir NULL remove propriedade existente. Em strict, o
-- caminho precisa existir e NULL representa o valor JSON null. JSON_MODIFY trata
-- texto comum como string e faz escape; JSON_QUERY marca um fragmento como JSON.
DECLARE @config nvarchar(max) = N'{"env":"dev","tags":["dp800","json"]}';
SELECT JSON_MODIFY(@config, '$.env', NULL) AS RemoveEmLax,
       JSON_MODIFY(@config, '$.tags', JSON_QUERY(@config, '$.tags')) AS MantemArray;

BEGIN TRY
    SELECT JSON_MODIFY(@config, 'strict $.missing', N'x') AS StrictFalha;
END TRY
BEGIN CATCH
    PRINT N'Erro strict esperado em JSON_MODIFY: ' + ERROR_MESSAGE();
END CATCH;
GO

-- SQL Server 2025 on-premises (17.x) pode executar JSON_ARRAYAGG e JSON_CONTAINS.
-- As instruções ficam documentadas e o bloco dinâmico seguinte as executa quando
-- versão e compatibilidade permitem. SQL dinâmico evita erro de compilação em
-- instâncias on-premises mais antigas.
-- SELECT JSON_ARRAYAGG(SalesOrderID ORDER BY SalesOrderID)
-- FROM lab.JsonFunctionsOrders WHERE SalesOrderID > 0;
--
-- SELECT JSON_OBJECTAGG(CONVERT(nvarchar(20), SalesOrderID): OrderDate)
-- FROM lab.JsonFunctionsOrders WHERE SalesOrderID > 0;
--
-- SELECT JSON_CONTAINS(OrderDocument, '"Northwest"', '$.territory.name')
-- FROM lab.JsonFunctionsOrders;
-- Fallback: SELECT ... FOR JSON PATH; disponível no caminho principal do lab.

DECLARE @MajorVersion int = TRY_CONVERT(int, SERVERPROPERTY(N'ProductMajorVersion'));
DECLARE @CompatibilityLevel int = CONVERT(int, DATABASEPROPERTYEX(DB_NAME(), N'CompatibilityLevel'));

IF @MajorVersion >= 17 AND @CompatibilityLevel >= 170
BEGIN
    PRINT N'Executando recursos JSON do SQL Server 2025 on-premises.';

    -- Caso 1: ordenar IDs dentro do array. Resultado: um array JSON ordenado.
    EXEC sys.sp_executesql N'
        SELECT JSON_ARRAYAGG(SalesOrderID ORDER BY SalesOrderID) AS OrderIdsJson
        FROM lab.JsonFunctionsOrders
        WHERE SalesOrderID > 0;';

    -- Caso 2: teste de contenção no documento. JSON_CONTAINS exige tipo json;
    -- o CAST é intencional porque a tabela principal permanece nvarchar(max) para
    -- também rodar em versões anteriores. Compare-o com JSON_VALUE: aqui a
    -- intenção é perguntar se o valor JSON está contido naquele caminho.
    EXEC sys.sp_executesql N'
        SELECT SalesOrderID,
               JSON_CONTAINS(CAST(OrderDocument AS json), ''"Northwest"'', ''$.territory.name'') AS IsNorthwest
        FROM lab.JsonFunctionsOrders
        WHERE SalesOrderID > 0
          AND JSON_CONTAINS(CAST(OrderDocument AS json), ''"Northwest"'', ''$.territory.name'') = 1;';
END
ELSE
BEGIN
    PRINT N'Recursos JSON 2025 não executados: exigem SQL Server 2025 (17.x) e compatibilidade 170. O fallback FOR JSON deste lab foi executado normalmente.';
END;
GO

-- PARTE 5C: AGREGAÇÃO DE ATRIBUTOS E PAYLOAD PARA API/IA
-- Em uma integração real, atributos flexíveis podem chegar como linhas e precisam
-- ser agrupados em JSON. A tabela é isolada e usa produtos reais como referência.
CREATE TABLE lab.JsonFunctionsProductAttributes
(
    ProductID int NOT NULL,
    AttributeName sysname NOT NULL,
    AttributeValue nvarchar(100) NOT NULL,
    CONSTRAINT PK_JsonFunctionsProductAttributes PRIMARY KEY (ProductID, AttributeName)
);

INSERT INTO lab.JsonFunctionsProductAttributes (ProductID, AttributeName, AttributeValue)
SELECT TOP (12) p.ProductID, v.AttributeName, v.AttributeValue
FROM Production.Product AS p
CROSS APPLY (VALUES
    (N'productNumber', CONVERT(nvarchar(100), p.ProductNumber)),
    (N'color', COALESCE(p.Color, N'not-specified')),
    (N'class', COALESCE(p.Class, N'not-specified'))
) AS v(AttributeName, AttributeValue)
WHERE p.ProductNumber IS NOT NULL
ORDER BY p.ProductID, v.AttributeName;
GO

-- Fallback portável: uma matriz de atributos por produto. Ele executa hoje em
-- SQL Server compatível com AdventureWorks e preserva tipos/ordem do SELECT.
SELECT a.ProductID,
       JSON_QUERY((
           SELECT a2.AttributeName AS [name], a2.AttributeValue AS [value]
           FROM lab.JsonFunctionsProductAttributes AS a2
           WHERE a2.ProductID = a.ProductID
           ORDER BY a2.AttributeName
           FOR JSON PATH
       )) AS AttributesJson
FROM lab.JsonFunctionsProductAttributes AS a
GROUP BY a.ProductID
ORDER BY a.ProductID;
GO

-- Opcional em versões anteriores; automático no SQL Server 2025 on-premises
-- quando o bloco seguinte detectar versão 17.x e compatibilidade 170:
-- SELECT ProductID,
--        JSON_ARRAYAGG(AttributeName ORDER BY AttributeName) AS AttributeNames,
--        JSON_OBJECTAGG(AttributeName: AttributeValue) AS AttributesObject
-- FROM lab.JsonFunctionsProductAttributes
-- GROUP BY ProductID;
-- Compare a forma: JSON_ARRAYAGG gera array; JSON_OBJECTAGG exige chaves únicas.

DECLARE @MajorVersionAttributes int = TRY_CONVERT(int, SERVERPROPERTY(N'ProductMajorVersion'));
DECLARE @CompatibilityLevelAttributes int = CONVERT(int, DATABASEPROPERTYEX(DB_NAME(), N'CompatibilityLevel'));

IF @MajorVersionAttributes >= 17 AND @CompatibilityLevelAttributes >= 170
BEGIN
    -- Caso 3: atributos de linhas para array e objeto. ProductID/AttributeName é
    -- chave única, evitando colisão no objeto resultante.
    EXEC sys.sp_executesql N'
        SELECT ProductID,
               JSON_ARRAYAGG(AttributeName ORDER BY AttributeName) AS AttributeNamesJson,
               JSON_OBJECTAGG(AttributeName: AttributeValue) AS AttributesObjectJson
        FROM lab.JsonFunctionsProductAttributes
        GROUP BY ProductID
        ORDER BY ProductID;';
END;
GO

-- Payload portável para uma API de IA/LLM. Ele usa contexto de produtos reais,
-- mas é somente um documento de saída: não chama serviço externo nem armazena
-- prompt sensível. Em um sistema real, limite campos, tamanho e autorização.
DECLARE @SystemPrompt nvarchar(400) =
    N'Você responde somente com recomendações de catálogo baseadas no contexto recebido.';
DECLARE @UserPrompt nvarchar(400) =
    N'Resuma produtos de bicicleta disponíveis e destaque cor e número do produto.';

SELECT
(
    SELECT N'gpt-4.1' AS [model],
           CONVERT(decimal(3, 1), 0.2) AS [temperature],
           JSON_QUERY((
               SELECT m.[role], m.[content]
               FROM
               (
                   SELECT N'system' AS [role], @SystemPrompt AS [content]
                   UNION ALL
                   SELECT N'user', @UserPrompt
               ) AS m
               FOR JSON PATH
           )) AS [messages],
           JSON_QUERY((
               SELECT TOP (3) p.ProductID AS [id], p.ProductNumber AS [number],
                      p.Name AS [name], p.Color AS [color]
               FROM Production.Product AS p
               WHERE p.ProductNumber IS NOT NULL
               ORDER BY p.ProductID
               FOR JSON PATH
           )) AS [context.products]
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
) AS PayloadJson;
GO
-- Observe que JSON_QUERY impede que messages/context.products virem texto escapado.
-- Adapte "model" ao provedor; não trate o exemplo como configuração de produção.

-- PARTE 6: PLANO E EXPANSÃO DE LINHAS
-- A primeira consulta pode usar a projeção indexada porque repete a expressão.
-- A segunda reduz pedidos por data/território e só depois expande itens; sem esse
-- filtro externo, a cardinalidade e os operadores posteriores podem crescer muito.
ALTER TABLE lab.JsonFunctionsOrders
ADD TerritoryName AS CONVERT(nvarchar(50), JSON_VALUE(OrderDocument, '$.territory.name'));
CREATE INDEX IX_JsonFunctionsOrders_TerritoryName ON lab.JsonFunctionsOrders (TerritoryName);
GO
SET STATISTICS IO, TIME ON;
SELECT SalesOrderID FROM lab.JsonFunctionsOrders
WHERE CONVERT(nvarchar(50), JSON_VALUE(OrderDocument, '$.territory.name')) = N'Northwest';
SELECT o.SalesOrderID, item.Sku, item.Qty
FROM lab.JsonFunctionsOrders AS o
CROSS APPLY OPENJSON(o.OrderDocument, '$.items')
WITH (Sku nvarchar(25) '$.sku', Qty int '$.qty') AS item
WHERE o.OrderDate >= '20070101'
  AND CONVERT(nvarchar(50), JSON_VALUE(o.OrderDocument, '$.territory.name')) = N'Northwest';
SET STATISTICS IO, TIME OFF;
GO
-- Analise scans/seeks, lookups, leituras, CPU, estimativas, cardinalidade,
-- joins/sorts, memory grant e spills. O plano não é garantido. Se estimadas e
-- reais divergirem após OPENJSON, primeiro reduza o conjunto externo e reveja o
-- formato/volume dos arrays; índice JSON não elimina o custo de expandir cada item.

-- PARTE 7: DESAFIO AVANÇADO - METADADOS JSON E SQL DINÂMICO SEGURO
-- =================================================================================
-- A procedure abaixo é METADATA-DRIVEN: lê uma "definição de projeção" salva
-- em lab.JsonFunctionsMapping (no formato JSON) e monta dinamicamente a lista
-- de colunas do SELECT. Para reutilizar em QUALQUER tabela que possua coluna JSON,
-- basta informar:
--   @MappingName → nome do mapping salvo em lab.JsonFunctionsMapping
--   @TableName   → nome totalmente qualificado da tabela (ex: lab.JsonFunctionsOrders)
--   @JsonColumn  → nome da coluna JSON dessa tabela (ex: OrderDocument)
--   @KeyColumn   → nome da coluna de chave primária retornada como 1ª coluna
--                  (ex: SalesOrderID, ProductID, CustomerID, etc.)
-- =================================================================================
CREATE TABLE lab.JsonFunctionsMapping
(
    MappingName sysname NOT NULL CONSTRAINT PK_JsonFunctionsMapping PRIMARY KEY,
    Definition  nvarchar(max) NOT NULL CONSTRAINT CK_JsonFunctionsMapping CHECK (ISJSON(Definition) = 1)
);
GO

INSERT INTO lab.JsonFunctionsMapping (MappingName, Definition) VALUES
(N'PedidoResumo', N'[
  {"alias":"Numero","path":"$.order.number","kind":"scalar"},
  {"alias":"Territorio","path":"$.territory.name","kind":"scalar"},
  {"alias":"Itens","path":"$.items","kind":"json"}]');
GO

-- =================================================================================
-- PROCEDURE 100% GENÉRICA: aceita QUALQUER tabela + coluna JSON + chave primária.
-- Validações alinhadas com MS Learn Dynamic SQL:
--   1) sys.tables confirma que a tabela existe no schema esperado
--   2) sys.columns confirma que @JsonColumn e @KeyColumn existem na tabela
--   3) OBJECT_ID + QUOTENAME isolam identificadores contra SQL injection
--   4) sp_executesql tipado evita concatenação de valor de entrada
-- =================================================================================
CREATE OR ALTER PROCEDURE lab.usp_JsonFunctionsProjection
     @MappingName sysname,   -- ex: N'PedidoResumo'
     @TableName   sysname,   -- ex: N'lab.JsonFunctionsOrders' (2-part obrigatório)
     @JsonColumn  sysname,   -- ex: N'OrderDocument' (coluna JSON da tabela)
     @KeyColumn   sysname,   -- ex: N'SalesOrderID'  (PK retornada como 1ª coluna)
     @Debug       bit = 0    -- 1 = PRINT do SQL montado antes de executar
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @schema sysname, @table sysname, @definition nvarchar(max),
            @selectList nvarchar(max), @sql nvarchar(max),
            @ErrorMessage nvarchar(2048);

    ------------------------------------------------------------------
    -- 1) Quebrar @TableName em schema + table (2-part name seguro)
    ------------------------------------------------------------------
    SELECT @schema = PARSENAME(@TableName, 2),
           @table  = PARSENAME(@TableName, 1);

    IF @schema IS NULL OR @table IS NULL
        THROW 50001, N'Informe o nome da tabela no formato schema.tabela.', 1;

    ------------------------------------------------------------------
    -- 2) Validar a existência física da TABELA via sys.tables
    ------------------------------------------------------------------
    IF OBJECT_ID(@TableName, N'U') IS NULL
    BEGIN
        SET @ErrorMessage = N'Tabela "' + @TableName + N'" não existe no banco atual.';
        THROW 50002, @ErrorMessage, 1;
    END;

    ------------------------------------------------------------------
    -- 3) Validar que @JsonColumn e @KeyColumn EXISTEM na tabela
    ------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.tables  t ON t.object_id = c.object_id
        WHERE SCHEMA_NAME(t.schema_id) = @schema
          AND t.name  = @table
          AND c.name  = @JsonColumn)
    BEGIN
        SET @ErrorMessage = N'Coluna JSON "' + @JsonColumn + N'" não existe em ' + @TableName + N'.';
        THROW 50003, @ErrorMessage, 1;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.tables  t ON t.object_id = c.object_id
        WHERE SCHEMA_NAME(t.schema_id) = @schema
          AND t.name  = @table
          AND c.name  = @KeyColumn)
    BEGIN
        SET @ErrorMessage = N'Coluna chave "' + @KeyColumn + N'" não existe em ' + @TableName + N'.';
        THROW 50004, @ErrorMessage, 1;
    END;

    ------------------------------------------------------------------
    -- 4) Ler a DEFINIÇÃO do mapping salvo
    ------------------------------------------------------------------
    SELECT @definition = Definition
    FROM   lab.JsonFunctionsMapping
    WHERE  MappingName = @MappingName;

    IF @definition IS NULL
    BEGIN
        SET @ErrorMessage = N'Mapping "' + @MappingName + N'" não encontrado em lab.JsonFunctionsMapping.';
        THROW 50005, @ErrorMessage, 1;
    END;

    ------------------------------------------------------------------
    -- 5) Construir a SELECT LIST dinamicamente.
    --    @JsonColumn é validado contra sys.columns antes (passo 3).
    --    Os paths do mapping são validados por JsonPath LIKE '$.%'.
    --    Os aliases são protegidos por QUOTENAME.
    ------------------------------------------------------------------
    SELECT @selectList = STRING_AGG(
        CASE WHEN Kind = N'scalar'
             THEN N'JSON_VALUE(' + QUOTENAME(@JsonColumn) + N', '''
                + REPLACE(JsonPath, '''', '''''') + N''') AS ' + QUOTENAME(AliasName)
             ELSE N'JSON_QUERY(' + QUOTENAME(@JsonColumn) + N', '''
                + REPLACE(JsonPath, '''', '''''') + N''') AS ' + QUOTENAME(AliasName)
        END,
        N',' + CHAR(10) + N'    ')
    FROM OPENJSON(@definition)
    WITH
    (
        AliasName sysname       N'$.alias',
        JsonPath  nvarchar(400) N'$.path',
        Kind      nvarchar(10)  N'$.kind'
    )
    WHERE JsonPath LIKE N'$.%' AND Kind IN (N'scalar', N'json');

    IF @selectList IS NULL
    BEGIN
        SET @ErrorMessage = N'Mapping "' + @MappingName + N'" não possui paths permitidos.';
        THROW 50006, @ErrorMessage, 1;
    END;

    ------------------------------------------------------------------
    -- 6) Montar o SQL final — TUDO via QUOTENAME (sem concatenação de valor)
    ------------------------------------------------------------------
    SET @sql = N'SELECT ' + QUOTENAME(@KeyColumn) + N',' + CHAR(10) + N'    ' + @selectList
             + CHAR(10) + N'FROM '   + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N';';

    IF @Debug = 1
        PRINT @sql;

    EXEC sys.sp_executesql @sql;
END;
GO

-- =================================================================================
-- EXEMPLOS DE USO — mesma procedure, MESMO mapping, mas tabelas/colunas diferentes.
-- =================================================================================

-- (A) PedidoResumo contra a tabela de PEDIDOS (a original)
EXEC lab.usp_JsonFunctionsProjection
     @MappingName = N'PedidoResumo',
     @TableName   = N'lab.JsonFunctionsOrders',
     @JsonColumn  = N'OrderDocument',
     @KeyColumn   = N'SalesOrderID',
     @Debug       = 1;
GO

-- (B) Reuso do mapping em uma tabela DIFERENTE (clientes hipotéticos).
--     Demonstra que a mesma proc funciona com QUALQUER tabela que tenha
--     coluna JSON, bastando um novo mapping com a mesma estrutura de paths.
IF OBJECT_ID('lab.JsonFunctionsClientes', 'U') IS NULL
BEGIN
    CREATE TABLE lab.JsonFunctionsClientes (
        ClienteID   int NOT NULL PRIMARY KEY,
        ClienteNome sysname NOT NULL,
        ClienteJson nvarchar(max) NOT NULL
            CONSTRAINT CK_JsonFunctionsClientes_Doc CHECK (ISJSON(ClienteJson) = 1)
    );
    INSERT INTO lab.JsonFunctionsClientes (ClienteID, ClienteNome, ClienteJson) VALUES
    (1, N'ACME Ltda.',  N'{"order":{"number":"AC-001"},"territory":{"name":"Norte"},"items":[{"sku":"X","qty":2}]}'),
    (2, N'Globex S/A',  N'{"order":{"number":"GB-002"},"territory":{"name":"Sul"},  "items":[]}');
END;
GO
INSERT INTO lab.JsonFunctionsMapping (MappingName, Definition) VALUES
(N'ClienteResumo', N'[
  {"alias":"Numero","path":"$.order.number","kind":"scalar"},
  {"alias":"Territorio","path":"$.territory.name","kind":"scalar"},
  {"alias":"Itens","path":"$.items","kind":"json"}]');
GO
EXEC lab.usp_JsonFunctionsProjection
     @MappingName = N'ClienteResumo',
     @TableName   = N'lab.JsonFunctionsClientes',
     @JsonColumn  = N'ClienteJson',
     @KeyColumn   = N'ClienteID';
GO

-- (C) FALHA SEGURA — passando coluna inexistente a proc REJEITA antes de
--     montar qualquer SQL dinâmico (proteção contra typos e SQL injection):
EXEC lab.usp_JsonFunctionsProjection
     @MappingName = N'PedidoResumo',
     @TableName   = N'lab.JsonFunctionsOrders',
     @JsonColumn  = N'ColunaInexistente',
     @KeyColumn   = N'SalesOrderID';
-- (erro esperado: "Coluna JSON 'ColunaInexistente' não existe em lab.JsonFunctionsOrders.")
GO

-- Desafio: acrescente um path escalar de produto e explique por que QUOTENAME
-- protege aliases, mas não transforma paths não validados em conteúdo confiável.
-- Limpeza opcional:
-- DROP PROCEDURE IF EXISTS lab.usp_JsonFunctionsProjection;
-- DROP TABLE IF EXISTS lab.JsonFunctionsProductAttributes;
-- DROP TABLE IF EXISTS lab.JsonFunctionsMapping;
-- DROP TABLE IF EXISTS lab.JsonFunctionsClientes;
-- DROP TABLE IF EXISTS lab.JsonFunctionsStage;
-- DROP TABLE IF EXISTS lab.JsonFunctionsOrders;
GO
