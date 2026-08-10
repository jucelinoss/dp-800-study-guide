---
title: Full-Text Search
type: study-material
tags:
  - dp-800
  - full-text-search
  - fts
  - contains
  - freetext
---

# Full-Text Search

## Overview

Full-text search (FTS) enables linguistic searching of character-based data — matching words, phrases, proximity, and inflected forms. Unlike LIKE queries (which do character pattern matching), FTS uses an **inverted index** and language-specific word breaking, stemming, and stop words. Thesaurus synonyms are available only when mappings are configured. The key predicates are `CONTAINS` (precise term matching) and `FREETEXT` (natural language matching).

> [!abstract]
>
> - Covers full-text search in Azure SQL: CONTAINS, FREETEXT, CONTAINSTABLE, FREETEXTTABLE, and full-text indexes
> - Full-text search enables linguistic and proximity searches beyond LIKE pattern matching
> - Key exam topics: CONTAINS vs FREETEXT use cases, full-text index requirement, ranked results with TABLE variants

> [!tip] What the Exam Tests
>
> - `CONTAINS` tends toward **higher precision**: exact terms, prefixes (`"data*"`), proximity (`NEAR`), Boolean conditions, and weighted terms (`ISABOUT`) let the query restrict what counts as a match
> - `FREETEXT` tends toward **higher recall**: natural-language input, inflectional forms, and configured thesaurus mappings broaden the candidates, which can also introduce less relevant results
> - `CONTAINSTABLE` / `FREETEXTTABLE` return a table with a `RANK` column (0–1000) — use when you need ranked results or want to join with other tables

> [!note] Precision, recall, and `RANK`
>
> **Precision** is the proportion of returned results that are relevant. **Recall** is the proportion of all relevant results that were returned. These are evaluation metrics for a search experience, not fixed labels attached to a SQL Server function. `CONTAINS` often improves precision by applying stricter linguistic criteria; `FREETEXT` often improves recall by expanding the input linguistically. The actual balance depends on the language, stoplist, thesaurus, data, and query. `CONTAINSTABLE` and `FREETEXTTABLE` do not inherently increase precision or recall: they expose matching rows and a relative `RANK` for ordering. `RANK` is not a percentage, probability, or precision score.

> The formulas are the same used in Data Science: `precision = relevant results returned / all results returned`, and `recall = relevant results returned / all relevant results that exist`. The difference is the evaluation context. In classification, positive labels are usually fixed for each example and are commonly expressed as true positives (`TP`), false positives (`FP`), and false negatives (`FN`). In search, relevance is query-specific and normally requires a human-labeled or otherwise known evaluation set. `CONTAINS` and `FREETEXT` return candidates; they do not calculate or guarantee these metrics.

---

## Foundations: Linguistic Search Through an Inverted Index

A full-text index does not scan every text looking for characters like a `LIKE` query. It builds an **inverted index**: for each analyzed term, it keeps a list of documents and positions where that term occurs. That is why it is suitable for finding words, phrases, and proximity across large text collections.

Before indexing, the engine interprets text according to its language: it splits words, can relate inflected forms, and ignores common *stop words*. The query goes through similar analysis. This makes Full-Text Search richer than `LIKE`, but it is not meaning-based search: it still relies on terms and linguistic rules, not embeddings.

Use `CONTAINS` when the application controls the syntax and needs precision — a phrase, prefix, Boolean operator, or proximity. `FREETEXT` accepts a natural-language phrase and broadens matching through inflections and, when mappings are configured, the thesaurus. In Microsoft’s description, “meaning” here refers to this linguistic expansion; it is not embedding-based semantic similarity. When results must be ordered or combined with other data, `CONTAINSTABLE` and `FREETEXTTABLE` return keys and a `RANK`; that rank is FTS-specific and must not be compared directly with vector scores.

### What a Thesaurus Does

A full-text thesaurus is a language-specific XML configuration that defines synonym or replacement mappings. For example, an expansion set can treat `fast`, `quick`, and `rapid` as equivalent terms for full-text matching. `FREETEXT` uses the configured thesaurus automatically; `CONTAINS` and `CONTAINSTABLE` use it only when the query explicitly includes `FORMSOF(THESAURUS, ...)`.

The thesaurus is not an AI model and does not infer general meaning from a sentence. It applies the mappings that an administrator configured for a language. If no mapping is configured, a thesaurus search does not automatically discover synonyms.

> [!note] Important boundary
>
> Full-Text Search retrieves linguistic matches, not general semantic knowledge. “Cancel plan” might not retrieve “end subscription” when the terms are not related by language processing or a thesaurus. Use vector or hybrid search for that kind of intent.

## When to Use Full-Text Search vs. Embeddings

Use Full-Text Search when the query depends on exact or linguistic terms: product codes, order numbers, legal clauses, names, quoted phrases, prefixes, Boolean logic, proximity, inflectional forms, or synonyms configured in a thesaurus. It is also preferable when explainable term matches, language-specific ranking, and no external model/API call are priorities.

Use embeddings/vector search when the query expresses intent or meaning and the relevant text may use different words: paraphrases, natural-language questions, semantic similarity, multilingual concepts supported by the model, recommendations, or RAG retrieval. Embeddings require an embedding model, stored vectors with a fixed dimension, and query-vector generation using the same model and vector space as the indexed vectors.

Choose hybrid search when both signals matter: for example, an exact code or identifier must match while the rest of the question may be paraphrased. Run FTS and vector search independently, apply authorization and tenant filters to both, and combine the ranked candidate lists (for example, with RRF). Do not add raw FTS `RANK` directly to vector distance because they have different meanings and scales.

**Reciprocal Rank Fusion (RRF)** combines the position of a document in each result list. A common formula is `RRF(document) = Σ 1 / (k + rank)`, where `rank` is the 1-based position in an FTS or vector list and `k` is a smoothing constant, often 60. A document ranked highly by both searches receives a higher combined score; a document appearing in only one list can still be retained. RRF uses rank positions, not the raw FTS `RANK` or vector distance, so the two search systems do not need compatible score scales.

| Need | Prefer |
|---|---|
| Exact term, code, phrase, prefix, Boolean logic, or proximity | Full-Text Search |
| Meaning, paraphrase, or natural-language intent | Embeddings/vector search |
| Both exact terms and semantic intent | Hybrid search |
| No model/API or vector maintenance allowed | Full-Text Search |
| Better recall across wording variations | Embeddings, validated with real queries |

## Full-Text Catalogs and Indexes

### Creating a Full-Text Catalog

```sql
-- A full-text catalog is a logical container for full-text indexes
CREATE FULLTEXT CATALOG [ProductCatalog] AS DEFAULT;

-- Verify
SELECT * FROM sys.fulltext_catalogs;
```

### Creating a Full-Text Index

```sql
-- A full-text index requires:
-- 1. A unique, single-column, non-nullable index (usually the PK)
-- 2. A full-text catalog

-- Create full-text index on Products table
CREATE FULLTEXT INDEX ON dbo.Products (
    ProductName LANGUAGE 1033,       -- 1033 = English
    Description LANGUAGE 1033
)
KEY INDEX PK_Products
ON ProductCatalog
WITH (CHANGE_TRACKING = AUTO,        -- AUTO = SQL tracks changes to indexed data
      STOPLIST = SYSTEM);            -- Use system stop list

-- Verify
SELECT * FROM sys.fulltext_indexes;
SELECT * FROM sys.fulltext_index_columns;
```

### Change Tracking Options

| Option | Behavior |
| :--- | :--- |
| `AUTO` | `SQL Server automatically updates the FTS index when rows change` |
| `MANUAL` | Updates only when you call `ALTER FULLTEXT INDEX ... START UPDATE POPULATION` |
| `OFF` | No change tracking; population and repopulation must be started manually (`FULL` or `INCREMENTAL` when applicable) |

### Population (Building the Index)

```sql
-- Start a full population (rebuild entire index)
ALTER FULLTEXT INDEX ON dbo.Products START FULL POPULATION;

-- Start an incremental population when the table has a timestamp column
ALTER FULLTEXT INDEX ON dbo.Products START INCREMENTAL POPULATION;

-- Check population status
SELECT FULLTEXTCATALOGPROPERTY('ProductCatalog', 'PopulateStatus') AS Status;
-- 0 = Idle, 1 = Full, 3 = Throttled, 6 = Incremental population in progress

-- Check if full-text index is populated
SELECT OBJECTPROPERTYEX(OBJECT_ID('dbo.Products'), 'TableFulltextPopulateStatus');
```

> [!note] Checking population status
>
> `FULLTEXTCATALOGPROPERTY(..., 'PopulateStatus')` is retained for compatibility and is documented for removal in a future SQL Server version. For new monitoring code, prefer the table-level `OBJECTPROPERTYEX(..., 'TableFulltextPopulateStatus')` check, rather than repeatedly polling the catalog status in a tight loop.

---

## Stop Lists

Stop words (common words like "the", "and", "is") are excluded from the index:

```sql
-- Create a custom stop list
CREATE FULLTEXT STOPLIST [MyStopList] FROM SYSTEM STOPLIST;

-- Add custom stop words
ALTER FULLTEXT STOPLIST [MyStopList] ADD 'product' LANGUAGE 'English';
ALTER FULLTEXT STOPLIST [MyStopList] ADD 'item' LANGUAGE 'English';

-- Assign to an index
ALTER FULLTEXT INDEX ON dbo.Products SET STOPLIST = [MyStopList];

-- View stop words
SELECT * FROM sys.fulltext_stopwords WHERE stoplist_id =
    (SELECT stoplist_id FROM sys.fulltext_stoplists WHERE name = 'MyStopList');
```

> [!warning] Stop words can suppress expected results
>
> A stopword is removed from the full-text index and from the search condition. Many are grammatical function words that occur very frequently and usually add little discriminatory value, such as `the` (article), `and` (conjunction), and `of`/`to` (prepositions). Suppressing them usually reduces index size and noise, but it is not always correct: a product name, legal expression, title, code, or short phrase may depend on one of those words. Therefore, a query for a common word such as `the`, or a query containing a custom stopword such as `product`, may return no rows or behave differently from a `LIKE` query. The index still preserves the positional information of omitted stopwords, so they can affect phrase and `NEAR` distance calculations even though they are not searchable tokens.
>
> When troubleshooting, check both the custom stoplist (`sys.fulltext_stopwords`) and the system list (`sys.fulltext_system_stopwords`). Use `sys.dm_fts_parser` to inspect how a word, language, thesaurus, and stoplist are tokenized. The server option `transform noise words` is relevant to Boolean and proximity queries containing stopwords: with the default value `0`, SQL Server can raise a warning and return zero rows; when enabled, it transforms/removes the noise word so the query can continue, which may change the meaning of the condition. Do not enable it as a substitute for choosing the correct stoplist and query terms.

---

## CONTAINS — Precise Search Predicate

`CONTAINS` searches for rows that match specific term criteria. Returns a boolean (used in WHERE clause).

### Simple Term Search

```sql
-- Find products containing the word "wireless"
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'wireless');

-- Search across multiple columns
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS((ProductName, Description), 'bluetooth');

-- Search all full-text indexed columns
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(*, 'ergonomic');
```

### Prefix Term Search

```sql
-- Find words starting with "comput" (matches computer, computing, computational)
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, '"comput*"');

-- Multiple prefix terms
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, '"wire*" OR "blue*"');
```

### Phrase Search

```sql
-- Exact phrase match
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, '"noise cancelling"');

-- Phrase with OR
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, '"noise cancelling" OR "active noise"');
```

### Boolean Operators

```sql
-- AND: both terms must appear
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'wireless AND headphones');

-- OR: either term
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'wireless OR bluetooth');

-- AND NOT: first term but not second
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'headphones AND NOT "in-ear"');
```

### NEAR — Proximity Search

```sql
-- Generic NEAR ranks matches based on proximity; matches farther than
-- 50 logical terms receive rank 0. This custom form explicitly limits
-- the maximum distance to 5 non-search terms.
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'NEAR((wireless, headphones), 5)');
-- Up to 5 non-search terms may occur between the search terms

-- Ordered NEAR (first term must come before second)
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'NEAR((noise, cancelling), 3, TRUE)');
-- TRUE = ordered
```

### FORMSOF — Inflectional and Thesaurus Matching

```sql
-- FORMSOF INFLECTIONAL: matches inflected forms (run, runs, running, ran)
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'FORMSOF(INFLECTIONAL, "connect")');
-- Matches inflectional forms according to the language stemmer, such as
-- connect, connects, connected, and connecting; it does not mean every
-- word derived from the same spelling, such as "connection".

-- FORMSOF THESAURUS: matches synonyms from the thesaurus file
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'FORMSOF(THESAURUS, "fast")');
-- Matches configured synonyms such as fast, quick, rapid, or speedy.
-- The actual terms depend on the language-specific thesaurus XML file.
```

---

## FREETEXT — Natural Language Search

`FREETEXT` breaks the input string into words and searches for any of them and their linguistic variations. It is less precise than CONTAINS but more natural-language friendly.

```sql
-- Natural language search — finds rows about fast wireless audio
SELECT ProductId, ProductName
FROM dbo.Products
WHERE FREETEXT(Description, 'fast wireless audio headphones');

-- FREETEXT automatically:
-- 1. Removes stop words
-- 2. Finds inflectional forms according to the language stemmer
-- 3. Expands to thesaurus synonyms (if thesaurus configured)
-- 4. Uses OR logic (any of the words can match)
```

---

## CONTAINSTABLE and FREETEXTTABLE — Ranked Results

These table-valued functions return matching rows with a `RANK` score (0–1000, higher = better relative match):

### CONTAINSTABLE

```sql
-- Get products matching "wireless headphones" with rank scores
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
-- Natural language search with rankings
SELECT
    p.ProductId,
    p.ProductName,
    ftt.[RANK] AS SearchRank
FROM FREETEXTTABLE(dbo.Products, (ProductName, Description), 'comfortable wireless earbuds') AS ftt
JOIN dbo.Products p ON p.ProductId = ftt.[KEY]
WHERE ftt.[RANK] > 50  -- filter by minimum relevance
ORDER BY ftt.[RANK] DESC;
```

### Top N Results with FREETEXTTABLE

```sql
-- Get top 10 most relevant results
SELECT TOP 10
    p.ProductId,
    p.ProductName,
    ftt.[RANK]
FROM FREETEXTTABLE(dbo.Products, Description, 'wireless audio', LANGUAGE 1033, 10) AS ftt
JOIN dbo.Products p ON p.ProductId = ftt.[KEY]
ORDER BY ftt.[RANK] DESC;
-- The 5th argument (10) is top_n_by_rank and limits results inside the FTS engine
```

---

## Language Support

```sql
-- Create full-text index with multiple languages
CREATE FULLTEXT INDEX ON dbo.Products (
    Name LANGUAGE 'English',
    DescriptionDE LANGUAGE 'German',
    DescriptionFR LANGUAGE 'French'
)
KEY INDEX PK_Products ON ProductCatalog;

-- List available language IDs
SELECT lcid, name FROM sys.fulltext_languages ORDER BY name;
-- Common: 1033=English, 1031=German, 1036=French, 1041=Japanese
```

---

## Use Cases

- **Product search**: Match product names and descriptions for keyword-based search in e-commerce
- **Document library search**: Find articles containing specific terms or phrases
- **Knowledge base**: Search FAQ or support articles using natural language queries
- **FREETEXTTABLE for ranking**: Return results ordered by relevance, not just presence of keywords

---

## Common Issues & Errors

| Issue | Cause | Fix |
| :--- | :--- | :--- |
| `No full-text index` error | FTS not enabled on the table | `CREATE FULLTEXT INDEX ON dbo.Products ...` |
| Query returns no results | Stop words excluded the search term | Check if term is in stop list; query `sys.fulltext_stopwords` |
| Index not up to date | CHANGE_TRACKING = MANUAL | Switch to AUTO or manually call `START UPDATE POPULATION` |
| FORMSOF THESAURUS returns nothing | Thesaurus file not configured | Edit the thesaurus XML file for the language |
| CONTAINS syntax error | Quotes missing around phrases | Phrase searches require double quotes: `'"noise cancelling"'` |

---

## Exam Tips

> [!tip] Exam Tips
>
> - `CONTAINS` returns a boolean match — use in WHERE clause; `CONTAINSTABLE` returns ranked results — use as a table
> - `FREETEXT` is for natural language; `CONTAINS` is for precise control (prefix, proximity, boolean)
> - **Stop words** can suppress expected results — if "product" is in the stop list, searching for "product" returns nothing
> - `CHANGE_TRACKING = AUTO` keeps the FTS index current; `MANUAL` requires explicit repopulation
> - `FORMSOF(INFLECTIONAL, ...)` — great for verb forms (search "run" finds "running", "ran", "runs")
> - `RANK` from CONTAINSTABLE/FREETEXTTABLE is 0–1000 — useful for relative relevance ordering; the absolute value can change between executions

---

## Key Takeaways

- Full-text indexes require a full-text catalog and a unique key index
- `CONTAINS`/`CONTAINSTABLE` for precise term, prefix, phrase, proximity, and Boolean searches
- `FREETEXT`/`FREETEXTTABLE` for natural language searches that automatically handle variations
- Use `FREETEXTTABLE` when you need relevance-ranked results for search UIs

---

## Related Topics

- [02-Vector Search](./02-vector-search.md)
- [03-Hybrid Search & RRF](./03-hybrid-search-rrf.md)
- [03-Chunking & Generation](../09-models-embeddings/03-chunking-generation.md)

---

## Official Documentation

- [Full-Text Search (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/search/full-text-search)
- [CONTAINS (T-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/queries/contains-transact-sql)
- [FREETEXTTABLE (T-SQL)](https://learn.microsoft.com/en-us/sql/relational-databases/system-functions/freetexttable-transact-sql)

---

**[↑ Back to Section](./intelligent-search.md) | [Next →](./02-vector-search.md)**
