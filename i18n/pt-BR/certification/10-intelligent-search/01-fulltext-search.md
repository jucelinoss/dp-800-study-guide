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
> - 📍 [Quando Usar Full-Text Search ou Embeddings](#quando-usar-full-text-search-ou-embeddings)
> - 📍 [2. Catálogos e Índices Full-Text](#catálogos-e-índices-full-text)
>   - 🔹 [Criando um Full-Text Catalog](#criando-um-full-text-catalog)
>   - 🔹 [Criando um Full-Text Index](#criando-um-full-text-index)
>   - 🔹 [Opções de Change Tracking](#opções-de-change-tracking)
>   - 🔹 [Population (Construindo o Índice)](#population-construindo-o-índice)
> - 📍 [3. Stop Lists](#stop-lists)
> - 📍 [4. CONTAINS — Predicado de Busca Precisa](#contains--predicado-de-busca-precisa)
>   - 🔹 [Busca de Termo Simples](#busca-de-termo-simples)
>   - 🔹 [Busca por Prefixo](#busca-por-prefixo)
>   - 🔹 [Busca por Frase](#busca-por-frase)
>   - 🔹 [Operadores Booleanos](#operadores-booleanos)
>   - 🔹 [NEAR — Busca por Proximidade](#near--busca-por-proximidade)
>   - 🔹 [FORMSOF — Correspondência Inflexional e de Thesaurus](#formsof--correspondência-inflexional-e-de-thesaurus)
> - 📍 [5. FREETEXT — Busca em Linguagem Natural](#freetext--busca-em-linguagem-natural)
> - 📍 [6. CONTAINSTABLE e FREETEXTTABLE — Resultados Ranqueados](#containstable-e-freetexttable--resultados-ranqueados)
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

A Full-Text Search (FTS) habilita a busca linguística de dados baseados em caracteres — correspondendo palavras, frases, proximidade e formas flexionadas. Diferente de queries `LIKE` (que fazem correspondência de padrões de caracteres), a FTS usa um **índice invertido**, separação de palavras, radicalização e stop words por idioma. Sinônimos do thesaurus só participam quando seus mapeamentos são configurados. Os predicados principais são `CONTAINS` (correspondência precisa de termos) e `FREETEXT` (correspondência em linguagem natural).

> [!abstract]
>
> - Aborda Full-Text Search no Azure SQL: CONTAINS, FREETEXT, CONTAINSTABLE, FREETEXTTABLE e índices full-text
> - A Full-Text Search habilita buscas linguísticas e de proximidade além do padrão LIKE
> - Tópicos-chave para o exame: casos de uso de CONTAINS vs FREETEXT, requisito de índice full-text, resultados ranqueados com variantes TABLE

> [!tip] O Que o Exame Testa
>
> - `CONTAINS` tende a produzir **maior precisão**: termos exatos, prefixos (`"data*"`), proximidade (`NEAR`), condições booleanas e termos ponderados (`ISABOUT`) permitem restringir o que conta como correspondência
> - `FREETEXT` tende a produzir **maior recall**: entrada em linguagem natural, formas flexionadas e mapeamentos configurados do thesaurus ampliam os candidatos, o que também pode incluir resultados menos relevantes
> - `CONTAINSTABLE` / `FREETEXTTABLE` retornam uma tabela com coluna `RANK` (0–1000) — use quando precisar de resultados ranqueados ou quiser fazer join com outras tabelas

> [!note] Precisão, recall e `RANK`
>
> **Precisão** é a proporção dos resultados retornados que é relevante. **Recall** é a proporção de todos os resultados relevantes que foi retornada. Essas são métricas de avaliação da experiência de busca, não rótulos fixos das funções do SQL Server. `CONTAINS` frequentemente melhora a precisão ao aplicar critérios linguísticos mais restritos; `FREETEXT` frequentemente melhora o recall ao expandir linguisticamente a entrada. O equilíbrio real depende do idioma, da stoplist, do thesaurus, dos dados e da consulta. `CONTAINSTABLE` e `FREETEXTTABLE` não aumentam, por si só, a precisão ou o recall: elas expõem as linhas correspondentes e um `RANK` relativo para ordenação. `RANK` não é porcentagem, probabilidade nem pontuação de precisão.

> As fórmulas são as mesmas usadas em Data Science: `precisão = resultados relevantes retornados / todos os resultados retornados`, e `recall = resultados relevantes retornados / todos os resultados relevantes existentes`. A diferença está no contexto de avaliação. Em classificação, os rótulos positivos normalmente são fixos para cada exemplo e costumam ser expressos como verdadeiros positivos (`TP`), falsos positivos (`FP`) e falsos negativos (`FN`). Em busca, a relevância depende da consulta e normalmente exige um conjunto de avaliação rotulado por pessoas ou conhecido por outra forma. `CONTAINS` e `FREETEXT` retornam candidatos; não calculam nem garantem essas métricas.

---

## Fundamentos: busca linguística por índice invertido

Um índice full-text não percorre cada texto procurando caracteres como uma consulta `LIKE`. Ele cria um **índice invertido**: para cada termo analisado, mantém a lista de documentos e posições em que o termo ocorre. Por isso ele é apropriado para procurar palavras, frases e proximidade em grandes volumes de texto.

Antes de indexar, o mecanismo interpreta o texto conforme o idioma: separa palavras, pode reduzir flexões a formas relacionadas e ignora *stop words* frequentes. A consulta passa pelo mesmo tipo de análise. Isso explica por que Full-Text Search é mais rica que `LIKE`, mas não é busca por significado: ela ainda depende de termos e regras linguísticas, não de embeddings.

`CONTAINS` é indicado quando a aplicação controla a sintaxe e quer precisão — uma frase, prefixo, operador booleano ou proximidade. `FREETEXT` recebe uma frase em linguagem natural e amplia a correspondência por formas flexionadas e, quando houver mapeamentos configurados, pelo thesaurus. Na descrição da Microsoft, “significado” aqui se refere a essa expansão linguística; não é similaridade semântica baseada em embeddings. Quando o resultado precisa ser ordenado ou combinado com outros dados, `CONTAINSTABLE` e `FREETEXTTABLE` devolvem chaves e um `RANK`; esse rank é específico da FTS e não deve ser comparado diretamente com scores vetoriais.

### O que um Thesaurus Faz

Um thesaurus de Full-Text Search é uma configuração XML específica de um idioma que define mapeamentos de sinônimos ou substituições. Por exemplo, um conjunto de expansão pode tratar `rápido`, `veloz` e `ágil` como termos equivalentes na correspondência Full-Text. `FREETEXT` usa o thesaurus configurado automaticamente; `CONTAINS` e `CONTAINSTABLE` só o usam quando a consulta inclui explicitamente `FORMSOF(THESAURUS, ...)`.

O thesaurus não é um modelo de IA e não infere o significado geral de uma frase. Ele aplica os mapeamentos configurados pelo administrador para um idioma. Se nenhum mapeamento estiver configurado, a busca com thesaurus não descobrirá sinônimos automaticamente.

> [!note] Limite importante
>
> Full-Text Search recupera correspondência linguística, não conhecimento semântico geral. “Cancelar plano” pode não recuperar “encerrar assinatura” se os termos não forem relacionados pelo idioma/thesaurus. Para esse tipo de intenção, considere busca vetorial ou híbrida.

## Quando Usar Full-Text Search ou Embeddings

Use Full-Text Search quando a consulta depender de termos exatos ou regras linguísticas: códigos de produto, números de pedido, cláusulas legais, nomes, frases entre aspas, prefixos, operadores booleanos, proximidade, formas flexionadas ou sinônimos configurados no thesaurus. Também é preferível quando a explicabilidade das correspondências, o ranking linguístico e a ausência de chamada a modelo/API externa forem prioridades.

Use embeddings/busca vetorial quando a consulta expressar intenção ou significado e o texto relevante puder usar palavras diferentes: paráfrases, perguntas em linguagem natural, similaridade semântica, conceitos multilíngues suportados pelo modelo, recomendações ou recuperação para RAG. Embeddings exigem um modelo, vetores armazenados com dimensão fixa e a geração do vetor da consulta usando o mesmo modelo e espaço vetorial dos vetores indexados.

Escolha busca híbrida quando os dois sinais forem importantes: por exemplo, um código ou identificador deve coincidir exatamente, mas o restante da pergunta pode ser uma paráfrase. Execute FTS e busca vetorial separadamente, aplique filtros de autorização e tenant às duas buscas e combine as listas de candidatos ranqueadas (por exemplo, com RRF). Não some diretamente o `RANK` da FTS à distância vetorial, pois eles têm significados e escalas diferentes.

**Reciprocal Rank Fusion (RRF)** combina a posição de um documento em cada lista de resultados. Uma fórmula comum é `RRF(documento) = Σ 1 / (k + posição)`, em que `posição` é o lugar começando em 1 na lista de FTS ou vetorial e `k` é uma constante de suavização, frequentemente 60. Um documento bem posicionado nas duas buscas recebe um score combinado maior; um documento que aparece em apenas uma lista ainda pode ser mantido. O RRF usa posições, não o `RANK` bruto da FTS nem a distância vetorial, portanto os dois sistemas não precisam ter escalas de score compatíveis.

| Necessidade | Prefira |
|---|---|
| Termo exato, código, frase, prefixo, lógica booleana ou proximidade | Full-Text Search |
| Significado, paráfrase ou intenção em linguagem natural | Embeddings/busca vetorial |
| Termos exatos e intenção semântica | Busca híbrida |
| Sem modelo/API ou manutenção de vetores | Full-Text Search |
| Maior recall diante de variações de redação | Embeddings, validados com consultas reais |

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
| `OFF` | Sem rastreamento de mudanças; a população e a repopulação devem ser iniciadas manualmente (`FULL` ou `INCREMENTAL` quando aplicável) |

### Population (Construindo o Índice)

```sql
-- Iniciar uma população completa (reconstruir o índice inteiro)
ALTER FULLTEXT INDEX ON dbo.Products START FULL POPULATION;

-- Iniciar uma população incremental quando a tabela tiver uma coluna timestamp
ALTER FULLTEXT INDEX ON dbo.Products START INCREMENTAL POPULATION;

-- Verificar o status da population
SELECT FULLTEXTCATALOGPROPERTY('ProductCatalog', 'PopulateStatus') AS Status;
-- 0 = Idle, 1 = Full, 3 = Throttled, 6 = população incremental em progresso

-- Verificar se o índice full-text está populado
SELECT OBJECTPROPERTYEX(OBJECT_ID('dbo.Products'), 'TableFulltextPopulateStatus');
```

> [!note] Verificando o status da população
>
> `FULLTEXTCATALOGPROPERTY(..., 'PopulateStatus')` é mantida por compatibilidade e está documentada para remoção em uma versão futura do SQL Server. Para código novo de monitoramento, prefira a verificação no nível da tabela com `OBJECTPROPERTYEX(..., 'TableFulltextPopulateStatus')`, em vez de consultar repetidamente o status do catálogo em um loop apertado.

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
> Uma stopword é removida do índice full-text e do critério de busca. Muitas são palavras funcionais que aparecem com muita frequência e geralmente acrescentam pouca capacidade de distinguir documentos, como `the` (artigo), `and` (conjunção) e `of`/`to` (preposições). Suprimi-las normalmente reduz o tamanho do índice e o ruído, mas isso nem sempre é correto: um nome de produto, expressão jurídica, título, código ou frase curta pode depender de uma dessas palavras. Por isso, uma consulta por uma palavra comum como `the`, ou por uma stopword customizada como `product`, pode não retornar linhas ou pode se comportar de forma diferente de uma consulta `LIKE`. O índice ainda preserva a informação de posição das stopwords omitidas; assim, elas podem afetar o cálculo de frases e da distância do `NEAR`, mesmo não sendo tokens pesquisáveis.
>
> Ao depurar, verifique tanto a lista customizada (`sys.fulltext_stopwords`) quanto a lista do sistema (`sys.fulltext_system_stopwords`). Use `sys.dm_fts_parser` para inspecionar como uma palavra, o idioma, o thesaurus e a stoplist são tokenizados. A opção de servidor `transform noise words` é relevante para consultas booleanas e de proximidade que contêm stopwords: com o valor padrão `0`, o SQL Server pode emitir um aviso e retornar zero linhas; quando habilitada, ela transforma/remove a noise word para permitir a continuidade da consulta, o que pode alterar o significado da condição. Não a habilite como substituta da escolha correta da stoplist e dos termos da consulta.

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
-- O NEAR genérico ranqueia as correspondências pela proximidade; correspondências
-- a mais de 50 termos lógicos recebem rank 0. Esta forma customizada limita
-- explicitamente a distância máxima a 5 termos não pesquisados.
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'NEAR((wireless, headphones), 5)');
-- Até 5 termos não pesquisados podem ocorrer entre os termos pesquisados

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
-- Corresponde a formas flexionais de acordo com o stemmer do idioma, como
-- connect, connects, connected e connecting; não significa toda palavra
-- derivada da mesma grafia, como "connection".

-- FORMSOF THESAURUS: correspondências de sinônimos do arquivo de thesaurus
SELECT ProductId, ProductName
FROM dbo.Products
WHERE CONTAINS(Description, 'FORMSOF(THESAURUS, "fast")');
-- Corresponde a sinônimos configurados, como fast, quick, rapid ou speedy.
-- Os termos reais dependem do arquivo XML de thesaurus do idioma.
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
-- 2. Encontra formas flexionadas de acordo com o stemmer do idioma
-- 3. Expande para sinônimos do thesaurus (se configurado)
-- 4. Usa lógica OR (qualquer uma das palavras pode corresponder)
```

> [!note] CONTAINS vs FREETEXT — Quando Usar Cada Um
>
> | | CONTAINS | FREETEXT |
> |---|---|---|
> | **Quando usar** | Controle preciso: prefixos, frases exatas, proximidade, booleanos | Entrada em linguagem natural e correspondência linguística mais ampla |
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
-- O 5º argumento (10) é top_n_by_rank e limita resultados dentro do engine FTS
```

> [!tip] Use as Variantes TABLE para Busca Ranqueada
>
> `CONTAINS` e `FREETEXT` são predicados — retornam apenas SIM/NÃO. Para ordenar resultados por relevância (como uma UI de busca), use `CONTAINSTABLE` ou `FREETEXTTABLE` — eles expõem a coluna `RANK` (0–1000) que você pode usar em `ORDER BY`.

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

**[↑ Voltar à Seção](./intelligent-search.md) | [Lab: Full-Text Search](../../practice/labs/10-intelligent-search/01-fulltext-search-lab.sql) | [Próximo →](./02-vector-search.md)**
