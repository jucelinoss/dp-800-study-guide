-- =================================================================================
-- DP-800 - LAB PRÁTICO: COLUNAS E ÍNDICES JSON (JSON COLUMNS AND INDEXES)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra na prática a manipulação, consulta e indexação de dados
-- no formato JSON dentro do SQL Server, cobrindo:
--   1. Armazenamento Clássico com validação ISJSON
--   2. Funções de Leitura: JSON_VALUE vs JSON_QUERY
--   3. Modos de busca: LAX vs STRICT (Erro 13608)
--   4. OPENJSON com e sem a cláusula WITH (com CROSS APPLY)
--   5. Agregadores Modernos: JSON_ARRAYAGG e JSON_OBJECTAGG (Azure SQL / SQL Server 2025)
--   6. Otimização e Indexação com Computed Columns
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva caso rode o script mais de uma vez
DROP TABLE IF EXISTS lab.OrdersJSON;
GO


-- =================================================================================
-- PARTE 1: ARMAZENAMENTO E VALIDAÇÃO (ISJSON)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - ARMAZENAMENTO JSON: Tradicionalmente, o SQL Server armazena JSON como strings de texto (`NVARCHAR(MAX)`).
--     O tipo nativo `json` é GA no Azure SQL Database e Azure SQL Managed Instance; no SQL Server 2025,
--     ele permanece em preview. Este laboratório usa NVARCHAR(MAX) para funcionar no SQL Server tradicional.
--   - ISJSON(): Função de validação. Retorna 1 se o texto for um JSON válido.
--     No SQL Server 2022+, é possível especificar parâmetros de validação de tipo, tais como:
--     `ISJSON(coluna, SCALAR)`, `ISJSON(coluna, ARRAY)` ou `ISJSON(coluna, OBJECT)`.
--   - CHECK CONSTRAINT COM ISJSON: Restrição de tabela fundamental para impedir a entrada de strings corrompidas
--     ou mal-formadas nas colunas destinadas a armazenar JSON em formato de texto.

CREATE TABLE lab.OrdersJSON
(
    OrderID INT IDENTITY PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    OrderDetails NVARCHAR(MAX) NULL,
    -- Coluna JSON
    -- Restrição CHECK para integridade estrutural
    CONSTRAINT CK_OrdersJSON_OrderDetails CHECK (ISJSON(OrderDetails) = 1)
);
GO

-- Inserindo um registro JSON válido
INSERT INTO lab.OrdersJSON
    (CustomerName, OrderDetails)
VALUES
    ('Alice Smith', N'{
    "region": "South",
    "delivery": { "carrier": "DHL", "days": 3 },
    "items": [
        { "product": "Smartphone", "qty": 1, "price": 899.00 },
        { "product": "Charger", "qty": 2, "price": 25.00 }
    ]
}');
GO

-- Teste: Tentar inserir um JSON mal-formado (Deve falhar no CHECK)
BEGIN TRY
    INSERT INTO lab.OrdersJSON
    (CustomerName, OrderDetails)
VALUES
    ('Bob Jones', N'{"region": "North", "delivery": {"carrier": "FedEx", "days": 5 }'); -- Falta fechar o objeto principal
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO: ' + ERROR_MESSAGE();
    -- Retornará: "The INSERT statement conflicted with the CHECK constraint..."
END CATCH;
GO


-- =================================================================================
-- PARTE 2: LEITURA DE VALORES (JSON_VALUE VS JSON_QUERY)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - JSON_VALUE: Extrai um valor escalar simples (ex: uma única string, número ou booleano) de uma string JSON.
--     Sempre retorna o valor convertido em `NVARCHAR(4000)`. Se for apontado para um objeto ou array inteiro, 
--     retorna NULL em modo lax (padrão) ou falha em modo strict.
--   - JSON_QUERY: Extrai um fragmento estruturado inteiro (um objeto `{}` ou um array `[]`) de uma string JSON.
--     Sempre retorna uma string JSON válida. Se for apontado para um valor escalar simples (ex: número ou string),
--     retorna NULL em modo lax ou gera erro em modo strict.
--   - PATH EXPRESSIONS (Caminho de Busca): Ambas as funções utilizam o caractere `$` para representar a raiz do JSON,
--     seguido pela notação de ponto para navegar nos objetos (ex: `$.delivery.carrier`) ou colchetes para arrays (ex: `$.items[0]`).

DECLARE @json NVARCHAR(MAX);
SELECT TOP 1
    @json = OrderDetails
FROM lab.OrdersJSON
WHERE CustomerName = 'Alice Smith';

SELECT @json
SELECT
    -- 1. Extração correta de valores escalares usando JSON_VALUE
    JSON_VALUE(@json, '$.region') AS Region,
    JSON_VALUE(@json, '$.delivery.carrier') AS Carrier,
    JSON_VALUE(@json, '$.items[0].product') AS FirstProduct,

    -- 2. Tentativa de buscar um objeto/array usando JSON_VALUE (Retorna NULL silenciosamente!)
    JSON_VALUE(@json, '$.delivery') AS DeliveryObject_Value_Fail,
    JSON_VALUE(@json, '$.items') AS ItemsArray_Value_Fail,

    -- 3. Extração correta de objetos/arrays usando JSON_QUERY
    JSON_QUERY(@json, '$.delivery') AS DeliveryObject_Query_Success,
    JSON_QUERY(@json, '$.items') AS ItemsArray_Query_Success,

    -- 4. Tentativa inversa: buscar um valor escalar usando JSON_QUERY (Também retorna NULL silenciosamente!)
    JSON_QUERY(@json, '$.region') AS Scalar_Query_Fail,
    JSON_QUERY(@json, '$.delivery.carrier') AS ScalarCarrier_Query_Fail;
GO


-- =================================================================================
-- PARTE 3: MODOS DE CAMINHO (LAX VS STRICT)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - MODO LAX (Padrão): Se a query tentar acessar um caminho (path expression) inexistente, 
--     um elemento ausente ou errar no tipo esperado (ex: mapear escalar para JSON_QUERY),
--     o SQL Server silencia o problema e retorna simplesmente NULL.
--   - MODO STRICT: Exige mapeamento perfeito. Se o caminho não existir ou houver inconformidade
--     de tipos (ex: elemento não encontrado, chave ausente), a engine interrompe a query e lança 
--     o erro de execução 13608 ("Property cannot be found on the specified JSON path").
--   - APLICAÇÃO PRÁTICA: O modo `strict` é essencial para validação rigorosa de esquemas em pipelines 
--     de ETL/Staging, enquanto o modo `lax` é preferível para consultas flexíveis tolerantes a esquemas dinâmicos.

DECLARE @json NVARCHAR(MAX) = N'{"name": "Alice"}';

-- Teste 1: Modo LAX (Padrão) - retorna NULL silenciosamente
SELECT
    JSON_VALUE(@json, 'lax $.age') AS AgeLax,
    JSON_VALUE(@json, '$.age') AS AgeDefault;
-- lax é o padrão se omitido

-- Teste 2: Modo STRICT - dispara erro de execução Msg 13608
BEGIN TRY
    SELECT JSON_VALUE(@json, 'strict $.age') AS AgeStrict;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO STRICT: ' + ERROR_MESSAGE();
END CATCH;
GO


-- =================================================================================
-- PARTE 4: OPENJSON - DESMEMBRANDO O JSON EM TABELA RELACIONAL
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - OPENJSON(): Função de tabela com valor que analisa um texto JSON e retorna suas propriedades 
--     em um formato tabular (linhas e colunas).
--   - OPENJSON SEM CLAUSULA WITH: Retorna uma estrutura padrão rígida com 3 colunas:
--     * key: Nome da propriedade (ou índice numérico no caso de arrays).
--     * value: Valor do elemento.
--     * type: Inteiro que mapeia o tipo do dado (0: Null, 1: String, 2: Number, 3: Boolean, 4: Array, 5: Object).
--   - OPENJSON COM CLAUSULA WITH: Permite declarar explicitamente o esquema da tabela resultante, definindo
--     nomes de colunas, tipos SQL e caminhos JSON correspondentes (ex: `Carrier VARCHAR(50) '$.delivery.carrier'`).
--   - MODIFICADOR AS JSON: Instrução especial na cláusula `WITH` necessária quando uma coluna mapeada deve
--     conter um sub-objeto ou sub-array inteiro em vez de um valor escalar. Sem ele, o SQL retorna NULL.
--   - CROSS APPLY VS OUTER APPLY:
--     * CROSS APPLY: Funciona como INNER JOIN. Se o sub-array '$.items' estiver vazio ([]), ausente ou for NULL,
--       a linha da tabela pai é totalmente DESCARTADA do resultado final.
--     * OUTER APPLY: Funciona como LEFT OUTER JOIN. Se o sub-array '$.items' estiver vazio ([]) ou ausente,
--       a linha da tabela pai É PRESERVADA no resultado final e as colunas do JSON vêm preenchidas com NULL.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. No exame, preste atenção se o requisito exige "manter pedidos sem itens na listagem". 
--    Se sim, use OUTER APPLY. Se exigir "apenas pedidos com itens válidos", use CROSS APPLY.
-- 2. Não existe a sintaxe "CROSS OUTER APPLY" no T-SQL; escolha explicitamente CROSS APPLY ou OUTER APPLY.

DECLARE @json NVARCHAR(MAX);
SELECT TOP 1
    @json = OrderDetails
FROM lab.OrdersJSON
WHERE CustomerName = 'Alice Smith';

-- 1. OPENJSON sem a cláusula WITH
-- Retorna uma tabela padrão com três colunas: key, value e type.
-- Type: 1 = String, 2 = Number, 3 = Boolean, 4 = Array, 5 = Object, 0 = Null
SELECT *
FROM OPENJSON(@json);

-- 2. OPENJSON com a cláusula WITH (Documento Raiz)
-- Mapeia diretamente propriedades do JSON em colunas tipadas definidas pelo usuário.
SELECT *
FROM OPENJSON(@json)
WITH (
    Region NVARCHAR(50) '$.region',
    CarrierName NVARCHAR(50) '$.delivery.carrier',
    DeliveryDays INT '$.delivery.days',
    ItemsRaw NVARCHAR(MAX) '$.items' AS JSON -- 'AS JSON' impede que a estrutura do array seja desfeita
);

-- 3. Consulta isolada do lado direito do CROSS APPLY (usando variável @json):
SELECT
    Product,
    Qty,
    Price,
    (Qty * Price) AS LineTotal
FROM OPENJSON(@json, '$.items')
WITH (
    Product NVARCHAR(100) '$.product',
    Qty     INT           '$.qty',
    Price   DECIMAL(18,2) '$.price'
);

-- 3.b Subconsulta Inline direta no primeiro parâmetro do OPENJSON (sem precisar de variável @json):
-- Permite testar rapidamente a leitura de qualquer caminho (path) em linhas reais da tabela!
SELECT
    Product,
    Qty,
    Price,
    (Qty * Price) AS LineTotal
FROM OPENJSON(
    (SELECT TOP 1 OrderDetails FROM lab.OrdersJSON WHERE CustomerName = 'Alice Smith'),
    '$.items' -- Alterando este caminho você navega por partes diferentes do JSON (ex: '$', '$.delivery', '$.items')
)
WITH (
    Product NVARCHAR(100) '$.product',
    Qty     INT           '$.qty',
    Price   DECIMAL(18,2) '$.price'
);

-- 4. CROSS APPLY com OPENJSON (Comportamento de INNER JOIN)
-- Se um pedido tiver o array '$.items' vazio ([]) ou ausente (NULL), a linha do pedido É DESCARTADA do resultado.
SELECT
    o.OrderID,
    o.CustomerName,
    item.Product,
    item.Qty,
    item.Price,
    (item.Qty * item.Price) AS LineTotal
FROM lab.OrdersJSON o
CROSS APPLY OPENJSON(o.OrderDetails, '$.items')
WITH (
    Product NVARCHAR(100) '$.product',
    Qty     INT           '$.qty',
    Price   DECIMAL(18,2) '$.price'
) AS item;

-- 5. OUTER APPLY com OPENJSON (Comportamento de LEFT OUTER JOIN)
-- Mesmo que um pedido tenha '$.items' vazio ([]) ou ausente, a linha do pedido É PRESERVADA no resultado (preenchendo os itens com NULL).
SELECT
    o.OrderID,
    o.CustomerName,
    item.Product,
    item.Qty,
    item.Price,
    (item.Qty * item.Price) AS LineTotal
FROM lab.OrdersJSON o
OUTER APPLY OPENJSON(o.OrderDetails, '$.items')
WITH (
    Product NVARCHAR(100) '$.product',
    Qty     INT           '$.qty',
    Price   DECIMAL(18,2) '$.price'
) AS item;
GO




-- =================================================================================
-- PARTE 5: AGREGADORES MODERNOS (JSON_ARRAYAGG E JSON_OBJECTAGG)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - JSON_ARRAYAGG: Função de agregação que agrupa valores de uma coluna de dados e os converte 
--     em um único array JSON lógicos (ex: `["Produto A", "Produto B"]`). Substitui a antiga necessidade
--     de usar hacks complexos de string concatenando caracteres.
--   - JSON_OBJECTAGG: Função de agregação que cria um objeto JSON a partir de dois campos chave-valor
--     extraídos de uma tabela relacional (ex: `{"ChaveA": "ValorA", "ChaveB": "ValorB"}`).
--   - PLATAFORMA: Use estes exemplos no Azure SQL Database/Managed Instance ou no SQL Server 2025,
--     onde os agregadores estão em preview. Eles não são recursos do SQL Server 2022.

-- 1. Criando um Array JSON dos nomes de produtos por categoria
SELECT
    pc.Name AS Categoria,
    JSON_ARRAYAGG(p.Name ORDER BY p.Name) AS Produtos
FROM Production.Product p
    JOIN Production.ProductSubcategory ps ON p.ProductSubcategoryID = ps.ProductSubcategoryID
    JOIN Production.ProductCategory pc ON ps.ProductCategoryID = pc.ProductCategoryID
GROUP BY pc.Name;

-- 2. Criando um objeto JSON de produtos por categoria.
-- Cada ProductID torna-se uma propriedade e o nome do produto vira o valor.
-- [PONTO DE ATENÇÃO DP-800] JSON_OBJECTAGG agrega pares chave:valor, ao contrário de
-- JSON_ARRAYAGG, que agrega apenas valores em uma lista.
SELECT
    pc.Name AS Categoria,
    JSON_OBJECTAGG(CONVERT(NVARCHAR(10), p.ProductID): p.Name) AS ProdutosPorId
FROM Production.Product AS p
JOIN Production.ProductSubcategory AS ps
    ON p.ProductSubcategoryID = ps.ProductSubcategoryID
JOIN Production.ProductCategory AS pc
    ON ps.ProductCategoryID = pc.ProductCategoryID
GROUP BY pc.Name;

-- 3. Gerando um payload JSON aninhado complexo (Pedidos com Array de Itens)
SELECT
    soh.SalesOrderID,
    soh.OrderDate,
    JSON_ARRAYAGG(JSON_OBJECT(
        'productID': sod.ProductID,
        'qty': sod.OrderQty,
        'price': sod.UnitPrice
    )) AS ItensDoPedido
FROM Sales.SalesOrderHeader soh
    JOIN Sales.SalesOrderDetail sod ON soh.SalesOrderID = sod.SalesOrderID
WHERE soh.SalesOrderID BETWEEN 43659 AND 43662
GROUP BY soh.SalesOrderID, soh.OrderDate;
GO


-- =================================================================================
-- PARTE 6: INDEXAÇÃO DE JSON VIA COMPUTED COLUMNS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - LIMITAÇÃO DE INDEXAÇÃO JSON: Em tabelas com JSON baseado em texto (`NVARCHAR(MAX)`), o SQL Server não
--     não indexa o caminho JSON diretamente. Sem um índice equivalente, a consulta pode exigir uma varredura;
--     sempre confirme o plano de execução e o custo estimado.
--   - COMPUTED COLUMN: Extraia o caminho com JSON_VALUE para uma coluna calculada e crie um índice rowstore
--     convencional. Para JSON_VALUE, a coluna não precisa ser PERSISTED para ser indexada, desde que a expressão
--     cumpra os requisitos usuais de determinismo e precisão.
--   - INDEXAÇÃO DO JSON: O índice na coluna calculada habilita buscas seletivas no valor interno do JSON.

-- 1. Popule a tabela com 1.000 linhas 100% aleatórias (usando ABS(CHECKSUM(NEWID())) por atributo)
WITH
    Numbers
    AS
    (
        SELECT TOP (1000)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
    )
INSERT INTO lab.OrdersJSON
    (CustomerName, OrderDetails)
SELECT
    CONCAT('Customer_', n) AS CustomerName,
    JSON_OBJECT(
        'region': CASE (ABS(CHECKSUM(NEWID())) % 4) 
                    WHEN 0 THEN 'North' 
                    WHEN 1 THEN 'South' 
                    WHEN 2 THEN 'East' 
                    ELSE 'West' 
                  END,
        'delivery': JSON_OBJECT(
            'carrier': CASE (ABS(CHECKSUM(NEWID())) % 4) 
                        WHEN 0 THEN 'FedEx' 
                        WHEN 1 THEN 'DHL' 
                        WHEN 2 THEN 'Correios' 
                        ELSE 'UPS' 
                       END,
            'days': (ABS(CHECKSUM(NEWID())) % 10) + 1
        ),
        'items': CASE WHEN (ABS(CHECKSUM(NEWID())) % 5) = 0 THEN JSON_ARRAY() -- 20% dos pedidos ficam sem itens (array []) para testar CROSS vs OUTER APPLY
                 ELSE JSON_ARRAY(
                    JSON_OBJECT('product': 'Bike Helmet', 'qty': (ABS(CHECKSUM(NEWID())) % 3) + 1, 'price': 50.00),
                    JSON_OBJECT('product': 'Water Bottle', 'qty': (ABS(CHECKSUM(NEWID())) % 4) + 1, 'price': 10.00)
                 )
            END
    ) AS OrderDetails
FROM Numbers;
GO

-- 2. Habilite estatísticas de I/O
SET STATISTICS IO ON;
GO

-- Teste 1: Consulta filtrando propriedade JSON antes de criar o índice.
-- PLANO DE EXECUÇÃO: com este volume, é comum observar Clustered Index Scan, mas o plano depende
-- dos dados, das estatísticas e do custo estimado.
SELECT CustomerName, OrderDetails
FROM lab.OrdersJSON
WHERE JSON_VALUE(OrderDetails, '$.region') = 'South';
GO

-- 3. Criar a computed column extraindo a propriedade do JSON
-- NOTA DE ARCHITECTURE / DP-800:
--   - O JSON_VALUE retorna por padrão NVARCHAR(4000) (que ocupa 8.000 bytes).
--   - O limite máximo para a CHAVE de um índice não-clusterizado é 1.700 bytes.
--   - Se não usarmos CAST, o SQL Server emite um WARNING de 8.000 bytes.
--   - SOLUÇÃO: Aplicar CAST(JSON_VALUE(...) AS NVARCHAR(50)) para definir o tamanho exato e eliminar avisos.
--ALTER TABLE lab.OrdersJSON
--drop column Region 
--GO
ALTER TABLE lab.OrdersJSON
ADD Region AS CAST(JSON_VALUE(OrderDetails, '$.region') AS NVARCHAR(50));
GO

-- 4. Criar o índice não clusterizado COBERTO (Covering Index) na coluna calculada
-- CONCEITOS E DEFINIÇÕES CHAVE (ÍNDICE COBERTO VS KEY LOOKUP):
--   - SEM INCLUDE: O índice guarda apenas (Region + PK OrderID). Para retornar CustomerName e OrderDetails,
--     o SQL Server faz um "Index Seek" no índice e depois um "Key Lookup" na tabela principal para cada linha.
--   - COM INCLUDE: Adicionar 'INCLUDE (CustomerName, OrderDetails)' armazena essas colunas diretamente nas páginas
--     folhas do índice. Isso o transforma em um ÍNDICE COBERTO (Covering Query). A consulta satisfaz 100% dos dados
--     diretamente no índice, ELIMINANDO O KEY LOOKUP e fazendo apenas um INDEX SEEK puro ultra rápido!


--drop INDEX IX_OrdersJSON_Region_Covered
--ON lab.OrdersJSON 


CREATE NONCLUSTERED INDEX IX_OrdersJSON_Region_Covered
ON lab.OrdersJSON(Region) 
INCLUDE (CustomerName, OrderDetails);
GO

-- Teste 2.a: Consulta filtrando pela expressão JSON_VALUE
SELECT CustomerName, OrderDetails
FROM lab.OrdersJSON
WHERE JSON_VALUE(OrderDetails, '$.region') = 'South';
GO

-- Teste 2.b: Consulta SARGável filtrando diretamente pela coluna calculada 'Region'
-- Como o índice inclui (CustomerName, OrderDetails), o plano executa um INDEX SEEK puro sem Key Lookup!
SELECT CustomerName, OrderDetails
FROM lab.OrdersJSON WITH (INDEX (IX_OrdersJSON_Region_Covered))
WHERE Region = 'South';
GO

SET STATISTICS IO OFF;
GO


-- =================================================================================
-- PARTE 7: CONSULTAS DINÂMICAS T-SQL GERADAS A PARTIR DE ESQUEMA JSON (METADADOS)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CONSULTAS DINÂMICAS DRIVEN BY METADATA: É perfeitamente possível (e muito comum em arquiteturas modernas
--     de ETL, Data Mesh e EAV) armazenar a definição de campos/mapeamentos JSON em uma tabela de metadados.
--   - MECANISMO:
--     1. Uma tabela armazena a estrutura do esquema desejado em formato JSON.
--     2. Com `OPENJSON`, lemos esses metadados (nomes de colunas, paths e se é escalar ou objeto).
--     3. Usamos `STRING_AGG` para concatenar a instrução `SELECT` dinamicamente com `JSON_VALUE` ou `JSON_QUERY`.
--     4. Executamos com `sp_executesql` garantindo segurança e flexibilidade.

-- 1. Criar a tabela de Metadados de Esquema
DROP TABLE IF EXISTS lab.DynamicJsonMapping;
CREATE TABLE lab.DynamicJsonMapping
(
    MappingID INT IDENTITY(1,1) PRIMARY KEY,
    TargetTableName NVARCHAR(100) NOT NULL,
    SchemaDefinition NVARCHAR(MAX) NOT NULL
);
GO

-- 2. Inserir a definição do esquema dinâmico em formato JSON
INSERT INTO lab.DynamicJsonMapping
    (TargetTableName, SchemaDefinition)
VALUES
    (
        'OrdersJSON',
        N'[
        {"ColumnAlias": "RegiaoPedido", "JsonPath": "$.region", "DataType": "NVARCHAR(50)", "IsScalar": 1},
        {"ColumnAlias": "Transportadora", "JsonPath": "$.delivery.carrier", "DataType": "NVARCHAR(50)", "IsScalar": 1},
        {"ColumnAlias": "ObjetoEntregaCompleto", "JsonPath": "$.delivery", "DataType": "NVARCHAR(MAX)", "IsScalar": 0}
    ]'
);
GO

-- 3. Procedure/Bloco T-SQL para montar e executar a query dinamicamente
DECLARE @TargetTable NVARCHAR(100) = 'OrdersJSON';
DECLARE @SchemaJson NVARCHAR(MAX);
DECLARE @DynamicSql NVARCHAR(MAX);
DECLARE @ColumnSelectList NVARCHAR(MAX);

-- Buscar a definição de esquema JSON armazenada na tabela de metadados
SELECT @SchemaJson = SchemaDefinition
FROM lab.DynamicJsonMapping
WHERE TargetTableName = @TargetTable;

-- Desmembrar a definição com OPENJSON e construir as cláusulas de seleção usando STRING_AGG
SELECT @ColumnSelectList = STRING_AGG(
    CASE 
        WHEN IsScalar = 1 THEN CONCAT('JSON_VALUE(OrderDetails, ''', JsonPath, ''') AS [', ColumnAlias, ']')
        ELSE CONCAT('JSON_QUERY(OrderDetails, ''', JsonPath, ''') AS [', ColumnAlias, ']')
    END,
    ',' + CHAR(10) + '    '
)
FROM OPENJSON(@SchemaJson)
WITH (
    ColumnAlias NVARCHAR(100) '$.ColumnAlias',
    JsonPath    NVARCHAR(200) '$.JsonPath',
    DataType    NVARCHAR(50)  '$.DataType',
    IsScalar    BIT           '$.IsScalar'
);

-- Montar a instrução SELECT completa
SET @DynamicSql = CONCAT(
    'SELECT CustomerName, ', CHAR(10), '    ', @ColumnSelectList, CHAR(10),
    'FROM lab.OrdersJSON;'
);

-- Exibir a instrução T-SQL que foi gerada automaticamente
PRINT '=== T-SQL DINÂMICO GERADO A PARTIR DOS METADADOS JSON ===';
PRINT @DynamicSql;

-- Executar a consulta gerada dinamicamente
EXEC sp_executesql @DynamicSql;
GO


-- =================================================================================
-- PARTE 8: ENCAPSULAMENTO EM STORED PROCEDURE 100% DINÂMICA
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CONSULTAS 100% DINÂMICAS DRIVEN BY METADATA: Em vez de hardcodear nomes de tabelas ou chaves,
--     a Stored Procedure lê TODOS os metadados (Esquema, Tabela, Colunas de Chave Primária, Coluna JSON e Mapeamentos).
--   - MECANISMO:
--     1. Uma tabela de metadados flexível registra a tabela alvo, quais colunas chave selecionar, a coluna JSON e o mapeamento dos atributos.
--     2. A procedure `lab.sp_ExecuteFullyDynamicJsonQuery` inspeciona a tabela de mapeamento.
--     3. Constrói 100% dinamicamente as cláusulas SELECT, FROM, nomes de colunas e funções JSON_VALUE / JSON_QUERY sem nenhum hardcode.
--     4. Executa com `sp_executesql`.

-- 1. Criar a tabela de Metadados de Esquema 100% Flexível
DROP TABLE IF EXISTS lab.FullyDynamicJsonMapping;
CREATE TABLE lab.FullyDynamicJsonMapping (
    MappingID INT IDENTITY(1,1) PRIMARY KEY,
    SchemaName NVARCHAR(128) NOT NULL DEFAULT 'lab',
    TargetTableName NVARCHAR(128) NOT NULL,
    KeyColumns NVARCHAR(250) NOT NULL, -- Colunas da tabela relacional a preservar no SELECT
    JsonColumnName NVARCHAR(128) NOT NULL, -- Nome da coluna física contendo o JSON
    SchemaDefinition NVARCHAR(MAX) NOT NULL
);
GO

-- 2. Inserir a definição do esquema dinâmico em formato JSON
INSERT INTO lab.FullyDynamicJsonMapping (SchemaName, TargetTableName, KeyColumns, JsonColumnName, SchemaDefinition)
VALUES (
    'lab',
    'OrdersJSON',
    'OrderID, CustomerName',
    'OrderDetails',
    N'[
        {"ColumnAlias": "RegiaoPedido", "JsonPath": "$.region", "DataType": "NVARCHAR(50)", "IsScalar": 1},
        {"ColumnAlias": "Transportadora", "JsonPath": "$.delivery.carrier", "DataType": "NVARCHAR(50)", "IsScalar": 1},
        {"ColumnAlias": "ObjetoEntregaCompleto", "JsonPath": "$.delivery", "DataType": "NVARCHAR(MAX)", "IsScalar": 0}
    ]'
);
GO

-- 3. Stored Procedure 100% Dinâmica para qualquer Tabela e qualquer JSON
CREATE OR ALTER PROCEDURE lab.sp_ExecuteFullyDynamicJsonQuery
    @TargetTableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SchemaName NVARCHAR(128);
    DECLARE @KeyColumns NVARCHAR(250);
    DECLARE @JsonColumnName NVARCHAR(128);
    DECLARE @SchemaJson NVARCHAR(MAX);
    DECLARE @ColumnSelectList NVARCHAR(MAX);
    DECLARE @DynamicSql NVARCHAR(MAX);

    -- 1. Buscar TODOS os metadados da tabela a partir do repositório de mapeamento
    SELECT 
        @SchemaName = SchemaName,
        @KeyColumns = KeyColumns,
        @JsonColumnName = JsonColumnName,
        @SchemaJson = SchemaDefinition 
    FROM lab.FullyDynamicJsonMapping 
    WHERE TargetTableName = @TargetTableName;

    IF @SchemaJson IS NULL
    BEGIN
        RAISERROR('Nenhum mapeamento de metadados encontrado para a tabela %s', 16, 1, @TargetTableName);
        RETURN;
    END;

    -- 2. Desmembrar o esquema com OPENJSON e construir as expressões de extração JSON usando STRING_AGG
    SELECT @ColumnSelectList = STRING_AGG(
        CASE 
            WHEN IsScalar = 1 THEN CONCAT('JSON_VALUE(', QUOTENAME(@JsonColumnName), ', ''', JsonPath, ''') AS [', ColumnAlias, ']')
            ELSE CONCAT('JSON_QUERY(', QUOTENAME(@JsonColumnName), ', ''', JsonPath, ''') AS [', ColumnAlias, ']')
        END,
        ',' + CHAR(10) + '    '
    )
    FROM OPENJSON(@SchemaJson)
    WITH (
        ColumnAlias NVARCHAR(100) '$.ColumnAlias',
        JsonPath    NVARCHAR(200) '$.JsonPath',
        DataType    NVARCHAR(50)  '$.DataType',
        IsScalar    BIT           '$.IsScalar'
    );

    -- 3. Montar a instrução SELECT 100% dinamicamente (Sem nenhum hardcode de tabela ou coluna!)
    SET @DynamicSql = CONCAT(
        'SELECT ', @KeyColumns, ', ', CHAR(10), '    ', @ColumnSelectList, CHAR(10),
        'FROM ', QUOTENAME(@SchemaName), '.', QUOTENAME(@TargetTableName), ';'
    );

    -- 4. Exibir o T-SQL gerado para auditoria
    PRINT '================ T-SQL 100% DINÂMICO GERADO VIA METADADOS ================';
    PRINT @DynamicSql;

    -- 5. Executar a consulta
    EXEC sp_executesql @DynamicSql;
END;
GO

-- Teste de Execução da Stored Procedure 100% Dinâmica:
EXEC lab.sp_ExecuteFullyDynamicJsonQuery @TargetTableName = 'OrdersJSON';
GO
