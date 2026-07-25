-- =================================================================================
-- DP-800 - LAB PRÁTICO: BUSCA FULL-TEXT (CONTAINS, FREETEXT, CONTAINSTABLE E STOPLISTS)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o uso de busca linguística nativa no SQL Server:
--   1. Criação de Catálogo e Índice Full-Text (`CREATE FULLTEXT CATALOG` e `INDEX`)
--   2. Predicados de Busca Precisa com `CONTAINS` (Prefixos `"capacete*"`, Proximidade `NEAR`, Inflexão `FORMSOF`)
--   3. Predicado de Busca em Linguagem Natural com `FREETEXT`
--   4. Consultas Ranqueadas com `CONTAINSTABLE` e `FREETEXTTABLE` (Coluna `[RANK]` de 0 a 1000)
--   5. Gerenciamento de Stoplists Customizadas (`sys.fulltext_stopwords`)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID('lab.FtsProductCatalog'))
    DROP FULLTEXT INDEX ON lab.FtsProductCatalog;

IF EXISTS (SELECT * FROM sys.fulltext_catalogs WHERE name = 'LabFtsCatalog')
    DROP FULLTEXT CATALOG LabFtsCatalog;

DROP TABLE IF EXISTS lab.FtsProductCatalog;
GO

-- Estrutura de Tabela para Teste de Busca Full-Text
CREATE TABLE lab.FtsProductCatalog (
    ProductID INT IDENTITY(1,1) PRIMARY KEY, -- Chave única exigida pelo FTS
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL
);
GO

INSERT INTO lab.FtsProductCatalog (ProductName, Description) VALUES
(N'Capacete de Ciclismo Pro', N'Capacete leve com fibra de carbono e fones de ouvido bluetooth embutidos.'),
(N'Bicicleta de Trilha', N'Bicicleta de montanha para corridas com cambio de 24 marchas rapidas.'),
(N'Fones Bluetooth Esportivos', N'Fones de ouvido sem fio bluetooth com cancelamento ativo de ruido.');
GO


-- =================================================================================
-- PARTE 1: CRIAÇÃO DO CATÁLOGO E ÍNDICE FULL-TEXT
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - FULLTEXT CATALOG: Contêiner lógico para os índices de busca full-text.
--   - KEY INDEX: Exige um índice único e não-nulo da tabela (geralmente a Chave Primária PK).
--   - CHANGE_TRACKING = AUTO: O SQL Server atualiza automaticamente o índice invertido conforme as linhas mudam.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Criar o Catálogo Full-Text
CREATE FULLTEXT CATALOG LabFtsCatalog AS DEFAULT;
GO

-- 2. Criar o Índice Full-Text nas colunas ProductName e Description
CREATE FULLTEXT INDEX ON lab.FtsProductCatalog (
    ProductName LANGUAGE 1033, -- 1033 = Inglês
    Description LANGUAGE 1033
)
KEY INDEX PK__FtsProdu__B40CC6ED3DFB3AC5 -- Chave primária da tabela
ON LabFtsCatalog
WITH (CHANGE_TRACKING = AUTO, STOPLIST = SYSTEM);
GO

-- Aguardar popuilação inicial (em ambiente real o índice é populado de forma assíncrona)
WAITFOR DELAY '00:00:02';
GO


-- =================================================================================
-- PARTE 2: PREDICADOS DE BUSCA (CONTAINS VS FREETEXT)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CONTAINS: Busca precisa com suporte a operadores booleanos (AND, OR, NOT), prefixos ("cap*") e proximidade (NEAR).
--   - FREETEXT: Busca semântica em linguagem natural (desconsidera stopwords e aplica flexões verbais).

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Busca com Prefixo (Wildcard de palavra `"capac*"` ou `"fon*"`)
SELECT ProductID, ProductName, Description
FROM lab.FtsProductCatalog
WHERE CONTAINS(Description, '"fon*" OR "capac*"');
GO

-- 2. Busca de Proximidade com NEAR (Palavras que aparecem próximas)
SELECT ProductID, ProductName, Description
FROM lab.FtsProductCatalog
WHERE CONTAINS(Description, 'NEAR((fones, bluetooth), 5)');
GO

-- 3. Busca de Linguagem Natural com FREETEXT
SELECT ProductID, ProductName, Description
FROM lab.FtsProductCatalog
WHERE FREETEXT(Description, 'fones de ouvido sem fio confortaveis');
GO


-- =================================================================================
-- PARTE 3: CONSULTAS RANQUEADAS (FREETEXTTABLE E CONTAINSTABLE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - FREETEXTTABLE / CONTAINSTABLE: Funções de tabela que retornam a coluna `[KEY]` (ID) e `[RANK]` (0 a 1000).
--     Permitem ordenar os resultados por relevância ou filtrar os N melhores resultados (`TOP N`).

-- -- [PONTO DE ATENÇÃO DP-800]
SELECT 
    p.ProductID,
    p.ProductName,
    ft.[RANK] AS RelevanciaScore
FROM FREETEXTTABLE(lab.FtsProductCatalog, Description, 'bluetooth capacete', 10) AS ft
JOIN lab.FtsProductCatalog p ON p.ProductID = ft.[KEY]
ORDER BY ft.[RANK] DESC;
GO


-- =================================================================================
-- PARTE 4: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz Comparativa CONTAINS vs FREETEXT para o Exame DP-800
-- Guia de decisão de sintaxe para o desenvolvimento de mecanismos de busca.

SELECT 
    'CONTAINS' AS Predicado,
    'Precisa / Booleana / Prefixos / Proximidade' AS ModeloBusca,
    'Requer aspas para frases: ''"noise cancelling"''' AS SintaxeExigida,
    'Sistemas de filtro avançado e e-commerce técnico' AS CasoDeUso
UNION ALL
SELECT 
    'FREETEXT',
    'Linguagem Natural (Recall elevado)',
    'Busca simples por texto corrido',
    'Campos de busca globais e Caixas de Busca (Search Bars)';
GO
