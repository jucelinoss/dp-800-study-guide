---
title: "SELECT, Filtros, Subconsultas e Operações de Conjunto"
type: topic
tags: [sql-server, select, where, subquery, set-operations, fundamentals]
---

# SELECT, Filtros, Subconsultas e Operações de Conjunto

## Visão Geral

`SELECT` é a linguagem do T-SQL para fazer perguntas aos dados. Uma consulta pode moldar colunas, filtrar linhas, comparar um resultado com outro e combinar resultados compatíveis sem alterar dados armazenados.

> [!abstract]
>
> - Domine a forma da consulta: projeção, fonte, predicados, agrupamento e ordenação.
> - Use subconsultas escalares, multi-linha, correlacionadas e derived tables apropriadamente.
> - Use `EXISTS`, `IN`, `UNION`, `INTERSECT` e `EXCEPT` para expressar questões baseadas em conjuntos.

> [!tip] Limite de escopo
> CTEs, tabelas temporárias e variáveis de tabela são estruturas de resultado intermediário. Elas pertencem à [Lição 09](./09-subqueries-and-ctes.md), onde seu tempo de vida e escopo podem ser ensinados sem duplicar a sintaxe de consulta.

---

## Uma consulta é uma pergunta sobre conjuntos

Tabelas representam conjuntos de linhas; uma consulta descreve o conjunto de resultados desejado a partir delas. O SQL Server decide como executar essa descrição.

```sql
SELECT p.ProductName,
       p.UnitPrice,
       p.UnitPrice * 1.10 AS price_with_tax
FROM study.Product AS p
WHERE p.IsDiscontinued = 0
ORDER BY price_with_tax DESC, p.ProductName ASC;
```

`price_with_tax` é calculado no resultado; não atualiza `UnitPrice`. A ordem de processamento lógico simplificada explica muitas regras de consulta:

```text
FROM / JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → TOP/OFFSET
```

| Cláusula | Propósito | Exemplo |
| :--- | :--- | :--- |
| `FROM` | Escolher linhas fonte | `FROM study.Product AS p` |
| `WHERE` | Filtrar linhas individuais | `WHERE UnitPrice >= 10` |
| `GROUP BY` | Definir granularidade do sumário | um resultado por cliente |
| `HAVING` | Filtrar grupos completados | total gasto >= 100 |
| `SELECT` | Moldar colunas de saída | nome, preço, cálculo |
| `ORDER BY` | Ordenar resultado final | maior preço primeiro |

## Projeção, aliases e filtros

Selecione apenas colunas que o resultado precisa. `SELECT *` é aceitável para exploração única, mas uma consulta durável não deve mudar silenciosamente quando uma tabela ganha uma coluna ou expor campos que o chamador não precisa.

```sql
SELECT CustomerId, CustomerName, Email
FROM study.Customer;
```

Use aliases para saída legível e consultas multi-tabela sem ambiguidade. `DISTINCT` remove linhas de resultado duplicadas completas; não é um reparo para um JOIN incorreto.

```sql
SELECT DISTINCT CustomerId
FROM study.SalesOrder;
```

`WHERE` mantém apenas linhas cuja condição é verdadeira:

| Padrão | Exemplo |
| :--- | :--- |
| comparação | `UnitPrice >= 20` |
| pertinência | `CustomerId IN (1, 3, 5)` |
| intervalo inclusivo | `UnitPrice BETWEEN 10 AND 20` |
| padrão de texto | `ProductName LIKE N'A%'` |
| valor ausente | `Email IS NULL` |

```sql
SELECT ProductName, UnitPrice
FROM study.Product
WHERE IsDiscontinued = 0
  AND UnitPrice BETWEEN 5.00 AND 50.00
  AND ProductName NOT LIKE N'%used%'
ORDER BY UnitPrice DESC;
```

Use parênteses sempre que `AND` e `OR` se misturarem:

```sql
WHERE IsActive = 1
  AND (Email IS NULL OR Email LIKE N'%@example.test')
```

Para uma coluna `datetime2`, use um intervalo de meio aberto para que cada hora do último dia seja incluída:

```sql
WHERE CreatedAt >= '2026-07-01'
  AND CreatedAt <  '2026-08-01'
```

## Ordene, limite e pagine resultados

Linhas não têm ordem prometida sem `ORDER BY`. `TOP` sem ele significa quaisquer linhas correspondentes.

```sql
SELECT TOP (5) ProductName, UnitPrice
FROM study.Product
ORDER BY UnitPrice DESC, ProductName ASC;
```

Use `OFFSET`/`FETCH` apenas com uma ordem estável:

```sql
SELECT ProductId, ProductName
FROM study.Product
ORDER BY ProductId
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
```

## Subconsultas: consulta dentro de consulta

Uma subconsulta fornece a uma consulta externa um valor, um conjunto, um teste de existência ou um resultado utilizável como fonte.

| Forma | Retorna | Use para |
| :--- | :--- | :--- |
| Subconsulta escalar | Um valor | Comparar uma linha a uma média ou máximo |
| Subconsulta multi-linha | Conjunto de uma coluna | Pertinência com `IN` |
| Subconsulta `EXISTS` | Existência | Se uma linha relacionada está presente |
| Derived table | Linhas e colunas | Consultar um resultado já moldado |

### Subconsulta escalar

```sql
SELECT SalesOrderId, CustomerId, OrderTotal
FROM study.SalesOrder
WHERE OrderTotal > (
    SELECT AVG(OrderTotal)
    FROM study.SalesOrder
);
```

A consulta interna deve retornar um valor. Se retornar múltiplas linhas em um contexto escalar, o SQL Server gera um erro.

### `IN`: pertinência a um conjunto

```sql
SELECT CustomerName
FROM study.Customer
WHERE CustomerId IN (
    SELECT CustomerId
    FROM study.SalesOrder
    WHERE OrderTotal >= 20.00
);
```

Leia como "clientes cujo ID pertence ao conjunto de clientes com um pedido qualificado." Duplicatas no resultado interno não alteram a pertinência.

### `EXISTS` e subconsultas correlacionadas

`EXISTS` é melhor quando a pergunta é "existe pelo menos uma linha relacionada?" A consulta é correlacionada porque a consulta interna referencia o cliente externo atual.

```sql
SELECT c.CustomerId, c.CustomerName
FROM study.Customer AS c
WHERE EXISTS (
    SELECT 1
    FROM study.SalesOrder AS o
    WHERE o.CustomerId = c.CustomerId
);
```

`SELECT 1` é convencional; `EXISTS` se importa apenas se a consulta interna produz uma linha. Use `NOT EXISTS` para clientes sem pedidos:

```sql
SELECT c.CustomerId, c.CustomerName
FROM study.Customer AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM study.SalesOrder AS o
    WHERE o.CustomerId = c.CustomerId
);
```

> [!warning] `NOT IN` e `NULL`
> Se o resultado interno de `NOT IN` contiver `NULL`, o predicado pode se tornar desconhecido para toda linha externa. Prefira `NOT EXISTS` para questões de anti-relacionamento a menos que `NULL` seja excluído deliberadamente.

### Derived tables

Uma derived table é uma subconsulta no `FROM`; deve ter um alias.

```sql
SELECT totals.CustomerId, totals.TotalSpend
FROM (
    SELECT CustomerId, SUM(OrderTotal) AS TotalSpend
    FROM study.SalesOrder
    GROUP BY CustomerId
) AS totals
WHERE totals.TotalSpend >= 100.00;
```

Use uma derived table para um pequeno passo de uma instrução. Uma CTE expressa o mesmo tipo de passo lógico com um nome; a Lição 09 explica seu escopo.

## Operadores de conjunto: combine resultados compatíveis

Operadores de conjunto empilham resultados verticalmente. As duas consultas devem retornar o mesmo número de colunas com tipos compatíveis e significado correspondente.

| Operador | Significado | Duplicatas |
| :--- | :--- | :--- |
| `UNION` | Linha em qualquer resultado | Removidas |
| `UNION ALL` | Linha em qualquer resultado | Mantidas |
| `INTERSECT` | Linha em ambos os resultados | Removidas |
| `EXCEPT` | Linha no primeiro mas não no segundo | Removidas |

```sql
-- Clientes que têm um pedido ou um email registrado.
SELECT CustomerId
FROM study.SalesOrder
UNION
SELECT CustomerId
FROM study.Customer
WHERE Email IS NOT NULL;

-- Clientes na lista de clientes que não fizeram um pedido.
SELECT CustomerId
FROM study.Customer
EXCEPT
SELECT CustomerId
FROM study.SalesOrder;
```

Use `UNION ALL` quando manter duplicatas é intencional ou os resultados são conhecidos como disjuntos; evita o trabalho de remoção de duplicatas de `UNION`. `INTERSECT` é útil para a sobreposição de duas listas.

### Operador de conjunto versus JOIN

```text
JOIN:  colunas do cliente + colunas do pedido  → linhas mais largas
UNION: linhas do resultado A + resultado B     → resultado mais alto
```

Use um JOIN para exibir um cliente ao lado de seus pedidos. Use um operador de conjunto para mesclar ou comparar listas compatíveis.

## Onde CTEs, tabelas temporárias e variáveis de tabela se encaixam

A estrutura deve corresponder a quanto tempo um resultado intermediário é necessário.

| Estrutura | Tempo de vida | Uso apropriado |
| :--- | :--- | :--- |
| Subconsulta / derived table | Uma instrução | Pequeno passo de consulta local |
| CTE | Uma instrução seguinte | Passo lógico nomeado e legível |
| Variável de tabela (`@T`) | Lote/procedimento/função atual | Conjunto processual pequeno com escopo |
| Tabela temporária local (`#T`) | Sessão atual | Reutilizar linhas intermediárias entre instruções |
| Tabela temporária global (`##T`) | Compartilhada enquanto existe | Evite por padrão; escopo compartilhado é arriscado |

A Lição 04 possui o vocabulário de consulta. A [Lição 09](./09-subqueries-and-ctes.md) possui o tempo de vida, escopo e escolha entre CTE, tabela temporária e variável de tabela. Isso evita que a teoria de CTE seja repetida em ambos os capítulos.

## Questões de Prática

### 1. Filtro de grupo

Qual cláusula filtra grupos após `SUM(OrderTotal)` ser calculado?

A. `WHERE`<br>
B. `HAVING`<br>
C. `ORDER BY`<br>
D. `DISTINCT`

> [!success]- Answer
> **B. `HAVING`** filtra resultados agrupados; `WHERE` filtra linhas de entrada antes do agrupamento.

### 2. Relacionamentos ausentes

Qual padrão retorna mais diretamente clientes sem pedidos?

A. `CustomerId <> NULL`<br>
B. `INNER JOIN SalesOrder`<br>
C. `NOT EXISTS (SELECT 1 FROM SalesOrder WHERE ...)`<br>
D. `UNION ALL`

> [!success]- Answer
> **C.** `NOT EXISTS` expressa a ausência de uma linha relacionada e evita o comportamento `NULL` de `NOT IN`.

### 3. Diferença de listas

Qual operador retorna linhas distintas presentes no primeiro resultado mas não no segundo?

A. `UNION ALL`<br>
B. `INTERSECT`<br>
C. `EXCEPT`<br>
D. `CROSS JOIN`

> [!success]- Answer
> **C. `EXCEPT`** retorna linhas do primeiro resultado menos o segundo.

## Casos de Uso

- Inspecione linhas exatas antes de um `UPDATE` ou `DELETE`.
- Compare cada linha com um benchmark calculado usando uma subconsulta escalar.
- Encontre entidades que têm ou não têm linhas relacionadas com `EXISTS`/`NOT EXISTS`.
- Mescle ou compare listas compatíveis com operadores de conjunto.

## Problemas Comuns & Erros

> [!warning] Erro Comum
> Sem `ORDER BY`, o SQL Server pode retornar linhas em qualquer ordem. `TOP` sem `ORDER BY` portanto retorna linhas arbitrárias.

> [!warning] Erro Comum
> `DISTINCT` e `UNION` podem esconder joins ruins ou dados duplicados inesperados. Entenda a fonte antes de remover duplicatas.

## Melhores Práticas

- Selecione apenas colunas necessárias e dê aliases claros a valores calculados.
- Use parênteses em condições mistas de `AND`/`OR`.
- Use `EXISTS` quando a pergunta é sobre existência, não sobre valores internos.
- Use `UNION ALL` apenas quando duplicatas são intencionalmente preservadas.
- Mantenha a lógica de uma instrução em uma subconsulta ou CTE; introduza estruturas temporárias apenas quando seu tempo de vida for necessário.

## Dicas para o Exame

> [!tip] Dicas para o Exame
> `WHERE` filtra linhas e `HAVING` filtra grupos. `EXISTS` testa se uma subconsulta correlacionada retorna alguma linha. `UNION` remove duplicatas, `UNION ALL` as preserva, `INTERSECT` encontra linhas comuns e `EXCEPT` encontra linhas apenas no primeiro resultado.

## Principais Conclusões

- `SELECT` descreve um resultado e não altera dados armazenados.
- A forma da subconsulta deve corresponder a se a consulta externa precisa de um valor, um conjunto ou existência.
- Operadores de conjunto empilham resultados compatíveis; JOINs combinam colunas de linhas relacionadas.
- CTEs, tabelas temporárias e variáveis de tabela são cobertas como estruturas intermediárias na Lição 09.

## Tópicos Relacionados

- [Relacionamentos e JOINs](./05-relationships-and-joins.md)
- [Agregação e agrupamento](./06-aggregation-and-grouping.md)
- [Subconsultas e CTEs](./09-subqueries-and-ctes.md)
- [Advanced T-SQL](../../03-advanced-tsql/advanced-tsql.md)

## Documentação Oficial

- [SELECT](https://learn.microsoft.com/sql/t-sql/queries/select-transact-sql)
- [Subconsultas](https://learn.microsoft.com/sql/relational-databases/performance/subqueries)
- [EXISTS](https://learn.microsoft.com/sql/t-sql/language-elements/exists-transact-sql)
- [UNION, EXCEPT e INTERSECT](https://learn.microsoft.com/sql/t-sql/language-elements/set-operators-union-transact-sql)

---

**[← Anterior](./03-create-and-load-data.md) | [↑ Voltar à Seção](./fundamentals.md) | [Próximo →](./05-relationships-and-joins.md)**
