-- =================================================================================
-- DP-800 - PRACTICAL LAB: SECURE ENDPOINTS, FIREWALL, AND SCOPED CREDENTIALS
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/05-data-security-compliance/05-secure-endpoints.md
--    Open the theory guide alongside this lab for conceptual context.
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need to restore the
-- AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates network access control and scoped credentials for external calls:
--   1. Database-Level Firewall Rules (`sp_set_database_firewall_rule`)
--   2. Inspecting and Cleaning Firewall Rules via `sys.database_firewall_rules`
--   3. Creating Database Scoped Credentials with Managed Identity
--   4. External Integration Simulation via `sp_invoke_external_rest_endpoint` (Azure OpenAI REST)
--   5. Practical Project Scenarios (Private Endpoints vs Service Endpoints)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'AzureOpenAIManagedIdentity')
    DROP DATABASE SCOPED CREDENTIAL [AzureOpenAIManagedIdentity];

IF EXISTS (SELECT * FROM sys.database_firewall_rules WHERE name = N'LabDevMachineRule')
    EXEC sp_delete_database_firewall_rule @name = N'LabDevMachineRule';
GO


-- =================================================================================
-- PART 1: MANAGING DATABASE-LEVEL FIREWALL RULES
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DATABASE FIREWALL: Defines specific IP permissions for a database without altering the entire server firewall.
--   - sp_set_database_firewall_rule: Adds or updates an IP rule.
--   - sys.database_firewall_rules: Catalog view listing all active rules in the database.

-- -- [DP-800 EXAM TIP]
-- 1. Create a firewall rule allowing a specific development IP
EXEC sp_set_database_firewall_rule
    @name = N'LabDevMachineRule',
    @start_ip_address = '203.0.113.10',
    @end_ip_address = '203.0.113.10';
GO

-- 2. Query active rules in the database
SELECT 
    id,
    name AS NomeRegra,
    start_ip_address AS IPInicio,
    end_ip_address AS IPFim,
    create_date AS DataCriacao
FROM sys.database_firewall_rules;
GO


-- =================================================================================
-- PART 2: DATABASE SCOPED CREDENTIALS FOR AI ENDPOINTS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - DATABASE SCOPED CREDENTIAL: Stores authentication references (Managed Identity or API Key) for external calls.
--   - sp_invoke_external_rest_endpoint: Allows invoking external REST APIs directly from a stored procedure.

-- -- [DP-800 EXAM TIP]
-- 1. Create a Scoped Credential for Managed Identity without password
CREATE DATABASE SCOPED CREDENTIAL [AzureOpenAIManagedIdentity]
WITH IDENTITY = 'Managed Identity';
GO

-- 2. View the created credential
SELECT 
    credential_id,
    name AS NomeCredencial,
    credential_identity AS IdentidadeUsada
FROM sys.database_scoped_credentials
WHERE name = 'AzureOpenAIManagedIdentity';
GO

-- Conceptual example of AI REST endpoint call
-- Managed Identity is not an API-key credential. For Azure OpenAI, Learn documents
-- the resource identifier in SECRET; do not place a real value in a lab script.
/*
CREATE DATABASE SCOPED CREDENTIAL [https://contoso.openai.azure.com]
WITH IDENTITY = 'Managed Identity',
     SECRET = '{"resourceid":"https://cognitiveservices.azure.com"}';

GRANT REFERENCES ON DATABASE SCOPED CREDENTIAL::[https://contoso.openai.azure.com]
    TO AppRole;

DECLARE @response NVARCHAR(MAX);
EXEC sp_invoke_external_rest_endpoint
    @url = 'https://meuseguro.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-01',
    @method = 'POST',
    @credential = [AzureOpenAIManagedIdentity],
    @payload = N'{"messages":[{"role":"user","content":"Otimize uma instrução SQL"}]}',
    @response = @response OUTPUT;
*/
GO


-- =================================================================================
-- PART 3: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Comparative Matrix of Network Isolation Architecture for DP-800
-- Choose between Private Endpoint vs Service Endpoint in compliance scenarios.

SELECT 
    'Private Endpoint (Azure Private Link)' AS TipoTecnologia,
    'Atribui IP Privado na VNet do cliente' AS MecanismoRede,
    'SIM (Desabilita endpoint público)' AS BloqueiaAcessoInternet,
    'Recomendado para Produção e Altíssima Segurança' AS CasoDeUso
UNION ALL
SELECT 
    'Service Endpoint',
    'Otimiza tráfego no backbone da Azure',
    'NÃO (Endpoint Público continua ativo)',
    'Abordagem legada; reduz latência mas exige regras de firewall';
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/05-data-security-compliance/05-secure-endpoints.md
-- =================================================================================================
