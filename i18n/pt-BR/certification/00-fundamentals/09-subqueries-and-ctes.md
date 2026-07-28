---
title: "CTEs e Estruturas Temporárias de Consulta"
type: topic
tags: [sql-server, cte, temp-table, table-variable, derived-table, fundamentals]
---

# CTEs e Estruturas Temporárias de Consulta

## Visão Geral

Quando uma consulta precisa de um resultado intermediário — para simplificar um cálculo de múltiplas etapas, reutilizar linhas entre instruções ou dividir um problema complexo em partes legíveis — o SQL Server oferece várias estruturas temporárias. Escolher a certa depende de escopo, reutilização e características de performance.

> [!abstract]
>
> - Use uma **derived table** (subconsulta no `FROM`) para um resultado inline de uma etapa.
> - Use uma **CTE** para nomear uma etapa lógica e melhorar a legibilidade em uma única instrução.
> - Use uma **tabela temporária local** quando várias instruções precisam das mesmas linhas intermediárias.
> - Use uma **variável de tabela** para um conjunto processual pequeno com escopo; nenhuma é um atalho de performance.

> [!tip] O que o Exame Testa
> Subconsultas (escalares, multi-valor), `EXISTS`, `NOT IN` e operadores de conjunto são cobertos na [Lição 04](./04-select-and-filter.md). Esta lição constrói a ponte para design avançado de consultas: CTEs recursivas, `APPLY` e padrões analíticos complexos na Seção 03.

---

## Derived tables

Uma **derived table** é uma subconsulta na cláusula `FROM`. Ela deve ter um alias e é visível apenas na instrução que a define.

```sql
-- Derived table: subconsulta no FROM com alias obrigatório
SELECT dt.ProductID, dt.TotalSold
FROM (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
) AS dt
WHERE dt.TotalSold > 100;
```

**Limitações:**

- Não pode ser referenciada mais de uma vez na mesma instrução.
- Não pode ser usada em consultas recursivas.
- Aninhar derived tables reduz a legibilidade.

```sql
-- Derived tables aninhadas (difícil de ler — prefira CTE)
SELECT SalesOrderID, TotalDue
FROM (
    SELECT SalesOrderID, TotalDue,
           ROW_NUMBER() OVER (ORDER BY TotalDue DESC) AS rn
    FROM Sales.SalesOrderHeader
) AS ranked
WHERE ranked.rn <= 5;
```

## Common Table Expressions (CTEs)

Uma CTE dá a um resultado de consulta um nome temporário para a instrução que a segue. Diferentemente de uma derived table, uma CTE pode ser referenciada múltiplas vezes na mesma instrução e suporta recursão.

```sql
-- CTE simples
WITH ProductSales AS (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
)
SELECT p.Name, ps.TotalSold
FROM ProductSales AS ps
INNER JOIN Production.Product AS p ON p.ProductID = ps.ProductID
WHERE ps.TotalSold > 100
ORDER BY ps.TotalSold DESC;
```

### CTEs múltiplas

Separe definições de CTE com uma vírgula. Cada CTE pode referenciar as definidas antes dela.

```sql
WITH
ProductSales AS (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
),
HighSellers AS (
    SELECT ProductID, TotalSold
    FROM ProductSales
    WHERE TotalSold > 1000
)
SELECT p.Name, hs.TotalSold
FROM HighSellers AS hs
INNER JOIN Production.Product AS p ON p.ProductID = hs.ProductID
ORDER BY hs.TotalSold DESC;
```

> [!warning] Erro Comum
> Uma CTE não é uma tabela temporária — é uma **expressão lógica** que o otimizador incorpora na consulta externa. Referenciar a mesma CTE duas vezes em uma instrução pode fazer com que a consulta subjacente execute duas vezes (sem materialização automática).

## CTEs vs derived tables

A mesma pergunta de negócio expressa de ambas as formas:

```sql
-- Estilo derived table
SELECT dt.CustomerID, dt.TotalSpend
FROM (
    SELECT CustomerID, SUM(TotalDue) AS TotalSpend
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
) AS dt
WHERE dt.TotalSpend > 5000;

-- Estilo CTE
WITH CustomerSpend AS (
    SELECT CustomerID, SUM(TotalDue) AS TotalSpend
    FROM Sales.SalesOrderHeader
    GROUP BY CustomerID
)
SELECT CustomerID, TotalSpend
FROM CustomerSpend
WHERE TotalSpend > 5000;
```

**Quando escolher qual:**

| Fator | CTE | Derived table |
| :--- | :--- | :--- |
| Legibilidade | Mais clara, especialmente com múltiplas etapas | Pode tornar-se profundamente aninhada |
| Referências múltiplas | Pode referenciar a mesma CTE mais de uma vez | Deve repetir a subconsulta |
| Recursão | Suporta consultas recursivas | Sem recursão |
| Escopo | Instrução única | Instrução única |

## Tabelas temporárias locais (#Temp)

Uma tabela temporária local é uma tabela física em `tempdb` que persiste durante a sessão. Suporta índices, estatísticas e todo DML T-SQL.

```sql
-- Crie uma tabela temporária local com chave primária
CREATE TABLE #HighValueOrders (
    SalesOrderID INT NOT NULL PRIMARY KEY,
    TotalDue     DECIMAL(18,2) NOT NULL
);

-- Insira nela
INSERT INTO #HighValueOrders (SalesOrderID, TotalDue)
SELECT SalesOrderID, TotalDue
FROM Sales.SalesOrderHeader
WHERE TotalDue > 5000;

-- Use-a em instruções subsequentes
SELECT COUNT(*) AS HighValueCount FROM #HighValueOrders;

-- Limpe explicitamente
DROP TABLE IF EXISTS #HighValueOrders;
```

**Características:**

- Visível apenas para a sessão criadora (nenhuma outra sessão pode ver `#HighValueOrders`).
- Descartada automaticamente quando a sessão termina, mas descartar explicitamente é melhor prática.
- Pode ter índices, restrições e estatísticas como uma tabela regular.
- Suporta `INSERT`, `UPDATE`, `DELETE`, `MERGE`.

> [!warning] Erro Comum
> Uma `#TempTable` tem escopo de sessão. Evite `##GlobalTempTable` (duplo `#`) por padrão — tabelas temporárias globais são visíveis a todas as sessões e criam colisões de nomes e dependências ocultas.

## Variáveis de tabela (@TableVar)

Uma variável de tabela tem escopo do lote, procedimento ou função que a declara. É mais leve que uma tabela temporária, mas tem limitações.

```sql
DECLARE @SelectedProducts TABLE (
    ProductID INT NOT NULL PRIMARY KEY,
    ListPrice DECIMAL(18,2) NOT NULL
);

INSERT INTO @SelectedProducts (ProductID, ListPrice)
SELECT ProductID, ListPrice
FROM Production.Product
WHERE ListPrice > 500;

SELECT COUNT(*) AS ExpensiveProducts FROM @SelectedProducts;
```

**Limitações vs tabelas temporárias:**

| Característica | #TempTable | @TableVariable |
| :--- | :--- | :--- |
| Escopo | Sessão | Lote / procedimento |
| Estatísticas | Sim (podem ser recriadas) | Não (estimativa de cardinalidade = 1 linha) |
| Índices | Sim (após criação) | Apenas chave primária / unique na declaração |
| Transações | Logado (pode desfazer) | Logado (mas menos logging em tempdb) |
| Quando usar | Conjuntos de dados maiores, muitas linhas | Conjuntos de lookup pequenos, escopo processual |

> [!note] Modelo mental — CTE = fórmula de planilha, #Temp = rascunho físico
> Uma CTE é como uma fórmula nomeada em uma planilha: recalcula cada vez que você a referencia. Uma tabela temporária é como escrever resultados intermediários em um pedaço de papel que fica em sua mesa (sessão) até você limpá-lo.

## Escolhendo a estrutura certa

| Necessidade | Escolha | Razão |
| :--- | :--- | :--- |
| Nomear uma etapa de consulta em uma instrução | CTE | Sintaxe mais limpa, sem persistência |
| Mesmo resultado intermediário usado 2+ vezes em uma consulta | CTE | Referencie pelo nome, mas cuidado com reexecução |
| Reutilizar linhas entre instruções na mesma sessão | `#TempTable` | Persiste entre lotes |
| Conjunto de lookup pequeno em um procedimento | `@TableVariable` | Escopo limitado, limpeza automática |
| Hierarquia recursiva (organograma, BOM) | CTE Recursiva | Única opção recursiva em T-SQL |
| Passar parâmetro com valor de tabela para uma função | `@TableVariable` | Obrigatório para TVP |

```sql
-- Quando você precisa TANTO de CTE (legibilidade) quanto de persistência (reuso):
-- 1. Defina a lógica em uma CTE
-- 2. Insira os resultados em uma tabela temporária
-- 3. Consulte a tabela temporária múltiplas vezes

WITH ProductSales AS (
    SELECT ProductID, SUM(OrderQty) AS TotalSold
    FROM Sales.SalesOrderDetail
    GROUP BY ProductID
)
SELECT p.ProductID, p.Name, ps.TotalSold
INTO #ProductSalesReport
FROM ProductSales AS ps
INNER JOIN Production.Product AS p ON p.ProductID = ps.ProductID;

-- Agora reutilize #ProductSalesReport em várias consultas
SELECT COUNT(*) FROM #ProductSalesReport WHERE TotalSold > 100;
SELECT AVG(TotalSold) FROM #ProductSalesReport;

DROP TABLE IF EXISTS #ProductSalesReport;
```

## Verifique-se

### 1. CTE ou derived table?

Escreva uma consulta que retorne os 5 principais produtos por valor total de vendas usando uma CTE. Use o schema AdventureWorks: `Sales.SalesOrderDetail` (UnitPrice, OrderQty) e `Production.Product` (Name).

> [!success]- Resposta
>
> ```sql
> WITH ProductRevenue AS (
>     SELECT sod.ProductID,
>            SUM(sod.UnitPrice * sod.OrderQty) AS Revenue
>     FROM Sales.SalesOrderDetail AS sod
>     GROUP BY sod.ProductID
> )
> SELECT TOP 5 p.Name, pr.Revenue
> FROM ProductRevenue AS pr
> INNER JOIN Production.Product AS p ON p.ProductID = pr.ProductID
> ORDER BY pr.Revenue DESC;
> ```

### 2. CTEs múltiplas

Você precisa de pedidos com total > 5000 E clientes que fizeram esses pedidos. Escreva uma consulta usando duas CTEs (uma para pedidos de alto valor, outra juntando ao Customer).

> [!success]- Resposta
>
> ```sql
> WITH HighValueOrders AS (
>     SELECT SalesOrderID, CustomerID, TotalDue
>     FROM Sales.SalesOrderHeader
>     WHERE TotalDue > 5000
> ),
> CustomerHighValue AS (
>     SELECT c.CustomerID, c.AccountNumber, hvo.TotalDue
>     FROM Sales.Customer AS c
>     INNER JOIN HighValueOrders AS hvo ON hvo.CustomerID = c.CustomerID
> )
> SELECT * FROM CustomerHighValue
> ORDER BY TotalDue DESC;
> ```

### 3. #Temp vs @TableVar

Quando você escolheria uma tabela temporária local em vez de uma variável de tabela?

> [!success]- Resposta
> Escolha `#TempTable` quando: (a) o resultado intermediário tem mais de ~100 linhas e precisa de estatísticas precisas para o otimizador; (b) você precisa de índices secundários; (c) os dados devem persistir entre múltiplos lotes na mesma sessão. Escolha `@TableVariable` para conjuntos de lookup pequenos (10–50 linhas) dentro de um único procedimento onde a limpeza automática é conveniente.

### 4. Materialização de CTE

Uma CTE é referenciada duas vezes em uma consulta. O SQL Server materializa o resultado uma vez ou o executa duas vezes?

> [!success]- Resposta
> O SQL Server pode executar a definição da CTE **duas vezes** (uma por referência). Uma CTE é uma expressão lógica, não um resultado materializado. Se a definição for cara e referenciada múltiplas vezes, considere inserir em uma `#TempTable`.

## Próximos Passos

- **CTEs recursivas** (Seção 03) — navegue hierarquias como organogramas e listas técnicas.
- **Operador `APPLY`** (Seção 03) — aplique uma expressão do lado direito a cada linha da entrada esquerda.
- **Views e funções de valor de tabela** (Seção 02) — encapsule lógica tipo CTE em objetos de banco de dados reutilizáveis.

## Casos de Uso

- Decomponha uma consulta analítica complexa em etapas nomeadas e legíveis.
- Prepare conjuntos de dados intermediários para múltiplas consultas de acompanhamento em uma sessão.
- Armazene um pequeno conjunto de referência (códigos de moeda, lookups de status) em um procedimento.
- Gere um resumo de relatório a partir de dados de transação detalhados.

## Problemas Comuns & Erros

> [!warning] Erro Comum
> Uma CTE deve ser imediatamente seguida pela instrução que a usa. Seu nome não está disponível para o próximo lote ou para um limite `GO` separado.

> [!warning] Erro Comum
> `#TempTable` é visível apenas na sessão criadora. Evite `##GlobalTempTable` — escopo compartilhado cria colisões e dependências ocultas.

> [!warning] Erro Comum
> Variáveis de tabela **não têm estatísticas**. Para conjuntos de dados grandes (1000+ linhas), o otimizador assume 1 linha, o que pode levar a planos de consulta ruins. Use `#TempTable` para resultados intermediários maiores.

## Melhores Práticas

- Use nomes que descrevam o resultado, não a implementação (`ProductSales`, não `CTE1`).
- Escolha a forma mais clara primeiro, depois meça antes de mudar uma consulta por performance.
- Explicitamente `DROP TABLE` tabelas temporárias quando não forem mais necessárias.
- Para consultas de relatório com múltiplas referências à mesma subconsulta, prefira inserir em uma tabela temporária para evitar execução repetida.

## Dicas para o Exame

> [!tip] Dicas para o Exame
> Uma CTE e uma derived table são ambas expressões lógicas de consulta — nenhuma persiste dados por si só. Uma CTE pode ser recursiva; uma derived table não pode. Tabelas temporárias e variáveis de tabela dão às linhas intermediárias um tempo de vida mais longo e com escopo. Conheça os limites de escopo: CTE = uma instrução, #Temp = sessão, @TableVar = lote/procedimento.

## Principais Conclusões

- CTEs nomeiam lógica de uma instrução; tabelas temporárias e variáveis de tabela dão às linhas intermediárias um tempo de vida mais longo e com escopo.
- Use a menor estrutura que expresse a tarefa claramente.
- CTEs não são materializadas por padrão — referenciar uma CTE duas vezes pode executar sua definição duas vezes.
- Variáveis de tabela não têm estatísticas; use tabelas temporárias para conjuntos de dados intermediários maiores.

## Tópicos Relacionados

- [SELECT, filtros, subconsultas e operações de conjunto](./04-select-and-filter.md)
- [Advanced T-SQL](../../03-advanced-tsql/advanced-tsql.md)
- [Performance Optimization](../../06-performance-optimization/performance-optimization.md)
- [Database Objects](../../01-database-objects/database-objects.md)

## Documentação Oficial

- [WITH common table expression](https://learn.microsoft.com/sql/t-sql/queries/with-common-table-expression-transact-sql)
- [CREATE TABLE (temporária)](https://learn.microsoft.com/sql/t-sql/statements/create-table-transact-sql)
- [Variáveis de tabela](https://learn.microsoft.com/sql/t-sql/language-elements/declare-local-variable-transact-sql)
- [Derived tables](https://learn.microsoft.com/sql/t-sql/queries/from-using-pivotal-and-unpivotal)

---

**[← Anterior](./08-integrity-rules.md) | [↑ Voltar à Seção](./fundamentals.md) | [Lab: Index Introduction](../../practice/labs/00-fundamentals/09-index-introduction.sql) | [Próximo →](./10-index-fundamentals.md)**
