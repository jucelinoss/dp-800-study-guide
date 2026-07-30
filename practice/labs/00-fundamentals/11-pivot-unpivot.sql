-- ====================================================================
-- DP-800 Study Guide — Lab 11: PIVOT and UNPIVOT
-- Database: StudyDB
-- Purpose: Reshape quarterly sales between long and wide formats.
-- Prerequisite: Run 01-setup-studydb.sql first.
-- ====================================================================

-- THEORY REFERENCE: ../../../certification/00-fundamentals/11-pivot-unpivot.md
--    Open the theory guide alongside this lab for conceptual context.

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

-- PART 1: Inspect the long/source format.
-- Each row represents one region, year, quarter, and amount. East has two Q1 rows,
-- which lets PIVOT demonstrate why an aggregate is required.
SELECT SalesYear, Region, QuarterName, Amount
FROM study.PivotSales
ORDER BY SalesYear, Region, QuarterName, Amount;
GO

-- PART 2: PIVOT long rows into a wide quarterly report.
-- SUM combines duplicate source rows (East Q1 = 100 + 25 = 125). The IN list fixes
-- the output columns. Missing source values remain NULL: East Q4 and North Q1-Q3.
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

-- PART 3: Compare PIVOT with conditional aggregation.
-- This produces the same wide shape using SUM(CASE). It is often easier to extend
-- when each output column needs a different condition or calculation.
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

-- PART 4: UNPIVOT the wide result back into rows.
-- The CTE first creates the same wide shape as Part 2. UNPIVOT then turns Q1-Q4
-- column names into QuarterName values and their cells into Amount values.
-- NULL cells are omitted, so missing quarters do not produce rows.
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

-- CHECK YOURSELF:
-- 1. Add a second Q2 row for North and verify that PIVOT sums both rows.
-- 2. Replace SUM with COUNT and explain what the pivoted values mean.
-- 3. Add a Q4 row for East and observe how the NULL disappears from the wide report.
-- 4. Explain why UNPIVOT does not recreate rows for missing quarters.

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/00-fundamentals/11-pivot-unpivot.md
-- =================================================================================================
