-- =================================================================================
-- DP-800 - LAB PRÁTICO: MANUTENÇÃO E REGENERAÇÃO DE EMBEDDINGS (DIRTY TRACKING E TRIGGERS)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra padrões de manutenção preventiva e atualização de vetores de embeddings:
--   1. Padrão Dirty Tracking (`IsEmbeddingStale BIT`) para identificar vetores desatualizados
--   2. Atualização Síncrona via Triggers de Tabela (`AFTER INSERT, UPDATE`)
--   3. Processamento de Lote (Batch Regeneration) para vetores pendentes
--   4. Estratégia de Regeneração Total (Troca de Modelo de AI de text-embedding-ada-002 para 3-small)
--   5. Cenários Práticos de Projeto (Rastreamento de Modificação de Texto vs Data do Vetor)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.ProductVectorCatalog;
GO

-- Estrutura de Tabela com Flags de Manutenção de Embeddings
CREATE TABLE lab.ProductVectorCatalog (
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL,
    DescriptionEmbedding NVARCHAR(MAX) NULL, -- Vetor serializado em JSON
    IsEmbeddingStale BIT NOT NULL DEFAULT 1, -- Flag Dirty Tracking
    LastUpdated DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    EmbeddingGeneratedAt DATETIME2 NULL
);
GO

INSERT INTO lab.ProductVectorCatalog (ProductID, ProductName, Description) VALUES
(101, N'Capacete Premium', N'Capacete aerodinamico com fibra de carbono e ventilacao extra.'),
(102, N'Luvas de Ciclismo', N'Luvas acolchoadas com gel e tecido respiravel.');
GO


-- =================================================================================
-- PARTE 1: PADRÃO DIRTY TRACKING COM TRIGGER DE TABELA
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DIRTY TRACKING: Marca `IsEmbeddingStale = 1` sempre que o campo de texto for alterado.
--     Desacopla a gravação do banco da chamada HTTP da API do OpenAI, permitindo regeneração assíncrona.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Trigger para marcar a coluna IsEmbeddingStale como 1 se a descrição mudar
CREATE OR ALTER TRIGGER lab.trg_ProductVectorCatalog_DirtyTracking
ON lab.ProductVectorCatalog
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    IF UPDATE(Description)
    BEGIN
        UPDATE p
        SET 
            IsEmbeddingStale = 1,
            LastUpdated = GETUTCDATE()
        FROM lab.ProductVectorCatalog p
        INNER JOIN inserted i ON p.ProductID = i.ProductID;
    END;
END;
GO

-- Simular alteração na descrição
UPDATE lab.ProductVectorCatalog
SET Description = N'Capacete aerodinamico com fibra de carbono, ventilacao extra e luz LED traseira.'
WHERE ProductID = 101;
GO

-- Verificar se a linha foi marcada como Stale (Dirty)
SELECT ProductID, ProductName, IsEmbeddingStale, LastUpdated 
FROM lab.ProductVectorCatalog;
GO


-- =================================================================================
-- PARTE 2: REGENERAÇÃO DE LOTE (BATCH REFRESH) E TROCA DE MODELO
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - TROCA DE MODELO: Trocar de `text-embedding-ada-002` para `text-embedding-3-small` EXIGE regerar 100% dos vetores!
--     Vetores de modelos diferentes não pertencem ao mesmo espaço vetorial e produzem resultados incorretos.

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Iniciar procedimento de troca total de modelo marcando todas as linhas como Stale
UPDATE lab.ProductVectorCatalog
SET IsEmbeddingStale = 1;
GO

-- 2. Processar lote de registros desatualizados (Simulação da chamada do job batch)
UPDATE lab.ProductVectorCatalog
SET 
    DescriptionEmbedding = N'[-0.012, 0.045, 0.089, ...]', -- Vetor simulado de 1536 dimensões
    IsEmbeddingStale = 0,
    EmbeddingGeneratedAt = GETUTCDATE()
WHERE IsEmbeddingStale = 1;
GO

-- Validar se todas as linhas foram re-indexadas com sucesso
SELECT ProductID, IsEmbeddingStale, EmbeddingGeneratedAt 
FROM lab.ProductVectorCatalog;
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz Comparativa de Abordagens de Manutenção de Embeddings
-- Guia de decisão de arquitetura para o Exame DP-800.

SELECT 
    'Triggers de Tabela (Sincrono)' AS Abordagem,
    'Alta (API chamada durante o UPDATE)' AS LatenciaEscrita,
    'Pequenas tabelas ou escritas infrequentes' AS CasoDeUsoRecomendado,
    'API indisponivel aborta a transacao de escrita' AS RiscoArquitetural
UNION ALL
SELECT 
    'Dirty Tracking + Batch Job (Assincrono)',
    'Zero (Nao afeta o UPDATE do usuario)',
    'Alta frequencia de escrita e tabelas grandes',
    'Vetor fica temporariamente desatualizado ate a roda do job'
UNION ALL
SELECT 
    'Azure Functions SQL Trigger Binding',
    'Quase em Tempo Real (Assincrono baseado em eventos)',
    'Arquiteturas Cloud Serverless nativas Azure',
    'Requer infraestrutura de Functions e Change Tracking ativo';
GO
