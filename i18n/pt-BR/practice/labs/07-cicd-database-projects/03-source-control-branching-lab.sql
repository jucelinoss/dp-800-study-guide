-- =================================================================================
-- DP-800 - LAB PRÁTICO: GOVERNAÇA DE CÓDIGO E VALIDAÇÃO DE DRIFT DE ESQUEMA
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o controle de alterações e governança de esquemas no Git/CI-CD:
--   1. Simulação de Breaking Changes em Pull Requests (Adição de coluna NOT NULL sem DEFAULT)
--   2. Padrão Retrocompatível para Pull Requests (Adição de NOT NULL com DEFAULT)
--   3. Detecção de Schema Drift (Alterações manuais não rastreadas no repositório)
--   4. Estruturação de regras de CODEOWNERS para revisão de DBAs
--   5. Cenários Práticos de Projeto (Auditoria de Objetos Modificados fora do Pipeline de CI/CD)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.OrdersBranchingTest;
GO

-- Estrutura de Tabela para Teste
CREATE TABLE lab.OrdersBranchingTest (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL,
    CreateDate DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
GO

INSERT INTO lab.OrdersBranchingTest (CustomerID, TotalAmount) VALUES (101, 250.00);
GO


-- =================================================================================
-- PARTE 1: VALIDAÇÃO DE PULL REQUEST - BREAKING CHANGES VS PADRÃO COMPATÍVEL
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - INCOMPATÍVEL: Adicionar uma nova coluna `NOT NULL` em uma tabela populada sem fornecer um valor `DEFAULT`.
--     O deploy do DACPAC falhará com a chave `BlockOnPossibleDataLoss=true`.
--   - COMPATÍVEL: Adicionar a coluna `NOT NULL` juntamente com um valor `DEFAULT` (ex: `DEFAULT 'Pending'`).

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Exemplo de Alteração Incompatível (Comentado pois quebraria o script):
-- ALTER TABLE lab.OrdersBranchingTest ADD OrderStatus NVARCHAR(20) NOT NULL; -- FALHA!

-- 2. Padrão Seguro e Retrocompatível para PRs:
ALTER TABLE lab.OrdersBranchingTest 
ADD OrderStatus NVARCHAR(20) NOT NULL 
    CONSTRAINT DF_OrdersBranchingTest_OrderStatus DEFAULT N'Pending';
GO

-- Verificar se a nova coluna recebeu o valor default para os registros pré-existentes
SELECT * FROM lab.OrdersBranchingTest;
GO


-- =================================================================================
-- PARTE 2: DETECÇÃO DE SCHEMA DRIFT (ALTERAÇÕES AD-HOC NÃO RASTREADAS)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - SCHEMA DRIFT: Ocorre quando um desenvolvedor ou DBA faz um `ALTER` diretamente no banco de produção
--     sem passar pelo Git / DACPAC.
--   - DETECÇÃO: DMVs de data de modificação (`sys.objects.modify_date`) indicam se houve alterações recentes.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Consultar objetos alterados recentemente que possam indicar Schema Drift
SELECT 
    name AS NomeObjeto,
    type_desc AS TipoObjeto,
    create_date AS DataCriacao,
    modify_date AS UltimaModificacao
FROM sys.objects
WHERE schema_id = SCHEMA_ID('lab')
  AND DATEDIFF(DAY, modify_date, GETDATE()) <= 1
ORDER BY modify_date DESC;
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Modelo de Arquivo CODEOWNERS para Governança do Repositório de Banco de Dados
-- Define quais equipes devem obrigatoriamente revisar Pull Requests de alterações de esquema.

SELECT 
    '*.sql' AS MascaraArquivo,
    '@dba-team' AS RevisorObrigatorio,
    'Revisao obrigatoria para qualquer instrucao SQL' AS ObjetivoGovernanca
UNION ALL
SELECT 
    '/src/MyDatabase/Schema/Security/*',
    '@security-team',
    'Aprovacao obrigatoria do time de seguranca para mudancas em roles/permissoes'
UNION ALL
SELECT 
    '/src/MyDatabase/Scripts/*',
    '@senior-dba-team',
    'Aprovacao de DBAs Seniores para scripts Pre/Post Deployment';
GO
