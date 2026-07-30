-- ====================================================================
-- Guia de Estudos DP-800 — Lab 11: PIVOT e UNPIVOT
-- Banco de dados: StudyDB
-- Objetivo: remodelar vendas trimestrais entre formatos longo e largo.
-- Pré-requisito: execute 01-setup-studydb.sql primeiro.
-- ====================================================================

-- REFERÊNCIA TEÓRICA: ../../../certification/00-fundamentals/11-pivot-unpivot.md
--    Abra a teoria junto com este lab para acompanhar os conceitos.

USE StudyDB;
GO

DROP TABLE IF EXISTS study.PivotSales;
GO

CREATE TABLE study.PivotSales
(
    SalesYear   int            NOT NULL,
    Region      nvarchar(20)  NOT NULL,
    QuarterName nchar(2)      NOT NULL,
    Amount      decimal(12,2) NOT NULL
);
GO

INSERT INTO study.PivotSales (SalesYear, Region, QuarterName, Amount)
VALUES
    (2025, N'East',  N'Q1', 100.00),
    (2025, N'East',  N'Q2', 120.00),
    (2025, N'East',  N'Q3', 135.00),
    (2025, N'West',  N'Q1',  90.00),
    (2025, N'West',  N'Q2', 110.00),
    (2025, N'West',  N'Q4', 160.00),
    (2025, N'East',  N'Q1',  25.00),
    (2025, N'North', N'Q4', 200.00);
GO

-- PARTE 1: Inspecione o formato longo/original.
-- Cada linha representa região, ano, trimestre e valor. East possui duas linhas Q1,
-- permitindo demonstrar por que PIVOT precisa de uma agregação.
SELECT SalesYear, Region, QuarterName, Amount
FROM study.PivotSales
ORDER BY SalesYear, Region, QuarterName, Amount;
GO

-- PARTE 2: Transforme linhas longas em um relatório trimestral largo.
-- SUM combina linhas duplicadas da origem (East Q1 = 100 + 25 = 125). A lista IN
-- fixa as colunas de saída. Valores ausentes permanecem NULL: East Q4 e North Q1-Q3.
SELECT SalesYear, Region, [Q1], [Q2], [Q3], [Q4]
FROM
(
    SELECT SalesYear, Region, QuarterName, Amount
    FROM study.PivotSales
) AS source_data
PIVOT
(
    SUM(Amount)
    FOR QuarterName IN ([Q1], [Q2], [Q3], [Q4])
) AS pivot_data
ORDER BY SalesYear, Region;
GO

-- PARTE 3: Compare PIVOT com agregação condicional.
-- O resultado tem o mesmo formato largo usando SUM(CASE). Essa forma costuma ser
-- mais fácil de estender quando cada coluna precisa de uma condição diferente.
SELECT
    SalesYear,
    Region,
    SUM(CASE WHEN QuarterName = N'Q1' THEN Amount END) AS Q1,
    SUM(CASE WHEN QuarterName = N'Q2' THEN Amount END) AS Q2,
    SUM(CASE WHEN QuarterName = N'Q3' THEN Amount END) AS Q3,
    SUM(CASE WHEN QuarterName = N'Q4' THEN Amount END) AS Q4
FROM study.PivotSales
GROUP BY SalesYear, Region
ORDER BY SalesYear, Region;
GO

-- PARTE 4: Faça UNPIVOT do resultado largo de volta para linhas.
-- A CTE primeiro cria o mesmo formato largo da Parte 2. UNPIVOT transforma os nomes
-- Q1-Q4 em valores de QuarterName e as células em Amount. Células NULL são omitidas,
-- portanto trimestres ausentes não geram linhas.
WITH Quarterly AS
(
    SELECT SalesYear, Region, [Q1], [Q2], [Q3], [Q4]
    FROM
    (
        SELECT SalesYear, Region, QuarterName, Amount
        FROM study.PivotSales
    ) AS source_data
    PIVOT
    (
        SUM(Amount)
        FOR QuarterName IN ([Q1], [Q2], [Q3], [Q4])
    ) AS pivot_data
)
SELECT SalesYear, Region, QuarterName, Amount
FROM Quarterly
UNPIVOT
(
    Amount FOR QuarterName IN ([Q1], [Q2], [Q3], [Q4])
) AS unpivot_data
ORDER BY SalesYear, Region, QuarterName;
GO

-- VERIFIQUE SEU APRENDIZADO:
-- 1. Adicione uma segunda linha Q2 para North e confirme que PIVOT soma as linhas.
-- 2. Troque SUM por COUNT e explique o significado dos valores pivotados.
-- 3. Adicione uma linha Q4 para East e observe o NULL desaparecer do relatório largo.
-- 4. Explique por que UNPIVOT não recria linhas para trimestres ausentes.

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/00-fundamentals/11-pivot-unpivot.md
-- =================================================================================================
