---
title: Busca Vetorial (Vector Search)
type: study-material
tags:
  - dp-800
  - vector-search
  - vector-distance
  - ann
  - enn
  - vector-index
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral](#visão-geral)
> - 📍 [2. Tipo de Dado VECTOR](#tipo-de-dado-vector)
> - 📍 [3. VECTOR_NORMALIZE](#vector-normalize)
> - 📍 [4. VECTORPROPERTY](#vectorproperty)
> - 📍 [5. VECTOR_DISTANCE — Métricas de Distância](#vector-distance-métricas-de-distância)
>   - 🔹 [Distância Cosseno](#distância-cosseno)
>   - 🔹 [Distância Euclidiana (L2)](#distância-euclidiana-l2)
>   - 🔹 [Distância Dot Product](#distância-dot-product)
>   - 🔹 [Comparação de Métricas de Distância](#comparação-de-métricas-de-distância)
> - 📍 [6. VECTOR_SEARCH — Approximate Nearest Neighbor](#vector-search-approximate-nearest-neighbor)
> - 📍 [7. Índice Vetorial (DiskANN)](#índice-vetorial-diskann)
>   - 🔹 [Opções do Índice DiskANN](#opções-do-índice-diskann)
>   - 🔹 [Quando o Optimizer Usa o Índice Vetorial](#quando-o-optimizer-usa-o-índice-vetorial)
> - 📍 [8. ANN vs ENN](#ann-vs-enn)
> - 📍 [9. Convertendo Similaridade em Distância](#convertendo-similaridade-em-distância)
> - 📍 [10. Padrão Completo de Busca com Embedding de Query](#padrão-completo-de-busca-com-embedding-de-query)
> - 📍 [11. Casos de Uso](#casos-de-uso)
> - 📍 [12. Problemas Comuns e Erros](#problemas-comuns-e-erros)
> - 📍 [13. Dicas para o Exame](#dicas-para-o-exame)
> - 📍 [14. Principais Conclusões](#principais-conclusões)
> - 📍 [15. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [16. Documentação Oficial](#documentação-oficial)

---

# Busca Vetorial (Vector Search)

## Visão Geral

A busca vetorial encontra linhas cujos embeddings vetoriais são matematicamente similares a um vetor de query. Isso habilita a busca semântica — encontrando conteúdo conceitualmente relacionado mesmo quando palavras-chave exatas não correspondem. O SQL Database no Fabric e o Azure SQL suportam busca vetorial nativa com o tipo de dado `VECTOR`, a função `VECTOR_DISTANCE` e a função `VECTOR_SEARCH` com indexação de approximate nearest neighbor (ANN) via DiskANN.

> [!abstract]
>
> - Aborda o tipo de dado VECTOR, VECTOR_DISTANCE (busca exata), VECTOR_SEARCH (busca aproximada) e indexação DiskANN
> - A busca vetorial habilita queries de similaridade semântica — encontrando conteúdo conceitualmente relacionado, não apenas correspondências de palavras-chave
> - Tópicos-chave para o exame: distinção ENN vs ANN, escolher a métrica de distância correta, requisito de VECTOR_NORMALIZE

> [!tip] O Que o Exame Testa
>
> - `VECTOR_DISTANCE('cosine', v1, v2)` = **exato** nearest neighbor (ENN) — compara todas as linhas; use quando precisão > velocidade
> - `VECTOR_SEARCH(TABLE, VECTOR(col), JSON_ARRAY(query_vector), top_n)` = **aproximado** (ANN) via DiskANN — mais rápido em escala
> - DiskANN suporta métricas `cosine`, `dot` e `euclidean` — a métrica do índice **deve corresponder** à métrica usada em `VECTOR_SEARCH`

> [!note] Status em 2026
>
> - `VECTOR` e `VECTOR_DISTANCE` — **GA** no SQL Server 2025 e Azure SQL Database.
> - `VECTOR_SEARCH`, `VECTOR_NORMALIZE`, `VECTORPROPERTY` — **preview público** no SQL Server 2025, Azure SQL Database e SQL database no Microsoft Fabric. Totalmente testável no exame.
> - **Índice vetorial DiskANN** — **preview público** no SQL Server 2025, Azure SQL Database, Azure SQL Managed Instance e SQL database no Fabric. SQL Server 2025 requer adicionalmente `PREVIEW_FEATURES = ON`. Espere questões sobre correspondência de métricas.
> - **Vetores de meia precisão (`float16`)** — preview; reduz armazenamento pela metade no mesmo número de dimensões. O limite documentado do tipo `VECTOR` é **1.998** dimensões.

---

## Tipo de Dado VECTOR

```sql
-- Armazenar um embedding de 1536 dimensões (text-embedding-3-small ou ada-002)
CREATE TABLE dbo.Products (
    ProductId         INT          NOT NULL PRIMARY KEY,
    ProductName       NVARCHAR(500) NOT NULL,
    Description       NVARCHAR(MAX) NOT NULL,
    DescriptionVector VECTOR(1536)  NULL      -- 1536 floats = 6 KB por linha
);

-- 3072 dimensões excedem o limite de float32. Em plataformas com
-- float16 em preview habilitado, use:
ALTER TABLE dbo.Documents ADD ContentVector VECTOR(3072, float16) NULL;

-- Inserir um vetor a partir de uma string de array JSON
INSERT INTO dbo.Products (ProductId, ProductName, DescriptionVector)
VALUES (1, 'Wireless Headphones',
    CAST('[0.023, -0.041, 0.018, ...]' AS VECTOR(1536)));
```

---

## VECTOR_NORMALIZE

Normaliza um vetor para comprimento unitário (norma L2 = 1). Necessário antes de usar dot product como aproximação de cosine similarity:

```sql
-- Normalizar um vetor
SELECT VECTOR_NORMALIZE(DescriptionVector, 'norm2') AS NormalizedVector
FROM dbo.Products
WHERE ProductId = 1;

-- Normalizar todos os vetores in-place
UPDATE dbo.Products
SET DescriptionVector = VECTOR_NORMALIZE(DescriptionVector, 'norm2')
WHERE DescriptionVector IS NOT NULL;
```

`'norm2'` = norma L2 (Euclidiana). Após normalização, o dot product é equivalente ao cosine similarity.

> [!note] Por Que Normalizar?
>
> O `VECTOR_DISTANCE('cosine', ...)` já computa a distância cosseno corretamente — você **não precisa normalizar** antes. Porém, se você usar dot product (`'dot'`) como métrica de similaridade, os vetores **devem estar normalizados** para que os resultados sejam equivalentes ao cosseno. A normalização antecipada também pode melhorar a performance de buscas repetidas.

---

## VECTORPROPERTY

Inspeciona propriedades de um valor vetorial:

```sql
-- Obter o número de dimensões em um vetor
SELECT VECTORPROPERTY(DescriptionVector, 'Dimensions') AS Dims
FROM dbo.Products
WHERE ProductId = 1;
-- Retorna: 1536

-- Obter o tipo de dado do vetor (float32 é o tipo suportado atualmente)
SELECT VECTORPROPERTY(DescriptionVector, 'BaseType') AS BaseType
FROM dbo.Products
WHERE ProductId = 1;
-- Retorna: float32
```

---

## VECTOR_DISTANCE — Métricas de Distância

`VECTOR_DISTANCE` computa a distância entre dois vetores. Menor distância = mais similar.

### Distância Cosseno

Mede o ângulo entre dois vetores. Melhor para embeddings de texto onde a magnitude não importa:

```sql
-- Encontrar produtos mais similares a um embedding de query
DECLARE @query_vector VECTOR(1536) = CAST('[0.025, -0.038, ...]' AS VECTOR(1536));

SELECT TOP 10
    p.ProductId,
    p.ProductName,
    VECTOR_DISTANCE('cosine', p.DescriptionVector, @query_vector) AS CosineDistance
FROM dbo.Products p
WHERE p.DescriptionVector IS NOT NULL
ORDER BY CosineDistance ASC;  -- Menor = mais similar
```

### Distância Euclidiana (L2)

Mede a distância em linha reta entre vetores no espaço n-dimensional:

```sql
SELECT TOP 10
    p.ProductId,
    p.ProductName,
    VECTOR_DISTANCE('euclidean', p.DescriptionVector, @query_vector) AS EuclideanDistance
FROM dbo.Products p
ORDER BY EuclideanDistance ASC;
```

### Distância Dot Product

Mede similaridade como o produto escalar (inner product) de dois vetores. Quando os vetores estão normalizados, é equivalente ao cosine similarity:

```sql
-- Dot product: para vetores normalizados, menor = menos similar (inverso do cosine sim)
-- Nota: computa o produto escalar negativo como "distância"
SELECT TOP 10
    p.ProductId,
    p.ProductName,
    VECTOR_DISTANCE('dot', p.DescriptionVector, @query_vector) AS DotDistance
FROM dbo.Products p
ORDER BY DotDistance ASC;
```

### Comparação de Métricas de Distância

| Métrica | Fórmula | Intervalo | Melhor Para |
| :--- | :--- | :--- | :--- |
| `cosine` | 1 - cos(θ) | 0 a 2 | Embeddings de texto, similaridade baseada em direção |
| `euclidean` | √Σ(a-b)² | 0 a ∞ | Dados espaciais/geométricos, vetores normalizados |
| `dot` | 1 - Σ(aᵢ×bᵢ) | -∞ a +∞ | Quando os vetores já estão normalizados em L2 |

**Regra geral:** Use `cosine` para embeddings de texto — ele é invariante à magnitude do vetor, que varia pelo comprimento do documento.

---

## VECTOR_SEARCH — Approximate Nearest Neighbor

`VECTOR_SEARCH` usa um índice vetorial (DiskANN) para realizar busca approximate nearest neighbor (ANN) — muito mais rápida que a busca exata para tabelas grandes.

```sql
-- Busca ANN usando VECTOR_SEARCH (requer um índice vetorial)
DECLARE @query_vector VECTOR(1536) = CAST('[...]' AS VECTOR(1536));

SELECT TOP 10
    p.ProductId,
    p.ProductName,
    vs.distance AS CosineDistance
FROM VECTOR_SEARCH(
    TABLE = dbo.Products AS p,
    COLUMN = DescriptionVector,
    SIMILAR_TO = @query_vector,
    METRIC = 'cosine',
    TOP_N = 50           -- recuperar os 50 candidatos principais do índice
) AS vs
ORDER BY vs.distance ASC
FETCH FIRST 10 ROWS ONLY;
```

O parâmetro `TOP_N` controla quantos candidatos o índice ANN retorna — um valor maior aumenta o recall ao custo de performance.

> [!important] TOP_N vs TOP Clause
>
> `TOP_N = 50` controla quantas candidatas o **índice ANN** retorna internamente. O `TOP 10` na query externa filtra o resultado final. Para boa qualidade de recuperação, use `TOP_N` maior que o número de resultados finais desejados — ex: `TOP_N = 50` para retornar 10 ao usuário.

---

## Índice Vetorial (DiskANN)

**DiskANN** (Disk-based Approximate Nearest Neighbor) é o tipo de índice vetorial no Azure SQL e Fabric SQL:

```sql
-- Criar um índice vetorial DiskANN na coluna DescriptionVector
CREATE VECTOR INDEX IX_Products_DescriptionVector
ON dbo.Products (DescriptionVector)
WITH (METRIC = 'cosine');  -- ou 'euclidean', 'dot'

-- Reconstruir o índice após inserções em lote
ALTER INDEX IX_Products_DescriptionVector ON dbo.Products REBUILD;

-- Verificar detalhes do índice vetorial
SELECT
    vector_index_type,
    distance_metric
FROM sys.vector_indexes
WHERE object_id = OBJECT_ID('dbo.Products')
  AND index_id = INDEXPROPERTY(
      OBJECT_ID('dbo.Products'), 'IX_Products_DescriptionVector', 'IndexId');
```

### Opções do Índice DiskANN

| Opção | Descrição |
| :--- | :--- |
| `METRIC` | Métrica de distância: `cosine`, `euclidean` ou `dot` |
| Tipo de índice | DiskANN é o único tipo de índice vetorial suportado |

### Quando o Optimizer Usa o Índice Vetorial

O índice vetorial é usado automaticamente por `VECTOR_SEARCH` — **não** é usado por `VECTOR_DISTANCE` em uma cláusula `ORDER BY` regular (que sempre faz busca exata/ENN).

> [!caution] Métrica do Índice deve Corresponder à Métrica da Query
>
> Se você criar o índice com `METRIC = 'cosine'` mas usar `VECTOR_SEARCH(..., METRIC = 'euclidean')`, o otimizador **não usará o índice** e fará silenciosamente um scan completo (ENN). Essa é uma armadilha de performance clássica — sempre certifique-se de que a métrica do índice corresponde à métrica da query.

---

## ANN vs ENN

```mermaid
flowchart TD
    Q["Vector query"] --> D{"Query usa<br/>WITH APPROXIMATE<br/>ou VECTOR_SEARCH TVF?"}
    D -- "sim" --> M{"Índice DiskANN<br/>correspondente na coluna<br/>+ mesma METRIC?"}
    D -- "não" --> E["ENN — scan exato<br/>O(n) todas as linhas<br/>top-K garantido"]
    M -- "sim" --> A["ANN — traversal do grafo DiskANN<br/>sub-segundo em milhões de linhas<br/>pode perder alguns vizinhos próximos"]
    M -- "não" --> W["Warning logado<br/>fallback silencioso para ENN<br/>(armadilha de performance)"]
```

| | ANN (Aproximado) | ENN (Exato) |
| :--- | :--- | :--- |
| **Sintaxe (atual)** | `SELECT TOP (N) ... ORDER BY VECTOR_DISTANCE(...) WITH APPROXIMATE` | `SELECT TOP (N) ... ORDER BY VECTOR_DISTANCE(...)` (sem `WITH APPROXIMATE`) |
| **Sintaxe (legada)** | `VECTOR_SEARCH(... TOP_N=N)` TVF — depreciada em índices mais novos | `VECTOR_DISTANCE` em `ORDER BY` |
| **Precisão** | Pode perder alguns vizinhos próximos | Top-K exato garantido |
| **Performance** | Sub-segundo em milhões de linhas | Scan linear — lento em tabelas grandes |
| **Caso de uso** | Busca em produção com grandes datasets | Tabelas pequenas ou validação |

```sql
-- ENN (Exact Nearest Neighbor) — varre cada linha
-- Preciso mas lento para tabelas grandes
SELECT TOP 10
    ProductId, ProductName,
    VECTOR_DISTANCE('cosine', DescriptionVector, @query) AS dist
FROM dbo.Products
ORDER BY dist ASC;

-- ANN (Approximate Nearest Neighbor) — usa índice DiskANN
-- Ligeiramente menos preciso, mas muito rápido
SELECT TOP 10
    p.ProductId, p.ProductName,
    vs.distance
FROM VECTOR_SEARCH(
    TABLE = dbo.Products AS p,
    COLUMN = DescriptionVector,
    SIMILAR_TO = @query,
    METRIC = 'cosine',
    TOP_N = 10
) AS vs
ORDER BY vs.distance;
```

---

## Convertendo Similaridade em Distância

`VECTOR_DISTANCE('cosine', ...)` retorna uma **distância** (0 = idêntico, 2 = oposto). Para expressar como pontuação de similaridade (0 a 1):

```sql
SELECT
    ProductId,
    1.0 - VECTOR_DISTANCE('cosine', DescriptionVector, @query_vector) AS CosineSimilarity
FROM dbo.Products
ORDER BY CosineSimilarity DESC;
```

---

## Padrão Completo de Busca com Embedding de Query

```sql
-- Padrão completo de busca semântica:
-- 1. Gerar embedding para a query do usuário
-- 2. Buscar documentos similares

-- Passo 1: gere o embedding da query com AI_GENERATE_EMBEDDINGS
-- ou no serviço de IA da aplicação e atribua-o à variável abaixo.
DECLARE @user_query NVARCHAR(500) = 'comfortable headphones for long meetings';
DECLARE @query_vector VECTOR(1536);

-- Passo 2: Encontrar produtos semanticamente similares
SELECT TOP 10
    p.ProductId,
    p.ProductName,
    p.Description,
    vs.distance AS SemanticDistance,
    1.0 - vs.distance AS SemanticSimilarity
FROM VECTOR_SEARCH(
    TABLE = dbo.Products AS p,
    COLUMN = DescriptionVector,
    SIMILAR_TO = @query_vector,
    METRIC = 'cosine',
    TOP_N = 10
) AS vs
ORDER BY vs.distance ASC;
```

---

## Casos de Uso

- **Busca semântica de produtos**: "comfortable headphones for long meetings" encontra headphones com cancelamento de ruído mesmo se as palavras da query não aparecerem nas descrições de produtos
- **Recuperação de documentos (RAG)**: Encontre chunks de documentos mais relevantes para uma pergunta do usuário antes de gerar uma resposta do LLM
- **Recomendações de itens similares**: "Clientes que viram X podem gostar de Y" — encontre produtos com embeddings de descrição similares
- **Detecção de duplicatas**: Encontre linhas quase-duplicadas onde as descrições são semanticamente equivalentes

---

## Problemas Comuns e Erros

| Problema | Causa | Correção |
| :--- | :--- | :--- |
| `Cannot use VECTOR_DISTANCE on NULL` | Vetor NULL na coluna | Adicione `WHERE DescriptionVector IS NOT NULL` |
| Erro de incompatibilidade de dimensão | Dimensão do vetor de query ≠ dimensão da coluna | Garanta que o embedding de query usa o mesmo modelo que os embeddings armazenados |
| Resultados ANN diferem do ENN | Esperado — ANN é aproximado | Aumente `TOP_N` em VECTOR_SEARCH para maior recall |
| Índice vetorial não usado | Usando `VECTOR_DISTANCE` em ORDER BY, não `VECTOR_SEARCH` | Use a função `VECTOR_SEARCH` para aproveitar o índice |
| Resultados de busca ruins | Embeddings não normalizados, usando dot product | Ou normalize os vetores ou use a métrica `cosine` |

---

## Dicas para o Exame

> [!tip] Dicas para o Exame
>
> - `VECTOR_DISTANCE('cosine', ...)` retorna uma **distância** (menor = mais similar) — não uma pontuação de similaridade
> - `VECTOR_SEARCH` usa o índice DiskANN (ANN); `VECTOR_DISTANCE` em ORDER BY é sempre ENN (exato)
> - A métrica do índice vetorial (`cosine`, `euclidean`, `dot`) deve corresponder à métrica usada em `VECTOR_SEARCH`
> - `VECTOR(1536)` armazena 1536 × 4 bytes = 6KB por linha — leve isso em conta no planejamento de armazenamento
> - `VECTOR_NORMALIZE` com `'norm2'` normaliza para comprimento unitário — necessário antes de usar dot product como cosine similarity

---

## Principais Conclusões

- Tipo de dado `VECTOR` armazena arrays de ponto flutuante de dimensão fixa
- `VECTOR_DISTANCE` computa distâncias exatas; `VECTOR_SEARCH` usa ANN para busca aproximada escalável
- Crie um índice DiskANN na coluna vetorial para habilitar busca ANN rápida
- Use distância cosseno para embeddings de texto; ela é robusta a diferenças na magnitude do vetor

---

## Tópicos Relacionados

- [01-Full-Text Search](./01-fulltext-search.md)
- [03-Hybrid Search e RRF](./03-hybrid-search-rrf.md)
- [03-Chunking e Geração](../09-models-embeddings/03-chunking-generation.md)
- [11-RAG: Casos de Uso](../11-rag/01-rag-use-cases.md) — a busca vetorial é o motor de recuperação para RAG
- [11-RAG: Prompts e Respostas](../11-rag/02-prompts-and-responses.md)

---

## Documentação Oficial

- [VECTOR Data Type](https://learn.microsoft.com/en-us/sql/t-sql/data-types/vector-data-type)
- [VECTOR_DISTANCE](https://learn.microsoft.com/en-us/sql/t-sql/functions/vector-distance-transact-sql)
- [VECTOR_SEARCH](https://learn.microsoft.com/en-us/sql/t-sql/functions/vector-search-transact-sql)
- [DiskANN Vector Index](https://learn.microsoft.com/en-us/azure/azure-sql/database/vector-index)

---

**[← Anterior](./01-fulltext-search.md) | [↑ Voltar à Seção](./intelligent-search.md) | [Próximo →](./03-hybrid-search-rrf.md)**
