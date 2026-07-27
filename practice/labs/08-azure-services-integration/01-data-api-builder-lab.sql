-- =================================================================================
-- DP-800 - PRACTICAL LAB: DATA API BUILDER (DAB) AND MAPPING SQL OBJECTS TO REST/GRAPHQL
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- CONFIGURATION NOTE: To run this and other lab scripts, you need to
-- restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates preparing SQL objects for consumption by Data API Builder (DAB):
--   1. Structuring Views and Stored Procedures ready for exposure via DAB
--   2. Defining the `dab-config.json` configuration file (Mappings and Permissions)
--   3. Column Mapping (Renaming fields without changing the database via `"mappings"`)
--   4. Role-Based Security Configuration (`anonymous`, `authenticated`)
--   5. Practical Project Scenarios (DAB CLI commands `dab init`, `dab add`, `dab start`)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
DROP VIEW IF EXISTS lab.vw_DabProductCatalog;
DROP PROCEDURE IF EXISTS lab.usp_DabCreateOrder;
GO

-- 1. Optimized view for REST/GraphQL exposure via DAB
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

-- 2. Stored Procedure ready for exposure as a GraphQL Mutation or REST POST
CREATE PROCEDURE lab.usp_DabCreateOrder
    @CustomerID INT,
    @ProductID INT,
    @Quantity INT,
    @NewOrderID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Simulate record insertion
    SET @NewOrderID = SCOPE_IDENTITY();
    IF @NewOrderID IS NULL SET @NewOrderID = 10001;

    PRINT 'Pedido criado via DAB com Sucesso!';
END;
GO


-- =================================================================================
-- PART 1: DAB-CONFIG.JSON FILE STRUCTURE (T-SQL/JSON SIMULATION)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - dab-config.json: Central file read by the DAB engine. Does not require writing C# or Node.js code.
--   - SECURITY: Connection credentials use `@env('DATABASE_CONNECTION_STRING')` to avoid password exposure.

-- -- [DP-800 KEY POINT]
-- Example DAB Configuration JSON generated for the Product Catalog
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
-- PART 2: PRACTICAL PROJECT SCENARIOS (DAB CLI)
-- =================================================================================

--- SCENARIO 1: DAB CLI Command Sequence for Initialization
-- Demonstrates how the objects created above are registered using the DAB command line.

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

-- SCENARIO 2: Secret reference belongs to the deployment layer.
-- DAB reads @env(...) from its environment/configuration. Azure Container Apps
-- maps a stored secret into that environment variable with secretref:.
SELECT
    N'DAB config or dab init' AS LayerName,
    N'@env(''MSSQL_CONNECTION_STRING'')' AS CorrectReference,
    N'DAB reads the environment variable; do not hardcode a credential' AS Meaning
UNION ALL
SELECT
    N'Azure Container Apps environment',
    N'DATABASE_CONNECTION_STRING=secretref:connection-string',
    N'Container Apps injects the secret into the environment variable';
GO
