---
title: JSON Columns and Indexes
type: study-material
tags:
  - dp-800
  - json
  - json-columns
  - indexes
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Armazenamento e Expressões JSON](#armazenamento-de-dados-json-storing-json-data)
>   - 🔹 [Armazenamento de Dados JSON](#armazenamento-de-dados-json-storing-json-data)
>   - 🔹 [Expressões de Caminho (Strict vs Lax)](#expressoes-de-caminho-json-json-path-expressions)
> - 📍 [3. Principais Funções JSON](#principais-funcoes-json-key-json-functions)
>   - 🔹 [Leitura de JSON](#leitura-de-json)
>   - 🔹 [Construção de JSON (JSON_ARRAYAGG / JSON_OBJECTAGG)](#construcao-de-json)
>   - 🔹 [Modificação e Filtragem](#modificacao-de-json)
> - 📍 [4. Indexação & Desempenho](#indexacao-de-json-json-indexes)
>   - 🔹 [Indexação com Computed Columns](#indexacao-com-computed-columns)
>   - 🔹 [OPENJSON e Schema Binding](#openjson-e-schema-binding)
> - 📍 [5. Casos de Uso Reais & Questões](#casos-de-uso-use-cases-e-cenarios-reais-de-projeto)
>   - 🔹 [Cenário 1: Catálogo Dinâmico E-Commerce](#cenario-1-catalogo-dinamico-de-e-commerce-produtos-com-atributos-variaveis)
>   - 🔹 [Cenário 2: Log de Eventos de API](#cenario-2-processamento-e-limpeza-de-log-de-eventos-de-api-integration-logging)
>   - 🔹 [Problemas Comuns, Práticas & Questões](#problemas-comuns-e-solucoes-common-issues)
---

# JSON Columns and Indexes

## Visão Geral (Overview)

O SQL Server e o Azure SQL armazenam dados JSON nativamente como colunas `nvarchar`, mas fornecem funções JSON nativas, expressões de caminho (path expressions) e, em versões recentes, um tipo de dados `json` dedicado com suporte a JSON indexes para manipulação eficiente de dados semiestruturados.

> [!abstract]
>
> - Cobre armazenamento de JSON em colunas NVARCHAR, funções JSON, OPENJSON, FOR JSON e estratégias de indexação.
> - O JSON clássico não é um tipo físico isolado — é armazenado como NVARCHAR e sua validade é validada com `ISJSON()`.
> - Tópicos chave do exame: `JSON_VALUE` vs `JSON_QUERY` vs `OPENJSON`, comportamento dos modos de caminho lax e strict, e indexação via computed columns persistidas (persisted computed columns).

> [!tip] O que o Exame Testa
>
> - `JSON_VALUE` retorna um valor **escalar**; `JSON_QUERY` retorna um fragmento de **objeto ou array** — utilize `JSON_QUERY` quando a expressão apontar para uma estrutura complexa.
> - `OPENJSON` sem a cláusula `WITH` retorna registros em formato padrão (key, value, type); com a cláusula `WITH` retorna colunas tipadas definidas pelo usuário.
> - O modo lax (padrão): caminhos inválidos ou não encontrados retornam NULL. O modo strict: caminhos inválidos disparam erros de execução.

---

---

## Armazenamento de Dados JSON (Storing JSON Data)

```sql
-- Abordagem clássica: armazenar JSON em colunas nvarchar
CREATE TABLE dbo.Products (
    ProductId   int             NOT NULL PRIMARY KEY,
    Name        nvarchar(200)   NOT NULL,
    Attributes  nvarchar(max)   NULL, -- JSON armazenado aqui
    CONSTRAINT CK_Products_Attributes CHECK (ISJSON(Attributes) = 1) -- Valida na inserção/atualização
);

-- Abordagem moderna (SQL Server 2025+ / Azure SQL): tipo nativo json
CREATE TABLE dbo.Events (
    EventId     int     NOT NULL PRIMARY KEY,
    Payload     json    NULL
);
```

---

---

## Expressões de Caminho JSON (JSON Path Expressions)

As expressões de caminho utilizam a notação de ponto ou colchetes, tendo o caractere `$` como a raiz:

```sql
-- $.property — acessa a propriedade de um objeto
-- $[0] — acessa o primeiro elemento de um array
-- $.address.city — acesso a propriedades aninhadas
-- $.tags[0] — primeiro elemento de um array interno

DECLARE @json nvarchar(max) = N'{
    "name": "Widget",
    "price": 9.99,
    "tags": ["sale", "new"],
    "supplier": { "id": 5, "name": "Acme" }
}';

SELECT
    JSON_VALUE(@json, '$.name')               AS Name,
    JSON_VALUE(@json, '$.price')              AS Price,
    JSON_VALUE(@json, '$.tags[0]')            AS FirstTag,
    JSON_VALUE(@json, '$.supplier.name')      AS Supplier;
```

---

## Modos Strict e Lax em Caminhos JSON

As expressões de caminhos suportam duas formas de tratar propriedades ausentes ou inválidas dentro do JSON:

- **Modo lax (padrão)**: Retorna `NULL` silenciosamente em caso de erro de mapeamento ou caminho inexistente.
- **Modo strict**: Lança o erro de execução `13608` se o caminho de busca solicitado não existir fisicamente no documento.
- **Quando utilizar o strict**: Processamento de arquivos integrados (ETL) e rotinas de importação onde a ausência de propriedades representa inconsistência ou dados inválidos.

```sql
DECLARE @json NVARCHAR(MAX) = '{"name":"Alice","address":{"city":"Seattle"}}';

-- Lax (comportamento padrão): retorna NULL caso não exista
SELECT JSON_VALUE(@json, 'lax $.phone');         -- Retorna NULL, sem erros
SELECT JSON_VALUE(@json, '$.phone');              -- Retorna NULL (lax é o padrão)

-- Strict: lança um erro caso não encontre a propriedade
SELECT JSON_VALUE(@json, 'strict $.phone');      -- Lança o erro Msg 13608

-- Uso prático: validação de dados em staging
INSERT INTO Customers (Name, City)
SELECT
    JSON_VALUE(j.JsonData, 'strict $.name'),   -- falha imediatamente caso a propriedade name falte
    JSON_VALUE(j.JsonData, 'lax $.city')       -- aceita nulo se city não constar do JSON
FROM StagingJSON j
WHERE ISJSON(j.JsonData) = 1;
```

---

---

## Principais Funções JSON (Key JSON Functions)

### Leitura de JSON

```sql
-- JSON_VALUE: extrai valor escalar (retorna string)
SELECT JSON_VALUE(Attributes, '$.color') FROM dbo.Products;

-- JSON_QUERY: retorna um fragmento JSON (objeto ou array)
SELECT JSON_QUERY(Attributes, '$.dimensions') FROM dbo.Products;

-- OPENJSON sem a cláusula WITH: retorna tabela padrão de pares (key, value, type)
SELECT [key], [value], [type] FROM OPENJSON(@json);

-- OPENJSON com a cláusula WITH: converte o JSON em formato tabular com colunas tipadas
SELECT *
FROM OPENJSON(@json)
WITH (
    name    nvarchar(200)   '$.name',
    price   decimal(10,2)  '$.price',
    tags    nvarchar(max)   '$.tags' AS JSON
);
```

> [!warning] Erro Comum
> A execução de `JSON_VALUE(col, '$.product.specs')` retorna NULL quando a propriedade `specs` representa um objeto ou array — isso não gera erro, mas não retorna os dados. Utilize `JSON_QUERY(col, '$.product.specs')` para extrair fragmentos complexos.

> [!important] Ponto de Atenção: JSON_VALUE vs JSON_QUERY
>
> - **JSON_VALUE**: Extrai um valor escalar (string, número, boolean). Retorna uma string do SQL Server (`NVARCHAR`). Não pode extrair objetos ou arrays lógicos.
> - **JSON_QUERY**: Extrai um objeto ou array JSON completo como uma string JSON válida. Retorna `NULL` caso seja apontado para um valor escalar.

## OPENJSON e Schema Binding

A função `OPENJSON` acompanhada da cláusula `WITH` analisa estruturas JSON complexas convertendo-as em registros relacionais tipados. Use o modificador `AS JSON` na cláusula `WITH` para preservar arrays e objetos internos aninhados em formato bruto para processamento posterior.

```sql
DECLARE @orderJSON NVARCHAR(MAX) = '{
    "orderId": 1001,
    "customer": "Alice",
    "items": [{"sku":"A1","qty":2},{"sku":"B2","qty":1}]
}';

-- Mapear propriedades principais
SELECT * FROM OPENJSON(@orderJSON)
WITH (
    OrderId INT '$.orderId',
    Customer NVARCHAR(100) '$.customer',
    Items NVARCHAR(MAX) '$.items' AS JSON  -- AS JSON preserva o array bruto
);

-- Utilizar CROSS APPLY para varrer o array interno aninhado
SELECT h.OrderId, li.SKU, li.Qty
FROM (SELECT 1001 AS OrderId, @orderJSON AS Doc) h
CROSS APPLY OPENJSON(h.Doc, '$.items')
WITH (SKU NVARCHAR(20) '$.sku', Qty INT '$.qty') li;
```

---

### Construção de JSON

```sql
-- JSON_OBJECT: constrói um objeto JSON a partir de pares chave-valor
SELECT JSON_OBJECT('id': ProductId, 'name': Name) FROM dbo.Products;

-- JSON_ARRAY: constrói uma lista/array JSON a partir de valores informados
SELECT JSON_ARRAY(1, 'two', NULL, GETDATE());

-- JSON_ARRAYAGG: agrega valores de linhas em um array JSON (Azure SQL e SQL Server 2025 em preview)
SELECT JSON_ARRAYAGG(Name ORDER BY Name) FROM dbo.Products;

-- FOR JSON PATH: formata o resultado de uma consulta relational direto em JSON
SELECT ProductId, Name, Attributes
FROM dbo.Products
FOR JSON PATH, ROOT('products');
```

## JSON_ARRAYAGG e JSON_OBJECTAGG

Disponíveis no Azure SQL e em SQL Server 2025 (preview), estas funções agregadas constroem estruturas JSON diretamente das linhas retornadas, reduzindo a necessidade de composição manual com `FOR JSON`.

- **JSON_ARRAYAGG**: Agrega os valores de uma coluna das linhas em um array JSON unificado (semelhante ao `STRING_AGG`, mas gera JSON válido).
- **JSON_OBJECTAGG**: Converte pares de chaves e valores retornados por linhas de tabelas em um objeto JSON.
- **Caso de uso**: Construção de respostas JSON aninhadas e integradas diretamente na query T-SQL.

```sql
-- JSON_ARRAYAGG: lista de produtos agrupados por categoria
SELECT CategoryID,
       JSON_ARRAYAGG(ProductName ORDER BY ProductName) AS ProductNames
FROM Products
GROUP BY CategoryID;

-- JSON_OBJECTAGG: constrói um dicionário de atributos dinâmicos
SELECT OrderID,
       JSON_OBJECTAGG(AttributeName: AttributeValue) AS Attributes
FROM OrderAttributes
GROUP BY OrderID;

-- JSON aninhado complexo: pedidos com seus respectivos detalhes em array
SELECT o.OrderID, o.OrderDate,
       JSON_ARRAYAGG(JSON_OBJECT(
           'sku': li.SKU,
           'qty': li.Quantity,
           'price': li.UnitPrice
       )) AS LineItems
FROM Orders o
JOIN LineItems li ON o.OrderID = li.OrderID
GROUP BY o.OrderID, o.OrderDate;
```

---

### Modificação de JSON

```sql
-- JSON_MODIFY: Atualizar um valor existente
UPDATE dbo.Products
SET Attributes = JSON_MODIFY(Attributes, '$.color', 'blue')
WHERE ProductId = 1;

-- JSON_MODIFY: Adicionar uma nova propriedade
UPDATE dbo.Products
SET Attributes = JSON_MODIFY(Attributes, '$.discount', 0.15)
WHERE ProductId = 1;

-- JSON_MODIFY: Remover uma propriedade (atribuindo NULL)
UPDATE dbo.Products
SET Attributes = JSON_MODIFY(Attributes, '$.obsoleteProperty', NULL)
WHERE ProductId = 1;

-- JSON_MODIFY: Anexar um item a um array existente (usando a chave append)
UPDATE dbo.Products
SET Attributes = JSON_MODIFY(Attributes, 'append $.tags', 'clearance')
WHERE ProductId = 1;
```

### Filtragem de JSON

```sql
-- JSON_CONTAINS (SQL 2025+ / Azure SQL): valida se uma propriedade JSON contém um valor específico
SELECT * FROM dbo.Products
WHERE JSON_CONTAINS(Attributes, '"sale"', '$.tags') = 1;

-- Abordagem tradicional baseada em JSON_VALUE
SELECT * FROM dbo.Products
WHERE JSON_VALUE(Attributes, '$.color') = 'blue';
```

---

---

## Indexação de JSON (JSON Indexes)

Para realizar buscas ou ordenação eficientes em propriedades contidas dentro de colunas JSON, extraia o valor em uma computed column e crie um index comum sobre ela:

```sql
-- Criar uma computed column mapeando a propriedade JSON
ALTER TABLE dbo.Products
ADD Color AS JSON_VALUE(Attributes, '$.color');

-- Criar o index sobre a computed column
CREATE INDEX IX_Products_Color ON dbo.Products (Color);

-- A consulta a seguir utilizará o index recém-criado
SELECT * FROM dbo.Products WHERE Color = 'blue';
```

Para o tipo físico nativo `json`, o SQL Server oferece suporte direto para indexes sobre expressões de caminhos:

```sql
-- JSON index sobre tipo nativo json (SQL Server 2025 em preview)
CREATE JSON INDEX IX_Events_Payload
ON dbo.Events (Payload)
FOR ('$.userId');
```

> [!tip] Dica de Performance: Tipo de Dado Nativo JSON
>
> - A partir do SQL Server 2025 e do Azure SQL, o tipo de dado nativo `json` armazena os documentos em formato binário otimizado sob o capô.
> - Isso elimina a necessidade de fazer o parsing textual do JSON em toda query, resultando em desempenho significativamente superior em comparação com o armazenamento em `NVARCHAR(MAX)`.
>
> ---

## Indexação com Computed Columns

**O Problema:** A execução de filtros baseados diretamente na função `JSON_VALUE` em cláusulas `WHERE` obriga o otimizador a realizar table scans completos, pois não é possível indexar caminhos de textos não-relacionais diretamente.

**A Solução:** Extraia as propriedades desejadas do JSON para uma computed column e crie um index tradicional sobre ela. Para `JSON_VALUE`, a computed column pode ser não persistida quando a expressão atende aos requisitos de indexação.

```sql
-- Adiciona a coluna calculada extraída do JSON
ALTER TABLE Orders
ADD ShipCountry AS JSON_VALUE(ShippingJSON, '$.country');

-- Cria o index sobre a coluna calculada persistida
CREATE INDEX IX_Orders_ShipCountry ON Orders(ShipCountry);

-- A query abaixo utilizará o index de forma automática
SELECT OrderID, TotalAmount
FROM Orders
WHERE JSON_VALUE(ShippingJSON, '$.country') = 'US';

-- Filtered index aplicado sobre colunas esparsas
CREATE INDEX IX_Orders_UK_Country
ON Orders(ShipCountry, TotalAmount)
WHERE ShipCountry = 'UK';
```

---

---

## Casos de Uso (Use Cases) e Cenários Reais de Projeto

Abaixo estão descritos e demonstrados através de scripts SQL completos dois cenários práticos de uso do JSON em bancos de dados SQL Server/Azure SQL.

### Cenário 1: Catálogo Dinâmico de E-Commerce (Produtos com Atributos Variáveis)
**Contexto**: Um e-commerce vende diferentes tipos de produtos (eletrônicos, vestuário, livros). Cada categoria possui propriedades específicas (ex: eletrônicos têm *tamanho de tela* e *voltagem*; vestuário tem *tamanho*, *cor* e *tecido*). Criar colunas físicas para cada variação geraria uma tabela esparsa ineficiente.

**Solução**: Armazenar os atributos dinâmicos em uma coluna JSON, mas indexar os atributos mais críticos (ex: marca) para buscas de alta performance.

```sql
-- 1. Criação da Tabela com validação de formato JSON
CREATE TABLE dbo.StoreProducts (
    ProductId INT IDENTITY(1,1) PRIMARY KEY,
    Title NVARCHAR(200) NOT NULL,
    Price DECIMAL(10,2) NOT NULL,
    Category NVARCHAR(50) NOT NULL,
    AttributesJson NVARCHAR(MAX) NULL,
    
    -- Validação: Garante que apenas JSON válidos sejam inseridos
    CONSTRAINT CK_StoreProducts_AttributesJson CHECK (ISJSON(AttributesJson) = 1)
);
```

> [!note] Equivalência entre Table Scan e Clustered Index Scan
> Filtrar por `JSON_VALUE(...)` sem um índice força o SQL Server a inspecionar todas as linhas da tabela, executando a função `JSON_VALUE` para cada registro na memória.
> - **Tabela Heap (sem Chave Primária Clustered)**: O plano de execução exibe o operador **Table Scan**.
> - **Tabela com Índice Clustered (com Chave Primária)**: O plano de execução exibe o operador **Clustered Index Scan**.
> 
> Conceitualmente e em termos de desempenho (I/O e CPU), **Table Scan** e **Clustered Index Scan** são equivalentes neste contexto: ambos representam uma varredura física completa de 100% das páginas de dados da tabela. Na terminologia de mercado (DBA), o termo "Table Scan" é usado de forma genérica para se referir a qualquer leitura completa da tabela, em contraste com um **Index Seek** pontual.

```sql
-- 2. Otimização de Performance: Criar coluna calculada para busca e indexar
ALTER TABLE dbo.StoreProducts
ADD Brand AS JSON_VALUE(AttributesJson, '$.brand');

CREATE INDEX IX_StoreProducts_Brand ON dbo.StoreProducts(Brand);

-- 3. Inserção de dados diversificados
INSERT INTO dbo.StoreProducts (Title, Price, Category, AttributesJson)
VALUES 
('Smartphone X', 999.99, 'Electronics', '{"brand": "TechCorp", "screen_size": "6.1 inches", "storage": "128GB"}'),
('T-Shirt Premium', 29.90, 'Clothing', '{"brand": "StyleCo", "size": "M", "color": "Navy Blue", "material": "Cotton"}'),
('Laptop Pro 15', 1899.00, 'Electronics', '{"brand": "TechCorp", "screen_size": "15.6 inches", "ram": "16GB"}');

-- 4. Consulta Otimizada (utiliza o índice IX_StoreProducts_Brand)
SELECT Title, Price, JSON_VALUE(AttributesJson, '$.storage') AS Storage
FROM dbo.StoreProducts
WHERE Brand = 'TechCorp';
```

---

### Cenário 2: Processamento e Limpeza de Log de Eventos de API (Integration Logging)
**Contexto**: O sistema registra requisições HTTP recebidas por um Webhook. Para auditoria e relatórios, precisamos filtrar payloads específicos, limpar dados sensíveis antes de exportar, e transformar o log JSON em um formato tabular para o time de dados (BI).

**Solução**: Armazenar os logs como NVARCHAR(MAX), extrair dados dinamicamente com `OPENJSON` e tratar payloads com `JSON_MODIFY`.

```sql
-- 1. Criação da Tabela de Logs
CREATE TABLE dbo.ApiWebhookLogs (
    LogId UNIQUEIDENTIFIER DEFAULT NEWID() PRIMARY KEY,
    LoggedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
    Payload NVARCHAR(MAX) NOT NULL,
    CONSTRAINT CK_ApiWebhookLogs_Payload CHECK (ISJSON(Payload) = 1)
);

-- 2. Inserindo logs de exemplo
INSERT INTO dbo.ApiWebhookLogs (Payload)
VALUES 
('{"event": "user.signup", "user": {"id": 1023, "email": "user1@example.com"}, "metadata": {"ip": "192.168.1.1", "user_agent": "Mozilla"}}'),
('{"event": "payment.success", "user": {"id": 1023}, "metadata": {"ip": "192.168.1.1"}, "payment": {"amount": 150.00, "token": "card_9823479abcdef"}}');

-- 3. Consulta de Auditoria: desmembrar o objeto aninhado 'metadata' usando CROSS APPLY e OPENJSON
SELECT 
    l.LogId,
    l.LoggedAt,
    JSON_VALUE(l.Payload, '$.event') AS EventType,
    m.IpAddress,
    m.UserAgent
FROM dbo.ApiWebhookLogs l
CROSS APPLY OPENJSON(l.Payload, '$.metadata')
WITH (
    IpAddress NVARCHAR(50) '$.ip',
    UserAgent NVARCHAR(200) '$.user_agent'
) m;

-- 4. Mascaramento de dados sensíveis para conformidade LGPD/GDPR usando JSON_MODIFY
-- Modificamos o JSON para remover ou ofuscar dados sensíveis
SELECT 
    LogId,
    JSON_MODIFY(
        JSON_MODIFY(Payload, '$.user.email', '***@***.com'),
        '$.payment.token', 'MASKED'
    ) AS CleanedPayload
FROM dbo.ApiWebhookLogs;
```

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| `JSON_VALUE` retorna NULL | O caminho não existe ou o elemento é um objeto/array | `Utilize `JSON_QUERY` para fragmentos estruturados; valide o caminho`. |
| Lentidão em buscas JSON | Busca em formato texto bruto | Crie uma computed column equivalente à expressão da consulta e aplique index sobre ela. |
| `ISJSON` retorna 0 | JSON com má formatação no banco | Adicione a restrição CHECK no banco e valide os dados na aplicação. |
| `OPENJSON` não retorna linhas | JSON estruturalmente válido, mas caminho incorreto | Teste a validade do caminho usando `JSON_VALUE` antes. |
| Erro 13608 no banco | Caminho strict não localizado | Altere para o modo lax ou corrija o arquivo JSON de origem. |

---

## Melhores Práticas (Best Practices)

- Adicione restrições `CHECK (ISJSON(coluna) = 1)` em colunas do tipo `nvarchar` dedicadas ao armazenamento de documentos JSON para barrar dados corrompidos.
- Crie a computed column com a mesma expressão `JSON_VALUE` usada nas consultas e valide os requisitos de determinismo e precisão antes de indexá-la.
- Implemente o modo de caminho `strict` em rotinas de carga ETL para identificar falta de dados essenciais rapidamente.
- Use `JSON_ARRAYAGG` e `JSON_OBJECTAGG` nas plataformas e versões que as suportam; no SQL Server 2025, verifique o status de preview antes de adotá-las em produção.
- Caso realize consultas sobre propriedades específicas muito frequentemente, extraia as propriedades e grave-as em colunas relacionais comuns no momento de inserção (Insert) para otimizar as buscas.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - `JSON_VALUE` extrai e retorna strings/valores escalares; `JSON_QUERY` extrai blocos complexos de JSON (objetos/arrays).
> - O uso de `OPENJSON` associado à cláusula `WITH` viabiliza o mapeamento direto de tipos relacionais estruturados.
> - Para buscas eficientes em campos JSON, crie uma **computed column equivalente à expressão consultada** e um index tradicional sobre ela.
> - `JSON_ARRAYAGG`, `JSON_OBJECTAGG`, `JSON_CONTAINS` e JSON indexes dependem de plataforma e versão; confira o status de GA ou preview antes de usá-los.
> - O modo lax de caminho é o padrão adotado; strict dispara erro 13608 na ausência da chave.
> - Use a instrução `AS JSON` na cláusula `OPENJSON WITH` para impedir que arrays/objetos filhos sejam desfeitos na leitura inicial.

---

## Resumo dos Conceitos (Key Takeaways)

- Os dados JSON tradicionais residem em colunas `nvarchar` ou sob o tipo físico `json`.
- Sempre imponha integridade aos dados usando restrições `CHECK` baseadas na função `ISJSON`.
- Acelere consultas mapeando propriedades JSON importantes em computed columns persistidas associadas a indexes tradicionais.
- O modificador `FOR JSON PATH` formata as linhas relacionais em respostas estruturadas de JSON para consumo de APIs.
- O modo lax retorna NULL em caminhos inválidos; o strict lança erro 13608.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma tabela possui uma coluna JSON chamada `Metadata`. Consultas que executam filtros baseados na cláusula `JSON_VALUE(Metadata, '$.region') = 'EU'` apresentam desempenho insatisfatório devido à ocorrência sistemática de *table scans*. Qual é a MELHOR solução de engenharia para otimizar esse cenário?

A. Utilizar o modificador `FOR JSON PATH` para reestruturar os dados

B. Adicionar uma computed column sobre a instrução `JSON_VALUE(Metadata, '$.region')` e criar um index sobre ela

C. Utilizar a função `OPENJSON` para varrer os registros com melhor desempenho

D. Ativar o modo de caminho `strict` para o JSON

> [!success]- Resposta
> **B — Adicionar uma computed column sobre a instrução `JSON_VALUE(Metadata, '$.region')` e criar um index sobre ela**
>
> O otimizador de consultas pode associar uma expressão `JSON_VALUE` a uma computed column equivalente indexada, permitindo buscas eficientes. O uso de OPENJSON (C) auxilia no desmembramento de arrays, mas não atua em buscas de chaves específicas. O modo strict (D) afeta apenas o comportamento de retorno de erros.

---

## Tópicos Relacionados

- [02-JSON Functions in Advanced T-SQL](../03-advanced-tsql/02-json-functions.md) *(Inglês apenas)*
- [01-Tables & Indexes](./01-tables-indexes.md)

---

## Documentação Oficial

- [JSON Data in SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server)
- [OPENJSON (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql)
- [FOR JSON (Transact-SQL)](https://learn.microsoft.com/en-us/sql/relational-databases/json/format-query-results-as-json-with-for-json-sql-server)

---

**[← Anterior](./02-specialized-tables.md) | [↑ Voltar para a Seção](./database-objects.md) | [Próximo →](./04-constraints-sequences.md)**
