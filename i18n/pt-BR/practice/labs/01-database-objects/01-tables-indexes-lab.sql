-- =================================================================================
-- DP-800 - LAB PRÁTICO: TABELAS, TIPOS DE DADOS E ÍNDICES
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/01-database-objects/01-tables-indexes.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script foi desenhado para você executar seção por seção no SSMS ou Azure Data
-- Studio. Ele demonstra na prática cada conceito cobrado no exame DP-800 para a aula 01.
-- 
-- DICA DE EXECUÇÃO (DDL TRIGGERS NO ADVENTUREWORKS):
--   Ao rodar comandos DDL (como CREATE/ALTER/DROP TABLE ou INDEX), você notará nas 
--   estatísticas de IO leituras na tabela 'DatabaseLog' e mensagens como 'CREATE_INDEX...'.
--   Isso ocorre porque o AdventureWorks possui um trigger de auditoria a nível de banco
--   (ddlDatabaseTriggerLog) que grava essas alterações. Caso queira silenciar isso, rode:
--   -> DISABLE TRIGGER ddlDatabaseTriggerLog ON DATABASE;
--   E para reabilitar após os testes:
--   -> ENABLE TRIGGER ddlDatabaseTriggerLog ON DATABASE;
-- =================================================================================
USE AdventureWorks2025;


GO
-- Crie um schema separado para manter seus laboratórios organizados e não alterar 
-- as tabelas originais do AdventureWorks.
IF NOT EXISTS (SELECT *
FROM sys.schemas
WHERE  name = 'lab')
    BEGIN
    EXECUTE ('CREATE SCHEMA lab');
END


-- =================================================================================
-- DP-800 - LAB PRÁTICO: TABELAS, TIPOS DE DADOS E ÍNDICES
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script foi desenhado para você executar seção por seção no SSMS ou Azure Data
-- Studio. Ele demonstra na prática cada conceito cobrado no exame DP-800 para a aula 01.
-- 
-- DICA DE EXECUÇÃO (DDL TRIGGERS NO ADVENTUREWORKS):
--   Ao rodar comandos DDL (como CREATE/ALTER/DROP TABLE ou INDEX), você notará nas 
--   estatísticas de IO leituras na tabela 'DatabaseLog' e mensagens como 'CREATE_INDEX...'.
--   Isso ocorre porque o AdventureWorks possui um trigger de auditoria a nível de banco
--   (ddlDatabaseTriggerLog) que grava essas alterações. Caso queira silenciar isso, rode:
--   -> DISABLE TRIGGER ddlDatabaseTriggerLog ON DATABASE;
--   E para reabilitar após os testes:
--   -> ENABLE TRIGGER ddlDatabaseTriggerLog ON DATABASE;
-- =================================================================================
USE AdventureWorks2025;


GO
-- Crie um schema separado para manter seus laboratórios organizados e não alterar 
-- as tabelas originais do AdventureWorks.
IF NOT EXISTS (SELECT *
FROM sys.schemas
WHERE  name = 'lab')
    BEGIN
    EXECUTE ('CREATE SCHEMA lab');
END


GO
-- Limpeza preventiva caso rode o script mais de uma vez
DROP PROCEDURE IF EXISTS lab.CheckColumnSparsity;
DROP TABLE IF EXISTS lab.ProductAttributesSparse;

DROP TABLE IF EXISTS lab.OrderDesignDemo;

DROP TABLE IF EXISTS lab.SalesOrderDetail_None;

DROP TABLE IF EXISTS lab.SalesOrderDetail_Row;

DROP TABLE IF EXISTS lab.SalesOrderDetail_Page;


GO
-- =================================================================================
-- PARTE 0: PROJETO DA TABELA — TIPOS DE DADOS, DATETIME2 E FILL FACTOR
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - Escolha o menor tipo que atenda à regra de negócio. Para valores monetários, use
--     DECIMAL/NUMERIC, e não FLOAT/REAL, pois eles são aproximados.
--   - DATETIME2 é a escolha usual para novos projetos: oferece faixa e precisão maiores
--     que DATETIME. DATETIMEOFFSET é apropriado quando o fuso também faz parte do dado.
--   - FILL FACTOR reserva espaço nas páginas folha durante criação/rebuild do índice.
--     Reduzi-lo pode diminuir page splits em chaves que recebem inserções no meio, mas
--     aumenta o número de páginas e o custo de leituras. Não é uma configuração padrão.
CREATE TABLE lab.OrderDesignDemo
(
    OrderId       INT IDENTITY(1,1) NOT NULL,
    CustomerId    INT NOT NULL,
    OrderDateUtc  DATETIME2(0) NOT NULL CONSTRAINT DF_OrderDesignDemo_OrderDateUtc DEFAULT SYSUTCDATETIME(),
    TotalAmount   DECIMAL(18,2) NOT NULL,
    CustomerNote  NVARCHAR(500) NULL,
    ExternalCode  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_OrderDesignDemo_ExternalCode DEFAULT NEWSEQUENTIALID(),
    CONSTRAINT PK_OrderDesignDemo PRIMARY KEY CLUSTERED (OrderId)
);
GO

INSERT INTO lab.OrderDesignDemo (CustomerId, TotalAmount, CustomerNote)
VALUES (1, 129.90, N'Pedido de demonstração');
GO

-- [PONTO DE ATENÇÃO DP-800] A chave é CustomerId; OrderDateUtc fica em INCLUDE porque
-- é retornada pela consulta, mas não participa da ordenação nem do predicado.
CREATE NONCLUSTERED INDEX IX_OrderDesignDemo_CustomerId
    ON lab.OrderDesignDemo (CustomerId)
    INCLUDE (OrderDateUtc, TotalAmount)
    WITH (FILLFACTOR = 90);
GO

-- Veja propriedades, fill factor e estatísticas do índice criado.
SELECT i.name, i.type_desc, i.fill_factor, s.name AS StatisticsName, s.auto_created
FROM sys.indexes AS i
LEFT JOIN sys.stats AS s
    ON s.object_id = i.object_id
   AND s.stats_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'lab.OrderDesignDemo');
GO

-- =================================================================================
-- PARTE 0.1: CONVERSÃO IMPLÍCITA DE TIPOS DE DADOS E IMPACTO DE PERFORMANCE
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PRECEDÊNCIA DE TIPOS: Em comparações entre tipos distintos, o SQL Server converte
--     implicitamente o tipo de menor precedência para o de maior precedência.
--   - NVARCHAR (precedência 25) tem MAIOR precedência que VARCHAR (precedência 27).
--   - NON-SARGABLE QUERY: Se a coluna for VARCHAR e a variável for NVARCHAR, a coluna é
--     convertida implicitamente (CONVERT_IMPLICIT). O índice perde o SEEK e vira INDEX SCAN.
DROP TABLE IF EXISTS lab.ImplicitConversionDemo;
GO

CREATE TABLE lab.ImplicitConversionDemo (
    AccountCode VARCHAR(20) NOT NULL,
    AccountName NVARCHAR(100) NOT NULL,
    CreatedDate DATETIME2(0) NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT PK_ImplicitConversionDemo PRIMARY KEY CLUSTERED (AccountCode)
);
GO

-- Popular dados de teste
INSERT INTO lab.ImplicitConversionDemo (AccountCode, AccountName)
VALUES ('ACC-1001', N'Conta Operacional'),
       ('ACC-1002', N'Conta Investimento'),
       ('ACC-1003', N'Conta Reserva');
GO

-- [PONTO DE ATENÇÃO DP-800] CONVERSÃO IMPLÍCITA PREJUDICIAL (Non-Sargable)
-- Variável NVARCHAR comparada com Coluna VARCHAR (causa Index Scan na tabela real)
DECLARE @SearchCodeNVARCHAR NVARCHAR(20) = N'ACC-1001';

SELECT AccountCode, AccountName 
FROM lab.ImplicitConversionDemo
WHERE AccountCode = @SearchCodeNVARCHAR; 
-- No plano de execução, o filtro vira CONVERT_IMPLICIT(nvarchar(20), AccountCode) = @SearchCodeNVARCHAR
GO

-- CORREÇÃO SARGABLE: Garantir que a busca use a mesma família de tipo (VARCHAR)
DECLARE @SearchCodeVARCHAR VARCHAR(20) = 'ACC-1001';

SELECT AccountCode, AccountName 
FROM lab.ImplicitConversionDemo
WHERE AccountCode = @SearchCodeVARCHAR; -- Realiza Seek direto na chave do índice.
GO

-- TENTATIVA DE CONVERSÃO INCORRETA DE STRING PARA INT COM ERRO ESPERADO
BEGIN TRY
    -- String com letras convertida para INT falha em tempo de execução
    SELECT CAST('ACC-1001' AS INT);
END TRY
BEGIN CATCH
    PRINT 'Erro Esperado de Conversão Implícita/Explícita: ' + ERROR_MESSAGE();
END CATCH;
GO

-- =================================================================================
-- PARTE 1: HEAP VS CLUSTERED & OPERADORES RID LOOKUP / KEY LOOKUP
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - HEAP (Pilha): Tabela sem índice clusterizado. Os dados são armazenados de forma
--     desordenada em páginas de dados ligadas por páginas IAM (Index Allocation Map).
--     A engine localiza registros usando um RID físico (FileID:PageID:SlotID).
--   - CLUSTERED TABLE: Tabela com um índice clusterizado. Os dados físicos no nível folha
--     da árvore B-Tree são organizados e ordenados de acordo com a chave do índice.
--   - RID LOOKUP: Operador que ocorre quando buscamos por um índice não-clusterizado em uma
--     Heap, e o SQL precisa ir até a página de dados física buscar colunas não indexadas usando o RID.
--   - KEY LOOKUP: Ocorre em tabelas clusterizadas quando o índice não-clusterizado localiza a
--     chave do índice clusterizado, e o SQL precisa percorrer a B-Tree principal para buscar as demais colunas.
-- 1. Criar uma tabela Heap populada com dados de SalesOrderDetail
SELECT *
INTO   lab.SalesOrderDetailHeap
FROM Sales.SalesOrderDetail;


GO
-- 2. Habilite a exibição do Plano de Execução Atual (Ctrl + M no SSMS)
-- E ative as estatísticas de I/O e Tempo para comparar o esforço de leitura:
-- NOTA IMPORTANTE (PLANO ATUAL VS ESTIMADO): Sempre utilize o "Plano de Execução Atual" (Ctrl + M)
-- ao rodar estes labs. O "Plano Estimado" (Ctrl + L) NÃO executa as linhas de código.
-- Com isso, variáveis locais e diretivas como 'OPTION (RECOMPILE)' (como na Parte 3)
-- não terão seus valores reais avaliados durante a estimativa, gerando planos genéricos
-- incorretos (que ocultam o uso do índice filtrado, por exemplo).
SET STATISTICS IO ON;

SET STATISTICS TIME ON;


GO
-- Teste 1: Busca pontual na Heap
-- PLANO DE EXECUÇÃO: Deve mostrar um "Table Scan" (Varredura de Tabela), pois não há ordem física.
SELECT SalesOrderID,
    SalesOrderDetailID,
    CarrierTrackingNumber
FROM lab.SalesOrderDetailHeap
WHERE  SalesOrderDetailID = 50000;


GO
-- Teste 2: Criando um índice Non-Clustered na Heap
CREATE NONCLUSTERED INDEX NIX_SalesOrderDetailHeap_SalesOrderDetailID
    ON lab.SalesOrderDetailHeap(SalesOrderDetailID);


GO
-- Agora rode a consulta novamente.
-- PLANO DE EXECUÇÃO: Você verá um "Index Seek" no índice não clusterizado recém-criado,
-- seguido por um "RID Lookup" (procura pelo identificador da linha física na Heap) 
-- para buscar a coluna 'CarrierTrackingNumber', que não está no índice.
SELECT SalesOrderID,
    SalesOrderDetailID,
    CarrierTrackingNumber
FROM lab.SalesOrderDetailHeap
WHERE  SalesOrderDetailID = 50000;


GO
-- Teste 3: Converter a Heap em uma Clustered Table
-- Criar a chave primária que por padrão gera um Clustered Index (CIX).
-- NOTA DO EXAME (Estatísticas de IO): Ao rodar este ALTER TABLE, você verá 2 leituras lógicas separadas:
--   1ª Leitura: Varredura na Heap original para extrair os dados, ordenar e montar a B-Tree do Clustered Index.
--   2ª Leitura: Como criamos o NIX_SalesOrderDetailHeap_SalesOrderDetailID anteriormente, o SQL Server 
--               precisa reconstruir esse índice não-clusterizado para atualizar seus ponteiros físicos.
--               Eles deixam de ser RIDs (Row IDs da Heap) e passam a apontar para a nova Clustered Key.
ALTER TABLE lab.SalesOrderDetailHeap
    ADD CONSTRAINT PK_SalesOrderDetailHeap PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID);


GO
-- Se você rodar a consulta agora, o RID Lookup desaparece e vira um "Key Lookup"
-- (pois agora o apontador lógico aponta para a chave Clustered e não mais para um RID de disco).
SELECT SalesOrderID,
    SalesOrderDetailID,
    CarrierTrackingNumber
FROM lab.SalesOrderDetailHeap
WHERE  SalesOrderDetailID = 50000;


GO
SET STATISTICS IO OFF;

SET STATISTICS TIME OFF;


GO
-- =================================================================================
-- PARTE 2: COLUNAS INCLUÍDAS (INCLUDE) E ÍNDICE DE COBERTURA (COVERING INDEX)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - COLUNAS NÃO-CHAVE (INCLUDE): Colunas que são armazenadas apenas no nível folha (último nível) 
--     do índice não-clusterizado. Elas não afetam a ordenação da árvore B-tree do índice e não podem
--     ser usadas em filtros (cláusula WHERE) de forma indexada.
--   - ÍNDICE DE COBERTURA (COVERING INDEX): Um índice não-clusterizado projetado de forma a
--     conter todas as colunas referenciadas na consulta (tanto no SELECT, WHERE, JOIN ou GROUP BY).
--     Como todas as colunas estão contidas no índice, a engine não precisa navegar até a tabela base
--     (Heap ou Clustered Table), eliminando completamente os operadores de Lookup (RID/Key) e reduzindo I/O.

-- 1. Criar uma tabela Rowstore com índice clusterizado para testes
SELECT *
INTO   lab.SalesOrderDetailRowstore
FROM Sales.SalesOrderDetail;

ALTER TABLE lab.SalesOrderDetailRowstore
    ADD CONSTRAINT PK_SalesOrderDetailRowstore PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID);


GO
-- 2. Criar um índice Non-Clustered comum na coluna ProductID
CREATE NONCLUSTERED INDEX NIX_SalesOrderDetailRowstore_ProductID
    ON lab.SalesOrderDetailRowstore(ProductID);


GO
SET STATISTICS IO ON;


GO
-- Teste 1: Consulta gerando Key Lookup
-- Como selecionamos UnitPrice e OrderQty, o SQL Server precisa navegar na B-Tree
-- do índice não-clusterizado de ProductID e depois ir à tabela base via Key Lookup.
SELECT ProductID,
    UnitPrice,
    OrderQty
FROM lab.SalesOrderDetailRowstore
WHERE  ProductID = 776;


GO
-- Teste 2: Substituir o índice simples por um índice de cobertura (Covering Index).
-- DROP_EXISTING só pode recriar um índice que tenha o mesmo nome. Como o índice de
-- cobertura tem outro nome, removemos explicitamente o índice simples antes de criá-lo.
DROP INDEX NIX_SalesOrderDetailRowstore_ProductID
    ON lab.SalesOrderDetailRowstore;

CREATE NONCLUSTERED INDEX NIX_SalesOrderDetailRowstore_ProductID_Covering
    ON lab.SalesOrderDetailRowstore(ProductID)
    INCLUDE(UnitPrice, OrderQty);


GO
-- Rode novamente.
-- PLANO DE EXECUÇÃO: O Key Lookup sumiu! Agora temos apenas um "Index Seek" puro.
-- O custo de I/O (páginas lidas) cai significativamente.
SELECT ProductID,
    UnitPrice,
    OrderQty
FROM lab.SalesOrderDetailRowstore
WHERE  ProductID = 776;


GO
SET STATISTICS IO OFF;


GO
-- =================================================================================
-- PARTE 3: ÍNDICES FILTRADOS (FILTERED INDEXES) E SUAS LIMITAÇÕES
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - ÍNDICE FILTRADO: Um índice não-clusterizado que possui uma cláusula WHERE física associada 
--     (ex: WHERE UnitPrice > 1000). Ele indexa apenas a porção de dados que satisfaz o critério.
--     Reduz drasticamente o tamanho do índice em disco e os tempos de manutenção.
--   - CONSULTAS PARAMETRIZADAS: Para usar um índice filtrado, o otimizador precisa provar que o
--     predicado da consulta implica o filtro do índice. Esse resultado depende da compilação, dos valores,
--     das estatísticas e do custo estimado; não é correto assumir que toda variável sempre o impede.
--   - OPTION (RECOMPILE): Diretiva que força a recompilação da query a cada execução, permitindo que o
--     otimizador substitua o parâmetro pelo valor em tempo de execução literal e use o índice filtrado com segurança.
-- 1. Criar índice filtrado para produtos caros (UnitPrice > 1000)
CREATE NONCLUSTERED INDEX NIX_SalesOrderDetailRowstore_Filtered_Expensive
    ON lab.SalesOrderDetailRowstore(ProductID)
    INCLUDE(UnitPrice) WHERE UnitPrice > 1000;


GO
SET STATISTICS IO ON;


GO
-- Teste 1: Consulta usando valor literal direto na cláusula WHERE.
-- Examine o plano: o índice filtrado é candidato porque UnitPrice > 1050 implica UnitPrice > 1000.
-- A escolha final ainda é baseada em custo e pode variar conforme os dados e as estatísticas.
SELECT ProductID,
    UnitPrice
FROM lab.SalesOrderDetailRowstore
WHERE  ProductID = 776
    AND UnitPrice > 1050;


GO
-- Teste 2: Consulta usando parâmetros/variáveis do SQL.
-- Compare o plano com o anterior. Sem recompilação, o índice filtrado pode não ser elegível
-- quando o otimizador não consegue provar a implicação do filtro durante a compilação.
DECLARE @PriceThreshold AS DECIMAL (18, 2) = 1050.00;

SELECT ProductID,
    UnitPrice
FROM lab.SalesOrderDetailRowstore
WHERE  ProductID = 776
    AND UnitPrice > @PriceThreshold;


GO
-- Teste 3: Como contornar usando OPTION (RECOMPILE)
-- Isso força a recompilação da query avaliando o valor em tempo de execução.
DECLARE @PriceThresholdRec AS DECIMAL (18, 2) = 1050.00;

SELECT ProductID,
    UnitPrice
FROM lab.SalesOrderDetailRowstore
WHERE  ProductID = 776
    AND UnitPrice > @PriceThresholdRec
OPTION
(RECOMPILE);


GO
SET STATISTICS IO OFF;


GO
-- =================================================================================
-- PARTE 4: COMPRESSÃO DE DADOS (ROW E PAGE COMPRESSION)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - COMPRESSÃO ROW (Linha): Reduz o armazenamento alterando o formato físico dos tipos de dados.
--     Valores numéricos de tamanho fixo (ex: INT, BIGINT, DECIMAL) e tipos de caracteres (CHAR) passam 
--     a ocupar apenas o espaço real do dado (ex: um INT com valor 2 consome 1 byte em vez de 4).
--     Possui impacto mínimo na CPU, sendo extremamente recomendada para cargas OLTP.
--   - COMPRESSÃO PAGE (Página): Aplica a compressão ROW e depois executa duas etapas adicionais por página de 8 KB:
--     1. Prefix Compression: Substitui padrões repetitivos no início dos valores de coluna de uma página por tokens curtos.
--     2. Dictionary Compression: Identifica todos os valores repetidos na página inteira e cria um dicionário local.
--     Requer maior consumo de CPU para descompactar na memória, mas gera a maior redução possível de I/O e espaço.
-- 1. Estimar economia de espaço para a compressão do tipo ROW e PAGE
-- O SQL Server nos dá uma prévia sem precisar alterar a tabela real.
EXECUTE sp_estimate_data_compression_savings @schema_name = 'lab', @object_name = 'SalesOrderDetailRowstore', @index_id = 1, -- Clustered Index
@partition_number = NULL, @data_compression = 'ROW';

EXECUTE sp_estimate_data_compression_savings @schema_name = 'lab', @object_name = 'SalesOrderDetailRowstore', @index_id = 1, @partition_number = NULL, @data_compression = 'PAGE';


GO
-- 2. LABORATORIO REAL: Comparar espaço ocupado em disco (None vs ROW vs PAGE)
-- Criamos 3 tabelas idênticas
SELECT *
INTO   lab.SalesOrderDetail_None
FROM Sales.SalesOrderDetail;

SELECT *
INTO   lab.SalesOrderDetail_Row
FROM Sales.SalesOrderDetail;

SELECT *
INTO   lab.SalesOrderDetail_Page
FROM Sales.SalesOrderDetail;


GO
-- Adicionamos Clustered Index em todas elas para organizar as páginas de dados
ALTER TABLE lab.SalesOrderDetail_None
    ADD CONSTRAINT PK_SalesOrderDetail_None PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID);

ALTER TABLE lab.SalesOrderDetail_Row
    ADD CONSTRAINT PK_SalesOrderDetail_Row PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID);

ALTER TABLE lab.SalesOrderDetail_Page
    ADD CONSTRAINT PK_SalesOrderDetail_Page PRIMARY KEY CLUSTERED (SalesOrderID, SalesOrderDetailID);


GO
-- Aplicamos as compressões correspondentes
ALTER TABLE lab.SalesOrderDetail_None REBUILD WITH (DATA_COMPRESSION = NONE);

ALTER TABLE lab.SalesOrderDetail_Row REBUILD WITH (DATA_COMPRESSION = ROW);

ALTER TABLE lab.SalesOrderDetail_Page REBUILD WITH (DATA_COMPRESSION = PAGE);


GO
-- 3. Verificando o tamanho em páginas e KB de cada tabela
-- DMV sys.dm_db_index_physical_stats nos diz quantas páginas físicas de 8KB a tabela ocupa.
SELECT OBJECT_NAME(object_id) AS Tabela,
    index_type_desc AS TipoIndice,
    page_count AS QtdPaginas_8KB,
    (page_count * 8) AS Tamanho_Total_KB,
    CAST (avg_page_space_used_in_percent AS DECIMAL (5, 2)) AS Percentual_Uso_Pagina
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED')
WHERE  object_id IN (OBJECT_ID('lab.SalesOrderDetail_None'), OBJECT_ID('lab.SalesOrderDetail_Row'), OBJECT_ID('lab.SalesOrderDetail_Page'))
    AND index_id = 1; -- Clustered Index (onde residem os dados da tabela)


GO
-- 4. Medindo o impacto em leituras lógicas (I/O) no plano atual
-- NOTA EXPLICATIVA (POR QUE A COMPRESSÃO GEROU MENOS LEITURAS LÓGICAS?):
--   No SQL Server, a unidade básica de armazenamento em memória/disco é a página de 8 KB.
--   Uma "leitura lógica" (logical read) é a leitura de uma única página de 8 KB da RAM.
--   Quando compactamos os dados (ROW ou PAGE):
--     1. O tamanho físico de cada linha de dados é reduzido (consome menos bytes).
--     2. Mais linhas conseguem ser empacotadas dentro de uma mesma página de 8 KB.
--     3. Consequentemente, o número TOTAL de páginas necessárias para armazenar a tabela diminui.
--     4. Ao fazer um SCAN completo para ler toda a tabela, a engine precisa ler menos páginas 
--        totais de 8 KB da RAM, resultando em menor número de leituras lógicas e menor esforço de I/O.
SET STATISTICS IO ON;


GO
-- Teste A: Varredura na Tabela SEM Compressão (Mais páginas lidas)
SELECT 'NONE' AS Compressao,
    SUM(LineTotal) AS TotalVendas
FROM lab.SalesOrderDetail_None;


GO
-- Teste B: Varredura na Tabela com ROW Compression (Páginas intermediárias)
SELECT 'ROW' AS Compressao,
    SUM(LineTotal) AS TotalVendas
FROM lab.SalesOrderDetail_Row;


GO
-- Teste C: Varredura na Tabela com PAGE Compression (Mínimo de páginas lidas, menos I/O!)
SELECT 'PAGE' AS Compressao,
    SUM(LineTotal) AS TotalVendas
FROM lab.SalesOrderDetail_Page;


GO
SET STATISTICS IO OFF;


GO
-- 5. Aplicar compressão apenas no índice não clusterizado de cobertura da tabela principal do lab
ALTER INDEX NIX_SalesOrderDetailRowstore_ProductID_Covering
    ON lab.SalesOrderDetailRowstore REBUILD WITH(DATA_COMPRESSION = ROW);


GO
-- =================================================================================
-- PARTE 5: ÍNDICES COLUMNSTORE (CCI VS NCCI)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CLUSTERED COLUMNSTORE INDEX (CCI): Armazenamento físico colunar comprimido altamente otimizado
--     para consultas analíticas e de agregação. Substitui o armazenamento rowstore como estrutura
--     principal e é indicado para tabelas de fatos e grandes dimensões de DW.
--   - Desde SQL Server 2016, um CCI pode ter índices rowstore não clusterizados secundários. Isso permite
--     buscas seletivas e também a aplicação de uma constraint UNIQUE/PRIMARY KEY por um índice rowstore
--     apropriado; avalie o custo extra de manutenção antes de adotá-los.
--   - NON-CLUSTERED COLUMNSTORE INDEX (NCCI): Um índice colunar criado em cima de uma tabela Rowstore (B-tree).
--     Permite que a tabela continue operando transações OLTP de escrita rápida na B-Tree principal, enquanto
--     consultas analíticas paralelas utilizam a estrutura colunar (cenários híbridos HTAP).
--   - BATCH MODE: Modo de processamento em que a engine de consulta processa vetores (lotes) de aproximadamente
--     900 linhas juntas na memória cache da CPU de uma única vez, em vez de avaliar registro por registro (Row Mode).
--     Acelera drasticamente agregações e agrupamentos.
-- 1. Criar tabela analítica para testes de Clustered Columnstore Index (CCI)
SELECT *
INTO   lab.SalesOrderDetailCCI
FROM Sales.SalesOrderDetail;
GO

-- 2. Aplicar Clustered Columnstore (substitui o armazenamento rowstore)
CREATE CLUSTERED COLUMNSTORE INDEX CCI_SalesOrderDetailCCI
    ON lab.SalesOrderDetailCCI;
GO

-- Um índice rowstore secundário sobre um CCI é suportado. Ele atende a buscas seletivas;
-- não o confunda com um segundo índice clusterizado.
CREATE NONCLUSTERED INDEX NIX_SalesOrderDetailCCI_SalesOrderDetailID
    ON lab.SalesOrderDetailCCI (SalesOrderID, SalesOrderDetailID);
GO

-- 3. Comparação de Performance Analítica (Rowstore vs Columnstore)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- Consulta Rowstore (Varredura Clássica B-Tree)
SELECT ProductID,
    SUM(LineTotal) AS TotalVendas,
    AVG(UnitPrice) AS MediaPreco
FROM lab.SalesOrderDetailRowstore
GROUP BY ProductID;
GO

-- Consulta Columnstore (Varredura Colunar + BATCH MODE)
-- PLANO DE EXECUÇÃO: Como verificar a propriedade "Execution Mode":
-- Ela deverá mostrar "Batch" em vez de "Row", processando conjuntos de 900 linhas de uma vez só.
--   1. Execute a query habilitando o "Plano de Execução Atual" (Ctrl + M).
--   2. Acesse a aba "Execution plan" no painel de resultados inferior.
--   3. Passe o cursor do mouse (ou clique e aperte F4 para abrir propriedades na direita) 
--      sobre o primeiro ícone da consulta: "Clustered Index Scan (Columnstore)".
--   4. Veja o campo: "Actual Execution Mode" (ou "Estimated Execution Mode"). 
--      Deverá mostrar "Batch" (enquanto na query Rowstore acima mostra "Row").
SELECT ProductID,
    SUM(LineTotal) AS TotalVendas,
    AVG(UnitPrice) AS MediaPreco
FROM lab.SalesOrderDetailCCI
GROUP BY ProductID;
GO

-- 4. NCCI (Non-Clustered Columnstore Index)
-- Adiciona um índice colunar para consultas analíticas sem alterar a tabela rowstore física.
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_SalesOrderDetailRowstore
    ON lab.SalesOrderDetailRowstore(ProductID, LineTotal, UnitPrice);
GO

-- Agora a tabela Rowstore original também consegue usar modo lote (Batch Mode) para queries analíticas!
SELECT ProductID,
    SUM(LineTotal) AS TotalVendas,
    AVG(UnitPrice) AS MediaPreco
FROM lab.SalesOrderDetailRowstore
GROUP BY ProductID;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
-- =================================================================================
-- PARTE 6: COLUNAS SPARSE (ARMAZENAMENTO OTIMIZADO PARA NULOS)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - COLUNAS SPARSE (Esparsas): Colunas ordinárias com armazenamento otimizado para valores nulos.
--     Se o valor for NULL, a coluna ocupa exatamente zero bytes na linha. Se o valor for preenchido,
--     ela consome de 2 a 4 bytes a mais que seu tamanho físico original. Ideal para colunas com 90%+ de nulos.
--   - COLUMN SET: Um campo XML dinâmico (representação untyped) que expõe todas as colunas SPARSE 
--     de uma tabela de forma agrupada. Ele permite inserir, ler e atualizar colunas esparsas enviando XML.
--     Útil para superar o limite máximo do SQL Server de 1.024 colunas por tabela (permitindo até 30.000 colunas).
-- 1. Criar tabela utilizando SPARSE columns e COLUMN SET (XML dinâmico para N colunas esparsas)
CREATE TABLE lab.ProductAttributesSparse
(
    ProductID INT IDENTITY (1, 1) PRIMARY KEY,
    ProductName NVARCHAR (100) NOT NULL,
    -- Colunas Sparse que consomem zero bytes se nulas
    SpecialColor NVARCHAR (50) SPARSE NULL,
    CustomWeight DECIMAL (5, 2) SPARSE NULL,
    CustomNotes NVARCHAR (MAX) SPARSE NULL,
    -- Column Set expõe todas as colunas Sparse da tabela em uma coluna XML dinâmica
    AllSparseAttributes XML COLUMN_SET FOR ALL_SPARSE_COLUMNS
);


GO
-- 2. Inserindo dados
-- Perceba que podemos inserir nas colunas SPARSE normalmente
INSERT  INTO lab.ProductAttributesSparse
    (ProductName, SpecialColor, CustomWeight)
VALUES
    ('Mountain Bike Pro', 'Matte Black', 12.50);
-- E também podemos inserir linhas com muitos nulos (que economizarão espaço)

INSERT  INTO lab.ProductAttributesSparse
    (ProductName)
VALUES
    ('Road Bike Basic');
-- 3. Selecionando dados -- O SELECT * trará a coluna XML AllSparseAttributes no lugar das colunas SPARSE individuais

SELECT *
FROM lab.ProductAttributesSparse;
-- Mas você ainda pode buscar as colunas explicitamente:

SELECT ProductName,
    SpecialColor,
    CustomWeight
FROM lab.ProductAttributesSparse;
GO

-- 4. Como conferir o percentual de esparsidade (nulos) de qualquer coluna via Stored Procedure
-- NOTA DO EXAME (LIMITAÇÃO DE UDFs): Não é possível criar uma User-Defined Function (UDF) 
-- para executar SQL Dinâmico no SQL Server (pois funções têm efeitos colaterais proibidos).
-- Por isso, encapsulamos essa lógica de análise dinâmica em uma STORED PROCEDURE.
GO

CREATE OR ALTER PROCEDURE lab.CheckColumnSparsity
    @TableName NVARCHAR(256),
    @ColumnName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Validar se a tabela e coluna informadas existem no banco (evita erros e SQL Injection)
    IF OBJECT_ID(@TableName) IS NULL
    BEGIN
        RAISERROR('Erro: A tabela informada não existe ou o schema não foi especificado.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(@TableName) AND name = @ColumnName
    )
    BEGIN
        RAISERROR('Erro: A coluna informada não existe na tabela.', 16, 1);
        RETURN;
    END;

    -- 2. Montar e executar o SQL dinâmico de forma segura usando QUOTENAME
    DECLARE @DynamicSQL NVARCHAR(MAX);
    SET @DynamicSQL = N'
    SELECT 
        @Table AS Tabela,
        @Col AS Coluna,
        COUNT(*) AS TotalLinhas,
        SUM(CASE WHEN ' + QUOTENAME(@ColumnName) + ' IS NULL THEN 1 ELSE 0 END) AS TotalNulos,
        CAST(
            (SUM(CASE WHEN ' + QUOTENAME(@ColumnName) + ' IS NULL THEN 1.0 ELSE 0.0 END) / NULLIF(COUNT(*), 0)) * 100 
            AS DECIMAL(5,2)
        ) AS Percentual_Esparsidade_NULL
    FROM ' + QUOTENAME(OBJECT_SCHEMA_NAME(OBJECT_ID(@TableName)))
         + N'.' + QUOTENAME(OBJECT_NAME(OBJECT_ID(@TableName))) + N';';

    EXEC sp_executesql @DynamicSQL, 
                       N'@Table NVARCHAR(256), @Col NVARCHAR(128)', 
                       @Table = @TableName, 
                       @Col = @ColumnName;
END;
GO

-- Exemplo de Execução 1: Testando com a nossa coluna SPARSE
EXEC lab.CheckColumnSparsity 
    @TableName = 'lab.ProductAttributesSparse', 
    @ColumnName = 'SpecialColor';
GO

-- Exemplo de Execução 2: Testando com uma tabela original do AdventureWorks
EXEC lab.CheckColumnSparsity 
    @TableName = 'Sales.SalesOrderHeader', 
    @ColumnName = 'Comment';
GO


-- =================================================================================
-- MANUTENÇÃO E LIMPEZA (OPCIONAL)
-- =================================================================================
-- Execute quando terminar o laboratório para não consumir espaço desnecessário no seu banco.
/*
DROP PROCEDURE IF EXISTS lab.CheckColumnSparsity;
DROP TABLE IF EXISTS lab.ProductAttributesSparse;
DROP TABLE IF EXISTS lab.OrderDesignDemo;
DROP TABLE IF EXISTS lab.SalesOrderDetailCCI;
DROP TABLE IF EXISTS lab.SalesOrderDetailRowstore;
DROP TABLE IF EXISTS lab.SalesOrderDetailHeap;
DROP TABLE IF EXISTS lab.SalesOrderDetail_None;
DROP TABLE IF EXISTS lab.SalesOrderDetail_Row;
DROP TABLE IF EXISTS lab.SalesOrderDetail_Page;
-- DROP SCHEMA IF EXISTS lab;
*/


-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/01-database-objects/01-tables-indexes.md
-- =================================================================================================
-- =================================================================================================
-- REFERÊNCIAS OFICIAIS DO MICROSOFT LEARN
-- =================================================================================================
-- CREATE INDEX, colunas incluídas e índices filtrados:
-- https://learn.microsoft.com/pt-br/sql/t-sql/statements/create-index-transact-sql?view=sql-server-ver17
-- Compactação de dados (ROW e PAGE):
-- https://learn.microsoft.com/pt-br/sql/relational-databases/data-compression/data-compression?view=sql-server-ver17
-- Índices columnstore:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/indexes/columnstore-indexes-query-performance?view=sql-server-ver17
-- Colunas esparsas (sparse columns):
-- https://learn.microsoft.com/pt-br/sql/relational-databases/tables/use-sparse-columns?view=sql-server-ver17
