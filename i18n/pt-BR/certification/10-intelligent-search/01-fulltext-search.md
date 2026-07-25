---
title: Full-Text Search (Busca Full-Text)
type: study-material
tags:
  - dp-800
  - full-text-search
  - fts
  - contains
  - freetext
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral](#visão-geral)
> - 📍 [2. Catálogos e Índices Full-Text](#catálogos-e-índices-full-text)
>   - 🔹 [Criando um Full-Text Catalog](#criando-um-full-text-catalog)
>   - 🔹 [Criando um Full-Text Index](#criando-um-full-text-index)
>   - 🔹 [Opções de Change Tracking](#opções-de-change-tracking)
>   - 🔹 [Population (Construindo o Índice)](#population-construindo-o-índice)
> - 📍 [3. Stop Lists](#stop-lists)
> - 📍 [4. CONTAINS — Predicado de Busca Precisa](#contains-predicado-de-busca-precisa)
>   - 🔹 [Busca de Termo Simples](#busca-de-termo-simples)
>   - 🔹 [Busca por Prefixo](#busca-por-prefixo)
>   - 🔹 [Busca por Frase](#busca-por-frase)
>   - 🔹 [Operadores Booleanos](#operadores-booleanos)
>   - 🔹 [NEAR — Busca por Proximidade](#near-busca-por-proximidade)
>   - 🔹 [FORMSOF — Correspondência Inflexional e de Thesaurus](#formsof-correspondência-inflexional-e-de-thesaurus)
> - 📍 [5. FREETEXT — Busca em Linguagem Natural](#freetext-busca-em-linguagem-natural)
> - 📍 [6. CONTAINSTABLE e FREETEXTTABLE — Resultados Ranqueados](#containstable-e-freetexttable-resultados-ranqueados)
>   - 🔹 [CONTAINSTABLE](#containstable)
>   - 🔹 [FREETEXTTABLE](#freetexttable)
>   - 🔹 [Top N Resultados com FREETEXTTABLE](#top-n-resultados-com-freetexttable)
> - 📍 [7. Suporte a Idiomas](#suporte-a-idiomas)
> - 📍 [8. Casos de Uso](#casos-de-uso)
> - 📍 [9. Problemas Comuns e Erros](#problemas-comuns-e-erros)
> - 📍 [10. Dicas para o Exame](#dicas-para-o-exame)
> - 📍 [11. Principais Conclusões](#principais-conclusões)
> - 📍 [12. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [13. Documentação Oficial](#documentação-oficial)

---

# Full-Text Search (Busca Full-Text)

## Visão Geral

A Full-Text Search (FTS) habilita a busca linguística de dados baseados em caracteres — correspondendo palavras, frases, proximidade e formas flexionadas. Diferente de queries `LIKE` (que fazem correspondência de padrões de caracteres), a FTS usa um **índice invertido** e entende semântica de idioma (radicais, sinônimos, stop words). Os predicados principais são `CONTAINS` (correspondência precisa de termos) e `FREETEXT` (correspondência em linguagem natural).

> [!abstract]
>
> - Aborda Full-Text Search no Azure SQL: CONTAINS, FREETEXT, CONTAINSTABLE, FREETEXTTABLE e índices full-text
> - A Full-Text Search habilita buscas linguísticas e de proximidade além do padrão LIKE
> - Tópicos-chave para o exame: casos de uso de CONTAINS vs FREETEXT, requisito de índice full-text, resultados ranqueados com variantes TABLE

> [!tip] O Que o Exame Testa
>
> - `CONTAINS` = **precisão**: termos exatos, prefixo (`"data*"`), proximidade (`NEAR`), termos ponderados (`ISABOUT`)
> - `FREETEXT` = **recall**: query em linguagem natural, flexões e sinônimos, correspondência mais ampla
> - `CONTAINSTABLE` / `FREETEXTTABLE` retornam uma tabela com coluna `RANK` (0–1000) — use quando precisar de resultados ranqueados ou quiser fazer join com outras tabelas

---

## Catálogos e Índices Full-Text

### Criando um Full-Text Catalog

```sql
-- Um full-text catalog é um contêiner lógico para índices full-text
CREATE FULLTEXT CATALOG [ProductCatalog] AS DEFAULT;

-- Verificar
SELECT * FROM sys.fulltext_catalogs;
```

### Criando um Full-Text Index

```sql
-- Um full-text index requer:
-- 1. Um índice único, de coluna única, não-nulo (normalmente a PK)
-- 2. Um full-text catalog

-- Criar full-text index na tabela Products
CREATE FULLTEXT INDEX ON dbo.Products (
    ProductName LANGUAGE 1033,       -- 1033 = Inglês
    Description LANGUAGE 1033
)
KEY INDEX PK_Products
ON ProductCatalog
WITH (CHANGE_TRACKING = AUTO,        -- AUTO = SQL rastreia mudanças nos dados indexados
      STOPLIST = SYSTEM);            -- Usar a stop list do sistema

-- Verificar
SELECT * FROM sys.fulltext_indexes;
SELECT * FROM sys.fulltext_index_columns;
```

> [!note] Pré-requisito: Índice Único na Chave
>
> O Full-Text Index **exige** um índice B-Tree único de coluna única na tabela (normalmente a Primary Key). Sem ele, `CREATE FULLTEXT INDEX` falhará. Isso é diferente dos índices vetoriais (DiskANN), que vão direto na coluna vetorial.

### Opções de Change Tracking

| Opção | Comportamento |
| :--- | :--- |
| `AUTO` | SQL Server atualiza automaticamente o índice FTS quando linhas mudam |
| `MANUAL` | Atualiza apenas quando você chama `ALTER FULLTEXT INDEX ... START UPDATE POPULATION` |
| `OFF` | Sem rastreamento de mudanças; apenas população manual completa |

### Population (Construindo o Índice)

```sql
-- Iniciar uma população completa (reconstruir o índice inteiro)
ALTER FULLTEXT INDEX ON dbo.Products START FULL POPULATION;

-- Iniciar uma população incremental (apenas linhas alteradas desde a última population)
ALTER FULLTEXT INDEX ON dbo.Products START INCREMENTAL POPULATION;

-- Verificar o status da population
SELECT FULLTEXTCATALOGPROPERTY('ProductCatalog', 'PopulateStatus') AS Status;
-- 0 = Idle, 1 = Full population em progresso, 5 = Throttled

-- Verificar se o índice full-text está populado
SELECT OBJECTPROPERTYEX(OBJECT_ID('dbo.Products'), 'TableFulltextPopulateStatus');
```

---

## Stop Lists

Stop words (palavras comuns como "the", "and", "is") são excluídas do índice:

```sql
-- Criar uma stop list customizada
CREATE FULLTEXT STOPLIST [MyStopList] FROM SYSTEM STOPLIST;

-- Adicionar stop words customizadas
ALTER FULLTEXT STOPLIST [MyStopList] ADD 'product' LANGUAGE 'English';
ALTER FULLTEXT STOPLIST [MyStopList] ADD 'item' LANGUAGE 'English';

-- Atribuir a um índice
ALTER FULLTEXT INDEX ON dbo.Products SET STOPLIST = [MyStopList];

-- Ver stop words
SELECT * FROM sys.fulltext_stopwords WHERE stoplist_id =
    (SELECT stoplist_id FROM sys.fulltext_stoplists WHERE name = 'MyStopList');
```

> [!warning] Stop Words Podem Suprimir Resultados Esperados
>
> Stop words são descartadas pelo mecanismo de Full-Text Search. Sempre verifique `sys.fulltext_stopwords` e a opção de transformação de noise words ao depurar consultas que retornam resultados inesperados.

---

## CONTAINS — Predicado de Busca Precisa

`CONTAINS` busca linhas que correspondam a critérios específicos de termos. Retorna um booleano (usado na cláusula WHERE).

### Busca de Termo Simples

```sql
-- Encontrar produtos contendo a palavra "wireless"
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'wireless');

-- Buscar em múltiplas colunas
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS((ProductName, Description), 'bluetooth');

-- Buscar em todas as colunas indexadas full-text
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(*, 'ergonomic');
```

### Busca por Prefixo

```sql
-- Encontrar palavras começando com "comput" (matches: computer, computing, computational)
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, '"comput*"');

-- Múltiplos termos de prefixo
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, '"wire*" OR "blue*"');
```

### Busca por Frase

```sql
-- Correspondência exata de frase
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, '"noise cancelling"');

-- Frase com OR
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, '"noise cancelling" OR "active noise"');
```

> [!important] Aspas Duplas para Frases
>
> Buscas de frases em `CONTAINS` **exigem** aspas duplas internas: `'"noise cancelling"'`. Esquecer as aspas causará um erro de sintaxe. A string externa usa aspas simples (sintaxe T-SQL padrão), a frase interna usa aspas duplas.

### Operadores Booleanos

```sql
-- AND: ambos os termos devem aparecer
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'wireless AND headphones');

-- OR: qualquer um dos termos
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'wireless OR bluetooth');

-- AND NOT: primeiro termo mas não o segundo
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'headphones AND NOT "in-ear"');
```

### NEAR — Busca por Proximidade

```sql
-- NEAR: termos dentro de 50 palavras um do outro (proximidade padrão)
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'NEAR((wireless, headphones), 5)');
-- Termos dentro de 5 palavras um do outro

-- NEAR ordenado (primeiro termo deve vir antes do segundo)
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'NEAR((noise, cancelling), 3, TRUE)');
-- TRUE = ordenado
```

### FORMSOF — Correspondência Inflexional e de Thesaurus

```sql
-- FORMSOF INFLECTIONAL: correspondências de formas flexionadas (run, runs, running, ran)
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'FORMSOF(INFLECTIONAL, "connect")');
-- Corresponde a formas flexionais do termo, como connect, connects,
-- connected e connecting; não pressupõe derivações como "connection".

-- FORMSOF THESAURUS: correspondências de sinônimos do arquivo de thesaurus
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'FORMSOF(THESAURUS, "fast")');
-- Corresponde: fast, quick, rapid, speedy (dependendo da configuração do thesaurus)
```

---

## FREETEXT — Busca em Linguagem Natural

`FREETEXT` divide a string de entrada em palavras e busca por qualquer uma delas e suas variações linguísticas. É menos preciso que CONTAINS, mas mais amigável para linguagem natural.

```sql
-- Busca em linguagem natural — encontra linhas sobre áudio sem fio rápido
SELECT ProductId, ProductName
FROM dbo.Products
WHERE FREETEXT(Description, 'fast wireless audio headphones');

-- FREETEXT automaticamente:
-- 1. Remove stop words
-- 2. Encontra formas flexionadas (connected → connect, connecting, connection)
-- 3. Expande para sinônimos do thesaurus (se configurado)
-- 4. Usa lógica OR (qualquer uma das palavras pode corresponder)
```

> [!note] CONTAINS vs FREETEXT — Quando Usar Cada Um
>
> | | CONTAINS | FREETEXT |
> |---|---|---|
> | **Quando usar** | Controle preciso: prefixos, frases exatas, proximidade, booleanos | Linguagem natural, intenção do usuário |
> | **Resultado** | Booleano na cláusula WHERE | Booleano na cláusula WHERE |
> | **Ranking** | Não (use CONTAINSTABLE) | Não (use FREETEXTTABLE) |
> | **Variações** | Via FORMSOF explícito | Automático |

---

## CONTAINSTABLE e FREETEXTTABLE — Resultados Ranqueados

Estas funções com valor de tabela retornam linhas correspondentes com uma pontuação `RANK` (0–1000, maior = melhor correspondência relativa):

### CONTAINSTABLE

```sql
-- Obter produtos correspondendo a "wireless headphones" com pontuações de rank
SELECT
    p.ProductId,
    p.ProductName,
    p.Description,
    ct.[RANK] AS SearchRank
FROM CONTAINSTABLE(dbo.Products, Description, 'wireless AND headphones') AS ct
JOIN dbo.Products p ON p.ProductId = ct.[KEY]
ORDER BY ct.[RANK] DESC;
```

### FREETEXTTABLE

```sql
-- Busca em linguagem natural com rankings
SELECT
    p.ProductId,
    p.ProductName,
    ftt.[RANK] AS SearchRank
FROM FREETEXTTABLE(dbo.Products, (ProductName, Description), 'comfortable wireless earbuds') AS ftt
JOIN dbo.Products p ON p.ProductId = ftt.[KEY]
WHERE ftt.[RANK] > 50  -- filtrar por relevância mínima
ORDER BY ftt.[RANK] DESC;
```

### Top N Resultados com FREETEXTTABLE

```sql
-- Obter os 10 resultados mais relevantes
SELECT TOP 10
    p.ProductId,
    p.ProductName,
    ftt.[RANK]
FROM FREETEXTTABLE(dbo.Products, Description, 'wireless audio', LANGUAGE 1033, 10) AS ftt
JOIN dbo.Products p ON p.ProductId = ftt.[KEY]
ORDER BY ftt.[RANK] DESC;
-- O 4º parâmetro (10) limita resultados dentro do engine FTS
```

> [!tip] Use as Variantes TABLE para Busca Ranqueada
>
> `CONTAINS` e `FREETEXT` são predicados — retornam apenas SIM/NÃO. Para ordenar resultados por relevância (como uma UI de busca), use `CONTAINSTABLE` ou `FREETEXTTABLE` — eles expõem a coluna `RANK` (1–1000) que você pode usar em `ORDER BY`.

---

## Suporte a Idiomas

```sql
-- Criar índice full-text com múltiplos idiomas
CREATE FULLTEXT INDEX ON dbo.Products (
    Name LANGUAGE 'English',
    DescriptionDE LANGUAGE 'German',
    DescriptionFR LANGUAGE 'French'
)
KEY INDEX PK_Products ON ProductCatalog;

-- Listar IDs de idiomas disponíveis
SELECT lcid, name FROM sys.fulltext_languages ORDER BY name;
-- Comuns: 1033=Inglês, 1031=Alemão, 1036=Francês, 1041=Japonês
```

---

## Casos de Uso

- **Busca de produtos**: Corresponda nomes e descrições de produtos para busca por palavras-chave em e-commerce
- **Busca em biblioteca de documentos**: Encontre artigos contendo termos ou frases específicos
- **Base de conhecimento**: Pesquise FAQ ou artigos de suporte usando queries em linguagem natural
- **FREETEXTTABLE para ranking**: Retorne resultados ordenados por relevância, não apenas pela presença de palavras-chave

---

## Problemas Comuns e Erros

| Problema | Causa | Correção |
| :--- | :--- | :--- |
| Erro `No full-text index` | FTS não habilitado na tabela | `CREATE FULLTEXT INDEX ON dbo.Products ...` |
| Query não retorna resultados | Stop words excluíram o termo de busca | Verifique se o termo está na stop list; consulte `sys.fulltext_stopwords` |
| Índice desatualizado | `CHANGE_TRACKING = MANUAL` | Mude para AUTO ou chame manualmente `START UPDATE POPULATION` |
| FORMSOF THESAURUS não retorna nada | Arquivo de thesaurus não configurado | Edite o arquivo XML de thesaurus para o idioma |
| Erro de sintaxe em CONTAINS | Aspas ausentes em torno de frases | Buscas de frases exigem aspas duplas: `'"noise cancelling"'` |

---

## Dicas para o Exame

> [!tip] Dicas para o Exame
>
> - `CONTAINS` retorna correspondência booleana — use na cláusula WHERE; `CONTAINSTABLE` retorna resultados ranqueados — use como tabela
> - `FREETEXT` é para linguagem natural; `CONTAINS` é para controle preciso (prefixo, proximidade, booleano)
> - **Stop words** podem suprimir resultados esperados — se "product" estiver na stop list, buscar "product" não retorna nada
> - `CHANGE_TRACKING = AUTO` mantém o índice FTS atualizado; `MANUAL` requer repopulação explícita
> - `FORMSOF(INFLECTIONAL, ...)` — ótimo para formas verbais (buscar "run" encontra "running", "ran", "runs")
> - `RANK` de CONTAINSTABLE/FREETEXTTABLE varia de 0 a 1000 e é útil para ordenar relevância relativa; o valor absoluto pode mudar entre execuções

---

## Principais Conclusões

- Índices full-text requerem um full-text catalog e um índice de chave único
- `CONTAINS`/`CONTAINSTABLE` para buscas precisas de termos, prefixos, frases, proximidade e booleanos
- `FREETEXT`/`FREETEXTTABLE` para buscas em linguagem natural que tratam variações automaticamente
- Use `FREETEXTTABLE` quando precisar de resultados ranqueados por relevância para UIs de busca

---

## Tópicos Relacionados

- [02-Busca Vetorial](./02-vector-search.md)
- [03-Hybrid Search e RRF](./03-hybrid-search-rrf.md)
- [03-Chunking e Geração](../09-models-embeddings/03-chunking-generation.md)

---

## Documentação Oficial

- [Full-Text Search (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/search/full-text-search)
- [CONTAINS (T-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/queries/contains-transact-sql)
- [FREETEXTTABLE (T-SQL)](https://learn.microsoft.com/en-us/sql/relational-databases/system-functions/freetexttable-transact-sql)

---

**[↑ Voltar à Seção](./intelligent-search.md) | [Próximo →](./02-vector-search.md)**
