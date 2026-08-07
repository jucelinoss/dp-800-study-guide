-- =================================================================================
-- DP-800 - LABORATÓRIO PRÁTICO: PROJETOS DE BANCO DE DADOS SQL, DACPAC E SQLCMD
-- =================================================================================
-- Banco: AdventureWorks2025 (ou qualquer banco descartável do SQL Server)
--
-- Este laboratório pode ser repetido: todos os objetos usam o schema lab e o script
-- remove somente os objetos criados por este exercício.
-- Ao executar pelo sqlcmd no Windows, preserve os acentos com: -f 65001
--
-- TEORIA:
-- ../../../certification/07-cicd-database-projects/02-sql-database-projects.md
--
-- MICROSOFT LEARN:
-- Scripts de pré/pós-implantação:
-- https://learn.microsoft.com/pt-br/sql/tools/sql-database-projects/concepts/pre-post-deployment-scripts?view=sql-server-ver17
-- Comandos sqlcmd (:r):
-- https://learn.microsoft.com/pt-br/sql/tools/sqlcmd/sqlcmd-commands?view=sql-server-ver17#r-filename
-- Instalação do AdventureWorks (opcional):
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================

USE AdventureWorks2025;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID(N'lab') IS NULL
    EXEC(N'CREATE SCHEMA lab');
GO

-- ---------------------------------------------------------------------------------
-- PARTE 0: RESET APENAS DOS OBJETOS DO LABORATÓRIO
-- ---------------------------------------------------------------------------------
DROP TABLE IF EXISTS lab.ReferenceCountries;
DROP TABLE IF EXISTS lab.ReferenceOrderStatus;
DROP TABLE IF EXISTS lab.__RefactorLog;
DROP TABLE IF EXISTS lab.MigratedCustomers;
DROP TABLE IF EXISTS lab.LegacyCustomers;
GO

-- ---------------------------------------------------------------------------------
-- PARTE 1: SIMULAR UMA MIGRAÇÃO DE DADOS DE PRÉ-IMPLANTAÇÃO
-- ---------------------------------------------------------------------------------
-- Um script de pré-implantação roda antes da aplicação do plano de implantação. O
-- plano é calculado antes da execução do pré-deploy; por isso, este é o lugar para
-- copiar valores que seriam perdidos por um rename/drop de coluna.

CREATE TABLE lab.LegacyCustomers
(
    CustomerID INT NOT NULL CONSTRAINT PK_LegacyCustomers PRIMARY KEY,
    FullContactName NVARCHAR(100) NOT NULL,
    LegacyCode VARCHAR(20) NULL
);

CREATE TABLE lab.MigratedCustomers
(
    CustomerID INT NOT NULL CONSTRAINT PK_MigratedCustomers PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Notes NVARCHAR(200) NULL
);
GO

INSERT INTO lab.LegacyCustomers (CustomerID, FullContactName, LegacyCode)
VALUES
    (1001, N'Alice Silva', 'LEG-1001'),
    (1002, N'Bob Santos', 'LEG-1002');
GO

-- Padrão idempotente de pré-deploy: executar este bloco duas vezes não duplica as
-- linhas migradas. Uma migração real também deve tratar nomes sem espaço e ser testada
-- com a distribuição real dos dados.
DECLARE @MigrationRows INT;

INSERT INTO lab.MigratedCustomers (CustomerID, FirstName, LastName, Notes)
SELECT
    l.CustomerID,
    LEFT(l.FullContactName, CHARINDEX(N' ', l.FullContactName + N' ') - 1),
    LTRIM(SUBSTRING(l.FullContactName, CHARINDEX(N' ', l.FullContactName + N' '), 100)),
    CONCAT(N'Migrado do código legado: ', l.LegacyCode)
FROM lab.LegacyCustomers AS l
WHERE l.LegacyCode IS NOT NULL
  AND NOT EXISTS
  (
      SELECT 1
      FROM lab.MigratedCustomers AS m
      WHERE m.CustomerID = l.CustomerID
  );

SET @MigrationRows = @@ROWCOUNT;
PRINT CONCAT(N'PRE-DEPLOYMENT: linhas migradas nesta execução = ', @MigrationRows);

-- Repita o mesmo bloco para provar que a segunda execução insere zero linhas.
INSERT INTO lab.MigratedCustomers (CustomerID, FirstName, LastName, Notes)
SELECT
    l.CustomerID,
    LEFT(l.FullContactName, CHARINDEX(N' ', l.FullContactName + N' ') - 1),
    LTRIM(SUBSTRING(l.FullContactName, CHARINDEX(N' ', l.FullContactName + N' '), 100)),
    CONCAT(N'Migrado do código legado: ', l.LegacyCode)
FROM lab.LegacyCustomers AS l
WHERE l.LegacyCode IS NOT NULL
  AND NOT EXISTS
  (
      SELECT 1
      FROM lab.MigratedCustomers AS m
      WHERE m.CustomerID = l.CustomerID
  );

PRINT CONCAT(N'PRE-DEPLOYMENT: linhas migradas na repetição = ', @@ROWCOUNT);
GO

SELECT CustomerID, FirstName, LastName, Notes
FROM lab.MigratedCustomers
ORDER BY CustomerID;
GO

-- ---------------------------------------------------------------------------------
-- PARTE 2: REFACTOR LOG E CHAVES DETERMINÍSTICAS DE OPERAÇÃO
-- ---------------------------------------------------------------------------------
-- O SQL Database Projects usa um refactor log para preservar renames feitos pelas
-- ferramentas do projeto. Esta tabela é apenas uma simulação didática; não crie nem
-- edite manualmente o refactor log real gerenciado pelo projeto.

CREATE TABLE lab.__RefactorLog
(
    OperationKey UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_lab_RefactorLog PRIMARY KEY,
    OperationDescription NVARCHAR(200) NOT NULL,
    AppliedAt DATETIME2(0) NOT NULL CONSTRAINT DF_lab_RefactorLog_AppliedAt DEFAULT SYSUTCDATETIME()
);
GO

DECLARE @OperationKey UNIQUEIDENTIFIER = '11111111-1111-1111-1111-111111111111';

IF NOT EXISTS
(
    SELECT 1
    FROM lab.__RefactorLog
    WHERE OperationKey = @OperationKey
)
BEGIN
    INSERT INTO lab.__RefactorLog (OperationKey, OperationDescription)
    VALUES (@OperationKey, N'Renomear o mapeamento LegacyCustomers.FullContactName');

    PRINT N'REFACTOR LOG: operação registrada.';
END
ELSE
    PRINT N'REFACTOR LOG: operação já registrada; nada a repetir.';
GO

-- ---------------------------------------------------------------------------------
-- PARTE 3: DADOS REFERENCIAIS DE PÓS-IMPLANTAÇÃO COM UPSERT IDEMPOTENTE
-- ---------------------------------------------------------------------------------
-- Um script de pós-implantação roda depois da conclusão do plano de implantação. Os
-- dados referenciais devem ser versionados com o projeto e carregados de modo seguro
-- para repetição.

CREATE TABLE lab.ReferenceOrderStatus
(
    StatusCode VARCHAR(20) NOT NULL CONSTRAINT PK_ReferenceOrderStatus PRIMARY KEY,
    StatusName NVARCHAR(100) NOT NULL,
    IsActive BIT NOT NULL
);

CREATE TABLE lab.ReferenceCountries
(
    CountryCode CHAR(2) NOT NULL CONSTRAINT PK_ReferenceCountries PRIMARY KEY,
    CountryName NVARCHAR(100) NOT NULL
);
GO

-- Este é o T-SQL que um arquivo de dados referenciado poderia conter.
UPDATE target
SET target.StatusName = source.StatusName,
    target.IsActive = source.IsActive
FROM lab.ReferenceOrderStatus AS target
JOIN
(
    VALUES
        ('NEW', N'Novo', CONVERT(BIT, 1)),
        ('CLOSED', N'Fechado', CONVERT(BIT, 1)),
        ('CANCELLED', N'Cancelado', CONVERT(BIT, 0))
) AS source(StatusCode, StatusName, IsActive)
    ON target.StatusCode = source.StatusCode;

INSERT INTO lab.ReferenceOrderStatus (StatusCode, StatusName, IsActive)
SELECT source.StatusCode, source.StatusName, source.IsActive
FROM
(
    VALUES
        ('NEW', N'Novo', CONVERT(BIT, 1)),
        ('CLOSED', N'Fechado', CONVERT(BIT, 1)),
        ('CANCELLED', N'Cancelado', CONVERT(BIT, 0))
) AS source(StatusCode, StatusName, IsActive)
WHERE NOT EXISTS
(
    SELECT 1
    FROM lab.ReferenceOrderStatus AS target
    WHERE target.StatusCode = source.StatusCode
);

INSERT INTO lab.ReferenceCountries (CountryCode, CountryName)
SELECT source.CountryCode, source.CountryName
FROM
(
    VALUES
        ('BR', N'Brasil'),
        ('US', N'Estados Unidos'),
        ('CA', N'Canadá')
) AS source(CountryCode, CountryName)
WHERE NOT EXISTS
(
    SELECT 1
    FROM lab.ReferenceCountries AS target
    WHERE target.CountryCode = source.CountryCode
);

PRINT N'POST-DEPLOYMENT: dados referenciais carregados sem chaves duplicadas.';
GO

SELECT StatusCode, StatusName, IsActive
FROM lab.ReferenceOrderStatus
ORDER BY StatusCode;

SELECT CountryCode, CountryName
FROM lab.ReferenceCountries
ORDER BY CountryCode;
GO

-- ---------------------------------------------------------------------------------
-- PARTE 4: COMO :r COMPÕE UM SCRIPT DE PÓS-IMPLANTAÇÃO
-- ---------------------------------------------------------------------------------
-- As linhas abaixo são comentários de propósito, para este laboratório rodar no modo
-- normal do SSMS. Para executá-las, crie os arquivos indicados e habilite Consulta >
-- Modo SQLCMD no SSMS (ou execute o script pai com sqlcmd).
--
-- Scripts/PostDeployment/PostDeployment.sql:
-- PRINT 'Post-deployment: carregando dados referenciais...';
-- :r .\..\..\Data\ReferenceData\dbo.OrderStatus.data.sql
-- :r .\..\..\Data\ReferenceData\dbo.Countries.data.sql
-- PRINT 'Post-deployment concluído.';
--
-- O :r é processado pelo sqlcmd antes que o SQL Server receba o lote. Os arquivos
-- referenciados são lidos em relação ao diretório de inicialização do sqlcmd e seus
-- conteúdos são inseridos na ordem. No .sqlproj, esses arquivos devem ser removidos
-- da compilação do modelo com Build Remove e podem permanecer visíveis como None.

-- ---------------------------------------------------------------------------------
-- PARTE 5: DACPAC, BACPAC E BAK — IDENTIFIQUE O ARTEFATO
-- ---------------------------------------------------------------------------------
SELECT Artefato, ContémSchema, ContémDadosDeUsuário, ImplantaçãoOuRestauração
FROM
(
    VALUES
        (N'DACPAC', N'Sim', N'Não', N'Implantação declarativa de schema / diff'),
        (N'BACPAC', N'Sim', N'Sim', N'Pacote de importação/exportação'),
        (N'BAK', N'Páginas e log conforme aplicável', N'Sim', N'Restauração física')
) AS artefatos(Artefato, ContémSchema, ContémDadosDeUsuário, ImplantaçãoOuRestauração);
GO

-- ---------------------------------------------------------------------------------
-- PARTE 6: AÇÕES DA CLI E GATES DE RELEASE
-- ---------------------------------------------------------------------------------
SELECT NomeDaAção, Objetivo, AlteraODestino
FROM
(
    VALUES
        (N'/Action:Build', N'Compilar e validar o projeto SQL', N'Não'),
        (N'/Action:Script', N'Gerar o T-SQL de implantação para revisão', N'Não'),
        (N'/Action:DeployReport', N'Gerar o relatório XML de implantação', N'Não'),
        (N'/Action:Publish', N'Aplicar a implantação da DACPAC', N'Sim')
) AS acoes(NomeDaAção, Objetivo, AlteraODestino);
GO

-- ---------------------------------------------------------------------------------
-- PARTE 7: ASSERTIONS AUTOMÁTICAS DO LABORATÓRIO
-- ---------------------------------------------------------------------------------
IF (SELECT COUNT(*) FROM lab.MigratedCustomers) <> 2
    THROW 51000, 'Eram esperados exatamente dois clientes migrados.', 1;

IF (SELECT COUNT(*) FROM lab.__RefactorLog) <> 1
    THROW 51001, 'Era esperada exatamente uma operação determinística de refactor.', 1;

IF (SELECT COUNT(*) FROM lab.ReferenceOrderStatus) <> 3
    THROW 51002, 'Eram esperados exatamente três status de pedido.', 1;

IF (SELECT COUNT(*) FROM lab.ReferenceCountries) <> 3
    THROW 51003, 'Eram esperados exatamente três países.', 1;

PRINT N'LABORATÓRIO APROVADO: migração, refactor log, dados referenciais e artefatos verificados.';
GO

-- A limpeza foi deixada como comando separado para você inspecionar as linhas.
-- Execute somente quando terminar:
-- DROP TABLE IF EXISTS lab.ReferenceCountries;
-- DROP TABLE IF EXISTS lab.ReferenceOrderStatus;
-- DROP TABLE IF EXISTS lab.__RefactorLog;
-- DROP TABLE IF EXISTS lab.MigratedCustomers;
-- DROP TABLE IF EXISTS lab.LegacyCustomers;
