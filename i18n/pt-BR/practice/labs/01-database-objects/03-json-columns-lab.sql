-- =============================================================================
-- DP-800 - LAB PRÁTICO: COLUNAS, ÍNDICES JSON E DESEMPENHO
-- Pré-requisito: AdventureWorks2025 restaurado. O script altera apenas objetos lab.
-- Habilite o plano de execução real no SSMS/ADS antes das Partes 4 a 6.
-- Objetivo: decidir o que permanece relacional e quando um atributo JSON merece
-- uma projeção indexável. Este não é um lab de OPENJSON: parsing e serialização
-- ficam no lab de Funções JSON.
--
-- Antes de começar, anote para cada experimento: leituras lógicas, CPU, duração,
-- linhas estimadas/reais e operadores. Não compare apenas o ícone Scan/Seek.
-- =============================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/01-database-objects/03-json-columns.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =============================================================================

USE AdventureWorks2025;
GO

-- Obrigatórias para criar e usar índices em colunas computadas.
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
DROP TABLE IF EXISTS lab.JsonColumnsOrders;
DROP TABLE IF EXISTS lab.JsonColumnsNative;
GO

-- PARTE 1: DADOS REAIS COMO COLUNAS RELACIONAIS E DOCUMENTO FLEXÍVEL
-- SalesOrderID, data, cliente e valor são usados em chaves, joins e agregações;
-- por isso permanecem como colunas. Entrega, território e linhas do pedido são
-- reunidos no documento para representar uma área flexível do payload.
CREATE TABLE lab.JsonColumnsOrders
(
    SalesOrderID int NOT NULL CONSTRAINT PK_JsonColumnsOrders PRIMARY KEY,
    OrderDate datetime NOT NULL,
    CustomerID int NOT NULL,
    TotalDue money NOT NULL,
    OrderDocument nvarchar(max) NOT NULL,
    CONSTRAINT CK_JsonColumnsOrders_Document CHECK (ISJSON(OrderDocument) = 1)
);
GO

INSERT INTO lab.JsonColumnsOrders
    (SalesOrderID, OrderDate, CustomerID, TotalDue, OrderDocument)
SELECT TOP (5000)
    h.SalesOrderID, h.OrderDate, h.CustomerID, h.TotalDue,
    (
        SELECT st.Name AS [territory.name], cr.CountryRegionCode AS [territory.countryCode],
               a.City AS [shipping.city], sp.StateProvinceCode AS [shipping.stateProvince],
               JSON_QUERY((
                   SELECT d.SalesOrderDetailID AS [lineId], p.ProductNumber AS [product.number],
                          p.Name AS [product.name], d.OrderQty AS [quantity], d.UnitPrice AS [unitPrice]
                   FROM Sales.SalesOrderDetail AS d
                   JOIN Production.Product AS p ON p.ProductID = d.ProductID
                   WHERE d.SalesOrderID = h.SalesOrderID FOR JSON PATH
               )) AS [items]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )
FROM Sales.SalesOrderHeader AS h
JOIN Sales.SalesTerritory AS st ON st.TerritoryID = h.TerritoryID
JOIN Person.Address AS a ON a.AddressID = h.ShipToAddressID
JOIN Person.StateProvince AS sp ON sp.StateProvinceID = a.StateProvinceID
JOIN Person.CountryRegion AS cr ON cr.CountryRegionCode = sp.CountryRegionCode
ORDER BY h.SalesOrderID;
GO

SELECT COUNT(*) AS Orders, MAX(JSON_VALUE(OrderDocument, '$.territory.name')) AS ExampleTerritory
FROM lab.JsonColumnsOrders;
GO

-- Inspecione uma amostra. A mesma informação de país aparece no documento, mas
-- só deverá virar uma coluna quando houver necessidade recorrente de filtrar,
-- relacionar, validar domínio ou aplicar segurança sobre ela.
SELECT TOP (1) SalesOrderID, OrderDate, CustomerID, TotalDue, OrderDocument
FROM lab.JsonColumnsOrders
ORDER BY SalesOrderID;
GO

-- PARTE 2: INTEGRIDADE E LIMITE DE MODELAGEM
-- ISJSON comprova estrutura JSON válida; não comprova que as propriedades de
-- negócio existem, têm tipo correto ou pertencem ao domínio permitido.
BEGIN TRY
    INSERT INTO lab.JsonColumnsOrders
        (SalesOrderID, OrderDate, CustomerID, TotalDue, OrderDocument)
    VALUES (-1, GETDATE(), -1, 0, N'{"shipping":');
END TRY
BEGIN CATCH
    PRINT N'Erro CHECK esperado: ' + ERROR_MESSAGE();
END CATCH;
GO

-- A CHECK com ISJSON não rejeitaria NULL se OrderDocument fosse anulável, porque
-- CHECK só falha quando a expressão é FALSE. Neste lab a coluna é NOT NULL para
-- exigir documento; em um modelo opcional use as duas regras explicitamente:
--   Payload nvarchar(max) NULL,
--   CONSTRAINT CK_Payload CHECK (Payload IS NULL OR ISJSON(Payload) = 1)
-- Para obrigar um objeto (e não array/escalar), SQL Server 2022+ permite:
--   CHECK (ISJSON(Payload, OBJECT) = 1)

-- Chaves, data e medida continuam relacionais; entrega e itens são flexíveis.
SELECT TOP (20) SalesOrderID, CustomerID, TotalDue,
    JSON_VALUE(OrderDocument, '$.territory.name') AS Territory,
    JSON_VALUE(OrderDocument, '$.shipping.city') AS ShipCity
FROM lab.JsonColumnsOrders ORDER BY TotalDue DESC;
GO

-- PARTE 3: LINHA DE BASE - JSON_VALUE SEM CAMINHO DE ACESSO
-- Abra o plano REAL e compare esta consulta com a Parte 4. Sem uma projeção
-- indexada equivalente, o mecanismo avalia JSON_VALUE para as linhas candidatas;
-- em 5.000 linhas isso pode parecer barato, mas o padrão de custo escala com a
-- tabela e com o tamanho do documento.
SET STATISTICS IO, TIME ON;
SELECT SalesOrderID, CustomerID, TotalDue
FROM lab.JsonColumnsOrders
WHERE JSON_VALUE(OrderDocument, '$.territory.countryCode') = N'US';
SET STATISTICS IO, TIME OFF;
GO
-- Diagnóstico aplicado: sintoma = muitas leituras e Scan; hipótese = não há um
-- caminho de acesso para a expressão JSON. Evidência = leituras lógicas, linhas
-- estimadas/reais e operador do plano. Ação da Parte 4 = projetar a expressão em
-- coluna computada. Risco: se o país for pouco seletivo, Scan pode continuar sendo
-- a decisão correta; não force Seek com hint.

-- PARTE 4: SARGABILIDADE POR EXPRESSÃO INDEXADA EQUIVALENTE
-- O CONVERT pequeno evita uma chave nvarchar(4000). A consulta repete a
-- mesma expressão para que o otimizador possa associá-la à coluna computada.
-- JSON_VALUE por si só retorna nvarchar(4000); indexar essa expressão diretamente
-- pode ultrapassar o limite de chave. Escolha tipo/tamanho pelo domínio real.
ALTER TABLE lab.JsonColumnsOrders
ADD CountryCode AS CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.territory.countryCode'));
GO
CREATE INDEX IX_JsonColumnsOrders_CountryCode ON lab.JsonColumnsOrders (CountryCode);
GO

SET STATISTICS IO, TIME ON;
SELECT SalesOrderID, CustomerID, TotalDue
FROM lab.JsonColumnsOrders
WHERE CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.territory.countryCode')) = N'US';
SET STATISTICS IO, TIME OFF;
GO
-- Diagnóstico aplicado: sintoma = índice localiza linhas, mas pode executar Key
-- Lookup repetido. Evidência = número de execuções do Lookup e leituras adicionais.
-- Ação = comparar o índice estreito com INCLUDE. Risco = o índice coberto melhora
-- leitura, mas custa espaço e manutenção em INSERT/UPDATE/DELETE.

-- Experimente uma por vez e registre o plano. A primeira consulta preserva a
-- expressão indexada; as duas seguintes alteram a expressão ou o padrão de busca.
-- Não conclua que "função sempre impede índice": a questão é equivalência da
-- expressão, seletividade e custo total escolhido pelo otimizador.
SELECT SalesOrderID FROM lab.JsonColumnsOrders
WHERE CountryCode = N'US';
SELECT SalesOrderID FROM lab.JsonColumnsOrders
WHERE UPPER(JSON_VALUE(OrderDocument, '$.territory.countryCode')) = N'US';
SELECT SalesOrderID FROM lab.JsonColumnsOrders WHERE CountryCode LIKE N'%S';
GO

-- PARTE 5: ÍNDICE COBERTO É UMA DECISÃO MEDIDA
-- Um índice estreito pode localizar CountryCode e depois buscar colunas ausentes
-- na tabela (Key Lookup). INCLUDE cobre esta projeção, mas aumenta o tamanho e o
-- custo de manutenção do índice durante escrita.
DROP INDEX IX_JsonColumnsOrders_CountryCode ON lab.JsonColumnsOrders;
GO
CREATE INDEX IX_JsonColumnsOrders_CountryCode
ON lab.JsonColumnsOrders (CountryCode) INCLUDE (CustomerID, TotalDue);
GO
SET STATISTICS IO, TIME ON;
SELECT SalesOrderID, CustomerID, TotalDue
FROM lab.JsonColumnsOrders
WHERE CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.territory.countryCode')) = N'US';
SET STATISTICS IO, TIME OFF;
GO

-- Troque a projeção abaixo por OrderDocument e observe por que o índice acima não
-- "cobre tudo". Incluir nvarchar(max) apenas para eliminar lookup raramente é uma
-- decisão automática; compare o benefício de leitura com o custo de escrita.
SELECT SalesOrderID, CustomerID, TotalDue, OrderDocument
FROM lab.JsonColumnsOrders
WHERE CountryCode = N'US';
GO

-- Confirme também expressão, tipo e collation. Índice filtrado não pode ser criado
-- diretamente sobre coluna computada; use coluna física mantida na carga ou atributo
-- relacional se esse padrão for necessário.

-- PARTE 6: CASOS EXECUTÁVEIS DE DIAGNÓSTICO
-- Caso A — seletividade: antes de criar mais índices, descubra a distribuição.
-- Resultado esperado: valores muito frequentes retornam mais linhas; o otimizador
-- pode escolher scan mesmo havendo índice, pois muitos lookups/seeks seriam piores.
SELECT CountryCode, COUNT(*) AS Pedidos,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS decimal(5, 2)) AS PercentualDoTotal
FROM lab.JsonColumnsOrders
GROUP BY CountryCode
ORDER BY Pedidos DESC;
GO

-- Caso B — predicado residual versus índice composto. CountryCode já possui um
-- índice; StateProvinceCode ainda é extraído do documento durante a primeira busca.
-- No plano, observe o predicado residual, linhas lidas versus retornadas e IO.
ALTER TABLE lab.JsonColumnsOrders
ADD StateProvinceCode AS CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.shipping.stateProvince'));
GO
SET STATISTICS IO, TIME ON;
SELECT SalesOrderID, CustomerID, TotalDue
FROM lab.JsonColumnsOrders
WHERE CountryCode = N'US'
  AND CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.shipping.stateProvince')) = N'WA';
SET STATISTICS IO, TIME OFF;
GO

-- Ação aplicada: o índice composto representa o filtro de dois atributos. Repita
-- exatamente a mesma consulta e compare evidências, não apenas o operador exibido.
CREATE INDEX IX_JsonColumnsOrders_CountryCode_StateProvinceCode
ON lab.JsonColumnsOrders (CountryCode, StateProvinceCode) INCLUDE (CustomerID, TotalDue);
GO
SET STATISTICS IO, TIME ON;
SELECT SalesOrderID, CustomerID, TotalDue
FROM lab.JsonColumnsOrders
WHERE CountryCode = N'US'
  AND CONVERT(nvarchar(3), JSON_VALUE(OrderDocument, '$.shipping.stateProvince')) = N'WA';
SET STATISTICS IO, TIME OFF;
GO

-- Diagnóstico já aplicado ao Caso B:
-- Evidência inicial: CountryCode limita o conjunto, porém StateProvinceCode é
-- avaliado como residual; a diferença entre linhas lidas e retornadas expõe isso.
-- Ação: o índice composto oferece caminho para ambos os atributos. Risco: aumenta
-- escrita e espaço; mantenha-o somente se esse padrão de filtro for recorrente.
-- Se estimadas e reais divergem muito, examine estatísticas, seletividade e tipos
-- antes de culpar o índice. Se houver Sort/Hash com spill, observe memory grant e
-- reduza linhas cedo; atualize estatísticas somente quando houver evidência.

-- Caso C — projeção larga. O índice coberto atende CustomerID/TotalDue, mas não o
-- documento inteiro. Esta consulta demonstra por que "incluir tudo" não é resposta
-- automática para um Key Lookup: OrderDocument pode ser grande e caro de manter.
SET STATISTICS IO, TIME ON;
SELECT SalesOrderID, CustomerID, TotalDue, OrderDocument
FROM lab.JsonColumnsOrders
WHERE CountryCode = N'US'
  AND StateProvinceCode = N'WA';
SET STATISTICS IO, TIME OFF;
GO
-- Diagnóstico já aplicado ao Caso C:
-- Evidência: compare Lookup/leituras com a Parte 5, que não projeta o documento.
-- Ação: retornar menos colunas, buscar o documento sob demanda ou separar o
-- atributo consultado para o modelo relacional. Não inclua nvarchar(max) no índice
-- apenas para eliminar um Lookup sem medir o efeito em INSERT/UPDATE/DELETE.

-- Decisão de modelagem após os casos: se CountryCode/StateProvinceCode participam
-- de joins, segurança ou filtros críticos, são obrigatórios e têm domínio estável,
-- compare o custo desses índices com uma coluna relacional. O documento JSON não
-- precisa carregar atributos que o modelo relacional deve governar diretamente.

-- ISJSON não aceita texto malformado, mas uma CHECK permite NULL quando a coluna
-- é anulável. Esta tabela usa NOT NULL. Em SQL Server 2022+, valide o formato:
SELECT ISJSON(OrderDocument) AS DocumentoValido,
       ISJSON(OrderDocument, OBJECT) AS DocumentoEObjeto
FROM lab.JsonColumnsOrders
WHERE SalesOrderID = (SELECT MIN(SalesOrderID) FROM lab.JsonColumnsOrders);
GO

-- Recurso SQL Server 2025 on-premises: tipo json e JSON index. O bloco cria uma
-- tabela isolada, carrega documentos já gerados e mede uma consulta. Em versões
-- anteriores ele é pulado sem impedir os experimentos nvarchar(max) deste lab.
DECLARE @MajorVersionNative int = TRY_CONVERT(int, SERVERPROPERTY(N'ProductMajorVersion'));
DECLARE @CompatibilityLevelNative int = CONVERT(int, DATABASEPROPERTYEX(DB_NAME(), N'CompatibilityLevel'));

IF @MajorVersionNative >= 17 AND @CompatibilityLevelNative >= 170
BEGIN
    EXEC sys.sp_executesql N'
        CREATE TABLE lab.JsonColumnsNative
        (
            EventId int NOT NULL PRIMARY KEY CLUSTERED,
            Payload json NOT NULL
        );

        INSERT INTO lab.JsonColumnsNative (EventId, Payload)
        SELECT SalesOrderID, OrderDocument
        FROM lab.JsonColumnsOrders;

        CREATE JSON INDEX IX_JsonColumnsNative_Payload
            ON lab.JsonColumnsNative (Payload) FOR (''$.territory.countryCode'');

        SET STATISTICS IO, TIME ON;
        SELECT EventId
        FROM lab.JsonColumnsNative
        WHERE JSON_VALUE(Payload, ''$.territory.countryCode'') = N''US'';
        SET STATISTICS IO, TIME OFF;';
    PRINT N'Teste de tipo json e JSON index executado no SQL Server 2025 on-premises.';
END
ELSE
BEGIN
    PRINT N'Teste de tipo json/JSON index ignorado: exige SQL Server 2025 (17.x) e compatibilidade 170.';
END;
GO

-- Referência manual equivalente, preservada para estudo:
-- CREATE TABLE lab.JsonColumnsNative
-- (EventId int NOT NULL PRIMARY KEY CLUSTERED, Payload json NOT NULL);
-- CREATE JSON INDEX IX_JsonColumnsNative_Payload
--     ON lab.JsonColumnsNative (Payload) FOR ('$.territory.countryCode');

-- Limpeza opcional:
-- DROP TABLE IF EXISTS lab.JsonColumnsNative;
-- DROP TABLE IF EXISTS lab.JsonColumnsOrders;
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/01-database-objects/03-json-columns.md
-- =================================================================================================
