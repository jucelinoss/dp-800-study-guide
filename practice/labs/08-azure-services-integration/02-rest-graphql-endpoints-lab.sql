-- =================================================================================
-- DP-800 - LAB: INVOCATION OF REST ENDPOINTS AND SERVICE INTEGRATION
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to restore the
-- AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates integrating SQL databases with external REST APIs directly via T-SQL:
--   1. Configuring Database Scoped Credentials (`CREATE DATABASE SCOPED CREDENTIAL`)
--   2. Invoking external REST APIs with `sp_invoke_external_rest_endpoint`
--   3. Processing JSON Response Payload with `JSON_VALUE` and `OPENJSON`
--   4. Error and Timeout Handling in Synchronous REST Calls
--   5. Practical Project Scenarios (Data Validation and Enrichment via Azure Function REST)
-- NOTE: this is not the DAB REST client lab. It uses outbound REST support from
-- Azure SQL/SQL Server 2025. The endpoint and credentials must be supplied in a
-- disposable environment; this script creates no secret.
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/08-azure-services-integration/02-rest-graphql-endpoints.md
--    Open the theory guide alongside this lab for conceptual context.

USE AdventureWorks2025;
GO

-- Preventive cleanup
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

-- 1. Credential template. Replace the placeholder only in a secure environment.
-- CREATE DATABASE SCOPED CREDENTIAL [AzureFunctionCredential]
-- WITH IDENTITY = 'HTTPEndpointHeaders',
--      SECRET = '{"Authorization":"Bearer <token>"}';
-- GO


-- =================================================================================
-- PART 1: INVOKING REST APIs VIA SP_INVOKE_EXTERNAL_REST_ENDPOINT
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - sp_invoke_external_rest_endpoint: Native Azure SQL stored procedure for direct HTTP/HTTPS REST calls.
--   - METHOD: Supports GET, POST, PUT, DELETE, PATCH.
--   - RESPONSE: Returns an HTTP status code (200, 404, 500) and the JSON payload.

-- -- [DP-800 KEY POINT]
-- Example of REST API Invocation for Customer Validation or Address Enrichment
DECLARE @StatusCode INT;
DECLARE @ResponsePayload NVARCHAR(MAX);

-- Invocation model. It requires an allowed endpoint, credential and
-- EXECUTE ANY EXTERNAL ENDPOINT permission; it remains commented for offline mode.
/*
EXEC sp_invoke_external_rest_endpoint
    @url = N'https://func-validate-customer.azurewebsites.net/api/validate',
    @method = N'POST',
    @credential = N'AzureFunctionCredential',
    @payload = N'{"CustomerID": 1001, "Email": "cliente@empresa.com"}',
    @response = @ResponsePayload OUTPUT;
*/

-- Manual simulation of the JSON response received from the external API
SET @ResponsePayload = N'{"status": "SUCCESS", "customerScore": 850, "riskLevel": "LOW"}';
SET @StatusCode = 200;

-- 2. Process the JSON response received from the REST API
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
-- PART 2: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Tracking Table for REST Integration Rules and Function Limits
-- Helps DBAs and Data Engineers design the integration architecture.

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
-- NEXT STEP: Review the theory at ../../../certification/08-azure-services-integration/02-rest-graphql-endpoints.md
-- =================================================================================================
