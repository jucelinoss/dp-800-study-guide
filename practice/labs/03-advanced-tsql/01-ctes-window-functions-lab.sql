-- =================================================================================
-- DP-800 - HANDS-ON LAB: CTEs (RECURSIVE, MATERIALIZATION) AND WINDOW FUNCTIONS
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to restore the
-- AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates advanced use of CTEs and Window Functions in SQL Server:
--   1. Simple CTEs, Multiple CTEs, and Recursive CTEs with MAXRECURSION control
--   2. Non-Materialization of CTEs vs Physical Temporary Tables (#temp)
--   3. Ranking Functions: ROW_NUMBER, RANK, DENSE_RANK, and NTILE (Ties and Gaps)
--   4. Window Framing: ROWS vs RANGE and Running Totals
--   5. Offset Functions: LAG, LEAD, FIRST_VALUE, and the LAST_VALUE Pitfall
--   6. Practical Project Scenarios (Record Deduplication and Percentile Analysis)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP TABLE IF EXISTS lab.OrgChart;
DROP TABLE IF EXISTS lab.SalesData;
DROP TABLE IF EXISTS lab.CustomerEvents;
GO

-- Table structures for testing
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
-- PART 1: RECURSIVE CTEs AND RECURSION CONTROL (MAXRECURSION)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - RECURSIVE CTE: Structure composed of an Anchor Member joined via `UNION ALL`
--     to a Recursive Member that references the CTE itself until the termination condition is met.
--   - MAXRECURSION: By default, SQL Server limits recursion to 100 levels to prevent infinite loops.
--     Use `OPTION (MAXRECURSION n)` to change it (where 0 = no limit, use with extreme caution).

-- 1. Populate organizational hierarchy data
INSERT INTO lab.OrgChart VALUES 
(1, 'CEO / Presidente', NULL),
(2, 'VP de Vendas', 1),
(3, 'Gerente de Vendas Região A', 2),
(4, 'Vendedor Senior 1', 3),
(5, 'Vendedor Junior 2', 3);
GO

-- 2. Recursive CTE query to map hierarchy levels
WITH EmployeeHierarchy AS (
    -- Anchor Member: top of the pyramid (no manager)
    SELECT EmployeeID, EmployeeName, ManagerID, 0 AS Level
    FROM lab.OrgChart
    WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive Member: subordinate employees
    SELECT e.EmployeeID, e.EmployeeName, e.ManagerID, h.Level + 1
    FROM lab.OrgChart e
    JOIN EmployeeHierarchy h ON e.ManagerID = h.EmployeeID
)
SELECT EmployeeID, EmployeeName, Level, REPLICATE('--- ', Level) + EmployeeName AS HierarchyTree
FROM EmployeeHierarchy
ORDER BY Level, EmployeeName;
GO

-- -- [DP-800 EXAM TIP]
-- Recursion Overflow Test (MAXRECURSION Exceeded):
-- Generating an infinite/long sequence to force SQL Server error 530.
BEGIN TRY
    ;WITH InfiniteSeq AS (
        SELECT 1 AS N
        UNION ALL
        SELECT N + 1 FROM InfiniteSeq WHERE N < 200
    )
    SELECT * FROM InfiniteSeq; -- Will fail because 200 > 100 (Default Limit)
END TRY
BEGIN CATCH
    PRINT 'ERRO ESPERADO MAXRECURSION: ' + ERROR_MESSAGE();
    -- Error: "The statement terminated because the maximum recursion 100 was exhausted..."
END CATCH;
GO


-- =================================================================================
-- PART 2: RANKING FUNCTIONS (ROW_NUMBER, RANK, DENSE_RANK, NTILE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - ROW_NUMBER(): Generates a strict unique numeric sequence (no ties, arbitrary tiebreaker).
--   - RANK(): Generates rankings with ties. Leaves gaps in the following rank (e.g. 1, 1, 3).
--   - DENSE_RANK(): Generates rankings with ties. Does NOT leave gaps in the following rank (e.g. 1, 1, 2).
--   - NTILE(n): Divides the result set into `n` buckets (quartiles, deciles, etc.) with equal sizes.

INSERT INTO lab.SalesData (SalesPersonID, SaleDate, Amount) VALUES 
(101, '2025-01-01', 500.00),
(102, '2025-01-01', 500.00), -- Tie in value
(103, '2025-01-01', 300.00),
(104, '2025-01-01', 200.00);
GO

-- -- [DP-800 EXAM TIP]
-- Side-by-side comparison of Ranking Functions
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
-- PART 3: WINDOW FRAMING (ROWS VS RANGE AND RUNNING TOTAL)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - RANGE (Default): Logical framing. Treats rows with identical ORDER BY values as a single block.
--   - ROWS: Strict physical framing. Evaluates physically row by row.
--   - RUNNING TOTAL: Requires the `ROWS UNBOUNDED PRECEDING` clause for performance and accuracy.

SELECT 
    SaleID,
    SalesPersonID,
    SaleDate,
    Amount,
    -- Running Total by SalesPerson
    SUM(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate, SaleID
        ROWS UNBOUNDED PRECEDING
    ) AS RunningTotal,
    -- Moving Average (Current Row + 1 Previous Row)
    AVG(Amount) OVER (
        PARTITION BY SalesPersonID
        ORDER BY SaleDate, SaleID
        ROWS BETWEEN 1 PRECEDING AND CURRENT ROW
    ) AS MovingAvg2
FROM lab.SalesData;
GO


-- =================================================================================
-- PART 4: OFFSET FUNCTIONS (LAG, LEAD, FIRST_VALUE, AND THE LAST_VALUE PITFALL)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - LAG / LEAD: Access the value of previous or subsequent rows without needing a self-join.
--   - FIRST_VALUE: Returns the first value of the window frame.
--   - LAST_VALUE: Returns the last value of the window frame.
--   - LAST_VALUE PITFALL: The default frame stops at the current row (`CURRENT ROW`).
--     Without declaring `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`, `LAST_VALUE` will return
--     the current row's own value instead of the true last record of the partition!

-- -- [DP-800 EXAM TIP]
SELECT 
    SaleID,
    SalesPersonID,
    Amount,
    LAG(Amount, 1, 0) OVER (PARTITION BY SalesPersonID ORDER BY SaleID) AS ValorAnterior,
    LEAD(Amount, 1, 0) OVER (PARTITION BY SalesPersonID ORDER BY SaleID) AS ProximoValor,
    
    -- Wrong/Misleading: Returns the current row's value because of the default framing
    LAST_VALUE(Amount) OVER (PARTITION BY SalesPersonID ORDER BY SaleID) AS LastValueErrado,
    
    -- Correct: Explicit declaration of the full partition window
    LAST_VALUE(Amount) OVER (
        PARTITION BY SalesPersonID 
        ORDER BY SaleID
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS LastValueCorreto
FROM lab.SalesData;
GO


-- =================================================================================
-- PART 5: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Deduplicating Event Records keeping only the latest update
-- Standard production technique using ROW_NUMBER() in a CTE to filter for `rn = 1`.

INSERT INTO lab.CustomerEvents (CustomerID, EventName, EventDate) VALUES 
    (1001, 'Login', '2025-01-01 10:00:00'),
    (1001, 'UpdateProfile', '2025-01-01 10:05:00'), -- Most recent event
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
WHERE RowNum = 1; -- Keeps only the most recent record per customer
GO
