-- =================================================================================
-- DP-800 - LAB PRÁTICO: ENDPOINTS SEGUROS, FIREWALL E CREDENCIAIS DE ESCOPO
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/05-data-security-compliance/05-secure-endpoints.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o controle de acesso de rede e credenciais de escopo para chamadas externas:
--   1. Regras de Firewall no Nível de Banco de Dados (`sp_set_database_firewall_rule`)
--   2. Inspeção e Limpeza de Regras de Firewall via `sys.database_firewall_rules`
--   3. Criação de Database Scoped Credentials com Managed Identity
--   4. Simulação de Integração Externa via `sp_invoke_external_rest_endpoint` (Azure OpenAI REST)
--   5. Cenários Práticos de Projeto (Diferenciação de Private Endpoints vs Service Endpoints)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'AzureOpenAIManagedIdentity')
    DROP DATABASE SCOPED CREDENTIAL [AzureOpenAIManagedIdentity];

IF EXISTS (SELECT * FROM sys.database_firewall_rules WHERE name = N'LabDevMachineRule')
    EXEC sp_delete_database_firewall_rule @name = N'LabDevMachineRule';
GO


-- =================================================================================
-- PARTE 1: GERENCIAMENTO DE REGRAS DE FIREWALL EM NÍVEL DE BANCO DE DADOS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - FIREWALL DE BANCO: Define permissões de IP específicas para um banco de dados sem alterar o firewall do servidor inteiro.
--   - sp_set_database_firewall_rule: Adiciona ou atualiza uma regra de IP.
--   - sys.database_firewall_rules: Visão de catálogo para listar todas as regras ativas no banco.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Criar regra de firewall permitindo um IP de desenvolvimento específico
EXEC sp_set_database_firewall_rule
    @name = N'LabDevMachineRule',
    @start_ip_address = '203.0.113.10',
    @end_ip_address = '203.0.113.10';
GO

-- 2. Consultar regras ativas no banco de dados
SELECT 
    id,
    name AS NomeRegra,
    start_ip_address AS IPInicio,
    end_ip_address AS IPFim,
    create_date AS DataCriacao
FROM sys.database_firewall_rules;
GO


-- =================================================================================
-- PARTE 2: CREDENCIAIS DE ESCOPO DE BANCO DE DADOS PARA ENDPOINTS DE IA
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DATABASE SCOPED CREDENTIAL: Armazena referências de autenticação (Managed Identity ou API Key) para chamadas externas.
--   - sp_invoke_external_rest_endpoint: Permite invocar APIs REST externas diretamente de uma stored procedure.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Criar Credencial de Escopo para a Managed Identity sem necessidade de senha
CREATE DATABASE SCOPED CREDENTIAL [AzureOpenAIManagedIdentity]
WITH IDENTITY = 'Managed Identity';
GO

-- 2. Visualizar a credencial criada
SELECT 
    credential_id,
    name AS NomeCredencial,
    credential_identity AS IdentidadeUsada
FROM sys.database_scoped_credentials
WHERE name = 'AzureOpenAIManagedIdentity';
GO

-- Managed Identity não é credencial de API key. Para Azure OpenAI, o Learn documenta resourceid no SECRET; nunca inclua valor real em um script de lab.
-- Exemplo conceitual da chamada de IA REST endpoint
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
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz Comparativa de Arquitetura de Isolamento de Rede para DP-800
-- Escolha entre Private Endpoint vs Service Endpoint em cenários de conformidade.

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
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/05-data-security-compliance/05-secure-endpoints.md
-- =================================================================================================
