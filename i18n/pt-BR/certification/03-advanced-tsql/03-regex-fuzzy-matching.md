---
title: Regex and Fuzzy String Matching
type: study-material
tags:
  - dp-800
  - regex
  - fuzzy-matching
  - edit-distance
  - jaro-winkler
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Funções Regex (Regex Functions)](#funcoes-regex-regex-functions)
>   - 🔹 [REGEXP_LIKE & REGEXP_REPLACE](#regexp_like--validacao-de-padrao)
>   - 🔹 [REGEXP_SUBSTR, REGEXP_INSTR & REGEXP_COUNT](#regexp_substr--extracao-de-substrings)
>   - 🔹 [REGEXP_MATCHES & REGEXP_SPLIT_TO_TABLE](#regexp_matches--retornar-ocorrencias-como-tabela)
> - 📍 [3. Fuzzy String Matching & Algoritmos](#funcoes-de-busca-difusa-fuzzy-string-matching-functions)
>   - 🔹 [EDIT_DISTANCE & EDIT_DISTANCE_SIMILARITY](#edit_distance-distancia-de-levenshtein)
>   - 🔹 [JARO_WINKLER_DISTANCE](#jaro_winkler_distance)
>   - 🔹 [SOUNDEX, DIFFERENCE & TRANSLATE](#funcoes-soundex-e-difference)
> - 📍 [4. Filtros LIKE, Collation & Escolha de Função](#padroes-de-filtros-avancados-com-o-operador-like)
>   - 🔹 [Operador LIKE Avançado](#padroes-de-filtros-avancados-com-o-operador-like)
>   - 🔹 [Unicode & Collation](#unicode-e-collation-no-casamento-de-strings)
>   - 🔹 [Matriz de Escolha de Função](#escolha-da-funcao-adequada-choosing-the-right-function)
> - 📍 [5. Aplicação Prática & Síntese](#casos-de-uso-use-cases)
>   - 🔹 [Casos de Uso](#casos-de-uso-use-cases)
>   - 🔹 [Problemas Comuns, Práticas & Exam Tips](#problemas-comuns-e-solucoes-common-issues)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)

---

# Regex and Fuzzy String Matching

## Visão Geral (Overview)

O SQL Server (e em especial os bancos SQL no Microsoft Fabric) provê suporte a funções Regex para buscas estruturadas por padrões textuais e funções de Fuzzy String Matching (busca difusa) para computar scores de similaridade de textos — recursos essenciais para garantia de qualidade de dados, deduplicação e buscas textuais inteligentes em IA.

> [!abstract]
>
> - Cobre busca por padrões (`LIKE`, `PATINDEX`), busca fonética (`SOUNDEX`, `DIFFERENCE`) e busca em texto completo (*Full-Text Search* via `CONTAINS`/`FREETEXT`).
> - SQL Server 2025 introduz funções nativas de expressões regulares. Em versões anteriores ou plataformas sem esse suporte, `LIKE`, `PATINDEX` e Full-Text Search continuam sendo alternativas.
> - Tópicos chave do exame: diferenças de casos de uso de `CONTAINS` vs `FREETEXT`, requisitos de criação de indexes de texto completo (*Full-Text Indexes*) e o retorno da função `PATINDEX`.

> [!tip] O que o Exame Testa
>
> - **CONTAINS** = busca de **precisão** — termos exatos, termos com prefixo (ex: `"word*"`), buscas de proximidade (`NEAR`) e termos ponderados.
> - **FREETEXT** = busca de **recuperação (recall)** — interpreta linguagem natural procurando sinônimos, plurais e flexões gramaticais sem exigir sintaxe exata.
> - Tanto `CONTAINS` como `FREETEXT` exigem a criação prévia de um **Full-Text Index** na coluna em questão — não funcionam sobre indexes não-clustered comuns.

---

## Funções Regex (Regex Functions)

As funções de Regex do Microsoft Fabric SQL adotam o padrão de expressões regulares de estilo POSIX.

> [!important] Suporte a Regex
>
> - As funções Regex aplicam-se ao SQL Server 2025 (17.x), Azure SQL Database, Azure SQL Managed Instance e SQL database do Microsoft Fabric. No Managed Instance, exigem a política SQL Server 2025 ou Always-up-to-date.
> - `REGEXP_LIKE` requer nível de compatibilidade 170; outras funções escalares Regex estão disponíveis em todos os níveis de compatibilidade suportados.

### REGEXP_LIKE — Validação de Padrão

```sql
-- Retorna 1 se o texto for compatível com o padrão de e-mail, 0 caso contrário
SELECT REGEXP_LIKE('user@example.com', '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') AS IsValidEmail;
-- Retorno: 1

-- Filtrar linhas de clientes com telefones válidos
SELECT * FROM dbo.Customers
WHERE REGEXP_LIKE(Phone, '^\+?[0-9\s\-()]{10,}$') = 1;
```

### REGEXP_REPLACE — Substituição por Padrão

```sql
-- Substituir caracteres não-alfanuméricos por strings vazias (limpeza)
SELECT REGEXP_REPLACE('(123) 456-7890', '[^0-9]', '') AS DigitsOnly;
-- Retorno: '1234567890'

-- Normalizar espaços repetidos em espaços únicos
SELECT REGEXP_REPLACE('  muitos   espaços   aqui  ', '\s+', ' ') AS Normalized;
-- Retorno: ' muitos espaços aqui '
```

### REGEXP_SUBSTR — Extração de Substrings

```sql
-- Extrair a primeira ocorrência compatível
SELECT REGEXP_SUBSTR('Pedido #12345 do cliente', '[0-9]+') AS OrderNumber;
-- Retorno: '12345'

-- Extrair ocorrência específica especificando a posição inicial de busca
SELECT REGEXP_SUBSTR('aa-bb-cc', '[a-z]+', 1, 2) AS SecondMatch;
-- Retorno: 'bb'
```

### REGEXP_INSTR — Localizar Posição

```sql
-- Retorna a posição inicial (base 1) da ocorrência compatível
SELECT REGEXP_INSTR('Hello World 123', '[0-9]+') AS NumberPosition;
-- Retorno: 13
```

### REGEXP_COUNT — Contar Ocorrências

```sql
-- Contar quantas datas no padrão AAAA-MM-DD aparecem no texto
SELECT REGEXP_COUNT('2025-01-15 e 2025-02-20', '[0-9]{4}-[0-9]{2}-[0-9]{2}') AS DateCount;
-- Retorno: 2
```

### REGEXP_MATCHES — Retornar Ocorrências como Tabela

```sql
-- Retorna uma tabela listando todas as ocorrências localizadas
SELECT match_value
FROM REGEXP_MATCHES('one two three', '[a-z]+');
-- Retorno (linhas): 'one', 'two', 'three'
```

### REGEXP_SPLIT_TO_TABLE — Dividir Texto por Padrão

```sql
-- Dividir a string gerando linhas com base no padrão delimitador
SELECT value
FROM REGEXP_SPLIT_TO_TABLE('a,b,,c', ',+');
-- Retorno (linhas): 'a', 'b', 'c'
```

---

## Funções de Busca Difusa (Fuzzy String Matching Functions)

As buscas difusas (fuzzy matching) quantificam numericamente o grau de similaridade entre duas strings — muito úteis em processos de deduplicação, data quality e resolução de identidades de entidades.

> [!tip] Jaro-Winkler vs Edit Distance
>
> - **EDIT_DISTANCE**: Retorna a contagem inteira e absoluta de modificações (inserções, remoções, trocas) para igualar as strings.
> - **JARO_WINKLER_DISTANCE**: Retorna uma distância `float`; valores menores indicam maior similaridade. Dá preferência a correspondências no início da palavra.

### EDIT_DISTANCE (Distância de Levenshtein)

A **Edit Distance** computa o menor número de edições de caracteres individuais (como inserções, exclusões e substituições) necessário para transformar uma string em outra.

```sql
SELECT EDIT_DISTANCE('kitten', 'sitting');  -- Retorno: 3
SELECT EDIT_DISTANCE('Microsoft', 'Microsift');  -- Retorno: 1

-- Mapear produtos com nomes muito parecidos (até 2 edições de distância)
SELECT a.ProductId, a.Name, b.ProductId AS DupId, b.Name AS DupName,
       EDIT_DISTANCE(a.Name, b.Name) AS Distance
FROM dbo.Products a
JOIN dbo.Products b ON a.ProductId < b.ProductId
WHERE EDIT_DISTANCE(a.Name, b.Name) <= 2;
```

### EDIT_DISTANCE_SIMILARITY

Retorna um score de similaridade padronizado em escala de 0 (strings totalmente diferentes) a 100 (strings idênticas) — representa a versão normalizada de porcentagem da Edit Distance.

```sql
SELECT EDIT_DISTANCE_SIMILARITY('Microsoft', 'Microsift'); -- Retorno: ~89 (percentual)

-- Encontrar nomes de clientes com mais de 80% de similaridade
SELECT a.CustomerId, a.Name, b.CustomerId AS MatchId, b.Name AS MatchName,
       EDIT_DISTANCE_SIMILARITY(a.Name, b.Name) AS Similarity
FROM dbo.Customers a
JOIN dbo.Customers b ON a.CustomerId < b.CustomerId
WHERE EDIT_DISTANCE_SIMILARITY(a.Name, b.Name) > 80;
```

### JARO_WINKLER_DISTANCE

O algoritmo Jaro-Winkler confere pesos maiores para correspondências localizadas no início das strings comparadas — ideal para cruzamento de nomes próprios de pessoas ou identificadores de strings curtas.

```sql
SELECT JARO_WINKLER_DISTANCE('MARTHA', 'MARHTA');   -- Retorno: ~0.9611
SELECT JARO_WINKLER_DISTANCE('DWAYNE', 'DUANE');    -- Retorno: ~0.8400
SELECT JARO_WINKLER_DISTANCE('John Smith', 'Jon Smith'); -- Retorno: ~0.9878

-- Localizar possíveis cadastros de contatos duplicados
SELECT a.ContactId, a.FullName,
       b.ContactId AS MatchId, b.FullName AS MatchName,
       JARO_WINKLER_DISTANCE(a.FullName, b.FullName) AS Similarity
FROM dbo.Contacts a
JOIN dbo.Contacts b ON a.ContactId < b.ContactId
WHERE JARO_WINKLER_DISTANCE(a.FullName, b.FullName) < 0.08;
```

---

## Funções SOUNDEX e DIFFERENCE

As funções `SOUNDEX` e `DIFFERENCE` são recursos clássicos built-in do T-SQL presentes em todas as edições do SQL Server e Azure SQL Database (não exclusivas do Fabric), facilitando buscas com base na fonética das palavras.

- **SOUNDEX(texto)**: avalia como a palavra soa em inglês e retorna uma chave de 4 caracteres (uma letra seguida de três números).
- **DIFFERENCE(texto1, texto2)**: realiza o cruzamento das duas chaves SOUNDEX de entrada e retorna um score na escala de 0 a 4 — onde o score 4 representa similaridade fonética máxima, e 0 representa nenhuma similaridade.
- **Limitações**: o algoritmo adota regras fonéticas da língua inglesa — podendo falhar ou trazer distorções em palavras de outros idiomas, acentuações ou caracteres especiais não latinos.

```sql
-- SOUNDEX: chaves idênticas para pronúncias equivalentes
SELECT SOUNDEX('Smith'), -- S530
       SOUNDEX('Smyth'), -- S530
       SOUNDEX('Schmidt'); -- S253

-- DIFFERENCE: escala de similaridade fonética (4 = máximo, 0 = mínimo)
SELECT DIFFERENCE('Smith', 'Smyth'),    -- 4
       DIFFERENCE('Smith', 'Brown'),    -- 1
       DIFFERENCE('Robert', 'Rupert');  -- 3

-- Buscar clientes cujos nomes soem foneticamente como 'Johnson'
SELECT CustomerID, Name
FROM Customers
WHERE DIFFERENCE(Name, 'Johnson') >= 3;
```

---

## Função TRANSLATE

A função `TRANSLATE(string, caracteres_origem, caracteres_destino)` substitui individualmente cada caractere do conjunto de origem pelo correspondente na mesma posição do conjunto de destino — uma substituição direta de 1 para 1 em massa em chamada única.

**Diferença comparada a REPLACE**: a função `REPLACE` trabalha localizando e substituindo uma substring completa de cada vez, exigindo o encadeamento de vários comandos aninhados caso você precise limpar múltiplos caracteres diferentes. O `TRANSLATE` realiza múltiplas trocas de caracteres simultaneamente, mantendo a escrita muito limpa.

```sql
-- Substituição simultânea de caracteres de telefone
SELECT TRANSLATE('(555) 123-4567', '()-', '   '); -- Retorno: '555  123 4567'

-- Normalizar caracteres limpando formatação
SELECT TRANSLATE(TRIM(Phone), '()- .', '     ')
FROM Customers;

-- Comparação estrutural: TRANSLATE contra vários REPLACEs aninhados
SELECT REPLACE(REPLACE(REPLACE('(555)-123', '(', ''), ')', ''), '-', '');
-- Com TRANSLATE fica elegante: TRANSLATE('(555)-123', '()-', '   ')
```

---

## Padrões de Filtros Avançados com o Operador LIKE

O operador `LIKE` suporta o uso de classes de caracteres em T-SQL, viabilizando validações ricas diretamente no banco sem dependências externas.

| Padrão de Busca | Significado | Exemplo de Uso |
| :--- | :--- | :--- |
| `%` | Qualquer cadeia de texto (0 ou mais caracteres). | `'S%'` localiza Smith, SQL, Silva |
| `_` | Exatamente um único caractere arbitrário. | `'S_ith'` localiza Smith, Smyth |
| `[abc]` | Qualquer único caractere contido no conjunto. | `'[SB]mith'` localiza Smith, Bmith |
| `[a-z]` | Qualquer único caractere dentro da faixa. | ``'[A-Z]%'` localiza textos iniciados por maiúscula` |
| `[^abc]` | Qualquer caractere que NÃO pertença ao conjunto. | `'[^0-9]%'` impede início com dígitos |

Use a instrução `ESCAPE` para buscar caracteres especiais como literais (ex: buscar `%` ou `_` no texto). A cláusula `COLLATE` permite forçar sensibilidade de caixa (case sensitivity) na comparação.

```sql
-- Validar códigos no formato exato de 3 letras maiúsculas + 4 números
SELECT ProductCode FROM Products
WHERE ProductCode LIKE '[A-Z][A-Z][A-Z][0-9][0-9][0-9][0-9]';

-- Buscar o caractere % como literal na query
SELECT Name FROM Products
WHERE Name LIKE '%50\%%' ESCAPE '\'; -- localiza '50% off sale'

-- Forçar busca com diferenciação de maiúsculas/minúsculas (Case-Sensitive)
SELECT Name FROM Customers
WHERE Name LIKE 'a%' COLLATE Latin1_General_CS_AS;
```

---

## Unicode e Collation no Casamento de Strings

As regras de Collation definem como o SQL Server avalia igualdades, ordena caracteres e utiliza indexes estruturais nas queries.

- **NVARCHAR vs VARCHAR**: utilize sistematicamente o prefixo `N` nas strings literais ao realizar buscas em colunas do tipo NVARCHAR (`N'Smith'`). A omissão força a conversão implícita dos dados, invalidando o uso de seeks em indexes (forçando index scans).
- **Sufixos de Sensibilidade do Collation**:
  - `CI` = Case Insensitive (ignora maiúsculas/minúsculas); `CS` = Case Sensitive (diferencia).
  - `AI` = Accent Insensitive (ignora acentuações); `AS` = Accent Sensitive (diferencia).
- **Collation de Indexes**: se a collation informada na query divergir da collation configurada na coluna da tabela, o otimizador não conseguirá realizar o Seek no index de forma eficiente.

> [!important] O Perigo das Conversões Implícitas (NVARCHAR vs VARCHAR)
>
> - Se você possuir uma coluna `NVARCHAR` indexada e rodar uma comparação contra uma string literal sem o prefixo `N` (ex: `WHERE Col = 'Smith'`), o SQL Server executará uma **conversão implícita** do valor da coluna para comparar.
> - Isso inviabiliza completamente o Seek do index (Index Seek), forçando um Scan completo na tabela. Sempre declare strings literais como Unicode (`N'Smith'`) se a coluna destino for `NVARCHAR`.

```sql
-- Mesmo texto, comportamentos de collation distintos
SELECT Name FROM Customers WHERE Name = N'José' COLLATE Latin1_General_CI_AI; -- localiza Jose, José
SELECT Name FROM Customers WHERE Name = N'José' COLLATE Latin1_General_CS_AS; -- localiza apenas José
```

---

## Escolha da Função Adequada (Choosing the Right Function)

| Cenário de Negócio | Função Recomendada |
| :--- | :--- |
| Validar padrão de formatos complexos (e-mails/CPFs/telefones) | `REGEXP_LIKE` |
| Extrair subconjunto de números ou caracteres de textos sujos | `REGEXP_SUBSTR` |
| Limpeza/substituição de padrões lógicos textuais | `REGEXP_REPLACE` |
| Identificar pequenos erros de digitação (contagem física) | `EDIT_DISTANCE` |
| Mapear similaridades com score percentual (%) independente de tamanho | ``EDIT_DISTANCE_SIMILARITY`` |
| Cruzamento de nomes próprios de pessoas ou identificadores curtos | `JARO_WINKLER_DISTANCE` |
| Busca fonética aproximada de nomes | `SOUNDEX` / `DIFFERENCE` |
| Substituição de múltiplos delimitadores de string de 1 para 1 | `TRANSLATE` |
| Validações estruturadas simples de strings | `LIKE` com classes de caracteres |

---

## Casos de Uso (Use Cases)

- **Qualidade de Dados (Data Quality)**: Limpeza estrutural de strings de telefones e identificação de erros de digitação em campos.
- **Processos de Deduplicação**: Mapeamento de possíveis contas de clientes em duplicidade com nomes aproximados antes de rodar processos de merge.
- **Preparação de payloads de IA**: Remoção de caracteres espúrios e normalização de strings antes da geração de vetores de embeddings para modelos LLMs.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| Funções regex retornam erro de "objeto não localizado" | As funções de Regex são nativas do Fabric SQL / Azure SQL, mas ausentes no SQL Server clássico | Valide a plataforma do banco antes de empregar; adote o operador `LIKE` ou `PATINDEX` no SQL Server. |
| Lentidão severa em joins com buscas difusas (fuzzy joins) | Cruzamento cartesiano (Cross Join) comparando todas as linhas de tabelas grandes | Pré-filtre os dados aplicando filtros lógicos baratos antes (ex: mesma letra inicial, mesma faixa de tamanho de texto). |
| SOUNDEX retorna palavras semanticamente diferentes | SOUNDEX atua exclusivamente baseado na fonética da pronúncia do inglês | Adote as funções `EDIT_DISTANCE` ou `JARO_WINKLER_DISTANCE`. |
| Varredura completa da tabela (Scan) em vez de Seek com o operador LIKE | Busca iniciada com caractere curinga (ex: `'%texto%'`) | `Substitua a busca por Full-Text Search com a cláusula `CONTAINS` em tabelas com grande volumetria de dados`. |

---

## Melhores Práticas (Best Practices)

- Prefira a função `EDIT_DISTANCE_SIMILARITY` em relação ao uso da `EDIT_DISTANCE` absoluta em validações de thresholds de similaridade — o retorno em escala normalized (0-100) independe do tamanho das palavras.
- Adote `TRANSLATE` em substituição a múltiplos comandos `REPLACE` encadeados para normalizações de múltiplos caracteres separadores em passo único.
- Evite buscas usando curingas no início do termo (ex: `LIKE '%termo%'`) em tabelas gigantescas; crie e adote o Full-Text Search (`CONTAINS`).
- Garanta a igualdade de Collation das strings literais informadas frente à configuração das colunas do banco para certificar-se de que buscas em indexes usarão Seeks eficientes.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - As funções de regex e de similaridade textual são recursos recentes do T-SQL, disponíveis conforme a plataforma e a versão: SQL Server 2025 (17.x), Azure SQL Database, Azure SQL Managed Instance e serviços SQL do Microsoft Fabric. No Managed Instance, confira a política de atualização; as funções de similaridade permanecem em *preview*. Verifique sempre a matriz **Aplica-se a** da função antes de adotá-la.
> - A função `EDIT_DISTANCE` computa e retorna um número inteiro absoluto de edições; a `EDIT_DISTANCE_SIMILARITY` retorna um percentual na escala de 0 a 100.
> - `JARO_WINKLER_DISTANCE` retorna uma distância `float`: menor valor significa maior similaridade.
> - As funções `SOUNDEX`/`DIFFERENCE` são padrões clássicos do T-SQL (presentes em todas as edições do SQL Server); um score de `DIFFERENCE` igual a 4 denota similaridade fonética máxima.
> - A função `TRANSLATE` exige conjuntos de caracteres de origem e destino com tamanhos de caracteres idênticos — divergências geram erro na execução da query.
> - Buscas iniciadas por curingas no operador `LIKE` forçam scans; o exame cobra que o candidato saiba sugerir o **Full-Text Search** (`CONTAINS`) como substituto performante.

---

## Resumo dos Conceitos (Key Takeaways)

- As funções Regex fornecem pesquisas no padrão POSIX muito superiores às limitações clássicas do operador `LIKE`.
- As funções difusas medem a proximidade léxica das palavras, viabilizando processos de de-duplicação de dados.
- O `TRANSLATE` atua como um canivete suíço para limpeza de formatações de múltiplos caracteres em uma única chamada.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma query realiza buscas textuais na tabela `Customers` (com mais de 1 milhão de linhas) filtrando pelo nome de contato com a cláusula `WHERE Name LIKE '%Smith%'`. A execução apresenta gargalo severo de tempo de resposta. Qual alternativa oferece os mesmos resultados de busca de forma otimizada para o uso de indexes?

A. Alterar o filtro para `SOUNDEX(Name) = SOUNDEX('Smith')`.

B. Modificar a busca para a instrução `CHARINDEX('Smith', Name) > 0`.

C. Gerar um Full-Text Index na coluna correspondente e consultar usando `CONTAINS(Name, '"Smith*"')`.

D. Executar o filtro usando `TRANSLATE(Name, 'Smith', '     ') IS NULL`.

> [!success]- Resposta
> **C — Gerar um Full-Text Index na coluna correspondente e consultar usando CONTAINS(Name, '"Smith*"')**
>
> O uso de curingas no início da expressão de filtro (`LIKE '%Smith%'`) impede o otimizador de realizar seeks lógicos em indexes comuns B-Tree, forçando scans completos em todas as páginas de dados da tabela. A criação de um Full-Text Index e consulta com `CONTAINS` permite ao SQL Server consultar um index invertido de palavras de forma instantânea. O uso de `SOUNDEX` (A) e `CHARINDEX` (B) continuam gerando scans de tabela. O `TRANSLATE` (D) não realiza buscas aproximadas de substrings.

---

## Tópicos Relacionados

- [02-JSON Functions](./02-json-functions.md)
- [04-Graph Queries](./04-graph-queries.md) *(Inglês apenas)*
- [03-Chunking & Generation](../09-models-embeddings/03-chunking-generation.md) *(Inglês apenas)*

---

## Documentação Oficial

- [REGEXP_LIKE (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/regexp-like-transact-sql)
- [EDIT_DISTANCE (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/edit-distance-transact-sql)
- [JARO_WINKLER_DISTANCE (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/jaro-winkler-distance-transact-sql)
- [SOUNDEX (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/soundex-transact-sql)
- [TRANSLATE (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/translate-transact-sql)

---

**[← Anterior](./02-json-functions.md) | [↑ Voltar para a Seção](./advanced-tsql.md) | [Próximo →](./04-graph-queries.md)**
