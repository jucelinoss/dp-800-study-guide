---
title: Chunking e Geração de Embeddings (Chunking and Embedding Generation)
type: study-material
tags:
  - dp-800
  - chunking
  - embeddings
  - vector
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral](#visão-geral)
> - 📍 [2. Identificando Quais Colunas Embeder](#identificando-quais-colunas-embeder)
>   - 🔹 [Combinando Múltiplas Colunas](#combinando-múltiplas-colunas)
> - 📍 [3. Estratégias de Chunking](#estratégias-de-chunking)
>   - 🔹 [Chunking de Tamanho Fixo](#chunking-de-tamanho-fixo)
>   - 🔹 [Chunking com Overlap](#chunking-com-overlap)
>   - 🔹 [Chunking Baseado em Sentenças](#chunking-baseado-em-sentenças)
>   - 🔹 [Comparação de Estratégias de Chunking](#comparação-de-estratégias-de-chunking)
> - 📍 [4. Gerando Embeddings](#gerando-embeddings)
>   - 🔹 [Estrutura da Tabela para Documentos Chunkados](#estrutura-da-tabela-para-documentos-chunkados)
>   - 🔹 [Gerando Embeddings via External Model](#gerando-embeddings-via-external-model)
>   - 🔹 [Gerando Embeddings via sp_invoke_external_rest_endpoint](#gerando-embeddings-via-sp-invoke-external-rest-endpoint)
>   - 🔹 [Embedding em Lote com JSON Batching](#embedding-em-lote-com-json-batching)
>   - 🔹 [Estimativa de Tokens](#estimativa-de-tokens)
> - 📍 [5. Casos de Uso](#casos-de-uso)
> - 📍 [6. Problemas Comuns e Erros](#problemas-comuns-e-erros)
> - 📍 [7. Dicas para o Exame](#dicas-para-o-exame)
> - 📍 [8. Principais Conclusões](#principais-conclusões)
> - 📍 [9. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [10. Documentação Oficial](#documentação-oficial)

---

# Chunking e Geração de Embeddings

## Visão Geral

Antes de gerar embeddings, você deve decidir quais colunas embeder e como preparar o texto. Para documentos longos, você também deve dividir o texto em segmentos que caibam no limite de tokens do modelo. A **estratégia de chunking** afeta significativamente a qualidade da recuperação. Após o chunking, os embeddings são gerados via chamada de external model e armazenados em uma coluna vetorial.

> [!abstract]
>
> - Aborda estratégias de chunking para preparar documentos para embedding: tamanho fixo, semântico e com overlap
> - Documentos devem ser divididos em chunks antes do embedding porque os modelos têm limites de tokens
> - Tópicos-chave para o exame: tradeoffs entre chunking fixo vs semântico, propósito do overlap, efeitos do tamanho do chunk na qualidade da recuperação

> [!tip] O Que o Exame Testa
>
> - **Chunking de tamanho fixo**: dividir a cada N tokens; simples e previsível; pode dividir no meio de uma frase
> - **Chunking semântico**: dividir em limites de frase/parágrafo; melhor preservação de contexto; mais complexo
> - **Overlap**: incluir os últimos M tokens do chunk anterior no início do próximo chunk — evita perder contexto nas fronteiras

---

## Identificando Quais Colunas Embeder

Nem toda coluna precisa de embedding. Escolha colunas onde a busca semântica agregaria valor:

| Tipo de Coluna | Embeder? | Razão |
| :--- | :--- | :--- |
| Descrição em texto livre | Sim | Linguagem natural, alto conteúdo semântico |
| Avaliação / feedback de clientes | Sim | Linguagem variada, busca baseada em intenção |
| Nome do produto | Às vezes | Curto; full-text pode ser suficiente |
| Códigos de status / enums | Não | Melhor tratado por match exato |
| Valores numéricos | Não | Use comparação escalar |
| Datas | Não | Queries de range são melhores |
| Payloads JSON | Às vezes | Extraia os campos relevantes primeiro |

### Combinando Múltiplas Colunas

Quando múltiplas colunas contribuem para o significado semântico, concatene-as antes de embeder:

```sql
-- Criar uma representação textual que combina campos relevantes
SELECT
    ProductId,
    -- Combinar nome, categoria e descrição em uma string para embedding
    CONCAT(
        'Product: ', ProductName, '. ',
        'Category: ', CategoryName, '. ',
        'Description: ', Description
    ) AS TextToEmbed
FROM dbo.Products p
JOIN dbo.Categories c ON p.CategoryId = c.CategoryId;
```

> [!note] Dica de Qualidade
>
> Prefixar cada campo com seu nome (ex: `"Product: "`, `"Category: "`) ajuda o modelo de embedding a entender a semântica de cada parte. Isso melhora a qualidade de recuperação comparado a simples concatenação sem prefixos.

---

## Estratégias de Chunking

Modelos de embedding têm um limite máximo de tokens de entrada (ex: 8192 tokens para `text-embedding-3-small`). Documentos mais longos que isso devem ser divididos em chunks.

### Chunking de Tamanho Fixo

Divide o texto em contagens fixas de caracteres ou tokens:

```sql
-- Chunking de tamanho fixo usando CTE recursiva (a cada 500 caracteres)
WITH DocumentChunks AS (
    SELECT
        DocumentId,
        1 AS ChunkNumber,
        LEFT(Content, 500) AS ChunkText,
        LEN(Content) AS TotalLength
    FROM dbo.Documents

    UNION ALL

    SELECT
        dc.DocumentId,
        dc.ChunkNumber + 1,
        SUBSTRING(d.Content, (dc.ChunkNumber * 500) + 1, 500),
        dc.TotalLength
    FROM DocumentChunks dc
    JOIN dbo.Documents d ON d.DocumentId = dc.DocumentId
    WHERE (dc.ChunkNumber * 500) < dc.TotalLength
)
INSERT INTO dbo.DocumentChunks (DocumentId, ChunkNumber, ChunkText)
SELECT DocumentId, ChunkNumber, ChunkText
FROM DocumentChunks
WHERE ChunkText <> ''
OPTION (MAXRECURSION 1000);
```

### Chunking com Overlap

Chunks com overlap preservam contexto nas fronteiras e melhoram o recall da recuperação ao custo de mais armazenamento e chamadas de API:

```sql
-- Chunking com overlap: chunks de 500 chars, overlap de 100 chars
-- Chunk 1: chars 1-500
-- Chunk 2: chars 401-900  (sobrepõe os últimos 100 do chunk 1)
-- Chunk 3: chars 801-1300
DECLARE @ChunkSize INT = 500;
DECLARE @Overlap   INT = 100;
DECLARE @Step      INT = @ChunkSize - @Overlap;  -- = 400

WITH Positions AS (
    SELECT
        DocumentId,
        1 AS StartPos,
        LEN(Content) AS TotalLen
    FROM dbo.Documents

    UNION ALL

    SELECT
        p.DocumentId,
        p.StartPos + @Step,
        p.TotalLen
    FROM Positions p
    WHERE p.StartPos + @Step <= p.TotalLen
),
Chunks AS (
    SELECT
        p.DocumentId,
        ROW_NUMBER() OVER (PARTITION BY p.DocumentId ORDER BY p.StartPos) AS ChunkNumber,
        SUBSTRING(d.Content, p.StartPos, @ChunkSize) AS ChunkText
    FROM Positions p
    JOIN dbo.Documents d ON d.DocumentId = p.DocumentId
)
INSERT INTO dbo.DocumentChunks (DocumentId, ChunkNumber, ChunkText)
SELECT DocumentId, ChunkNumber, ChunkText
FROM Chunks
WHERE LEN(TRIM(ChunkText)) > 10
OPTION (MAXRECURSION 2000);
```

> [!tip] Por Que Usar Overlap?
>
> Sem overlap, uma informação chave que cai exatamente na fronteira de dois chunks pode ser cortada ao meio — fazendo com que nenhum chunk a contenha completamente. Com overlap, os últimos N tokens do chunk anterior são repetidos no início do próximo, garantindo que a recuperação encontre o contexto completo. O custo é armazenamento extra (~20% a mais de chunks).

### Chunking Baseado em Sentenças

Divide nos limites de sentenças para preservar unidades semânticas:

```sql
-- Divisão simples de sentenças em padrões de ponto+espaço
-- Para produção, use Azure Function ou Python para divisão NLP correta de sentenças
CREATE OR ALTER FUNCTION dbo.SplitIntoSentences (@text NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN (
    WITH SentenceSplit AS (
        SELECT value AS Sentence,
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS SentenceNum
        FROM STRING_SPLIT(REPLACE(REPLACE(@text, '. ', '.|'), '? ', '?|'), '|')
        WHERE LEN(TRIM(value)) > 5
    )
    SELECT Sentence, SentenceNum FROM SentenceSplit
);
```

```sql
-- Agrupar sentenças em chunks de ~3-5 sentenças
-- (Implementações de produção normalmente usam Python/Azure Functions para isso)
WITH SentencesWithChunk AS (
    SELECT
        d.DocumentId,
        s.Sentence,
        s.SentenceNum,
        CEILING(s.SentenceNum / 4.0) AS ChunkNumber  -- ~4 sentenças por chunk
    FROM dbo.Documents d
    CROSS APPLY dbo.SplitIntoSentences(d.Content) s
)
INSERT INTO dbo.DocumentChunks (DocumentId, ChunkNumber, ChunkText)
SELECT
    DocumentId,
    ChunkNumber,
    STRING_AGG(Sentence, ' ') WITHIN GROUP (ORDER BY SentenceNum) AS ChunkText
FROM SentencesWithChunk
GROUP BY DocumentId, ChunkNumber;
```

### Comparação de Estratégias de Chunking

| Estratégia | Prós | Contras | Melhor Para |
| :--- | :--- | :--- | :--- |
| Tamanho fixo | Simples, previsível | Pode cortar no meio de uma frase | Docs técnicos, texto longo |
| Com overlap | Melhor recall nas fronteiras | Mais chunks, maior custo | Documentos em geral |
| Baseado em sentenças | Semanticamente coerente | Tamanho de chunk variável | Artigos, avaliações, Q&A |
| Baseado em parágrafos | Quebras naturais | Tamanho muito variável | Conteúdo web, documentação |

---

## Gerando Embeddings

### Estrutura da Tabela para Documentos Chunkados

```sql
-- Tabela de documentos
CREATE TABLE dbo.Documents (
    DocumentId   INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    Title        NVARCHAR(500) NOT NULL,
    Content      NVARCHAR(MAX) NOT NULL,
    SourceUrl    NVARCHAR(1000) NULL,
    CreatedAt    DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt    DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);

-- Chunks de documentos com embeddings
CREATE TABLE dbo.DocumentChunks (
    ChunkId       INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    DocumentId    INT           NOT NULL REFERENCES dbo.Documents(DocumentId),
    ChunkNumber   INT           NOT NULL,
    ChunkText     NVARCHAR(MAX) NOT NULL,
    TokenCount    INT           NULL,         -- estimativa de contagem de tokens
    Embedding     VECTOR(1536)  NULL,         -- text-embedding-3-small
    EmbeddedAt    DATETIME2     NULL,
    CONSTRAINT UQ_DocumentChunks UNIQUE (DocumentId, ChunkNumber)
);

CREATE INDEX IX_DocumentChunks_EmbeddingNull
    ON dbo.DocumentChunks (DocumentId) WHERE Embedding IS NULL;
```

> [!note] Armazene Sempre o ChunkText
>
> Armazene sempre a coluna `ChunkText` junto ao embedding — ela é necessária para montar o contexto para o LLM durante o RAG. Um embedding sem o texto original é inútil para geração de respostas.

### Gerando Embeddings via External Model

```sql
-- Gerar embeddings para todos os chunks não-embeddados
UPDATE dc
SET
    Embedding  = CAST(
        PREDICT(MODEL = [MyEmbeddingModel],
                DATA = (SELECT dc2.ChunkText AS input_text)) AS VECTOR(1536)),
    EmbeddedAt = GETUTCDATE()
FROM dbo.DocumentChunks dc
CROSS APPLY (SELECT dc.ChunkText) dc2(ChunkText)
WHERE dc.Embedding IS NULL;
```

### Gerando Embeddings via sp_invoke_external_rest_endpoint

Para ambientes sem suporte a external model, chame o Azure OpenAI diretamente:

```sql
-- Gerar embedding para um único chunk via REST
DECLARE @chunk_text NVARCHAR(MAX) = 'Azure SQL supports vector search for semantic similarity.';
DECLARE @response   NVARCHAR(MAX);
DECLARE @embedding  NVARCHAR(MAX);

DECLARE @payload NVARCHAR(MAX) = N'{"input": ' + QUOTENAME(@chunk_text, '"') + '}';

EXEC sp_invoke_external_rest_endpoint
    @url     = 'https://myopenai.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01',
    @method  = 'POST',
    @headers = '{"Content-Type":"application/json"}',
    @payload = @payload,
    @credential = [https://myopenai.openai.azure.com/],
    @response = @response OUTPUT;

-- Extrair o array de embedding da resposta JSON
SET @embedding = JSON_QUERY(@response, '$.result.data[0].embedding');

-- Armazenar como VECTOR
UPDATE dbo.DocumentChunks
SET Embedding = CAST(@embedding AS VECTOR(1536)),
    EmbeddedAt = GETUTCDATE()
WHERE ChunkId = 1;
```

### Embedding em Lote com JSON Batching

Para eficiência, agrupe múltiplos textos em uma única chamada de API:

```sql
-- Embedding em lote: enviar até 2048 textos em uma requisição
DECLARE @batch_size INT = 100;

-- Construir array de input para o lote
DECLARE @inputs NVARCHAR(MAX);
SELECT @inputs = '[' +
    STRING_AGG('"' + REPLACE(ChunkText, '"', '\"') + '"', ',')
    WITHIN GROUP (ORDER BY ChunkId)
    + ']'
FROM (SELECT TOP (@batch_size) ChunkId, ChunkText
      FROM dbo.DocumentChunks WHERE Embedding IS NULL) batch;

DECLARE @payload NVARCHAR(MAX) = N'{"input": ' + @inputs + '}';
DECLARE @response NVARCHAR(MAX);

EXEC sp_invoke_external_rest_endpoint
    @url     = 'https://myopenai.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-02-01',
    @method  = 'POST',
    @headers = '{"Content-Type":"application/json"}',
    @payload = @payload,
    @credential = [https://myopenai.openai.azure.com/],
    @response = @response OUTPUT;

-- Parsear a resposta do lote e atualizar a tabela
-- Cada item de resposta tem índice, array de embedding
-- Na prática é mais fácil fazer isso em uma stored procedure com OPENJSON
```

### Estimativa de Tokens

Antes de chamar a API, estime as contagens de tokens para evitar exceder o limite de 8192 tokens:

```sql
-- Estimativa grosseira de tokens: ~4 caracteres por token para texto em inglês
UPDATE dbo.DocumentChunks
SET TokenCount = LEN(ChunkText) / 4
WHERE TokenCount IS NULL;

-- Sinalizar chunks que podem ser muito longos
SELECT ChunkId, DocumentId, ChunkNumber, LEN(ChunkText) AS CharCount, TokenCount
FROM dbo.DocumentChunks
WHERE TokenCount > 7500;  -- Deixe margem abaixo do limite de 8192
```

> [!caution] Limite de Tokens do Modelo
>
> Verifique o limite de entrada do deployment e da versão do modelo em uso. A regra aproximada de 4 caracteres por token vale apenas como triagem para inglês; use uma contagem compatível com o tokenizer do modelo antes de enviar o lote.

---

## Casos de Uso

- **Busca em documentos**: Divida em chunks manuais de produtos, artigos de base de conhecimento ou documentos de suporte; embeda cada chunk; recupere os chunks mais relevantes para uma query do usuário
- **Catálogo de produtos**: Embeda nome do produto + descrição concatenados para busca semântica de produtos
- **Avaliações de clientes**: Embeda cada avaliação para clustering de sentimento e similaridade semântica
- **Pares de Q&A**: Embeda perguntas e respostas separadamente para melhor qualidade de recuperação

---

## Problemas Comuns e Erros

| Problema | Causa | Correção |
| :--- | :--- | :--- |
| `Token limit exceeded` | Texto do chunk muito longo | Reduza o tamanho do chunk; adicione verificação de estimativa de tokens antes do embedding |
| Embeddings são `NULL` após update | Erro do PREDICT silenciosamente suprimido | Teste PREDICT em uma única linha primeiro; verifique os logs de erro |
| Má qualidade de recuperação | Chunks muito grandes ou divididos no meio de uma frase | Use chunks menores com overlap, ou divisão baseada em sentenças |
| Embedding em lote muito lento | Uma chamada de API por linha | Use chamadas REST em lote ou PREDICT em UPDATE baseado em conjunto |
| Inchaço de armazenamento | 1536 floats × 4 bytes × milhões de linhas | Use `text-embedding-3-small` (mesmas dims que ada-002 mas melhor qualidade); considere compressão de VECTOR |

---

## Dicas para o Exame

> [!tip] Dicas para o Exame
>
> - Modelos de embedding têm um **limite de tokens** — divida o texto em chunks antes do embedding; ~4 chars por token para inglês
> - **Chunks com overlap** melhoram o recall nas fronteiras — use quando a qualidade de recuperação importa mais que o custo
> - `VECTOR(1536)` armazena 1536 floats × 4 bytes = 6KB por linha — planeje o armazenamento adequadamente
> - Sempre armazene o `ChunkText` junto ao embedding — é necessário para montar o contexto para o LLM
> - `PREDICT(MODEL = ..., DATA = (SELECT text AS input_text))` — o alias `input_text` é obrigatório para modelos de embedding

---

## Principais Conclusões

- Escolha colunas para embeder com base no valor de busca semântica — textos livres, descrições, avaliações são bons candidatos
- Divida documentos longos em chunks antes do embedding — tamanho fixo com overlap é um padrão seguro
- Armazene chunks em uma tabela separada com colunas `ChunkText`, `DocumentId`, `ChunkNumber` e `Embedding`
- Gere embeddings com `PREDICT` (external model) ou `sp_invoke_external_rest_endpoint` (chamada REST)

---

## Tópicos Relacionados

- [01-External Models](./01-external-models.md)
- [02-Manutenção de Embeddings](./02-embedding-maintenance.md)
- [02-Busca Vetorial](../10-intelligent-search/02-vector-search.md)
- [03-Hybrid Search e RRF](../10-intelligent-search/03-hybrid-search-rrf.md)

---

## Documentação Oficial

- [VECTOR Data Type](https://learn.microsoft.com/en-us/sql/t-sql/data-types/vector-data-type)
- [PREDICT Function](https://learn.microsoft.com/en-us/sql/t-sql/queries/predict-transact-sql)
- [Azure OpenAI Embeddings](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/embeddings)

---

**[← Anterior](./02-embedding-maintenance.md) | [↑ Voltar à Seção](./models-embeddings.md)**
