-- =================================================================================
-- DP-800 - LAB PRÁTICO: ESTRATÉGIA DE TESTES E DADOS DE REFERÊNCIA (TSQLT E MERGE)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra estratégias de testes unitários e carga de dados de referência.
--   1. Preparação do Ambiente para tSQLt (Configuração de CLR)
--   2. Estruturação real de uma classe de testes tSQLt
--   3. Isolamento com FakeTable, AssertEquals e ExpectException
--   4. Carga Idempotente de Dados de Referência com a Instrução MERGE
--   5. Cenários Práticos de Projeto (Carga de Tabelas de Domínio em Scripts Post-Deployment)
-- =================================================================================
-- REFERENCIA TEORICA: ../../../certification/07-cicd-database-projects/01-testing-strategy.md
--    Abra o guia teorico junto com este laboratorio para contexto conceitual.

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.ReferenceOrderStatus;
DROP TABLE IF EXISTS lab.TestOrders;
GO

-- Estrutura de Tabelas para Teste
CREATE TABLE lab.ReferenceOrderStatus (
    StatusID INT PRIMARY KEY,
    StatusName NVARCHAR(50) NOT NULL,
    Description NVARCHAR(200) NULL
);

CREATE TABLE lab.TestOrders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    TotalAmount DECIMAL(18,2) NOT NULL,
    StatusID INT NOT NULL
);
GO


-- =================================================================================
-- PARTE 1: PRÉ-REQUISITOS E PREPARAÇÃO PARA O FRAMEWORK TSQLT
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - tSQLt: Framework nativo de testes unitários em T-SQL.
--   - ISOLAMENTO: Todos os testes do tSQLt executam dentro de transações que sofrem ROLLBACK automático ao final!
--   - PRÉ-REQUISITOS: Requer `clr enabled = 1` e a instalação/confiabilidade da assembly
--     do tSQLt conforme a documentação oficial. TRUSTWORTHY ON não é habilitado aqui.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Habilitar execução de CLR no SQL Server
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;
GO

-- Instale o tSQLt antes de continuar:
-- https://tsqlt.org/download/
IF OBJECT_ID(N'tSQLt.Run') IS NULL
    THROW 51010, 'tSQLt não está instalado neste banco. Instale o framework e execute novamente.', 1;
GO


-- =================================================================================
-- PARTE 2: SIMULAÇÃO DE ESTRUTURA DE TESTE UNITÁRIO (ISOLAMENTO E ASSERÇÃO)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - tSQLt.FakeTable: Substitui uma tabela real por uma cópia vazia sem constraints ou chaves estrangeiras.
--     Isso isola a unidade de teste impedindo falhas em cascata por dependência de dados.
--   - tSQLt.AssertEquals: Valida se o resultado obtido é idêntico ao valor esperado.

-- Exemplo de procedimento sob teste
CREATE OR ALTER PROCEDURE lab.usp_CalculateDiscountedTotal
    @TotalAmount DECIMAL(18,2),
    @DiscountPercent DECIMAL(5,2),
    @FinalAmount DECIMAL(18,2) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @DiscountPercent > 50.00
        THROW 50002, 'Desconto maximo permitido e de 50%.', 1;

    SET @FinalAmount = @TotalAmount * (1.0 - (@DiscountPercent / 100.0));
END;
GO

-- Criar uma classe de testes tSQLt. O IF torna a execução repetível.
IF SCHEMA_ID(N'labDiscountTests') IS NULL
    EXEC tSQLt.NewTestClass N'labDiscountTests';
GO

CREATE OR ALTER PROCEDURE [labDiscountTests].[test desconto valido retorna 90]
AS
BEGIN
    DECLARE @ResultadoCalculado DECIMAL(18,2);

    EXEC lab.usp_CalculateDiscountedTotal
        @TotalAmount = 100.00,
        @DiscountPercent = 10.00,
        @FinalAmount = @ResultadoCalculado OUTPUT;

    EXEC tSQLt.AssertEquals 90.00, @ResultadoCalculado;
END;
GO

CREATE OR ALTER PROCEDURE [labDiscountTests].[test desconto acima do limite gera excecao]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExpectedMessagePattern = N'%Desconto maximo%';

    EXEC lab.usp_CalculateDiscountedTotal
        @TotalAmount = 100.00,
        @DiscountPercent = 60.00,
        @FinalAmount = NULL;
END;
GO

-- Execute os testes reais. O rollback automático do tSQLt isola cada caso.
EXEC tSQLt.Run N'labDiscountTests';
GO


-- =================================================================================
-- PARTE 3: CARGA IDEMPOTENTE DE DADOS DE REFERÊNCIA COM MERGE
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DADOS EÁTICOS / REFERÊNCIA: Tabelas de domínio (ex: Status, Países, Moedas) devem ser mantidas via script versionado.
--   - PADRÃO MERGE: Garante a idempotência. Pode ser re-executado N vezes no Post-Deployment sem duplicar ou falhar.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Carga Idempotente de Status de Pedido via MERGE
MERGE INTO lab.ReferenceOrderStatus AS Target
USING (VALUES
    (1, N'Pendente',   N'Pedido recebido aguardando pagamento'),
    (2, N'Processando', N'Pagamento aprovado em separacao'),
    (3, N'Enviado',     N'Pedido entregue a transportadora'),
    (4, N'Concluido',   N'Pedido entregue ao cliente final')
) AS Source (StatusID, StatusName, Description)
ON Target.StatusID = Source.StatusID
WHEN MATCHED THEN
    UPDATE SET 
        Target.StatusName = Source.StatusName,
        Target.Description = Source.Description
WHEN NOT MATCHED BY TARGET THEN
    INSERT (StatusID, StatusName, Description)
    VALUES (Source.StatusID, Source.StatusName, Source.Description);
GO

-- Verificar resultado da carga idempotente
SELECT * FROM lab.ReferenceOrderStatus;
GO


-- =================================================================================
-- PARTE 4: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Estruturação de Script Post-Deployment para Pipelines de CI/CD
-- Simula o script de automação executado após a publicação do DACPAC para atualizar dados de referência.

PRINT 'Iniciando execucao de Post-Deployment scripts...';
PRINT 'Carga de tabelas de dominio finalizada com sucesso.';
GO

-- =================================================================================================
-- PROXIMO PASSO: Revise a teoria em ../../../certification/07-cicd-database-projects/01-testing-strategy.md
-- =================================================================================================
