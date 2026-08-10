-- =================================================================================
-- DP-800 - LAB PRÁTICO: CLASSIFICAÇÃO DE SENSIBILIDADE
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/05-data-security-compliance/data-security-compliance.md
--
-- SQL Server 2019+ / Azure SQL Database:
--   sys.sensitivity_classifications armazena uma linha por coluna classificada.
--   A classificação é metadado; não mascara, criptografa nem altera os dados.
-- =================================================================================
-- Este lab demonstra:
--   1. Por que sys.sensitivity_classifications pode estar vazia
--   2. Como criar uma tabela de laboratório segura a partir do AdventureWorks
--   3. Como classificar colunas com ADD SENSITIVITY CLASSIFICATION
--   4. Como gerar e filtrar um inventário de conformidade
--   5. Como remover uma classificação com DROP SENSITIVITY CLASSIFICATION
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva: este lab possui somente o objeto abaixo no schema lab.
IF OBJECT_ID('lab.SensitiveCustomerData', 'U') IS NOT NULL
BEGIN
    DROP TABLE lab.SensitiveCustomerData;
END;
GO

IF SCHEMA_ID('lab') IS NULL
    EXEC('CREATE SCHEMA lab');
GO

CREATE TABLE lab.SensitiveCustomerData
(
    CustomerID       INT            NOT NULL PRIMARY KEY,
    FirstName        NVARCHAR(50)   NOT NULL,
    LastName         NVARCHAR(50)   NOT NULL,
    EmailAddress     NVARCHAR(50)   NULL,
    PhoneNumber      NVARCHAR(25)   NULL,
    BirthDate        DATE           NULL,
    NationalIDNumber NVARCHAR(15)   NULL
);
GO

INSERT INTO lab.SensitiveCustomerData
(
    CustomerID, FirstName, LastName, EmailAddress,
    PhoneNumber, BirthDate, NationalIDNumber
)
SELECT TOP (10)
    p.BusinessEntityID,
    p.FirstName,
    p.LastName,
    e.EmailAddress,
    pp.PhoneNumber,
    eom.BirthDate,
    eom.NationalIDNumber
FROM Person.Person AS p
LEFT JOIN HumanResources.Employee AS eom
    ON eom.BusinessEntityID = p.BusinessEntityID
OUTER APPLY
(
    SELECT TOP (1) EmailAddress
    FROM Person.EmailAddress
    WHERE BusinessEntityID = p.BusinessEntityID
    ORDER BY EmailAddressID
) AS e
OUTER APPLY
(
    SELECT TOP (1) PhoneNumber
    FROM Person.PersonPhone
    WHERE BusinessEntityID = p.BusinessEntityID
    ORDER BY PhoneNumberTypeID, PhoneNumber
) AS pp
ORDER BY p.BusinessEntityID;
GO

-- PARTE 1: antes da classificação, a view pode retornar zero linhas para a tabela.
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS TableName,
    c.name AS ColumnName,
    sc.information_type,
    sc.label,
    sc.rank_desc
FROM sys.sensitivity_classifications AS sc
JOIN sys.objects AS o ON o.object_id = sc.major_id
JOIN sys.columns AS c
    ON c.object_id = sc.major_id
   AND c.column_id = sc.minor_id
WHERE o.object_id = OBJECT_ID('lab.SensitiveCustomerData')
ORDER BY SchemaName, TableName, ColumnName;
GO

-- PARTE 2: adicionar metadados de sensibilidade às colunas escolhidas.
ADD SENSITIVITY CLASSIFICATION TO
    lab.SensitiveCustomerData.EmailAddress,
    lab.SensitiveCustomerData.PhoneNumber
WITH
(
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Contact Info',
    RANK = HIGH
);

ADD SENSITIVITY CLASSIFICATION TO
    lab.SensitiveCustomerData.BirthDate,
    lab.SensitiveCustomerData.NationalIDNumber
WITH
(
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Credentials',
    RANK = CRITICAL
);
GO

-- PARTE 3: inventário de todas as classificações do banco atual.
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS TableName,
    c.name AS ColumnName,
    sc.information_type,
    sc.label,
    sc.rank_desc
FROM sys.sensitivity_classifications AS sc
JOIN sys.objects AS o ON o.object_id = sc.major_id
JOIN sys.columns AS c
    ON c.object_id = sc.major_id
   AND c.column_id = sc.minor_id
ORDER BY SchemaName, TableName, ColumnName;
GO

-- PARTE 4: filtrar o inventário como uma consulta de conformidade.
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS TableName,
    c.name AS ColumnName,
    sc.information_type,
    sc.label,
    sc.rank_desc
FROM sys.sensitivity_classifications AS sc
JOIN sys.objects AS o ON o.object_id = sc.major_id
JOIN sys.columns AS c
    ON c.object_id = sc.major_id
   AND c.column_id = sc.minor_id
WHERE sc.label IN ('Confidential', 'Highly Confidential')
ORDER BY SchemaName, TableName, ColumnName;
GO

-- A classificação é somente metadado: os valores continuam sendo retornados.
SELECT * FROM lab.SensitiveCustomerData;
GO

-- PARTE 5: limpeza opcional em ambiente descartável.
-- Remova os comentários somente para apagar as classificações deste lab.
-- DROP SENSITIVITY CLASSIFICATION FROM lab.SensitiveCustomerData.EmailAddress;
-- DROP SENSITIVITY CLASSIFICATION FROM lab.SensitiveCustomerData.PhoneNumber;
-- DROP SENSITIVITY CLASSIFICATION FROM lab.SensitiveCustomerData.BirthDate;
-- DROP SENSITIVITY CLASSIFICATION FROM lab.SensitiveCustomerData.NationalIDNumber;
-- DROP TABLE lab.SensitiveCustomerData;
