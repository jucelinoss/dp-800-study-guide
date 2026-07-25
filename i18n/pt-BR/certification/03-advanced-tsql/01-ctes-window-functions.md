---
title: CTEs and Window Functions
type: study-material
tags:
  - dp-800
  - cte
  - window-functions
  - ranking
  - analytics
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Common Table Expressions (CTEs)](#common-table-expressions-ctes)
>   - 🔹 [CTE Básica & Múltiplas CTEs](#cte-basica-basic-cte)
>   - 🔹 [CTE Recursiva (Hierarquias)](#cte-recursiva-recursive-cte)
>   - 🔹 [Comportamento de Não-Materialização](#cte-non-materialization-behavior)
>   - 🔹 [Limite de Profundidade (MAXRECURSION)](#limite-de-profundidade-em-ctes-recursivas)
> - 📍 [3. Window Functions](#window-functions)
>   - 🔹 [Ranking Functions (ROW_NUMBER, RANK, DENSE_RANK)](#ranking-functions-funcoes-de-classificacao)
>   - 🔹 [Aggregate Window Functions](#funcoes-de-agregacao-na-janela-aggregate-window-functions)
>   - 🔹 [Offset Functions (LAG, LEAD, FIRST_VALUE, LAST_VALUE)](#funcoes-de-deslocamento-offset-functions)
>   - 🔹 [Especificação de Frames (Frame Specification)](#especificacao-de-frames-frame-specification)
>   - 🔹 [PERCENT_RANK, CUME_DIST & LAST_VALUE Pitfall](#percent_rank-e-cume_dist)
> - 📍 [4. Aplicação Prática & Síntese](#padroes-comuns-de-queries-common-patterns)
>   - 🔹 [Padrões Comuns de Queries](#padroes-comuns-de-queries-common-patterns)
>   - 🔹 [Casos de Uso & Problemas Comuns](#casos-de-uso-use-cases)
>   - 🔹 [Melhores Práticas & Exam Tips](#melhores-praticas-best-practices)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)

---

# CTEs and Window Functions

## Visão Geral (Overview)

As Common Table Expressions (CTEs) fornecem conjuntos de resultados temporários nomeados que tornam queries complexas mais legíveis e reutilizáveis. As Window Functions realizam cálculos matemáticos e estatísticos através de conjuntos de linhas correlacionadas à linha corrente (a janela de dados) — sem colapsar ou agrupar os registros resultantes como faz o comando `GROUP BY`.

> [!abstract]
>
> - Cobre CTEs (recursivas e não recursivas), Window Functions (`ROW_NUMBER`, `RANK`, `DENSE_RANK`, `LAG`, `LEAD`, `SUM OVER`) e cláusulas de especificação de frames (`ROWS`/`RANGE`).
> - As CTEs aumentam a legibilidade; as CTEs recursivas percorrem estruturas hierárquicas e grafos; as Window Functions calculam valores sobre partições lógicas de dados sem colapsar as linhas.
> - Tópicos chave do exame: comportamento de desempate (ties) nas funções de classificação (ranking), estrutura lógica de CTEs recursivas e as diferenças entre as cláusulas de frame `ROWS` vs `RANGE`.

> [!tip] O que o Exame Testa
>
> - Desempates (Ties): `ROW_NUMBER` = gera números sequenciais únicos arbitrários; `RANK` = deixa lacunas de numeração após empates (ex: 1, 1, 3); `DENSE_RANK` = não gera lacunas sequenciais nos empates (ex: 1, 1, 2).
> - CTE Recursiva = composta obrigatoriamente por um **anchor member** (executado uma vez) associado por um `UNION ALL` ao **recursive member** (executado repetidamente até que nenhuma linha seja retornada). Limite físico padrão de 100 recursões; contornável via hint de consulta `OPTION (MAXRECURSION n)` (com `0` indicando infinito).
> - A cláusula `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` é o padrão performante para totalizadores acumulados (running totals); o modificador padrão `RANGE` computa faixas lógicas agregando empates em um único bloco de cálculo.

---

## Common Table Expressions (CTEs)

### CTE Básica (Basic CTE)

```sql
-- Declarar uma CTE simples
WITH RecentOrders AS (
    SELECT OrderId, CustomerId, OrderDate, TotalAmount
    FROM dbo.Orders
    WHERE OrderDate >= DATEADD(DAY, -30, GETUTCDATE())
)
SELECT c.Name, r.OrderId, r.TotalAmount
FROM RecentOrders r
JOIN dbo.Customers c ON c.CustomerId = r.CustomerId;
```

### Múltiplas CTEs (Multiple CTEs)

```sql
WITH
TopCustomers AS (
    SELECT CustomerId, SUM(TotalAmount) AS Revenue
    FROM dbo.Orders
    GROUP BY CustomerId
    HAVING SUM(TotalAmount) > 10000
),
CustomerDetails AS (
    SELECT c.CustomerId, c.Name, c.Email
    FROM dbo.Customers c
    WHERE c.IsActive = 1
)
SELECT cd.Name, cd.Email, tc.Revenue
FROM TopCustomers tc
JOIN CustomerDetails cd ON cd.CustomerId = tc.CustomerId
ORDER BY tc.Revenue DESC;
```

### CTE Recursiva (Recursive CTE)

As **Recursive CTEs** são projetadas para navegar em dados com relações hierárquicas ou grafos (ex: organogramas de empresas ou listas de materiais de montagem - Bill of Materials).

```sql
WITH EmployeeHierarchy AS (
    -- Anchor: funcionários raiz do topo da cadeia (sem gerente direto)
    SELECT EmployeeId, Name, ManagerId, 0 AS Level
    FROM dbo.Employees
    WHERE ManagerId IS NULL

    UNION ALL

    -- Recursive: funcionários nos níveis hierárquicos inferiores
    SELECT e.EmployeeId, e.Name, e.ManagerId, h.Level + 1
    FROM dbo.Employees e
    JOIN EmployeeHierarchy h ON h.EmployeeId = e.ManagerId
)
SELECT EmployeeId, Name, Level,
       REPLICATE('  ', Level) + Name AS IndentedName
FROM EmployeeHierarchy
ORDER BY Level, Name;
```

**Mecanismos de salvaguarda em recursão:**

- Limite físico padrão: 100 iterações (sobrescrever aplicando o hint `OPTION (MAXRECURSION n)`).
- Sempre inclua um filtro `WHERE` consistente para interromper a execução recursiva e evitar loops infinitos.

---

## CTE Non-Materialization Behavior

As CTEs **não são materializadas** em disco ou memória por padrão — elas agem apenas como definições lógicas temporárias inline expandidas pelo otimizador de consultas (como Views). Se a mesma CTE for referenciada múltiplas vezes dentro de uma query, o otimizador pode executar o código da CTE repetidas vezes. Diferentemente, tabelas temporárias (`#temp`) e variáveis de tabela são materializadas fisicamente no TempDB.

As CTEs recursivas são exceções: o resultado gerado pelo membro âncora (anchor) é temporariamente armazenado em cache para servir às iterações recursivas subsequentes.

```sql
-- CTE invocada duas vezes: risco de dupla execução (sem garantia de cache)
WITH ExpensiveCTE AS (
    SELECT CustomerID, COUNT(*) AS OrderCount
    FROM Orders
    GROUP BY CustomerID
)
SELECT c.Name, e.OrderCount
FROM Customers c
JOIN ExpensiveCTE e ON c.CustomerID = e.CustomerID
WHERE e.OrderCount > (SELECT AVG(OrderCount) FROM ExpensiveCTE); -- A CTE executa novamente aqui!

-- Abordagem otimizada: materializar em tabela temporária quando houver multi-referência
SELECT CustomerID, COUNT(*) AS OrderCount
INTO #OrderCounts FROM Orders GROUP BY CustomerID;

SELECT c.Name, o.OrderCount FROM Customers c
JOIN #OrderCounts o ON c.CustomerID = o.CustomerID
WHERE o.OrderCount > (SELECT AVG(OrderCount) FROM #OrderCounts);
```

**Quando preferir uma tabela temporária em vez de uma CTE:**

- A CTE realiza agregações ou joins complexos e caros de processamento e é referenciada mais de uma vez na query.
- É necessário ter estatísticas atualizadas das linhas geradas para otimizar queries subsequentes (tabelas temporárias expõem estatísticas ao otimizador; CTEs não).

> [!important] CTEs e Reutilização: O Perigo da Não-Materialização
>
> - Ao contrário das tabelas temporárias, as CTEs são tratadas pelo otimizador como Views embutidas.
> - Se você referenciar a mesma CTE três vezes na mesma query, o motor poderá executar a query interna da CTE três vezes físicas. Se a query for pesada, reescreva-a usando uma tabela temporária `#temp` para armazenar o resultado intermediário.

---

## Limite de Profundidade em CTEs Recursivas

O limite de profundidade máximo de recursão por padrão no SQL Server é de **100**. Utilize a cláusula `OPTION(MAXRECURSION n)` para alterar; o valor `0` remove o limite físico (use com cautela extrema — loops infinitos rodarão indefinidamente até esgotar os recursos de hardware ou a query ser cancelada manualmente).

```sql
-- Navegar na árvore da empresa com limite de profundidade rígido
WITH OrgHierarchy AS (
    -- Anchor: executivos do topo da pirâmide
    SELECT EmployeeID, Name, ManagerID, 0 AS Level
    FROM Employees WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive: funcionários vinculados ao nível anterior
    SELECT e.EmployeeID, e.Name, e.ManagerID, h.Level + 1
    FROM Employees e
    JOIN OrgHierarchy h ON e.ManagerID = h.EmployeeID
)
SELECT * FROM OrgHierarchy
ORDER BY Level, Name
OPTION(MAXRECURSION 50); -- Limita fisicamente a recursão a 50 níveis
```

---

## Window Functions

As Window Functions utilizam a cláusula obrigatória `OVER()` para especificar a janela (grupo de linhas) sobre a qual os cálculos serão realizados — sem agrupar as linhas, preservando a identidade de cada registro original no SELECT.

### Ranking Functions (Funções de Classificação)

```sql
SELECT
    ProductId,
    CategoryId,
    Price,
    -- Ranking global (deixa lacunas após empates: 1, 1, 3)
    RANK()          OVER (ORDER BY Price DESC) AS GlobalRank,
    -- Ranking sem deixar lacunas após empates (1, 1, 2)
    DENSE_RANK()    OVER (ORDER BY Price DESC) AS DenseRank,
    -- Números sequenciais únicos e contínuos sem empates
    ROW_NUMBER()    OVER (ORDER BY Price DESC, ProductId) AS RowNum,
    -- Divide os registros em N grupos equilibrados
    NTILE(4)        OVER (ORDER BY Price DESC) AS Quartile,
    -- Classificação resetada para cada categoria (PARTITION BY)
    RANK()          OVER (PARTITION BY CategoryId ORDER BY Price DESC) AS CategoryRank
FROM dbo.Products;
```

> [!warning] Erro Comum
> Tanto `RANK` quanto `DENSE_RANK` geram o mesmo valor classificatório em caso de empates de dados (ties). Contudo, somente `DENSE_RANK` evita lacunas sequenciais no número seguinte. Se o requisito exigir números sequenciais contínuos mesmo com empates, a resposta correta é DENSE_RANK.

### Funções de Agregação na Janela (Aggregate Window Functions)

```sql
SELECT
    OrderId,
    CustomerId,
    OrderDate,
    TotalAmount,
    -- Total acumulado (Running Total)
    SUM(TotalAmount) OVER (
        PARTITION BY CustomerId
        ORDER BY OrderDate
        ROWS UNBOUNDED PRECEDING
    ) AS RunningTotal,
    -- Média móvel (Média do registro atual + 2 anteriores)
    AVG(TotalAmount) OVER (
        PARTITION BY CustomerId
        ORDER BY OrderDate
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS MovingAvg3,
    -- Percentual do registro frente ao total consolidado do cliente
    TotalAmount / SUM(TotalAmount) OVER (PARTITION BY CustomerId) * 100 AS PctOfCustomerTotal
FROM dbo.Orders;
```

### Funções de Deslocamento (Offset Functions)

```sql
SELECT
    OrderId,
    CustomerId,
    OrderDate,
    TotalAmount,
    -- Valor contido na linha anterior (retorna 0 caso não exista)
    LAG(TotalAmount, 1, 0) OVER (PARTITION BY CustomerId ORDER BY OrderDate) AS PrevAmount,
    -- Valor contido na próxima linha (retorna 0 caso não exista)
    LEAD(TotalAmount, 1, 0) OVER (PARTITION BY CustomerId ORDER BY OrderDate) AS NextAmount,
    -- Primeiro valor absoluto da janela
    FIRST_VALUE(TotalAmount) OVER (PARTITION BY CustomerId ORDER BY OrderDate
        ROWS UNBOUNDED PRECEDING) AS FirstOrderAmount,
    -- Último valor absoluto da janela
    LAST_VALUE(TotalAmount) OVER (PARTITION BY CustomerId ORDER BY OrderDate
        ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS LastOrderAmount
FROM dbo.Orders;
```

### Especificação de Frames (Frame Specification)

```sql
-- ROWS vs RANGE:
-- ROWS: especifica um número físico exato de linhas relativo à linha atual.
-- RANGE: define limites lógicos avaliando o valor contido no ORDER BY (linhas empatadas entram juntas no cálculo).

OVER (ORDER BY Date ROWS UNBOUNDED PRECEDING) -- todas as linhas anteriores ao registro
OVER (ORDER BY Date ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) -- linha anterior, atual e posterior (±1 linha)
OVER (ORDER BY Date ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) -- da linha atual até o final da janela
OVER (PARTITION BY Dept ORDER BY Salary) -- padrão RANGE implícito de início até o atual
```

---

## PERCENT_RANK e CUME_DIST

Ambas as funções classificadoras retornam valores fracionários contidos entre 0.0 e 1.0, úteis para análise de percentis, faixas de salários ou identificação de anomalias (outliers) nos dados.

| Função | Fórmula de Cálculo | Faixa de Retorno |
| :--- | :--- | :--- |
| `PERCENT_RANK()` | (rank - 1) / (total de linhas - 1) | `0.0 (menor) a 1.0 (maior)` |
| `CUME_DIST()` | linhas com valor <= atual / total de linhas | 1/n (menor) a 1.0 (maior) |

Diferença crucial: `PERCENT_RANK` baseia-se na posição (rank) de classificação do registro; `CUME_DIST` avalia a quantidade acumulada de registros cujos valores sejam menores ou iguais ao valor da linha corrente.

```sql
SELECT EmployeeID, Name, Salary,
       PERCENT_RANK() OVER (ORDER BY Salary) AS PctRank,
       CUME_DIST() OVER (ORDER BY Salary) AS CumeDist
FROM Employees;
-- PERCENT_RANK: retorna 0.0 para o menor salário, e 1.0 para o maior
-- CUME_DIST: retorna 1.0/n para o menor, e exatamente 1.0 para o maior

-- Identificar os funcionários na faixa dos 10% maiores salários
WITH RankedSalaries AS (
    SELECT EmployeeID, Name, Salary,
           PERCENT_RANK() OVER (ORDER BY Salary) AS PctRank
    FROM Employees
)
SELECT * FROM RankedSalaries WHERE PctRank >= 0.90;
```

---

## Armadilha do FIRST_VALUE e LAST_VALUE (LAST_VALUE Pitfall)

A função `FIRST_VALUE` opera sem problemas utilizando o frame padrão do SQL Server. Porém, a função `LAST_VALUE` **não** — o frame implícito padrão adotado pelo SQL na omissão é `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, que limita a avaliação até a linha atual. Assim, `LAST_VALUE` sempre retornará o valor do próprio registro atual em vez do último registro real da janela.

Esta é uma armadilha recorrente em exames da Microsoft. Sempre declare explicitamente a definição do frame ao utilizar a função `LAST_VALUE`.

> [!important] Por que LAST_VALUE "falha" por padrão?
>
> - Por padrão, o SQL Server adota o frame `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`.
> - Para a função `LAST_VALUE`, o "último valor" dentro desse frame padrão é sempre a própria linha atual.
> - Para resolver isso, altere o frame para buscar até o fim da janela:
>   `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`

```sql
SELECT OrderID, OrderDate, TotalAmount,
       FIRST_VALUE(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS FirstOrderAmount,
       -- LAST_VALUE exige definição de frame explícito para funcionar corretamente!
       LAST_VALUE(TotalAmount) OVER (
           PARTITION BY CustomerID
           ORDER BY OrderDate
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS LastOrderAmount
FROM Orders;
```

---

## Padrões Comuns de Queries (Common Patterns)

```sql
-- Remover Duplicidades: manter apenas o registro de alteração mais recente do cliente
WITH Ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY CustomerId ORDER BY UpdatedAt DESC) AS rn
    FROM dbo.CustomerEvents
)
DELETE FROM Ranked WHERE rn > 1;

-- Maiores N por Grupo (Top N per group): trazer os 3 produtos mais vendidos por categoria
WITH Ranked AS (
    SELECT *, DENSE_RANK() OVER (PARTITION BY CategoryId ORDER BY Sales DESC) AS dr
    FROM dbo.Products
)
SELECT * FROM Ranked WHERE dr <= 3;
```

---

## Casos de Uso (Use Cases)

- **CTEs**: Simplificar queries aninhadas dividindo a lógica em passos lógicos nomeados; modelagem de hierarquias recursivas.
- **ROW_NUMBER**: Deduplicação de registros e rotinas de paginação de dados (`WHERE RowNum BETWEEN 1 AND 20`).
- **LAG/LEAD**: Análise comparativa entre períodos (ex: faturamento atual vs mês anterior) e identificação de lacunas.
- **Totalizadores Acumulados**: Soma contínua em relatórios contábeis e financeiros.
- **PERCENT_RANK / CUME_DIST**: Distribuições percentis e classificação em faixas (salary bands).

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| Recursão infinita na CTE | Falha ou ausência do filtro de parada no membro recursivo | Insira um filtro `WHERE` adequado; declare o uso de `MAXRECURSION` para segurança. |
| Total acumulado incorreto | Ausência da instrução `ROWS UNBOUNDED PRECEDING` | `O frame padrão `RANGE` agrupa linhas empatadas e calcula seus totais de uma única vez, distorcendo o acumulado`. |
| `LAST_VALUE` retorna a própria linha | O frame padrão implícito de leitura termina na linha atual | Adicione a cláusula `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`. |
| Lentidão em CTEs repetidas na query | Falta de materialização física; o código da CTE é compilado e executado múltiplas vezes | Substitua a CTE por uma tabela temporária (`#temp`) para forçar o cache físico dos dados intermediários. |

---

## Melhores Práticas (Best Practices)

- Prefira tabelas temporárias em vez de CTEs quando o resultado intermediário for referenciado repetidamente em queries que envolvam agregações ou joins pesados.
- Declare sistematicamente `ROWS` (em vez do padrão `RANGE`) em totalizadores na cláusula `OVER()` para otimizar a performance física de leitura em disco e evitar distorções de agrupamento em registros empatados.
- Forneça uma condição de encerramento segura em CTEs recursivas e defina um limite `MAXRECURSION` aderente ao tamanho estimado de níveis da sua hierarquia.
- Adote `DENSE_RANK()` no lugar de `RANK()` caso lacunas na numeração da sequência possam quebrar lógicas de leitura na sua aplicação cliente.
- Sempre use o frame `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` ao invocar a função `LAST_VALUE`.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - `RANK()` deixa lacunas após empates (1, 1, 3); `DENSE_RANK()` mantém a sequência contínua (1, 1, 2); `ROW_NUMBER()` atribui sequenciais únicos sem empates.
> - O frame padrão implícito do SQL Server é `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` — declare `ROWS` explicitamente para evitar processamentos de empates.
> - CTEs recursivas exigem a definição de um membro âncora (anchor) e de um membro recursivo vinculados via `UNION ALL`.
> - CTEs **não geram materialização física** — múltiplas referências reexecutam o código.
> - Sem frame explícito, a função `LAST_VALUE` retorna a linha atual.
> - `PERCENT_RANK` retorna 0.0 para o primeiro registro; `CUME_DIST` nunca retorna 0.0.
> - O hint `OPTION(MAXRECURSION 0)` desliga o limite máximo de recursão — perigoso caso ocorra loops infinitos.

---

## Resumo dos Conceitos (Key Takeaways)

- As CTEs trazem legibilidade e organização, mas não trazem ganhos nativos de performance de leitura por si só.
- As Window Functions computam valores agregados sem reduzir a volumetria das linhas projetadas no SELECT.
- A cláusula `PARTITION BY` nas Window Functions independe da presença de agrupamentos físicos por `GROUP BY`.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma CTE contendo uma agregação complexa e custosa é referenciada duas vezes na mesma query. A execução geral da query apresenta lentidão severa. Qual é a causa MAIS PROVÁVEL deste comportamento?

A. As CTEs não suportam o uso de funções agregadoras em sua definição.

B. A lógica interna da CTE é executada duas vezes físicas pelo motor de banco, pois as CTEs não sofrem materialização por padrão.

C. O emprego de Window Functions dentro de CTEs bloqueia a execução paralela de queries.

D. O SQL Server limita a volumetria de retorno de CTEs a exatamente 100 linhas por padrão.

> [!success]- Resposta
> **B — A lógica interna da CTE é executada duas vezes físicas pelo motor de banco, pois as CTEs não sofrem materialização por padrão.**
>
> As CTEs no SQL Server funcionam apenas como expansões inline lógicas de consulta (como Views), sem cache ou gravação física padrão. Chamar a CTE duas vezes força o otimizador a recompilar e processar o bloco agregador repetidamente. Empregar uma tabela temporária `#temp` soluciona o gargalo materializando a etapa intermediária. A opção D está incorreta (o limite de 100 se refere apenas à profundidade máxima de recursão em CTEs recursivas).

---

## Tópicos Relacionados

- [02-JSON Functions](./02-json-functions.md) *(Inglês apenas)*
- [05-Correlated Queries & Error Handling](./05-correlated-queries-error-handling.md) *(Inglês apenas)*

---

## Documentação Oficial

- [WITH common_table_expression (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/queries/with-common-table-expression-transact-sql)
- [Window Functions (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-over-clause-transact-sql)

---

**[↑ Voltar para a Seção](./advanced-tsql.md) | [Próximo →](./02-json-functions.md)**
