---
title: Triggers
type: study-material
tags:
  - dp-800
  - triggers
  - dml-triggers
  - ddl-triggers
  - instead-of
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. DML Triggers](#dml-triggers)
>   - 🔹 [AFTER Triggers](#after-triggers)
>   - 🔹 [INSTEAD OF Triggers](#instead-of-triggers)
>   - 🔹 [INSTEAD OF Triggers sobre Views](#instead-of-triggers-sobre-views-instead-of-triggers-on-views)
> - 📍 [3. DDL & Logon Triggers](#ddl-triggers)
>   - 🔹 [DDL Triggers](#ddl-triggers)
>   - 🔹 [Logon Triggers](#logon-triggers)
>   - 🔹 [Ordem de Execução & Gerenciamento](#ordem-de-execucao-de-triggers)
> - 📍 [4. Aplicação Prática & Síntese](#casos-de-uso-use-cases)
>   - 🔹 [Casos de Uso](#casos-de-uso-use-cases)
>   - 🔹 [Problemas Comuns e Soluções](#problemas-comuns-e-solucoes-common-issues)
>   - 🔹 [Melhores Práticas](#melhores-praticas-best-practices)
>   - 🔹 [Dicas para o Exame](#dicas-para-o-exame-exam-tips)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)

---

# Triggers

## Visão Geral (Overview)

Os Triggers são Stored Procedures especiais executadas automaticamente em resposta a eventos DML (como `INSERT`, `UPDATE` e `DELETE`) ou eventos DDL (como `CREATE`, `ALTER` e `DROP`). São amplamente utilizados para auditorias de tabelas, aplicação de regras de validação lógica complexas e atualização automática de dados agregados ou redundantes.

> [!abstract]
>
> - Cobre DML Triggers (AFTER, INSTEAD OF), DDL Triggers e o comportamento das tabelas virtuais `INSERTED`/`DELETED`.
> - Os Triggers disparam de forma transparente em resposta a alterações de dados ou do esquema físico do banco.
> - Tópicos chave do exame: diferenças operacionais de AFTER vs INSTEAD OF, conteúdo das tabelas temporárias `INSERTED` e `DELETED` em comandos `UPDATE`, e o escopo de atuação de DDL Triggers.

> [!tip] O que o Exame Testa
>
> - O trigger do tipo **`AFTER`** dispara **após** a instrução DML original ser bem-sucedida e validada pelas constraints; o trigger **`INSTEAD OF`** dispara **no lugar** da DML correspondente (ou seja, a operação DML original não executa no banco de forma automática).
> - Em gatilhos de `UPDATE`: a tabela virtual `INSERTED` contém os **novos** valores atualizados; a tabela virtual `DELETED` armazena os valores **antigos** (pré-update) — ambas as estruturas são populadas em tempo de execução.
> - Gatilhos `INSTEAD OF` associados a Views viabilizam a execução de DMLs de gravação sobre Views complexas não atualizáveis nativamente (ex: Views contendo joins de várias tabelas).

---

## DML Triggers

### AFTER Triggers

Os AFTER Triggers disparam apenas após a conclusão da operação DML correspondente e depois de toda a validação de constraints de banco. Eles têm acesso local às tabelas virtuais do sistema `inserted` e `deleted`.

```sql
CREATE TRIGGER trg_Orders_Audit
ON dbo.Orders
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Registrar inserções
    INSERT INTO dbo.OrderAudit (OrderId, Action, ChangedAt, ChangedBy)
    SELECT i.OrderId, 'INSERT', GETUTCDATE(), SUSER_SNAME()
    FROM inserted i
    WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.OrderId = i.OrderId);

    -- Registrar atualizações
    INSERT INTO dbo.OrderAudit (OrderId, Action, ChangedAt, ChangedBy)
    SELECT i.OrderId, 'UPDATE', GETUTCDATE(), SUSER_SNAME()
    FROM inserted i
    WHERE EXISTS (SELECT 1 FROM deleted d WHERE d.OrderId = i.OrderId);

    -- Registrar deleções
    INSERT INTO dbo.OrderAudit (OrderId, Action, ChangedAt, ChangedBy)
    SELECT d.OrderId, 'DELETE', GETUTCDATE(), SUSER_SNAME()
    FROM deleted d
    WHERE NOT EXISTS (SELECT 1 FROM inserted i WHERE i.OrderId = d.OrderId);
END;
```

**Comportamento das tabelas inserted e deleted:**

| Operação DML | `inserted` | `deleted` |
| :--- | :--- | :--- |
| INSERT | Contém os novos registros inseridos. | Vazia (Empty) |
| DELETE | Vazia (Empty) | Contém as linhas antigas excluídas. |
| UPDATE | `Novos valores informados` | Valores antigos anteriores à atualização |

> [!important] Cuidado de Performance: Triggers rodam na mesma transação
>
> - Todos os DML Triggers (seja AFTER ou INSTEAD OF) executam **dentro da mesma transação do comando que os disparou**.
> - Como o trigger só termina junto com a transação principal, qualquer consulta demorada, loop ou espera dentro dele mantém locks e outros recursos por mais tempo. Isso aumenta a chance de *blocking*, deadlocks e degradação de concorrência. Portanto, mantenha o trigger curto, com lógica *set-based*; para trabalho pesado, grave o evento em uma fila/tabela e processe-o de forma assíncrona.

### INSTEAD OF Triggers

Os INSTEAD OF Triggers interceptam e substituem por completo a operação DML disparada — são comuns sobre Views complexas ou para processar validações rígidas antes de persistir os dados fisicamente.

```sql
-- Trigger INSTEAD OF INSERT aplicado sobre uma View que une duas tabelas base
CREATE TRIGGER trg_vw_CustomerOrders_Insert
ON dbo.vw_CustomerOrders
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Inserir novo cliente caso não exista
    INSERT INTO dbo.Customers (Name)
    SELECT DISTINCT CustomerName FROM inserted
    WHERE CustomerName NOT IN (SELECT Name FROM dbo.Customers);

    -- Inserir o pedido vinculando ao respectivo cliente
    INSERT INTO dbo.Orders (CustomerId, OrderDate, TotalAmount)
    SELECT c.CustomerId, i.OrderDate, i.TotalAmount
    FROM inserted i
    JOIN dbo.Customers c ON c.Name = i.CustomerName;
END;
```

> [!warning] Erro Comum
> Na presença de um trigger do tipo INSTEAD OF, a instrução DML original enviada pelo usuário NÃO executa. Cabe ao código de dentro do Trigger realizar explicitamente as inserções, exclusões ou atualizações reais nas tabelas base, caso contrário a alteração pretendida se perde silenciosamente.

---

## INSTEAD OF Triggers sobre Views (INSTEAD OF Triggers on Views)

Views com joins permitem, em alguns casos, `UPDATE` de colunas de uma única tabela base, mas não permitem `INSERT` ou `DELETE` se referenciam mais de uma tabela. Views com agregações não são atualizáveis diretamente. Um trigger `INSTEAD OF` pode interceptar o comando e rotear os dados manualmente às tabelas de origem.

Regras de funcionamento:

- O gatilho roda **no lugar** da DML — a instrução que disparou o trigger nunca é executada no banco.
- Você deve escrever explicitamente as instruções de escrita (`INSERT`/`UPDATE`/`DELETE`) apontando para as tabelas físicas no corpo do trigger.
- Suporta as variantes: `INSTEAD OF INSERT`, `INSTEAD OF UPDATE` e `INSTEAD OF DELETE`.
- Como a instrução DML original é substituída, as constraints relevantes são as das instruções de escrita executadas dentro do trigger.

```sql
-- View unindo duas tabelas (não aceita DML direto)
CREATE VIEW vw_OrderDetails
AS SELECT o.OrderID, o.TotalAmount, c.Name, c.Email
   FROM Orders o JOIN Customers c ON o.CustomerID = c.CustomerID;
GO

-- Trigger INSTEAD OF INSERT na View
CREATE TRIGGER trg_IOI_OrderDetails
ON vw_OrderDetails
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    -- Primeiro, inserir o cliente se necessário
    INSERT INTO Customers (Name, Email)
    SELECT i.Name, i.Email FROM inserted i
    WHERE NOT EXISTS (SELECT 1 FROM Customers c WHERE c.Email = i.Email);

    -- Segundo, inserir o pedido associando a ID gerada
    INSERT INTO Orders (CustomerID, TotalAmount)
    SELECT c.CustomerID, i.TotalAmount
    FROM inserted i
    JOIN Customers c ON c.Email = i.Email;
END;
```

---

## DDL Triggers

Os DDL Triggers são disparados em resposta a alterações na estrutura física do banco de dados (schema changes) — muito empregados para auditoria ou para travar modificações estruturais indesejadas em produção.

```sql
-- No nível do servidor (Server-level): impede exclusão de bancos
CREATE TRIGGER trg_PreventDatabaseDrop
ON ALL SERVER
FOR DROP_DATABASE
AS
BEGIN
    PRINT 'A exclusão de bancos de dados é proibida.';
    ROLLBACK;
END;
GO

-- No nível do banco (Database-level): auditoria de tabelas
CREATE TRIGGER trg_AuditTableCreate
ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE
AS
BEGIN
    DECLARE @EventData xml = EVENTDATA();

    INSERT INTO dbo.SchemaChangeLog (EventType, ObjectName, ChangedAt, ChangedBy)
    VALUES (
        @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'nvarchar(100)'),
        @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'nvarchar(200)'),
        GETUTCDATE(),
        SUSER_SNAME()
    );
END;
GO
```

### Características de DDL Triggers

- **Escopo**: Escopo do banco de dados (`ON DATABASE`) ou do servidor de banco inteiro (`ON ALL SERVER`).
- **Eventos Comuns**: `CREATE_TABLE`, `ALTER_TABLE`, `DROP_TABLE`, `CREATE_PROCEDURE`, `ALTER_PROCEDURE`, `DROP_PROCEDURE`.
- **A função `EVENTDATA()`**: Retorna uma estrutura em formato XML contendo detalhes ricos sobre o evento (nome do objeto, tipo do evento, comando T-SQL executado, horário e conta de login).

```sql
-- Impedir o drop de tabelas na base de Produção
CREATE TRIGGER trg_PreventDrop
ON DATABASE
FOR DROP_TABLE
AS
BEGIN
    PRINT 'A exclusão de tabelas é proibida. Contate o time de DBA.';
    ROLLBACK;
END;
GO

-- Logar alterações de DDL em tabela de histórico
CREATE TRIGGER trg_AuditDDL
ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE
AS
BEGIN
    INSERT INTO DDLAuditLog (EventType, ObjectName, LoginName, EventTime, EventData)
    SELECT
        EVENTDATA().value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(200)'),
        EVENTDATA().value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(200)'),
        GETUTCDATE(),
        EVENTDATA();
END;
GO
```

---

## Ordem de Execução de Triggers

Quando existem múltiplos gatilhos configurados para o mesmo evento de DML sobre a mesma tabela, utilize a procedure de sistema `sp_settriggerorder` para especificar qual gatilho deve rodar primeiro (`First`) e qual deve ser o último (`Last`). Gatilhos intermediários rodam em ordem arbitrária determinada pelo engine.

- **Gatilhos aninhados (Nested triggers)**: Ocorre quando a execução DML de um trigger dispara um trigger secundário em outra tabela (limite físico de até 32 níveis de aninhamento).
- **Gatilhos recursivos (Recursive triggers)**: Ocorre quando um DML de dentro do gatilho altera a mesma tabela T que o disparou original, re-invocando a si mesmo. Desabilitado por padrão (`RECURSIVE_TRIGGERS OFF`).
- **Limite máximo**: O estouro do limite de 32 níveis gera falha e aborta toda a transação com rollback.

```sql
-- Definir ordem de execução do trigger
EXEC sp_settriggerorder
    @triggername = 'trg_AuditUpdate',
    @order = 'First',
    @stmttype = 'UPDATE';

-- Verificar se a recursividade está ativa
SELECT name, is_recursive_triggers_on
FROM sys.databases WHERE name = DB_NAME();
```

> [!warning] Estouro do Limite de Aninhamento (Nested Triggers)
>
> - O SQL Server permite aninhamento de triggers até um limite rígido de **32 níveis**.
> - Se o trigger da Tabela A insere na Tabela B, que dispara outro para a C, e assim por diante até exceder 32 níveis (ou em caso de loop infinito indireto), o banco interrompe a execução com erro e desfaz toda a transação (`ROLLBACK`).

---

## Logon Triggers

> [!important] Disponibilidade
>
> Logon Triggers são suportados no SQL Server e no Azure SQL Managed Instance. Não são suportados no Azure SQL Database nem no Microsoft Fabric.

Os Logon Triggers possuem escopo do servidor e disparam quando uma sessão de login do SQL Server é solicitada (imediatamente após a autenticação com sucesso, mas antes do canal de comunicação do usuário ser estabelecido e liberado).

- **Escopo**: Nível do servidor — definidos com a cláusula `ON ALL SERVER`.
- **Aplicações**: Restringir logins de usuários fora do horário comercial, auditar tentativas de conexão ou bloquear conexões com base em IPs específicos.
- A invocação do comando **`ROLLBACK`** dentro de um Logon Trigger aborta o processo, desconectando o usuário imediatamente.
- Logon Triggers não utilizam as tabelas temporárias `inserted`/`deleted`; as informações devem ser capturadas via `EVENTDATA()` ou `ORIGINAL_LOGIN()`.

```sql
-- Restringir logins fora do horário comercial (Seg-Sex, 08:00 às 18:00)
CREATE TRIGGER trg_RestrictLoginHours
ON ALL SERVER
FOR LOGON
AS
BEGIN
    DECLARE @Hour int = DATEPART(HOUR, GETDATE());
    DECLARE @Weekday int = DATEPART(WEEKDAY, GETDATE());

    -- DATEPART(WEEKDAY) depende de SET DATEFIRST; ajuste os valores abaixo à configuração do servidor.
    IF @Weekday IN (1, 7) OR @Hour < 8 OR @Hour >= 18
    BEGIN
        IF ORIGINAL_LOGIN() <> 'sa' -- ignorar conta sa para acessos administrativos de emergência
        BEGIN
            PRINT 'Logins são permitidos apenas de Seg a Sex, das 08:00 às 18:00.';
            ROLLBACK;
        END;
    END;
END;
GO
```

> [!caution] Perigo Crítico de Bloqueio Geral (Lockout)
>
> - Um erro lógico ou falha de sintaxe em um Logon Trigger pode **bloquear todas as conexões de entrada do SQL Server**, incluindo logins administrativos.
> - Se isso ocorrer, um membro de `sysadmin` pode usar a **DAC (Dedicated Administrator Connection)** ou iniciar o Database Engine em configuração mínima para desabilitar ou remover o trigger.

---

## Gerenciamento de Triggers (Managing Triggers)

```sql
-- Desabilitar um trigger
DISABLE TRIGGER trg_Orders_Audit ON dbo.Orders;

-- Habilitar um trigger
ENABLE TRIGGER trg_Orders_Audit ON dbo.Orders;

-- Desabilitar todos os triggers de uma tabela
DISABLE TRIGGER ALL ON dbo.Orders;

-- Visualizar o código DDL de criação do trigger
SELECT definition FROM sys.sql_modules
WHERE object_id = OBJECT_ID('trg_Orders_Audit');
```

---

## Casos de Uso (Use Cases)

- **Auditoria de Tabelas**: Rastrear autores, modificações e timestamps de forma transparente sem alterar o código dos sistemas.
- **Regras Lógicas Avançadas**: Garantir validações complexas que superem os recursos lógicos das CHECK constraints.
- **Sincronização de Estatísticas e Agregações**: Manutenção de colunas pré-calculadas ou tabelas resumo em tempo real.
- **DML em Views**: Permitir operações de escrita em Views complexas de multi-tabelas.
- **Governança do Banco**: Triggers DDL para evitar exclusões e alterações acidentais de tabelas em ambientes produtivos.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| O trigger falha ou age apenas na primeira linha em DMLs com múltiplos registros | Escrita de código assumindo linha única (uso de `SELECT TOP 1` ou variáveis escalares) | `Escreva código orientado a conjuntos (set-based) varrendo todas as linhas de `inserted`/`deleted``. |
| Loop de recursão infinita | O trigger dispara comandos DML que chamam a si próprio | Avalie o parâmetro `is_recursive` e desligue a propriedade no banco. |
| Gargalo de desempenho | Lógica pesada e síncrona rodando em DMLs | Mova processamentos demorados para rotinas assíncronas (Service Broker, filas). |
| Logon trigger bloqueou o acesso geral ao banco | Falha de sintaxe ou de lógica interna com `ROLLBACK` geral | Acesse o servidor utilizando a Conexão de Administrador Dedicada (DAC: `admin:`) para desabilitar o trigger. |

---

## Melhores Práticas (Best Practices)

- **Sempre assuma DMLs multi-linhas**: `inserted` e `deleted` podem conter zero, uma ou milhares de linhas em uma única instrução. Código baseado em variáveis escalares, `TOP (1)` ou loops pode ignorar linhas e corromper regras de negócio; prefira uma única operação *set-based* que trate todo o conjunto.
- **Mantenha a lógica curta**: O trigger participa da transação do DML que o disparou. Consultas lentas, loops e esperas prolongam locks, aumentam *blocking* e deadlocks e atrasam a confirmação da operação do usuário. Para trabalho pesado, registre o evento e processe-o de forma assíncrona.
- **Adote `SET NOCOUNT ON`**: Cada DML interno pode emitir mensagens de “N linhas afetadas”. Elas não são o resultado de negócio, aumentam tráfego e podem confundir clientes, APIs ou procedures que esperam uma única contagem; `NOCOUNT` elimina esse ruído.
- **Evite recursividade de gatilhos**: Um DML executado pelo próprio trigger pode dispará-lo novamente e repetir a cadeia até o limite de aninhamento ou até uma falha. Projete para não atualizar a mesma tabela sem necessidade e, quando a regra exigir, controle a recursividade com `ALTER DATABASE SET RECURSIVE_TRIGGERS OFF` e verificações explícitas.
- **Teste Logon Triggers com rigor**: Eles executam antes de a sessão do usuário ser estabelecida. Um erro de sintaxe, uma dependência indisponível ou um `ROLLBACK` indevido pode bloquear praticamente todos os logins; mantenha uma rota de recuperação, como DAC e uma conta administrativa excluída da regra.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - Gatilhos do tipo `AFTER` rodam **depois das constraints** — se um CHECK ou FK falhar, o trigger não é disparado.
> - Gatilhos do tipo `INSTEAD OF` interceptam e substituem o DML original; as constraints são avaliadas nas instruções de escrita executadas pelo próprio trigger.
> - A função `EVENTDATA()` retorna os detalhes dos eventos estruturados em formato XML.
> - Operações DML de escrita sobre Views complexas exigem a criação de um trigger **INSTEAD OF** na View — triggers do tipo AFTER não resolvem essa limitação relacional.
> - Logon triggers são de escopo do servidor (`ON ALL SERVER`) e encerram sessões retornando `ROLLBACK`.
> - A procedure `sp_settriggerorder` define o trigger inicial (`First`) e o final (`Last`) para um mesmo evento.

---

## Resumo dos Conceitos (Key Takeaways)

- `inserted` = novos dados; `deleted` = dados antigos; ambos são preenchidos nas operações de `UPDATE`.
- O trigger `INSTEAD OF` em Views viabiliza suportar DMLs em visualizações lógicas de múltiplas tabelas.
- Triggers DDL auditam e bloqueiam modificações na estrutura de tabelas e procedures usando `EVENTDATA()`.
- O limite máximo de aninhamento de gatilhos é de 32 níveis.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma View une os dados das tabelas `Orders` e `Customers`. Um usuário tenta submeter um comando `INSERT` contra esta View, porém recebe um erro do banco informando que o objeto não aceita inserções diretas. Qual abordagem soluciona essa limitação de escrita?

A. Criar um trigger `AFTER INSERT` sobre a tabela `Orders`.

B. Criar um trigger `INSTEAD OF INSERT` sobre a View correspondente.

C. Implementar um DDL Trigger para o evento `CREATE` na View.

D. Criar um trigger `AFTER INSERT` diretamente na View.

> [!success]- Resposta
> **B — Criar um trigger `INSTEAD OF INSERT` sobre a View correspondente**
>
> Views que envolvem joins de múltiplas tabelas não aceitam DMLs diretos de escrita. A criação de um gatilho `INSTEAD OF INSERT` na View intercepta a inserção e permite rotear os dados manualmente às tabelas base correspondentes. Triggers do tipo `AFTER` (A e D) só rodam após a confirmação da escrita da DML, que nesse caso falha antes. Triggers DDL (C) atuam sobre alterações estruturais, não DMLs de dados.

---

## Tópicos Relacionados

- [03-Stored Procedures](./03-stored-procedures.md)
- [04-Auditing](../05-data-security-compliance/04-auditing.md) *(Inglês apenas)*
- [02-Specialized Tables — Ledger](../01-database-objects/02-specialized-tables.md)

---

## Documentação Oficial

- [DML Triggers (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/triggers/dml-triggers)
- [DDL Triggers (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/triggers/ddl-triggers)
- [Logon Triggers (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/triggers/logon-triggers)

---

**[← Anterior](./03-stored-procedures.md) | [↑ Voltar para a Seção](./programmability-objects.md)**
