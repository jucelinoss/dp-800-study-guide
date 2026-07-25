-- =================================================================================
-- DP-800 - LAB PRÁTICO: MODELOS EXTERNOS DE IA (CREATE EXTERNAL MODEL E PREDICT)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a integração de modelos de IA (Azure OpenAI) como objetos do banco de dados:
--   1. Criação de Credenciais de Escopo (`CREATE DATABASE SCOPED CREDENTIAL`)
--   2. Registro de Modelos Externos (`CREATE EXTERNAL MODEL`) para Embeddings e Completions
--   3. Invocação via Função `PREDICT(MODEL = ..., DATA = ...)`
--   4. Gerenciamento de Permissões de Uso (`GRANT EXECUTE ON EXTERNAL MODEL`)
--   5. Cenários Práticos de Projeto (Armazenamento de Vetores de 1536 dimensões)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'AzureOpenAI_Embedding_Small')
    DROP EXTERNAL MODEL [AzureOpenAI_Embedding_Small];

IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'AzureOpenAIApiKeyCred')
    DROP DATABASE SCOPED CREDENTIAL [AzureOpenAIApiKeyCred];

DROP TABLE IF EXISTS lab.ProductEmbeddings;
GO

-- Estrutura de Tabela para Armazenamento de Vetores
CREATE TABLE lab.ProductEmbeddings (
    ProductID INT PRIMARY KEY,
    ProductDescription NVARCHAR(MAX) NOT NULL,
    EmbeddingVector NVARCHAR(MAX) NULL -- Armazena o vetor de 1536 dimensões serializado em JSON
);
GO

INSERT INTO lab.ProductEmbeddings (ProductID, ProductDescription) VALUES
(1, N'Capacete de ciclismo leve com alta protecao contra impactos'),
(2, N'Bicicleta de montanha com 24 marchas e suspensao dupla');
GO


-- =================================================================================
-- PARTE 1: REGISTRO DE MODELO EXTERNO E CREDENCIAL DE ESCOPO
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CREATE EXTERNAL MODEL: Registra um endpoint de IA (Azure OpenAI / Fabric AI) no catálogo de objetos do banco.
--   - CREDENTIAL: Referencia a credencial de escopo contendo a chave de API (Bearer Token) com segurança.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Criar a Credencial de Escopo com a API Key de acesso
CREATE DATABASE SCOPED CREDENTIAL [AzureOpenAIApiKeyCred]
WITH IDENTITY = 'HTTPEndpointHeaders',
SECRET = '{"api-key": "SUA_AZURE_OPENAI_KEY_AQUI"}';
GO

-- 2. Criar o Modelo Externo para Embeddings (text-embedding-3-small)
CREATE EXTERNAL MODEL [AzureOpenAI_Embedding_Small]
WITH (
    LOCATION = 'https://meu-recurso-openai.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings',
    API_FORMAT = 'Azure_OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    CREDENTIAL = [AzureOpenAIApiKeyCred]
);
GO

-- 3. Consultar modelos externos registrados na visão de catálogo
SELECT 
    name AS NomeModelo,
    model_type_desc AS TipoModelo,
    location AS EndpointURL,
    create_date AS DataCriacao
FROM sys.external_models;
GO


-- =================================================================================
-- PARTE 2: INVOCANDO O MODELO VIA PREDICT E ATRIBUINDO PERMISSÕES
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PREDICT: Função T-SQL nativa para invocar modelos de IA integrados.
--   - PERMISSÕES: Para invocar um modelo com PREDICT, o usuário precisa da permissão `GRANT EXECUTE ON EXTERNAL MODEL`.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Conceder permissão de execução do modelo externo para a role do aplicativo
GRANT EXECUTE ON EXTERNAL MODEL::[AzureOpenAI_Embedding_Small] TO [public];
GO

-- 2. Exemplo conceitual de chamada em lote via PREDICT para preencher a coluna de vetor
/*
UPDATE p
SET EmbeddingVector = CAST(
    PREDICT(MODEL = [AzureOpenAI_Embedding_Small],
            DATA = (SELECT p2.ProductDescription AS input_text)
           ) AS NVARCHAR(MAX))
FROM lab.ProductEmbeddings p
CROSS APPLY (SELECT p.ProductDescription) p2(ProductDescription)
WHERE p.EmbeddingVector IS NULL;
*/
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz de Comparação de Dimensionamento de Modelos de Embedding
-- Guia de decisão de arquitetura para armazenamento e custo de vetor.

SELECT 
    'text-embedding-3-small' AS Modelo,
    1536 AS DimensoesVetor,
    'Baixo / Otimo para a maioria dos casos' AS CustoStorage,
    'Recomendado como padrao para RAG e busca semantica' AS Recomendacao
UNION ALL
SELECT 
    'text-embedding-3-large',
    3072,
    'Alto (Dobro do tamanho por vetor)',
    'Usar apenas quando for exigida altíssima precisão de busca';
GO
