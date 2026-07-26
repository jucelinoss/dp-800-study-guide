---
title: Scalar and Table-Valued Functions
type: study-material
tags:
  - dp-800
  - functions
  - scalar-functions
  - table-valued-functions
  - tvf
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Tipos de User-Defined Functions (UDFs)](#funcoes-escalares-scalar-functions)
>   - 🔹 [Funções Escalares (Scalar Functions)](#funcoes-escalares-scalar-functions)
>   - 🔹 [Inline Table-Valued Functions (iTVF)](#inline-table-valued-functions-itvf)
>   - 🔹 [Multi-Statement Table-Valued Functions (mTVF)](#multi-statement-table-valued-functions-mtvf)
>   - 🔹 [Comparativo de Funções](#comparativo-de-funcoes-function-comparison)
> - 📍 [3. Desempenho & Otimização de UDFs](#inlining-de-scalar-udfs-scalar-udf-inlining)
>   - 🔹 [Inlining de Scalar UDFs](#inlining-de-scalar-udfs-scalar-udf-inlining)
>   - 🔹 [Desempenho: Inline vs Multi-Statement TVF](#desempenho-inline-vs-multi-statement-tvf)
>   - 🔹 [Operador APPLY com Table-Valued Functions](#operador-apply-com-table-valued-functions)
>   - 🔹 [Determinismo & SCHEMABINDING](#determinismo-de-funcoes-function-determinism)
> - 📍 [4. Aplicação Prática & Síntese](#casos-de-uso-use-cases)
>   - 🔹 [Casos de Uso](#casos-de-uso-use-cases)
>   - 🔹 [Problemas Comuns e Soluções](#problemas-comuns-e-solucoes-common-issues)
>   - 🔹 [Melhores Práticas](#melhores-praticas-best-practices)
>   - 🔹 [Dicas para o Exame](#dicas-para-o-exame-exam-tips)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)

---

# Scalar and Table-Valued Functions

## Visão Geral (Overview)

As funções em T-SQL encapsulam lógica de programação reutilizável. As Scalar Functions retornam um valor único; as Table-Valued Functions (TVFs) retornam um conjunto de dados em formato de tabela e podem ser Inline ou Multi-Statement.

> [!abstract]
>
> - Cobre Scalar UDFs, Inline TVFs, Multi-Statement TVFs e o conceito de determinismo.
> - As Inline TVFs são expandidas inline pelo otimizador exatamente como as Views; as Multi-Statement TVFs atuam como caixas pretas (black boxes) fechadas.
> - Tópicos chave do exame: diferenças de desempenho entre Inline e Multi-Statement TVFs, determinismo vs não determinismo e a cláusula `SCHEMABINDING`.

> [!tip] O que o Exame Testa
>
> - **Inline TVF** = retorna o resultado de uma única instrução `SELECT` e sua expressão pode ser integrada ao plano da consulta chamadora.
> - **Multi-statement TVF** = declara e preenche explicitamente uma variável do tipo `TABLE`; seu resultado é tratado de forma diferente pelo otimizador e pode receber estimativas menos precisas.
> - No SQL Server 2019+ (compatibilidade 150 ou superior), no Azure SQL Database e no Azure SQL Managed Instance, uma Scalar UDF elegível pode sofrer inlining automático. A elegibilidade não garante que o inlining ocorra em toda consulta.

---

## Funções Escalares (Scalar Functions)

As Scalar Functions retornam um único valor de saída e podem ser inseridas em qualquer local da query onde uma expressão seja aceita.

```sql
CREATE FUNCTION dbo.fn_GetFullName (
    @FirstName nvarchar(100),
    @LastName  nvarchar(100)
)
RETURNS nvarchar(200)
WITH SCHEMABINDING
AS
BEGIN
    RETURN LTRIM(RTRIM(@FirstName)) + ' ' + LTRIM(RTRIM(@LastName));
END;
GO

-- Exemplo de uso
SELECT dbo.fn_GetFullName(FirstName, LastName) AS FullName
FROM dbo.Employees;
```

**Alerta de desempenho:** quando uma Scalar UDF não é inline, sua invocação pode ocorrer linha a linha e inibir o paralelismo. Em SQL Server 2019+ e serviços Azure compatíveis, confirme no plano se a Scalar UDF elegível foi inline antes de atribuir esse custo à função.

> [!warning] Erro Comum
> Scalar UDFs tradicionais rodando em cláusulas `WHERE` ou de projeção forçam loops row-by-row e barram execuções paralelas. A prova costuma questionar qual tipo de função oferece melhor performance — a recomendação padrão é preferir Inline TVFs em relação a Scalar UDFs ou Multi-statement TVFs.

> [!warning] Gargalo de Performance: Scalar UDFs em SELECT/WHERE
>
> - Ao contrário de views e iTVFs, uma Scalar UDF declarada na projeção ou filtro executa **uma vez para cada linha** retornada.
> - Se sua consulta varrer 1 milhão de registros, a Scalar UDF rodará 1 milhão de vezes físicas, degradando o tempo de processamento drasticamente e impedindo o paralelismo da query.

### Como Evitar o Gargalo das Scalar UDFs?

Para eliminar ou mitigar esse gargalo em consultas de alto volume, utilize as seguintes estratégias (ordenadas por eficiência):

1. **Reescrever como Inline Table-Valued Function (iTVF) com `APPLY` (Recomendação Principal do Exame):**
   - Converta a Scalar UDF em uma iTVF que retorna uma única linha com o valor calculado e invoque-a via `CROSS APPLY` ou `OUTER APPLY`.
   - As iTVFs são expandidas inline como views parametrizadas em todas as versões do SQL Server, eliminando o RBAR e liberando o paralelismo.
   
   ```sql
   -- Em vez de Scalar UDF:
   -- SELECT dbo.fn_CalcularImposto(ValorTotal) FROM dbo.Vendas;

   -- Reescreva como iTVF:
   CREATE FUNCTION dbo.fn_CalcularImpostoITVF (@Valor decimal(10,2))
   RETURNS TABLE WITH SCHEMABINDING AS
   RETURN (SELECT @Valor * 0.15 AS Imposto);
   GO

   -- Uso via CROSS APPLY:
   SELECT v.IdVenda, i.Imposto
   FROM dbo.Vendas v
   CROSS APPLY dbo.fn_CalcularImpostoITVF(v.ValorTotal) i;
   ```

2. **Garantir a Elegibilidade para Scalar UDF Inlining (SQL Server 2019+ / IQP):**
   - Mantenha o nível de compatibilidade em **150+** e adeque o código da função para que `sys.sql_modules.is_inlineable = 1`.
   - *Nota:* Lembre-se de que a elegibilidade não garante inlining em 100% dos contextos de chamada.

3. **Substituir Buscas Internas por `JOIN` Direto:**
   - Se a Scalar UDF faz um `SELECT` interno para buscar descrições ou códigos em outra tabela, substitua a função por um `LEFT JOIN` ou `INNER JOIN` direto na consulta chamadora.

4. **Utilizar Coluna Calculada (*Computed Column*):**
   - Mova a expressão lógica para uma coluna calculada na própria tabela. Se for determinística e criada `WITH SCHEMABINDING`, ela pode ser **persistida (`PERSISTED`) ou indexada**, eliminando o custo de processamento em tempo de leitura.

5. **Inlining Manual de Expressões (`CASE WHEN` Direto):**
   - Para regras simples, escreva a expressão `CASE` diretamente no `SELECT` ou dentro de uma `VIEW`.

---

## Inline Table-Valued Functions (iTVF)

As **Inline TVFs** representam o modelo de função de melhor desempenho — atuam de forma análoga a Views parametrizadas e são expandidas de forma transparente no plano de execução pelo otimizador.

```sql
CREATE FUNCTION dbo.fn_GetCustomerOrders (@CustomerId int)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT
        o.OrderId,
        o.OrderDate,
        SUM(oi.Quantity * oi.UnitPrice) AS TotalAmount
    FROM dbo.Orders o
    JOIN dbo.OrderItems oi ON oi.OrderId = o.OrderId
    WHERE o.CustomerId = @CustomerId
    GROUP BY o.OrderId, o.OrderDate
);
GO

-- Uso (associando com o operador CROSS APPLY)
SELECT c.Name, o.OrderId, o.TotalAmount
FROM dbo.Customers c
CROSS APPLY dbo.fn_GetCustomerOrders(c.CustomerId) o;
```

---

## Multi-Statement Table-Valued Functions (mTVF)

As Multi-Statement TVFs retornam uma variável do tipo tabela que é preenchida por múltiplas instruções imperativas sequenciais — são muito flexíveis logicamente, mas apresentam pior desempenho de consulta por não sofrerem inlining.

```sql
CREATE FUNCTION dbo.fn_GetOrderHierarchy (@OrderId int)
RETURNS @Result TABLE (
    Level       int,
    ItemId      int,
    Description nvarchar(200),
    Amount      decimal(10,2)
)
AS
BEGIN
    INSERT INTO @Result
    SELECT 1, OrderId, 'Order', TotalAmount
    FROM dbo.Orders WHERE OrderId = @OrderId;

    INSERT INTO @Result
    SELECT 2, oi.ItemId, p.Name, oi.Quantity * oi.UnitPrice
    FROM dbo.OrderItems oi
    JOIN dbo.Products p ON p.ProductId = oi.ProductId
    WHERE oi.OrderId = @OrderId;

    RETURN;
END;
```

---

## Comparativo de Funções (Function Comparison)

| Aspecto | Scalar | Inline TVF | Multi-Statement TVF |
| :--- | :--- | :--- | :--- |
| Retorno | Valor escalar único | Tabela (um único `SELECT`) | Tabela (múltiplos blocos de código) |
| Inlining pelo otimizador | Possível para UDFs escalares elegíveis em plataformas compatíveis | **Sim** como expansão relacional | Não é expandida como iTVF |
| Paralelismo | Pode ser inibido quando não há inlining | Permitido conforme o plano chamador | Depende do plano; não assuma bloqueio absoluto |
| `SCHEMABINDING` | Suportado | Suportado | Suportado |
| Múltiplas instruções | Sim | Não | Sim |
| Desempenho geral | Lento em escala | **Melhor performance** | Moderado |

---

## Inlining de Scalar UDFs (Scalar UDF Inlining)

O **Scalar UDF Inlining** foi introduzido no SQL Server 2019 (nível de compatibilidade 150) e nos serviços Azure SQL como parte do **Intelligent Query Processing (IQP)**. Seu objetivo é resolver o gargalo histórico de desempenho das funções escalares definidas pelo usuário.

### O que é Intelligent Query Processing (IQP)?

O **Intelligent Query Processing (IQP)** é uma família de recursos de otimização automática integrados ao motor do SQL Server (2017+), Azure SQL Database e Azure SQL Managed Instance. A premissa central do IQP é **melhorar drasticamente o desempenho de consultas existentes com zero alteração de código**, ativado apenas ao atualizar o nível de compatibilidade do banco de dados (`COMPATIBILITY_LEVEL = 140, 150 ou 160`).

> [!abstract] Diferença Fundamental: Otimizador Tradicional vs. IQP
> - **Otimizador Tradicional (Estático):** Gera um único plano de execução fixo antes de rodar a consulta baseado em estimativas estáticas. Erros de estimativa persistem e degradam o desempenho.
> - **Otimizador com IQP (Dinamismo e Aprendizado):** Ajusta decisões em tempo de execução (ex: alterando tipo de *Join*) ou aprende com execuções passadas (*feedback loops* de memória, paralelismo e estimativa de cardinalidade).

#### Evolução dos Recursos do IQP no Exame DP-800:

| Versão / Nível | Recurso Chave do IQP | Descrição e Impacto em Programmability |
| :--- | :--- | :--- |
| **SQL 2017 (Compat 140)** | *Interleaved Execution para mTVFs* | Executa Multi-Statement TVFs durante a otimização para obter cardinalidade real em vez da estimativa estática de 100 linhas. |
| **SQL 2017 (Compat 140)** | *Batch Mode Adaptive Joins* | Alterna dinamicamente entre *Hash Join* e *Nested Loops* no meio da execução baseado no número real de linhas. |
| **SQL 2019 (Compat 150)** | **Scalar UDF Inlining** | Converte UDFs escalares elegíveis em expressões inline no plano de execução, liberando paralelismo e eliminando RBAR. |
| **SQL 2019 (Compat 150)** | *Table Variable Deferred Compilation* | Adia a compilação de variáveis de tabela (`DECLARE @t TABLE`) para usar a contagem real de linhas em vez da estimativa de 1 linha. |
| **SQL 2019 (Compat 150)** | *Batch Mode on Rowstore* | Permite execução em lote (*Batch Mode*) em tabelas tradicionais baseadas em linhas (*Rowstore*) sem exigir índice Columnstore. |
| **SQL 2022 (Compat 160)** | *PSP (Parameter Sensitive Plan) Optimization* | Mantém múltiplos planos ativos para a mesma consulta parametrizada para resolver *Parameter Sniffing*. |
| **SQL 2022 (Compat 160)** | *DOP & CE Feedback* | Auto-ajusta o Grau de Paralelismo e o Estimador de Cardinalidade com base no histórico de execução. |

### O que é Inlining?

**Inlining** (ou *embutimento*) é a capacidade do otimizador de consultas de **substituir a chamada de uma função pelo próprio código ou expressão matemática/lógica contida nela** diretamente no plano de execução da consulta pai. O otimizador faz uma transformação equivalente a "incorporar" o código da UDF dentro da instrução `SELECT`, `WHERE` ou `JOIN`.

### Gargalo Histórico das UDFs Escalares (Sem Inlining)

Em versões anteriores ao SQL Server 2019 (ou sob níveis de compatibilidade < 150), o motor tratava as UDFs escalares como **"caixas pretas"**:

1. **Execução RBAR (*Row-By-Agonizing-Row*):** A função era invocada de forma isolada uma vez para cada linha retornada ou avaliada pela consulta.
2. **Troca de Contexto (*Context Switching*):** Ocorria uma alternância contínua entre o motor relacional T-SQL e o executor de expressões escalares a cada linha.
3. **Inibição de Paralelismo:** Como o otimizador não enxergava a lógica interna da função, ele assumia um custo estimado fictício e **forçava a consulta a rodar em um plano serial (single-threaded)**.

### Funcionamento no SQL Server 2019+ (IQP)

Com o inlining ativo, o otimizador transpila a lógica imperativa da UDF em subexpressões relacionais equivalentes.

```sql
-- Exemplo de Scalar UDF elegível:
CREATE FUNCTION dbo.fn_CalcularDesconto (@Valor decimal(10,2), @Categoria char(1))
RETURNS decimal(10,2)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE WHEN @Categoria = 'A' THEN @Valor * 0.10 ELSE @Valor * 0.05 END;
END;
GO

-- Consulta chamadora:
SELECT IdVenda, dbo.fn_CalcularDesconto(ValorTotal, CategoriaCliente) AS Desconto
FROM dbo.Vendas;

-- O otimizador reescreve internamente a árvore da consulta (Query Tree) para algo equivalente a:
-- SELECT IdVenda, (CASE WHEN CategoriaCliente = 'A' THEN ValorTotal * 0.10 ELSE ValorTotal * 0.05 END) AS Desconto
-- FROM dbo.Vendas;
```

**Principais Benefícios:**
- **Eliminação do RBAR e Troca de Contexto:** A lógica é avaliada em lote junto com os dados da tabela.
- **Habilitação de Paralelismo:** A consulta pode utilizar múltiplos núcleos de CPU (*multi-threading*).
- **Estimativas de Custo Reais:** O otimizador calcula o custo exato das operações contidas na UDF.

### Como Garantir a Compatibilidade (Nível 150+ e Configurações)

Para que o Scalar UDF Inlining funcione, é necessário verificar e garantir as configurações em 4 níveis (Banco, Escopo, Consulta e Função):

#### 1. Verificar e Alterar o Nível de Compatibilidade (`COMPATIBILITY_LEVEL`)
O Inlining exige nível de compatibilidade **150** (SQL Server 2019) ou **160** (SQL Server 2022 / Azure SQL Database/MI).

```sql
-- 1. Verificar nível de compatibilidade atual:
SELECT name, compatibility_level 
FROM sys.databases 
WHERE name = DB_NAME();

-- 2. Alterar para 150 (SQL Server 2019) ou 160 (SQL Server 2022 / Azure SQL):
ALTER DATABASE MeuBancoDB 
SET COMPATIBILITY_LEVEL = 150;
GO
```

#### 2. Configuração de Escopo do Banco de Dados (`DATABASE SCOPED CONFIGURATION`)
Você pode ativar ou desativar o recurso para o banco de dados sem alterar o nível de compatibilidade geral:

```sql
-- Habilitar inlining no escopo do banco de dados:
ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = ON;

-- Verificar o status da configuração:
SELECT name, value 
FROM sys.database_scoped_configurations 
WHERE name = 'TSQL_SCALAR_UDF_INLINING';
```

#### 3. Controle via Dicas de Consulta (*Query Hints*)
É possível forçar ou desabilitar o inlining para uma instrução `SELECT` específica:

```sql
-- Desabilitar inlining para uma consulta específica:
SELECT dbo.fn_CalcularDesconto(ValorTotal, CategoriaCliente) FROM dbo.Vendas
OPTION (USE HINT('DISABLE_SCALAR_UDF_INLINING'));

-- Forçar inlining se o banco estiver em nível < 150 (mas a instância for 2019+):
SELECT dbo.fn_CalcularDesconto(ValorTotal, CategoriaCliente) FROM dbo.Vendas
OPTION (USE HINT('ENABLE_SCALAR_UDF_INLINING'));
```

#### 4. Cláusula `INLINE = ON` na Definição da Função (SQL Server 2022+ / Compat 160)
A partir do SQL Server 2022, é possível declarar explicitamente se a função deve aceitar inlining:

```sql
CREATE OR ALTER FUNCTION dbo.fn_CalcularDesconto (@Valor decimal(10,2))
RETURNS decimal(10,2)
WITH SCHEMABINDING, INLINE = ON -- (ou INLINE = OFF para proibir explicitamente)
AS
BEGIN
    RETURN @Valor * 0.10;
END;
GO
```

### Elegibilidade da Função vs. Ocorrência de Inlining na Consulta

> [!important] Dica para o Exame DP-800
> **A elegibilidade de uma UDF não garante que o inlining ocorra em toda e qualquer consulta.** 
> A elegibilidade é uma propriedade da *definição da função*, enquanto a ocorrência do inlining depende do *contexto da consulta chamadora*.

#### 1. Elegibilidade da Função (`is_inlineable = 1`)
A UDF em si deve atender a critérios estruturais para que o motor possa transformá-la. Verifique a elegibilidade via DMV:

```sql
SELECT name, is_inlineable 
FROM sys.sql_modules m
JOIN sys.objects o ON m.object_id = o.object_id
WHERE name = 'fn_CalcularDesconto';
```

A função **NÃO será elegível** (`is_inlineable = 0`) se contiver:
- Variáveis do tipo `TABLE` ou tabelas temporárias (`#temp`).
- Funções não-determinísticas ou dependentes do tempo/contexto (como `GETDATE()`, `NEWID()`, `@@ROWCOUNT`).
- Instruções `EXECUTE` dinâmicas ou modificações de dados (`INSERT`/`UPDATE`/`DELETE`).
- Referências a UDFs não-elegíveis ou funções agregadas nativas incompatíveis.

#### 2. Fatores que Impedem o Inlining em Consultas Específicas
Mesmo que a UDF possua `is_inlineable = 1`, o inlining pode ser ignorado durante a compilação de uma consulta específica devido a:
- **Dicas de Consulta (*Query Hints*):** Uso explícito de `OPTION (USE HINT('DISABLE_SCALAR_UDF_INLINING'))`.
- **Contextos de Linguagem Complexos:** Consultas utilizando CTEs recursivas, certas combinações complexas de funções de janela (*Window Functions*) ou cláusulas `GROUP BY` agregadas sobre a UDF.
- **Estouro de Limite de Profundidade:** Múltiplas UDFs encadeadas ou expressões que excedem os limites de memória/tempo de compilação do otimizador.
- **Divergência de Collation ou Tratamento de Erros:** Conflitos de ordenação de caracteres ou blocos de captura de exceção atípicos.

#### Como Verificar se o Inlining Ocorreu
No plano de execução gerado:
- Se o inlining ocorreu, o operador **`User Defined Function` desaparece** e a lógica aparece incorporada aos operadores relacionais normais.
- O XML do plano de execução exibirá o atributo `IsInlineable="true"` e a indicação de execução inline na consulta.

---

## Desempenho: Inline vs. Multi-Statement TVF

O divisor de águas entre as Inline TVFs (iTVFs) e as Multi-statement TVFs (mTVFs) reside na **visibilidade que o otimizador possui do código interno**.

**Inline TVF — o otimizador enxerga a lógica interna:**

- É composta por um único comando `SELECT`; o otimizador a expande como uma "View parametrizada".
- Estatísticas das tabelas físicas continuam expostas, resultando em estimativas de cardinalidade corretas.
- É mesclada diretamente dentro do plano de execução da query chamadora.

**Multi-statement TVF — caixa preta para o otimizador:**

- Preenche uma variável local do tipo tabela através de blocos isolados; a lógica interna é oculta.
- Historicamente, o otimizador usava uma estimativa fixa de linhas para mTVFs (1 linha antes do SQL Server 2014 e 100 linhas a partir do SQL Server 2014).
- A execução intercalada de mTVFs, disponível no SQL Server 2017+ com nível de compatibilidade 140 e em serviços Azure compatíveis, pode executar a mTVF durante a otimização e usar a cardinalidade real da primeira execução. Ela não é a compilação adiada de variáveis de tabela.

### Execução intercalada (*Interleaved Execution*) para mTVFs

É um recurso de **Intelligent Query Processing (IQP)** que corrige uma limitação específica das mTVFs: antes de conhecer o tamanho de sua tabela de retorno, o otimizador precisava usar um palpite fixo de cardinalidade. A partir do SQL Server 2017, com `COMPATIBILITY_LEVEL` 140 ou superior, uma consulta elegível pode interromper temporariamente a otimização para obter esse dado real.

O fluxo é o seguinte:

1. O otimizador começa a compilar a consulta e encontra uma mTVF candidata.
2. Em vez de escolher de imediato o restante do plano com o palpite fixo, ele pausa a otimização.
3. O SQL Server executa a parte da consulta que materializa a mTVF e captura a quantidade real de linhas retornadas.
4. A otimização é retomada para os operadores **posteriores** à mTVF — por exemplo, `JOIN`, `Sort`, agregações e *memory grant* — agora com essa cardinalidade.

Isso pode mudar uma escolha inadequada de `Nested Loops` para `Hash Join`, dimensionar melhor a memória e reduzir *spills* no TempDB. A primeira execução que compila o plano é essencial: é nela que a cardinalidade é observada; se o plano sair do cache, uma nova compilação repete o processo. `OPTION (RECOMPILE)` também cria um plano novo para aquela execução.

**Pré-requisitos e verificação:** o banco precisa estar em compatibilidade 140+, a configuração de execução intercalada deve estar habilitada (padrão) e a instrução precisa ser elegível. Não é uma garantia para toda mTVF ou todo contexto de consulta. A consulta precisa de fato ser executada para que o mecanismo revise a estimativa; o plano estimado apenas pode indicar candidatos com o atributo XML `ContainsInterleavedExecutionCandidates`. No plano real, compare as linhas estimadas e reais no operador da TVF e nas operações posteriores.

```sql
-- Confirme o nível de compatibilidade necessário.
SELECT name, compatibility_level
FROM sys.databases
WHERE name = DB_NAME();

-- Verifique a configuração aplicável à versão instalada.
SELECT name, value, value_for_secondary
FROM sys.database_scoped_configurations
WHERE name IN (N'INTERLEAVED_EXECUTION_TVF', N'DISABLE_INTERLEAVED_EXECUTION_TVF');
```

**Limites importantes:** a execução intercalada melhora a estimativa de **quantidade de linhas**, não cria estatísticas ou histogramas sobre a tabela de retorno, não torna a lógica da mTVF visível ao otimizador e não elimina o custo de materializá-la. Portanto, uma iTVF continua sendo a opção preferida quando a regra de negócio puder ser expressa em um único `SELECT`. Não confunda este recurso com *Table Variable Deferred Compilation* (SQL Server 2019/compatibilidade 150), que trata variáveis de tabela declaradas na consulta, não o resultado de uma mTVF.

**Gargalo de cardinalidade:** Quando uma mTVF retorna milhares de registros reais, mas o otimizador estima de antemão apenas 100, os operadores subsequentes (joins, ordenação, agregação) são dimensionados de forma incorreta. Isso gera concessões de memória insuficientes (memory grant underestimates), vazamentos de memória para o TempDB e estratégias de joins ineficientes.

**Regra geral:** Adote sistematicamente as Inline TVFs, exceto em cenários de processamentos imperativos complexos em múltiplos passos impossíveis de serem modelados em um único `SELECT`.

> [!important] Multi-statement TVFs e TempDB Spill
>
> - Como o otimizador não pode "olhar" dentro da MSTVF, as estimativas de cardinalidade estática incorretas (como estimar 100 linhas para um retorno de 100.000 linhas) levam a concessões de memória (memory grants) subdimensionadas.
> - Isso faz com que o SQL Server jogue dados excedentes para o disco (TempDB Spill) durante ordenações ou junções do plano, causando quedas catastróficas de I/O.

```sql
-- iTVF: o otimizador mapeia a lógica interna
CREATE FUNCTION dbo.fn_GetCustomerOrders(@CustomerID INT)
RETURNS TABLE
AS
RETURN (
    SELECT OrderID, OrderDate, TotalAmount
    FROM Orders
    WHERE CustomerID = @CustomerID
    AND Status = 'Active'
);

-- mTVF: caixa preta para o otimizador, estimativas fixas ruins
CREATE FUNCTION dbo.fn_GetOrderDetails(@CustomerID INT)
RETURNS @Result TABLE (OrderID INT, Total DECIMAL(18,2))
AS
BEGIN
    INSERT @Result
    SELECT OrderID, TotalAmount FROM Orders WHERE CustomerID = @CustomerID;
    -- operações adicionais...
    RETURN;
END;
```

---

## Operador APPLY com Table-Valued Functions

O operador `APPLY` executa a chamada de uma TVF (ou subquery parametrizada) para cada linha individual retornada pela tabela à esquerda da expressão. Há duas formas de uso:

- **CROSS APPLY** — atua de forma semelhante a um `INNER JOIN`; descarta linhas da tabela esquerda caso a execução da TVF retorne vazia.
- **OUTER APPLY** — atua de forma semelhante a um `LEFT JOIN`; preserva todas as linhas da tabela esquerda preenchendo com NULL se a TVF correspondente não trouxer dados.

**Casos de uso principais:** Executar uma função por linha sobre o conjunto de dados, ou retornar uma quantidade variável de linhas relacionadas para cada linha pai.

```sql
-- CROSS APPLY: trazer as 3 maiores compras de cada cliente
SELECT c.CustomerID, c.Name, o.OrderID, o.TotalAmount
FROM Customers c
CROSS APPLY (
    SELECT TOP 3 OrderID, TotalAmount
    FROM Orders
    WHERE CustomerID = c.CustomerID
    ORDER BY TotalAmount DESC
) o;

-- OUTER APPLY com uma inline TVF
SELECT c.CustomerID, c.Name, latest.LastOrderDate
FROM Customers c
OUTER APPLY dbo.fn_GetLatestOrder(c.CustomerID) latest;
```

A cláusula `CROSS APPLY` substituindo subqueries correlacionadas é a forma canônica de associar dados de uma TVF a tabelas relacionais em T-SQL.

---

## Determinismo de Funções (Function Determinism)

Uma função é dita **determinística** quando retorna sempre o mesmo resultado exato quando alimentada com os mesmos parâmetros de entrada e sob o mesmo estado físico do banco. Caso contrário, é considerada **não determinística**.

| Categoria | Exemplos |
| :--- | :--- |
| Determinística | `LEN`, `DATEADD`, `ROUND`, `UPPER`, `ABS` |
| Não determinística | `GETDATE`, `NEWID`, `RAND`, `@@ROWCOUNT` |

**Por que isso é relevante:**

- A criação de indexes sobre computed columns exige que as funções envolvidas sejam estritamente determinísticas (e usem `SCHEMABINDING`).
- As Indexed Views só aceitam funções determinísticas em sua declaração.
- Funções não determinísticas impedem certas otimizações dinâmicas de planos no otimizador.

Para verificar se uma função criada pelo usuário (UDF) é determinística:

```sql
SELECT OBJECTPROPERTY(OBJECT_ID('dbo.MyFunc'), 'IsDeterministic');
-- Retorna 1 (determinística) ou 0 (não determinística)
```

O modificador `SCHEMABINDING` é obrigatório para que o SQL Server avalie uma UDF como determinística — sem ele, o motor assume que a função pode acessar objetos externos arbitrários, classificando-a como não determinística.

---

## SCHEMABINDING para Funções

A propriedade `WITH SCHEMABINDING` acopla a função aos objetos de banco referenciados em seu corpo, impedindo que essas tabelas/views sejam excluídas ou alteradas de forma a invalidar a lógica interna da função.

**Requisito obrigatório quando:**

- A função for referenciada por uma computed column a ser indexada.
- A função for referenciada na estrutura de uma Indexed View.
- A função for invocada de dentro de outro objeto configurado com schemabinding.

**Regras:**

- Todas as tabelas e views referenciadas devem usar o padrão de nomes de duas partes: `dbo.NomeTabela`.
- Declare `WITH SCHEMABINDING` imediatamente após a cláusula `RETURNS` (nas Scalar) ou `RETURNS TABLE` (nas inline TVFs).

```sql
CREATE FUNCTION dbo.fn_FormatPhone(@Phone nvarchar(20))
RETURNS nvarchar(20)
WITH SCHEMABINDING
AS
BEGIN
    RETURN '(' + LEFT(@Phone,3) + ') ' + SUBSTRING(@Phone,4,3) + '-' + RIGHT(@Phone,4);
END;
```

---

## Casos de Uso (Use Cases)

- **Scalar**: Formatações de texto, cálculos matemáticos rápidos e encapsulamento de regras lógicas de negócio simples.
- **Inline TVF**: Substitutas parametrizadas para Views convencionais, ou junções complexas com `CROSS APPLY`.
- **Multi-statement TVF**: Lógicas procedurais imperativas complexas cujos retornos de tabelas não caibam em uma única query `SELECT`.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| Consulta muito lenta com Scalar UDF | Processamento row-by-row, bloqueio de paralelismo | `Reescreva a lógica como uma Inline TVF ou insira o código inline na query`. |
| Baixo desempenho geral em mTVF | Estimativa de cardinalidade inadequada para o resultado | Considere reescrever como iTVF; quando aplicável, use SQL Server 2017+ com compatibilidade 140 para avaliar a execução intercalada. |
| Erro ao criar index sobre coluna calculada | A função envolvida não é determinística ou falta o schemabinding | Insira a instrução `WITH SCHEMABINDING` e certifique-se de referenciar objetos com nomes de duas partes. |
| Cláusula `CROSS APPLY` omitindo linhas importantes | Comportamento de INNER JOIN em vez de LEFT JOIN | Modifique o operador da query de `CROSS APPLY` para `OUTER APPLY`. |

---

## Melhores Práticas (Best Practices)

- Prefira sempre o uso de **Inline TVFs em relação a Scalar Functions** em processamentos orientados a conjuntos — as iTVFs liberam o paralelismo e inlining pelo otimizador.
- Configure `WITH SCHEMABINDING` em funções consumidas por computed columns indexadas, Indexed Views ou outros objetos críticos.
- Minimize o uso de MSTVFs em queries de alta volumetria. Caso sejam indispensáveis, valide o plano e, em SQL Server 2017+ com compatibilidade 140, avalie se a execução intercalada está disponível.
- Adote **CROSS APPLY** (em vez de subqueries correlacionadas redundantes no SELECT) para associar TVFs a tabelas.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - **Inline TVF é o tipo preferido de função** — suporta inlining do otimizador de plano.
> - Uma Scalar UDF que não sofre inlining pode inibir o paralelismo; confirme a elegibilidade e o plano de execução.
> - mTVFs usavam estimativas fixas de 1 linha antes do SQL Server 2014 e de 100 linhas a partir dele. SQL Server 2017+ com compatibilidade 140 pode usar execução intercalada para obter a cardinalidade real.
> - A diretiva `SCHEMABINDING` é necessária para validar o determinismo exigido em indexes sobre computed columns.
> - `CROSS APPLY` descarta linhas que não encontrem correspondência na TVF (INNER); `OUTER APPLY` preserva todas as linhas da esquerda preenchendo com nulo caso falte dados (LEFT).

---

## Resumo dos Conceitos (Key Takeaways)

- Substitua lógicas escalares por Inline TVFs sempre que possível.
- O Schemabinding resguarda a consistência e integridade estrutural das dependências.
- O inlining automático de Scalar UDFs (SQL 2019+) otimiza queries simples sem requerer refatoração manual.
- As mTVFs geram péssimas escolhas de planos downstream devido ao ocultamento de sua lógica de contagem de linhas para o otimizador.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma query que executa a junção da tabela `Customers` com uma Multi-statement TVF filtrando pelo campo `CustomerID` apresenta péssimo desempenho e exibe estimativa de linhas errada no plano de execução. Qual é a causa PRIMÁRIA dessa ineficiência?

A. As Multi-statement TVFs forçam o banco a realizar scans completos na tabela base referenciada.

B. O otimizador de consultas não consegue mapear a lógica interna da Multi-statement TVF, adotando uma estimativa de cardinalidade fixa padrão.

C. A junção direta não é permitida em Multi-statement TVFs, sendo obrigatório o uso de `CROSS APPLY`.

D. A TVF apresenta falha por não possuir um Clustered Index configurado sobre sua variável de tabela de retorno.

> [!success]- Resposta
> **B — O otimizador de consultas não consegue mapear a lógica interna da Multi-statement TVF, adotando uma estimativa de cardinalidade fixa padrão**
>
> As mTVFs não são expandidas como uma iTVF no plano chamador. Historicamente, isso fazia o otimizador adotar uma estimativa estática (1 linha antes do SQL Server 2014 e 100 linhas a partir dele). Em SQL Server 2017+ com compatibilidade 140, a execução intercalada pode melhorar essa estimativa. Reescrever como Inline TVF costuma dar maior visibilidade ao otimizador; `CROSS APPLY` não altera, por si só, a estimativa.

---

## Tópicos Relacionados

- [01-Views](./01-views.md)
- [03-Stored Procedures](./03-stored-procedures.md) *(Inglês apenas)*
- [01-CTEs & Window Functions](../03-advanced-tsql/01-ctes-window-functions.md) *(Inglês apenas)*

---

## Documentação Oficial

- [User-Defined Functions](https://learn.microsoft.com/en-us/sql/relational-databases/user-defined-functions/user-defined-functions)
- [Scalar UDF Inlining](https://learn.microsoft.com/en-us/sql/relational-databases/user-defined-functions/scalar-udf-inlining)

---

**[← Anterior](./01-views.md) | [↑ Voltar para a Seção](./programmability-objects.md) | [Próximo →](./03-stored-procedures.md)**
