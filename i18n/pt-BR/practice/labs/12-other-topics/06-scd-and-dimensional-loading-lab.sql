-- =================================================================================
-- DP-800 - LABORATÓRIO PRÁTICO: SCD E CARGAS DIMENSIONAIS
-- Banco de dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- O script demonstra uma carga incremental sem MERGE:
--   * EmailAddress = SCD Tipo 1: sobrescreve somente o estado atual.
--   * Segment/Region = SCD Tipo 2: fecha a versão e cria uma nova surrogate key.
--   * PreviousSegment = SCD Tipo 3: mantém o valor anterior na linha atual.
--   * Hashdiff, vigência, idempotência, resolução histórica da fato e checks.
--
-- TEORIA: ../../../certification/12-other-topics/06-scd-and-dimensional-loading.md
-- REFERÊNCIA OFICIAL:
-- https://learn.microsoft.com/en-us/fabric/iq/plan/powertable-concept-slowly-changing-dimensions
-- =================================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

USE AdventureWorks2025;
GO

DROP TABLE IF EXISTS lab_scd.FactSales;
DROP TABLE IF EXISTS lab_scd.DimCustomer;
DROP TABLE IF EXISTS lab_scd.CustomerStage;
DROP TABLE IF EXISTS lab_scd.BatchControl;
GO

IF SCHEMA_ID(N'lab_scd') IS NULL
    EXEC(N'CREATE SCHEMA lab_scd AUTHORIZATION dbo;');
GO

-- =================================================================================
-- PARTE 1: STAGING E CONTROLE DE LOTES
-- =================================================================================
CREATE TABLE lab_scd.BatchControl (
    BatchID NVARCHAR(50) NOT NULL CONSTRAINT PK_ScdBatch PRIMARY KEY,
    LoadedAt DATETIME2(0) NOT NULL,
    Status VARCHAR(20) NOT NULL,
    RowsRead INT NOT NULL
);

CREATE TABLE lab_scd.CustomerStage (
    StageRowID BIGINT IDENTITY(1,1) CONSTRAINT PK_ScdStage PRIMARY KEY,
    BatchID NVARCHAR(50) NOT NULL,
    ChangeEffectiveAt DATETIME2(7) NOT NULL,
    CustomerID INT NOT NULL,
    EmailAddress NVARCHAR(200) NOT NULL,
    Segment NVARCHAR(50) NOT NULL,
    Region NVARCHAR(50) NOT NULL,
    CONSTRAINT FK_ScdStage_Batch FOREIGN KEY (BatchID) REFERENCES lab_scd.BatchControl(BatchID)
);
GO

INSERT INTO lab_scd.BatchControl (BatchID, LoadedAt, Status, RowsRead)
VALUES (N'batch-001', '2026-08-01T08:00:00', 'READY', 3),
       (N'batch-002', '2026-08-10T08:00:00', 'READY', 3);

INSERT INTO lab_scd.CustomerStage
    (BatchID, ChangeEffectiveAt, CustomerID, EmailAddress, Segment, Region)
VALUES
    -- Initial state.
    (N'batch-001', '2026-08-01T00:00:00.0000000', 100, N'ana@contoso.test', N'Standard', N'Southeast'),
    (N'batch-001', '2026-08-01T00:00:00.0000000', 200, N'bruno@northwind.test', N'Premium', N'South'),
    (N'batch-001', '2026-08-01T00:00:00.0000000', 300, N'carla@fabrikam.test', N'Standard', N'North'),
    -- Incremental state: 100 changes Type 1 and Type 2 attributes.
    (N'batch-002', '2026-08-10T00:00:00.0000000', 100, N'ana.silva@contoso.test', N'Premium', N'South'),
    -- 200 changes only Type 1 email; no new historical version is required.
    (N'batch-002', '2026-08-10T00:00:00.0000000', 200, N'bruno.souza@northwind.test', N'Premium', N'South'),
    -- 400 is a new member and receives its first version.
    (N'batch-002', '2026-08-10T00:00:00.0000000', 400, N'diego@adventure.test', N'Standard', N'West');
GO

-- =================================================================================
-- PARTE 2: DIMENSÃO SCD E CARGA INICIAL
-- =================================================================================
CREATE TABLE lab_scd.DimCustomer (
    CustomerKey INT IDENTITY(1,1) CONSTRAINT PK_ScdDimCustomer PRIMARY KEY,
    CustomerID INT NOT NULL,
    EmailAddress NVARCHAR(200) NOT NULL,
    Segment NVARCHAR(50) NOT NULL,
    Region NVARCHAR(50) NOT NULL,
    PreviousSegment NVARCHAR(50) NULL,
    EffectiveFrom DATETIME2(7) NOT NULL,
    EffectiveTo DATETIME2(7) NOT NULL,
    IsCurrent BIT NOT NULL,
    HashDiff BINARY(32) NOT NULL,
    CONSTRAINT CK_ScdDim_Interval CHECK (EffectiveFrom < EffectiveTo)
);
GO

SET IDENTITY_INSERT lab_scd.DimCustomer ON;
INSERT INTO lab_scd.DimCustomer
    (CustomerKey, CustomerID, EmailAddress, Segment, Region, PreviousSegment,
     EffectiveFrom, EffectiveTo, IsCurrent, HashDiff)
VALUES
    (0, -1, N'unknown@example.test', N'Unknown', N'Unknown', NULL,
     '1900-01-01', '9999-12-31T23:59:59.9999999', 1,
     CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'Unknown|Unknown')));
SET IDENTITY_INSERT lab_scd.DimCustomer OFF;

INSERT INTO lab_scd.DimCustomer
    (CustomerID, EmailAddress, Segment, Region, PreviousSegment, EffectiveFrom,
     EffectiveTo, IsCurrent, HashDiff)
SELECT s.CustomerID, s.EmailAddress, s.Segment, s.Region, NULL, s.ChangeEffectiveAt,
       CONVERT(DATETIME2(7), '9999-12-31T23:59:59.9999999'), 1,
       CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONCAT(s.Segment, N'|', s.Region)))
FROM lab_scd.CustomerStage AS s
WHERE s.BatchID = N'batch-001';
GO

-- =================================================================================
-- PARTE 3: CARGA INCREMENTAL: TIPO 1, TIPO 2 E TIPO 3
-- =================================================================================
DECLARE @BatchID NVARCHAR(50) = N'batch-002';

-- Tipo 1: email representa apenas o estado atual. Histórico antigo não é alterado
-- por esta política; somente a versão corrente recebe o novo email.
UPDATE d
SET d.EmailAddress = s.EmailAddress
FROM lab_scd.DimCustomer AS d
JOIN lab_scd.CustomerStage AS s ON s.CustomerID = d.CustomerID
WHERE d.IsCurrent = 1
  AND s.BatchID = @BatchID
  AND d.EmailAddress <> s.EmailAddress;

-- Tipo 2: fechar versões atuais somente quando o hash dos atributos históricos mudar.
UPDATE d
SET d.EffectiveTo = DATEADD(NANOSECOND, -100, s.ChangeEffectiveAt),
    d.IsCurrent = 0
FROM lab_scd.DimCustomer AS d
JOIN lab_scd.CustomerStage AS s ON s.CustomerID = d.CustomerID
WHERE d.IsCurrent = 1
  AND s.BatchID = @BatchID
  AND d.HashDiff <> CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONCAT(s.Segment, N'|', s.Region)));

-- Tipo 2 + Tipo 3: uma nova versão recebe a chave e o segmento anterior.
INSERT INTO lab_scd.DimCustomer
    (CustomerID, EmailAddress, Segment, Region, PreviousSegment, EffectiveFrom,
     EffectiveTo, IsCurrent, HashDiff)
SELECT s.CustomerID,
       s.EmailAddress,
       s.Segment,
       s.Region,
       current_version.Segment,
       s.ChangeEffectiveAt,
       CONVERT(DATETIME2(7), '9999-12-31T23:59:59.9999999'),
       1,
       CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONCAT(s.Segment, N'|', s.Region)))
FROM lab_scd.CustomerStage AS s
OUTER APPLY (
    SELECT TOP (1) d.Segment
    FROM lab_scd.DimCustomer AS d
    WHERE d.CustomerID = s.CustomerID AND d.IsCurrent = 0
    ORDER BY d.EffectiveTo DESC
) AS current_version
WHERE s.BatchID = @BatchID
  AND NOT EXISTS (
      SELECT 1
      FROM lab_scd.DimCustomer AS d
      WHERE d.CustomerID = s.CustomerID
        AND d.IsCurrent = 1
        AND d.HashDiff = CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONCAT(s.Segment, N'|', s.Region)))
  );

UPDATE lab_scd.BatchControl
SET Status = 'APPLIED'
WHERE BatchID = @BatchID;
GO

SELECT CustomerKey, CustomerID, EmailAddress, Segment, Region, PreviousSegment,
       EffectiveFrom, EffectiveTo, IsCurrent
FROM lab_scd.DimCustomer
ORDER BY CustomerID, EffectiveFrom;
GO

-- Reprocessamento do mesmo lote: a contagem não deve crescer porque o hashdiff e
-- a versão corrente já existem. O teste repete somente a inserção idempotente.
DECLARE @BeforeRerun INT = (SELECT COUNT(*) FROM lab_scd.DimCustomer);
INSERT INTO lab_scd.DimCustomer
    (CustomerID, EmailAddress, Segment, Region, PreviousSegment, EffectiveFrom,
     EffectiveTo, IsCurrent, HashDiff)
SELECT s.CustomerID, s.EmailAddress, s.Segment, s.Region, NULL, s.ChangeEffectiveAt,
       CONVERT(DATETIME2(7), '9999-12-31T23:59:59.9999999'), 1,
       CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONCAT(s.Segment, N'|', s.Region)))
FROM lab_scd.CustomerStage AS s
WHERE s.BatchID = N'batch-002'
  AND NOT EXISTS (
      SELECT 1 FROM lab_scd.DimCustomer AS d
      WHERE d.CustomerID = s.CustomerID AND d.IsCurrent = 1
        AND d.HashDiff = CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONCAT(s.Segment, N'|', s.Region)))
  );
IF @BeforeRerun <> (SELECT COUNT(*) FROM lab_scd.DimCustomer)
    THROW 51060, 'Reprocessamento criou versão duplicada.', 1;
GO

-- =================================================================================
-- PARTE 4: FATO RESOLVIDA PELA DATA DO EVENTO
-- =================================================================================
CREATE TABLE lab_scd.FactSales (
    OrderID NVARCHAR(50) NOT NULL CONSTRAINT PK_ScdFactSales PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    CustomerKey INT NOT NULL CONSTRAINT FK_ScdFactCustomer REFERENCES lab_scd.DimCustomer(CustomerKey),
    SalesAmount DECIMAL(14,2) NOT NULL
);

INSERT INTO lab_scd.FactSales (OrderID, CustomerID, OrderDate, CustomerKey, SalesAmount)
SELECT v.OrderID, v.CustomerID, v.OrderDate, COALESCE(d.CustomerKey, 0), v.SalesAmount
FROM (VALUES
    (N'O-7001', 100, CONVERT(DATE, '2026-08-05'), CONVERT(DECIMAL(14,2), 120.00)),
    (N'O-7002', 100, CONVERT(DATE, '2026-08-12'), CONVERT(DECIMAL(14,2), 180.00)),
    (N'O-7003', 200, CONVERT(DATE, '2026-08-11'), CONVERT(DECIMAL(14,2), 90.00)),
    (N'O-7004', 999, CONVERT(DATE, '2026-08-11'), CONVERT(DECIMAL(14,2), 40.00))
) AS v(OrderID, CustomerID, OrderDate, SalesAmount)
OUTER APPLY (
    SELECT TOP (1) d.CustomerKey
    FROM lab_scd.DimCustomer AS d
    WHERE d.CustomerID = v.CustomerID
      AND CONVERT(DATETIME2(7), v.OrderDate) >= d.EffectiveFrom
      AND CONVERT(DATETIME2(7), v.OrderDate) < d.EffectiveTo
    ORDER BY d.EffectiveFrom DESC
) AS d;
GO

SELECT f.OrderID, f.OrderDate, f.SalesAmount, f.CustomerID,
       f.CustomerKey, d.Segment, d.Region, d.EmailAddress
FROM lab_scd.FactSales AS f
JOIN lab_scd.DimCustomer AS d ON d.CustomerKey = f.CustomerKey
ORDER BY f.OrderID;
GO

-- =================================================================================
-- PARTE 5: CHECKS DE HISTÓRICO, INTERVALOS E RECONCILIAÇÃO
-- =================================================================================
IF EXISTS (
    SELECT CustomerID FROM lab_scd.DimCustomer
    WHERE CustomerID <> -1 AND IsCurrent = 1
    GROUP BY CustomerID HAVING COUNT(*) <> 1
)
    THROW 51061, 'Cada cliente deve ter exatamente uma versão corrente.', 1;

IF EXISTS (
    SELECT d.CustomerID
    FROM lab_scd.DimCustomer AS d
    JOIN lab_scd.DimCustomer AS next_version
      ON next_version.CustomerID = d.CustomerID
     AND next_version.EffectiveFrom = d.EffectiveTo
    WHERE d.CustomerID <> -1 AND d.EffectiveFrom >= d.EffectiveTo
)
    THROW 51062, 'Intervalo de dimensão inválido.', 1;

IF NOT EXISTS (SELECT 1 FROM lab_scd.FactSales WHERE CustomerKey = 0)
    THROW 51063, 'O teste de membro desconhecido não foi exercitado.', 1;

IF (SELECT SUM(SalesAmount) FROM lab_scd.FactSales) <> 430.00
    THROW 51064, 'Reconciliação de vendas falhou.', 1;

SELECT N'PASSOU' AS SCDQualityGate,
       N'Tipos 1, 2 e 3, idempotência, vigência, resolução histórica e totais foram validados.' AS Result;
GO

-- PRÓXIMO PASSO: revise a teoria em
-- ../../../certification/12-other-topics/06-scd-and-dimensional-loading.md
