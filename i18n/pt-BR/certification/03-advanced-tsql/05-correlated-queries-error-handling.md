---
title: Correlated Queries and Error Handling
type: study-material
tags:
  - dp-800
  - correlated-subquery
  - error-handling
  - try-catch
  - throw
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Subconsultas Correlacionadas & Operadores](#subconsultas-correlacionadas-correlated-subqueries)
>   - 🔹 [EXISTS / NOT EXISTS](#exists--not-exists)
>   - 🔹 [Subconsultas Escalares, IN / NOT IN](#subconsulta-correlacionada-escalar-scalar-correlated-subquery)
>   - 🔹 [UPDATE & DELETE Correlacionados](#update-e-delete-correlacionados-correlated-update--delete)
>   - 🔹 [Operadores APPLY (CROSS / OUTER APPLY)](#operadores-apply-apply-operators)
> - 📍 [3. Tratamento de Erros & Gestão Transacional](#tratamento-de-erros-com-trycatch-error-handling-with-trycatch)
>   - 🔹 [Tratamento de Erros com TRY/CATCH](#tratamento-de-erros-com-trycatch-error-handling-with-trycatch)
>   - 🔹 [THROW vs RAISERROR](#throw-vs-raiserror)
>   - 🔹 [Códigos de Erro Personalizados](#codigos-de-erros-personalizados-custom-error-numbers)
>   - 🔹 [TRY_PARSE & TRY_CONVERT](#try_parse-e-try_convert)
>   - 🔹 [Diretiva XACT_ABORT & Gestão Transacional Avançada](#diretiva-xact_abort-e-comportamentos-de-transacoes)
> - 📍 [4. Aplicação Prática & Síntese](#casos-de-uso-use-cases)
>   - 🔹 [Casos de Uso](#casos-de-uso-use-cases)
>   - 🔹 [Problemas Comuns, Práticas & Exam Tips](#problemas-comuns-e-solucoes-common-issues)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)

---

# Correlated Queries and Error Handling

## Visão Geral (Overview)

As subconsultas correlacionadas (correlated subqueries) fazem referência direta às colunas da consulta externa (outer query) e são avaliadas uma vez para cada linha processada por ela. O tratamento de erros estruturado com os blocos `TRY/CATCH` e o comando `THROW` fornece um mecanismo de gestão de exceções robusto e comparável aos blocos equivalentes de linguagens de programação de alto nível.

> [!abstract]
>
> - Cobre subconsultas correlacionadas, `EXISTS`/`NOT EXISTS`, tratamento de erros com `TRY/CATCH`, `THROW` vs `RAISERROR` e estados de transação.
> - As subconsultas correlacionadas dependem da consulta externa. `EXISTS`, `IN`, junções e `APPLY` podem resultar em planos equivalentes; escolha a forma semântica adequada e valide o plano para dados reais.
> - Tópicos chave do exame: retornos e interpretações da função `XACT_STATE()`, diferenças de comportamento entre `THROW` vs `RAISERROR` e funções auxiliares `ERROR_*` no bloco `CATCH`.

> [!tip] O que o Exame Testa
>
> - `XACT_STATE()
>   - `-1` = transação ativa corrompida e não confirmável (uncommittable transaction), exigindo a execução obrigatória de `ROLLBACK`;
>   - `1` = transação ativa confirmável; 
>   - `0` = ausência de transações ativas.
> - A instrução `THROW` propaga exceções de volta preservando os metadados, gravidade e código originais; o comando `RAISERROR` cria novos códigos personalizados permitindo configurar a gravidade (severity).
> - `EXISTS` expressa teste de existência e evita a semântica problemática de `NOT IN` quando a subconsulta pode retornar `NULL`. Não há garantia de que seja sempre mais rápido que `IN`.

---

## Subconsultas Correlacionadas (Correlated Subqueries)

Uma subconsulta correlacionada faz referência a colunas declaradas na consulta externa (outer query) — impossibilitando sua execução de forma isolada.

### EXISTS / NOT EXISTS

```sql
-- Localizar clientes que realizaram pelo menos um pedido
SELECT c.CustomerId, c.Name
FROM dbo.Customers c
WHERE EXISTS (
    SELECT 1 FROM dbo.Orders o
    WHERE o.CustomerId = c.CustomerId -- correlação: faz referência a 'c' da query externa
);

-- Localizar clientes que NUNCA realizaram pedidos
SELECT c.CustomerId, c.Name
FROM dbo.Customers c
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Orders o
    WHERE o.CustomerId = c.CustomerId
);
```

> [!tip] Dica de Performance: EXISTS vs IN
>
> - **EXISTS**: Utiliza avaliação de curto-circuito (short-circuit). Assim que o SQL Server encontra a primeira linha correspondente na subquery, ele interrompe a busca para aquela linha da query externa.
> - **IN**: Compara individualmente contra todos os valores retornados pela subquery. Se a subquery puder retornar valores `NULL`, o uso de `NOT IN` retornará zero linhas de forma incorreta porque a comparação `Value != NULL` resulta em `UNKNOWN`.

### Subconsulta Correlacionada Escalar (Scalar Correlated Subquery)

```sql
-- Trazer o valor da compra mais recente de cada cliente
SELECT
    c.CustomerId,
    c.Name,
    (SELECT TOP 1 o.TotalAmount
     FROM dbo.Orders o
     WHERE o.CustomerId = c.CustomerId
     ORDER BY o.OrderDate DESC) AS LastOrderAmount
FROM dbo.Customers c;
```

Uma alternativa sem subconsulta correlacionada é classificar os pedidos em uma CTE e manter apenas o primeiro de cada cliente:

```sql
WITH RankedOrders AS (
    SELECT
        o.CustomerId,
        o.TotalAmount,
        ROW_NUMBER() OVER (
            PARTITION BY o.CustomerId
            ORDER BY o.OrderDate DESC
        ) AS OrderRank
    FROM dbo.Orders AS o
)
SELECT
    c.CustomerId,
    c.Name,
    ro.TotalAmount AS LastOrderAmount
FROM dbo.Customers AS c
LEFT JOIN RankedOrders AS ro
    ON ro.CustomerId = c.CustomerId
   AND ro.OrderRank = 1;
```

O `LEFT JOIN` mantém clientes sem pedidos e retorna `NULL` em `LastOrderAmount`, assim como a subconsulta escalar original.

### IN / NOT IN com Subconsultas (IN / NOT IN with Subquery)

```sql
-- Produtos cujas categorias possuam mais de 100 itens cadastrados
SELECT ProductId, Name
FROM dbo.Products
WHERE CategoryId IN (
    SELECT CategoryId FROM dbo.Products
    GROUP BY CategoryId
    HAVING COUNT(*) > 100
);
```

A mesma filtragem pode ser expressa com uma CTE e um `JOIN`, deixando a lista de categorias elegíveis explícita:

```sql
WITH LargeCategories AS (
    SELECT CategoryId
    FROM dbo.Products
    GROUP BY CategoryId
    HAVING COUNT(*) > 100
)
SELECT
    p.ProductId,
    p.Name
FROM dbo.Products AS p
INNER JOIN LargeCategories AS lc
    ON lc.CategoryId = p.CategoryId;
```

### UPDATE e DELETE Correlacionados (Correlated UPDATE / DELETE)

```sql
-- Atualizar o total da tabela pai Orders a partir do somatório de itens filhos OrderItems
UPDATE o
SET o.TotalAmount = (
    SELECT SUM(oi.Quantity * oi.UnitPrice)
    FROM dbo.OrderItems oi
    WHERE oi.OrderId = o.OrderId
)
FROM dbo.Orders o;

-- Limpar registros órfãos da tabela OrderItems (sem Orders correspondente)
DELETE oi
FROM dbo.OrderItems oi
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Orders o
    WHERE o.OrderId = oi.OrderId
);
```

As mesmas operações podem ser escritas sem subconsultas correlacionadas. Essa forma separa o cálculo dos totais da atualização e torna explícito o `JOIN` usado para localizar cada registro:

```sql
-- Alternativa ao UPDATE correlacionado: calcular os totais uma única vez e fazer JOIN
WITH OrderTotals AS (
    SELECT
        OrderId,
        SUM(Quantity * UnitPrice) AS TotalAmount
    FROM dbo.OrderItems
    GROUP BY OrderId
)
UPDATE o
SET o.TotalAmount = ot.TotalAmount
FROM dbo.Orders AS o
LEFT JOIN OrderTotals AS ot
    ON ot.OrderId = o.OrderId;

-- Alternativa ao DELETE com NOT EXISTS: localizar órfãos com LEFT JOIN
DELETE oi
FROM dbo.OrderItems AS oi
LEFT JOIN dbo.Orders AS o
    ON o.OrderId = oi.OrderId
WHERE o.OrderId IS NULL;
```

O `LEFT JOIN` mantém também os pedidos sem itens, cujo total ficará `NULL`, como na consulta correlacionada original. Para gravar zero nesses casos, use `COALESCE(ot.TotalAmount, 0)`.

### Operadores APPLY (APPLY Operators)

Os operadores `CROSS APPLY` e `OUTER APPLY` representam alternativas muito poderosas às subconsultas correlacionadas:

```sql
-- CROSS APPLY: semelhança com INNER JOIN (linhas sem correspondência na TVF são descartadas)
SELECT c.Name, recent.OrderId, recent.OrderDate
FROM dbo.Customers c
CROSS APPLY (
    SELECT TOP 3 OrderId, OrderDate
    FROM dbo.Orders
    WHERE CustomerId = c.CustomerId
    ORDER BY OrderDate DESC
) AS recent;

-- OUTER APPLY: semelhança com LEFT JOIN (linhas sem correspondência retornam NULL nas colunas da direita)
SELECT c.Name, last_order.OrderDate
FROM dbo.Customers c
OUTER APPLY (
    SELECT TOP 1 OrderDate
    FROM dbo.Orders
    WHERE CustomerId = c.CustomerId
    ORDER BY OrderDate DESC
) AS last_order;
```

As mesmas consultas também podem ser escritas com uma CTE e a função de janela `ROW_NUMBER()`. Essa abordagem é útil quando se deseja classificar todas as linhas primeiro e depois filtrá-las com um `JOIN`:

```sql
-- Alternativa ao CROSS APPLY: INNER JOIN mantém apenas clientes com pedidos
WITH RankedOrders AS (
    SELECT
        o.CustomerId,
        o.OrderId,
        o.OrderDate,
        ROW_NUMBER() OVER (
            PARTITION BY o.CustomerId
            ORDER BY o.OrderDate DESC
        ) AS OrderRank
    FROM dbo.Orders AS o
)
SELECT
    c.Name,
    ro.OrderId,
    ro.OrderDate
FROM dbo.Customers AS c
INNER JOIN RankedOrders AS ro
    ON ro.CustomerId = c.CustomerId
   AND ro.OrderRank <= 3;

-- Alternativa ao OUTER APPLY: LEFT JOIN mantém clientes sem pedidos
WITH RankedOrders AS (
    SELECT
        o.CustomerId,
        o.OrderDate,
        ROW_NUMBER() OVER (
            PARTITION BY o.CustomerId
            ORDER BY o.OrderDate DESC
        ) AS OrderRank
    FROM dbo.Orders AS o
)
SELECT
    c.Name,
    ro.OrderDate
FROM dbo.Customers AS c
LEFT JOIN RankedOrders AS ro
    ON ro.CustomerId = c.CustomerId
   AND ro.OrderRank = 1;
```

O `INNER JOIN` reproduz o comportamento do `CROSS APPLY`, enquanto o `LEFT JOIN` reproduz o comportamento do `OUTER APPLY`.

> [!warning] Erro Comum
> Nem todos os erros do banco são capturáveis por blocos `TRY/CATCH` — erros com gravidade (severity) de 20 ou superior (erros fatais que encerram a conexão de rede com o banco) e erros de sintaxe ou compilação de código ignoram e contornam o bloco `CATCH`. Sempre valide o retorno de `XACT_STATE()` antes de invocar `COMMIT` ou `ROLLBACK` de dentro do CATCH; tentar executar commit com `XACT_STATE() = -1` gerará nova falha no banco de dados.

---

## Tratamento de Erros com TRY/CATCH (Error Handling with TRY/CATCH)

```sql
BEGIN TRY
    -- Código sujeito a falhas de execução
    BEGIN TRANSACTION;

    INSERT INTO dbo.Accounts (AccountId, Balance) VALUES (1, 1000);
    UPDATE dbo.Accounts SET Balance = Balance - 500 WHERE AccountId = 1;

    IF (SELECT Balance FROM dbo.Accounts WHERE AccountId = 1) < 0
        THROW 50001, 'Saldo insuficiente para a operação.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    -- Registrar a falha na tabela de log
    INSERT INTO dbo.ErrorLog (
        ErrorNumber, ErrorMessage, ErrorSeverity,
        ErrorProcedure, ErrorLine, OccurredAt
    )
    VALUES (
        ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_SEVERITY(),
        ERROR_PROCEDURE(), ERROR_LINE(), GETUTCDATE()
    );

    -- Repassar o erro de volta ao chamador (re-throw)
    THROW;
END CATCH;
```

---

## THROW vs RAISERROR

```sql
-- THROW: propaga o erro de sistema original preservando os detalhes (Recomendado)
THROW; -- Re-throw: re-disparar o erro original (apenas dentro do CATCH)
THROW 50001, 'Mensagem customizada.', 1; -- Novo erro: id_erro, mensagem, estado

-- RAISERROR: abordagem de sintaxe legada
RAISERROR ('Mensagem de falha', 16, 1); -- gravidade 16 = erro comum de usuário
RAISERROR ('Valor incorreto: %d', 16, 1, @MyVariable); -- suporta parâmetros formatados
```

> [!important] Por que preferir THROW a RAISERROR?
>
> - **THROW** é mais simples, pois não requer que você configure os parâmetros de severidade e estado toda vez se for re-disparar um erro.
> - Além disso, o comando `THROW` respeita o comando `SET XACT_ABORT ON` e interrompe imediatamente a execução do lote de comandos, enquanto o `RAISERROR` pode continuar executando linhas subsequentes dependendo da severidade configurada.

**Quadro Comparativo: THROW vs RAISERROR:**

| Funcionalidade | THROW | RAISERROR |
| :--- | :--- | :--- |
| Gravidade (Severity) | Sempre fixado em 16 | Escala de 1 a 25 (definida pelo usuário) |
| Re-propagar (Re-throw) | `THROW;` simples (sem argumentos) | Obriga re-declarar todos os parâmetros |
| Uso dentro de CATCH | Sim (re-propaga) | Sim |
| Interrupção do Lote | Sim (sob a diretiva XACT_ABORT) | Varia conforme o nível de gravidade |
| Faixa de Código do Erro | Novo erro deve usar número entre 50000 e 2147483647 | Pode referenciar uma mensagem registrada ou uma string |
| Preservar erro original | `THROW;` preserva os detalhes originais | Exige recriar a mensagem e os parâmetros |
| Parâmetros de Entrada | Não suporta formatação de strings | Formatação no estilo printf do C |
| Recomendação de Uso | **Código moderno (SQL Server 2012+)** | Sintaxe legada |

Padrão de re-propagar erros (re-throw pattern) usando `THROW` sem argumentos de entrada:

```sql
BEGIN TRY
    EXEC dbo.SomeRiskyProcedure;
END TRY
BEGIN CATCH
    -- Registrar a ocorrência
    INSERT INTO ErrorLog (Message, Severity, ErrorTime)
    VALUES (ERROR_MESSAGE(), ERROR_SEVERITY(), GETUTCDATE());

    -- Disparar novamente a falha original (THROW sem argumentos)
    THROW;
END CATCH;
```

---

## Códigos de Erros Personalizados (Custom Error Numbers)

Erros customizados definidos pelo usuário devem possuir ID maior que 50000:

```sql
-- Registrar a mensagem no catálogo do banco (sys.messages)
EXEC sp_addmessage 50001, 16, 'O saldo da conta corrente não pode ser negativo.';

-- Invocar o erro registrado pelo seu respectivo ID usando RAISERROR
RAISERROR (50001, 16, 1);
```

---

## TRY_PARSE e TRY_CONVERT

As funções seguras de conversão de tipos retornam `NULL` em caso de falha de parsing ou cast em vez de disparar uma exceção de erro — ideais para higienizar dados de entrada sem gerar overhead de tratamento com try/catch.

- **TRY_CONVERT(tipo, expressao)** — retorna NULL caso a conversão de tipo falhe.
- **TRY_CAST(expressao AS tipo)** — comportamento idêntico ao `TRY_CONVERT` adotando sintaxe ANSI.
- **TRY_PARSE(expressao AS tipo USING cultura)** — realiza parsing de texto para data ou números sensíveis à localidade (locale-aware); retorna NULL caso falhe.

```sql
-- TRY_CONVERT: conversão de tipos protegida
SELECT TRY_CONVERT(INT, '123'),          -- 123
       TRY_CONVERT(INT, 'abc'),          -- NULL (sem falhas de query)
       TRY_CONVERT(DATE, '2024-13-01'),  -- NULL (mês inválido)
       TRY_CONVERT(DATE, '2024-06-15');  -- 2024-06-15

-- TRY_PARSE: parsing com base em padrões geográficos de formatação (Cultura)
SELECT TRY_PARSE('June 15, 2024' AS DATE USING 'en-US'), -- 2024-06-15
       TRY_PARSE('15/06/2024' AS DATE USING 'fr-FR');     -- 2024-06-15

-- Filtrar linhas contendo exclusivamente formatos válidos de datas
SELECT * FROM StagingImport
WHERE TRY_CONVERT(DATE, EventDateStr) IS NOT NULL;
```

---

## Diretiva XACT_ABORT e Comportamentos de Transações

O comando `SET XACT_ABORT ON` configura o banco para que qualquer erro em tempo de execução force o rollback imediato e completo de toda a transação ativa. O comportamento padrão (`XACT_ABORT OFF`) faz o rollback apenas do comando específico que falhou, podendo manter trechos da transação abertos e inconsistentes de forma imperfeita.

- **Uso Crítico**: Fundamental em Stored Procedures consumidas por sistemas externos; garante atomicidade e integridade relacional.
- **Interação com blocos TRY/CATCH**: sob a ativação de `XACT_ABORT ON`, o bloco `CATCH` ainda é invocado permitindo logar a falha, porém a transação ativa é classificada como perdida (`XACT_STATE() = -1`), sendo impossível executar o commit.

**Códigos de retorno da função XACT_STATE():**

| Valor | Significado Clínico |
| :--- | :--- |
| `1` | Transação ativa e saudável (confirmável / committable). |
| `-1` | `Transação ativa corrompida (perdida) — o ROLLBACK é obrigatório`. |
| `0` | Sem transações ativas no momento da execução. |

> [!warning] O que fazer quando XACT_STATE() = -1?
>
> - Quando o `XACT_STATE()` retorna `-1`, a transação está ativa, mas corrompida.
> - Você **não pode confirmar (COMMIT)** nenhuma alteração realizada nesta transação.
> - Qualquer tentativa de rodar `COMMIT TRANSACTION` sob este estado falhará e lançará um erro severo. A única operação permitida é o `ROLLBACK TRANSACTION`.

```sql
-- Forçar rollback completo em qualquer falha de instrução
SET XACT_ABORT ON;
BEGIN TRANSACTION;
    INSERT INTO Orders VALUES (1, 100.00);
    INSERT INTO OrderItems VALUES (99999, 'A1', 1); -- Falha de chave estrangeira (FK)
    -- Com XACT_ABORT ON: desfaz toda a transação
    -- Sem XACT_ABORT: apenas o item falha, o cabeçalho Orders é persistido de forma órfã
COMMIT;

-- Uso do XACT_STATE no bloco CATCH
BEGIN TRY
    BEGIN TRANSACTION;
    -- ... operações ...
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() = -1 -- transação corrompida perdida
        ROLLBACK TRANSACTION;
    ELSE IF XACT_STATE() = 1 -- transação ativa saudável
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
```

---

## Gestão Avançada de Transações no Tratamento de Erros

```sql
CREATE PROCEDURE dbo.usp_SafeOperation
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TranCount int = @@TRANCOUNT;

    -- Se já existir transação aberta do chamador externo, abrir um savepoint interno
    IF @TranCount > 0
        SAVE TRANSACTION MySavepoint;
    ELSE
        BEGIN TRANSACTION;

    BEGIN TRY
        -- lógica de escrita aqui
        IF @TranCount = 0
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        -- Em caso de erro, desfazer apenas até o savepoint local ou realizar rollback completo
        IF @TranCount > 0
            ROLLBACK TRANSACTION MySavepoint; -- desfaz apenas a etapa local
        ELSE
            ROLLBACK TRANSACTION; -- desfaz tudo

        THROW;
    END CATCH;
END;
GO
```

---

## Casos de Uso (Use Cases)

- **EXISTS/NOT EXISTS**: Validações de presença ou ausência de dados de relacionamentos; geralmente mais rápidos do que usar `IN` (que lida de forma complexa na presença de nulos).
- **CROSS/OUTER APPLY**: Consultar Top N por categoria, ou interagir de forma parametrizada com TVFs para cada linha.
- **TRY/CATCH + THROW**: Implementação em Stored Procedures transacionais contendo comandos DML.
- **TRY_CONVERT/TRY_PARSE**: Validação estrutural de tipos e dados em cargas de tabelas de staging para evitar abortos abruptos em tempo de execução.

---

## Laboratório Prático: Consultas Alternativas (Hands-on Lab)

Execute o script de preparação uma vez em uma mesma sessão e, em seguida, compare cada consulta original com sua alternativa. As tabelas temporárias são usadas para que o laboratório não altere dados permanentes:

> Para comparar as duas formas de `UPDATE` ou `DELETE`, execute o script de preparação novamente antes da segunda forma, pois essas instruções alteram os dados temporários.

```sql
DROP TABLE IF EXISTS #OrderItems;
DROP TABLE IF EXISTS #Orders;
DROP TABLE IF EXISTS #Customers;
DROP TABLE IF EXISTS #Products;

CREATE TABLE #Customers (
    CustomerId int PRIMARY KEY,
    Name       varchar(50) NOT NULL
);

CREATE TABLE #Orders (
    OrderId     int PRIMARY KEY,
    CustomerId  int NOT NULL,
    OrderDate   date NOT NULL,
    TotalAmount decimal(10, 2) NULL
);

CREATE TABLE #OrderItems (
    OrderId  int NOT NULL,
    ProductId int NOT NULL,
    Quantity int NOT NULL,
    UnitPrice decimal(10, 2) NOT NULL
);

CREATE TABLE #Products (
    ProductId int IDENTITY PRIMARY KEY,
    Name      varchar(50) NOT NULL,
    CategoryId int NOT NULL
);

INSERT INTO #Customers VALUES
    (1, 'Alice'), (2, 'Bruno'), (3, 'Carla');

INSERT INTO #Orders (OrderId, CustomerId, OrderDate, TotalAmount) VALUES
    (101, 1, '2026-01-10', 20.00),
    (102, 1, '2026-02-15', 25.00),
    (103, 2, '2026-01-20', 15.00);

INSERT INTO #OrderItems VALUES
    (101, 1, 2, 10.00),
    (102, 2, 1, 25.00),
    (103, 3, 3, 5.00),
    (999, 4, 1, 99.00); -- item órfão para o teste do DELETE

INSERT INTO #Products (Name, CategoryId)
VALUES ('Produto avulso', 2);

;WITH Numbers AS (
    SELECT TOP (101)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Number
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
)
INSERT INTO #Products (Name, CategoryId)
SELECT CONCAT('Produto ', Number), 1
FROM Numbers;
```

### 1. Último pedido por cliente

```sql
-- Forma correlacionada
SELECT c.CustomerId, c.Name,
       (SELECT TOP 1 o.TotalAmount
        FROM #Orders AS o
        WHERE o.CustomerId = c.CustomerId
        ORDER BY o.OrderDate DESC) AS LastOrderAmount
FROM #Customers AS c;

-- Alternativa com ROW_NUMBER e LEFT JOIN
WITH RankedOrders AS (
    SELECT o.CustomerId, o.TotalAmount,
           ROW_NUMBER() OVER (
               PARTITION BY o.CustomerId ORDER BY o.OrderDate DESC
           ) AS OrderRank
    FROM #Orders AS o
)
SELECT c.CustomerId, c.Name, ro.TotalAmount AS LastOrderAmount
FROM #Customers AS c
LEFT JOIN RankedOrders AS ro
    ON ro.CustomerId = c.CustomerId AND ro.OrderRank = 1;
```

### 2. Categorias com mais de 100 produtos

```sql
-- Forma com IN
SELECT ProductId, Name
FROM #Products
WHERE CategoryId IN (
    SELECT CategoryId
    FROM #Products
    GROUP BY CategoryId
    HAVING COUNT(*) > 100
);

-- Alternativa com CTE e INNER JOIN
WITH LargeCategories AS (
    SELECT CategoryId
    FROM #Products
    GROUP BY CategoryId
    HAVING COUNT(*) > 100
)
SELECT p.ProductId, p.Name
FROM #Products AS p
INNER JOIN LargeCategories AS lc
    ON lc.CategoryId = p.CategoryId;
```

### 3. UPDATE e DELETE sem subconsulta correlacionada

```sql
-- Forma correlacionada: atualizar os totais
UPDATE o
SET o.TotalAmount = (
    SELECT SUM(oi.Quantity * oi.UnitPrice)
    FROM #OrderItems AS oi
    WHERE oi.OrderId = o.OrderId
)
FROM #Orders AS o;

-- Atualizar totais com CTE e LEFT JOIN
WITH OrderTotals AS (
    SELECT OrderId, SUM(Quantity * UnitPrice) AS TotalAmount
    FROM #OrderItems
    GROUP BY OrderId
)
UPDATE o
SET o.TotalAmount = ot.TotalAmount
FROM #Orders AS o
LEFT JOIN OrderTotals AS ot ON ot.OrderId = o.OrderId;

SELECT * FROM #Orders;

-- Forma correlacionada: remover órfãos
DELETE oi
FROM #OrderItems AS oi
WHERE NOT EXISTS (
    SELECT 1
    FROM #Orders AS o
    WHERE o.OrderId = oi.OrderId
);

-- Remover órfãos com LEFT JOIN
DELETE oi
FROM #OrderItems AS oi
LEFT JOIN #Orders AS o ON o.OrderId = oi.OrderId
WHERE o.OrderId IS NULL;
```

### 4. CROSS APPLY e OUTER APPLY

```sql
-- Formas originais com APPLY
SELECT c.Name, recent.OrderId, recent.OrderDate
FROM #Customers AS c
CROSS APPLY (
    SELECT TOP 3 OrderId, OrderDate
    FROM #Orders
    WHERE CustomerId = c.CustomerId
    ORDER BY OrderDate DESC
) AS recent;

SELECT c.Name, last_order.OrderDate
FROM #Customers AS c
OUTER APPLY (
    SELECT TOP 1 OrderDate
    FROM #Orders
    WHERE CustomerId = c.CustomerId
    ORDER BY OrderDate DESC
) AS last_order;

-- Alternativa ao CROSS APPLY: INNER JOIN mantém apenas clientes com pedidos
WITH RankedOrders AS (
    SELECT o.CustomerId, o.OrderId, o.OrderDate,
           ROW_NUMBER() OVER (
               PARTITION BY o.CustomerId ORDER BY o.OrderDate DESC
           ) AS OrderRank
    FROM #Orders AS o
)
SELECT c.Name, ro.OrderId, ro.OrderDate
FROM #Customers AS c
INNER JOIN RankedOrders AS ro
    ON ro.CustomerId = c.CustomerId AND ro.OrderRank <= 3;

-- Alternativa ao OUTER APPLY: LEFT JOIN mantém clientes sem pedidos
WITH RankedOrders AS (
    SELECT o.CustomerId, o.OrderDate,
           ROW_NUMBER() OVER (
               PARTITION BY o.CustomerId ORDER BY o.OrderDate DESC
           ) AS OrderRank
    FROM #Orders AS o
)
SELECT c.Name, ro.OrderDate
FROM #Customers AS c
LEFT JOIN RankedOrders AS ro
    ON ro.CustomerId = c.CustomerId AND ro.OrderRank = 1;
```

Compare também essas consultas com as versões `CROSS APPLY` e `OUTER APPLY` apresentadas anteriormente. Os resultados devem ser equivalentes, respeitando a diferença entre `INNER JOIN` e `LEFT JOIN`.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| O operador `NOT IN` não retorna nenhuma linha | A subconsulta de retorno trouxe ao menos um registro contendo valor `NULL` | `Substitua a cláusula por `NOT EXISTS` (que gerencia nulos corretamente)`. |
| O bloco `CATCH` não intercepta o erro | Falhas com gravidade abaixo de 11, ou erros de compilação/sintaxe física do script | O `TRY/CATCH` atua apenas em erros de tempo de execução (runtime) com gravidade maior ou igual a 11. |
| Erro de sintaxe ao invocar a instrução `THROW` | Uso do comando `THROW` sem argumentos fora de blocos `CATCH` | O comando `THROW;` puro (sem parâmetros de erro) só é permitido dentro de blocos `CATCH` para fins de re-disparo. |
| Transações parciais ativas após erros lógicos | O parâmetro implícito do banco `XACT_ABORT` está configurado como `OFF` (padrão) | Declare explicitamente a instrução `SET XACT_ABORT ON` no cabeçalho das Stored Procedures. |
| Falha ao tentar fechar transação no CATCH | Tentativa de rodar `COMMIT` em transação corrompida | Verifique o valor de `XACT_STATE()`; se for igual a `-1`, a única saída válida aceita pelo banco é o `ROLLBACK`. |

---

## Melhores Práticas (Best Practices)

- Defina `SET XACT_ABORT ON` no início de Stored Procedures que iniciam transações lógicas para certificar-se de que falhas físicas forcem rollbacks automáticos do escopo todo.
- Valide sistematicamente o valor de `XACT_STATE()` no bloco `CATCH` para tomar decisões de integridade física.
- Prefira a instrução `THROW` em detrimento a `RAISERROR` em novas implementações T-SQL; a cláusula `THROW;` preserva todos os dados do erro de sistema de origem de forma limpa.
- Utilize `TRY_CONVERT` ou `TRY_PARSE` para higienizações rápidas de dados textuais importados de staging, contornando a necessidade de overhead de código com blocos try/catch.
- Adote o operador `NOT EXISTS` no lugar de `NOT IN` para evitar o comportamento nulo do SQL de invalidar retornos de joins quando a subquery trouxer nulos.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - O operador `NOT EXISTS` é a recomendação padrão de desempenho em relação a `NOT IN` em subqueries com presença de nulos.
> - As diretivas `CROSS APPLY` e `OUTER APPLY` correlacionam dados row-by-row de forma semelhante a `INNER JOIN` e `LEFT JOIN` lógicos, respectivamente.
> - Invocado dentro do bloco `CATCH`, o comando `THROW;` (sem argumentos) propaga a exceção original sem alterar o código do erro, número da linha e gravidade.
> - A leitura de `@@TRANCOUNT > 0` identifica que o código está executando de dentro de uma transação aberta anteriormente por um chamador externo.
> - `XACT_STATE() = -1` indica transação perdida que não aceita commits lógicos no banco de dados.
> - `SET XACT_ABORT ON` garante reversão total de transações em erros, evitando transações parciais (partial commits) inconsistentes.

---

## Resumo dos Conceitos (Key Takeaways)

- Subconsultas correlacionadas dependem do contexto de linhas da consulta externa.
- `TRY/CATCH` isola e captura de forma limpa exceções e falhas com severidade (severity) maior ou igual a 11.
- `TRY_CONVERT` e `TRY_PARSE` evitam estouros de consultas retornando NULL lógicos em dados textuais de formato incorreto.
- A função `XACT_STATE()` determina de forma segura a saúde e o destino aceito de transações ativas em tratamentos de exceção.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma Stored Procedure contendo transações lógicas é executada sem a diretiva `SET XACT_ABORT ON`. Ocorre uma falha de violação de chave estrangeira no segundo comando de inserção de um lote composto por três INSERTs. Qual será o estado físico da transação quando o fluxo de processamento atingir o bloco `CATCH`?

A. Toda a transação e inserções foram automaticamente desfeitas (rolled back) pelo banco.

B. Somente a segunda inserção (que falhou) sofreu rollback; a primeira inserção continua aberta e pendente na transação de forma ativa.

C. Todas as três inserções do lote sofrem rollback por padrão.

D. A transação inteira é confirmada (committed) até a linha anterior ao erro de violação.

> [!success]- Resposta
> **B — Somente a segunda inserção (que falhou) sofreu rollback; a primeira inserção continua aberta e pendente na transação de forma ativa.**
>
> Por padrão (com `XACT_ABORT OFF`), o SQL Server realiza rollbacks apenas em nível de instrução (statement-level rollback). Desse modo, o erro no segundo INSERT desfaz apenas a si mesmo, mantendo a transação ativa e a primeira inserção pendente de confirmação. Se o bloco `CATCH` não executar um `ROLLBACK` explícito, a primeira inserção pode ser indevidamente gravada ou mantida travando registros em produção. O uso de `SET XACT_ABORT ON` altera essa lógica desfazendo a transação inteira na ocorrência de qualquer falha (Opção A).

---

## Tópicos Relacionados

- [03-Stored Procedures](../02-programmability-objects/03-stored-procedures.md)
- [01-CTEs & Window Functions](./01-ctes-window-functions.md)

---

## Documentação Oficial

- [TRY...CATCH (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/try-catch-transact-sql)
- [THROW (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/throw-transact-sql)
- [Subquery Fundamentals](https://learn.microsoft.com/en-us/sql/relational-databases/performance/subqueries)
- [TRY_CONVERT (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/try-convert-transact-sql)
- [SET XACT_ABORT (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-xact-abort-transact-sql)

---

**[← Anterior](./04-graph-queries.md) | [↑ Voltar para a Seção](./advanced-tsql.md) | [Lab: Correlated Queries e Error Handling](../../practice/labs/03-advanced-tsql/05-correlated-queries-error-handling-lab.sql)**
