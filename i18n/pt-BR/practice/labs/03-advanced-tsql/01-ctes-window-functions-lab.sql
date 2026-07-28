-- =================================================================================
-- DP-800 - LAB PRÁTICO: CTEs (RECURSIVAS / MATERIALIZAÇÃO) E WINDOW FUNCTIONS
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script cobre 100% da teoria MS Learn DP-800 sobre CTEs & Window Functions.
-- ÍNDICE COMPLETO DAS SEÇÕES:
--   Parte 1    → CTE Recursiva + MAXRECURSION (estouro de limites, TRY/CATCH)
--   Parte 1.5  → CTEs Múltiplas (WITH A, B, C ... sem redefinir)
--   Parte 1.6  → Não-Materialização CTE vs #temp (prova com NEWID não-determinístico)
--   Parte 2    → Funções de Ranking: ROW_NUMBER / RANK / DENSE_RANK / NTILE
--   Parte 3    → Window Framing: ROWS vs RANGE (Running Total com empates em data)
--   Parte 4    → Offset Functions: LAG, LEAD, FIRST_VALUE e a ARMADILHA LAST_VALUE
--   Extra 4.1  → RANGE vs ROWS no LAST_VALUE (linhas empatadas em Amount)
--   Parte 4.2  → 🧠 lab.sp_render_tree: função genérica para renderizar
--                 QUALQUER hierarquia de adjacency-list em Markdown / ASCII Tree
--                 (SQL dinâmico SEGURO com QUOTENAME + detecção automática de ciclo)
--   Parte 5    → Cenários de Produção:
--      C1. Deduplicação por grupo (ROW_NUMBER + CTE WHERE rn = 1)
--      C2. Percentis: PERCENTILE_CONT/DISC + CUME_DIST + PERCENT_RANK
--      C3. HIERARCHYID nativo: comparação com Adjacency List + IsDescendantOf
--      C4. Detecção de GAPS: LAG + predicado sobre IDs e datas
--      C5. Top-N por Grupo: ROW_NUMBER vs RANK no corte
--   Final      → CHECKLIST DP-800 de tópicos cobertos + links MS Learn
-- =================================================================================

USE AdventureWorks2025;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'lab')
    EXEC(N'CREATE SCHEMA lab AUTHORIZATION dbo;');
GO

-- Limpeza preventiva
DROP PROCEDURE IF EXISTS lab.sp_render_tree;
DROP TABLE IF EXISTS lab.OrgChartHierarchyid;
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
-- PARTE 1.5: CTES MÚLTIPLAS (DEFINIÇÕES SEPARADAS POR VÍRGULA)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - Várias CTEs podem ser definidas em um único `WITH` separadas por vírgula.
--   - Uma CTE posterior pode REFERENCIAR uma CTE anterior (não vice-versa: sem forward refs).
--   - Sintaxe limpa para "quebrar" a lógica em estágios nomeados em vez de subqueries aninhadas.
--
-- [PONTO DE ATENÇÃO DP-800] Pergunta clássica: "Quantas vezes o nome de uma CTE é
--   avaliado se referenciado N vezes na query?" RESPOSTA: N vezes.
--   A CTE é uma MACRO expandida no plano de execução, NÃO uma tabela temporária materializada.

WITH
    -- CTE 1: Vendas brutas por vendedor
    VendasPorVendedor AS (
        SELECT SalesPersonID, SUM(Amount) AS TotalVendas
        FROM lab.SalesData
        GROUP BY SalesPersonID
    ),
    -- CTE 2: Métricas globais (referencia a CTE anterior indiretamente via agregação total)
    MetricasGlobais AS (
        SELECT
            SUM(TotalVendas) AS TotalGeral,
            AVG(TotalVendas * 1.0) AS MediaPorVendedor
        FROM VendasPorVendedor
    )
-- Query principal combina as duas CTEs sem JOIN adicional
SELECT
    v.SalesPersonID,
    v.TotalVendas,
    g.TotalGeral,
    g.MediaPorVendedor,
    -- % de participação de cada vendedor no total
    CAST(v.TotalVendas * 100.0 / NULLIF(g.TotalGeral, 0) AS DECIMAL(6,2)) AS PercentualDoTotal
FROM VendasPorVendedor v
CROSS JOIN MetricasGlobais g
ORDER BY v.TotalVendas DESC;
GO


-- =================================================================================
-- PARTE 1.6: NÃO-MATERIALIZAÇÃO DE CTE vs #TEMP (PROVA PRÁTICA)
-- =================================================================================
-- CONCEITO CRÍTICO MS Learn:
--   - CTE: Resultado NÃO é persistido. Se a CTE aparece 2x na query final, a sua
--     lógica subjacente é EXECUTADA 2x (risco de inconsistência em dados concorrentes
--     e perda de performance).
--   - #temp (tabela temporária local): Materializa linhas em tempdb. Lê 1x, usa Nx.
--
--   Demonstração abaixo: usamos NEWID() não-determinístico para provar que a CTE é
--   recalculada a cada referência. Se a CTE fosse materializada, o mesmo GUID apareceria
--   em ambas as colunas.

-- ===== (A) CTE referenciada DUAS VEZES → NEWID() diferente em cada coluna =====
WITH CteComGuid AS (
    SELECT SalesPersonID, NEWID() AS GuidNaoDeterministico
    FROM lab.SalesData
    WHERE SalesPersonID = 101
)
SELECT
    a.SalesPersonID,
    a.GuidNaoDeterministico AS GuidDaPrimeiraReferencia,
    b.GuidNaoDeterministico AS GuidDaSegundaReferencia,
    MesmoGuid = CASE WHEN a.GuidNaoDeterministico = b.GuidNaoDeterministico
                     THEN 'SIM (materializado)' ELSE 'NAO (executado 2x)' END
FROM CteComGuid a
INNER JOIN CteComGuid b ON a.SalesPersonID = b.SalesPersonID;
-- 👇 Resultado esperado: MesmoGuid = "NAO" — prova que a CTE rodou duas vezes!
GO

-- ===== (B) #TEMP referenciada DUAS VEZES → NEWID() igual em ambas as colunas =====
DROP TABLE IF EXISTS #TempComGuid;
CREATE TABLE #TempComGuid (SalesPersonID INT, GuidNaoDeterministico UNIQUEIDENTIFIER);
INSERT INTO #TempComGuid (SalesPersonID, GuidNaoDeterministico)
SELECT SalesPersonID, NEWID()
FROM lab.SalesData
WHERE SalesPersonID = 101;

SELECT
    a.SalesPersonID,
    a.GuidNaoDeterministico AS GuidDaPrimeiraReferencia,
    b.GuidNaoDeterministico AS GuidDaSegundaReferencia,
    MesmoGuid = CASE WHEN a.GuidNaoDeterministico = b.GuidNaoDeterministico
                     THEN 'SIM (materializado)' ELSE 'NAO (executado 2x)' END
FROM #TempComGuid a
INNER JOIN #TempComGuid b ON a.SalesPersonID = b.SalesPersonID;
-- 👇 Resultado esperado: MesmoGuid = "SIM" — a #temp é calculada UMA vez e reutilizada.
DROP TABLE IF EXISTS #TempComGuid;
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
-- Vendedor 101: 3 vendas (partição com múltiplas linhas para demonstrar framing)
(101, '2025-01-05', 500.00),
(101, '2025-01-10', 800.00),
(101, '2025-01-15', 1200.00),
-- Vendedor 102: 2 vendas (empate proposital de valor na Parte 2 - Ranking)
(102, '2025-01-03', 500.00),
(102, '2025-01-08', 500.00),
-- Vendedor 103: 3 vendas, DUAS NO MESMO DIA (2025-01-12) → empate em SaleDate
-- Essencial para demonstrar diferença entre RANGE (bloco lógico) e ROWS (físico)
(103, '2025-01-02', 300.00),
(103, '2025-01-12', 250.00),
(103, '2025-01-12', 200.00),
-- Vendedor 104: 2 vendas
(104, '2025-01-01', 200.00),
(104, '2025-01-20', 950.00);
GO


-- =================================================================================
-- 🔑 AULA TEÓRICA: O QUE REALMENTE FAZ O "PARTITION BY" DENTRO DE OVER()?
-- =================================================================================
-- Esta é a explicação que cristaliza o que o MS Learn DP-800 não deixa explícito. 👇
--
-- Imagine que a cláusula OVER() tem 3 "botões de configuração" EXECUTADOS NESSA ORDEM:
--
--    1. PARTITION BY  →  CORTA O DATASET EM GRUPOS SEPARADOS
--    2. ORDER BY     →  ORDENA CADA GRUPO (OBRIGATÓRIO PARA FRAMING E OFFSET)
--    3. ROWS/RANGE   →  PEGA UMA "JANELINHA" DESLIZANTE DENTRO DO GRUPO ORDENADO
--
-- A regra mais importante:
--    ⚠️  "OVER()" SEM NENHUM PARÂMETRO  =  UMA ÚNICA PARTIÇÃO = TODO O MUNDO JUNTO
--    ⚠️  "OVER(PARTITION BY col)"        =  N PARTIÇÕES INDEPENDENTES, UMA POR VALOR
--
-- Vamos calcular NA MÃO o efeito de PARTITION BY sobre a função LAG()
-- usando este mini-subconjunto do nosso lab.SalesData (vendedores 101 e 102):
--
--       |Linha | Vendedor | Amount |
--       |------|----------|--------|
--       | L1   | 101      | 500    |
--       | L2   | 101      | 800    |
--       | L3   | 101      | 1200   |
--       | L4   | 102      | 500    |
--       | L5   | 102      | 500    |
--
--   CASO A - FUNÇÃO SEM PARTITION BY:  OVER(ORDER BY Vendedor, SaleID)
--   -----------------------------------------------------------------
--   TUDO é UMA partição SÓ. A contagem de LAG/LINHA ANTERIOR atravessa vendedores.
--
--       Linha L1 → LAG(Amount) = NULL (não tem linha anterior na partição)
--       Linha L2 → LAG(Amount) = 500  (vem da L1 — mesmo vendedor)
--       Linha L3 → LAG(Amount) = 800  (vem da L2 — mesmo vendedor)
--       Linha L4 → LAG(Amount) = 1200 (vem da L3 — VENDEDOR DIFERENTE! 🚨BUG)
--       Linha L5 → LAG(Amount) = 500  (vem da L4)
--
--       Resultado: Vendedor 102 pega o Amount do vendedor 101 como "anterior"!
--       ERRADO para análise por vendedor, mas útil para ranking global.
--
--   CASO B - FUNÇÃO COM PARTITION BY SalesPersonID:
--   -----------------------------------------------------------------
--   O SQL cria 2 partições independentes: {L1,L2,L3} e {L4,L5}.
--   Cada uma começa com contagem do zero, como se a outra partição NÃO EXISTISSE.
--
--       Partição 101:
--          L1 → LAG = NULL (primeiro da partição 101)
--          L2 → LAG = 500 (vem de L1, dentro da mesma partição)
--          L3 → LAG = 800 (vem de L2, dentro da mesma partição)
--
--       Partição 102:
--          L4 → LAG = NULL (primeiro da partição 102 — NOVAMENTE NULL!)
--          L5 → LAG = 500 (vem de L4, dentro da mesma partição)
--
--       Resultado: Cada vendedor vê apenas suas próprias linhas.
--       Isso é 99% das vezes o que você quer em relatórios de performance!
--
-- E o LAST_VALUE então? Sofre DOBRO:
--   • Em PARTIÇÃO ÚNICA (sem partition), "último" = última linha da tabela inteira
--   • Em MÚLTIPLAS PARTIÇÕES, "último" = última linha DENTRO DO GRUPO do vendedor
--
-- Em todos os casos, sem o frame `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`,
-- LAST_VALUE ainda vai retornar a própria linha (a armadilha do frame default).
-- =================================================================================
-- NAS SEÇÕES ABAIXO, TODAS AS CONSULTAS VÊM EM DOIS SABORES:
--    LAB A  →  MESMO DATASET MAS SEM PARTITION BY (tudo numa partição)
--    LAB B  →  MESMO DATASET COM PARTITION BY SalesPersonID (por vendedor)
-- Compare lado a lado as colunas e veja a diferença na prática!
-- =================================================================================


-- =================================================================================
--  LAB A vs  LAB B — FUNÇÕES DE RANKING (Parte 2)
-- =================================================================================
-- Coloquei TODAS as 8 colunas num mesmo SELECT para você comparar visualmente
-- sem precisar alternar entre janelas.
--
--  LAB A - SEM PARTITION BY: Ranking GLOBAL (todas as 10 vendas competem entre si)
--  LAB B - COM PARTITION BY SalesPersonID: Ranking DENTRO DE CADA VENDEDOR
--          (cada vendedor começa com rank 1 para a sua maior venda própria)
SELECT
    SaleID,
    SalesPersonID,
    Amount,

    -- =========================================================================
    --  LAB A — Ranking GLOBAL (dataset inteiro = 1 partição)
    -- =========================================================================
    ROW_NUMBER() OVER (ORDER BY Amount DESC)          AS A_RN_Global,
    RANK()       OVER (ORDER BY Amount DESC)          AS A_RK_Global,  -- veja o 1,1,3
    DENSE_RANK() OVER (ORDER BY Amount DESC)          AS A_DR_Global,  -- veja o 1,1,2
    NTILE(2)     OVER (ORDER BY Amount DESC)          AS A_NTile2_Global,

    -- =========================================================================
    --  LAB B — Ranking POR VENDEDOR (cada vendedor = partição independente)
    -- =========================================================================
    ROW_NUMBER() OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS B_RN_PorVendedor,
    RANK()       OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS B_RK_PorVendedor,
    DENSE_RANK() OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS B_DR_PorVendedor,
    NTILE(2)     OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS B_NTile2_PorVendedor

FROM lab.SalesData
ORDER BY SalesPersonID, Amount DESC, SaleID;
-- 👉 OBSERVAÇÕES didáticas:
--    • Vendedor 101 (R$500, 800, 1200): no LAB A ele aparece como posições 5,3,1 (global)
--      mas no LAB B ele é 3,2,1 (porque só compete com ele mesmo)
--    • Vendedor 102 tem Amount EMPATADO em R$500 (2 linhas). No LAB B, DENSE_RANK retorna
--      1,1 sem lacuna, e RANK retorna 1,1 sem lacuna (porque só tem 2 linhas, nenhuma outra
--      para criar lacuna — observe em dados maiores o efeito do RANK pular do 1 para o 3).
GO


-- =================================================================================
--  LAB A vs  LAB B — WINDOW FRAMING & RUNNING TOTAL (Parte 3)
-- =================================================================================
--
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - RANGE (Padrão quando ORDER BY é usado sem frame explícito):
--         Enquadramento LÓGICO. Trata TODAS as linhas empatadas no ORDER BY como um
--         único bloco — "CURRENT ROW" no RANGE = todas as linhas com mesmo valor.
--   - ROWS: Enquadramento FÍSICO estrito. Avalia fisicamente linha a linha, sem
--         agrupamento por valor.
--   - Frame DEFAULT completo (MS Learn oficial):
--         `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`
--
-- [PONTO DE ATENÇÃO DP-800] Para SALDO ACUMULADO (Running Total):
--   - Use ROWS UNBOUNDED PRECEDING para performance (otimização de spool interno)
--     e previsibilidade.
--   - RANGE pode dar RESULTADO DIFERENTE quando existirem valores empatados no ORDER BY
--     (mesma data, mesmo valor etc.) e é MAIS LENTO em grandes volumes.

SELECT
    SaleID,
    SalesPersonID,
    SaleDate,
    Amount,

    -- =========================================================================
    --  LAB A — SEM PARTITION BY (GLOBAL: dataset todo = 1 partição)
    --           Running total começa em 2/jan e soma vendas de TODOS os vendedores
    --           até 20/jan. A primeira linha é sempre o primeiro valor da tabela
    --           ordenada e a última linha é igual ao SUM(Amount) total de TUDO.
    -- =========================================================================
    SUM(Amount) OVER (ORDER BY SaleDate, SaleID ROWS UNBOUNDED PRECEDING)
        AS A_RT_Global_ROWS,
    SUM(Amount) OVER (ORDER BY SaleDate, SaleID RANGE UNBOUNDED PRECEDING)
        AS A_RT_Global_RANGE,  -- atenção para o bloco lógico em 12/jan (vendedor 103)

    -- Média móvel global (2 últimas linhas, sem separar por vendedor)
    AVG(Amount) OVER (ORDER BY SaleDate, SaleID ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)
        AS A_MA2_Global,

    -- =========================================================================
    --  LAB B — COM PARTITION BY SalesPersonID (POR VENDEDOR)
    --           Running total ZERA para cada vendedor novo. O maior valor aqui
    --           será o total de cada vendedor, não da empresa toda.
    -- =========================================================================
    -- (B1) Running Total com ROWS (físico): conta linha a linha
    --      Vendedor 103 terá valores 300 → 550 → 750 (acumula passo-a-passo)
    SUM(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate, SaleID
        ROWS UNBOUNDED PRECEDING
    ) AS B_RT_PorVend_ROWS_Fisico,

    -- (B2) Running Total com RANGE (lógico): trata o dia 12/jan como bloco único
    --      Vendedor 103 terá valores 300 → 750 → 750 (ambas as linhas do dia 12
    --      recebem o TOTAL do bloco de 12/jan de uma vez!)
    SUM(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate
        RANGE UNBOUNDED PRECEDING
    ) AS B_RT_PorVend_RANGE_Logico,

    -- (B3) Running Total com frame DEFAULT IMPLÍCITO (sem escrever ROWS/RANGE)
    --      Resultado IDÊNTICO ao (B2) RANGE — prova que o padrão do SQL Server
    --      é RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    SUM(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate
    ) AS B_RT_PorVend_DefaultImplicito,

    -- Média móvel por vendedor (2 últimas linhas DO MESMO VENDEDOR)
    AVG(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate, SaleID
        ROWS BETWEEN 1 PRECEDING AND CURRENT ROW
    ) AS B_MA2_PorVend

FROM lab.SalesData
ORDER BY SaleDate, SaleID;
-- 👉 OBSERVAÇÕES didáticas cruciais:
--    • Compare a linha do vendedor 103 em 12/jan (SaleID 6 e 7):
--        - A_RT_Global_RANGE pulou 2 de uma vez (bloco RANGE 12/jan inteiro)
--        - B_RT_PorVend_RANGE = 750 em AMBAS as linhas 6 e 7 (bloco por vendedor)
--    • Na primeira linha do vendedor 102 (SaleID 4): A_MA2_Global traz a média
--      com o vendedor 104 (venda anterior do dataset ordenado), enquanto
--      B_MA2_PorVend traz APENAS o valor da própria linha 102 (porque é a
--      primeira linha da partição 102, sem linha anterior para média).
GO


-- =================================================================================
--  LAB A vs  LAB B — OFFSET FUNCTIONS + A ARMADILHA DO LAST_VALUE (Parte 4)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE (alinhados com MS Learn DP-800):
--   - LAG / LEAD: Acessam o valor de linhas anteriores ou posteriores sem auto-join.
--     IMPORTANTE: LAG e LEAD NÃO utilizam a cláusula ROWS/RANGE (framing). O deslocamento
--     é controlado APENAS pelo parâmetro `offset`. Frame clauses são IGNORADAS para essas
--     funções, por isso elas NÃO sofrem da mesma "armadilha" que LAST_VALUE.
--
--   - FIRST_VALUE / LAST_VALUE: Retornam o primeiro/último valor do ENQUADRAMENTO (frame),
--     NÃO da partição inteira por padrão. O MS Learn define explicitamente o frame padrão como:
--         `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`
--     Ou seja: a janela começa no início da partição e TERMINA NA LINHA ATUAL (ou em todas
--     as linhas empatadas com a atual, no modo RANGE lógico).
--
--   - ARMADILHA DO LAST_VALUE (pergunta frequente na prova DP-800):
--     Sem declarar `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`, LAST_VALUE
--     enxerga apenas até a linha atual → retorna o VALOR DA PRÓPRIA LINHA (comportamento
--     sem utilidade para "último da partição"). FIRST_VALUE não aparenta ter esse problema
--     porque o início do frame default já é o primeiro da partição.

-- -- [PONTO DE ATENÇÃO DP-800] DEMONSTRAÇÃO COMPLETA — MESMO SELECT DUPLO
-- Compare lado a lado as colunas do LAB A (sem partition) vs LAB B (com partition)
-- e veja a armadilha do LAST_VALUE se repetir em AMBOS os cenários.
SELECT 
    SaleID,
    SalesPersonID,
    SaleDate,
    Amount,

    -- =====================================================================
    --  LAB A — SEM PARTITION BY (TABELA INTEIRA COMO UMA SÓ PARTIÇÃO)
    -- =====================================================================
    LAG(Amount, 1, 0)  OVER (ORDER BY SaleDate, SaleID)        AS A_LAG_Global,
    LEAD(Amount, 1, 0) OVER (ORDER BY SaleDate, SaleID)        AS A_LEAD_Global,

    FIRST_VALUE(Amount) OVER (ORDER BY SaleDate, SaleID)       AS A_FirstV_Global,
    -- Armadilha no GLOBAL: "último" seria a última linha da tabela inteira (950),
    -- mas sem frame explícito ele retorna a própria linha:
    LAST_VALUE(Amount)  OVER (ORDER BY SaleDate, SaleID)       AS A_LV_Global_Default, -- bug!
    LAST_VALUE(Amount)  OVER (
        ORDER BY SaleDate, SaleID
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                                                          AS A_LV_Global_Correto, -- 950 em todas!

    -- =====================================================================
    --  LAB B — COM PARTITION BY SalesPersonID (POR VENDEDOR)
    -- =====================================================================
    LAG(Amount, 1, 0)  OVER (PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID) AS B_LAG_PorVend,
    LEAD(Amount, 1, 0) OVER (PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID) AS B_LEAD_PorVend,

    FIRST_VALUE(Amount) OVER (PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID)
                                                                                  AS B_FirstV_PorVend,
    -- Armadilha no POR VENDEDOR: "último" seria a última venda DO VENDEDOR,
    -- mas sem frame ele retorna a própria linha:
    LAST_VALUE(Amount) OVER (
        PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID
    )                                                          AS B_LV_PorVend_Default, -- bug!
    LAST_VALUE(Amount) OVER (
        PARTITION BY SalesPersonID ORDER BY SaleDate, SaleID
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                                                          AS B_LV_PorVend_Correto

FROM lab.SalesData
ORDER BY SaleDate, SaleID;
GO
-- 👉 OBSERVAÇÕES didáticas cruciais para DP-800:
--    • A_LAG_Global: 1ª linha é 0 (default), 2ª linha pega o valor da 1ª LINHA DA TABELA
--      (que é do VENDEDOR 104, não do mesmo vendedor!). Já B_LAG_PorVend re-zera para 0
--      SEMPRE na primeira venda de cada novo vendedor.
--    • A_LV_Global_Correto (última coluna LAB A): todas as linhas exibem 950 (a última
--      venda da tabela inteira — 20/jan do vendedor 104).
--    • B_LV_PorVend_Correto (última coluna LAB B): vendedor 101 → sempre 1200,
--      vendedor 103 → sempre 750 (total do seu grupo, não da tabela).
--    • EM AMBOS os "_Default" o LAST_VALUE retorna a própria linha Amount!
--      A armadilha é GLOBAL (independe de PARTITION BY) — depende apenas do frame.


-- --------------------------------------------------------------------------------
-- EXTRA DIDÁTICO 4.1 - RANGE vs ROWS em Ação no LAB B (por vendedor)
--                      aproveitando SalesPersonID=102 com Amount EMPATADO em 500.
-- CONFORME MS Learn: RANGE trata todos os "empatados" no ORDER BY como um bloco lógico.
-- Em ROWS, cada linha física é contada individualmente.
-- --------------------------------------------------------------------------------
SELECT
    SaleID,
    SalesPersonID,
    SaleDate,
    Amount,

    -- LAST_VALUE com RANGE: quando o Amount empatar, o "CURRENT ROW" do RANGE
    -- inclui TODAS as linhas com aquele valor, então o último do bloco é retornado.
    LAST_VALUE(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY Amount
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS LV_Range_LogicoEmpates,

    -- LAST_VALUE com ROWS: mesmo ORDER BY com empates, cada linha física é
    -- contada separadamente → a linha 1 retorna ela mesma, a linha 2 retorna ela mesma
    LAST_VALUE(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY Amount
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS LV_Rows_FisicoLinhaALinha

FROM lab.SalesData
WHERE SalesPersonID IN (101, 102)  -- 101 tem valores crescentes, 102 tem empate
ORDER BY SalesPersonID, Amount, SaleID;
GO


-- =================================================================================
-- PARTE 4.2: FUNÇÃO GENÉRICA DE RENDERIZAÇÃO DE HIERARQUIA EM MARKDOWN
-- =================================================================================
-- OBJETIVO: Criar uma procedure reutilizável que recebe NOME DE TABELA + COLUNAS
--   de relacionamento pai/filho e retorna uma única coluna com a árvore pronta
--   para colar em README.md, cadernos, documentação etc.
--
-- SINTAXE DE USO (como pedido):
--   EXEC lab.sp_render_tree
--        @table_name = 'lab.OrgChart',
--        @col_dad    = 'ManagerID',
--        @col_son    = 'EmployeeID',
--        @col_label  = 'EmployeeName',            -- opcional
--        @tree_style = 'md';                      -- 'md' (markdown) | 'ascii'
--
-- SEGURANÇA (alinhada com MS Learn Dynamic SQL):
--   ✅ Usa OBJECT_ID() para validar a tabela antes de montar SQL dinâmico
--   ✅ Usa sys.columns para validar colunas de pai/filho/rótulo
--   ✅ TODOS os identificadores são quotados com QUOTENAME() (injeção = impossível)
--   ✅ Dados passados como parâmetros são injetados via sp_executesql tipados
--
-- CARACTERÍSTICAS:
--   🧠 Detecção de Ciclo: cada nó carrega um "breadcrumb" dos IDs visitados.
--      Se o pai atual já apareceu no caminho, a recursão pára e marca is_cycle=1.
--   🧠 Renderização ASCII (estilo tree do linux): usa │, ├─, └─ com precisão de
--      "último irmão" → visualização profissional sem monoespaço quebrado.
--   🧠 @root_id opcional: permite renderizar APENAS uma sub-árvore (ex: só a região A).
-- =================================================================================

CREATE OR ALTER PROCEDURE lab.sp_render_tree
    @table_name SYSNAME,           -- tabela (1 ou 2 partes: 'OrgChart' ou 'lab.OrgChart')
    @col_dad    SYSNAME,           -- coluna FK de self-reference (ex: ManagerID → NULL = raiz)
    @col_son    SYSNAME,           -- coluna PK/id do nó (ex: EmployeeID)
    @col_label  SYSNAME   = NULL,  -- coluna amigável p/ exibição. Se NULL, usa @col_son
    @root_id    NVARCHAR(MAX) = NULL,  -- se NULL: todas as raízes (dad IS NULL). Senão, raiz = son == @root_id
    @max_level  INT       = 50,    -- segurança contra recursão infinita
    @tree_style CHAR(3)   = 'md',  -- 'md' (Markdown bullets) ou 'asc' (ASCII Tree art)
    @debug_sql  BIT       = 0      -- se 1, imprime o SQL dinâmico gerado via PRINT
AS
BEGIN
    SET NOCOUNT ON;

    -- =========================================================================
    -- PASSO 1: VALIDAÇÃO ESTÁTICA (NÃO USA SQL DINÂMICO AINDA)
    -- =========================================================================
    DECLARE @obj_id INT = OBJECT_ID(@table_name);
    IF @obj_id IS NULL
    BEGIN
        THROW 50001, N'[sp_render_tree] Tabela não existe. Verifique @table_name (use 2-part name se for schema diferente de dbo).', 1;
        RETURN;
    END;

    -- Valida @col_dad / @col_son / @col_label via sys.columns
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @obj_id AND name = @col_dad)
    BEGIN
        THROW 50002, N'[sp_render_tree] Coluna "pai" (col_dad) não encontrada na tabela alvo.', 1;
        RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @obj_id AND name = @col_son)
    BEGIN
        THROW 50003, N'[sp_render_tree] Coluna "filho" (col_son) não encontrada na tabela alvo.', 1;
        RETURN;
    END;
    IF @col_label IS NOT NULL AND
       NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @obj_id AND name = @col_label)
    BEGIN
        THROW 50004, N'[sp_render_tree] Coluna de rótulo (col_label) não encontrada na tabela alvo.', 1;
        RETURN;
    END;
    IF @tree_style NOT IN ('md', 'asc')
    BEGIN
        THROW 50005, N'[sp_render_tree] @tree_style deve ser ''md'' (markdown) ou ''asc'' (ascii).', 1;
        RETURN;
    END;

    -- Monta identificadores de tabela + colunas SEGUROS via QUOTENAME
    DECLARE @schema_name SYSNAME = OBJECT_SCHEMA_NAME(@obj_id);
    DECLARE @table_only  SYSNAME = OBJECT_NAME(@obj_id);
    DECLARE @q_table NVARCHAR(300) = QUOTENAME(@schema_name) + N'.' + QUOTENAME(@table_only);
    DECLARE @q_dad   NVARCHAR(150) = QUOTENAME(@col_dad);
    DECLARE @q_son   NVARCHAR(150) = QUOTENAME(@col_son);
    DECLARE @q_label NVARCHAR(150) = CASE WHEN @col_label IS NULL THEN @q_son ELSE QUOTENAME(@col_label) END;

    -- =========================================================================
    -- PASSO 2: MONTAGEM DO SQL DINÂMICO
    -- =========================================================================
    -- Lógica da CTE:
    --   (A) Pré-computa, para CADA nó, sua posição entre os irmãos (SiblingOrder
    --       e SiblingCount) → necessário para desenhar "└─ último irmão" vs "├─".
    --   (B) CTE recursiva carrega:
    --         * CyclePath = delimitado por » «  (evita falso-positivo em overlaps
    --           numéricos como 1 ∈ 11)
    --         * PrefixAcc = acumulador de prefixo ASCII: "│   " para irmãos-não-últimos
    --           e "    " (4 espaços) quando o ancestral era o último filho
    --         * Level + IsLastSibling do nó ATUAL
    -- =========================================================================
    DECLARE @sql NVARCHAR(MAX) = N'
;WITH BaseTable AS (
    -- Encapsulamento: lê a tabela de interesse + rótulo já tratado como string
    SELECT
        ' + @q_dad   + N' AS dad_id,
        ' + @q_son   + N' AS son_id,
        CONVERT(NVARCHAR(MAX), ' + @q_label + N') AS node_label,
        CONVERT(NVARCHAR(MAX), ' + @q_son   + N') AS son_id_str
    FROM ' + @q_table + N'
),
SiblingStats AS (
    -- Para cada nó, calcula sua posição entre irmãos do MESMO pai
    SELECT
        son_id,
        ROW_NUMBER() OVER (PARTITION BY dad_id ORDER BY son_id) AS SibOrder,
        COUNT(*)     OVER (PARTITION BY dad_id)                  AS SibTotal
    FROM BaseTable
),
RecursiveTree AS (
    -- ===========================
    -- ÂNCORA: nós raiz
    -- ===========================
    SELECT
        b.dad_id,
        b.son_id,
        b.node_label,
        b.son_id_str,
        Level      = 0,
        IsCycle    = CAST(0 AS BIT),
        -- Prefixo ASCII de níveis ANCESTRAIS (acumula conforme descemos)
        PrefixAcc  = CAST(N'''' AS NVARCHAR(MAX)),
        -- Ciclo: começa com »root_id«
        CyclePath  = CAST(N''»'' + b.son_id_str + N''«'' AS NVARCHAR(MAX)),
        ss.SibOrder,
        ss.SibTotal,
        -- Raiz por definição é o último (e único) do seu nível de irmãos
        IsLastSibling = CAST(1 AS BIT)
    FROM BaseTable b
    JOIN SiblingStats ss ON b.son_id = ss.son_id
    WHERE
        -- Caso A: usuário pediu uma raiz específica via @p_root_id
        (@p_root_id IS NOT NULL AND b.son_id_str = CONVERT(NVARCHAR(MAX), @p_root_id))
        OR
        -- Caso B: raízes padrão = todas as linhas onde pai é NULL
        (@p_root_id IS NULL AND b.dad_id IS NULL)

    UNION ALL

    -- ===========================
    -- RECURSÃO: filhos → netos → ...
    -- ===========================
    SELECT
        b.dad_id,
        b.son_id,
        b.node_label,
        b.son_id_str,
        Level      = rt.Level + 1,
        IsCycle    = CAST(CASE
                        WHEN CHARINDEX(N''»'' + CONVERT(NVARCHAR(MAX), b.dad_id) + N''«'', rt.CyclePath) > 0
                        THEN 1 ELSE 0 END AS BIT),
        PrefixAcc  = CAST(rt.PrefixAcc
                        + CASE WHEN rt.IsLastSibling = 1 THEN N''    ''
                                                        ELSE N''│   '' END
                       AS NVARCHAR(MAX)),
        CyclePath  = CAST(rt.CyclePath + N''»'' + b.son_id_str + N''«'' AS NVARCHAR(MAX)),
        ss.SibOrder,
        ss.SibTotal,
        IsLastSibling = CAST(CASE WHEN ss.SibOrder = ss.SibTotal THEN 1 ELSE 0 END AS BIT)
    FROM BaseTable b
    JOIN RecursiveTree rt ON b.dad_id = rt.son_id
    JOIN SiblingStats  ss ON b.son_id = ss.son_id
    WHERE
        -- Proteção 1: não continua se já detectamos ciclo
        rt.IsCycle = 0
        -- Proteção 2: respeita o limite de níveis do usuário
        AND rt.Level + 1 <= @p_max_level
)
SELECT ResultColumn
FROM (
    SELECT
        Level, son_id, dad_id, node_label, IsCycle, SibOrder, CyclePath,
        --------------------------------------------------------------
        -- COLUNA FINAL PRONTA PARA COLAR EM MARKDOWN / TERMINAL
        --------------------------------------------------------------
        CASE @p_tree_style
            WHEN ''md'' THEN
                -- Markdown: 2 espaços por nível + bullet "- "
                REPLICATE(N''  '', Level) + N''- ''
                + node_label
                + CASE WHEN IsCycle = 1 THEN N'' ⚠️ CICLO DETECTADO'' ELSE N'''' END
            ELSE
                -- ASCII Tree art: combina prefixo ancestral (│ / espaços)
                -- com o símbolo do nó atual (├─ | └─). Level 0 não tem símbolo.
                CASE WHEN Level = 0 THEN N''''
                     ELSE PrefixAcc
                        + CASE WHEN IsLastSibling = 1 THEN N''└─ '' ELSE N''├─ '' END END
                + node_label
                + CASE WHEN IsCycle = 1 THEN N''  [CICLO! path='' + REPLACE(CyclePath, N''»«'', N''<'') + N'']'' ELSE N'''' END
        END AS ResultColumn
    FROM RecursiveTree
) x
-- Para documentos: ordem topológica ancestral → filhos por posição entre irmãos
ORDER BY CyclePath, SibOrder
OPTION (MAXRECURSION 0); -- 0 = ilimitado; o nosso @max_level interno já protege.
';

    IF @debug_sql = 1
    BEGIN
        PRINT N'-- ===== SQL DINÂMICO GERADO POR lab.sp_render_tree =====';
        PRINT @sql;
    END;

    -- =========================================================================
    -- PASSO 3: EXECUÇÃO TIPADA COM sp_executesql (seguro)
    -- =========================================================================
    DECLARE @params NVARCHAR(MAX) = N'
        @p_root_id   NVARCHAR(MAX),
        @p_max_level INT,
        @p_tree_style CHAR(3)
    ';

    EXEC sp_executesql
        @stmt   = @sql,
        @params = @params,
        @p_root_id   = @root_id,
        @p_max_level = @max_level,
        @p_tree_style = @tree_style;
END;
GO

-- --------------------------------------------------------------------------------
-- EXEMPLOS DE USO DA lab.sp_render_tree
-- --------------------------------------------------------------------------------
PRINT '═══════════════════════════════════════════════════════════════';
PRINT 'Exemplo 1) Árvore lab.OrgChart em MARKDOWN (estilo bullets "- ")';
PRINT '═══════════════════════════════════════════════════════════════';
EXEC lab.sp_render_tree
     @table_name = 'lab.OrgChart',
     @col_dad    = 'ManagerID',
     @col_son    = 'EmployeeID',
     @col_label  = 'EmployeeName',
     @tree_style = 'md';
GO

PRINT '═══════════════════════════════════════════════════════════════';
PRINT 'Exemplo 2) A MESMA árvore, agora em ASCII Tree (│ ├─ └─)';
PRINT '═══════════════════════════════════════════════════════════════';
EXEC lab.sp_render_tree
     @table_name = 'lab.OrgChart',
     @col_dad    = 'ManagerID',
     @col_son    = 'EmployeeID',
     @col_label  = 'EmployeeName',
     @tree_style = 'asc';
GO

PRINT '═══════════════════════════════════════════════════════════════';
PRINT 'Exemplo 3) Sub-árvore: somente a partir do Gerente de Região A';
PRINT '            (EmployeeID = 3 — usei @root_id para "cortar" a árvore)';
PRINT '═══════════════════════════════════════════════════════════════';
EXEC lab.sp_render_tree
     @table_name = 'lab.OrgChart',
     @col_dad    = 'ManagerID',
     @col_son    = 'EmployeeID',
     @col_label  = 'EmployeeName',
     @root_id    = '3',
     @tree_style = 'asc';
GO

PRINT '═══════════════════════════════════════════════════════════════';
PRINT 'Exemplo 4) [SEGURANÇA] Demonstração de @debug_sql = 1:';
PRINT '            (imprime o SQL dinâmico — útil para entender a CTE)';
PRINT '═══════════════════════════════════════════════════════════════';
EXEC lab.sp_render_tree
     @table_name = 'lab.OrgChart',
     @col_dad    = 'ManagerID',
     @col_son    = 'EmployeeID',
     @col_label  = 'EmployeeName',
     @tree_style = 'md',
     @debug_sql  = 1;
GO

-- --------------------------------------------------------------------------------
-- 🔥 EXEMPLO 5 - Hierarquia REAL do AdventureWorks (ponte HIERARCHYID → Adjacency List)
--     HumanResources.Employee usa o tipo HIERARCHYID e não tem coluna ManagerID direta.
--     Criamos uma #temp materializando a coluna ManagerID via OrganizationNode.GetAncestor(1)
--     e depois entregamos à mesma sp_render_tree — prova de que a procedure funciona
--     EM QUALQUER tabela, não apenas nas nossas tabelas "didáticas".
-- --------------------------------------------------------------------------------
DROP TABLE IF EXISTS #AWDiretoria;
CREATE TABLE #AWDiretoria (
    EmployeeID   INT NOT NULL PRIMARY KEY,
    ManagerID    INT NULL FOREIGN KEY REFERENCES #AWDiretoria(EmployeeID),
    EmployeeName NVARCHAR(300) NOT NULL
);

INSERT INTO #AWDiretoria (EmployeeID, ManagerID, EmployeeName)
SELECT
    emp.BusinessEntityID,
    mgr.BusinessEntityID AS ManagerID,
    N'[' + emp.JobTitle + N'] ' + p.FirstName + N' ' + ISNULL(p.MiddleName + N' ', N'') + p.LastName
FROM HumanResources.Employee emp
INNER JOIN Person.Person p ON p.BusinessEntityID = emp.BusinessEntityID
LEFT JOIN HumanResources.Employee mgr
       ON mgr.OrganizationNode = emp.OrganizationNode.GetAncestor(1)
WHERE emp.OrganizationLevel <= 2  -- limita a 3 níveis: CEO + Diretores + Gerentes
ORDER BY emp.OrganizationLevel, emp.BusinessEntityID;

PRINT '═══════════════════════════════════════════════════════════════';
PRINT 'Exemplo 5) Dados REAIS do AdventureWorks — Diretoria da empresa';
PRINT '            (HumanResources.Employee convertido p/ Adjacency List)';
PRINT '═══════════════════════════════════════════════════════════════';
EXEC lab.sp_render_tree
     @table_name = 'tempdb..#AWDiretoria',
     @col_dad    = 'ManagerID',
     @col_son    = 'EmployeeID',
     @col_label  = 'EmployeeName',
     @tree_style = 'asc';
GO

-- --------------------------------------------------------------------------------
-- NOTA TÉCNICA: Por que é STORED PROCEDURE e não uma Table-Valued Function (TVF)?
-- A sua ideia de `SELECT * FROM fn_render_table(...)` é elegantíssima, mas no
-- SQL Server UDFs NÃO PODEM chamar EXEC / sp_executesql (SQL dinâmico).
-- Isso é uma limitação do motor para manter determinação e consistência de plano.
-- Workaround para usar o resultado como "tabela":
--   1) Crie uma #temp com a estrutura desejada
--   2) Popule com `INSERT #temp EXEC lab.sp_render_tree ...`
--   3) Agora sim, filtre, junte e ordene à vontade: `SELECT * FROM #temp WHERE ...`
-- Abaixo o pattern pronto para copiar:
-- --------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TreeResult') IS NOT NULL DROP TABLE #TreeResult;
CREATE TABLE #TreeResult (ResultColumn NVARCHAR(MAX));
INSERT INTO #TreeResult (ResultColumn)
EXEC lab.sp_render_tree
     @table_name = 'lab.OrgChart',
     @col_dad    = 'ManagerID',
     @col_son    = 'EmployeeID',
     @col_label  = 'EmployeeName',
     @tree_style = 'asc';
SELECT * FROM #TreeResult WHERE ResultColumn LIKE N'%Vendedor%'; -- filtrando como tabela!
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


--- CENÁRIO 2: Análise de Percentil e Distribuição (MS Learn: PERCENTILE_CONT/DISC,
---           CUME_DIST, PERCENT_RANK). Alinhado ao módulo "Funções de Janela" da DP-800.
-- CONCEITOS CHAVE:
--   - PERCENTILE_CONT(p): Interpolação CONTÍNUA (pode NÃO existir nos dados).
--        Ex: mediana P50 de {10,20,30,40} = 25 (valor interpolado).
--   - PERCENTILE_DISC(p): Valor DISCRETO que EXISTE na coluna (sem interpolação).
--        Retorna o menor valor cujo CUME_DIST >= p. Ex: P50 acima = 20.
--   - CUME_DIST(): Distribuição Cumulativa (0,1]. P100 = 1.0. Útil para "top 10%".
--   - PERCENT_RANK(): Ranking percentual [0,1]. Primeira linha = 0. Útil para "estou abaixo de X%".
--
-- [PONTO DE ATENÇÃO DP-800] PERCENTILE_CONT/DISC usam WITHIN GROUP (ORDER BY ...),
--   NÃO OVER (ORDER BY ...). O OVER() só aceita PARTITION BY — ORDER BY de framing
--   não é permitido nessas funções.

SELECT DISTINCT
    SalesPersonID,
    -- 🔴 Mediana (P50) CONTÍNUA (interpolada) — pode não corresponder a nenhuma venda real
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Amount)
        OVER (PARTITION BY SalesPersonID) AS P50_MedianaContinua,
    -- 🔵 Mediana (P50) DISCRETA — sempre coincide com um Amount real da partição
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY Amount)
        OVER (PARTITION BY SalesPersonID) AS P50_MedianaDiscreta,
    -- 🟢 P90 — valor que separa os 10% maiores
    PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY Amount)
        OVER (PARTITION BY SalesPersonID) AS P90_Discreto
FROM lab.SalesData
ORDER BY SalesPersonID;
GO

-- Complemento: CUME_DIST vs PERCENT_RANK lado a lado (vendedor 103 com 3 vendas)
SELECT
    SaleID, SalesPersonID, Amount,
    CUME_DIST()    OVER (PARTITION BY SalesPersonID ORDER BY Amount) AS CumeDist_PosicaoAcumulada,
    PERCENT_RANK() OVER (PARTITION BY SalesPersonID ORDER BY Amount) AS PercentRank_Relativo
FROM lab.SalesData
WHERE SalesPersonID = 103
ORDER BY Amount;
GO


--- CENÁRIO 3: BÔNUS HIERARCHYID — Tipo Nativo vs Adjacency List + CTE Recursiva
-- CONCEITO MS Learn:
--   O SQL Server oferece o tipo HIERARCHYID para representar árvores sem precisar
--   de CTE recursiva. Internamente armazena o CAMINHO (ex: /1/3/2/) em binário.
--   Operações: .GetLevel(), .GetAncestor(n), .IsDescendantOf(x), .ToString().
--   Vantagem: consultas de sub-árvore e ancestralidade são O(1) por índice clusterizado.
--   Desvantagem: a manutenção (rebalanceamento) é manual.
--
-- [PONTO DE ATENÇÃO DP-800] Diferenciar quando usar cada abordagem:
--   • HIERARCHYID = árvores profundas que precisam de consultas ancestrais rápidas.
--   • Adjacency List (col_dad NULL) + CTE Recursiva = estrutura mais simples,
--     flexível, compatível com todos os bancos, ideal para estruturas rasas/médias.

CREATE TABLE lab.OrgChartHierarchyid (
    NodeId      HIERARCHYID NOT NULL PRIMARY KEY,   -- /1/  /1/1/  /1/1/1/ etc.
    EmployeeID  INT NOT NULL UNIQUE,                 -- id lógico (mesmo conceito do lab.OrgChart)
    EmployeeName NVARCHAR(100) NOT NULL,
    Nivel AS NodeId.GetLevel()                       -- coluna computada!
);
GO

-- Popula a partir da nossa tabela adjacência lab.OrgChart (uma forma de migração):
-- Para 5 nós usamos literais didáticos; em produção você geraria a partir da rCTE.
INSERT INTO lab.OrgChartHierarchyid (NodeId, EmployeeID, EmployeeName) VALUES
('/1/',     1, N'CEO / Presidente'),          -- Level 0 (raiz)
('/1/1/',   2, N'VP de Vendas'),              -- Level 1 (filho do CEO)
('/1/1/1/', 3, N'Gerente de Vendas Região A'),-- Level 2
('/1/1/1/1/',4, N'Vendedor Senior 1'),        -- Level 3
('/1/1/1/2/',5, N'Vendedor Junior 2');        -- Level 3 (irmão do anterior)
GO

-- Consulta 1: Visualização tipo "path" (Sem CTE! Tudo nativo do HIERARCHYID)
SELECT
    NodeId.ToString() AS PathString,
    Nivel,
    EmployeeID,
    EmployeeName,
    NodeId.GetAncestor(1).ToString() AS PaiImediato
FROM lab.OrgChartHierarchyid
ORDER BY NodeId;
GO

-- Consulta 2: Sub-árvore abaixo do "Gerente de Vendas Região A" (EmployeeID=3)
-- Novamente sem recursão — simples predicado IsDescendantOf!
DECLARE @gerente HIERARCHYID = (SELECT NodeId FROM lab.OrgChartHierarchyid WHERE EmployeeID = 3);
SELECT
    REPLICATE('  ', Nivel - @gerente.GetLevel()) + '- ' + EmployeeName AS SubArvoreMarkdown,
    EmployeeID
FROM lab.OrgChartHierarchyid
WHERE NodeId.IsDescendantOf(@gerente) = 1
ORDER BY NodeId;
GO


--- CENÁRIO 4: Detecção de GAPS (lacunas) em sequências — LAG() com predicado
-- CONCEITO: Em dados de séries temporais / IDs sequenciais, uma "lacuna" é quando
--   o valor atual não é igual ao anterior + 1 (ou o tempo saltou além do esperado).
--   Com LAG isso é resolvido em 1 passagem SEM auto-join.

-- Exemplo prático: detecção de falha de gravação — esperamos 1 SaleID por INSERT,
-- mas verificamos se houve alguma lacuna (no dataset atual não há, mas o SQL detecta).
WITH Lacunas AS (
    SELECT
        SaleID,
        LAG(SaleID, 1) OVER (ORDER BY SaleID) AS SaleID_Anterior,
        LAG(SaleDate, 1) OVER (PARTITION BY SalesPersonID ORDER BY SaleDate) AS DataAnterior,
        SalesPersonID, SaleDate
    FROM lab.SalesData
)
SELECT
    SalesPersonID,
    SaleID, SaleID_Anterior,
    CASE WHEN SaleID <> SaleID_Anterior + 1 AND SaleID_Anterior IS NOT NULL
              THEN 'LACUNA DE ID!' ELSE 'ok' END AS StatusID,
    SaleDate, DataAnterior,
    DATEDIFF(DAY, DataAnterior, SaleDate) AS DiasEntreVendas,
    CASE WHEN DATEDIFF(DAY, DataAnterior, SaleDate) > 14
              THEN '⚠️ Intervalo >14 dias' ELSE 'ok' END AS StatusIntervalo
FROM Lacunas
ORDER BY SalesPersonID, SaleID;
GO


--- CENÁRIO 5: Top-N por Grupo (Top 2 maiores vendas por vendedor)
-- PADRÃO PRODUÇÃO: ROW_NUMBER() ou DENSE_RANK() em CTE + WHERE rn <= N
--   ROW_NUMBER → desempate arbitrário (exatamente N linhas, sem permitir + por empate)
--   RANK/DENSE_RANK → permite mais de N se houver empate no corte.

WITH RankVendasPorVendedor AS (
    SELECT
        SaleID, SalesPersonID, SaleDate, Amount,
        -- 2 rankings lado a lado para comparar o efeito de empates (vendedor 102 R$500 x2)
        ROW_NUMBER() OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC, SaleID) AS RN,
        RANK()       OVER (PARTITION BY SalesPersonID ORDER BY Amount DESC) AS RK
    FROM lab.SalesData
)
SELECT *
FROM RankVendasPorVendedor
WHERE RN <= 2  -- top 2 por vendedor
ORDER BY SalesPersonID, RN;
GO


-- =================================================================================
-- CHECKLIST FINAL DP-800: TÓPICOS COBERTOS NESTE LABORATÓRIO
-- =================================================================================
-- ✅ CTES BÁSICAS e MÚLTIPLAS (WITH A AS (...), B AS (...) FROM A JOIN B)
-- ✅ CTE RECURSIVA (Anchor + Recursive Member + MAXRECURSION + TRY/CATCH)
-- ✅ NÃO-MATERIALIZAÇÃO: CTE referenciada 2x é recalculada 2x (vs #temp 1x)
-- ✅ RANKING: ROW_NUMBER vs RANK vs DENSE_RANK vs NTILE (empates, lacunas, quartis)
-- ✅ FRAME DEFAULT IMPLÍCITO: RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW (MS Learn)
-- ✅ ROWS vs RANGE em AGREGADOS: Running Total com valores empatados em ORDER BY
-- ✅ OFFSET: LAG / LEAD (NÃO usam framing) vs FIRST_VALUE / LAST_VALUE (USAM framing)
-- ✅ ARMADILHA LAST_VALUE: frame explícito UNBOUNDED FOLLOWING para pegar fim da partição
-- ✅ PERCENTILE_CONT/DISC (WITHIN GROUP) + CUME_DIST + PERCENT_RANK
-- ✅ DETECÇÃO DE CICLO em rCTE (breadcrumb com delimitador » « — evita falso-positivo 1 ∈ 11)
-- ✅ HIERARCHYID: GetLevel / GetAncestor / IsDescendantOf / ToString
-- ✅ DETECÇÃO DE GAPS: LAG + predicado (sequência e datas)
-- ✅ TOP-N POR GRUPO: ROW_NUMBER/DENSE_RANK em CTE + filtro
-- ✅ RENDERIZAÇÃO DE ÁRVORE: lab.sp_render_tree (SQL dinâmico seguro, MD + ASCII)
-- =================================================================================
-- Para reler a teoria oficial MS Learn completa:
--   • Window Functions: https://learn.microsoft.com/pt-br/training/modules/write-queries-that-use-window-functions/
--   • LAST_VALUE trap: https://learn.microsoft.com/pt-br/sql/t-sql/functions/last-value-transact-sql
--   • OVER clause frames: https://learn.microsoft.com/pt-br/sql/t-sql/queries/select-over-clause-transact-sql
--   • Dynamic SQL seguro: https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-executesql-transact-sql
-- =================================================================================
GO
