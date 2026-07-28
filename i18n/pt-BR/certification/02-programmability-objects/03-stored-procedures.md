---
title: Stored Procedures
type: study-material
tags:
  - dp-800
  - stored-procedures
  - t-sql
  - execute-as
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Desenvolvimento de Stored Procedures](#criando-stored-procedures-creating-stored-procedures)
>   - 🔹 [Criando Stored Procedures](#criando-stored-procedures-creating-stored-procedures)
>   - 🔹 [Parâmetros de Saída (Output Parameters)](#parametros-de-saida-output-parameters)
>   - 🔹 [Parâmetros do Tipo Tabela (Table-Valued Parameters)](#parametros-do-tipo-tabela-table-valued-parameters)
>   - 🔹 [Tratamento de Erros (Error Handling)](#tratamento-de-erros-error-handling)
> - 📍 [3. Arquitetura Avançada, Segurança & Performance](#execute-as--contexto-de-seguranca-security-context)
>   - 🔹 [EXECUTE AS — Contexto de Segurança](#execute-as--contexto-de-seguranca-security-context)
>   - 🔹 [Recompilação e Plan Caching](#recompilacao-recompilation)
>   - 🔹 [sp_executesql para SQL Dinâmico](#sp_executesql-para-sql-dinamico-dynamic-sql)
>   - 🔹 [Natively Compiled Stored Procedures](#natively-compiled-stored-procedures)
> - 📍 [4. Aplicação Prática & Síntese](#casos-de-uso-use-cases)
>   - 🔹 [Casos de Uso](#casos-de-uso-use-cases)
>   - 🔹 [Problemas Comuns](#problemas-comuns-e-solucoes-common-issues)
>   - 🔹 [Melhores Práticas & Dicas de Exame](#melhores-praticas-best-practices)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)

---

# Stored Procedures

## Visão Geral (Overview)

As Stored Procedures são lotes (batches) de comandos T-SQL armazenados no banco de dados. O SQL Server pode compilar e reutilizar seus planos de execução; elas também aceitam parâmetros, tratamento de erros, controle de transações e alternância de contexto de segurança.

> [!abstract]
>
> - Cobre a criação de Stored Procedures, parâmetros (INPUT/OUTPUT), SQL dinâmico, tratamento de erros e contexto de execução.
> - As Stored Procedures encapsulam lógicas de negócio, facilitam o reuso de planos de execução e podem utilizar a cláusula `EXECUTE AS` para gerenciar contextos de segurança.
> - Tópicos chave do exame: diferenças de `sp_executesql` vs `EXEC` para SQL dinâmico, blocos `TRY/CATCH` com a função `XACT_STATE()`, e configuração de parâmetros `OUTPUT`.

> [!tip] O que o Exame Testa
>
> - A procedure do sistema **`sp_executesql`** permite parametrização completa (bloqueia SQL injection e viabiliza reuso de planos de execução); a cláusula `EXEC(@sql)` não aceita parametrização direta.
> - Parâmetros do tipo `OUTPUT` retornam valores de volta para o código chamador; devem ser declarados com o modificador `@parametro tipo OUTPUT` tanto na definição da procedure quanto no comando de execução.
> - No bloco `CATCH`, `XACT_STATE() = -1` indica uma transação não confirmável. Ela não pode receber novas alterações nem `COMMIT`; faça `ROLLBACK` antes de encerrar ou reutilizar a transação.

---

## Criando Stored Procedures (Creating Stored Procedures)

```sql
CREATE PROCEDURE dbo.usp_GetCustomerOrders
    @CustomerId  int,
    @StartDate   date = NULL,
    @EndDate     date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        o.OrderId,
        o.OrderDate,
        o.TotalAmount
    FROM dbo.Orders o
    WHERE o.CustomerId = @CustomerId
      AND (@StartDate IS NULL OR o.OrderDate >= @StartDate)
      AND (@EndDate   IS NULL OR o.OrderDate <= @EndDate)
    ORDER BY o.OrderDate DESC;
END;
GO

-- Executar a procedure
EXEC dbo.usp_GetCustomerOrders @CustomerId = 42, @StartDate = '2025-01-01';
```

---

## Parâmetros de Saída (Output Parameters)

```sql
CREATE PROCEDURE dbo.usp_CreateOrder
    @CustomerId  int,
    @OrderId     int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Orders (CustomerId, OrderDate)
    VALUES (@CustomerId, GETUTCDATE());

    SET @OrderId = SCOPE_IDENTITY();
END;
GO

-- Executar capturando o valor OUTPUT
DECLARE @NewOrderId int;
EXEC dbo.usp_CreateOrder @CustomerId = 1, @OrderId = @NewOrderId OUTPUT;
SELECT @NewOrderId AS NewOrderId;
```

---

## Parâmetros do Tipo Tabela (Table-Valued Parameters)

```sql
-- Criar o tipo de dados tabela
CREATE TYPE dbo.OrderItemList AS TABLE (
    ProductId   int             NOT NULL,
    Quantity    int             NOT NULL,
    UnitPrice   decimal(10,2)   NOT NULL
);
GO

-- Consumir o tipo criado na assinatura da procedure
CREATE PROCEDURE dbo.usp_InsertOrderItems
    @OrderId    int,
    @Items      dbo.OrderItemList READONLY -- Deve ser obrigatoriamente READONLY
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.OrderItems (OrderId, ProductId, Quantity, UnitPrice)
    SELECT @OrderId, ProductId, Quantity, UnitPrice
    FROM @Items;
END;
GO
```

> [!important] TVPs devem ser READONLY
>
> - Parâmetros do tipo Table-Valued Parameter (TVP) são **obrigatoriamente passados como READONLY** para a Stored Procedure.
> - Você não pode modificar (executar `UPDATE`, `INSERT` ou `DELETE` diretamente nas linhas do TVP) de dentro da procedure.

---

## Tratamento de Erros (Error Handling)

```sql
CREATE PROCEDURE dbo.usp_TransferFunds
    @FromAccountId  int,
    @ToAccountId    int,
    @Amount         decimal(18,2)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE dbo.Accounts SET Balance -= @Amount WHERE AccountId = @FromAccountId;
        UPDATE dbo.Accounts SET Balance += @Amount WHERE AccountId = @ToAccountId;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW; -- Propaga o erro original de volta ao chamador
    END CATCH;
END;
GO
```

**Funções auxiliares de erro utilizáveis no bloco CATCH:**

| Função | Retorno |
| :--- | :--- |
| `ERROR_NUMBER()` | Número identificador do erro no SQL. |
| `ERROR_MESSAGE()` | `Texto com a descrição da mensagem de erro`. |
| `ERROR_SEVERITY()` | Nível de gravidade do erro (faixa de 1 a 25). |
| `ERROR_STATE()` | Estado do erro. |
| `ERROR_LINE()` | Número da linha física onde ocorreu a exceção. |
| `ERROR_PROCEDURE()` | Nome do objeto de procedure correspondente. |

---

## EXECUTE AS — Contexto de Segurança (Security Context)

A diretiva `EXECUTE AS` altera temporariamente o contexto de execução de segurança do banco durante a chamada da procedure:

```sql
-- Executar sob a identidade de um usuário específico
CREATE PROCEDURE dbo.usp_GetSensitiveData
WITH EXECUTE AS 'ReportUser'
AS
BEGIN
    SELECT * FROM dbo.SensitiveTable; -- executa sob o contexto e permissões do ReportUser
END;

-- Executar sob a identidade do criador/dono do objeto (schema owner)
CREATE PROCEDURE dbo.usp_CrossSchemaQuery
WITH EXECUTE AS OWNER
AS
BEGIN
    SELECT * FROM OtherSchema.Table1;
END;
```

**Opções disponíveis no EXECUTE AS:** `CALLER` (padrão, herda do chamador), `SELF` (dono/criador atual do objeto), `OWNER` (proprietário do esquema da procedure), `'username'` (usuário específico).

> [!warning] EXECUTE AS CALLER vs OWNER vs USER
>
> - **CALLER (Padrão)**: Executa com os privilégios de quem está chamando a procedure.
> - **OWNER**: Executa com as permissões do dono do esquema do objeto (útil para quebrar cadeias de propriedade quebradas sem expor tabelas).
> - **'username'**: Executa fingindo ser uma conta específica (requer permissão de personificação `IMPERSONATE` no usuário).

---

## Recompilação (Recompilation)

```sql
-- Forçar recompilação pontual (para evitar problemas de parameter sniffing na chamada)
EXEC dbo.usp_GetCustomerOrders @CustomerId = 42 WITH RECOMPILE;

-- Forçar recompilação a cada execução (para consultas com dados de alta variação física)
CREATE PROCEDURE dbo.usp_VariableQuery
WITH RECOMPILE
AS ...
```

> [!tip] Dica para a Prova: Sniffing vs Recompile
>
> - Se a variabilidade de cardinalidade for alta em apenas uma consulta específica dentro da procedure, use o hint `OPTION(RECOMPILE)` na query individual, em vez de recompilar a procedure inteira com `WITH RECOMPILE`. Isso poupa CPU valioso.

---

## sp_executesql para SQL Dinâmico (Dynamic SQL)

Utilize sistematicamente a procedure de sistema **`sp_executesql`** em vez do comando `EXEC(@sql)`. Isso viabiliza a parametrização das variáveis, otimiza o cache de planos e elimina o risco de ataques por injeção de SQL (SQL injection).

**Benefícios de usar sp_executesql em relação a EXEC(@sql):**

- **Parametrização** — os valores são passados como variáveis tipadas, e não concatenados diretamente como texto plano na string.
- **Plan caching** — possibilita ao motor reutilizar o mesmo hash de plano compilado para chamadas futuras com parâmetros de valores distintos.
- **Segurança contra SQL injection** — impede que caracteres especiais de entrada de usuários alterem as instruções lógicas do comando compilado.

**Sintaxe básica:** `EXEC sp_executesql @stmt, N'@param1 tipo, @param2 tipo', @param1 = valor, @param2 = valor`

**Quando usar SQL dinâmico:** Necessidade de referenciar nomes de tabelas/colunas variáveis recebidos por parâmetros de entrada, ordenações estruturadas dinâmicas (`ORDER BY`) ou nomes de objetos avaliados em tempo de execução.

```sql
-- VULNERÁVEL: concatenação direta = Risco de SQL injection + impede reuso de planos
DECLARE @sql NVARCHAR(MAX);
DECLARE @CustomerID int = 42;
SET @sql = 'SELECT * FROM Orders WHERE CustomerID = ' + @CustomerID;
EXEC(@sql); -- PÉSSIMA PRÁTICA: sem parametrização

-- SEGURO: uso de sp_executesql parametrizado
SET @sql = 'SELECT * FROM Orders WHERE CustomerID = @CustID';
EXEC sp_executesql
    @sql,
    N'@CustID INT',
    @CustID = @CustomerID; -- EXCELENTE: parametrizável e cacheável

-- Nome de tabela dinâmico (necessita de validação prévia de segurança)
DECLARE @TableName NVARCHAR(128) = N'Orders';
-- Validar se o objeto existe fisicamente no banco!
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = @TableName AND type = 'U')
    THROW 50001, 'Nome de tabela inválido', 1;
SET @sql = 'SELECT COUNT(*) FROM ' + QUOTENAME(@TableName);
EXEC sp_executesql @sql;
```

> [!warning] Erro Comum
> O uso de `EXEC(@sql)` com concatenação de dados de entrada externos representa uma falha de segurança grave de injeção de SQL. Sempre implemente `sp_executesql` com parametrização para SQL dinâmico. O exame DP-800 cobra essa distinção de forma rotineira em questões de segurança e otimização de performance (reuso de cache de planos).

---

## Natively Compiled Stored Procedures

As Stored Procedures compiladas nativamente são pré-compiladas diretamente para código de máquina no momento de sua criação física, provendo desempenho extremo em cargas OLTP executadas sobre tabelas In-Memory OLTP.

**Requisitos estruturais:**

- O modificador `WITH NATIVE_COMPILATION` deve ser declarado.
- A cláusula `SCHEMABINDING` é obrigatória; impede modificações nas tabelas base referenciadas.
- Deve referenciar exclusivamente tabelas do tipo memory-optimized.

**Limitações:**

- Subconjunto restrito de T-SQL suportado: sem suporte a tabelas temporárias, cursores e tipos complexos de JOINs.
- O corpo deve ter um único bloco `BEGIN ATOMIC`; `TRY...CATCH` e `THROW` são suportados em módulos compilados nativamente nas versões atuais.
- Não aceita execução de SQL dinâmico ou procedures do tipo `EXEC`.

**Blocos ATOMIC** definem o escopo transacional obrigatório da procedure compilada nativamente. Eles tornam a execução atômica, mas não substituem o tratamento explícito de erros com `TRY...CATCH` quando esse tratamento for necessário.

```sql
CREATE PROCEDURE dbo.usp_InsertOrder
    @CustomerID INT,
    @TotalAmount DECIMAL(18,2)
WITH NATIVE_COMPILATION, SCHEMABINDING
AS
BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'English')
    INSERT INTO dbo.OrdersMemoryOptimized (CustomerID, TotalAmount, OrderDate)
    VALUES (@CustomerID, @TotalAmount, GETUTCDATE());
END;
```

---

## Cache de Planos e Recompilação (Plan Caching & Recompilation)

O SQL Server compila e armazena o plano de execução de uma procedure em sua primeira execução para reuso futuro. O comportamento de **parameter sniffing** (escuta de parâmetros) significa que este primeiro plano gerado é otimizado com base nos valores específicos informados nesta primeira chamada.

**Quando o parameter sniffing vira um problema:**

- A primeira execução utiliza parâmetros atípicos (ex: busca por IDs que trazem pouquíssimas linhas).
- O plano otimizado gerado é ineficiente para as execuções seguintes contendo volumetria alta de dados.
- Sintomas típicos: a procedure roda super rápido para alguns clientes, mas é lenta para outros sem que a estrutura ou os indexes tenham mudado.

### Diagnóstico: evidência antes de aplicar hints

*Parameter sniffing* é uma hipótese, não uma conclusão automática. Antes de usar `OPTION(RECOMPILE)`, `OPTIMIZE FOR` ou qualquer outro hint, colete evidências que separem esse problema de estatísticas desatualizadas, índice ausente ou predicado não sargável:

- **Plano de execução real:** compare `Estimated Rows` e `Actual Rows`, principalmente nos operadores posteriores ao filtro por parâmetro. Divergências grandes e repetíveis indicam que a cardinalidade usada na compilação não representa a chamada atual.
- **I/O e CPU:** use `SET STATISTICS IO, TIME ON` com parâmetros seletivos e não seletivos. Registre leituras lógicas, CPU e duração; compare chamadas equivalentes, não apenas o custo percentual exibido no plano.
- **Padrão reproduzível:** confirme que a lentidão muda conforme o parâmetro ou conforme qual chamada compilou o plano em cache. Uma ocorrência isolada pode ser cache frio, bloqueio, espera de recursos ou atividade concorrente.
- **Estatísticas e acesso:** confirme que as estatísticas relevantes estão atualizadas e examine `Key Lookups` repetitivos, `Nested Loops` sobre muitas linhas, scans excessivos e *spills* de `Sort`/`Hash`. Corrija índice, estatística ou query antes de fixar um hint.

Somente após esse diagnóstico escolha a menor intervenção que resolva o sintoma e registre a razão. Reavalie a decisão quando o volume ou a distribuição dos dados mudar.

**Opções de resolução:**

| Abordagem | Funcionamento | Custo / Impacto |
| :--- | :--- | :--- |
| `OPTION(RECOMPILE)` | Recompila apenas a query específica a cada execução. | Alto — perde reuso de planos para a query. |
| `OPTIMIZE FOR (valor)` | Compila o plano otimizado para um valor específico informado. | Baixo — plano fixo único, pode não servir para todos. |
| `OPTIMIZE FOR UNKNOWN` | `Ignora o valor do parâmetro e usa estatísticas médias de distribuição`. | Baixo — gera plano balanceado comum. |
| Variável local temporária | Mapear o parâmetro em variável local antes de usar. | Baixo — rompe o sniffing gerando plano médio. |
| `WITH RECOMPILE` na procedure | Recompila a procedure inteira a cada execução. | Alto — use apenas se indispensável. |

```sql
-- OPTION(RECOMPILE) aplicada a uma query específica
SELECT * FROM Orders WHERE CustomerID = @CustomerID
OPTION(RECOMPILE);

-- OPTIMIZE FOR para otimizar com base em um valor representativo padrão
SELECT * FROM Orders WHERE CustomerID = @CustomerID
OPTION(OPTIMIZE FOR (@CustomerID = 12345));

-- OPTIMIZE FOR UNKNOWN (utiliza estatísticas médias das colunas)
SELECT * FROM Orders WHERE CustomerID = @CustomerID
OPTION(OPTIMIZE FOR (@CustomerID UNKNOWN));
```

---

## Casos de Uso (Use Cases)

- **Encapsulamento**: Esconder lógicas de banco complexas por trás de uma chamada simples.
- **Segurança e Privilégios**: Conceder acesso à execução da procedure (`EXECUTE`) sem dar acesso de leitura física direto às tabelas (Ownership Chaining / Encadeamento de Propriedade).
- **Desempenho**: Compilação única com reuso de planos; redução de tráfego de rede.
- **Transacionalidade**: Empacotar operações em múltiplos passos sob a segurança de uma única transação atômica.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| Desempenho inconsistente (parameter sniffing) | Plano em cache otimizado para parâmetro atípico | Utilize `OPTION (RECOMPILE)` ou o hint `OPTIMIZE FOR`. |
| Erros em transações aninhadas | Commits de transações internas invalidando a externa | Valide a variável global `@@TRANCOUNT`; utilize `SAVE TRANSACTION` para savepoints. |
| Lentidão por tráfego de rede verbose | Falta da instrução de supressão de mensagens | Declare sistematicamente `SET NOCOUNT ON` no início das procedures. |
| Vulnerabilidade a injeção SQL | Concatenação de variáveis em SQL dinâmico | `Adote `sp_executesql` parametrizado; higienize objetos usando `QUOTENAME``. |
| Falhas em natively compiled procedures | Uso de recursos T-SQL incompatíveis com in-memory | Revise a documentação de recursos incompatíveis com In-Memory OLTP. |

---

## Melhores Práticas (Best Practices)

- Insira sempre `SET NOCOUNT ON` no início de todas as procedures para suprimir mensagens de contagem de linhas retornadas ao cliente, otimizando o tráfego de rede.
- Utilize `sp_executesql` para qualquer execução de SQL dinâmico; nunca concatene entradas externas diretamente nas strings de comando.
- Prefira a instrução `THROW` em relação ao comando `RAISERROR` legado — o `THROW` mantém com total fidelidade o erro de sistema original.
- Adote a função `SCOPE_IDENTITY()` em vez da global `@@IDENTITY` para evitar a captura acidental de chaves geradas por triggers internos.
- Use `EXECUTE AS` com princípio de menor privilégio quando a procedure precisar acessar objetos em outros esquemas fora das permissões do usuário chamador.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - `THROW` propaga erros de forma limpa preservando códigos originais; `RAISERROR` é a opção legada.
> - A função `SCOPE_IDENTITY()` retorna o último identificador gerado no **escopo corrente** da execução (mais seguro do que `@@IDENTITY`).
> - Parâmetros do tipo tabela (table-valued parameters) devem ser obrigatoriamente declarados como `READONLY` na assinatura da procedure.
> - A procedure `sp_executesql` permite reuso de planos para queries dinâmicas; `EXEC(@sql)` não executa parametrização.
> - Stored Procedures compiladas nativamente exigem um bloco `ATOMIC`; `TRY...CATCH` e `THROW` permanecem disponíveis nas versões atuais.
> - O hint `OPTIMIZE FOR UNKNOWN` é a solução padrão mais equilibrada para resolver parameter sniffing mitigando planos extremos ineficientes.

---

## Resumo dos Conceitos (Key Takeaways)

- As procedures aceitam parâmetros de INPUT, OUTPUT e do tipo TABLE.
- Implemente lógicas robustas de transação envolvendo blocos `TRY/CATCH` e tratamento com `THROW`.
- A alternância com `EXECUTE AS` viabiliza padrões rígidos de controle de acesso sem necessidade de permissões diretas nas tabelas base.
- O parameter sniffing degrada a estabilidade do tempo de execução; a recompilação seletiva ou o uso de estatísticas médias de distribuição sanam a inconsistência.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma Stored Procedure que realiza buscas de pedidos recebendo o parâmetro `CustomerID` apresenta excelente tempo de resposta para a quase totalidade das buscas, porém é extremamente lenta quando executada para um cliente específico de altíssimo volume de vendas. A análise revela que o plano de execução em cache foi gerado na primeira chamada com um cliente de baixíssima movimentação. Qual é a MELHOR abordagem para sanar essa inconsistência de desempenho de forma permanente?

A. Declarar a instrução `WITH RECOMPILE` na definição da Stored Procedure.

B. Adicionar o hint `OPTION(OPTIMIZE FOR (@CustomerID UNKNOWN))` na query.

C. Recompilar todos os indexes físicos associados à tabela `Orders`.

D. Modificar o código interno para executar a busca via comando `EXEC` em vez de `sp_executesql`.

> [!success]- Resposta
> **B — Adicionar o hint `OPTION(OPTIMIZE FOR (@CustomerID UNKNOWN))` na query**
>
> O cenário descreve um problema clássico de *parameter sniffing*. O uso da instrução `OPTIMIZE FOR UNKNOWN` força o otimizador a desconsiderar o valor de entrada na compilação e adotar estatísticas médias de distribuição de registros, produzindo um plano balanceado e eficiente para qualquer cliente. Adicionar `WITH RECOMPILE` na procedure (A) forçaria recompilações completas em cada chamada de execução, gerando consumo proibitivo de CPU. A recriação de indexes (C) ou alteração de comando de execução (D) não tratam do parameter sniffing do cache.

---

## Inspecionar contrato de resultado

`sys.sp_describe_first_result_set` retorna metadados do primeiro result set sem
executar a operação de negócio. Pode falhar quando o SQL Server não determina
estaticamente o formato, como em alguns caminhos de SQL dinâmico.

## Tópicos Relacionados

- [02-Functions](./02-functions.md)
- [04-Triggers](./04-triggers.md) *(Inglês apenas)*
- [05-Correlated Queries & Error Handling](../03-advanced-tsql/05-correlated-queries-error-handling.md) *(Inglês apenas)*

---

## Documentação Oficial

- [Stored Procedures (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/stored-procedures/stored-procedures-database-engine)
- [EXECUTE AS (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/execute-as-transact-sql)
- [sp_executesql (Transact-SQL)](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-executesql-transact-sql)
- [Natively Compiled Stored Procedures](https://learn.microsoft.com/en-us/sql/relational-databases/in-memory-oltp/natively-compiled-stored-procedures)

---

**[← Anterior](./02-functions.md) | [↑ Voltar para a Seção](./programmability-objects.md) | [Lab: Stored Procedures](../../practice/labs/02-programmability-objects/03-stored-procedures-lab.sql) | [Próximo →](./04-triggers.md)**
