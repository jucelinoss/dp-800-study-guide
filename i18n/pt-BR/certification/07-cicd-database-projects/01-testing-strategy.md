---
title: Estratégias de Testes para Projetos de Banco de Dados SQL (Testing Strategy for SQL Database Projects)
type: study-material
tags:
  - dp-800
  - testing
  - unit-tests
  - integration-tests
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. O Framework de Testes Unitários tSQLt](#o-framework-de-testes-unitários-tsqlt)
>   - 🔹 [Preparando o Ambiente e Instalando o tSQLt](#preparando-o-ambiente-e-instalando-o-tsqlt)
>   - 🔹 [Criando Classes de Testes](#criando-classes-de-testes)
>   - 🔹 [Escrevendo um Teste Unitário Simples](#escrevendo-um-teste-unitário-simples)
>   - 🔹 [Isolamento com FakeTable](#isolamento-com-faketable)
>   - 🔹 [Comparando Conjuntos de Dados com AssertEqualsTable](#comparando-conjuntos-de-dados-com-assertequalstable)
>   - 🔹 [Mockando Funções e Procedures (FakeFunction / SpyProcedure)](#mockando-funções-e-procedures-fakefunction-spyprocedure)
>   - 🔹 [Executando Testes do tSQLt](#executando-testes-do-tsqlt)
> - 📍 [3. Testes de Integração (Integration Tests)](#testes-de-integração-integration-tests)
> - 📍 [4. Gestão de Dados Estáticos e Referenciais (Static / Reference Data)](#gestão-de-dados-estáticos-e-referenciais-static-reference-data)
>   - 🔹 [Idempotência em Scripts com MERGE](#idempotência-em-scripts-com-merge)
>   - 🔹 [Scripts de Pós-Implantação (Post-Deployment Scripts)](#scripts-de-pós-implantação-post-deployment-scripts)
> - 📍 [5. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [6. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [7. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [8. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [9. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [10. Documentação Oficial](#documentação-oficial)
---

# Estratégias de Testes para Projetos de Banco de Dados SQL (Testing Strategy for SQL Database Projects)

## Visão Geral (Overview)

Uma estratégia robusta de testes para bancos de dados mescla testes unitários (unit tests - rápidos, isolados e baseados em dados falsificados / mockados) com testes de integração (integration tests - de ponta a ponta, simulando fluxos transacionais reais). O framework **tSQLt** é o padrão consagrado para testes unitários em T-SQL, enquanto dados estáticos ou referenciais devem ser versionados e implantados de forma idempotente junto com os schemas.

> [!abstract]
>
> - Cobre abordagens de testes de códigos SQL: testes unitários (tSQLt), testes de integração e testes transacionais.
> - O framework tSQLt executa testes baseados em T-SQL e os envolve em transações que são desfeitas de forma automática ao término de cada teste.
> - Tópicos chave do exame: mecanismos de isolamento do tSQLt (fakes/mocks) e funções de validação de asserções (assertions).

> [!tip] O que o Exame Testa
>
> - Testes tSQLt rodam **dentro de transações que sofrem ROLLBACK automático** no final — garantindo que a base de testes nunca acumule lixo ou sofra alterações permanentes de dados.
> - O comando `tSQLt.FakeTable` substitui tabelas reais por cópias vazias e sem restrições lógicas para isolar testes de dependências de chaves.
> - As asserções principais são regidas pelas funções: `tSQLt.AssertEquals`, `tSQLt.AssertEqualsTable` e `tSQLt.ExpectException`.

---

## O Framework de Testes Unitários tSQLt

O **tSQLt** roda inteiramente dentro da instância do SQL Server. Os testes são organizados em schemas de banco que funcionam como classes de teste (test classes), onde cada teste individual é implementado na forma de uma stored procedure cujo nome deve obrigatoriamente iniciar com o termo "test".

### Preparando o Ambiente e Instalando o tSQLt

```sql
-- tSQLt requer a integração CLR.
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;

-- Em SQL Server 2017 ou posterior, 'clr strict security' é habilitado
-- por padrão. Siga o processo de instalação do framework para confiar
-- na assembly; não habilite TRUSTWORTHY como configuração padrão.

-- Validar a instalação rodando o info do framework
EXEC tSQLt.Info;
```

> [!important] Requisitos de Sistema para Executar o tSQLt
>
> - O framework **tSQLt** baseia-se em lógica executada através de código CLR (.NET).
> - **Cuidado de Configuração**: O recurso `clr enabled` deve estar ativado no SQL Server. Em SQL Server 2017 ou posterior, `clr strict security` é habilitado por padrão; `TRUSTWORTHY ON` não é um pré-requisito geral e não deve ser adotado como configuração padrão, pois amplia a superfície de segurança. Siga o processo de confiança da assembly indicado pelo framework e pelas políticas da organização. O tSQLt executa testes de forma síncrona dentro de transações que sofrem rollback automático ao término de cada teste, garantindo isolamento de dados.

### Criando Classes de Testes

```sql
-- Uma classe de teste é um Schema marcado com a propriedade estendida do tSQLt
EXEC tSQLt.NewTestClass 'OrderTests';

-- O comando acima equivale a executar de forma declarativa:
CREATE SCHEMA [OrderTests];
GO
EXEC sp_addextendedproperty
    @name = N'tSQLt.TestClass',
    @value = 1,
    @level0type = N'SCHEMA',
    @level0name = N'OrderTests';
```

### Escrevendo um Teste Unitário Simples

```sql
-- Teste de validação lógica de retorno da função CalculateOrderTotal
CREATE OR ALTER PROCEDURE [OrderTests].[test CalculateOrderTotal retorna soma correta]
AS
BEGIN
    -- Arrange (Preparar): Mockar tabelas reais de dependência
    EXEC tSQLt.FakeTable 'dbo.Orders';
    EXEC tSQLt.FakeTable 'dbo.OrderItems';

    INSERT INTO dbo.Orders (OrderId, CustomerId) VALUES (1, 100);
    INSERT INTO dbo.OrderItems (OrderId, Quantity, UnitPrice)
    VALUES (1, 2, 10.00), (1, 1, 25.00);

    -- Act (Executar): Invocar a função sob teste
    DECLARE @result DECIMAL(10,2);
    SELECT @result = dbo.CalculateOrderTotal(1);

    -- Assert (Validar): Validar se o retorno condiz com o esperado
    EXEC tSQLt.AssertEquals 45.00, @result;
END;
```

### Isolamento com FakeTable

O comando `FakeTable` cria uma cópia da tabela sem constraints de integridade referencial, triggers ou índices. Isso permite preencher a tabela fake sem a obrigação de alimentar chaves estrangeiras ou passar por regras CHECK de outras tabelas.

```sql
CREATE OR ALTER PROCEDURE [OrderTests].[test impede a inserção de produtos duplicados]
AS
BEGIN
    -- FakeTable remove constraints para isolar a tabela no teste unitário
    EXEC tSQLt.FakeTable 'dbo.Products';

    INSERT INTO dbo.Products (ProductId, Name, Price) VALUES (1, 'Widget', 9.99);

    -- Restaurar a constraint PK na tabela fake para testar o comportamento de integridade
    EXEC tSQLt.ApplyConstraint 'dbo.Products', 'PK_Products';

    -- Configurar o teste para esperar uma exceção de chave duplicada
    EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%PRIMARY KEY%';
    INSERT INTO dbo.Products (ProductId, Name, Price) VALUES (1, 'Duplicate', 5.00);
END;
```

> [!tip] Como Funciona o FakeTable no tSQLt?
>
> - A instrução `tSQLt.FakeTable 'dbo.MinhaTabela'` renomeia temporariamente a tabela original e cria em seu lugar uma tabela idêntica falsa **sem restrições (constraints), triggers ou chaves estrangeiras (foreign keys)**.
> - Isso permite inserir dados mockados simplificados ignorando dependências integras de chaves. Caso queira testar uma constraint específica na tabela fake, utilize `EXEC tSQLt.ApplyConstraint` logo em seguida.

### Comparando Conjuntos de Dados com AssertEqualsTable

```sql
CREATE OR ALTER PROCEDURE [OrderTests].[test GetActiveOrders retorna somente ativos]
AS
BEGIN
    EXEC tSQLt.FakeTable 'dbo.Orders';

    INSERT INTO dbo.Orders (OrderId, Status, CustomerId)
    VALUES (1, 'Active', 10), (2, 'Closed', 10), (3, 'Active', 20);

    -- Criar tabela de retorno esperado
    CREATE TABLE #Expected (OrderId INT, Status NVARCHAR(20), CustomerId INT);
    INSERT INTO #Expected VALUES (1, 'Active', 10), (3, 'Active', 20);

    -- Criar tabela temporária de resultados reais obtidos
    CREATE TABLE #Actual (OrderId INT, Status NVARCHAR(20), CustomerId INT);
    INSERT INTO #Actual
    EXEC dbo.GetActiveOrders;

    -- Validar a igualdade física de registros das duas tabelas
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
END;
```

### Mockando Funções e Procedures (FakeFunction / SpyProcedure)

```sql
-- SpyProcedure intercepta e loga chamadas sem executar a procedure original
EXEC tSQLt.SpyProcedure 'dbo.SendEmailNotification';

-- O tSQLt cria uma tabela de log automática no padrão: [ProcedureName]_SpyProcedureLog
-- Após rodar o código, valide se a procedure dependente foi chamada
SELECT * FROM dbo.SendEmailNotification_SpyProcedureLog;

-- FakeFunction substitui funções por lógicas mockadas com retornos predeterminados
EXEC tSQLt.FakeFunction 'dbo.GetCurrentRate', 'OrderTests.FakeGetCurrentRate';
```

### Executando Testes do tSQLt

```sql
-- Executar todos os testes de uma classe
EXEC tSQLt.Run 'OrderTests';

-- Executar um teste individual específico
EXEC tSQLt.Run 'OrderTests.[test CalculateOrderTotal retorna soma correta]';

-- Executar todos os testes existentes na base
EXEC tSQLt.RunAll;

-- Mapear os retornos como XML para pipelines de CI/CD
EXEC tSQLt.SetTestResultFormatter 'tSQLt.XmlResultFormatter';
EXEC tSQLt.RunAll;
```

---

## Testes de Integração (Integration Tests)

Os testes de integração verificam a coexistência e o tráfego lógico correto entre objetos contendo constraints de chaves e triggers ativas de forma real:

```sql
-- Teste de Integração validando integridade no fluxo de pedidos
CREATE OR ALTER PROCEDURE [IntegrationTests].[test fluxo completo de gravacao de pedidos]
AS
BEGIN
    BEGIN TRANSACTION;
    BEGIN TRY
        -- Tabelas reais ativas (Sem FakeTable) para validar as triggers e chaves estrangeiras
        DECLARE @CustomerId INT = 9999;
        DECLARE @OrderId INT;

        INSERT INTO dbo.Customers (CustomerId, Name, Email)
        VALUES (@CustomerId, 'Test Customer', 'test@example.com');

        EXEC dbo.CreateOrder
            @CustomerId = @CustomerId,
            @ProductId = 1,
            @Quantity = 3,
            @OrderId = @OrderId OUTPUT;

        DECLARE @Status NVARCHAR(20);
        SELECT @Status = Status FROM dbo.Orders WHERE OrderId = @OrderId;

        EXEC tSQLt.AssertEquals 'Pending', @Status;

        DECLARE @StockAfter INT;
        SELECT @StockAfter = StockQuantity FROM dbo.Products WHERE ProductId = 1;
        EXEC tSQLt.AssertNotEquals 0, @StockAfter;

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    -- Garantir o Rollback transacional para limpar o banco
    ROLLBACK TRANSACTION;
END;
```

---

## Gestão de Dados Estáticos e Referenciais (Static / Reference Data)

Os dados estáticos (tabelas de lookup, domínio, parametrizações) devem ser versionados e gerenciados via código juntamente com as definições de DDL das tabelas.

### Idempotência em Scripts com MERGE

```sql
-- MERGE pode tornar o script reexecutável; valide concorrência,
-- chaves únicas e o efeito da cláusula DELETE antes do deploy.
MERGE INTO dbo.OrderStatus AS target
USING (VALUES
    (1, 'Pending',   'Order received, awaiting processing'),
    (2, 'Active',    'Order being processed'),
    (3, 'Shipped',   'Order shipped to customer'),
    (4, 'Delivered', 'Order delivered'),
    (5, 'Cancelled', 'Order cancelled')
) AS source (StatusId, StatusName, Description)
ON target.StatusId = source.StatusId
WHEN MATCHED THEN
    UPDATE SET
        target.StatusName  = source.StatusName,
        target.Description = source.Description
WHEN NOT MATCHED BY TARGET THEN
    INSERT (StatusId, StatusName, Description)
    VALUES (source.StatusId, source.StatusName, source.Description)
WHEN NOT MATCHED BY SOURCE THEN
    DELETE; -- Remove do banco registros que sumiram do arquivo fonte (Cuidado!)
```

> [!warning] Dica de Exame: Idempotência com MERGE
>
> - Ao implantar dados estáticos/referenciais, use scripts idempotentes e teste-os no ambiente-alvo.
> - `MERGE` pode ser apropriado para uma origem controlada, mas exige testes de concorrência, chaves únicas e de todos os caminhos de alteração. A cláusula `WHEN NOT MATCHED BY SOURCE THEN DELETE` só é segura quando a origem é autoritativa e completa.

### Scripts de Pós-Implantação (Post-Deployment Scripts)

Os dados estáticos devem ser acionados no final do processo por meio do arquivo `Post-Deployment` dos projetos de bancos de dados:

```sql
-- PostDeployment.sql (Roda ao término da implantação do schema DDL)
PRINT 'Carregando dados de lookup referenciais...';

:r .\Data\ReferenceData\dbo.OrderStatus.data.sql
:r .\Data\ReferenceData\dbo.Countries.data.sql
:r .\Data\ReferenceData\dbo.Currencies.data.sql

PRINT 'Carga de dados referenciais concluída.';
```

---

## Problemas Comuns e Soluções (Common Issues)

| Sintoma | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Erro `CLR not enabled` ao instalar tSQLt | Permissão CLR desativada no SQL Server | Execute a procedure `sp_configure 'clr enabled', 1` no banco master. |
| Testes unitários falham por chaves órfãs | Ausência de isolamento em tabelas de dependência | Utilize a instrução `tSQLt.FakeTable` para as tabelas relacionadas. |
| Linhas duplicadas após implantação | Script de seed estático sem validação | Use uma estrutura idempotente; avalie `MERGE` somente após testar concorrência e unicidade. |
| Falhas intermitentes em ambientes de staging | Testes anteriores não executaram Rollback | Certifique-se de que os scripts envolvam transações limpas com `ROLLBACK`. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - O tSQLt executa testes unitários baseados inteiramente em **Stored Procedures** no banco; ele não exige instaladores ou executáveis externos no pipeline.
> - O comando `FakeTable` remove índices, constraints e triggers para simplificar a preparação de dados simulados (mocks).
> - Use a instrução `ApplyConstraint` se precisar validar regras de check ou PK/FK específicas em tabelas fakes.
> - Os scripts de **Post-Deployment** (`Post-Deployment Scripts`) são a localização técnica correta para incluir inserts e merges de dados referenciais estáticos no SSDT.

---

## Resumo dos Conceitos (Key Takeaways)

- Testes unitários do tSQLt isolam códigos eliminando restrições através de tabelas fakes.
- Os testes rodam de forma síncrona dentro de transações revertidas por Rollback.
- Mantenha tabelas de lookups e parametrizações versionadas e implantadas via comandos idempotentes; use `MERGE` somente após validar concorrência, unicidade e exclusões.
- Gerencie cargas estáticas integrando scripts de carga na fase de Post-Deployment dos pacotes.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Você está configurando uma pipeline de CI/CD para compilar e implantar um projeto de banco de dados do SQL Server. A tabela `dbo.OrderTypes` armazena dados estáticos de tipos de ordens que as aplicações consultam. Você precisa garantir que novas linhas inseridas no controle de versão sejam implantadas de forma automática na pipeline sem gerar duplicidades ou falhas de chaves se rodado várias vezes. Onde você deve colocar o script e qual sintaxe deve utilizar?

A. Criar um script de Pre-Deployment utilizando inserções diretas (`INSERT INTO`).

B. Criar um script de Post-Deployment utilizando a instrução `MERGE`.

C. Criar um teste unitário no tSQLt usando `tSQLt.FakeTable`.

D. Executar comandos de carga manual no pipeline do Azure DevOps usando SqlPackage.

> [!success]- Resposta
> **B — Criar um script de Post-Deployment utilizando a instrução `MERGE`**
>
> Em projetos de banco de dados SQL (SSDT), os scripts de Post-Deployment são executados após a atualização completa das estruturas de schemas (tabelas e views). O uso de `MERGE` provê a idempotência necessária para atualizar, inserir ou deletar registros de lookups estáticos sem violar chaves lógicas caso a pipeline seja disparada repetidas vezes.

---

## Tópicos Relacionados

- [02-Projetos de Banco de Dados SQL](./02-sql-database-projects.md)
- [03-Controle de Versão & Branching](./03-source-control-branching.md) *(Inglês apenas)*
- [04-Pipelines de Implantação](./04-deployment-pipelines.md) *(Inglês apenas)*

---

## Documentação Oficial

- [tSQLt Framework](https://tsqlt.org/full-user-guide/)
- [MERGE (T-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql)
- [SQL Database Projects - Post-Deployment Scripts](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-projects-overview)

---

**[↑ Voltar para a Seção](./cicd-database-projects.md) | [Lab: Estrategia de Testes](../../practice/labs/07-cicd-database-projects/01-testing-strategy-lab.sql) | [Next →](./02-sql-database-projects.md)**
