-- =================================================================================
-- DP-800 - LAB PRÁTICO: PARTICIONAMENTO DE TABELAS E ÍNDICES
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/01-database-objects/05-partitioning.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a criação, gerenciamento e otimização de tabelas e 
-- índices particionados no SQL Server, abordando:
--   1. Criação de Partition Function (RANGE RIGHT) e Partition Scheme
--   2. Criação de tabelas e índices alinhados particionados
--   3. Verificação de Partições via DMV e função de sistema $PARTITION
--   4. Eliminação de Partição (Partition Elimination) no plano de execução
--   5. Operação instantânea de arquivamento: Partition Switching (SWITCH OUT)
--   6. Ciclo de Janela Deslizante (Sliding Window): SPLIT, MERGE e NEXT USED
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva caso rode o script mais de uma vez
DROP TABLE IF EXISTS lab.OrdersPartitionedStaging;
DROP TABLE IF EXISTS lab.OrdersPartitionedHistory;
DROP TABLE IF EXISTS lab.OrdersPartitioned;
IF EXISTS (SELECT * FROM sys.partition_schemes WHERE name = 'PS_OrdersByYear')
    DROP PARTITION SCHEME PS_OrdersByYear;
IF EXISTS (SELECT * FROM sys.partition_functions WHERE name = 'PF_OrdersByYear')
    DROP PARTITION FUNCTION PF_OrdersByYear;
GO


-- =================================================================================
-- PARTE 1: CRIANDO A ESTRUTURA DE PARTICIONAMENTO (FUNCTION E SCHEME)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PARTICIONAMENTO DE TABELAS: Técnica de divisão física de tabelas e índices em segmentos menores e
--     gerenciáveis (partições) na base, mantendo a visão lógica relacional como uma única tabela para a aplicação.
--     Melhora significativamente a performance de varredura e a manutenção de grandes volumes de dados.
--   - PARTITION FUNCTION (Função de Partição): Define a regra lógica de divisão de dados com base em uma chave
--     de partição e limites específicos (boundary values), mapeando se os limites pertencem ao lado esquerdo ou direito.
--   - RANGE RIGHT VS RANGE LEFT:
--     * RANGE RIGHT: O valor limite (ex: '2025-01-01') é o valor mínimo do intervalo à direita (dado >= limite).
--       É o padrão mais intuitivo e recomendado para partições de data (ex: dados de 2025 começam exatamente em 01/01).
--     * RANGE LEFT: O valor limite pertence ao intervalo à esquerda (dado <= limite).
--   - PARTITION SCHEME (Esquema de Partição): Mapeia as partições lógicas geradas pela Partition Function
--     para diferentes Filegroups físicos do banco de dados (permitindo distribuir I/O entre discos diferentes).
--   - ÍNDICES ALINHADOS: Índices que compartilham do mesmo Partition Scheme e Partition Key da tabela base. 
--     O alinhamento perfeito de todos os índices é requisito obrigatório para habilitar o comando de Partition Switching.

-- 1. Criar a Partition Function (RANGE RIGHT para agrupamentos de datas)
-- RANGE RIGHT: O valor limite especificado pertence à partição à direita (>= valor).
-- Valores limites: 2024-01-01, 2025-01-01, 2026-01-01.
-- Isto cria 4 partições:
--   Partição 1: valores < '2024-01-01'
--   Partição 2: valores >= '2024-01-01' e < '2025-01-01'
--   Partição 3: valores >= '2025-01-01' e < '2026-01-01'
--   Partição 4: valores >= '2026-01-01'
CREATE PARTITION FUNCTION PF_OrdersByYear (DATE)
AS RANGE RIGHT FOR VALUES (
    '2024-01-01', 
    '2025-01-01', 
    '2026-01-01'
);
GO

-- 2. Criar o Partition Scheme
-- Mapeando todas as partições para o filegroup PRIMARY (para facilitar o laboratório).
-- Em produção, costuma-se mapear para filegroups de discos diferentes para ganho de I/O.
CREATE PARTITION SCHEME PS_OrdersByYear
AS PARTITION PF_OrdersByYear ALL TO ([PRIMARY]);
GO

-- 3. Criar a Tabela Particionada referenciando o Scheme
-- Importante: A chave de particionamento (OrderDate) DEVE fazer parte da chave primária composta.
CREATE TABLE lab.OrdersPartitioned (
    OrderID INT NOT NULL,
    OrderDate DATE NOT NULL,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_OrdersPartitioned PRIMARY KEY CLUSTERED (OrderDate, OrderID)
) ON PS_OrdersByYear (OrderDate); -- Tabela particionada aqui
GO

-- 4. Criar um Índice Não-Clusterizado ALINHADO
-- Um índice está "alinhado" quando é criado no mesmo Partition Scheme da tabela base.
-- Isso é pré-requisito obrigatório para operações de Partition Switching.
CREATE NONCLUSTERED INDEX IX_OrdersPartitioned_CustomerID
ON lab.OrdersPartitioned(CustomerID)
ON PS_OrdersByYear (OrderDate); -- Alinhado!
GO


-- =================================================================================
-- PARTE 2: CONSULTANDO METADADOS E A FUNÇÃO $PARTITION
-- =================================================================================

-- 1. Popular dados de teste para diferentes anos
INSERT INTO lab.OrdersPartitioned (OrderID, OrderDate, CustomerID, TotalAmount)
VALUES 
(1, '2023-11-15', 101, 150.00), -- Partição 1 (< 2024)
(2, '2024-05-10', 102, 350.00), -- Partição 2 (2024)
(3, '2024-12-31', 103, 720.00), -- Partição 2 (2024)
(4, '2025-02-28', 101, 110.00), -- Partição 3 (2025)
(5, '2026-07-20', 104, 500.00); -- Partição 4 (>= 2026)
GO

-- 2. Descobrir a qual partição um determinado valor pertence usando a função $PARTITION
SELECT 
    $PARTITION.PF_OrdersByYear('2023-11-15') AS Particao_Registro_1,
    $PARTITION.PF_OrdersByYear('2024-12-31') AS Particao_Registro_3,
    $PARTITION.PF_OrdersByYear('2026-01-01') AS Particao_Registro_5;
GO

-- 3. Visualizar as partições, contagem de linhas e faixas via DMV de metadados
SELECT 
    p.partition_number AS NumeroParticao,
    p.rows AS QuantidadeLinhas,
    prv.value AS LimiteValorSuperior
FROM sys.partitions p
JOIN sys.indexes i
    ON i.object_id = p.object_id
   AND i.index_id = p.index_id
JOIN sys.partition_schemes ps
    ON ps.data_space_id = i.data_space_id
JOIN sys.partition_functions pf
    ON pf.function_id = ps.function_id
LEFT JOIN sys.partition_range_values prv 
    ON prv.function_id = pf.function_id 
    AND prv.boundary_id = p.partition_number
WHERE pf.name = 'PF_OrdersByYear' AND p.index_id <= 1
ORDER BY p.partition_number;
GO


-- =================================================================================
-- PARTE 3: ELIMINAÇÃO DE PARTIÇÃO (PARTITION ELIMINATION)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - ELIMINAÇÃO DE PARTIÇÃO (Partition Elimination): Otimização crucial em que a engine de consulta,
--     ao analisar os filtros da query (cláusula WHERE), identifica as partições que contêm as linhas desejadas
--     e acessa fisicamente APENAS essas partições, descartando as restantes. Reduz o I/O e acelera as buscas.
--   - IMPEDIMENTOS DE ELIMINAÇÃO (Gargalos): O otimizador de consultas não consegue aplicar essa simplificação,
--     forçando um escaneamento completo de todas as partições (Partition Scan), se:
--     1. O filtro usar funções na coluna chave de partição (ex: `WHERE YEAR(OrderDate) = 2025` em vez de `WHERE OrderDate >= '2025-01-01'`).
--     2. A função ou conversão for aplicada à própria coluna particionada (ex: `WHERE YEAR(OrderDate) = 2025`).
--        Uma função aplicada ao valor procurado, como `OrderDate >= CAST(GETDATE() AS date)`, não impede
--        automaticamente a eliminação; confirme sempre o plano.
--     3. Ocorrerem conversões implícitas sobre a chave de partição, impedindo o predicado de ser sargável.

SET STATISTICS IO ON;
GO

-- Teste 1: Query filtrando pela Partition Key (OrderDate)
-- PLANO DE EXECUÇÃO: Verifique as propriedades do Clustered Index Seek. 
-- No campo "Partitions Accessed", você verá um intervalo fixo como "3..3" (acessou apenas a partição do ano de 2025).
SELECT OrderID, CustomerID, TotalAmount 
FROM lab.OrdersPartitioned
WHERE OrderDate = '2025-02-28';
GO

-- Teste 2: Query filtrando por outra coluna sem a chave de partição
-- PLANO DE EXECUÇÃO: O otimizador precisa escanear todas as partições em busca do ID. 
-- No campo "Partitions Accessed", o intervalo será "1..4" (Full Scan de partições).
SELECT OrderID, CustomerID, TotalAmount 
FROM lab.OrdersPartitioned
WHERE CustomerID = 101;
GO

SET STATISTICS IO OFF;
GO


-- =================================================================================
-- PARTE 4: PARTITION SWITCHING (ARQUIVAMENTO E CARGA EM MILISSEGUNDOS)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PARTITION SWITCHING (Troca de Partição): Operação de metadados normalmente muito rápida
--     usada para mover blocos inteiros de dados de uma tabela/partição para outra. A engine apenas altera os ponteiros 
--     físicos de alocação de páginas no dicionário de dados do SQL Server, sem mover linhas fisicamente.
--     Ainda assim, requer locks de esquema e pode bloquear ou ser bloqueada; não trate como garantia de downtime zero.
--   - REQUISITOS E REGRAS RÍGIDAS DE SWITCH:
--     1. As tabelas origem e destino devem possuir estruturas idênticas (mesmas colunas, tipos de dados, nulidade e constraints).
--     2. Todos os índices (tanto o Clustered principal quanto os NCIs) devem estar alinhados no mesmo Partition Scheme.
--     3. A partição ou a tabela de destino da troca deve estar completamente vazia (TRUNCATE).
--     4. Ambas as tabelas ou partições de origem e destino devem residir no mesmo Filegroup físico.

-- 1. Criar a Tabela de Histórico (Destino do arquivamento da Partição 2 - Ano 2024)
-- Deve estar alinhada no mesmo esquema de partição e ter as mesmas constraints/índices.
CREATE TABLE lab.OrdersPartitionedHistory (
    OrderID INT NOT NULL,
    OrderDate DATE NOT NULL,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_OrdersPartitionedHistory PRIMARY KEY CLUSTERED (OrderDate, OrderID)
) ON PS_OrdersByYear (OrderDate);

CREATE NONCLUSTERED INDEX IX_OrdersPartitionedHistory_CustomerID
ON lab.OrdersPartitionedHistory(CustomerID)
ON PS_OrdersByYear (OrderDate);
GO

-- 2. Executar o SWITCH OUT da Partição 2 (Dados de 2024) para a tabela de histórico
-- Perceba que isso é instantâneo e livre de locks de escrita em disco nas linhas!
ALTER TABLE lab.OrdersPartitioned
SWITCH PARTITION 2 TO lab.OrdersPartitionedHistory PARTITION 2;
GO

-- 3. Verificando o resultado: os dados do ano de 2024 sumiram da tabela ativa e estão no histórico.
SELECT 'Ativa (2024 removida)' AS Tabela, OrderID, OrderDate FROM lab.OrdersPartitioned
UNION ALL
SELECT 'Histórico (Apenas 2024)', OrderID, OrderDate FROM lab.OrdersPartitionedHistory;
GO


-- =================================================================================
-- PARTE 5: JANELA DESLIZANTE (SLIDING WINDOW) - SPLIT E MERGE
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - JANELA DESLIZANTE (Sliding Window): Técnica de administração de dados temporais para manter apenas dados 
--     de um período recente ativo (ex: manter sempre os últimos 3 anos ativos). Periodicamente, removemos o ano
--     mais antigo (MERGE) e criamos um intervalo para o ano que está entrando (SPLIT).
--   - SPLIT (Divisão): Comando da Partition Function que cria um novo limite (boundary), dividindo uma partição
--     existente em duas. Antes do SPLIT, confirme que cada partition scheme dependente já tem um filegroup
--     `NEXT USED`; execute `ALTER PARTITION SCHEME ... NEXT USED` apenas quando isso ainda não estiver definido.
--   - MERGE (Fusão): Comando que exclui um limite de partição, fundindo duas partições adjacentes em uma única.
--   - MOVIMENTAÇÃO FÍSICA DE DADOS (Data Movement): Se executarmos um SPLIT em uma partição que já possui dados gravados,
--     ou um MERGE fundindo partições que contêm linhas ativas, o SQL Server será forçado a mover as linhas fisicamente 
--     no disco para alinhá-las à nova lógica das partições. Isso gera locks extensos de tabela, consome muito log de transações
--     e pode travar o banco. **Sempre esvazie a partição (via SWITCH ou TRUNCATE) antes do MERGE, e execute o SPLIT apenas em segmentos vazios.**

-- 1. Definir qual Filegroup receberá o novo limite criado pelo SPLIT.
-- Em um ambiente com múltiplos schemes, confirme o NEXT USED de cada um deles.
ALTER PARTITION SCHEME PS_OrdersByYear
NEXT USED [PRIMARY];
GO

-- 2. Executar o SPLIT para criar uma nova partição de dados futura (Ano de 2027)
-- Limite lógico: 2027-01-01
ALTER PARTITION FUNCTION PF_OrdersByYear()
SPLIT RANGE ('2027-01-01');
GO

-- 3. Executar o MERGE para unir partições vazias antigas
-- Unir a partição correspondente a '2024-01-01'
ALTER PARTITION FUNCTION PF_OrdersByYear()
MERGE RANGE ('2024-01-01');
GO

-- 4. Verifique a nova configuração de metadados das partições
-- Note que o número e os limites de partições foram readequados instantaneamente.
SELECT 
    p.partition_number AS NumeroParticao,
    p.rows AS QuantidadeLinhas,
    prv.value AS LimiteValorSuperior
FROM sys.partitions p
JOIN sys.indexes i
    ON i.object_id = p.object_id
   AND i.index_id = p.index_id
JOIN sys.partition_schemes ps
    ON ps.data_space_id = i.data_space_id
JOIN sys.partition_functions pf
    ON pf.function_id = ps.function_id
LEFT JOIN sys.partition_range_values prv 
    ON prv.function_id = pf.function_id 
    AND prv.boundary_id = p.partition_number
WHERE pf.name = 'PF_OrdersByYear' AND p.index_id <= 1
ORDER BY p.partition_number;
GO


-- =================================================================================
-- PARTE 6: CENÁRIOS PRÁTICOS ADICIONAIS (RANGE LEFT VS RIGHT E ÍNDICES NÃO-ALINHADOS)
-- =================================================================================

-- 1. Testando a diferença de partição para a data exata limite '2025-01-01'.
-- Em RANGE RIGHT, o limite pertence à partição à direita; em RANGE LEFT, à da esquerda.
-- Após SPLIT/MERGE, os números físicos de partição podem mudar. Valide com $PARTITION, não por suposição.
SELECT 
    '2025-01-01' AS DataLimite,
    $PARTITION.PF_OrdersByYear('2025-01-01') AS ParticaoRangeRight;
GO

-- 2. Demonstração de Bloqueio no SWITCH por causa de Índice NÃO-ALINHADO
-- Criar um índice não-alinhado (salvo no filegroup [PRIMARY] sem referenciar a chave de partição)
CREATE NONCLUSTERED INDEX IX_OrdersPartitioned_NonAligned
ON lab.OrdersPartitioned(TotalAmount)
ON [PRIMARY]; -- NÃO ALINHADO!
GO

-- Tentativa de SWITCH com índice não alinhado (Deve falhar com erro 7733)
BEGIN TRY
    ALTER TABLE lab.OrdersPartitioned
    SWITCH PARTITION 3 TO lab.OrdersPartitionedHistory PARTITION 3;
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO SWITCH COM ÍNDICE NÃO ALINHADO: ' + ERROR_MESSAGE();
    -- Mensagem: "ALTER TABLE SWITCH statement failed because index... is not partitioned..."
END CATCH;
GO

-- Solução: Remover o índice não-alinhado ou recriá-lo como alinhado
DROP INDEX IX_OrdersPartitioned_NonAligned ON lab.OrdersPartitioned;
GO

-- 3. Matriz de decisão para retenção. SWITCH exige destino vazio e estruturalmente compatível; TRUNCATE PARTITION não permite arquivar os dados.
SELECT N'DELETE' AS Operacao, N'Remove linhas selecionadas dentro da partição' AS QuandoUsar, N'Totalmente registrado; pode custar caro em lotes grandes' AS TradeOff
UNION ALL SELECT N'TRUNCATE PARTITION', N'Descarta todas as linhas de uma partição conhecida', N'Rápido e minimamente registrado; não arquiva as linhas'
UNION ALL SELECT N'SWITCH PARTITION', N'Move uma partição alinhada inteira para arquivo', N'Destino deve existir, estar vazio e atender aos requisitos de SWITCH';
GO


-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/01-database-objects/05-partitioning.md
-- =================================================================================================
-- =================================================================================================
-- REFERÊNCIAS OFICIAIS DO MICROSOFT LEARN
-- =================================================================================================
-- Funções e esquemas de partição, além de índices alinhados:
-- https://learn.microsoft.com/pt-br/sql/relational-databases/partitions/create-partitioned-tables-and-indexes?view=sql-server-ver17
-- Função de metadados $PARTITION:
-- https://learn.microsoft.com/pt-br/sql/t-sql/functions/partition-transact-sql?view=sql-server-ver17
-- Operações SPLIT e MERGE:
-- https://learn.microsoft.com/pt-br/sql/t-sql/statements/alter-partition-function-transact-sql?view=sql-server-ver17
-- Troca de partições (partition switching):
-- https://learn.microsoft.com/pt-br/sql/relational-databases/partitions/switching-partitions?view=sql-server-ver17
