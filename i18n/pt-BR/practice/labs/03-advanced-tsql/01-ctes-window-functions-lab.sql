-- =================================================================================
-- DP-800 - LAB PRÁTICO: CTEs (RECURSIVAS, MATERIALIZAÇÃO) E WINDOW FUNCTIONS
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o uso avançado de CTEs e Funções de Janela no SQL Server:
--   1. CTEs Simples, Múltiplas e CTEs Recursivas com controle MAXRECURSION
--   2. Não-Materialização de CTEs vs Tabelas Temporárias físicas (#temp)
--   3. Funções de Ranking: ROW_NUMBER, RANK, DENSE_RANK e NTILE (Empates e Lacunas)
--   4. Enquadramento de Janela (Window Framing): ROWS vs RANGE e Saldo Acumulado
--   5. Funções de Deslocamento: LAG, LEAD, FIRST_VALUE e a Armadilha do LAST_VALUE
--   6. Cenários Práticos de Projeto (Deduplicação de Registros e Análise de Percentil)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.OrgChart;
DROP TABLE IF EXISTS lab.SalesData;
DROP TABLE IF EXISTS lab.CustomerEvents;
GO

-- Estruturas de Tabelas para Teste
CREATE TABLE lab.OrgChart (
    EmployeeID INT PRIMARY KEY,
    EmployeeName NVARCHAR(100) NOT NULL,
    ManagerID INT NULL
);

CREATE TABLE lab.SalesData (
    SaleID INT IDENTITY(1,1) PRIMARY KEY,
    SalesPersonID INT NOT NULL,
    SaleDate DATE NOT NULL,
    Amount DECIMAL(18,2) NOT NULL
);

CREATE TABLE lab.CustomerEvents (
    EventID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    EventName NVARCHAR(50) NOT NULL,
    EventDate DATETIME2 NOT NULL
);
GO


-- =================================================================================
-- PARTE 1: CTES RECURSIVAS E CONTROLE DE RECURSÃO (MAXRECURSION)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - RECURSIVE CTE: Estrutura composta por um Membro Âncora (Anchor) unhado via `UNION ALL`
--     a um Membro Recursivo que referencia a própria CTE até que a condição de parada seja atingida.
--   - MAXRECURSION: Por padrão, o SQL Server limita a recursão a 100 níveis para evitar loops infinitos.
--     Utilize `OPTION (MAXRECURSION n)` para alterar (onde 0 = sem limite, usar com extremo cuidado).

-- 1. Popular dados de hierarquia organizacional
INSERT INTO lab.OrgChart VALUES 
(1, 'CEO / Presidente', NULL),
(2, 'VP de Vendas', 1),
(3, 'Gerente de Vendas Região A', 2),
(4, 'Vendedor Senior 1', 3),
(5, 'Vendedor Junior 2', 3);
GO

-- 2. Consulta com CTE Recursiva para mapear níveis de hierarquia
WITH EmployeeHierarchy AS (
    -- Membro Âncora: topo da pirâmide (sem gerente)
    SELECT EmployeeID, EmployeeName, ManagerID, 0 AS Level
    FROM lab.OrgChart
    WHERE ManagerID IS NULL

    UNION ALL

    -- Membro Recursivo: funcionários subordinados
    SELECT e.EmployeeID, e.EmployeeName, e.ManagerID, h.Level + 1
    FROM lab.OrgChart e
    JOIN EmployeeHierarchy h ON e.ManagerID = h.EmployeeID
)
SELECT EmployeeID, EmployeeName, Level, REPLICATE('--- ', Level) + EmployeeName AS HierarchyTree
FROM EmployeeHierarchy
ORDER BY Level, EmployeeName;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- Teste de Estouro de Recursão (MAXRECURSION Excedido):
-- Gerando uma sequência infinita/longa para forçar o erro 530 do SQL Server.
BEGIN TRY
    ;WITH InfiniteSeq AS (
        SELECT 1 AS N
        UNION ALL
        SELECT N + 1 FROM InfiniteSeq WHERE N < 200
    )
    SELECT * FROM InfiniteSeq; -- Falhará pois 200 > 100 (Limite Padrão)
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO MAXRECURSION: ' + ERROR_MESSAGE();
    -- Erro: "The statement terminated because the maximum recursion 100 was exhausted..."
END CATCH;
GO


-- =================================================================================
-- PARTE 2: RANKING FUNCTIONS (ROW_NUMBER, RANK, DENSE_RANK, NTILE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - ROW_NUMBER(): Gera uma sequência numérica única estrita (sem empates, desempate arbitrário).
--   - RANK(): Gera rankings com empates. Deixa lacunas no ranking seguinte (ex: 1, 1, 3).
--   - DENSE_RANK(): Gera rankings com empates. NÃO DEIXA lacunas no ranking seguinte (ex: 1, 1, 2).
--   - NTILE(n): Divide o conjunto de resultados em `n` baldes (quartis, decis, etc.) com tamanhos iguais.

INSERT INTO lab.SalesData (SalesPersonID, SaleDate, Amount) VALUES 
(101, '2025-01-01', 500.00),
(102, '2025-01-01', 500.00), -- Empate de valor
(103, '2025-01-01', 300.00),
(104, '2025-01-01', 200.00);
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- Comparativo em Paralelo das Funções de Ranking
SELECT 
    SalesPersonID,
    Amount,
    ROW_NUMBER() OVER (ORDER BY Amount DESC) AS RowNum,
    RANK()       OVER (ORDER BY Amount DESC) AS RankWithGaps,    -- 1, 1, 3
    DENSE_RANK() OVER (ORDER BY Amount DESC) AS DenseRankNoGaps, -- 1, 1, 2
    NTILE(2)     OVER (ORDER BY Amount DESC) AS QuartileBucket
FROM lab.SalesData;
GO


-- =================================================================================
-- PARTE 3: WINDOW FRAMING (ROWS VS RANGE E SALDO ACUMULADO)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - RANGE (Padrão): Enquadramento lógico. Trata linhas com valores idênticos no ORDER BY como um único bloco.
--   - ROWS: Enquadramento físico estrito. Avalia fisicamente linha a linha.
--   - SALDO ACUMULADO (Running Total): Requer a cláusula `ROWS UNBOUNDED PRECEDING` para performance e precisão.

SELECT 
    SaleID,
    SalesPersonID,
    SaleDate,
    Amount,
    -- Saldo Acumulado por Vendedor
    SUM(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate, SaleID
        ROWS UNBOUNDED PRECEDING
    ) AS RunningTotal,
    -- Média Móvel (Linha Atual + 1 Linha Anterior)
    AVG(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate, SaleID
        ROWS BETWEEN 1 PRECEDING AND CURRENT ROW
    ) AS MovingAvg2
FROM lab.SalesData;
GO


-- =================================================================================
-- PARTE 4: OFFSET FUNCTIONS (LAG, LEAD, FIRST_VALUE E A ARMADILHA DO LAST_VALUE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - LAG / LEAD: Acessam o valor de linhas anteriores ou posteriores sem necessidade de auto-join.
--   - FIRST_VALUE: Retorna o primeiro valor do enquadramento da janela.
--   - LAST_VALUE: Retorna o último valor do enquadramento. 
--   - ARMADILHA DO LAST_VALUE: O enquadramento padrão para no registro atual (`CURRENT ROW`).
--     Sem declarar `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`, `LAST_VALUE` retornará
--     o próprio valor da linha atual em vez do verdadeiro último registro da partição!

-- -- [PONTO DE ATENÇÃO DP-800]
SELECT 
    SaleID,
    SalesPersonID,
    Amount,
    LAG(Amount, 1, 0) OVER (PARTITION BY SalesPersonID ORDER BY SaleID) AS ValorAnterior,
    LEAD(Amount, 1, 0) OVER (PARTITION BY SalesPersonID ORDER BY SaleID) AS ProximoValor,
    
    -- Errado/Enganoso: Retorna o valor da própria linha por causa do enquadramento padrão
    LAST_VALUE(Amount) OVER (PARTITION BY SalesPersonID ORDER BY SaleID) AS LastValueErrado,
    
    -- Correto: Declaração explícita da janela total da partição
    LAST_VALUE(Amount) OVER (
        PARTITION BY SalesPersonID 
        ORDER BY SaleID
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS LastValueCorreto
FROM lab.SalesData;
GO


-- =================================================================================
-- PARTE 5: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Deduplicação de Registros de Eventos mantendo apenas a última atualização
-- Técnica padrão de produção utilizando ROW_NUMBER() em uma CTE para filtrar `rn = 1`.

INSERT INTO lab.CustomerEvents (CustomerID, EventName, EventDate) VALUES 
(1001, 'Login', '2025-01-01 10:00:00'),
(1001, 'UpdateProfile', '2025-01-01 10:05:00'), -- Evento mais recente
(1002, 'Login', '2025-01-01 11:00:00');
GO

WITH RankedEvents AS (
    SELECT 
        EventID,
        CustomerID,
        EventName,
        EventDate,
        ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY EventDate DESC) AS RowNum
    FROM lab.CustomerEvents
)
SELECT EventID, CustomerID, EventName, EventDate
FROM RankedEvents
WHERE RowNum = 1; -- Mantém apenas o registro mais recente por cliente
GO
