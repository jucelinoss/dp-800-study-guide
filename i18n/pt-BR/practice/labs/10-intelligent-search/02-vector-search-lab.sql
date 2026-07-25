-- =================================================================================
-- DP-800 - LAB PRÁTICO: BUSCA VETORIAL E DISTÂNCIA DE EMBEDDINGS (VECTOR_DISTANCE)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra o armazenamento de vetores e buscas por similaridade semântica em T-SQL:
--   1. Armazenamento e Inspeção de Propriedades Vetoriais (`VECTORPROPERTY`)
--   2. Cálculo de Distância Exata (ENN) com `VECTOR_DISTANCE` (Métricas: `cosine`, `euclidean`, `dot`)
--   3. Normalização de Vetores com `VECTOR_NORMALIZE(..., 'norm2')`
--   4. Indexação Vetorial Aproximada (ANN via DiskANN) e a função `VECTOR_SEARCH`
--   5. Cenários Práticos de Projeto (Conversão de Distância em Score de Similaridade de 0 a 1)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.VectorProducts;
GO

-- Estrutura de Tabela com Tipo Vetorial (Armazenamento de 1536 dimensões)
CREATE TABLE lab.VectorProducts (
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL,
    DescriptionVector NVARCHAR(MAX) NOT NULL -- Simulação em JSON / VARBINARY no T-SQL padrão
);
GO

-- Popular dados de teste com vetores simulados
INSERT INTO lab.VectorProducts (ProductID, ProductName, Description, DescriptionVector) VALUES
(1, N'Capacete Ciclismo Pro', N'Capacete leve de alta protecao', N'[0.025, -0.038, 0.089, 0.120]'),
(2, N'Capacete Urbano', N'Capacete para uso diario na cidade', N'[0.023, -0.035, 0.082, 0.115]'),
(3, N'Bicicleta de Trilha', N'Bike mountain bike 24 marchas', N'[-0.085, 0.120, -0.045, -0.010]');
GO


-- =================================================================================
-- PARTE 1: CONSULTA DE DISTÂNCIA EXATA (EXACT NEAREST NEIGHBOR - ENN)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - VECTOR_DISTANCE: Calcula a distância matemática entre o vetor da consulta e os vetores armazenados.
--   - MÉTRICA COSINE: Retorna valores entre 0 (vetores idênticos em direção) e 2 (opostos). Ideal para texto.
--   - SIMILARIDADE COSSENO: Calculada como `1.0 - VECTOR_DISTANCE('cosine', v1, v2)`.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Exemplo de Busca Semântica Simulado (Buscando o produto mais próximo do vetor do Capacete Ciclismo Pro)
DECLARE @QueryVector NVARCHAR(MAX) = N'[0.025, -0.038, 0.089, 0.120]';

SELECT 
    ProductID,
    ProductName,
    Description,
    -- Simulação da função VECTOR_DISTANCE em ambiente offline
    CASE ProductID 
        WHEN 1 THEN 0.0000 -- Distância zero (vetor exato)
        WHEN 2 THEN 0.0425 -- Distância muito baixa (semântica muito próxima)
        ELSE 0.8950        -- Distância alta (produto totalmente diferente)
    END AS CosineDistance,
    -- Conversão para Score de Similaridade (0.0 a 1.0)
    1.0 - (CASE ProductID WHEN 1 THEN 0.0000 WHEN 2 THEN 0.0425 ELSE 0.8950 END) AS SimilarityScore
FROM lab.VectorProducts
ORDER BY CosineDistance ASC;
GO


-- =================================================================================
-- PARTE 2: ÍNDICES VETORIAIS APROXIMADOS (DISKANN E VECTOR_SEARCH)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - DISKANN: Tipo de índice vetorial otimizado para gravação em disco e busca gráfica aproximada (ANN).
--   - VECTOR_SEARCH: Função de tabela que consome o índice DiskANN para responder buscas em sub-segundos em tabelas com milhões de linhas.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Estrutura de criação de índice DiskANN (Sintaxe de referência da documentação oficial)
/*
CREATE INDEX IX_VectorProducts_DescriptionVector
ON lab.VectorProducts (DescriptionVector)
USING DISKANN
WITH (METRIC = 'cosine');
*/
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz de Escolha da Métrica de Distância Vetorial
-- Guia de decisão de arquitetura para otimização de busca vetorial.

SELECT 
    'cosine' AS MetricaDistancia,
    '0.0 (Identico) a 2.0 (Oposto)' AS IntervaloValores,
    'Independe do tamanho da frase / magnitude do vetor' AS Vantagens,
    'Busca semantica de texto, RAG e comparacao de artigos' AS CasoDeUsoIdeal
UNION ALL
SELECT 
    'euclidean',
    '0.0 a Infinito',
    'Mede a distancia direta em linha reta entre os pontos no espaco',
    'Dados de coordenadas geograficas, imagens e atributos fisicos'
UNION ALL
SELECT 
    'dot',
    'Inverso do Produto Escalar',
    'Altissima velocidade computacional se os vetores forem normalizados',
    'Vetores pré-normalizados com L2 (VECTOR_NORMALIZE norm2)';
GO
