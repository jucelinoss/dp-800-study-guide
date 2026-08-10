-- =================================================================================
-- DP-800 - LAB PRÁTICO: INVOCAÇÃO DE ENDPOINTS REST E INTEGRAÇÃO DE SERVIÇOS
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a integração de bancos SQL com APIs REST externas diretamente via T-SQL:
--   1. Configuração de Credenciais de Escopo (`CREATE DATABASE SCOPED CREDENTIAL`)
--   2. Invocação de APIs REST externas com `sp_invoke_external_rest_endpoint`
--   3. Processamento do Payload de Resposta JSON com a função `JSON_VALUE` e `OPENJSON`
--   4. Tratamento de Erros e Timeouts em Chamadas REST síncronas
--   5. Cenários Práticos de Projeto (Validação e Enriquecimento de Dados via Azure Function REST)
-- ATENÇÃO: este lab não é o cliente REST do DAB. Ele usa a capacidade de saída
-- do Azure SQL/SQL Server 2025. O endpoint e as credenciais devem ser fornecidos
-- em um ambiente descartável; nenhum segredo é criado por este script.
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/08-azure-services-integration/02-rest-graphql-endpoints.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'AzureFunctionCredential')
    DROP DATABASE SCOPED CREDENTIAL [AzureFunctionCredential];

DROP TABLE IF EXISTS lab.CustomerValidationLog;
GO

CREATE TABLE lab.CustomerValidationLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    ValidationResult NVARCHAR(100) NOT NULL,
    ValidatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
GO

-- 1. Modelo de credencial. Substitua o placeholder somente em ambiente seguro.
-- CREATE DATABASE SCOPED CREDENTIAL [AzureFunctionCredential]
-- WITH IDENTITY = 'HTTPEndpointHeaders',
--      SECRET = '{"Authorization":"Bearer <token>"}';
-- GO


-- =================================================================================
-- PARTE 1: INVOCANDO APIs REST VIA SP_INVOKE_EXTERNAL_REST_ENDPOINT
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - sp_invoke_external_rest_endpoint: Stored Procedure nativa do Azure SQL que permite chamadas diretas HTTP/HTTPS REST.
--   - MÉTODO: Suporta GET, POST, PUT, DELETE, PATCH.
--   - RESPOSTA: Retorna um código de status HTTP (200, 404, 500) e o payload em JSON.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Exemplo de Invocação de API REST para Validação de CPF/CNPJ ou Enriquecimento de Endereço
DECLARE @StatusCode INT;
DECLARE @ResponsePayload NVARCHAR(MAX);

-- Modelo de invocação. Requer endpoint permitido, credencial e permissão
-- EXECUTE ANY EXTERNAL ENDPOINT; permanece comentado para o modo offline.
/*
EXEC sp_invoke_external_rest_endpoint
    @url = N'https://func-validate-customer.azurewebsites.net/api/validate',
    @method = N'POST',
    @credential = N'AzureFunctionCredential',
    @payload = N'{"CustomerID": 1001, "Email": "cliente@empresa.com"}',
    @response = @ResponsePayload OUTPUT;
*/

-- Simulação manual da resposta JSON recebida da API externa
SET @ResponsePayload = N'{"status": "SUCCESS", "customerScore": 850, "riskLevel": "LOW"}';
SET @StatusCode = 200;

-- 2. Processar a resposta JSON recebida da API REST
IF @StatusCode = 200
BEGIN
    DECLARE @Score INT = CAST(JSON_VALUE(@ResponsePayload, '$.customerScore') AS INT);
    DECLARE @Risk NVARCHAR(20) = JSON_VALUE(@ResponsePayload, '$.riskLevel');

    INSERT INTO lab.CustomerValidationLog (CustomerID, ValidationResult)
    VALUES (1001, CONCAT('Aprovado - Score: ', @Score, ' Risk: ', @Risk));

    PRINT 'Integracao REST executada com sucesso e dados gravados!';
END
GO

SELECT * FROM lab.CustomerValidationLog;
GO


-- =================================================================================
-- PARTE 2: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Tabela de Rastreamento das Regras de Integração REST e Limites da Função
-- Auxilia DBAs e Engenheiros de Dados no desenho da arquitetura de integração.

SELECT 
    'sp_invoke_external_rest_endpoint' AS Recurso,
    'Sincrona (Bloqueia até resposta da API)' AS ModeloExecucao,
    'Azure SQL Database / Managed Instance' AS PlataformasSuportadas,
    'Usar em transacoes curtas para evitar lockings prolongados' AS RecomendacaoPerformance
UNION ALL
SELECT 
    'Azure Data Factory / Event Grid',
    'Assincrona (Event-driven)',
    'Todas as plataformas Azure',
    'Recomendado para alto volume e chamadas de lote (>1000/min)';
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/08-azure-services-integration/02-rest-graphql-endpoints.md
-- =================================================================================================
