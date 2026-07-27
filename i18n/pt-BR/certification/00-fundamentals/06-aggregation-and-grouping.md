---
title: "Agregação e Agrupamento"
type: topic
tags: [sql-server, group-by, aggregate, fundamentals]
---

# Agregação e Agrupamento

## Visão Geral

Funções agregadas resumem múltiplas linhas em um único valor. `GROUP BY` define a granularidade do agrupamento — o nível no qual cada sumário é calculado — enquanto `HAVING` filtra grupos após a agregação.

> [!abstract]
>
> - `COUNT`, `SUM`, `AVG`, `MIN` e `MAX` cada um lida com valores `NULL` de forma diferente.
> - Toda coluna no `SELECT` que não é um agregado deve aparecer no `GROUP BY`.
> - `WHERE` filtra linhas antes do agrupamento; `HAVING` filtra grupos após o agrupamento.
> - Agregação condicional com `CASE` evita múltiplas passagens sobre os mesmos dados.

> [!tip] O que o Exame Testa
> Agregação é a base para funções janela, consultas analíticas e padrões de relatório testados em todo o exame DP-800. Entenda granularidade, comportamento `NULL` e a distinção `WHERE`/`HAVING` antes de passar para tópicos avançados.

---

## As funções agregadas

O SQL Server fornece cinco funções agregadas básicas. Todas ignoram valores `NULL` exceto `COUNT(*)`, que conta linhas independentemente do conteúdo `NULL`.

| Função | Exemplo de sintaxe | O que retorna | Comportamento NULL |
| :--- | :--- | :--- | :--- |
| `COUNT(*)` | `COUNT(*)` | Número de linhas de entrada | Conta todas as linhas |
| `COUNT(coluna)` | `COUNT(ShipDate)` | Número de valores não nulos na coluna | Ignora `NULL` |
| `COUNT(DISTINCT coluna)` | `COUNT(DISTINCT CustomerID)` | Número de valores distintos não nulos | Ignora `NULL` |
| `SUM` | `SUM(TotalDue)` | Soma de valores não nulos | Ignora `NULL`; conjunto vazio retorna `NULL` |
| `AVG` | `AVG(TotalDue)` | Média de valores não nulos | Ignora `NULL`; conjunto vazio retorna `NULL` |
| `MIN` | `MIN(OrderDate)` | Menor (mais antigo / menor) valor | Ignora `NULL` |
| `MAX` | `MAX(OrderDate)` | Maior (mais recente / maior) valor | Ignora `NULL` |

```sql
-- Agregados básicos sobre SalesOrderHeader (~31k linhas)
SELECT COUNT(*)              AS AllRows,
       COUNT(ShipDate)       AS ShippedRows,
       COUNT(DISTINCT CustomerID) AS UniqueCustomers,
       MIN(TotalDue)         AS SmallestOrder,
       MAX(TotalDue)         AS LargestOrder,
       AVG(TotalDue)         AS AvgOrderValue,
       SUM(TotalDue)         AS GrandTotal
FROM Sales.SalesOrderHeader;
```

> [!note] `COUNT_BIG`
> O SQL Server também oferece `COUNT_BIG`, que retorna `bigint` em vez de `int`. Use-o quando as contagens de linhas podem exceder 2,1 bilhões. A sintaxe e o comportamento `NULL` são idênticos ao `COUNT`.

## GROUP BY e granularidade do resultado

### Uma linha por quê?

Antes de escrever um `GROUP BY`, complete a frase: **"Preciso de uma linha por \_\_\_\_."** A resposta define o conjunto de agrupamento.

| Pergunta | Granularidade | GROUP BY |
| :--- | :--- | :--- |
| "Total de vendas por cliente" | Uma linha por cliente | `GROUP BY CustomerID` |
| "Preço médio por categoria de produto" | Uma linha por categoria | `GROUP BY Category` |
| "Contagem de pedidos por ano" | Uma linha por ano | `GROUP BY YEAR(OrderDate)` |

### GROUP BY composto

Quando você agrupa por mais de uma expressão, a granularidade se torna **uma linha por combinação única** dessas expressões.

```sql
-- Uma linha por combinação ano + território
SELECT YEAR(soh.OrderDate)          AS OrderYear,
       st.Name                      AS Territory,
       COUNT(soh.SalesOrderID)      AS OrderCount,
       SUM(soh.TotalDue)            AS TotalSales
FROM Sales.SalesOrderHeader AS soh
INNER JOIN Sales.Customer AS c         ON c.CustomerID = soh.CustomerID
INNER JOIN Sales.SalesTerritory AS st  ON st.TerritoryID = c.TerritoryID
GROUP BY YEAR(soh.OrderDate), st.Name
ORDER BY OrderYear, TotalSales DESC;
```

> [!warning] Erro Comum
> Adicionar uma coluna não agregada à lista `SELECT` sem incluí-la no `GROUP BY` gera um erro. Exemplo: adicionar `OrderDate` a uma consulta de nível de cliente falha porque um cliente pode ter muitas datas diferentes. Ou mude a granularidade ou use `MIN(OrderDate)` / `MAX(OrderDate)`.

### GROUP BY com expressões

O SQL Server permite agrupar por expressões como `YEAR(OrderDate)` ou `LEFT(ProductNumber, 2)`, não apenas nomes de colunas simples. A mesma expressão deve aparecer no `SELECT` para legibilidade.

```sql
-- Agrupar por uma expressão calculada
SELECT LEFT(ProductNumber, 2) AS ProductSeries,
       COUNT(*)               AS ProductCount,
       AVG(ListPrice)         AS AvgPrice
FROM Production.Product
GROUP BY LEFT(ProductNumber, 2)
ORDER BY ProductSeries;
```

## DISTINCT vs GROUP BY

Tanto `DISTINCT` quanto `GROUP BY` podem eliminar linhas duplicadas, mas servem a propósitos diferentes.

| Propósito | Use |
| :--- | :--- |
| Remover duplicatas sem agregação | `SELECT DISTINCT` |
| Resumir grupos com agregados | `GROUP BY` |
| Listar combinações únicas | `SELECT DISTINCT` ou `GROUP BY` (preferência de estilo) |

```sql
-- DISTINCT: lista apenas combinações únicas
SELECT DISTINCT CustomerID, TerritoryID
FROM Sales.Customer;

-- GROUP BY: mesmas combinações únicas, mas permite agregados
SELECT CustomerID, TerritoryID, COUNT(*) AS RowCount
FROM Sales.Customer
GROUP BY CustomerID, TerritoryID;
```

`DISTINCT` não agrega. Se você precisa de `SUM`, `AVG` ou `COUNT` por grupo, você deve usar `GROUP BY`.

## WHERE vs HAVING

A ordem de processamento lógico da consulta é:

1. `FROM` / `JOIN`
2. `WHERE`
3. `GROUP BY`
4. `HAVING`
5. `SELECT`
6. `ORDER BY`

`WHERE` filtra linhas individuais **antes** do agrupamento. `HAVING` filtra grupos **após** a agregação. Filtrar cedo com `WHERE` é mais claro e geralmente reduz o trabalho.

```sql
-- WHERE filtra linhas, HAVING filtra grupos
SELECT CustomerID,
       COUNT(*) AS OrderCount,
       SUM(TotalDue) AS TotalSpend
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-01-01'          -- descarta linhas antigas antes de agrupar
  AND OrderDate < '2014-01-01'
GROUP BY CustomerID
HAVING SUM(TotalDue) >= 1000;           -- mantém apenas clientes de alto gasto
```

> [!note] Modelo mental — granularidade
> Pense na granularidade como a resposta a: "O que uma linha no meu resultado representa?" Antes de escrever `GROUP BY`, diga em voz alta: "Uma linha por \_\_\_\_." Esse hábito previne muitos erros de agregação.

## Agregação condicional

Agregação condicional usa expressões `CASE` dentro de funções agregadas para contar ou somar linhas que satisfazem uma condição — tudo em uma única passagem sobre os dados.

```sql
-- Agregação condicional: compare métodos
SELECT CustomerID,
       COUNT(*)                                            AS AllOrders,
       SUM(CASE WHEN TotalDue > 1000 THEN 1 ELSE 0 END)   AS LargeOrders,
       SUM(CASE WHEN TotalDue > 1000 THEN TotalDue ELSE 0 END) AS LargeOrdersTotal,
       AVG(CASE WHEN TotalDue > 1000 THEN TotalDue END)   AS LargeOrdersAvg
FROM Sales.SalesOrderHeader
GROUP BY CustomerID;
```

Compare isso com a alternativa: uma cláusula `WHERE` mais uma consulta separada para cada condição. Agregação condicional é mais eficiente porque examina os dados uma vez.

> [!tip]
> `CASE` é uma expressão, não uma instrução de controle de fluxo. Dentro de um agregado, `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` atua como um contador condicional.

## Armadilhas comuns de agregação

### 1. NULL em SUM/AVG

`SUM` e `AVG` ignoram valores `NULL`, mas não os tratam como zero. Se todas as linhas em um grupo têm `NULL`, o resultado é `NULL`, não zero.

```sql
SELECT CustomerID,
       SUM(TotalDue) AS TotalSpend,          -- NULL se não houver linhas
       COALESCE(SUM(TotalDue), 0.00) AS TotalSpendSafe
FROM Sales.SalesOrderHeader
GROUP BY CustomerID;
```

### 2. COUNT(*) vs COUNT(coluna)

`COUNT(*)` conta linhas. `COUNT(coluna)` conta valores não nulos. Eles retornam números diferentes quando a coluna é anulável.

```sql
SELECT COUNT(*)       AS AllRows,         -- 31465
       COUNT(ShipDate) AS WithShipDate,    -- menos, porque ShipDate pode ser NULL
       COUNT(CustomerID) AS WithCustomerID -- igual a COUNT(*) pois CustomerID é NOT NULL
FROM Sales.SalesOrderHeader;
```

### 3. Coluna não agregada sem GROUP BY

Uma lista `SELECT` com agregados e colunas simples sem `GROUP BY` é permitida apenas quando todas as colunas simples são funcionalmente dependentes do agrupamento — mas o SQL Server geralmente não detecta dependência funcional. Adicione toda coluna não agregada ao `GROUP BY`.

```sql
-- ERRADO: OrderDate não está em GROUP BY e não é agregado
-- SELECT CustomerID, OrderDate, SUM(TotalDue)
-- FROM Sales.SalesOrderHeader
-- GROUP BY CustomerID;

-- CORRETO: ou agregue a data ou inclua-a no GROUP BY
SELECT CustomerID,
       MAX(OrderDate) AS LastOrderDate,
       SUM(TotalDue) AS TotalSpend
FROM Sales.SalesOrderHeader
GROUP BY CustomerID;
```

### 4. LEFT JOIN + agregação

Ao agregar após um `LEFT JOIN`, lembre-se de que o lado não preservado produz linhas estendidas com `NULL` para pais não correspondidos. `COUNT(ChildID)` retorna corretamente zero; `COUNT(*)` conta a linha estendida com nulo como um.

```sql
-- Correto: conte pedidos por cliente (incluindo zero)
SELECT c.CustomerID,
       COUNT(soh.SalesOrderID) AS OrderCount,
       COALESCE(SUM(soh.TotalDue), 0.00) AS TotalSpend
FROM Sales.Customer AS c
LEFT JOIN Sales.SalesOrderHeader AS soh ON soh.CustomerID = c.CustomerID
GROUP BY c.CustomerID;
```

## Verifique-se

### 1. NULL e COUNT

Qual é a diferença entre `COUNT(*)` e `COUNT(ShipDate)` quando `ShipDate` é anulável?

> [!success]- Resposta
> `COUNT(*)` retorna o número total de linhas. `COUNT(ShipDate)` retorna apenas o número de linhas onde `ShipDate` não é nulo. Se 100 linhas existem mas 10 têm `ShipDate` nulo, `COUNT(*)` = 100 e `COUNT(ShipDate)` = 90.

### 2. WHERE vs HAVING

Você pode filtrar grupos usando `WHERE`? Pode filtrar linhas individuais usando `HAVING`?

> [!success]- Resposta
> Não para ambos. `WHERE` opera em linhas individuais **antes** do agrupamento e não pode referenciar resultados agregados. `HAVING` opera em grupos **após** a agregação e não pode filtrar linhas individuais pré-agrupamento sem também incluí-las no grupo.

### 3. Agregação condicional

Escreva uma consulta que retorne cada produto com quantidade total vendida e quantidade total vendida em pedidos acima de $1.000.

> [!success]- Resposta
>
> ```sql
> SELECT sod.ProductID,
>        SUM(sod.OrderQty) AS TotalQty,
>        SUM(CASE WHEN soh.TotalDue > 1000 THEN sod.OrderQty ELSE 0 END) AS LargeOrderQty
> FROM Sales.SalesOrderDetail AS sod
> INNER JOIN Sales.SalesOrderHeader AS soh ON soh.SalesOrderID = sod.SalesOrderID
> GROUP BY sod.ProductID;
> ```

### 4. Granularidade LEFT JOIN

Você faz `LEFT JOIN` de Customer para SalesOrderHeader e depois `GROUP BY CustomerID`. O que uma linha de resultado representa? O que acontece se você usar `COUNT(*)` em vez de `COUNT(SalesOrderID)`?

> [!success]- Resposta
> Uma linha por cliente. `COUNT(*)` contaria a linha estendida com nulo para clientes sem pedidos (retornando 1 em vez de 0), o que é enganoso. Sempre use `COUNT(ChildID)` para contagens de filhos em agregações com left join.

## Próximos Passos

Agregação é o portal para padrões analíticos mais avançados:

- **Funções janela** (Seção 03) — calculam agregados como totais acumulados ou médias móveis sem colapsar linhas.
- **`ROLLUP` / `CUBE` / `GROUPING SETS`** (Seção 03) — produzem múltiplos níveis de agrupamento em uma única consulta.
- **`OVER` com `PARTITION BY`** (Seção 03) — agregam dentro de um grupo enquanto preservam linhas de detalhe.

## Casos de Uso

- Gere relatórios resumidos: vendas totais por região por ano.
- Identifique outliers: clientes com contagens de pedidos excepcionalmente altas ou baixas.
- Calcule proporções: percentual do total de vendas por categoria de produto.
- Verificações de qualidade de dados: conte nulos, duplicatas ou intervalos de datas ausentes.

## Problemas Comuns & Erros

> [!warning] Erro Comum
> `COUNT(coluna)` ignora valores `NULL`; `COUNT(*)` conta linhas. Sempre escolha o que corresponde à intenção.

> [!warning] Erro Comum
> Adicionar uma coluna não agregada ao `SELECT` sem colocá-la no `GROUP BY` causa um erro. Ou agregue-a ou adicione-a ao `GROUP BY`.

> [!warning] Erro Comum
> `WHERE` em uma expressão agregada é inválido. Use `HAVING` para filtrar após o agrupamento.

## Melhores Práticas

- Declare a granularidade antes de escrever `GROUP BY`: "Uma linha por \_\_\_\_."
- Filtre cedo com `WHERE` para reduzir o número de linhas que devem ser agrupadas.
- Use `COALESCE` em torno de `SUM`/`AVG` quando um resultado `NULL` seria enganoso.
- Prefira agregação condicional (`SUM(CASE ...)`) sobre múltiplas consultas.
- Dê aos agregados aliases descritivos (`TotalSales`, não `SUM(TotalDue)`).

## Dicas para o Exame

> [!tip] Dicas para o Exame
> Entenda granularidade: toda questão de agregação no exame recompensa saber o que uma linha de resultado representa. `GROUP BY` colapsa linhas; funções janela (Seção 03) calculam valores relacionados enquanto preservam cada linha.

## Principais Conclusões

- Agregados resumem conjuntos; `GROUP BY` define o limite do conjunto.
- `WHERE` filtra linhas antes da agregação; `HAVING` filtra grupos após.
- `COUNT(*)` conta linhas; `COUNT(coluna)` conta valores não nulos.
- Agregação condicional com `CASE` é uma técnica de passagem única.
- O comportamento `NULL` difere por função agregada — conheça a tabela.

## Tópicos Relacionados

- [SELECT, filtros, subconsultas e operações de conjunto](./04-select-and-filter.md)
- [Relacionamentos e JOINs](./05-relationships-and-joins.md)
- [Subconsultas e CTEs](./09-subqueries-and-ctes.md)
- [Advanced T-SQL](../../03-advanced-tsql/advanced-tsql.md)

## Documentação Oficial

- [GROUP BY](https://learn.microsoft.com/sql/t-sql/queries/select-group-by-transact-sql)
- [Funções agregadas](https://learn.microsoft.com/sql/t-sql/functions/aggregate-functions-transact-sql)
- [HAVING](https://learn.microsoft.com/sql/t-sql/queries/select-having-transact-sql)
- [CASE](https://learn.microsoft.com/sql/t-sql/language-elements/case-transact-sql)

---

**[← Anterior](./05-relationships-and-joins.md) | [↑ Voltar à Seção](./fundamentals.md) | [Próximo →](./07-change-data-safely.md)**
