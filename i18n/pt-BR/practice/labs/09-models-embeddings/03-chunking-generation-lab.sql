-- =================================================================================
-- DP-800 - LAB PRÁTICO: FRAGMENTAÇÃO DE TEXTO (CHUNKING) E GERAÇÃO DE EMBEDDINGS
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a preparação de documentos extensos para busca semântica (RAG):
--   1. Estruturação da Tabela de Documentos (`Documents`) e Fragmentos (`DocumentChunks`)
--   2. Fragmentação com Tamanho Fixo e Sobreposição (Overlapping Chunking via CTE Recursiva)
--   3. Estimativa de Tokens e Limitação de Tamanho por Chunks
--   4. Geração em Lote de Embeddings (Batch Generation)
--   5. Cenários Práticos de Projeto (Preparação para Busca Vetorial RAG)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.DocumentChunks;
DROP TABLE IF EXISTS lab.SourceDocuments;
GO

-- Estrutura da Tabela Principal de Documentos e de Chunks
CREATE TABLE lab.SourceDocuments (
    DocumentID INT IDENTITY(1,1) PRIMARY KEY,
    Title NVARCHAR(200) NOT NULL,
    FullContent NVARCHAR(MAX) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);

CREATE TABLE lab.DocumentChunks (
    ChunkID INT IDENTITY(1,1) PRIMARY KEY,
    DocumentID INT NOT NULL REFERENCES lab.SourceDocuments(DocumentID),
    ChunkNumber INT NOT NULL,
    ChunkText NVARCHAR(MAX) NOT NULL,
    EstimatedTokens INT NULL,
    EmbeddingVector NVARCHAR(MAX) NULL, -- Vetor serializado em JSON
    CONSTRAINT UQ_DocumentChunks UNIQUE (DocumentID, ChunkNumber)
);
GO

-- Inserir documento extenso de teste
INSERT INTO lab.SourceDocuments (Title, FullContent) VALUES 
(N'Manual de Manutencao de Bicicletas', 
 N'A manutencao preventiva de bicicletas inclui a verificacao semanal da pressao dos pneus, limpeza e lubrificacao da corrente. ' +
 N'Os freios a disco devem ser inspecionados para evitar o desgaste prematuro das pastilhas. ' +
 N'A suspensao dianteira necessita de revisao a cada 50 horas de uso intenso em trilhas. ' +
 N'Mantenha sempre os parafusos do selim e do guidao apertados com o torque recomendado pelo fabricante.');
GO


-- =================================================================================
-- PARTE 1: ESTRATÉGIA DE FRAGMENTAÇÃO COM SOBREPOSIÇÃO (OVERLAPPING CHUNKING)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CHUNKING: Dividir documentos grandes para não ultrapassar o limite de tokens do modelo (ex: 8192 no text-embedding-3-small).
--   - OVERLAP (SOBREPOSIÇÃO): Mantém as últimas N palavras/caracteres no início do próximo fragmento para preservar o contexto.

-- -- [PONTO DE ATENÇÃO DP-800]
DECLARE @ChunkSize INT = 150; -- Tamanho de cada fragmento em caracteres
DECLARE @Overlap INT = 40;   -- Quantidade de caracteres que sobrepõe
DECLARE @Step INT = @ChunkSize - @Overlap; -- Tamanho do avanço (110)

WITH SequencePositions AS (
    SELECT 
        DocumentID,
        1 AS StartPos,
        LEN(FullContent) AS TotalLen
    FROM lab.SourceDocuments
    
    UNION ALL
    
    SELECT 
        sp.DocumentID,
        sp.StartPos + @Step,
        sp.TotalLen
    FROM SequencePositions sp
    WHERE sp.StartPos + @Step <= sp.TotalLen
),
GeneratedChunks AS (
    SELECT 
        sp.DocumentID,
        ROW_NUMBER() OVER (PARTITION BY sp.DocumentID ORDER BY sp.StartPos) AS ChunkNumber,
        SUBSTRING(d.FullContent, sp.StartPos, @ChunkSize) AS ChunkText
    FROM SequencePositions sp
    JOIN lab.SourceDocuments d ON d.DocumentID = sp.DocumentID
)
INSERT INTO lab.DocumentChunks (DocumentID, ChunkNumber, ChunkText, EstimatedTokens)
SELECT 
    DocumentID,
    ChunkNumber,
    ChunkText,
    LEN(ChunkText) / 4 -- Estimativa aproximada: ~4 caracteres por token
FROM GeneratedChunks
WHERE LEN(TRIM(ChunkText)) > 10
OPTION (MAXRECURSION 500);
GO

-- Consultar os fragmentos gerados com sobreposição
SELECT ChunkID, DocumentID, ChunkNumber, EstimatedTokens, ChunkText 
FROM lab.DocumentChunks;
GO


-- =================================================================================
-- PARTE 2: GERAÇÃO DE EMBEDDINGS EM LOTE (BATCH ENCODING)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - BATCH GENERATION: Envia múltiplos fragmentos em uma única requisição HTTP JSON para a API de Embeddings.
--     Reduz drásticamente o overhead de rede e tempo de processamento em comparação com chamadas por linha.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Construção do Payload JSON em lote para envio ao Azure OpenAI
DECLARE @BatchPayload NVARCHAR(MAX);

SELECT @BatchPayload = N'{"input": [' + 
    STRING_AGG('"' + REPLACE(ChunkText, '"', '\"') + '"', ',') WITHIN GROUP (ORDER BY ChunkID) + 
    N']}'
FROM lab.DocumentChunks
WHERE EmbeddingVector IS NULL;

PRINT 'PAYLOAD JSON DE LOTE GERADO COM SUCESSO:';
PRINT LEFT(@BatchPayload, 300) + '...';
GO


-- =================================================================================
-- PARTE 3: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz Comparativa de Estratégias de Chunking para RAG
-- Guia de decisão de arquitetura para otimização de busca vetorial.

SELECT 
    'Fixed-Size Chunking' AS Estrategia,
    'Simples e previsivel' AS Vantagens,
    'Pode cortar frases ao meio perdendo sentido' AS Desvantagens,
    'Documentos estruturados ou de tamanho homogêneo' AS Recomendacao
UNION ALL
SELECT 
    'Overlapping Chunking',
    'Preserva o contexto entre as bordas dos fragmentos',
    'Gera mais chunks aumentando o armazenamento de vetores',
    'Padrao recomendado para a maioria das aplicacoes RAG'
UNION ALL
SELECT 
    'Sentence/Paragraph Chunking',
    'Unidades semânticas perfeitas e completas',
    'Tamanho de fragmento altamente variavel',
    'Artigos, manuais e bases de conhecimento de Q&A';
GO
