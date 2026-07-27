-- =================================================================================
-- DP-800 - LAB PRÁTICO: DATA API BUILDER (DAB) E MAPEAMENTO DE OBJETOS SQL PARA REST/GRAPHQL
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a preparação de objetos SQL para consumo pelo Data API Builder (DAB):
--   1. Estruturação de Views e Stored Procedures prontas para exposição via DAB
--   2. Definição do arquivo de configuração `dab-config.json` (Mapeamentos e Permissões)
--   3. Mapeamento de Colunas (Renomeação de campos sem alterar o banco via `"mappings"`)
--   4. Configuração de Segurança por Papel (`anonymous`, `authenticated`)
--   5. Cenários Práticos de Projeto (Comandos da CLI DAB `dab init`, `dab add`, `dab start`)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP VIEW IF EXISTS lab.vw_DabProductCatalog;
DROP PROCEDURE IF EXISTS lab.usp_DabCreateOrder;
GO

-- 1. View otimizada para exposição REST/GraphQL via DAB
CREATE VIEW lab.vw_DabProductCatalog
AS
SELECT 
    ProductID AS ItemID,
    Name AS ItemName,
    ProductNumber AS SKU,
    ListPrice AS Price,
    ModifiedDate AS LastUpdated
FROM SalesLT.Product;
GO

-- 2. Stored Procedure pronta para exposição como Mutation no GraphQL ou POST no REST
CREATE PROCEDURE lab.usp_DabCreateOrder
    @CustomerID INT,
    @ProductID INT,
    @Quantity INT,
    @NewOrderID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Simulação de gravação
    SET @NewOrderID = SCOPE_IDENTITY();
    IF @NewOrderID IS NULL SET @NewOrderID = 10001;

    PRINT 'Pedido criado via DAB com Sucesso!';
END;
GO


-- =================================================================================
-- PARTE 1: ESTRUTURA DO ARQUIVO DAB-CONFIG.JSON (SIMULAÇÃO T-SQL/JSON)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - dab-config.json: Arquivo central lido pelo mecanismo do DAB. Não requer escrita de código C# ou Node.js.
--   - SEGURANÇA: Credenciais de conexão usam `@env('DATABASE_CONNECTION_STRING')` para evitar exposição de senhas.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Exemplo de JSON de Configuração do DAB gerado para o Catálogo de Produtos
SELECT N'{
  "data-source": {
    "database-type": "mssql",
    "connection-string": "@env(''DATABASE_CONNECTION_STRING'')"
  },
  "entities": {
    "ProductCatalog": {
      "source": {
        "object": "lab.vw_DabProductCatalog",
        "type": "view",
        "key-fields": ["ItemID"]
      },
      "mappings": {
        "ItemID": "id",
        "ItemName": "name",
        "Price": "unitPrice"
      },
      "permissions": [
        { "role": "anonymous", "actions": ["read"] },
        { "role": "authenticated", "actions": ["read"] }
      ]
    },
    "CreateOrder": {
      "source": {
        "object": "lab.usp_DabCreateOrder",
        "type": "stored-procedure"
      },
      "permissions": [
        { "role": "authenticated", "actions": ["execute"] }
      ]
    }
  }
}' AS DabConfigurationJson;
GO


-- =================================================================================
-- PARTE 2: CENÁRIOS PRÁTICOS DE PROJETO (CLI DO DAB)
-- =================================================================================

--- CENÁRIO 1: Sequência de Comandos da CLI do DAB para Inicialização
-- Demonstra como os objetos criados acima são registrados usando a linha de comando do DAB.

SELECT 
    'dab init --database-type mssql --connection-string "@env(''DATABASE_CONNECTION_STRING'')" --config dab-config.json' AS ComandoCLI,
    'Inicializa o arquivo de configuracao central do Data API Builder' AS Finalidade
UNION ALL
SELECT 
    'dab add ProductCatalog --source lab.vw_DabProductCatalog --source.type view --source.key-fields ItemID --permissions "anonymous:read"',
    'Expoe a view como um endpoint REST (/api/ProductCatalog) e GraphQL'
UNION ALL
SELECT 
    'dab add CreateOrder --source lab.usp_DabCreateOrder --source.type stored-procedure --permissions "authenticated:execute"',
    'Expoe a stored procedure como uma mutation GraphQL e POST REST'
UNION ALL
SELECT 
    'dab start --config dab-config.json',
    'Inicia o servidor runtime do DAB escutando as requisicoes HTTP';
GO

--- CENÁRIO 2: Referência de segredo por camada
SELECT N'Configuração DAB ou dab init' AS Camada, N'@env(''MSSQL_CONNECTION_STRING'')' AS ReferenciaCorreta, N'DAB lê a variável de ambiente; não codifique credenciais' AS Significado
UNION ALL
SELECT N'Ambiente do Azure Container Apps', N'DATABASE_CONNECTION_STRING=secretref:connection-string', N'Container Apps injeta o segredo na variável de ambiente';
GO
