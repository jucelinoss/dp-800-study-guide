-- =================================================================================
-- DP-800 - LAB PRÁTICO: CONSULTAS DE GRAFO (NODES, EDGES, MATCH E SHORTEST_PATH)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/03-advanced-tsql/04-graph-queries.md
-- Este é o lab avançado de Graph. Os objetos Graph* são exclusivos deste arquivo;
-- o lab de tabelas especializadas usa objetos SpecializedGraph* e pode rodar antes
-- ou depois deste script sem conflito.
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva: edges primeiro, depois nodes. Cada objeto pertence somente
-- a este lab, portanto o cleanup não remove objetos de outros exercícios.
DROP PROCEDURE IF EXISTS lab.sp_generate_mermaid_graph;
DROP TABLE IF EXISTS lab.GraphLikes;
DROP TABLE IF EXISTS lab.GraphFriendOf;
DROP TABLE IF EXISTS lab.GraphOwnsCard;
DROP TABLE IF EXISTS lab.GraphUsedIP;
DROP TABLE IF EXISTS lab.GraphSupplies;
DROP TABLE IF EXISTS lab.GraphStores;
DROP TABLE IF EXISTS lab.GraphRestaurant;
DROP TABLE IF EXISTS lab.GraphCreditCard;
DROP TABLE IF EXISTS lab.GraphIPAddress;
DROP TABLE IF EXISTS lab.GraphPerson;
DROP TABLE IF EXISTS lab.GraphSupplier;
DROP TABLE IF EXISTS lab.GraphWarehouse;
DROP TABLE IF EXISTS lab.GraphProduct;
GO


-- =================================================================================
-- PARTE 1: MODELO AVANÇADO DE GRAFO
-- =================================================================================
-- Nodes representam entidades; edges representam relações direcionadas.
-- CONNECTION restringe, no DDL, quais tipos de node cada edge pode ligar.

CREATE TABLE lab.GraphPerson (
    PersonID int NOT NULL PRIMARY KEY,
    Name nvarchar(100) NOT NULL,
    City nvarchar(100) NULL
) AS NODE;

CREATE TABLE lab.GraphRestaurant (
    RestaurantID int NOT NULL PRIMARY KEY,
    Name nvarchar(100) NOT NULL,
    Cuisine nvarchar(50) NOT NULL
) AS NODE;

CREATE TABLE lab.GraphCreditCard (
    CardID int NOT NULL PRIMARY KEY,
    CardNumber nvarchar(20) NOT NULL,
    Issuer nvarchar(50) NOT NULL
) AS NODE;

CREATE TABLE lab.GraphIPAddress (
    IPID int NOT NULL PRIMARY KEY,
    IPAddress nvarchar(45) NOT NULL
) AS NODE;

CREATE TABLE lab.GraphSupplier (
    SupplierID int NOT NULL PRIMARY KEY,
    SupplierName nvarchar(100) NOT NULL,
    City nvarchar(100) NOT NULL
) AS NODE;

CREATE TABLE lab.GraphWarehouse (
    WarehouseID int NOT NULL PRIMARY KEY,
    WarehouseName nvarchar(100) NOT NULL,
    Location nvarchar(100) NOT NULL
) AS NODE;

CREATE TABLE lab.GraphProduct (
    ProductID int NOT NULL PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    Category nvarchar(50) NOT NULL
) AS NODE;
GO

CREATE TABLE lab.GraphFriendOf (
    CONSTRAINT EC_GraphFriendOf
        CONNECTION (lab.GraphPerson TO lab.GraphPerson) ON DELETE CASCADE
) AS EDGE;

CREATE TABLE lab.GraphLikes (
    Rating int NULL,
    CONSTRAINT EC_GraphLikes
        CONNECTION (lab.GraphPerson TO lab.GraphRestaurant) ON DELETE CASCADE
) AS EDGE;

CREATE TABLE lab.GraphOwnsCard (
    CONSTRAINT EC_GraphOwnsCard
        CONNECTION (lab.GraphPerson TO lab.GraphCreditCard) ON DELETE CASCADE
) AS EDGE;

CREATE TABLE lab.GraphUsedIP (
    CONSTRAINT EC_GraphUsedIP
        CONNECTION (lab.GraphPerson TO lab.GraphIPAddress) ON DELETE CASCADE
) AS EDGE;

CREATE TABLE lab.GraphSupplies (
    CONSTRAINT EC_GraphSupplies
        CONNECTION (lab.GraphSupplier TO lab.GraphWarehouse) ON DELETE CASCADE
) AS EDGE;

CREATE TABLE lab.GraphStores (
    CONSTRAINT EC_GraphStores
        CONNECTION (lab.GraphWarehouse TO lab.GraphProduct) ON DELETE CASCADE
) AS EDGE;
GO


-- =================================================================================
-- PARTE 2: CARGA DOS NODES E EDGES
-- =================================================================================
INSERT INTO lab.GraphPerson (PersonID, Name, City)
VALUES (1, N'Alice', N'São Paulo'),
       (2, N'Bob', N'Rio de Janeiro'),
       (3, N'Charlie', N'Belo Horizonte'),
       (4, N'Daniela', N'Curitiba'),
       (5, N'Eve', N'Salvador'); -- nó isolado intencional

INSERT INTO lab.GraphRestaurant (RestaurantID, Name, Cuisine)
VALUES (101, N'Sushi Master', N'Japonesa'),
       (102, N'Pizzeria Bella', N'Italiana');

INSERT INTO lab.GraphCreditCard (CardID, CardNumber, Issuer)
VALUES (201, N'4111-XXXX-XXXX-1111', N'Visa'),
       (202, N'5500-YYYY-YYYY-2222', N'MasterCard');

INSERT INTO lab.GraphIPAddress (IPID, IPAddress)
VALUES (301, N'192.168.1.100'),
       (302, N'10.0.0.5');

INSERT INTO lab.GraphSupplier (SupplierID, SupplierName, City)
VALUES (401, N'TechComponents SA', N'São Paulo'),
       (402, N'LogisticaGlobal LTDA', N'Curitiba'),
       (403, N'Fornecedor Inativo', N'Rio de Janeiro'); -- nó isolado

INSERT INTO lab.GraphWarehouse (WarehouseID, WarehouseName, Location)
VALUES (501, N'CD Principal', N'Campinas'),
       (502, N'Depósito Sul', N'Joinville');

INSERT INTO lab.GraphProduct (ProductID, ProductName, Category)
VALUES (601, N'Servidor Rack 2U', N'Hardware'),
       (602, N'Switch L3 48p', N'Redes'),
       (603, N'Item Obsoleto', N'Descontinuado'); -- nó isolado
GO

-- `$node_id` é a identidade interna do Graph usada em `$from_id` e `$to_id`.
INSERT INTO lab.GraphFriendOf ($from_id, $to_id)
VALUES
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 1),
 (SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 2)),
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 2),
 (SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 3)),
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 3),
 (SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 4));

INSERT INTO lab.GraphLikes ($from_id, $to_id, Rating)
VALUES
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 1),
 (SELECT $node_id FROM lab.GraphRestaurant WHERE RestaurantID = 101), 5),
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 2),
 (SELECT $node_id FROM lab.GraphRestaurant WHERE RestaurantID = 102), 4);

INSERT INTO lab.GraphOwnsCard ($from_id, $to_id)
VALUES
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 1),
 (SELECT $node_id FROM lab.GraphCreditCard WHERE CardID = 201)),
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 2),
 (SELECT $node_id FROM lab.GraphCreditCard WHERE CardID = 201)),
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 3),
 (SELECT $node_id FROM lab.GraphCreditCard WHERE CardID = 202));

INSERT INTO lab.GraphUsedIP ($from_id, $to_id)
VALUES
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 2),
 (SELECT $node_id FROM lab.GraphIPAddress WHERE IPID = 301)),
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 3),
 (SELECT $node_id FROM lab.GraphIPAddress WHERE IPID = 301)),
((SELECT $node_id FROM lab.GraphPerson WHERE PersonID = 1),
 (SELECT $node_id FROM lab.GraphIPAddress WHERE IPID = 302));

INSERT INTO lab.GraphSupplies ($from_id, $to_id)
VALUES
((SELECT $node_id FROM lab.GraphSupplier WHERE SupplierID = 401),
 (SELECT $node_id FROM lab.GraphWarehouse WHERE WarehouseID = 501)),
((SELECT $node_id FROM lab.GraphSupplier WHERE SupplierID = 402),
 (SELECT $node_id FROM lab.GraphWarehouse WHERE WarehouseID = 502));

INSERT INTO lab.GraphStores ($from_id, $to_id)
VALUES
((SELECT $node_id FROM lab.GraphWarehouse WHERE WarehouseID = 501),
 (SELECT $node_id FROM lab.GraphProduct WHERE ProductID = 601)),
((SELECT $node_id FROM lab.GraphWarehouse WHERE WarehouseID = 502),
 (SELECT $node_id FROM lab.GraphProduct WHERE ProductID = 602));
GO


-- =================================================================================
-- PARTE 3: MATCH, RECOMENDAÇÃO E DETECÇÃO DE FRAUDE
-- =================================================================================
-- MATCH expressa os joins entre pseudo-colunas de Graph sem expor `$node_id`.

-- Restaurantes apreciados por amigos de Alice.
SELECT p1.Name AS Pessoa,
       p2.Name AS Amigo,
       r.Name AS RestauranteRecomendado,
       r.Cuisine
FROM lab.GraphPerson AS p1,
     lab.GraphFriendOf AS f,
     lab.GraphPerson AS p2,
     lab.GraphLikes AS l,
     lab.GraphRestaurant AS r
WHERE MATCH(p1-(f)->p2-(l)->r)
  AND p1.Name = N'Alice';
GO

-- Duas pessoas usando o mesmo cartão são um candidato a investigação de fraude.
SELECT p1.Name AS Cliente1,
       p2.Name AS Cliente2,
       c.CardNumber AS CartaoCompartilhado
FROM lab.GraphPerson AS p1,
     lab.GraphOwnsCard AS o1,
     lab.GraphCreditCard AS c,
     lab.GraphOwnsCard AS o2,
     lab.GraphPerson AS p2
WHERE MATCH(p1-(o1)->c<-(o2)-p2)
  AND p1.PersonID < p2.PersonID;
GO

-- Duas pessoas usando o mesmo IP também formam um sinal de risco.
SELECT p1.Name AS Cliente1,
       p2.Name AS Cliente2,
       ip.IPAddress AS IPCompartilhado
FROM lab.GraphPerson AS p1,
     lab.GraphUsedIP AS u1,
     lab.GraphIPAddress AS ip,
     lab.GraphUsedIP AS u2,
     lab.GraphPerson AS p2
WHERE MATCH(p1-(u1)->ip<-(u2)-p2)
  AND p1.PersonID < p2.PersonID;
GO

-- Cadeia de suprimento: fornecedor, armazém e produto relacionado.
SELECT s.SupplierName,
       w.WarehouseName,
       p.ProductName
FROM lab.GraphSupplier AS s,
     lab.GraphSupplies AS su,
     lab.GraphWarehouse AS w,
     lab.GraphStores AS st,
     lab.GraphProduct AS p
WHERE MATCH(s-(su)->w-(st)->p);
GO


-- =================================================================================
-- PARTE 4: SHORTEST_PATH E ÍNDICES DE GRAFO
-- =================================================================================
-- SHORTEST_PATH encontra a rota com menor número de hops. Edge e node intermediário
-- devem usar FOR PATH; GRAPH PATH preserva a ordem da travessia.
SELECT p1.Name AS Origem,
       LAST_VALUE(p2.Name) WITHIN GROUP (GRAPH PATH) AS DestinoFinal,
       STRING_AGG(p2.Name, N' -> ') WITHIN GROUP (GRAPH PATH) AS RotaPercorrida
FROM lab.GraphPerson AS p1,
     lab.GraphFriendOf FOR PATH AS f,
     lab.GraphPerson FOR PATH AS p2
WHERE MATCH(SHORTEST_PATH(p1(-(f)->p2)+))
  AND p1.Name = N'Alice';
GO

-- Índices nas pseudo-colunas reduzem o custo de travessias em edges maiores.
CREATE INDEX IX_GraphFriendOf_FromTo ON lab.GraphFriendOf ($from_id, $to_id);
CREATE INDEX IX_GraphLikes_FromTo ON lab.GraphLikes ($from_id, $to_id);
CREATE INDEX IX_GraphOwnsCard_FromTo ON lab.GraphOwnsCard ($from_id, $to_id);
CREATE INDEX IX_GraphUsedIP_FromTo ON lab.GraphUsedIP ($from_id, $to_id);
GO


-- =================================================================================
-- PARTE 5: RENDERIZADOR MERMAID ORIENTADO A METADADOS
-- =================================================================================
-- A procedure usa SQL dinâmico somente para ler tabelas identificadas nos metadados.
-- Ela é limitada ao schema lab e ao prefixo Graph*, portanto não mistura objetos de
-- outros labs. `@TabelaAlvo = NULL` renderiza todos os Graph*; ao informar um node
-- ou edge, ela renderiza a vizinhança direta daquele tipo de tabela.
GO
CREATE OR ALTER PROCEDURE lab.sp_generate_mermaid_graph
    @TabelaAlvo sysname = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SchemaAlvo sysname = N'lab';
    DECLARE @NomeTabela sysname;
    DECLARE @ObjectIdAlvo int;
    DECLARE @IsNode bit;
    DECLARE @IsEdge bit;
    DECLARE @Sql nvarchar(max);
    DECLARE @AllEdgesExistsClause nvarchar(max);

    IF @TabelaAlvo IS NOT NULL
    BEGIN
        IF PARSENAME(@TabelaAlvo, 3) IS NOT NULL
           OR PARSENAME(@TabelaAlvo, 4) IS NOT NULL
            THROW 51001, N'Informe somente Tabela ou schema.Tabela.', 1;

        SET @NomeTabela = PARSENAME(@TabelaAlvo, 1);
        SET @SchemaAlvo = COALESCE(PARSENAME(@TabelaAlvo, 2), N'lab');

        IF @SchemaAlvo <> N'lab'
            THROW 51002, N'A tabela alvo deve pertencer ao schema lab.', 1;

        SELECT @ObjectIdAlvo = t.object_id,
               @IsNode = t.is_node,
               @IsEdge = t.is_edge
        FROM sys.tables AS t
        WHERE t.schema_id = SCHEMA_ID(N'lab')
          AND t.name = @NomeTabela
          AND t.name LIKE N'Graph%'
          AND (t.is_node = 1 OR t.is_edge = 1);

        IF @ObjectIdAlvo IS NULL
            THROW 51003, N'Tabela alvo inexistente ou fora do escopo Graph* deste lab.', 1;
    END;

    CREATE TABLE #SelectedNodes
    (
        ObjectId int NOT NULL PRIMARY KEY,
        SchemaName sysname NOT NULL,
        TableName sysname NOT NULL,
        DisplayColumn sysname NOT NULL
    );

    CREATE TABLE #SelectedEdges
    (
        ObjectId int NOT NULL PRIMARY KEY,
        SchemaName sysname NOT NULL,
        TableName sysname NOT NULL
    );

    -- Sem parâmetro: todos os objetos Graph* do lab, inclusive nodes isolados.
    IF @TabelaAlvo IS NULL
    BEGIN
        INSERT INTO #SelectedNodes (ObjectId, SchemaName, TableName, DisplayColumn)
        SELECT t.object_id,
               s.name,
               t.name,
               COALESCE(
                   (SELECT TOP (1) c.name
                    FROM sys.columns AS c
                    WHERE c.object_id = t.object_id
                      AND c.is_hidden = 0
                      AND c.name NOT LIKE N'%ID%'
                    ORDER BY c.column_id),
                   (SELECT TOP (1) c.name
                    FROM sys.columns AS c
                    WHERE c.object_id = t.object_id
                      AND c.is_hidden = 0
                    ORDER BY c.column_id))
        FROM sys.tables AS t
        JOIN sys.schemas AS s ON s.schema_id = t.schema_id
        WHERE t.schema_id = SCHEMA_ID(N'lab')
          AND t.is_node = 1
          AND t.name LIKE N'Graph%';

        INSERT INTO #SelectedEdges (ObjectId, SchemaName, TableName)
        SELECT t.object_id, s.name, t.name
        FROM sys.tables AS t
        JOIN sys.schemas AS s ON s.schema_id = t.schema_id
        WHERE t.schema_id = SCHEMA_ID(N'lab')
          AND t.is_edge = 1
          AND t.name LIKE N'Graph%';
    END
    ELSE IF @IsNode = 1
    BEGIN
        -- Node alvo + edges incidentes + nodes nos extremos opostos dessas edges.
        INSERT INTO #SelectedNodes (ObjectId, SchemaName, TableName, DisplayColumn)
        SELECT t.object_id, s.name, t.name,
               COALESCE((SELECT TOP (1) c.name FROM sys.columns AS c
                         WHERE c.object_id = t.object_id AND c.is_hidden = 0
                           AND c.name NOT LIKE N'%ID%' ORDER BY c.column_id),
                        (SELECT TOP (1) c.name FROM sys.columns AS c
                         WHERE c.object_id = t.object_id AND c.is_hidden = 0 ORDER BY c.column_id))
        FROM sys.tables AS t
        JOIN sys.schemas AS s ON s.schema_id = t.schema_id
        WHERE t.object_id = @ObjectIdAlvo;

        INSERT INTO #SelectedEdges (ObjectId, SchemaName, TableName)
        SELECT DISTINCT e.object_id, s.name, e.name
        FROM sys.edge_constraints AS ec
        JOIN sys.edge_constraint_clauses AS ecc ON ecc.object_id = ec.object_id
        JOIN sys.tables AS e ON e.object_id = ec.parent_object_id
        JOIN sys.schemas AS s ON s.schema_id = e.schema_id
        WHERE e.schema_id = SCHEMA_ID(N'lab')
          AND e.name LIKE N'Graph%'
          AND (@ObjectIdAlvo = ecc.from_object_id OR @ObjectIdAlvo = ecc.to_object_id);
    END
    ELSE
    BEGIN
        -- Edge alvo + os dois tipos de node definidos pela CONNECTION.
        INSERT INTO #SelectedEdges (ObjectId, SchemaName, TableName)
        SELECT t.object_id, s.name, t.name
        FROM sys.tables AS t
        JOIN sys.schemas AS s ON s.schema_id = t.schema_id
        WHERE t.object_id = @ObjectIdAlvo;
    END;

    -- Para filtro por node ou edge, completa os nodes alcançados pelas edges selecionadas.
    INSERT INTO #SelectedNodes (ObjectId, SchemaName, TableName, DisplayColumn)
    SELECT DISTINCT n.object_id,
           ns.name,
           n.name,
           COALESCE((SELECT TOP (1) c.name FROM sys.columns AS c
                     WHERE c.object_id = n.object_id AND c.is_hidden = 0
                       AND c.name NOT LIKE N'%ID%' ORDER BY c.column_id),
                    (SELECT TOP (1) c.name FROM sys.columns AS c
                     WHERE c.object_id = n.object_id AND c.is_hidden = 0 ORDER BY c.column_id))
    FROM #SelectedEdges AS se
    JOIN sys.edge_constraints AS ec ON ec.parent_object_id = se.ObjectId
    JOIN sys.edge_constraint_clauses AS ecc ON ecc.object_id = ec.object_id
    CROSS APPLY (VALUES (ecc.from_object_id), (ecc.to_object_id)) AS endpoints(ObjectId)
    JOIN sys.tables AS n ON n.object_id = endpoints.ObjectId
    JOIN sys.schemas AS ns ON ns.schema_id = n.schema_id
    WHERE NOT EXISTS (SELECT 1 FROM #SelectedNodes AS sn WHERE sn.ObjectId = n.object_id);

    SELECT @AllEdgesExistsClause = STRING_AGG(
        N'EXISTS (SELECT 1 FROM ' + QUOTENAME(SchemaName) + N'.' + QUOTENAME(TableName)
        + N' AS E WHERE E.$from_id = N.$node_id OR E.$to_id = N.$node_id)',
        N' OR ')
    FROM #SelectedEdges;

    SET @AllEdgesExistsClause = COALESCE(@AllEdgesExistsClause, N'1 = 0');

    CREATE TABLE #MermaidLines
    (
        SortOrder int NOT NULL,
        LineContent nvarchar(max) NOT NULL
    );

    INSERT INTO #MermaidLines VALUES (1, N'graph LR');
    INSERT INTO #MermaidLines VALUES (2, N'    subgraph "Nodes conectados"');

    DECLARE @NodeSchema sysname, @NodeTable sysname, @DisplayColumn sysname;
    DECLARE node_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT SchemaName, TableName, DisplayColumn FROM #SelectedNodes;

    OPEN node_cursor;
    FETCH NEXT FROM node_cursor INTO @NodeSchema, @NodeTable, @DisplayColumn;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'INSERT INTO #MermaidLines
            SELECT 3, N''        N_'' + CONVERT(varchar(32), HASHBYTES(''MD5'', N.$node_id), 2)
                   + N''["' + REPLACE(@NodeTable, N'"', N'''') + N': ''
                   + ISNULL(CONVERT(nvarchar(100), N.' + QUOTENAME(@DisplayColumn) + N'), N''N/A'') + N''"]''
            FROM ' + QUOTENAME(@NodeSchema) + N'.' + QUOTENAME(@NodeTable) + N' AS N
            WHERE ' + @AllEdgesExistsClause + N';';
        EXEC sys.sp_executesql @Sql;
        FETCH NEXT FROM node_cursor INTO @NodeSchema, @NodeTable, @DisplayColumn;
    END;
    CLOSE node_cursor;
    DEALLOCATE node_cursor;

    DECLARE @EdgeSchema sysname, @EdgeTable sysname;
    DECLARE edge_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT SchemaName, TableName FROM #SelectedEdges;

    OPEN edge_cursor;
    FETCH NEXT FROM edge_cursor INTO @EdgeSchema, @EdgeTable;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'INSERT INTO #MermaidLines
            SELECT 4, N''        N_'' + CONVERT(varchar(32), HASHBYTES(''MD5'', $from_id), 2)
                   + N'' -- "' + REPLACE(@EdgeTable, N'"', N'''') + N'" --> N_''
                   + CONVERT(varchar(32), HASHBYTES(''MD5'', $to_id), 2)
            FROM ' + QUOTENAME(@EdgeSchema) + N'.' + QUOTENAME(@EdgeTable) + N';';
        EXEC sys.sp_executesql @Sql;
        FETCH NEXT FROM edge_cursor INTO @EdgeSchema, @EdgeTable;
    END;
    CLOSE edge_cursor;
    DEALLOCATE edge_cursor;

    INSERT INTO #MermaidLines VALUES (5, N'    end');
    INSERT INTO #MermaidLines VALUES (6, N'    subgraph "Nodes isolados"');

    DECLARE isolated_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT SchemaName, TableName, DisplayColumn FROM #SelectedNodes;

    OPEN isolated_cursor;
    FETCH NEXT FROM isolated_cursor INTO @NodeSchema, @NodeTable, @DisplayColumn;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'INSERT INTO #MermaidLines
            SELECT 7, N''        N_'' + CONVERT(varchar(32), HASHBYTES(''MD5'', N.$node_id), 2)
                   + N''["' + REPLACE(@NodeTable, N'"', N'''') + N': ''
                   + ISNULL(CONVERT(nvarchar(100), N.' + QUOTENAME(@DisplayColumn) + N'), N''N/A'') + N''"]''
            FROM ' + QUOTENAME(@NodeSchema) + N'.' + QUOTENAME(@NodeTable) + N' AS N
            WHERE NOT (' + @AllEdgesExistsClause + N');';
        EXEC sys.sp_executesql @Sql;
        FETCH NEXT FROM isolated_cursor INTO @NodeSchema, @NodeTable, @DisplayColumn;
    END;
    CLOSE isolated_cursor;
    DEALLOCATE isolated_cursor;

    INSERT INTO #MermaidLines VALUES (8, N'    end');

    SELECT LineContent AS MermaidCode
    FROM #MermaidLines
    ORDER BY SortOrder, LineContent;
END;
GO

-- Sem parâmetro: todos os Graph* deste lab, conectados ou isolados.
EXEC lab.sp_generate_mermaid_graph;
GO

-- Node: mostra GraphPerson, as edges incidentes e os nodes diretamente ligados.
EXEC lab.sp_generate_mermaid_graph @TabelaAlvo = N'GraphPerson';
GO

-- Edge: mostra GraphOwnsCard e os tipos de node definidos pela CONNECTION.
EXEC lab.sp_generate_mermaid_graph @TabelaAlvo = N'lab.GraphOwnsCard';
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/03-advanced-tsql/04-graph-queries.md
-- =================================================================================================
