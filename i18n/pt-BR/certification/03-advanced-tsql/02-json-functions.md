---
title: JSON Functions
type: study-material
tags:
  - dp-800
  - json
  - json-functions
  - openjson
  - for-json
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Lendo & Transformando JSON](#lendo-dados-json-reading-json)
>   - 🔹 [JSON_VALUE (Escalares)](#json_value--extracao-de-valores-escalares)
>   - 🔹 [JSON_QUERY (Objetos & Arrays)](#json_query--extracao-de-objetos-e-arrays)
>   - 🔹 [OPENJSON (Transformar em Linhas)](#openjson--transformar-json-em-linhas-rows)
> - 📍 [3. Construindo & Modificando JSON](#construindo-dados-json-building-json)
>   - 🔹 [JSON_OBJECT & JSON_ARRAY](#json_object)
>   - 🔹 [JSON_ARRAYAGG & JSON_OBJECTAGG](#json_arrayagg)
>   - 🔹 [FOR JSON (PATH & AUTO)](#for-json-path)
>   - 🔹 [JSON_MODIFY & Filtragem (ISJSON, JSON_CONTAINS)](#modificando-dados-json-modifying-json)
> - 📍 [4. Validação, Schemas & CROSS APPLY](#referencia-de-expressoes-de-caminho-json-json-path-expressions)
>   - 🔹 [JSON Path Expressions & Strict/Lax](#referencia-de-expressoes-de-caminho-json-json-path-expressions)
>   - 🔹 [JSON Aninhado com CROSS APPLY](#json-aninhado-com-cross-apply-nested-json)
>   - 🔹 [Validação de Schemas com CHECK Constraints](#padroes-de-validacao-de-schemas-json)
> - 📍 [5. Aplicação Prática & Síntese](#casos-de-uso-use-cases)
>   - 🔹 [Casos de Uso](#casos-de-uso-use-cases)
>   - 🔹 [Problemas Comuns, Práticas & Exam Tips](#problemas-comuns-e-solucoes-common-issues)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)

---

# JSON Functions

## Visão Geral (Overview)

O SQL Server disponibiliza um conjunto rico de funções JSON nativas para leitura, construção, modificação e filtragem de dados no formato JSON. Devido ao foco do exame DP-800 em dados semiestruturados, integrações de APIs e payloads de Inteligência Artificial, este assunto é fortemente cobrado.

> [!abstract]
>
> - Estudo aprofundado de todas as funções JSON do T-SQL: extração, modificação, análise (parsing) e serialização.
> - O JSON pode ser armazenado em `NVARCHAR` e, nas plataformas que o suportam, no tipo de dados `json`; a disponibilidade dos recursos mais recentes varia por produto e versão.
> - Tópicos chave do exame: diferenças de `JSON_VALUE` vs `JSON_QUERY`, a cláusula `WITH` da função `OPENJSON`, comportamento de `FOR JSON PATH` vs `FOR JSON AUTO`, e os modos de caminhos `lax` vs `strict`.

> [!tip] O que o Exame Testa
>
> - `JSON_VALUE` = extrai apenas valores escalares (strings, números, booleanos); `JSON_QUERY` = extrai fragmentos de objetos ou arrays JSON. Se o caminho apontar para um objeto ou array e você usar `JSON_VALUE`, o retorno padrão será NULL.
> - A função `OPENJSON` sem a cláusula `WITH` retorna uma estrutura padrão chave/valor/tipo (key, value, type); quando acompanhada da cláusula `WITH`, retorna colunas tipadas e mapeadas correspondendo à estrutura do documento.
> - A cláusula `FOR JSON PATH` combinada com aliases de colunas usando notação de ponto (`coluna AS 'objeto.propriedade'`) gera JSON aninhado customizado; `FOR JSON AUTO` gera o aninhamento baseando-se na estrutura e aliases das tabelas na consulta.

---

## Lendo dados JSON (Reading JSON)

### JSON_VALUE — Extração de Valores Escalares

```sql
DECLARE @json nvarchar(max) = N'{
    "customer": {
        "id": 42,
        "name": "Alice",
        "tier": "gold"
    },
    "tags": ["vip", "loyal"],
    "score": 9.5
}';

SELECT
    JSON_VALUE(@json, '$.customer.id')     AS CustomerId,   -- '42' (scalar como string)
    JSON_VALUE(@json, '$.customer.name')   AS Name,         -- 'Alice'
    JSON_VALUE(@json, '$.tags[0]')         AS FirstTag,     -- 'vip'
    JSON_VALUE(@json, '$.score')           AS Score;        -- '9.5'
-- Retorna NULL caso o caminho não seja localizado (comportamento padrão: modo lax)
-- Retorna um erro explícito se declarado em modo strict: JSON_VALUE(@json, 'strict $.missing')
```

### JSON_QUERY — Extração de Objetos e Arrays

```sql
SELECT
    JSON_QUERY(@json, '$.customer')    AS CustomerObject,  -- retorna o objeto JSON completo
    JSON_QUERY(@json, '$.tags')        AS TagsArray;       -- retorna o array JSON completo
-- Retorna NULL se apontado para um valor escalar (utilize JSON_VALUE para escalares)
```

> [!warning] Erro Comum
> Executar `JSON_VALUE(coluna, '$.produto.detalhes')` retornará silenciosamente NULL caso `detalhes` represente um objeto ou array — este é o comportamento padrão do modo `lax`. Se configurado em modo `strict`, a instrução geraria um erro. O exame costuma testar estes dois comportamentos nas alternativas: saiba que o padrão implícito é lax (retorna NULL, não erro).

> [!important] Códigos de Tipo de Dados (Type Values) no OPENJSON
>
> - Ao consultar o OPENJSON sem cláusula `WITH`, a coluna `type` retorna um número inteiro de 0 a 5.
> - **Dica de Memorização**:
>   - `0` = null, `1` = string, `2` = number, `3` = boolean, `4` = array, `5` = object.

### OPENJSON — Transformar JSON em Linhas (Rows)

```sql
-- Padrão sem cláusula WITH: retorna chave-valor-tipo
SELECT [key], [value], [type]
FROM OPENJSON(@json, '$.customer');
-- Retorno: id/42/2, name/Alice/1, tier/gold/1

-- Saída estruturada e tipada usando a cláusula WITH
SELECT id, name, tier
FROM OPENJSON(@json, '$.customer')
WITH (
    id      int             '$.id',
    name    nvarchar(100)   '$.name',
    tier    nvarchar(20)    '$.tier'
);

-- Analisar um array simples
SELECT value AS Tag
FROM OPENJSON(@json, '$.tags');
```

**Mapeamento de tipos retornados pelo OPENJSON:**

| Valor do Campo `type` | Tipo JSON Correspondente |
| :--- | :--- |
| 0 | null |
| 1 | string |
| 2 | `number` |
| 3 | true/false |
| 4 | array |
| 5 | object |

---

## Construindo dados JSON (Building JSON)

### JSON_OBJECT

```sql
-- Criar um objeto JSON dinamicamente
SELECT JSON_OBJECT(
    'id'   : CustomerId,
    'name' : Name,
    'email': Email
) AS CustomerJson
FROM dbo.Customers;
```

### JSON_ARRAY

```sql
-- Criar um array JSON dinamicamente
SELECT JSON_ARRAY(1, 'two', NULL, GETDATE());
-- Retorno: [1,"two",null,"2025-06-15T10:00:00"]
```

### JSON_ARRAYAGG

> [!important] Disponibilidade
>
> `JSON_ARRAYAGG` e `JSON_OBJECTAGG` estão em GA no Azure SQL Database, no Azure SQL Managed Instance com política SQL Server 2025 ou Always-up-to-date, no SQL database do Microsoft Fabric e no Fabric Data Warehouse. No SQL Server 2025 (17.x), permanecem em preview.

```sql
-- Agregar valores de linhas em um único array JSON agrupando por categoria
SELECT
    CategoryId,
    JSON_ARRAYAGG(Name ORDER BY Name) AS ProductNames
FROM dbo.Products
GROUP BY CategoryId;

-- Agregar múltiplos objetos JSON de linhas distintas em um único array
SELECT
    OrderId,
    JSON_ARRAYAGG(
        JSON_OBJECT('sku': Sku, 'qty': Quantity, 'price': UnitPrice)
        ORDER BY LineNumber
    ) AS LineItemsJson
FROM dbo.OrderLines
GROUP BY OrderId;
```

### JSON_OBJECTAGG

```sql
-- Agregar pares de chave-valor de múltiplas linhas em um único objeto JSON
-- Ideal para pivotar tabelas de atributos dinâmicos (EAV) para documentos JSON
SELECT
    ProductId,
    JSON_OBJECTAGG(AttributeName: AttributeValue) AS Attributes
FROM dbo.ProductAttributes
GROUP BY ProductId;
-- Retorno do campo Attributes: {"color":"red","size":"L","weight":"1.2kg"}

-- Combinar com tabelas de parametrização do sistema
SELECT JSON_OBJECTAGG(ConfigKey: ConfigValue) AS AppConfig
FROM dbo.AppSettings
WHERE IsActive = 1;
-- Retorno: {"MaxRetries":"3","Timeout":"30","Environment":"prod"}
```

### FOR JSON PATH

```sql
-- Converter registros de uma consulta SQL diretamente para formato JSON
SELECT
    c.CustomerId,
    c.Name,
    o.OrderId,
    o.TotalAmount
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerId = c.CustomerId
FOR JSON PATH, ROOT('customers');

-- Retorno estruturado:
-- {"customers":[{"CustomerId":1,"Name":"Alice","OrderId":101,"TotalAmount":99.99},...]}
```

> [!tip] Dica para a Prova: FOR JSON PATH vs AUTO
>
> - **FOR JSON PATH**: Permite controle total do formato final do JSON. Usando aliases com pontos (ex: `SELECT Name AS 'customer.name'`), você define os níveis e nomes de aninhamento.
> - **FOR JSON AUTO**: Cria o aninhamento baseado exclusivamente nas tabelas da cláusula `FROM` e nos joins executados. É menos flexível para modelar o schema final.

### FOR JSON AUTO

```sql
-- Aninhamento automático de objetos JSON com base nos aliases das tabelas
SELECT c.Name, o.OrderId
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerId = c.CustomerId
FOR JSON AUTO;
-- Aninha os pedidos (Orders) dentro do nó de cada cliente (Customers) automaticamente
```

---

## Modificando dados JSON (Modifying JSON)

### JSON_MODIFY

```sql
DECLARE @json nvarchar(max) = N'{"name":"Alice","score":7}';

-- Atualizar o valor de uma propriedade existente
SET @json = JSON_MODIFY(@json, '$.score', 9.5);

-- Inserir uma nova propriedade
SET @json = JSON_MODIFY(@json, '$.tier', 'gold');

-- Remover uma propriedade (atribuir NULL com cast explícito de tipo)
SET @json = JSON_MODIFY(@json, '$.tier', NULL);

-- Adicionar um novo valor ao final de um array (append)
SET @json = JSON_MODIFY(@json, 'append $.tags', 'vip');
```

---

## Filtrando com JSON (Filtering with JSON)

### JSON_CONTAINS (preview no SQL Server 2025)

> [!warning] Disponibilidade
>
> `JSON_CONTAINS` está em preview e, atualmente, disponível apenas no SQL Server 2025 (17.x).

```sql
-- Verificar se um array JSON contém um valor específico
SELECT * FROM dbo.Products
WHERE JSON_CONTAINS(Tags, '"sale"') = 1;

-- Verificar a presença de objeto em caminhos aninhados
SELECT * FROM dbo.Events
WHERE JSON_CONTAINS(Payload, '{"status":"active"}', '$.user') = 1;
```

### ISJSON — Validação Estrutural

```sql
SELECT * FROM dbo.Products
WHERE ISJSON(Attributes) = 1; -- 1 = JSON válido, 0 = inválido

-- Validação de tipo estrutural específico com ISJSON (SQL Server 2022+)
WHERE ISJSON(Attributes, OBJECT) = 1  -- deve ser obrigatoriamente um objeto JSON {}
WHERE ISJSON(Tags, ARRAY) = 1         -- deve ser obrigatoriamente um array JSON []
```

---

## Referência de Expressões de Caminho JSON (JSON Path Expressions)

| Expressão | Retorno Esperado |
| :--- | :--- |
| `$.propriedade` | Propriedade no nó raiz principal. |
| `$.a.b` | Propriedade aninhada dentro de outra. |
| `$.array[0]` | Primeiro item dentro do array JSON. |
| `$.array[*]` | Sintaxe de curinga de caminho SQL/JSON para recursos que a suportam; para transformar um array em linhas, use `OPENJSON(@json, '$.array')`. |
| `lax $.missing` | `Retorna NULL caso a chave não exista (padrão)`. |
| `strict $.missing` | Retorna um erro de exceção caso a chave não exista. |

O modo padrão de caminhos adotado por todas as funções JSON no SQL Server é o modo `lax`. Use o prefixo `strict` quando precisar que chaves ausentes disparem erros, o que é útil em fluxos de validação de carga de dados.

---

## JSON Aninhado com CROSS APPLY (Nested JSON)

Utilize a combinação de `CROSS APPLY OPENJSON` para expandir arrays aninhados de documentos JSON complexos em linhas relacionais planas estruturadas.

```sql
-- Payload contendo dados de pedidos com itens aninhados em array
DECLARE @orders NVARCHAR(MAX) = '[
    {"id": 1, "customer": "Alice", "items": [{"sku":"A1","qty":2},{"sku":"B2","qty":1}]},
    {"id": 2, "customer": "Bob",   "items": [{"sku":"C3","qty":5}]}
]';

-- Abrir o primeiro nível (pedidos) e cruzar com o segundo nível (itens)
SELECT o.id, o.customer, li.sku, li.qty
FROM OPENJSON(@orders)
WITH (
    id       INT             '$.id',
    customer NVARCHAR(100)   '$.customer',
    items    NVARCHAR(MAX)   '$.items' AS JSON -- AS JSON mantém o fragmento íntegro para o passo seguinte
) o
CROSS APPLY OPENJSON(o.items)
WITH (sku NVARCHAR(20) '$.sku', qty INT '$.qty') li;
```

A flag **`AS JSON`** na definição da cláusula `WITH` faz `OPENJSON` retornar o objeto ou array como fragmento JSON. Sem ela, quando o caminho aponta para um objeto ou array, a coluna tipada retorna `NULL` em modo `lax`.

> [!important] Importância da Flag "AS JSON"
>
> - Ao usar `OPENJSON` com a cláusula `WITH` para extrair dados aninhados, se uma coluna representar um objeto ou array JSON que você pretende extrair ou tratar em queries filhas (ex: usando `CROSS APPLY`), você **deve adicionar a palavra-chave `AS JSON`** no tipo.
> - Se você esquecer `AS JSON`, o SQL Server tentará converter o conteúdo em texto plano e a execução subsequente de funções JSON sobre ele retornará `NULL` ou falhará.

---

## Padrões de Validação de Schemas JSON

### Validação com ISJSON em Constraints do tipo CHECK

```sql
-- Garantir a validação estrutural do JSON no momento da gravação
ALTER TABLE Products
ADD CONSTRAINT CK_ValidJSON CHECK (ISJSON(Attributes) = 1);
```

### Validação em Processos de ETL — Detectar Linhas Inválidas

```sql
-- Identificar registros corrompidos ou incompletos na carga de staging
SELECT src.RowID, src.JsonData
FROM StagingTable src
WHERE ISJSON(src.JsonData) = 0                               -- JSON inválido/malformado
   OR JSON_VALUE(src.JsonData, 'strict $.id')   IS NULL      -- ausência de campo obrigatório (id)
   OR JSON_VALUE(src.JsonData, 'strict $.name') IS NULL;

-- Contagem de linhas saudáveis vs inválidas
SELECT
    SUM(CASE WHEN ISJSON(JsonData) = 1 THEN 1 ELSE 0 END) AS ValidCount,
    SUM(CASE WHEN ISJSON(JsonData) = 0 THEN 1 ELSE 0 END) AS InvalidCount
FROM StagingTable;
```

### Validação por Tipo Estrutural (SQL Server 2022+)

```sql
-- Rejeitar registros que não representem um objeto JSON puro (bloqueia arrays ou escalares soltos)
ALTER TABLE Events
ADD CONSTRAINT CK_PayloadIsObject CHECK (ISJSON(Payload, OBJECT) = 1);
```

---

## Casos de Uso (Use Cases)

- **Armazenamento de Atributos Flexíveis**: Metadados de produtos, configurações de aplicações e payloads de telemetria ou eventos.
- **Cache de APIs**: Salvar respostas brutas de chamadas a serviços externos em formato NVARCHAR(MAX) estruturado para consultas posteriores.
- **Pipelines de IA e RAG**: Consolidar múltiplos registros relacionais para formatos JSON aceitos em requisições HTTP para Large Language Models (LLMs) usando `FOR JSON`.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| `JSON_VALUE` retorna NULL inesperado | O caminho não foi localizado no documento (lax mode) | `Valide o caminho declarado; mude para o modo `strict` para gerar um erro de depuração`. |
| `JSON_QUERY` retorna NULL ao consultar string/número | Escalares não são aceitos pela função `JSON_QUERY` | Utilize `JSON_VALUE` para extrair escalares (strings/números) e `JSON_QUERY` para fragmentos (objetos/arrays). |
| O resultado de `FOR JSON` gera aninhamento confuso | Falta de aliases de colunas usando notação de ponto | Declare aliases explícitos no formato `'nome.propriedade'` ao usar `FOR JSON PATH`. |
| `CROSS APPLY OPENJSON` não retorna dados secundários | O campo aninhado não foi configurado com a flag `AS JSON` | Insira a instrução `AS JSON` na coluna do array secundário dentro da cláusula `WITH`. |
| Funções `JSON_OBJECTAGG`/`JSON_ARRAYAGG` não são reconhecidas | Plataforma ou política de atualização sem suporte | Verifique a disponibilidade do produto; use `FOR JSON` como alternativa quando as agregações JSON não estiverem disponíveis. |

---

## Melhores Práticas (Best Practices)

- Defina colunas JSON como `NVARCHAR(MAX)` associadas a uma CHECK constraint com a função `ISJSON` para impedir a gravação de strings inválidas.
- Prefira invocar `OPENJSON` com a cláusula estruturada `WITH` em vez de encadear múltiplos comandos isolados `JSON_VALUE` — a abertura do documento em passo único economiza CPU e tempo de parsing.
- Adote o modo de caminho `strict` em processos de carga de dados e ETL para forçar erros visíveis caso propriedades críticas obrigatórias estejam ausentes.
- Gere indexes sobre computed columns com base em campos JSON acessados com frequência em buscas e joins (ex: `INDEX IX ON Tabela (ComputedCol) WHERE ComputedCol IS NOT NULL`).

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - `JSON_VALUE` = extrai valores escalares e os retorna como string; `JSON_QUERY` = extrai e retorna fragmentos válidos de JSON (arrays ou objetos).
> - A cláusula `WITH` na função `OPENJSON` converte estruturas JSON diretamente para colunas relacionais tipadas em consultas.
> - O controle de formatação no retorno é feito por `FOR JSON PATH` (notação por ponto nos aliases) ou `FOR JSON AUTO` (estrutura automática com base nos joins).
> - `JSON_ARRAYAGG` e `JSON_OBJECTAGG` têm disponibilidade distinta por plataforma: GA no Azure SQL Database, no Azure SQL Managed Instance com política compatível e no Fabric; preview no SQL Server 2025.
> - O modo de caminhos padrão do SQL Server é `lax` (retorna NULL na ausência de chaves); use o prefixo `strict` para disparar erros explícitos.

---

## Resumo dos Conceitos (Key Takeaways)

- A extração é dividida entre `JSON_VALUE` (para valores simples) e `JSON_QUERY` (para estruturas aninhadas).
- `OPENJSON` é o motor mais eficiente para converter documentos de texto semiestruturados em tabelas relacionais normais.
- A cláusula `FOR JSON` converte tabelas relacionais do banco em formato JSON para transmissões e integrações de rede.
- A combinação de `CROSS APPLY OPENJSON` com a instrução `AS JSON` resolve lógicas de arrays JSON com múltiplos níveis de aninhamento.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma query de consulta faz uso da função `JSON_VALUE(coluna, '$.address.city')`, contudo diversas linhas na tabela não possuem a propriedade `address` configurada em seu JSON. O que será retornado para estas linhas específicas por padrão?

A. Uma string vazia `''`.

B. Valor do tipo `NULL` do SQL.

C. Um erro de exceção de execução será disparado pelo banco de dados.

D. A string contendo o texto `'null'`.

> [!success]- Resposta
> **B — Valor do tipo NULL do SQL**
>
> As funções JSON no SQL Server adotam implicitamente o modo de caminho `lax` por padrão. No modo `lax`, caso a chave informada no caminho não seja localizada no documento, a função intercepta a ausência de dados e retorna o valor `NULL` ordinário do SQL Server, sem gerar falhas na execução da query. Se o requisito exigisse o disparo de um erro, o caminho deveria ser prefixado explicitamente como `'strict $.address.city'` (Opção C).

---

## Tópicos Relacionados

- [03-JSON Columns](../01-database-objects/03-json-columns.md)
- [02-RAG Prompts and Responses](../11-rag/02-prompts-and-responses.md) *(Inglês apenas)*

---

## Documentação Oficial

- [JSON Functions (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/json-functions-transact-sql)
- [OPENJSON (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql)
- [FOR JSON (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/json/format-query-results-as-json-with-for-json-sql-server)

---

**[← Anterior](./01-ctes-window-functions.md) | [↑ Voltar para a Seção](./advanced-tsql.md) | [Próximo →](./03-regex-fuzzy-matching.md)**
