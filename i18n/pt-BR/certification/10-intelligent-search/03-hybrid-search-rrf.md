---
title: Hybrid Search e Reciprocal Rank Fusion (Hybrid Search and Reciprocal Rank Fusion)
type: study-material
tags:
  - dp-800
  - hybrid-search
  - rrf
  - reciprocal-rank-fusion
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral](#visão-geral)
> - 📍 [2. Quando Usar Cada Tipo de Busca](#quando-usar-cada-tipo-de-busca)
> - 📍 [3. Algoritmo Reciprocal Rank Fusion](#algoritmo-reciprocal-rank-fusion)
> - 📍 [4. Implementando Hybrid Search com RRF em T-SQL](#implementando-hybrid-search-com-rrf-em-t-sql)
> - 📍 [5. RRF Simplificado Sem Índice Vetorial](#rrf-simplificado-sem-índice-vetorial)
> - 📍 [6. Avaliando a Performance da Busca](#avaliando-a-performance-da-busca)
>   - 🔹 [Recall](#recall)
>   - 🔹 [Precisão](#precisão)
>   - 🔹 [Mean Reciprocal Rank (MRR)](#mean-reciprocal-rank-mrr)
>   - 🔹 [Avaliando com Ground Truth](#avaliando-com-ground-truth)
>   - 🔹 [Medição de Latência](#medição-de-latência)
> - 📍 [7. Ajustando RRF — Ajustando k](#ajustando-rrf-ajustando-k)
> - 📍 [8. Casos de Uso](#casos-de-uso)
> - 📍 [9. Problemas Comuns e Erros](#problemas-comuns-e-erros)
> - 📍 [10. Dicas para o Exame](#dicas-para-o-exame)
> - 📍 [11. Principais Conclusões](#principais-conclusões)
> - 📍 [12. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [13. Documentação Oficial](#documentação-oficial)

---

# Hybrid Search e Reciprocal Rank Fusion

## Visão Geral

O Hybrid Search combina a full-text search (correspondência por palavras-chave) com a busca vetorial (similaridade semântica) para produzir resultados melhores do que qualquer uma sozinha. O desafio é mesclar duas listas ranqueadas com diferentes escalas de pontuação. O **Reciprocal Rank Fusion (RRF)** é o algoritmo padrão para combinar listas ranqueadas sem precisar normalizar pontuações — ele usa apenas a posição do rank, não os valores de pontuação.

> [!abstract]
>
> - Aborda o hybrid search: combinando resultados de full-text search e busca vetorial usando Reciprocal Rank Fusion (RRF)
> - O hybrid search melhora em relação a cada método individualmente capturando tanto precisão de palavras-chave quanto recall semântico
> - Tópicos-chave para o exame: fórmula RRF, parâmetro k, como combinar result sets, quando o hybrid supera o método único

> [!tip] O Que o Exame Testa
>
> - **Fórmula RRF**: `score = Σ 1/(k + rank)` para cada result set; `k = 60` é uma convenção comum, mas deve ser ajustado e validado para o conjunto de dados
> - RRF é um **algoritmo de combinação de ranks** — combina os ranks de resultados de múltiplas fontes, não suas pontuações brutas
> - O hybrid search supera o método único quando as queries misturam palavras-chave exatas e significado semântico

---

## Fundamentos: duas formas de evidência, uma lista final

Full-text e busca vetorial respondem a sinais diferentes. A primeira favorece termos exatos, códigos, frases e regras linguísticas; a segunda favorece intenção e significado aproximado. Uma mesma pergunta pode precisar dos dois: um usuário pode escrever o nome exato de uma política e, ao mesmo tempo, usar uma formulação diferente daquela armazenada no documento.

O problema é que os scores não têm a mesma escala nem o mesmo significado. Um `RANK` de Full-Text Search é produzido pelo mecanismo linguístico; uma distância ou similaridade vetorial vem de uma métrica matemática. Somá-los diretamente cria pesos arbitrários. O **Reciprocal Rank Fusion (RRF)** resolve isso ignorando os valores brutos e combinando apenas a posição de cada item nas listas: aparecer nas primeiras posições de uma ou das duas fontes aumenta sua pontuação final.

RRF não cria relevância do nada. Ele só reorganiza candidatos recuperados pelas buscas individuais. Portanto, escolha um número razoável de candidatos de cada fonte, aplique filtros de segurança antes da fusão e avalie com perguntas e resultados esperados (*ground truth*). Se a lista final traz resultados ruins, investigue primeiro a qualidade do índice, dos embeddings, dos chunks e das consultas de origem antes de ajustar `k`.

## Quando Usar Cada Tipo de Busca

| Cenário | Melhor Abordagem |
| :--- | :--- |
| Busca de código de produto exato (SKU-123) | Apenas full-text (palavras-chave) |
| Query em linguagem natural, intenção vaga | Apenas vetorial |
| Query curta com termos específicos e significado semântico | Híbrida (ambas) |
| Formas flexionadas ou sinônimos configurados no thesaurus | Full-text (`FORMSOF`) |
| Busca multilíngue | Vetorial (embeddings lidam com tradução) |
| Requisito de alto recall (não perder nada relevante) | Híbrida |

---

## Algoritmo Reciprocal Rank Fusion

O RRF combina listas ranqueadas atribuindo a cada documento uma pontuação baseada em seu rank em cada lista:

```text
RRF_score(doc) = Σ  1 / (k + rank_in_list_i)
```

Onde `k` é uma constante (tipicamente 60) que reduz o impacto de ranks muito altos.

**Exemplo:**

| Documento | Rank FTS | Rank Vetorial | Pontuação RRF (k=60) |
| :--- | :--- | :--- | :--- |
| Produto A | 1 | 3 | 1/(60+1) + 1/(60+3) = 0,0164 + 0,0159 = **0,0323** |
| Produto B | 5 | 1 | 1/(60+5) + 1/(60+1) = 0,0154 + 0,0164 = **0,0318** |
| Produto C | 2 | 50 | 1/(60+2) + 1/(60+50) = 0,0161 + 0,0091 = **0,0252** |
| Produto D | 100 | 2 | 1/(60+100) + 1/(60+2) = 0,0063 + 0,0161 = **0,0224** |

Documentos que aparecem em ambas as listas pontuam mais alto do que os que aparecem em apenas uma. A constante `k=60` evita que um resultado em posição 1 em uma lista domine completamente se tiver pontuação ruim na outra.

![Hybrid Search & Reciprocal Rank Fusion Architecture](../../../../dist/images/hybrid_search_rrf_architecture.png)

> [!note] Por Que k=60?
>
> O valor `k=60` é uma convenção usada em várias implementações de RRF. Com `k=1`, o rank 1 domina mais; com `k=100`, a distribuição é mais uniforme. Trate `k` como parâmetro de relevância a ser avaliado com dados reais, não como regra universal.

---

## Implementando Hybrid Search com RRF em T-SQL

```sql
CREATE OR ALTER PROCEDURE dbo.HybridSearch
    @query_text   NVARCHAR(500),
    @query_vector VECTOR(1536),
    @top_n        INT = 10,
    @rrf_k        INT = 60
AS
BEGIN
    SET NOCOUNT ON;

    -- A aplicação ou o chamador gera @query_vector com o mesmo modelo
    -- usado nos embeddings persistidos.

    -- Passo 2: Resultados de full-text search com rank
    WITH FTSResults AS (
        SELECT
            p.[KEY]   AS ProductId,
            p.[RANK]  AS FTSScore,
            ROW_NUMBER() OVER (ORDER BY p.[RANK] DESC) AS FTSRank
        FROM FREETEXTTABLE(
            dbo.Products, (ProductName, Description), @query_text, LANGUAGE 1033, 50
        ) AS p
    ),

    -- Passo 3: Resultados de busca vetorial com rank
    VectorResults AS (
        SELECT TOP (50) WITH APPROXIMATE
            vs.ProductId,
            vs.distance AS VectorDistance,
            ROW_NUMBER() OVER (ORDER BY vs.distance) AS VectorRank
        FROM VECTOR_SEARCH(
            TABLE = dbo.Products,
            COLUMN = DescriptionVector,
            SIMILAR_TO = @query_vector,
            METRIC = 'cosine'
        ) AS vs
        ORDER BY vs.distance
    ),

    -- Passo 4: Combinar com RRF
    RRFScores AS (
        SELECT
            COALESCE(f.ProductId, v.ProductId) AS ProductId,
            -- Fórmula RRF: soma de 1/(k + rank) em todas as listas
            COALESCE(1.0 / (@rrf_k + f.FTSRank), 0) +
            COALESCE(1.0 / (@rrf_k + v.VectorRank), 0) AS RRFScore,
            f.FTSScore,
            f.FTSRank,
            v.VectorDistance,
            v.VectorRank
        FROM FTSResults f
        FULL OUTER JOIN VectorResults v ON f.ProductId = v.ProductId
    )

    -- Passo 5: Retornar top N resultados
    SELECT TOP (@top_n)
        r.ProductId,
        p.ProductName,
        p.Description,
        r.RRFScore,
        r.FTSRank,
        r.VectorRank,
        r.VectorDistance
    FROM RRFScores r
    JOIN dbo.Products p ON p.ProductId = r.ProductId
    ORDER BY r.RRFScore DESC;
END;
```

```sql
-- Uso
-- @query_vector deve ser gerado com o mesmo modelo dos vetores persistidos.
DECLARE @query_vector VECTOR(1536) = CAST('[...]' AS VECTOR(1536));
EXEC dbo.HybridSearch
    @query_text = 'comfortable wireless headphones for work',
    @query_vector = @query_vector,
    @top_n = 10;
```

> [!important] FULL OUTER JOIN é Obrigatório
>
> Um documento pode aparecer apenas em uma das duas listas de resultados. Se você usar `INNER JOIN`, perderá documentos que correspondem apenas à busca vetorial ou apenas à busca full-text. **Sempre use `FULL OUTER JOIN`** para garantir que todos os candidatos de ambas as listas sejam incluídos na pontuação RRF.

---

## RRF Simplificado Sem Índice Vetorial

Para tabelas menores onde o scan completo do vetor é aceitável:

```sql
DECLARE @query_text   NVARCHAR(500) = 'ergonomic keyboard for developers';
DECLARE @query_vector VECTOR(1536);
DECLARE @rrf_k        INT = 60;
DECLARE @top_n        INT = 10;

-- Gere o embedding da query com AI_GENERATE_EMBEDDINGS ou no serviço
-- de IA da aplicação antes de executar a busca.

WITH FTSResults AS (
    SELECT
        [KEY] AS ProductId,
        ROW_NUMBER() OVER (ORDER BY [RANK] DESC) AS FTSRank
    FROM FREETEXTTABLE(dbo.Products, *, @query_text, LANGUAGE 1033, 50)
),
VectorResults AS (
    SELECT
        ProductId,
        ROW_NUMBER() OVER (ORDER BY VECTOR_DISTANCE('cosine', DescriptionVector, @query_vector) ASC) AS VectorRank
    FROM dbo.Products
    WHERE DescriptionVector IS NOT NULL
),
RRF AS (
    SELECT
        COALESCE(f.ProductId, v.ProductId) AS ProductId,
        ISNULL(1.0 / (@rrf_k + f.FTSRank), 0) +
        ISNULL(1.0 / (@rrf_k + v.VectorRank), 0) AS RRFScore
    FROM FTSResults f
    FULL OUTER JOIN VectorResults v ON f.ProductId = v.ProductId
)
SELECT TOP (@top_n)
    r.ProductId,
    p.ProductName,
    r.RRFScore
FROM RRF r
JOIN dbo.Products p ON p.ProductId = r.ProductId
ORDER BY r.RRFScore DESC;
```

---

## Avaliando a Performance da Busca

### Recall

O recall mede quantos itens relevantes são retornados de todos os itens relevantes existentes:

```text
Recall@K = |Itens relevantes no top K| / |Total de itens relevantes|
```

- Maior é melhor
- O hybrid search normalmente melhora o recall em relação a qualquer abordagem individual

### Precisão

A precisão mede quantos itens retornados são realmente relevantes:

```text
Precision@K = |Itens relevantes no top K| / K
```

- Maior é melhor
- A busca por palavras-chave pode ter alta precisão mas baixo recall para queries semânticas

### Mean Reciprocal Rank (MRR)

```text
MRR = (1/|Q|) × Σ (1 / rank_do_primeiro_resultado_relevante)
```

- Mede quão rapidamente o primeiro resultado relevante aparece

### Avaliando com Ground Truth

```sql
-- Criar um conjunto de testes com produtos relevantes conhecidos para queries
CREATE TABLE dbo.SearchEvaluation (
    EvalId      INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    QueryText   NVARCHAR(500) NOT NULL,
    RelevantIds NVARCHAR(MAX) NOT NULL  -- array JSON de ProductIds relevantes
);

INSERT INTO dbo.SearchEvaluation (QueryText, RelevantIds) VALUES
('wireless noise cancelling headphones', '[1, 7, 23, 45]'),
('ergonomic mechanical keyboard', '[12, 88, 91]');

-- Avaliar: para cada query de teste, medir Precision@10
-- (Comparar ProductIds retornados no top-10 com RelevantIds)
```

### Medição de Latência

```sql
-- Medir latência do hybrid search
DECLARE @start DATETIME2 = SYSDATETIME();
EXEC dbo.HybridSearch @query_text = 'wireless audio', @top_n = 10;
SELECT DATEDIFF(MILLISECOND, @start, SYSDATETIME()) AS LatencyMs;
```

**Alavancas de otimização de performance:**

| Alavanca | Impacto |
| :--- | :--- |
| Índice vetorial (DiskANN) | Maior — milissegundos vs segundos para ANN |
| Índice FTS | Maior — instantâneo vs full table scan |
| Reduzir `TOP (N)` aproximado | Menor — menos candidatos |
| Reduzir limite de resultados FTS | Menor — avaliação FTS mais rápida |
| Pré-normalizar embeddings | Menor — pula VECTOR_NORMALIZE no tempo de query |

---

## Ajustando RRF — Ajustando k

A constante `k` controla quanto as posições de alto rank importam:

```sql
-- k=60 (convenção comum): reduz impacto dos primeiros ranks
-- k=1: primeiro rank domina (ponderação extrema para rank 1)
-- k=100: pontuação mais uniforme entre ranks

-- Experimente com diferentes valores de k para ajustar para seu dataset
EXEC dbo.HybridSearch @query_text = 'wireless headphones', @top_n = 10, @rrf_k = 60;
EXEC dbo.HybridSearch @query_text = 'wireless headphones', @top_n = 10, @rrf_k = 20;
```

k menor → resultados top-ranqueados recebem mais peso
k maior → distribuição mais uniforme entre ranks

---

## Casos de Uso

- **Busca de produtos em e-commerce**: Usuários digitam queries curtas ricas em palavras-chave, mas podem usar terminologia diferente das descrições de produtos — o hybrid lida com ambos
- **Busca em base de conhecimento**: Artigos técnicos têm terminologia específica (FTS), mas usuários frequentemente parafraseiam (vetorial)
- **Suporte ao cliente**: O hybrid search encontra a melhor correspondência de FAQ mesmo quando a formulação do usuário difere da pergunta do FAQ
- **Recuperação de documentos RAG**: Garante que tanto correspondências de palavras-chave quanto chunks semanticamente similares sejam considerados

---

## Problemas Comuns e Erros

| Problema | Causa | Correção |
| :--- | :--- | :--- |
| Uma lista sempre domina | k muito pequeno; uma lista muito maior | Aumente k; garanta que ambas as listas retornem número similar de candidatos |
| FTS não retorna nada | Stop words removeram todos os termos da query | Adicione fallback: se FTS vazio, use apenas vetorial |
| RRFScore NULL | FULL OUTER JOIN sem resultado FTS | Use `ISNULL(..., 0)` em torno dos componentes de pontuação RRF |
| Hybrid search lento | Sem índice vetorial compatível | Crie índice DiskANN; use `WITH APPROXIMATE` |
| Baixo recall | Quantidade aproximada de candidatos muito pequena | Aumente `TOP (N)` antes do top-10 final |

---

## Dicas para o Exame

> [!tip] Dicas para o Exame
>
> - RRF usa **ranks**, não pontuações brutas — isso o torna invariante a escala e robusto a diferentes sistemas de pontuação
> - `k=60` é uma convenção comum de RRF; em T-SQL, trate-o como parâmetro a validar no corpus
> - `FULL OUTER JOIN` é essencial — um documento pode aparecer em apenas um dos dois result sets
> - O hybrid search melhora o **recall** (encontra mais itens relevantes) comparado a usar apenas uma abordagem
> - A busca vetorial lida com similaridade semântica; a full-text lida com palavras-chave exatas — nenhuma sozinha é ótima para busca em produção

---

## Principais Conclusões

- Hybrid search = full-text search + busca vetorial, mesclados com RRF
- Fórmula RRF: `1 / (k + rank)` somado em todas as listas de resultados — pontuação maior = melhor rank combinado
- Use `FULL OUTER JOIN` para mesclar as duas listas para que documentos aparecendo em apenas uma lista ainda sejam incluídos
- Meça recall, precisão e latência para avaliar e ajustar o pipeline de hybrid search

---

## RRF versus score ponderado

RRF funde **ranks** e evita escalas incompatíveis. Fórmula ponderada requer
distância numérica e normalização de `RANK`: `(distance * 0.60) + ((1.0 - rank /
1000.0) * 0.40)`. Se a fórmula precisa da distância, use `VECTOR_DISTANCE`, não
`WITH APPROXIMATE`.

## Tópicos Relacionados

- [01-Full-Text Search](./01-fulltext-search.md)
- [02-Busca Vetorial](./02-vector-search.md)
- [01-RAG Casos de Uso](../11-rag/01-rag-use-cases.md)

---

## Documentação Oficial

- [Hybrid Search in Azure AI Search](https://learn.microsoft.com/en-us/azure/search/hybrid-search-overview)
- [Reciprocal Rank Fusion](https://learn.microsoft.com/en-us/azure/search/hybrid-search-ranking)
- [VECTOR_SEARCH](https://learn.microsoft.com/en-us/sql/t-sql/functions/vector-search-transact-sql)

---

**[← Anterior](./02-vector-search.md) | [↑ Voltar à Seção](./intelligent-search.md)**
