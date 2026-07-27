-- =================================================================================
-- DP-800 - LAB PRÁTICO: PIPELINES DE DEPLOYMENT E COMANDOS SQLPACKAGE CLI
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o comportamento e automações dos pipelines de CI/CD para SQL Server:
--   1. Ações da CLI SqlPackage (/Action:Publish, /Action:Extract, /Action:Export, /Action:DeployReport)
--   2. Comparativo de Sinalizadores de Segurança por Ambiente (Dev, Staging e Produção)
--   3. Diagnóstico de Drift de Esquema usando Relatórios XML do SqlPackage
--   4. Autenticação Passwordless em Pipelines usando Managed Identity e Azure Key Vault
--   5. Cenários Práticos de Projeto (Simulação da Execução de Pipeline com Transações de Deploy)
-- =================================================================================

USE AdventureWorks2025;
GO

-- PARTE 4: GATES DE DEPLOYMENT DE REFERÊNCIA
SELECT 1 AS Etapa, N'Commit e validação de política de branch' AS Gate, N'Mudança versionada no projeto' AS Evidencia
UNION ALL SELECT 2, N'Build e validação do DACPAC', N'Build e modelo válidos'
UNION ALL SELECT 3, N'Testes e relatórios de drift/deploy', N'Artefatos de teste e relatório'
UNION ALL SELECT 4, N'Revisão de script e aprovações', N'Revisão de perda de dados e aprovação'
UNION ALL SELECT 5, N'Deploy e monitoração', N'Ambiente controlado e histórico de deploy';
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.PipelineDeployHistory;
GO

-- Estrutura para Registrar Histórico de Deploys de CI/CD
CREATE TABLE lab.PipelineDeployHistory (
    DeployID INT IDENTITY(1,1) PRIMARY KEY,
    EnvironmentName NVARCHAR(50) NOT NULL,
    DacpacVersion NVARCHAR(20) NOT NULL,
    DeployedBy NVARCHAR(100) NOT NULL DEFAULT SUSER_SNAME(),
    DeployDate DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
GO


-- =================================================================================
-- PARTE 1: VERBO DE AÇÃO E SINALIZADORES DA CLI SQLPACKAGE
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - /Action:Publish: Aplica o estado desejado do DACPAC calculando e executando a diferença (delta) no banco alvo.
--   - /Action:Extract: Gera um arquivo .dacpac (somente esquema) a partir de um banco existente.
--   - /Action:Export: Gera um arquivo .bacpac (esquema + dados) para migração/importação.
--   - /Action:DeployReport: Gera um relatório de alterações em XML sem modificar a base (ideal para detecção de Drift).
--   - /p:IncludeTransactionalScripts=true: Envolve toda a alteração de esquema em uma transação T-SQL com ROLLBACK automático em caso de erro.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Simular inserção de registro pós-publicação pelo pipeline
INSERT INTO lab.PipelineDeployHistory (EnvironmentName, DacpacVersion)
VALUES ('Production', 'v1.2.0');
GO

-- Consultar histórico de publicação
SELECT * FROM lab.PipelineDeployHistory;
GO


-- =================================================================================
-- PARTE 2: MATRIZ DE CONFIGURAÇÕES DE DEPLOYMENT POR AMBIENTE
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DESENVOLVIMENTO: Permissivo. `/p:BlockOnPossibleDataLoss=false`, `/p:DropObjectsNotInSource=true`.
--   - STAGING: Moderado. `/p:BlockOnPossibleDataLoss=true`, `/p:DropObjectsNotInSource=false`.
--   - PRODUÇÃO: Estrito. `/p:BlockOnPossibleDataLoss=true`, `/p:IncludeTransactionalScripts=true`, `/p:GenerateSmartDefaults=true`.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Exemplo de Matriz de Configuração para o Exame
SELECT 
    'Desenvolvimento' AS Ambiente,
    '/p:BlockOnPossibleDataLoss=false /p:DropObjectsNotInSource=true' AS FlagsSqlPackage,
    'Permite recriação e perda de dados de teste' AS Justificativa
UNION ALL
SELECT 
    'Staging / UAT',
    '/p:BlockOnPossibleDataLoss=true /p:DropObjectsNotInSource=false',
    'Bloqueia perda acidental e valida dados legados'
UNION ALL
SELECT 
    'Produção',
    '/p:BlockOnPossibleDataLoss=true /p:IncludeTransactionalScripts=true /p:GenerateSmartDefaults=true',
    'Garante rollback transacional em falhas e exige defaults para NOT NULL';
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Modelo de Script CLI para Execução de Publish de DACPAC via Azure Pipelines / GitHub Actions
-- Exemplo do comando exato executado em uma task do runner.

/*
# Executar a publicação em ambiente de Produção via PowerShell / Bash Runner:
sqlpackage /Action:Publish \
    /SourceFile:./bin/Release/AdventureWorks2025.dacpac \
    /TargetConnectionString:"Server=tcp:sql-prod.database.windows.net,1433;Initial Catalog=AdventureWorks2025;Authentication=Active Directory Managed Identity;" \
    /p:BlockOnPossibleDataLoss=true \
    /p:IncludeTransactionalScripts=true \
    /p:GenerateSmartDefaults=true
*/
GO
