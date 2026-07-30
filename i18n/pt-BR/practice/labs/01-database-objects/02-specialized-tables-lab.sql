-- =================================================================================
-- DP-800 - LAB PRÁTICO: TABELAS ESPECIALIZADAS (SPECIALIZED TABLES)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/01-database-objects/02-specialized-tables.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a criação, uso e consulta dos 5 principais tipos de
-- tabelas especializadas cobradas no exame DP-800:
--   1. In-Memory OLTP (Memory-Optimized Tables)
--   2. Temporal Tables (System-Versioned)
--   3. Ledger Tables (Updatable e Append-Only)
--   4. Graph Tables (Nodes e Edges com o operador MATCH)
--   5. External Tables (Sintaxe e Cenários de Integração)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva caso rode o script mais de uma vez
DROP TABLE IF EXISTS lab.FinancialTransactionsLedger;
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'SalariesLedger')
    ALTER TABLE lab.SalariesLedger SET (SYSTEM_VERSIONING = OFF);
DROP TABLE IF EXISTS lab.SalariesLedger;
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'EmployeesTemporal')
    ALTER TABLE lab.EmployeesTemporal SET (SYSTEM_VERSIONING = OFF);
DROP TABLE IF EXISTS lab.EmployeesTemporal;
DROP TABLE IF EXISTS lab.EmployeesTemporalHistory;
IF EXISTS (SELECT 1 FROM sys.external_tables WHERE object_id = OBJECT_ID(N'lab.ExternalSalesOrders'))
    DROP EXTERNAL TABLE lab.ExternalSalesOrders;
IF EXISTS (SELECT 1 FROM sys.external_tables WHERE object_id = OBJECT_ID(N'lab.ExternalYellowTaxi2013'))
    DROP EXTERNAL TABLE lab.ExternalYellowTaxi2013;
IF EXISTS (SELECT 1 FROM sys.external_tables WHERE object_id = OBJECT_ID(N'lab.ExternalGreenTaxi2013'))
    DROP EXTERNAL TABLE lab.ExternalGreenTaxi2013;
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'AzureBlobStorageSales') DROP EXTERNAL DATA SOURCE AzureBlobStorageSales;
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'NYC_Taxi_Yellow') DROP EXTERNAL DATA SOURCE NYC_Taxi_Yellow;
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'NYC_Taxi_Green') DROP EXTERNAL DATA SOURCE NYC_Taxi_Green;
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'ParquetFileFormat') DROP EXTERNAL FILE FORMAT ParquetFileFormat;
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'NycTaxiParquet') DROP EXTERNAL FILE FORMAT NycTaxiParquet;
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'CSVFileFormat') DROP EXTERNAL FILE FORMAT CSVFileFormat;
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'MyStorageCredential') DROP DATABASE SCOPED CREDENTIAL [MyStorageCredential];
DROP TABLE IF EXISTS lab.SpecializedGraphUses;
DROP TABLE IF EXISTS lab.SpecializedGraphAsset;
DROP TABLE IF EXISTS lab.SpecializedGraphPerson;
DROP TABLE IF EXISTS lab.SessionCacheMemData;
DROP TABLE IF EXISTS lab.SessionCacheMemOnly;
DROP TYPE IF EXISTS lab.MyMemoryTableType;
GO


-- =================================================================================
-- PARTE 1: IN-MEMORY (MEMORY-OPTIMIZED) TABLES & DURABILITY
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - IN-MEMORY OLTP: Tecnologia do SQL Server que otimiza tabelas para processamento em memória RAM.
--     Utiliza algoritmos de concorrência Lock-Free e Latch-Free (sem bloqueios físicos de threads) e compilação
--     nativa de procedures para eliminar gargalos de transações OLTP de alto rendimento.
--   - BUCKET_COUNT: Parâmetro crítico na criação de índices HASH otimizados para memória. Deve ser
--     dimensionado entre 1 e 2 vezes a quantidade estimada de valores únicos na coluna indexada. 
--     Valores muito baixos geram colisões de hash na RAM (degradando buscas), e valores muito altos desperdiçam memória.
--   - DURABILITY = SCHEMA_ONLY: A tabela mantém sua estrutura salva no disco, mas seus dados residem apenas na RAM.
--     Se o serviço do SQL Server for reiniciado, a tabela é recriada vazia. Perfeito para caches e dados transientes.
--   - DURABILITY = SCHEMA_AND_DATA: Garante persistência total (esquema e dados). As transações gravam no log
--     de transações em disco de forma assíncrona ou síncrona, assegurando que os dados sobrevivam a reinícios do banco.

-- 1. Verificar e adicionar Filegroup Otimizado para Memória se não existir
IF NOT EXISTS (SELECT * FROM sys.filegroups WHERE type = 'FX')
BEGIN
    -- Adiciona o Filegroup
    ALTER DATABASE AdventureWorks2025 
    ADD FILEGROUP FG_MemOptimized CONTAINS MEMORY_OPTIMIZED_DATA;
    
    -- Adiciona um container/pasta física ao filegroup
    -- NOTA: O diretório não pode existir previamente; o SQL Server criará a pasta.
    DECLARE @filepath NVARCHAR(260);
    SELECT TOP 1 @filepath = SUBSTRING(physical_name, 1, CHARINDEX('AdventureWorks', physical_name) - 1)
    FROM sys.master_files 
    WHERE database_id = DB_ID('AdventureWorks2025');

    SET @filepath = @filepath + 'AW_MemOpt_Container';

    DECLARE @sql NVARCHAR(MAX) = 'ALTER DATABASE AdventureWorks2025 ADD FILE (NAME = ''AW_MemOpt_File'', FILENAME = ''' + @filepath + ''') TO FILEGROUP FG_MemOptimized;';
    EXEC sp_executesql @sql;
END;
GO

-- 2. Criar tabela com DURABILITY = SCHEMA_AND_DATA (Persistente, padrão)
-- Armazena o esquema e os dados. Sobrevive a reinicializações do servidor.
CREATE TABLE lab.SessionCacheMemData (
    SessionID uniqueidentifier NOT NULL,
    UserID INT NOT NULL,
    CachedData NVARCHAR(2000) NULL,
    CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    -- Índices não podem ser B-Tree padrão, devem ser NONCLUSTERED ou HASH.
    CONSTRAINT PK_SessionCacheMemData PRIMARY KEY NONCLUSTERED HASH (SessionID) 
        WITH (BUCKET_COUNT = 65536) -- Bucket count deve ser aprox. o dobro do número planejado de chaves únicas
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);
GO

-- 3. Criar tabela com DURABILITY = SCHEMA_ONLY (Transiente/Volátil)
-- Apenas a estrutura (esquema) é salva em disco. Em caso de reinício,
-- a tabela estará vazia (ótima para caches e estados temporários).
CREATE TABLE lab.SessionCacheMemOnly (
    SessionID uniqueidentifier NOT NULL,
    UserID INT NOT NULL,
    CachedData NVARCHAR(2000) NULL,
    CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_SessionCacheMemOnly PRIMARY KEY NONCLUSTERED (SessionID) -- NONCLUSTERED padrão (Bucketless/Index Seek em intervalo)
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_ONLY);
GO

-- 4. LABORATORIO REAL: Testando a Diferença de Durabilidade (None vs SCHEMA_ONLY vs SCHEMA_AND_DATA)
-- A. Inserindo dados de teste em ambas as tabelas
INSERT INTO lab.SessionCacheMemData (SessionID, UserID, CachedData) 
VALUES (NEWID(), 101, 'Dados persistentes na RAM e persistidos em Disco');

INSERT INTO lab.SessionCacheMemOnly (SessionID, UserID, CachedData) 
VALUES (NEWID(), 102, 'Dados voláteis apenas na RAM (perda ao reiniciar)');
GO

-- Verificando os dados ativos antes da reinicialização
SELECT 'SessionCacheMemData' AS Tabela, SessionID, UserID, CachedData FROM lab.SessionCacheMemData
UNION ALL
SELECT 'SessionCacheMemOnly', SessionID, UserID, CachedData FROM lab.SessionCacheMemOnly;
GO

-- B. Validação da durabilidade.
-- [PONTO DE ATENÇÃO DP-800] Não coloque o banco OFFLINE neste laboratório: isso derruba
-- conexões e pode afetar outros usuários. Para observar a perda real dos dados SCHEMA_ONLY,
-- execute o bloco abaixo SOMENTE em uma instância dedicada, após registrar os resultados acima.
/*
ALTER DATABASE AdventureWorks2025 SET OFFLINE WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE AdventureWorks2025 SET ONLINE;
GO
USE AdventureWorks2025;
GO
*/


-- C. Verificando o resultado pós-reinício:
-- A tabela SCHEMA_AND_DATA terá seus dados preservados.
-- A tabela SCHEMA_ONLY estará COMPLETAMENTE VAZIA (mas a sua estrutura/esquema continua existindo).
SELECT 'SessionCacheMemData (SCHEMA_AND_DATA)' AS Tabela, COUNT(*) AS QtdRegistros FROM lab.SessionCacheMemData
UNION ALL
SELECT 'SessionCacheMemOnly (SCHEMA_ONLY)', COUNT(*) AS QtdRegistros FROM lab.SessionCacheMemOnly;
GO

-- 5. Variáveis de Tabela Otimizadas para Memória
-- Evitam overhead de escrita no TempDB clássico.
-- Primeiro, criamos o tipo de tabela otimizada para memória:
CREATE TYPE lab.MyMemoryTableType AS TABLE (
    ItemID INT NOT NULL INDEX IX_ItemID NONCLUSTERED,
    ItemName NVARCHAR(100) NOT NULL
) WITH (MEMORY_OPTIMIZED = ON);
GO

-- Exemplo de uso da variável de tabela otimizada para memória:
DECLARE @myTableVar lab.MyMemoryTableType;
INSERT INTO @myTableVar (ItemID, ItemName) VALUES (1, 'Teclado'), (2, 'Mouse');
SELECT * FROM @myTableVar;
GO


-- =================================================================================
-- PARTE 2: TEMPORAL TABLES (SYSTEM-VERSIONED)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - TABELAS TEMPORAIS (System-Versioned): Compostas por duas tabelas físicas trabalhando juntas:
--     1. TABELA PRINCIPAL (ex: lab.EmployeesTemporal): Mantém apenas o estado ATUAL e ativo dos dados.
--        Qualquer registro ativo possui a data final SysEndTime setada no valor máximo '9999-12-31 23:59:59.9999999'.
--     2. TABELA DE HISTÓRICO (ex: lab.EmployeesTemporalHistory): Guarda todas as versões passadas de linhas
--        que sofreram UPDATE ou DELETE. O SysEndTime marca o timestamp exato de expiração da versão anterior.
--        Nota: A tabela de histórico é protegida e read-only (bloqueia comandos de escrita direta pela aplicação).
--   - COLUNAS DE PERÍODO (SysStartTime / SysEndTime): Campos obrigatórios do tipo DATETIME2 
--     marcadas com a instrução `GENERATED ALWAYS AS ROW START/END`. Elas registram a vigência temporal de cada registro.
--     IMPORTANTE: O SQL Server grava estas datas SEMPRE em UTC (Universal Time Coordinated), ignorando o fuso horário local.
--   - OPERAÇÃO DE SCHEMA (DDL): Para alterar o layout de colunas da tabela principal, você DEVE desativar
--     o versionamento temporariamente (`SET (SYSTEM_VERSIONING = OFF)`), aplicar o `ALTER TABLE` na principal e na de 
--     histórico, e em seguida reativar o versionamento para manter o alinhamento.
--   - TIME TRAVEL (FOR SYSTEM_TIME AS OF): Recurso do otimizador que permite consultar o estado exato dos dados
--     em qualquer instante do passado. O SQL Server une a tabela ativa com a de histórico (UNION ALL) de forma automática.
--   - AUDITORIA: Temporal registra versões e horários UTC, mas não identifica automaticamente quem
--     alterou a linha. Para isso, grave o usuário da aplicação ou use SQL Server Audit/Azure SQL Auditing.

-- 1. Criar Tabela Temporal com tabela de histórico nomeada explicitamente (Melhor Prática!)
CREATE TABLE lab.EmployeesTemporal (
    EmployeeID INT NOT NULL PRIMARY KEY CLUSTERED,
    Name NVARCHAR(100) NOT NULL,
    Salary DECIMAL(18,2) NOT NULL,
    Department NVARCHAR(50) NOT NULL,
    -- Colunas de vigência (obrigatórias e gerenciadas pelo sistema)
    SysStartTime DATETIME2(7) GENERATED ALWAYS AS ROW START NOT NULL,
    SysEndTime DATETIME2(7) GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = lab.EmployeesTemporalHistory));
GO

-- 2. Inserir alguns registros iniciais
INSERT INTO lab.EmployeesTemporal (EmployeeID, Name, Salary, Department)
VALUES 
(1, 'Carlos Silva', 5000.00, 'TI'),
(2, 'Ana Costa', 6200.00, 'Financeiro');
GO

-- Vamos simular a passagem de tempo para ver o versionamento histórico.
-- Como os registros precisam ter timestamps diferentes, faremos uma pausa (WAITFOR).
WAITFOR DELAY '00:00:02';

-- 3. Atualizar o salário do funcionário 1 (Gera registro histórico)
UPDATE lab.EmployeesTemporal
SET Salary = 5500.00
WHERE EmployeeID = 1;
GO

WAITFOR DELAY '00:00:02';

-- 4. Deletar a funcionária Ana Costa (Move o registro vigente por completo para o histórico)
DELETE FROM lab.EmployeesTemporal
WHERE EmployeeID = 2;
GO

-- 5. CONSULTAS DE VIAGEM NO TEMPO (TIME TRAVEL)
-- A. Estado atual da tabela (apenas o que está ativo hoje)
SELECT * FROM lab.EmployeesTemporal;

-- B. Ver todas as versões da história (tabela atual + histórico combinado)
SELECT EmployeeID, Name, Salary, SysStartTime, SysEndTime 
FROM lab.EmployeesTemporal
FOR SYSTEM_TIME ALL;

-- C. Consulta Point-in-Time (Como a tabela estava exatamente há alguns segundos?)
-- NOTA CRÍTICA DO EXAME: As tabelas temporais (System-Versioned) do SQL Server SEMPRE armazenam
-- as colunas de período (SysStartTime/SysEndTime) em UTC, independentemente do fuso horário do servidor.
-- Por isso, para consultas point-in-time comparativas, devemos usar obrigatoriamente SYSUTCDATETIME() 
-- em vez de SYSDATETIME(), senão a consulta buscará um horário com diferença de fuso (ex: UTC-3).
DECLARE @Timestamp DATETIME2 = DATEADD(second, -3, SYSUTCDATETIME());

SELECT EmployeeID, Name, Salary 
FROM lab.EmployeesTemporal
FOR SYSTEM_TIME AS OF @Timestamp;
GO


-- =================================================================================
-- PARTE 3: LEDGER TABLES (PROVA CRIPTOGRÁFICA DE INTEGRIDADE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - LEDGER: Recurso de segurança que fornece rastreamento e prova criptográfica de integridade dos dados (anti-adulteração).
--     Cada transação gera um hash SHA-256 e armazena os registros em blocos encadeados (semelhante a um blockchain).
--   - UPDATABLE LEDGER: Permite atualizações e exclusões normais. Contudo, as versões antigas são arquivadas
--     automaticamente em uma tabela histórica protegida do Ledger, e a visualização das alterações fica disponível via
--     uma View especial do Ledger (`_Ledger`).
--   - APPEND_ONLY LEDGER: Tabelas estritas de inserção apenas. Qualquer instrução `UPDATE` ou `DELETE` é fisicamente
--     bloqueada pelo motor do SQL Server de forma nativa. Ideal para logs de auditoria e registros financeiros.
--   - DIGESTS E VERIFICAÇÃO (`sp_verify_database_ledger`): Para validar que ninguém (inclusive sysadmins com acesso de root)
--     alterou os hashes diretamente nos arquivos de dados, o SQL Server gera "digests" (blocos de hash assinados) que são
--     guardados em locais externos seguros (ex: Azure Storage Imutável). A verificação recalcula a cadeia de hashes e compara com os digests.
--
-- NOTA CRÍTICA DO EXAME & TRADE-OFF DE ARQUITETURA (PREPARAÇÃO DO BANCO):
-- A execução de auditoria do Ledger (sp_verify_database_ledger) exige obrigatoriamente ALLOW_SNAPSHOT_ISOLATION = ON.
-- IMPLICAÇÕES E TRADE-OFFS DO SNAPSHOT ISOLATION NO BANCO DE DADOS:
--   - DESVANTAGENS (OVERHEAD DE TEMPDB E DISCO):
--     1. Impacto no Banco Inteiro: Assim que ativado, QUALQUER comando UPDATE ou DELETE executado em QUALQUER
--        tabela do banco de dados passa a gravar a versão anterior da linha na área de Version Store do TempDB.
--        Isso gera aumento significativo de I/O, espaço em disco e pressão de CPU no TempDB.
--     2. Overhead de 14 Bytes por Linha: Cada linha modificada no banco ganha um ponteiro de 14 bytes no cabeçalho
--        para mapear sua versão no TempDB. Em tabelas muito cheias/densas, isso pode causar Page Splits físicos.
--     3. Processo de Coleta de Lixo: O SQL Server consome CPU rodando threads em segundo plano para limpar versões antigas no TempDB.
--   - VANTAGENS (CONCORRÊNCIA E AUDITORIA):
--     1. Leituras Não-Bloqueantes: Consultas SELECT leem versões do TempDB sem aplicar bloqueios compartilhados (Shared Locks),
--        eliminando completamente os travamentos entre leitores e escritores.
--     2. Verificação do Ledger: Habilita a execução da procedure sp_verify_database_ledger para auditar hashes sem travar o banco.



-- 1. Updatable Ledger Table
-- Permite comandos DML padrão, mas gera hashes e rastreia o histórico de auditoria criptograficamente.
CREATE TABLE lab.SalariesLedger (
    EmployeeID INT NOT NULL PRIMARY KEY CLUSTERED,
    Salary DECIMAL(18,2) NOT NULL
) WITH (SYSTEM_VERSIONING = ON, LEDGER = ON);
GO

-- 2. Append-Only Ledger Table
-- Excelente para logs/auditoria. Bloqueia tentativas de UPDATE e DELETE de forma nativa.
CREATE TABLE lab.FinancialTransactionsLedger (
    TransactionID INT IDENTITY PRIMARY KEY,
    AccountID INT NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    -- Nota: Usar SYSUTCDATETIME() é a melhor prática para logs/ledger pois alinha com a coluna commit_time de sys.database_ledger_transactions (UTC).
    TransactionDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
) WITH (LEDGER = ON (APPEND_ONLY = ON));
GO

-- Teste 1: Executando operações normais na Updatable Ledger Table
INSERT INTO lab.SalariesLedger (EmployeeID, Salary) VALUES (1, 5000.00), (2, 7500.00);
GO
-- Atualizar salário (Gera registro histórico de auditoria)
UPDATE lab.SalariesLedger SET Salary = 5500.00 WHERE EmployeeID = 1;
GO
-- Deletar funcionário (Gera registro histórico de exclusão)
DELETE FROM lab.SalariesLedger WHERE EmployeeID = 2;
GO

-- Visualizar a tabela de histórico automática do ledger e a view do ledger
-- Nota: A view SalariesLedger_Ledger mostra a ordem sequencial de todas as transações, IDs e operações (INSERT/DELETE).
SELECT l.EmployeeID,
       l.Salary,
       l.ledger_transaction_id,
       l.ledger_sequence_number,
       l.ledger_operation_type,
       l.ledger_operation_type_desc
FROM   lab.SalariesLedger_Ledger AS l;

-- Teste 2: Tentar atualizar ou deletar na tabela Append-Only
INSERT  INTO lab.FinancialTransactionsLedger (AccountID, Amount)
VALUES                                      (10, 250.00);


GO
-- 1. Confirmar que a inserção ocorreu com sucesso na tabela Append-Only
SELECT 'Tabela Append-Only (Inserção OK)' AS Status,
       TransactionID,
       AccountID,
       Amount,
       TransactionDate
FROM   lab.FinancialTransactionsLedger;


GO
-- 2. Tentar UPDATE em tabela Append-Only (SQL Server aborta a instrução com o erro Msg 37359)
-- Usamos sp_executesql para isolar a compilação e permitir que o CATCH capture a mensagem.
BEGIN TRY
    EXEC sp_executesql N'UPDATE lab.FinancialTransactionsLedger SET Amount = 1000.00 WHERE TransactionID = 1;';
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO APPEND-ONLY UPDATE: ' + ERROR_MESSAGE();
END CATCH
GO

-- 3. Tentar DELETE em tabela Append-Only (SQL Server aborta a instrução com o erro Msg 37359)
BEGIN TRY
    EXEC sp_executesql N'DELETE FROM lab.FinancialTransactionsLedger WHERE TransactionID = 1;';
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO APPEND-ONLY DELETE: ' + ERROR_MESSAGE();
END CATCH
GO
-- 4. Confirmar que o registro inserido PERMANECE intacto e inalterado na tabela
SELECT 'Registro Mantido Intacto' AS Status,
       TransactionID,
       AccountID,
       Amount,
       TransactionDate
FROM   lab.FinancialTransactionsLedger;


-- 3. Verificando a Integridade da Ledger Table
-- COMO CONFIGURAR E OBTER O LOCAL DOS DIGESTS (EXPORTAÇÃO DE CHAVES):
--   A. GERAÇÃO MANUAL: A proc 'EXEC sys.sp_generate_database_ledger_digest;' gera um documento JSON 
--      contendo o hash do bloco atual. Esse arquivo JSON é salvo em um local externo imutável (ex: WORM storage).
--   B. CONFIGURAÇÃO AUTOMÁTICA (AZURE): No Azure SQL ou via Azure CLI, configura-se "Automatic Digest Storage" 
--      apontando a URL do container imutável do Azure Blob Storage ou Azure Confidential Ledger.
--   C. PASSAGEM DE PARÂMETRO NA VERIFICAÇÃO: Para auditar, o conteúdo JSON do digest salvo é lido e passado no
--      parâmetro @digests (ou a URL no parâmetro @digest_locations) da procedure sp_verify_database_ledger.

-- Habilitar a configuração necessária no banco 
ALTER DATABASE AdventureWorks2025 SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
BEGIN TRY
    -- Exemplo: Gerar o digest atual sob demanda (retorna o JSON da cadeia de hashes)
    EXEC sys.sp_generate_database_ledger_digest;

    -- Em produção, o conteúdo do arquivo JSON retornado/exportado é passado no parâmetro @digests:
    -- DECLARE @digests NVARCHAR(MAX) = N'[]';
    DECLARE @digests NVARCHAR(MAX) = N'[{"path":"https://myaccount.blob.core.windows.net/sqldledgermfd/mydb/2026-07-21/...json", "last_digest_block_id": 1, "is_current": true}]';
    EXEC sys.sp_verify_database_ledger @digests = @digests;
    
END TRY
BEGIN CATCH
    PRINT 'NOTA SOBRE VERIFICAÇÃO DE LEDGER: ' + ERROR_MESSAGE();
    -- Em ambiente local sem exportação configurada, a proc avisa a necessidade do JSON de digests.
END CATCH;
GO

-- 4. Restaurar a configuração do banco para DESATIVAR o Snapshot Isolation e eliminar o overhead no TempDB
ALTER DATABASE AdventureWorks2025 SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO


-- =================================================================================
/*
-- CONTEÚDO MIGRADO: os cenários avançados de Graph, incluindo fraude,
-- SHORTEST_PATH e o renderizador Mermaid, agora pertencem ao lab avançado:
-- ../../../practice/labs/03-advanced-tsql/04-graph-queries-lab.sql
--
-- Esta implementação anterior permanece apenas como referência histórica e não
-- é executada, evitando colisões com os objetos do lab avançado.
-- PARTE 4 LEGADA: GRAPH TABLES (MODELAGEM E ANÁLISE DE REDES E DETECÇÃO DE FRAUDES)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE DO EXAME DP-800:
--   - BANCO DE DADOS EM GRAFO: Permite modelar relacionamentos N:M complexos de forma nativa e altamente performática.
--   - TABELAS NODE (Nós): Entidades do grafo (ex: Pessoas, Cartões de Crédito, IPs). Contêm a coluna implícita `$node_id`.
--   - TABELAS EDGE (Arestas): Conexões direcionadas entre nós (ex: Conhece, UsaIP, PossuiCartão). Contêm `$from_id` e `$to_id`.
--   - CONNECTION CONSTRAINTS: Restrições de integridade que definem quais tipos de Nó uma Aresta pode conectar.
--   - CLÁUSULA MATCH(): Permite expressar padrões de conexão visual em ASCII na cláusula WHERE. Ex: `MATCH(P1-(A)->P2)`.
--   - SHORTEST_PATH: Recurso avançado para encontrar o menor caminho/cadeia de conexões de N saltos entre dois nós.

-- 0. Limpeza preventiva específica dos objetos de Grafo
-- REGRA DE ORDEM: Tabelas EDGE (Arestas) devem ser apagadas ANTES das tabelas NODE (Nós)
-- para evitar erros de integridade decorrentes de CONNECTION CONSTRAINTS.
DROP TABLE IF EXISTS lab.OwnsCard;
DROP TABLE IF EXISTS lab.UsedIP;
DROP TABLE IF EXISTS lab.Knows;
DROP TABLE IF EXISTS lab.Supplies;
DROP TABLE IF EXISTS lab.Stores;
DROP TABLE IF EXISTS lab.CreditCard;
DROP TABLE IF EXISTS lab.IPAddress;
DROP TABLE IF EXISTS lab.Person;
DROP TABLE IF EXISTS lab.Supplier;
DROP TABLE IF EXISTS lab.Warehouse;
DROP TABLE IF EXISTS lab.Product;
GO

-- 1. Criar as Tabelas de Nós (NODES)
-- GRUPO 1: Rede Financeira e de Segurança (Person, CreditCard, IPAddress)
CREATE TABLE lab.Person (
    PersonID INT IDENTITY PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) NOT NULL
) AS NODE;

CREATE TABLE lab.CreditCard (
    CardID INT IDENTITY PRIMARY KEY,
    CardNumber NVARCHAR(20) NOT NULL,
    Issuer NVARCHAR(50) NOT NULL
) AS NODE;

CREATE TABLE lab.IPAddress (
    IPID INT IDENTITY PRIMARY KEY,
    IPAddress NVARCHAR(45) NOT NULL
) AS NODE;

-- GRUPO 2: Rede Logística e Cadeia de Suprimentos (Supply Chain - 100% Independente do Grupo 1)
CREATE TABLE lab.Supplier (
    SupplierID INT IDENTITY PRIMARY KEY,
    SupplierName NVARCHAR(100) NOT NULL,
    City NVARCHAR(50) NOT NULL
) AS NODE;

CREATE TABLE lab.Warehouse (
    WarehouseID INT IDENTITY PRIMARY KEY,
    WarehouseName NVARCHAR(100) NOT NULL,
    Location NVARCHAR(50) NOT NULL
) AS NODE;

CREATE TABLE lab.Product (
    ProductID INT IDENTITY PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Category NVARCHAR(50) NOT NULL
) AS NODE;
GO

-- 2. Criar as Tabelas de Arestas (EDGES) com CONNECTION CONSTRAINTS (Restrições de Grafo)
-- GRUPO 1: Arestas da Rede Financeira
CREATE TABLE lab.Knows AS EDGE;

CREATE TABLE lab.OwnsCard (
    CONSTRAINT EC_OwnsCard CONNECTION (lab.Person TO lab.CreditCard)
) AS EDGE;

CREATE TABLE lab.UsedIP (
    CONSTRAINT EC_UsedIP CONNECTION (lab.Person TO lab.IPAddress)
) AS EDGE;

-- GRUPO 2: Arestas da Rede Logística (Supply Chain)
CREATE TABLE lab.Supplies (
    CONSTRAINT EC_Supplies CONNECTION (lab.Supplier TO lab.Warehouse)
) AS EDGE;

CREATE TABLE lab.Stores (
    CONSTRAINT EC_Stores CONNECTION (lab.Warehouse TO lab.Product)
) AS EDGE;
GO

-- 3. Inserir Dados nos Nós
-- GRUPO 1: Nós da Rede Financeira
-- Nota: 'Eve' é inserida sem NENHUMA aresta para demonstrar a detecção de Nó Isolado (Ilha Desconectada) do Grupo 1
INSERT INTO lab.Person (Name, Email) 
VALUES ('Alice', 'alice@empresa.com'),
       ('Bob', 'bob@empresa.com'),
       ('Charlie', 'charlie@empresa.com'),
       ('David', 'david@empresa.com'),
       ('Eve', 'eve@empresa.com');

INSERT INTO lab.CreditCard (CardNumber, Issuer)
VALUES ('4111-XXXX-XXXX-1111', 'Visa'),
       ('5500-YYYY-YYYY-2222', 'MasterCard');

INSERT INTO lab.IPAddress (IPAddress)
VALUES ('192.168.1.100'),
       ('10.0.0.5');

-- GRUPO 2: Nós da Rede Logística (Supply Chain)
-- Nota: 'FornecedorInativo Corp' e 'ItemObsoleto SemEstoque' são inseridos sem arestas para testar Nós Isolados no Grupo 2!
INSERT INTO lab.Supplier (SupplierName, City)
VALUES ('TechComponents SA', 'São Paulo'),
       ('LogisticaGlobal LTDA', 'Curitiba'),
       ('FornecedorInativo Corp', 'Rio de Janeiro');

INSERT INTO lab.Warehouse (WarehouseName, Location)
VALUES ('Centro de Distribuição Principal', 'Campinas'),
       ('Depósito Regional Sul', 'Joinville');

INSERT INTO lab.Product (ProductName, Category)
VALUES ('Servidor Rack 2U', 'Hardware'),
       ('Switch L3 48p', 'Redes'),
       ('ItemObsoleto SemEstoque', 'Descontinuado');
GO

-- 4. Inserir Relacionamentos nas Arestas ($from_id -> $to_id)
-- GRUPO 1: Relacionamentos da Rede Financeira
-- A. Amizades entre Pessoas (Knows)
INSERT INTO lab.Knows ($from_id, $to_id)
VALUES 
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Alice'), (SELECT $node_id FROM lab.Person WHERE Name = 'Bob')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Bob'), (SELECT $node_id FROM lab.Person WHERE Name = 'Charlie')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Charlie'), (SELECT $node_id FROM lab.Person WHERE Name = 'David'));

-- B. Cartões de Crédito pertencentes a Pessoas (OwnsCard)
-- Nota de Análise de Fraude: Alice e Bob possuem O MESMO cartão de crédito!
INSERT INTO lab.OwnsCard ($from_id, $to_id)
VALUES 
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Alice'), (SELECT $node_id FROM lab.CreditCard WHERE CardNumber = '4111-XXXX-XXXX-1111')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Bob'), (SELECT $node_id FROM lab.CreditCard WHERE CardNumber = '4111-XXXX-XXXX-1111')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Charlie'), (SELECT $node_id FROM lab.CreditCard WHERE CardNumber = '5500-YYYY-YYYY-2222'));

-- C. IPs de Acesso utilizados pelas Pessoas (UsedIP)
-- Nota de Análise de Fraude: Bob e Charlie acessaram usando O MESMO endereço IP!
INSERT INTO lab.UsedIP ($from_id, $to_id)
VALUES 
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Alice'), (SELECT $node_id FROM lab.IPAddress WHERE IPAddress = '10.0.0.5')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Bob'), (SELECT $node_id FROM lab.IPAddress WHERE IPAddress = '192.168.1.100')),
    ((SELECT $node_id FROM lab.Person WHERE Name = 'Charlie'), (SELECT $node_id FROM lab.IPAddress WHERE IPAddress = '192.168.1.100'));

-- GRUPO 2: Relacionamentos da Rede Logística (Supplies & Stores)
INSERT INTO lab.Supplies ($from_id, $to_id)
VALUES 
    ((SELECT $node_id FROM lab.Supplier WHERE SupplierName = 'TechComponents SA'), (SELECT $node_id FROM lab.Warehouse WHERE WarehouseName = 'Centro de Distribuição Principal')),
    ((SELECT $node_id FROM lab.Supplier WHERE SupplierName = 'LogisticaGlobal LTDA'), (SELECT $node_id FROM lab.Warehouse WHERE WarehouseName = 'Depósito Regional Sul'));

INSERT INTO lab.Stores ($from_id, $to_id)
VALUES 
    ((SELECT $node_id FROM lab.Warehouse WHERE WarehouseName = 'Centro de Distribuição Principal'), (SELECT $node_id FROM lab.Product WHERE ProductName = 'Servidor Rack 2U')),
    ((SELECT $node_id FROM lab.Warehouse WHERE WarehouseName = 'Depósito Regional Sul'), (SELECT $node_id FROM lab.Product WHERE ProductName = 'Switch L3 48p'));
GO

-- =================================================================================
-- CONSULTAS DE ANÁLISE DE GRAFO (EXAME DP-800)
-- =================================================================================
-- COMO O SQL SERVER EXECUTA O MATCH() INTERNAMENTE:
-- Embora a cláusula FROM liste as tabelas separadas por vírgula (sintaxe parecida com Produto Cartesiano),
-- o compilador do SQL Server intercepta o MATCH() e converte a busca em JOINs altamente otimizados 
-- entre as colunas ocultas de sistema:
--   - P1.$node_id = O1.$from_id (Nó de Origem se conecta à Aresta)
--   - O1.$to_id = C.$node_id (Aresta se conecta ao Nó de Destino)
--   - C.$node_id = O2.$to_id (Trajeto de Volta: O mesmo Nó conecta a outra Aresta de entrada)
--   - O2.$from_id = P2.$node_id (Aresta conecta à segunda Pessoa)

-- 0. MAPA MESTRE: Visualizar TODA a Árvore de Relacionamentos do Grafo (Visão Geral da Rede)
SELECT 
    'Pessoa' AS TipoOrigem,
    P.Name AS EntidadeOrigem,
    'Possui Cartão' AS Relacionamento,
    'Cartão de Crédito' AS TipoDestino,
    C.CardNumber AS EntidadeDestino,
    '[Pessoa: ' + P.Name + '] --- (Possui Cartão) ---> [Cartão: ' + C.CardNumber + ']' AS ArvoreVisual
FROM lab.Person P, lab.OwnsCard O, lab.CreditCard C
WHERE MATCH(P-(O)->C)

UNION ALL

SELECT 
    'Pessoa' AS TipoOrigem,
    P.Name AS EntidadeOrigem,
    'Acessou pelo IP' AS Relacionamento,
    'Endereço IP' AS TipoDestino,
    IP.IPAddress AS EntidadeDestino,
    '[Pessoa: ' + P.Name + '] --- (Acessou IP) ---> [IP: ' + IP.IPAddress + ']' AS ArvoreVisual
FROM lab.Person P, lab.UsedIP U, lab.IPAddress IP
WHERE MATCH(P-(U)->IP)

UNION ALL

SELECT 
    'Pessoa' AS TipoOrigem,
    P1.Name AS EntidadeOrigem,
    'Amigo de / Conhece' AS Relacionamento,
    'Pessoa' AS TipoDestino,
    P2.Name AS EntidadeDestino,
    '[Pessoa: ' + P1.Name + '] --- (Conhece) ---> [Pessoa: ' + P2.Name + ']' AS ArvoreVisual
FROM lab.Person P1, lab.Knows K, lab.Person P2
WHERE MATCH(P1-(K)->P2)

ORDER BY EntidadeOrigem, Relacionamento;
GO

-- 1. DETECÇÃO DE FRAUDE 1: Encontrar Clientes Distintos Compartilhando o Mesmo Cartão de Crédito
-- ESQUEMA DE IDA E VOLTA DO MATCH():
--   [Pessoa 1: Alice] ----(O1: OwnsCard)----> [Cartão: Visa 4111] <----(O2: OwnsCard)---- [Pessoa 2: Bob]
--    (Nó Origem Ida)                          (Nó de Encontro)                            (Nó Origem Volta)
SELECT 
    P1.Name + ' ===[ CARTÃO COMPARTILHADO: ' + C.CardNumber + ' ]===> ' + P2.Name AS AlertaFraudeVisual,
    P1.Name AS Cliente1,
    P2.Name AS Cliente2,
    C.CardNumber AS CartaoCompartilhado
FROM lab.Person P1, lab.OwnsCard O1, lab.CreditCard C, lab.OwnsCard O2, lab.Person P2
WHERE MATCH(P1-(O1)->C<-(O2)-P2)
  AND P1.PersonID < P2.PersonID; -- Evita duplicados e espelhados (Alice+Bob vs Bob+Alice)
GO

-- 2. DETECÇÃO DE FRAUDE 2: Encontrar Clientes Compartilhando o Mesmo IP de Acesso
-- ESQUEMA DE IDA E VOLTA DO MATCH():
--   [Pessoa 1: Bob] ----(U1: UsedIP)----> [IP: 192.168.1.100] <----(U2: UsedIP)---- [Pessoa 2: Charlie]
SELECT 
    P1.Name + ' ===[ IP COMPARTILHADO: ' + IP.IPAddress + ' ]===> ' + P2.Name AS AlertaSuspeitoIP,
    P1.Name AS Cliente1,
    P2.Name AS Cliente2,
    IP.IPAddress AS IPCompartilhado
FROM lab.Person P1, lab.UsedIP U1, lab.IPAddress IP, lab.UsedIP U2, lab.Person P2
WHERE MATCH(P1-(U1)->IP<-(U2)-P2)
  AND P1.PersonID < P2.PersonID;
GO

-- 3. DETECÇÃO DE FRAUDE EM ESTRELA (CADEIA DE FRAUDE MULTINÍVEL DE 4 SALTOS):
-- ESQUEMA COMPLETO:
--   (Alice) --[Possui]--> (Card) <--[Possui]-- (Bob) --[UsaIP]--> (IP) <--[UsaIP]-- (Charlie)
--   Salto 1               Salto 2             Ponto Médio   Salto 3          Salto 4
SELECT 
    P1.Name AS Origem,
    Card.CardNumber AS CartaoEmComum,
    P2.Name AS Intermediario,
    IP.IPAddress AS IPEmComum,
    P3.Name AS DestinoSuspeito
FROM lab.Person P1, lab.OwnsCard O1, lab.CreditCard Card, lab.OwnsCard O2, lab.Person P2,
     lab.UsedIP U1, lab.IPAddress IP, lab.UsedIP U2, lab.Person P3
WHERE MATCH(P1-(O1)->Card<-(O2)-P2-(U1)->IP<-(U2)-P3)
  AND P1.PersonID <> P3.PersonID;
GO

-- 4. TRAVESSIA RECURSIVA COM SHORTEST_PATH (ENCONTRAR A MENOR CADEIA DE CONEXÃO DE N SALTOS)
-- Requisito DP-800: Encontrar qual é o menor caminho de amizade entre Alice e David (N saltos)
-- ESQUEMA DE TRAVESSIA RECURSIVA: (Alice) ----[Knows]----> (Bob) ----[Knows]----> (Charlie) ----[Knows]----> (David)
SELECT 
    P1.Name AS PessoaInicial,
    STRING_AGG(P2.Name, ' -> ') WITHIN GROUP (GRAPH PATH) AS CadeiaDeConexao,
    LAST_VALUE(P2.Name) WITHIN GROUP (GRAPH PATH) AS PessoaFinal
FROM lab.Person P1,
     lab.Knows FOR PATH K,
     lab.Person FOR PATH P2
WHERE MATCH(SHORTEST_PATH(P1(-(K)->P2)+))
  AND P1.Name = 'Alice'
  AND LAST_VALUE(P2.Name) WITHIN GROUP (GRAPH PATH) = 'David';
GO

-- 5. DETECÇÃO DE NÓS ISOLADOS (ILHAS DESCONECTADAS SEM ARESTAS)
-- Análise de Grafos: Identifica entidades cadastradas no banco que não possuem NENHUMA conexão de aresta atrelada
-- REQUISITO DP-800: O operador MATCH() não permite operadores lógicos OR dentro de sua expressão.
-- Para validar sentidos de ida e volta com OR, devemos separar em cláusulas MATCH() distintas ou NOT EXISTS separados.
SELECT 
    P.Name AS PessoaIsolada,
    P.Email,
    'ALERTA: Nó no Grafo sem nenhuma Aresta conectada (Ilha Desconectada)' AS StatusConexao
FROM lab.Person P
WHERE NOT EXISTS (
    SELECT 1 FROM lab.OwnsCard O, lab.CreditCard C WHERE MATCH(P-(O)->C)
)
AND NOT EXISTS (
    SELECT 1 FROM lab.UsedIP U, lab.IPAddress IP WHERE MATCH(P-(U)->IP)
)
AND NOT EXISTS (
    SELECT 1 FROM lab.Knows K, lab.Person P2 WHERE MATCH(P-(K)->P2)
)
AND NOT EXISTS (
    SELECT 1 FROM lab.Knows K, lab.Person P2 WHERE MATCH(P<-(K)-P2)
);
GO

-- 6. GERADOR AUTOMÁTICO DE DIAGRAMA MERMAID (SQL DINÂMICO DE GRAFO -> MERMAID.JS)
-- Copie os resultados desta query e cole em qualquer visualizador Markdown para renderizar o mapa visual (https://mermaid.live/)
-- NOTA: Agrupa os nós por Componentes Conectados (Rede Principal vs Nós Isolados).
SELECT MermaidCode
FROM (
    SELECT 1 AS SortOrder, 'graph LR' AS MermaidCode
    UNION ALL
    SELECT 2 AS SortOrder, '    subgraph "Rede Principal de Conexões e Fraudes"' AS MermaidCode
    UNION ALL
    SELECT DISTINCT 3 AS SortOrder, '        ' + REPLACE(P.Name, ' ', '_') + '["Pessoa: ' + P.Name + '"]'
    FROM lab.Person P
    WHERE P.Name <> 'Eve'
    UNION ALL
    SELECT DISTINCT 3 AS SortOrder, '        C_' + REPLACE(REPLACE(C.CardNumber, '-', '_'), ' ', '_') + '["Cartão: ' + C.CardNumber + '"]' FROM lab.CreditCard C
    UNION ALL
    SELECT DISTINCT 3 AS SortOrder, '        IP_' + REPLACE(IP.IPAddress, '.', '_') + '["IP: ' + IP.IPAddress + '"]' FROM lab.IPAddress IP
    UNION ALL
    SELECT DISTINCT 4 AS SortOrder, '        ' + REPLACE(P.Name, ' ', '_') + ' -- "Possui" --> C_' + REPLACE(REPLACE(C.CardNumber, '-', '_'), ' ', '_')
    FROM lab.Person P, lab.OwnsCard O, lab.CreditCard C
    WHERE MATCH(P-(O)->C)
    UNION ALL
    SELECT DISTINCT 4 AS SortOrder, '        ' + REPLACE(P.Name, ' ', '_') + ' -- "Acessou IP" --> IP_' + REPLACE(IP.IPAddress, '.', '_')
    FROM lab.Person P, lab.UsedIP U, lab.IPAddress IP
    WHERE MATCH(P-(U)->IP)
    UNION ALL
    SELECT DISTINCT 4 AS SortOrder, '        ' + REPLACE(P1.Name, ' ', '_') + ' -- "Conhece" --> ' + REPLACE(P2.Name, ' ', '_')
    FROM lab.Person P1, lab.Knows K, lab.Person P2
    WHERE MATCH(P1-(K)->P2)
    UNION ALL
    SELECT 5 AS SortOrder, '    end' AS MermaidCode
    UNION ALL
    SELECT 6 AS SortOrder, '    subgraph "Nós Isolados (Ilhas sem Conexão)"' AS MermaidCode
    UNION ALL
    SELECT DISTINCT 7 AS SortOrder, '        ' + REPLACE(P.Name, ' ', '_') + '["Pessoa: ' + P.Name + '"]'
    FROM lab.Person P
    WHERE P.Name = 'Eve'
    UNION ALL
    SELECT 8 AS SortOrder, '    end' AS MermaidCode
) AS MermaidData
ORDER BY SortOrder;
GO

-- 7. ENCAPSULAMENTO EM STORED PROCEDURE 100% DINÂMICA: lab.sp_generate_mermaid_graph
-- Esta Procedure inspeciona os metadados do banco de dados (sys.tables onde is_node = 1 e is_edge = 1)
-- de FORMA 100% GENÉRICA (SEM HARDCODE), construindo dinamicamente as cláusulas para qualquer banco de grafos!
CREATE OR ALTER PROCEDURE lab.sp_generate_mermaid_graph
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#MermaidLines') IS NOT NULL DROP TABLE #MermaidLines;
    CREATE TABLE #MermaidLines (SortOrder INT, LineContent NVARCHAR(MAX));

    -- 1. CONSTRUIR O PREDICADO DINÂMICO DE CONEXÃO CONTRA TODAS AS TABELAS EDGE DO BANCO
    DECLARE @AllEdgesExistsClause NVARCHAR(MAX) = N'';

    SELECT @AllEdgesExistsClause = STRING_AGG(
        N'EXISTS (SELECT 1 FROM ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N' WHERE $from_id = N.$node_id OR $to_id = N.$node_id)',
        N' OR '
    )
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.is_edge = 1;

    IF ISNULL(@AllEdgesExistsClause, N'') = N''
        SET @AllEdgesExistsClause = N'1 = 0';

    INSERT INTO #MermaidLines VALUES (1, 'graph LR');

    -- 2. SUBGRAFO PARA NÓS CONECTADOS (REDE DE RELACIONAMENTOS)
    INSERT INTO #MermaidLines VALUES (2, '    subgraph "Rede Principal de Conexões"');

    DECLARE @NodeSchema NVARCHAR(128), @NodeTable NVARCHAR(128), @DisplayCol NVARCHAR(128), @SQL NVARCHAR(MAX);

    DECLARE node_cursor CURSOR FOR 
    SELECT s.name AS SchemaName, t.name AS TableName,
           ISNULL((SELECT TOP 1 c.name FROM sys.columns c WHERE c.object_id = t.object_id AND c.is_hidden = 0 AND c.name NOT LIKE '%ID%' ORDER BY c.column_id),
                  (SELECT TOP 1 c.name FROM sys.columns c WHERE c.object_id = t.object_id AND c.is_hidden = 0 ORDER BY c.column_id)) AS FirstUserCol
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.is_node = 1;

    OPEN node_cursor;
    FETCH NEXT FROM node_cursor INTO @NodeSchema, @NodeTable, @DisplayCol;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Nós que possuem conexões em qualquer aresta registrada nos metadados
        SET @SQL = N'INSERT INTO #MermaidLines ' +
                   N'SELECT 3, ''        N_'' + CONVERT(VARCHAR(32), HASHBYTES(''MD5'', N.$node_id), 2) + ' +
                   N'''["' + @NodeTable + ': '' + ISNULL(CAST(N.' + QUOTENAME(@DisplayCol) + N' AS NVARCHAR(100)), ''N/A'') + ''"]'' ' +
                   N'FROM ' + QUOTENAME(@NodeSchema) + N'.' + QUOTENAME(@NodeTable) + N' N ' +
                   N'WHERE (' + @AllEdgesExistsClause + N');';
        EXEC sp_executesql @SQL;

        FETCH NEXT FROM node_cursor INTO @NodeSchema, @NodeTable, @DisplayCol;
    END;

    CLOSE node_cursor;

    -- Arestas/Conexões dentro da Rede Principal (Inspeciona dinamicamente todas as tabelas EDGE)
    DECLARE @EdgeSchema NVARCHAR(128), @EdgeTable NVARCHAR(128);

    DECLARE edge_cursor CURSOR FOR 
    SELECT s.name AS SchemaName, t.name AS TableName
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.is_edge = 1;

    OPEN edge_cursor;
    FETCH NEXT FROM edge_cursor INTO @EdgeSchema, @EdgeTable;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'INSERT INTO #MermaidLines ' +
                   N'SELECT 4, ''        N_'' + CONVERT(VARCHAR(32), HASHBYTES(''MD5'', $from_id), 2) + ' +
                   N''' -- "' + @EdgeTable + N'" --> N_'' + CONVERT(VARCHAR(32), HASHBYTES(''MD5'', $to_id), 2) ' +
                   N'FROM ' + QUOTENAME(@EdgeSchema) + N'.' + QUOTENAME(@EdgeTable) + N';';
        EXEC sp_executesql @SQL;

        FETCH NEXT FROM edge_cursor INTO @EdgeSchema, @EdgeTable;
    END;

    CLOSE edge_cursor;
    DEALLOCATE edge_cursor;

    INSERT INTO #MermaidLines VALUES (5, '    end');

    -- 3. SUBGRAFO PARA NÓS ISOLADOS (ILHAS SEM CONEXÃO)
    INSERT INTO #MermaidLines VALUES (6, '    subgraph "Nós Isolados (Ilhas sem Conexão)"');

    OPEN node_cursor;
    FETCH NEXT FROM node_cursor INTO @NodeSchema, @NodeTable, @DisplayCol;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Nós que NÃO possuem conexões em NENHUMA aresta (Inversão dinâmica NOT)
        SET @SQL = N'INSERT INTO #MermaidLines ' +
                   N'SELECT 7, ''        N_'' + CONVERT(VARCHAR(32), HASHBYTES(''MD5'', N.$node_id), 2) + ' +
                   N'''["' + @NodeTable + ': '' + ISNULL(CAST(N.' + QUOTENAME(@DisplayCol) + N' AS NVARCHAR(100)), ''N/A'') + ''"]'' ' +
                   N'FROM ' + QUOTENAME(@NodeSchema) + N'.' + QUOTENAME(@NodeTable) + N' N ' +
                   N'WHERE NOT (' + @AllEdgesExistsClause + N');';
        EXEC sp_executesql @SQL;

        FETCH NEXT FROM node_cursor INTO @NodeSchema, @NodeTable, @DisplayCol;
    END;

    CLOSE node_cursor;
    DEALLOCATE node_cursor;

    INSERT INTO #MermaidLines VALUES (8, '    end');

    -- Exibir o código Mermaid gerado em ordem sequencial de linhas
    SELECT LineContent AS MermaidCodeFromMetadata
    FROM #MermaidLines
    ORDER BY SortOrder;
END;
GO

-- Teste de Execução da Stored Procedure 100% Dinâmica e Genérica:
-- A Procedure varre a sys.tables filtrando por is_node = 1 e is_edge = 1.
-- Como criamos DOIS grupos de grafos 100% independentes (Rede Financeira/Segurança + Rede Logística/Supply Chain):
-- 1. A Procedure detecta automaticamente as 6 tabelas Node (Person, CreditCard, IPAddress, Supplier, Warehouse, Product).
-- 2. A Procedure detecta automaticamente as 5 tabelas Edge (Knows, OwnsCard, UsedIP, Supplies, Stores).
-- 3. A Procedure inclui no subgrafo conectado todos os nós de AMBAS as redes que possuem relacionamentos.
-- 4. A Procedure detecta e insere no subgrafo "Nós Isolados" as ilhas sem conexão de AMBOS os grupos (Eve, FornecedorInativo Corp, ItemObsoleto SemEstoque).
-- TUDO ISSO SEM NENHUM HARDCODE OU ALTERAÇÃO NO CÓDIGO DA PROCEDURE!
EXEC lab.sp_generate_mermaid_graph;
GO


-- =================================================================================
*/

-- =================================================================================
-- PARTE 4: GRAPH TABLES (INTRODUÇÃO A NODE, EDGE E MATCH)
-- =================================================================================
-- Este lab apresenta apenas a modelagem básica. Os cenários de fraude,
-- SHORTEST_PATH e o renderizador Mermaid ficam no lab avançado de Graph.
-- Os nomes SpecializedGraph* evitam conflito com outros labs.

-- Edges devem ser removidas antes dos nodes quando o script for reexecutado.
DROP TABLE IF EXISTS lab.SpecializedGraphUses;
DROP TABLE IF EXISTS lab.SpecializedGraphAsset;
DROP TABLE IF EXISTS lab.SpecializedGraphPerson;
GO

-- Dois nodes e uma edge com CONNECTION mostram o contrato básico do Graph.
CREATE TABLE lab.SpecializedGraphPerson (
    PersonID int NOT NULL PRIMARY KEY,
    Name nvarchar(100) NOT NULL
) AS NODE;

CREATE TABLE lab.SpecializedGraphAsset (
    AssetID int NOT NULL PRIMARY KEY,
    AssetName nvarchar(100) NOT NULL
) AS NODE;

CREATE TABLE lab.SpecializedGraphUses (
    CONSTRAINT EC_SpecializedGraphUses
        CONNECTION (lab.SpecializedGraphPerson TO lab.SpecializedGraphAsset)
) AS EDGE;
GO

-- `$node_id` é a chave interna usada pelas arestas; PersonID e AssetID continuam
-- sendo as chaves de negócio exibidas para o usuário.
INSERT INTO lab.SpecializedGraphPerson (PersonID, Name)
VALUES (1, N'Alice'), (2, N'Bob');

INSERT INTO lab.SpecializedGraphAsset (AssetID, AssetName)
VALUES (10, N'Laptop corporativo'), (20, N'Token de acesso');

INSERT INTO lab.SpecializedGraphUses ($from_id, $to_id)
VALUES
((SELECT $node_id FROM lab.SpecializedGraphPerson WHERE PersonID = 1),
 (SELECT $node_id FROM lab.SpecializedGraphAsset WHERE AssetID = 10)),
((SELECT $node_id FROM lab.SpecializedGraphPerson WHERE PersonID = 2),
 (SELECT $node_id FROM lab.SpecializedGraphAsset WHERE AssetID = 20));
GO

-- MATCH substitui os joins manuais entre `$node_id`, `$from_id` e `$to_id`.
SELECT p.Name AS Pessoa,
       a.AssetName AS AtivoUtilizado
FROM lab.SpecializedGraphPerson AS p,
     lab.SpecializedGraphUses AS u,
     lab.SpecializedGraphAsset AS a
WHERE MATCH(p-(u)->a);
GO

-- =================================================================================
-- PARTE 5: EXTERNAL TABLES & VIRTUALIZAÇÃO DE DADOS (POLYBASE / DATA LAKE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE (DP-800):
--   - TABELAS EXTERNAS (External Tables / PolyBase): Recurso de virtualização de dados que permite ao SQL Server / Synapse
--     consultar arquivos armazenados fora do banco de dados (ex: Azure Blob Storage, Azure Data Lake Gen2, S3, HDFS) 
--     como se fossem tabelas relacionais locais, sem importar fisicamente os dados.
--   - DATABASE SCOPED CREDENTIAL: Objeto de segurança local do banco que encapsula as credenciais de autenticação
--     (chaves de conta de armazenamento, tokens SAS, identidades gerenciadas) necessárias para acessar o storage externo.
--   - EXTERNAL DATA SOURCE: Define a conexão lógica apontando para o endpoint físico do storage externo
--     (URL do bucket/container) e associa a respectiva credencial de escopo criada.
--   - EXTERNAL FILE FORMAT: Define as propriedades de formatação dos arquivos que residem no storage
--     (ex: tipo do arquivo PARQUET ou CSV DELIMITEDTEXT, tipo de compressão Snappy/Gzip, delimitadores de campo, etc.).
--   - EXTERNAL TABLE: Tabela virtual que vincula a estrutura relacional de colunas (tipos SQL) ao local físico
--     do arquivo (LOCATION) referenciando a fonte de dados (DATA_SOURCE) e o formato (FILE_FORMAT).

-- ---------------------------------------------------------------------------------
-- EXEMPLO 1A: BULK INSERT - IMPORTAR CSV LOCALMENTE (SQL SERVER 2022 LOCAL)
-- ---------------------------------------------------------------------------------
-- Arquivo de teste: practice/labs/data/sales_data.csv (CRLF — padrão Windows)
--
-- ⚠️ PONTO DE ATENÇÃO 1 — CSV no SQL Server:
--   • SQL Server 2017+ suporta FORMAT = 'CSV' para arquivos compatíveis com RFC 4180.
--   • FORMAT = 'CSV' pode ser combinado com FIELDTERMINATOR, ROWTERMINATOR e FIELDQUOTE.
--   • Este exemplo usa o modo clássico para evidenciar delimitadores; prefira FORMAT = 'CSV'
--     quando precisar tratar corretamente campos entre aspas que contenham vírgulas.
--
-- ⚠️ PONTO DE ATENÇÃO 2 — ROWTERMINATOR depende do encoding do arquivo:
--
--   CENÁRIO A — CSV salvo no Windows/Excel (CRLF = 0x0D 0x0A):
--     ROWTERMINATOR = '\r\n'    ← string literal   (funciona ✅)
--     ROWTERMINATOR = '0x0d0a'  ← hex equivalente  (também funciona ✅)
--
--   CENÁRIO B — CSV salvo no Linux/Mac/Git (LF puro = 0x0A):
--     ROWTERMINATOR = '0x0a'    ← OBRIGATÓRIO usar hex (✅)
--     ROWTERMINATOR = '\n'      ← NÃO funciona no Windows SQL Server (❌ tabela vazia!)
--     → Por quê? O SQL Server interpreta '\n' como 2 chars literais (\+n),
--       não como o byte 0x0A, então nunca encontra o terminador de linha.
--
--   Como detectar o encoding do seu CSV (PowerShell):
--     [System.IO.File]::ReadAllBytes('arquivo.csv') | % { '{0:X2}' -f $_ } | Select -Last 4
--     → Termina em "0D 0A" = CRLF (Cenário A) → use '\r\n'
--     → Termina em "0A"    = LF   (Cenário B) → use '0x0a'
--
-- O arquivo sales_data.csv deste lab usa CRLF (Cenário A) — testado e funcional.
-- ---------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#SalesImport') IS NOT NULL DROP TABLE #SalesImport;
CREATE TABLE #SalesImport (
    SaleID      INT,
    ProductName VARCHAR(100),
    Amount      DECIMAL(18,2),
    SaleDate    DATE
);
-- Ajuste o caminho se o repositório estiver em outro diretório.
BULK INSERT #SalesImport
FROM 'd:\source\dp-800-study-guide\practice\labs\data\sales_data.csv'
WITH (
    FIRSTROW        = 2,          -- Pular linha de cabeçalho
    FIELDTERMINATOR = ',',        -- Separador de colunas
    ROWTERMINATOR   = '0x0d0a',   -- ✅ CRLF como hex explícito (padrão seguro no SQL Server Windows)
    -- ROWTERMINATOR = '0x0a',    -- Use este se o CSV for LF puro (Linux/Mac/Git)
    TABLOCK,                      -- Lock de tabela: melhor performance em carga em lote
    MAXERRORS       = 0           -- Abortar imediatamente em qualquer erro
);

SELECT SaleID, ProductName, Amount, SaleDate FROM #SalesImport;
GO


/* -- EXEMPLO 1B: OPENROWSET COM FORMAT='CSV' E PARSER_VERSION (APENAS AZURE SYNAPSE SERVERLESS)
-- Execute este bloco em Azure Synapse Analytics Serverless SQL Pool, NÃO em SQL Server local.
SELECT 
    SalesCSV.SaleID,
    SalesCSV.ProductName,
    SalesCSV.Amount,
    SalesCSV.SaleDate
FROM OPENROWSET(
    BULK 'd:\source\dp-800-study-guide\practice\labs\data\sales_data.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',  -- Suportado apenas em Synapse Serverless v2 parser
    FIRSTROW = 2
) WITH (
    SaleID INT,
    ProductName VARCHAR(100),
    Amount DECIMAL(18,2),
    SaleDate DATE
) AS SalesCSV;
GO
*/

/*
-- ---------------------------------------------------------------------------------

-- EXEMPLO 2: DDL COMPLETO DE TABELAS EXTERNAS (REQUISITO DP-800 & SYNAPSE/POLYBASE)
-- Referência Oficial: Microsoft SQL DW / Synapse Samples
-- (https://github.com/microsoft/sql-server-samples/blob/master/samples/demos/SQLDW/free-trial-lab/create-external-tables.sql)
-- ---------------------------------------------------------------------------------
-- 1. Criar Formato de Arquivo CSV (Delimited Text)
CREATE EXTERNAL FILE FORMAT CSVFileFormat
WITH (
    FORMAT_TYPE = DELIMITEDTEXT,
    FORMAT_OPTIONS (
        FIELD_TERMINATOR = ',',
        STRING_DELIMITER = '"',
        FIRST_ROW = 2,
        USE_TYPE_DEFAULT = TRUE
    )
);
GO

-- 2. Criar Formato de Arquivo PARQUET (Compactação Snappy)
CREATE EXTERNAL FILE FORMAT ParquetFileFormat
WITH (
    FORMAT_TYPE = PARQUET,
    DATA_COMPRESSION = 'org.apache.hadoop.io.compress.SnappyCodec'
);
GO

-- 3. Criar Credencial de Escopo de Banco (SAS Token / Shared Key)
CREATE DATABASE SCOPED CREDENTIAL [MyStorageCredential]
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = 'sv=2021-06-08&ss=bfqt&srt=sco&sp=rwdlacupx...'; -- Token SAS do Azure Storage
GO

-- 4. Criar Fonte de Dados Externa (Azure Data Lake Storage Gen2 / Blob Storage)
CREATE EXTERNAL DATA SOURCE AzureBlobStorageSales
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://myaccount.blob.core.windows.net/salesdata',
    CREDENTIAL = [MyStorageCredential]
);
GO

-- 5. Criar Tabela Externa Mapeada para Arquivos no Data Lake
CREATE EXTERNAL TABLE lab.ExternalSalesOrders (
    SalesOrderID INT NOT NULL,
    OrderDate DATETIME2 NULL,
    CustomerID INT NULL,
    TotalDue DECIMAL(18,2) NULL
)
WITH (
    LOCATION = '/parquet_exports/2026/',
    DATA_SOURCE = AzureBlobStorageSales,
    FILE_FORMAT = ParquetFileFormat
);
GO
*/
-- =========================================================================
-- EXEMPLO 3: NYC TAXI - AZURE OPEN DATASETS (URLs CORRETAS DA DOCUMENTAÇÃO OFICIAL)
-- =========================================================================
-- FONTE OFICIAL: https://learn.microsoft.com/en-us/azure/open-datasets/dataset-taxi-yellow
--
-- ✅ URL CORRETA:
--   Storage Account : azureopendatastorage
--   Container       : nyctlc            (NÃO "azureopen/yellowtripdata")
--   Táxi Amarelo    : nyctlc/yellow/
--   Táxi Verde      : nyctlc/green/
--
-- Estrutura de pastas (particionamento Hive):
--   nyctlc/yellow/puYear=<ano>/puMonth=<mes>/<arquivo>.parquet
--   nyctlc/green/puYear=<ano>/puMonth=<mes>/<arquivo>.parquet
--
-- Protocolo para OPENROWSET no Synapse Serverless SQL:
--   abs://<container>@<account>.blob.core.windows.net/<path>
--   abs://nyctlc@azureopendatastorage.blob.core.windows.net/yellow/puYear=2018/puMonth=6/*.parquet
--
-- ⚠️  COLUNAS: camelCase  (NÃO snake_case!)
--   tpepPickupDateTime   (NÃO tpep_pickup_datetime)
--   tpepDropoffDateTime  (NÃO tpep_dropoff_datetime)
--   fareAmount, totalAmount, passengerCount, tripDistance ...
-- =========================================================================

-- -----------------------------------------------------------------------
-- EXEMPLO 3A-1: CONSULTA DE ARQUIVO ÚNICO (UM MÊS ESPECÍFICO)
-- Executar em: Azure Synapse Serverless SQL Pool ou Azure SQL + PolyBase
-- -----------------------------------------------------------------------
-- Lê apenas um conjunto de arquivos parquet de um mês/ano específico
SELECT TOP 100
    *
FROM OPENROWSET(
    -- abs:// = Azure Blob Storage URI scheme — funciona no Synapse Serverless
    -- *.parquet = curinga para todos os arquivos do mês (pode ser subdividido em chunks)
    BULK 'abs://nyctlc@azureopendatastorage.blob.core.windows.net/yellow/puYear=2018/puMonth=6/*.parquet',
    FORMAT = 'PARQUET'
) AS TaxiYellow2018Jun
ORDER BY tpepPickupDateTime;
GO

-- -----------------------------------------------------------------------
-- EXEMPLO 3A-2: CONSULTA DE PASTA INTEIRA (MÚLTIPLOS ANOS/MESES)
-- Usa curinga ** para varrer recursivamente todas as partições
-- -----------------------------------------------------------------------

SELECT 
    COUNT(*)                        AS TotalCorridas
    --AVG(fareAmount)                 AS TarifaMedia,
    --AVG(passengerCount)             AS PassageirosMedio,
    --SUM(totalAmount)                AS FaturamentoTotal
FROM OPENROWSET(
    -- ** = curinga recursivo: lê TODAS as partições ano/mês de uma só vez
    BULK 'abs://nyctlc@azureopendatastorage.blob.core.windows.net/yellow/**',
    FORMAT = 'PARQUET'
) AS TaxiYellowAll

GO

-- -----------------------------------------------------------------------
-- EXEMPLO 3B: DDL COMPLETO DE TABELAS EXTERNAS (SYNAPSE SQL DEDICADO / POLYBASE)
-- Para uso no Azure Synapse Analytics SQL Pool Dedicado.
-- NOTA: Containers públicos NÃO exigem DATABASE SCOPED CREDENTIAL!
-- -----------------------------------------------------------------------

-- -----------------------------------------------------------------------
-- EXEMPLO 3B: CREATE EXTERNAL TABLE — REQUISITO DP-800 (REFERÊNCIA)
-- ⚠️  Este bloco É REFERÊNCIA PARA O EXAME — não executar localmente!
-- -----------------------------------------------------------------------
-- CAUSA DO ERRO Msg 46525 "External tables not supported with data source type":
--
--   TYPE = BLOB_STORAGE → APENAS para BULK INSERT e OPENROWSET ad-hoc
--                          NÃO suporta CREATE EXTERNAL TABLE
--
--   TYPE = HADOOP        → Necessário para CREATE EXTERNAL TABLE
--                          Requer PolyBase habilitado no SQL Server
--
-- MATRIZ DE COMPATIBILIDADE:
-- ┌─────────────────────────────┬─────────────┬──────────────────┬──────────────────┐
-- │ Operação                    │ SQL Local   │ Synapse Serverl. │ Synapse Dedicado │
-- ├─────────────────────────────┼─────────────┼──────────────────┼──────────────────┤
-- │ BULK INSERT                 │ ✅ BLOB_ST. │ ✅               │ ✅               │
-- │ OPENROWSET(BULK...)         │ ✅ BLOB_ST. │ ✅ (abs://)      │ ✅               │
-- │ CREATE EXTERNAL TABLE       │ ✅ HADOOP   │ ✅ (sem DDL)     │ ✅ HADOOP/abfss  │
-- │ TYPE = BLOB_STORAGE + ExTab │ ❌ Msg 46525│ ❌               │ ❌               │
-- └─────────────────────────────┴─────────────┴──────────────────┴──────────────────┘
--
/* ============================================================
   DDL PARA SQL SERVER 2022 ON-PREMISES + POLYBASE
   Requisito: PolyBase Feature instalado e habilitado
   sp_configure 'polybase enabled', 1; RECONFIGURE;
   ============================================================

-- SQL Server 2022: usa TYPE = HADOOP com protocolo wasbs://
CREATE EXTERNAL DATA SOURCE NYC_Taxi_Yellow_PolyBase
WITH (
    TYPE = HADOOP,
    LOCATION = 'wasbs://nyctlc@azureopendatastorage.blob.core.windows.net'
    -- Container público: sem CREDENTIAL
);
GO

CREATE EXTERNAL FILE FORMAT NycTaxiParquet
WITH (
    FORMAT_TYPE = PARQUET,
    DATA_COMPRESSION = 'org.apache.hadoop.io.compress.SnappyCodec'
);
GO

CREATE EXTERNAL TABLE lab.ExternalYellowTaxi (
    vendorID              VARCHAR(10),
    tpepPickupDateTime    DATETIME2(7),
    tpepDropoffDateTime   DATETIME2(7),
    passengerCount        INT,
    tripDistance          FLOAT,
    puLocationId          VARCHAR(10),
    doLocationId          VARCHAR(10),
    rateCodeId            INT,
    storeAndFwdFlag       CHAR(2),
    paymentType           INT,
    fareAmount            FLOAT,
    extra                 FLOAT,
    mtaTax                FLOAT,
    improvementSurcharge  VARCHAR(10),
    tipAmount             FLOAT,
    tollsAmount           FLOAT,
    totalAmount           FLOAT,
    puYear                INT,
    puMonth               INT
)
WITH (
    LOCATION = 'yellow/',
    DATA_SOURCE = NYC_Taxi_Yellow_PolyBase,
    FILE_FORMAT = NycTaxiParquet,
    REJECT_TYPE = VALUE,
    REJECT_VALUE = 0
);
GO
============================================================ */

/* ============================================================
   DDL PARA AZURE SYNAPSE ANALYTICS SQL POOL DEDICADO
   Usa abfss:// (Azure Data Lake Storage Gen2) ou wasbs://
   ============================================================

-- Synapse Dedicated: TYPE = HADOOP com abfss://
CREATE EXTERNAL DATA SOURCE NYC_Taxi_ADLS
WITH (
    TYPE = HADOOP,
    LOCATION = 'abfss://nyctlc@azureopendatastorage.dfs.core.windows.net'
    -- Para ADLS Gen2, use .dfs.core.windows.net (não .blob.)
);
GO

CREATE EXTERNAL TABLE dbo.ExternalYellowTaxi (
    vendorID              VARCHAR(10),
    tpepPickupDateTime    DATETIME2(7),
    tpepDropoffDateTime   DATETIME2(7),
    passengerCount        INT,
    tripDistance          FLOAT,
    fareAmount            FLOAT,
    totalAmount           FLOAT,
    puYear                INT,
    puMonth               INT
)
WITH (
    LOCATION = 'yellow/puYear=2018/puMonth=6/',
    DATA_SOURCE = NYC_Taxi_ADLS,
    FILE_FORMAT = NycTaxiParquet
);
GO
============================================================ */

-- -----------------------------------------------------------------------
-- EXEMPLO 3C: ANÁLISE — CONSULTA AD-HOC (EXECUTA NO SYNAPSE SERVERLESS)
-- -----------------------------------------------------------------------
-- Distribuição de corridas por hora do dia (Junho/2018)
SELECT
    DATEPART(HOUR, tpepPickupDateTime) AS HoraDoDia,
    COUNT(*)                           AS TotalCorridas,
    AVG(fareAmount)                    AS TarifaMedia,
    AVG(CAST(passengerCount AS FLOAT)) AS MediaPassageiros
FROM OPENROWSET(
    BULK 'abs://nyctlc@azureopendatastorage.blob.core.windows.net/yellow/puYear=2018/puMonth=6/*.parquet',
    FORMAT = 'PARQUET'
) AS TaxiYellow
GROUP BY DATEPART(HOUR, tpepPickupDateTime)
ORDER BY HoraDoDia;
GO

-- =================================================================================
-- SCRIPT DE LIMPEZA GERAL / TEARDOWN (OPCIONAL)
-- Execute este bloco para remover TODOS os objetos criados neste laboratório.
-- =================================================================================
/*
USE AdventureWorks2025;
GO

-- 1. Desativar System Versioning antes de dropar tabelas temporais e ledger
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'SalariesLedger' AND schema_id = SCHEMA_ID('lab'))
    ALTER TABLE lab.SalariesLedger SET (SYSTEM_VERSIONING = OFF);

IF EXISTS (SELECT * FROM sys.tables WHERE name = 'EmployeesTemporal' AND schema_id = SCHEMA_ID('lab'))
    ALTER TABLE lab.EmployeesTemporal SET (SYSTEM_VERSIONING = OFF);

-- 2. Drop das Tabelas do Lab 2
DROP TABLE IF EXISTS lab.FinancialTransactionsLedger;
DROP TABLE IF EXISTS lab.SalariesLedger;
DROP TABLE IF EXISTS lab.EmployeesTemporal;
DROP TABLE IF EXISTS lab.EmployeesTemporalHistory;

-- 3. Drop das Graph Tables (Arestas primeiro, depois Nós)
DROP TABLE IF EXISTS lab.OwnsCard;
DROP TABLE IF EXISTS lab.UsedIP;
DROP TABLE IF EXISTS lab.Knows;
DROP TABLE IF EXISTS lab.CreditCard;
DROP TABLE IF EXISTS lab.IPAddress;
DROP TABLE IF EXISTS lab.Person;

-- 4. Drop das In-Memory Tables e Types
DROP TABLE IF EXISTS lab.SessionCacheMemData;
DROP TABLE IF EXISTS lab.SessionCacheMemOnly;
DROP TYPE IF EXISTS lab.MyMemoryTableType;

-- 5. Drop de Stored Procedures e Objetos de External Tables
DROP PROCEDURE IF EXISTS lab.sp_generate_mermaid_graph;
DROP EXTERNAL TABLE IF EXISTS lab.ExternalSalesOrders;
DROP EXTERNAL TABLE IF EXISTS lab.ExternalYellowTaxi2013;
DROP EXTERNAL TABLE IF EXISTS lab.ExternalGreenTaxi2013;
DROP EXTERNAL TABLE IF EXISTS lab.ExternalYellowTaxi;

IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'AzureBlobStorageSales') DROP EXTERNAL DATA SOURCE AzureBlobStorageSales;
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'NYC_Taxi_Yellow') DROP EXTERNAL DATA SOURCE NYC_Taxi_Yellow;
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'NYC_Taxi_Green') DROP EXTERNAL DATA SOURCE NYC_Taxi_Green;

IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'ParquetFileFormat') DROP EXTERNAL FILE FORMAT ParquetFileFormat;
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'NycTaxiParquet') DROP EXTERNAL FILE FORMAT NycTaxiParquet;
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'CSVFileFormat') DROP EXTERNAL FILE FORMAT CSVFileFormat;

IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'MyStorageCredential') DROP DATABASE SCOPED CREDENTIAL [MyStorageCredential];

-- 6. Tabela Temporária do BULK INSERT
IF OBJECT_ID('tempdb..#SalesImport') IS NOT NULL DROP TABLE #SalesImport;
GO
*/


-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/01-database-objects/02-specialized-tables.md
-- =================================================================================================
-- =================================================================================================
-- REFERÊNCIAS OFICIAIS DO MICROSOFT LEARN
-- =================================================================================================
-- Tabelas com otimização de memória e durabilidade:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/in-memory-oltp/introduction-to-memory-optimized-tables?view=sql-server-ver17
-- Tabelas temporais com versão do sistema:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/tables/temporal-tables?view=sql-server-ver17
-- Tabelas ledger:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/security/ledger/ledger-landing-sql-server?view=sql-server-ver17
-- SQL Graph:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/graphs/sql-graph-overview?view=sql-server-ver17
-- Tabelas externas e PolyBase:
-- https://learn.microsoft.com/pt-br/sql/t-sql/statements/create-external-table-transact-sql?view=sql-server-ver17





