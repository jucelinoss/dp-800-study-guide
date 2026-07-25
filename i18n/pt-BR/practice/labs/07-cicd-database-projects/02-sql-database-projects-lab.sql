-- =================================================================================
-- DP-800 - LAB PRÁTICO: PROJETOS DE BANCO DE DADOS SQL (.SQLPROJ E ARTEFATOS DACPAC)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a estrutura e comportamento de implantação declarativa de um .sqlproj:
--   1. Diferença entre Artefato de Esquema (.dacpac) vs Esquema + Dados (.bacpac)
--   2. Padrão de Scripts Pre-Deployment (Preservação/Migração de dados antes do alter do DACPAC)
--   3. Padrão de Scripts Post-Deployment (Carga de dados estáticos e permissões após o DACPAC)
--   4. Rastreamento de Refatoração de Nomes via Tabela de Log (`__RefactorLog`)
--   5. Cenários Práticos de Projeto (Simulação de Ações de Proteção contra Perda de Dados em CI/CD)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.__RefactorLog;
DROP TABLE IF EXISTS lab.LegacyCustomers;
DROP TABLE IF EXISTS lab.MigratedCustomers;
GO

-- Estrutura para simular a tabela de Refatoração do SQL Database Projects
CREATE TABLE lab.__RefactorLog (
    OperationKey UNIQUEIDENTIFIER NOT NULL PRIMARY KEY
);

-- Estrutura de Tabela Antiga para Teste de Migração Pre-Deployment
CREATE TABLE lab.LegacyCustomers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FullContactName NVARCHAR(100) NOT NULL,
    LegacyCode VARCHAR(20) NULL
);

CREATE TABLE lab.MigratedCustomers (
    CustomerID INT PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Notes NVARCHAR(200) NULL
);
GO

INSERT INTO lab.LegacyCustomers (FullContactName, LegacyCode) VALUES 
('Alice Silva', 'LEG-1001'),
('Bob Santos', 'LEG-1002');
GO


-- =================================================================================
-- PARTE 1: PADRÃO DE SCRIPT PRE-DEPLOYMENT (PRESERVAÇÃO ANTES DA ALTERAÇÃO)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PRE-DEPLOYMENT SCRIPT: Executado pelo SqlPackage ANTES da comparação e aplicação do DACPAC.
--   - USO TÍPICO: Migrar dados de colunas que serão excluídas/renomeadas para evitar erro `BlockOnPossibleDataLoss=true`.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Simulação de Script Pre-Deployment: Copiar dados da tabela legada antes de a coluna ser dropada pelo DACPAC
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('lab.LegacyCustomers') AND name = 'LegacyCode')
BEGIN
    PRINT 'PRE-DEPLOYMENT: Migrando dados da coluna LegacyCode antes do DACPAC aplicar o DROP...';

    INSERT INTO lab.MigratedCustomers (CustomerID, FirstName, LastName, Notes)
    SELECT 
        CustomerID,
        SUBSTRING(FullContactName, 1, CHARINDEX(' ', FullContactName) - 1),
        SUBSTRING(FullContactName, CHARINDEX(' ', FullContactName) + 1, LEN(FullContactName)),
        CONCAT('Migrado do codigo antigo: ', LegacyCode)
    FROM lab.LegacyCustomers;
END
GO

-- Validar dados preservados no Pre-Deployment
SELECT * FROM lab.MigratedCustomers;
GO


-- =================================================================================
-- PARTE 2: REFACTORLOG E EVITANDO RE-EXECUÇÕES REPETIDAS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - __RefactorLog: Tabela do sistema mantida pelo DACPAC para registrar renomeações de objetos via IDE.
--     Evita que o SqlPackage interprete uma renomeação como um DROP TABLE seguido de CREATE TABLE.

-- -- [PONTO DE ATENÇÃO DP-800]
DECLARE @RefactorGuid UNIQUEIDENTIFIER = NEWID();

IF NOT EXISTS (SELECT 1 FROM lab.__RefactorLog WHERE OperationKey = @RefactorGuid)
BEGIN
    INSERT INTO lab.__RefactorLog (OperationKey) VALUES (@RefactorGuid);
    PRINT 'REFACTORLOG: Operacao de renomeacao gravada com sucesso.';
END
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz de Parâmetros da CLI SqlPackage para Pipelines de CI/CD
-- Utilizado por engenheiros de dados para configurar a publicação segura de DACPACs em staging e produção.

SELECT 
    'SqlPackage /Action:Publish' AS ComandoCLI,
    'Deploys da diferença entre DACPAC e banco alvo' AS DescricaoAcao,
    'BlockOnPossibleDataLoss=true' AS ParametroSegurancaCritical,
    'Aborta o deploy se houver DROP de colunas com dados' AS EfeitoParametro
UNION ALL
SELECT 
    'SqlPackage /Action:DeployReport',
    'Gera um relatório XML de alterações sem alterar o banco',
    'TargetFile: drift-report.xml',
    'Usado para aprovação de PRs e validação de Drift'
UNION ALL
SELECT 
    'SqlPackage /Action:Script',
    'Gera o script T-SQL resultante do DACPAC',
    'OutputPath: ./deploy.sql',
    'Recomendado para revisão por DBAs em ambientes estritos';
GO
