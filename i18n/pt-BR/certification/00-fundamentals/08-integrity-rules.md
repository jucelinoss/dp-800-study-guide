---
title: "Regras de Integridade"
type: topic
tags: [sql-server, constraints, keys, fundamentals]
---

# Regras de Integridade

## Visão Geral

Restrições (constraints) mantêm dados inválidos fora do banco de dados, independentemente de qual aplicação os submete. Elas são a primeira linha de defesa para um modelo relacional confiável — uma **salvaguarda no lado do banco de dados** que não pode ser contornada por código de aplicação defeituoso, scripts ad-hoc ou importações de dados.

> [!abstract]
>
> - `PRIMARY KEY` identifica unicamente uma linha e garante não-anulabilidade.
> - `FOREIGN KEY` exige uma linha pai correspondente.
> - `UNIQUE`, `CHECK`, `DEFAULT` e `NOT NULL` expressam regras locais de coluna e tabela.
> - Restrições são nomeadas para que erros sejam compreensíveis na camada de aplicação.

> [!tip] O que o Exame Testa
> Restrições, sequências, colunas identity e suas consequências operacionais aparecem na seção Database Objects. No exame DP-800, espere perguntas baseadas em cenários sobre violações de restrição, ações em cascata e a interação entre `CHECK` e `NULL`.

---

## PRIMARY KEY

Toda tabela deve ter uma chave primária. Ela garante duas regras simultaneamente: **unicidade** e **não-anulabilidade**.

```sql
-- Chave primária de coluna única (clustered por padrão)
CREATE TABLE study.Customer (
    CustomerId   int IDENTITY(1,1) NOT NULL,
    CustomerName nvarchar(100) NOT NULL,
    CONSTRAINT PK_Customer PRIMARY KEY (CustomerId)
);
```

```sql
-- Chave primária composta (duas ou mais colunas)
CREATE TABLE study.OrderItem (
    SalesOrderId int NOT NULL,
    ProductId    int NOT NULL,
    Quantity     smallint NOT NULL,
    CONSTRAINT PK_OrderItem PRIMARY KEY (SalesOrderId, ProductId)
);
```

> [!note]
> No SQL Server, uma chave primária cria um **índice clustered único** por padrão. Isso é uma escolha de armazenamento, não um requisito. Você pode especificar `NONCLUSTERED` na definição da restrição. O modelo conceitual: uma chave primária é uma restrição lógica; o índice é um detalhe de implementação física.

```sql
-- Chave primária com índice nonclustered
CREATE TABLE study.Example (
    Id int NOT NULL,
    CONSTRAINT PK_Example PRIMARY KEY NONCLUSTERED (Id)
);
```

### Diagrama: PK no modelo relacional

```text
study.Customer                         study.SalesOrder
-------------------------------        ---------------------------------
| PK  CustomerId       int   |──┐     | PK  SalesOrderId     int      |
|     CustomerName nvarchar(100)|     | FK  CustomerId       int      |
|     Email      nvarchar(320)|     |     OrderDate         date     |
-------------------------------     |     OrderTotal        decimal  |
                                     ---------------------------------
```

## FOREIGN KEY

Uma chave estrangeira garante que um valor na tabela filha tenha um valor correspondente na chave primária ou restrição única da tabela pai. Impede linhas órfãs.

```sql
-- Chave estrangeira na criação da tabela
CREATE TABLE study.SalesOrder (
    SalesOrderId int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_SalesOrder PRIMARY KEY,
    CustomerId   int NOT NULL,
    OrderDate    date NOT NULL,
    CONSTRAINT FK_SalesOrder_Customer
        FOREIGN KEY (CustomerId) REFERENCES study.Customer(CustomerId)
);
```

Tentar inserir uma linha filha com um valor pai inexistente gera o erro 547:

```sql
-- ERRO 547: violação de FK
INSERT INTO study.SalesOrder (CustomerId, OrderDate, OrderTotal)
VALUES (999, '2026-07-01', 10.00);
-- Msg 547: The INSERT statement conflicted with the FOREIGN KEY constraint.
```

> [!warning] Erro Comum
> Uma chave estrangeira **não** cria automaticamente um índice na coluna filha. A FK protege a integridade referencial; um índice na chave filha é uma decisão separada de performance.

### ON DELETE e ON UPDATE

| Ação | Efeito nas linhas filhas quando o pai é excluído |
| :--- | :--- |
| `NO ACTION` (padrão) | A exclusão falha com erro FK |
| `CASCADE` | As linhas filhas são excluídas automaticamente |
| `SET NULL` | A FK filha é definida como `NULL` (coluna deve ser anulável) |
| `SET DEFAULT` | A FK filha recebe seu valor padrão |

```sql
ALTER TABLE study.SalesOrder
ADD CONSTRAINT FK_SalesOrder_Customer_Cascade
    FOREIGN KEY (CustomerId) REFERENCES study.Customer(CustomerId)
    ON DELETE CASCADE;
```

> [!warning] Erro Comum
> `CASCADE` pode encadear através de múltiplas tabelas. O SQL Server restringe cascateamento a um máximo de 75 níveis. Projete cuidadosamente para evitar exclusões em massa não intencionais.

## Restrição UNIQUE

Uma restrição `UNIQUE` garante que duas linhas não tenham o mesmo valor na(s) coluna(s) especificada(s). Diferentemente de uma chave primária, uma restrição unique **permite um `NULL`** no SQL Server.

```sql
CREATE TABLE study.Customer (
    CustomerId   int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Customer PRIMARY KEY,
    CustomerName nvarchar(100) NOT NULL,
    Email        nvarchar(320) NULL
        CONSTRAINT UQ_Customer_Email UNIQUE
);
```

| Característica | PRIMARY KEY | UNIQUE |
| :--- | :--- | :--- |
| Unicidade garantida | Sim | Sim |
| NULL permitido | Não | Um NULL no SQL Server |
| Índice padrão | Clustered (tipicamente) | Nonclustered |
| Por tabela | Uma | Múltiplas |

```sql
-- UNIQUE composto: cada combinação de valores deve ser única
CREATE TABLE lab.ProductCategory (
    ProductId  int NOT NULL,
    CategoryId int NOT NULL,
    CONSTRAINT UQ_ProductCategory UNIQUE (ProductId, CategoryId)
);
```

## Restrição CHECK

Uma restrição `CHECK` valida se um valor em uma única linha satisfaz uma expressão booleana.

```sql
CREATE TABLE study.Product (
    ProductId   int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Product PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    UnitPrice   decimal(10,2) NOT NULL
        CONSTRAINT CK_Product_UnitPrice CHECK (UnitPrice >= 0)
);
```

Tentar inserir um valor inválido:

```sql
-- ERRO: violação de restrição CHECK
INSERT INTO study.Product (ProductName, UnitPrice)
VALUES (N'Invalid price', -5.00);
-- Msg 547: The INSERT statement conflicted with the CHECK constraint.
```

### CHECK e NULL — a armadilha UNKNOWN

Uma restrição `CHECK` passa quando seu predicado avalia para **TRUE ou UNKNOWN**. Como uma comparação com `NULL` produz `UNKNOWN`, um valor `NULL` passa por um `CHECK` mesmo quando o predicado falharia para um valor real.

```sql
-- Isso passa porque NULL >= 0 avalia para UNKNOWN, não FALSE
CREATE TABLE #TestCheck (
    Val decimal(10,2) NULL CHECK (Val >= 0)
);
INSERT INTO #TestCheck (Val) VALUES (NULL);  -- sucesso
INSERT INTO #TestCheck (Val) VALUES (-5.00); -- falha
DROP TABLE #TestCheck;
```

Se uma coluna nunca deve conter um valor negativo *e* nunca estar ausente, combine `CHECK` com `NOT NULL`.

> [!note] Modelo mental — o segurança
> Pense em cada restrição como um **segurança de balada**. O segurança `PRIMARY KEY` verifica o documento (único + obrigatório). O segurança `FOREIGN KEY` verifica se você está em uma lista de convidados (pai existe). O segurança `CHECK` impõe o código de vestimenta (valor válido). O segurança `UNIQUE` garante que ninguém mais tem o mesmo passe VIP. O segurança `DEFAULT` te dá uma bebida se você não especificar uma. O segurança `NOT NULL` verifica se um campo está preenchido — sem entradas em branco.

## Restrição DEFAULT

Um `DEFAULT` aplica um valor quando uma instrução `INSERT` omite a coluna.

```sql
CREATE TABLE study.Customer (
    CustomerId   int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Customer PRIMARY KEY,
    CustomerName nvarchar(100) NOT NULL,
    IsActive     bit NOT NULL
        CONSTRAINT DF_Customer_IsActive DEFAULT (1),
    CreatedDate  date NOT NULL
        CONSTRAINT DF_Customer_CreatedDate DEFAULT (CAST(SYSDATETIME() AS date))
);
```

```sql
-- Usa default para IsActive e CreatedDate
INSERT INTO study.Customer (CustomerName) VALUES (N'Ana Silva');
-- IsActive = 1, CreatedDate = hoje

-- NÃO usa default para IsActive; armazena NULL
INSERT INTO study.Customer (CustomerName, IsActive)
VALUES (N'Bruno Costa', NULL);
-- IsActive = NULL, não 1
```

> [!warning] Erro Comum
> Inserir explicitamente `NULL` em uma coluna com `DEFAULT` **não** invoca o default. O default se aplica apenas quando a coluna é omitida da lista de colunas do `INSERT`.

## NOT NULL

`NOT NULL` é a restrição mais simples: rejeita qualquer linha que deixaria a coluna nula.

```sql
CREATE TABLE study.Product (
    ProductId   int IDENTITY(1,1) NOT NULL,
    ProductName nvarchar(100) NOT NULL,  -- todo produto DEVE ter um nome
    Description nvarchar(500) NULL       -- descrição é opcional
);
```

Diretrizes para decidir anulabilidade:

| Característica da coluna | Anulável? |
| :--- | :--- |
| Fato de negócio sempre conhecido | `NOT NULL` |
| Valor genuinamente desconhecido no momento do insert | `NULL` permitido |
| Chave estrangeira em tabela filha | Geralmente `NOT NULL` |
| Atributo opcional (nome do meio, sufixo) | `NULL` permitido |
| Será preenchido depois em um fluxo de trabalho | Pode ser `NULL` durante estado intermediário |

## ALTER TABLE com CHECK / NOCHECK

Ao adicionar uma restrição a uma tabela existente, o SQL Server por padrão valida os dados existentes (`WITH CHECK`). Use `WITH NOCHECK` para pular a validação (útil quando você sabe que os dados existentes estão limpos, ou ao aplicar uma nova regra apenas a dados futuros).

```sql
-- Padrão: valida TODAS as linhas existentes (falha se alguma violar)
ALTER TABLE study.SalesOrder WITH CHECK
ADD CONSTRAINT CK_SalesOrder_Total CHECK (OrderTotal >= 0);

-- Pula validação de linhas existentes (nova regra se aplica apenas a novos dados)
ALTER TABLE study.SalesOrder WITH NOCHECK
ADD CONSTRAINT CK_SalesOrder_Total CHECK (OrderTotal >= 0);
```

> [!warning] Erro Comum
> Uma restrição adicionada com `WITH NOCHECK` é marcada como **não confiável**. O otimizador de consulta pode não usá-la para estimativa de cardinalidade, o que pode afetar a performance. Consulte `sys.check_constraints` para ver o sinalizador `is_not_trusted`.

```sql
SELECT name, is_not_trusted
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID(N'study.SalesOrder');
```

## Verifique-se

### 1. Violação de chave estrangeira

Você tenta inserir um `SalesOrder` com `CustomerId = 999` em uma tabela onde nenhum cliente tem esse ID. Que erro você obtém? Como você o capturaria graciosamente em T-SQL?

> [!success]- Answer
> Erro 547: violação de restrição de chave estrangeira. Capture com `BEGIN TRY...BEGIN CATCH` e inspecione `ERROR_NUMBER()`:
>
> ```sql
> BEGIN TRY
>     INSERT INTO study.SalesOrder (CustomerId, OrderDate, OrderTotal)
>     VALUES (999, '2026-07-01', 10.00);
> END TRY
> BEGIN CATCH
>     IF ERROR_NUMBER() = 547
>         PRINT 'FK violation: CustomerId does not exist.';
> END CATCH;
> ```

### 2. CHECK e NULL

O que acontece quando você insere `NULL` em uma coluna definida como `CHECK (Value > 0)` e a coluna é anulável?

> [!success]- Answer
> O insert **é bem-sucedido**. Uma comparação com `NULL` avalia para `UNKNOWN`, que não é `FALSE`. A restrição `CHECK` apenas rejeita linhas onde o predicado avalia para `FALSE`. Adicione `NOT NULL` à coluna se um valor ausente também deve ser rejeitado.

### 3. UNIQUE e NULL

Quantos valores `NULL` uma restrição `UNIQUE` pode aceitar no SQL Server?

> [!success]- Answer
> Um `NULL`. O SQL Server trata `NULL` como um valor distinto para fins de unicidade. Se a coluna é anulável, uma única linha com `NULL` é permitida; uma segunda linha com `NULL` violaria a restrição.

### 4. Mal-entendido de DEFAULT

Você cria uma coluna `IsActive bit NOT NULL DEFAULT (1)` e depois executa:

```sql
INSERT INTO study.Customer (CustomerName, IsActive) VALUES (N'Test', NULL);
```

Qual é o valor de `IsActive` para a nova linha?

> [!success]- Answer
> `NULL`. O `DEFAULT` só se aplica quando a coluna é **omitida** da lista de colunas do `INSERT`. Passar explicitamente `NULL` insere `NULL` — e como a coluna é `NOT NULL`, este insert **falha**.

## Próximos Passos

Restrições são os blocos de construção do design confiável de banco de dados. Construa sobre esta base nas seções seguintes:

- **Sequências e identity** → Seção 01 — Database Objects
- **Tabelas temporais** → Seção 02 — Programmability Objects
- **Tabelas Ledger** → Seção 02 — Programmability Objects
- **Design de índices** → Seção 01 — Database Objects (filtered, columnstore)

## Casos de Uso

- Impedir pedidos referenciando um cliente que não existe (FK).
- Impedir preços ou quantidades negativas (CHECK).
- Garantir endereços de email únicos por usuário (UNIQUE).
- Definir automaticamente timestamps de auditoria no insert (DEFAULT).

## Problemas Comuns & Erros

> [!warning] Erro Comum
> Uma chave estrangeira não cria automaticamente um índice na coluna filha. A FK protege a integridade referencial; o índice é uma decisão separada de performance.

> [!warning] Erro Comum
> Um `CHECK` passa quando o resultado é `UNKNOWN` (isto é, quando a coluna é `NULL`). Combine com `NOT NULL` se inválido e ausente são ambos inaceitáveis.

> [!warning] Erro Comum
> Inserir explicitamente `NULL` não invoca um `DEFAULT`. O default só dispara quando a coluna é omitida da lista de colunas do insert.

> [!warning] Erro Comum
> Remover uma restrição é `ALTER TABLE ... DROP CONSTRAINT`. Não há `DISABLE CONSTRAINT` no SQL Server padrão (você pode usar `NOCHECK` para FK/CHECK em alguns cenários). Não altere a restrição para "deixar dados ruins entrar" — corrija os dados.

## Melhores Práticas

- Nomeie todas as restrições para que mensagens de erro em produção sejam significativas.
- Coloque regras de negócio duráveis em restrições quando puderem ser expressas declarativamente.
- Sempre teste violações de restrição com `BEGIN TRY...BEGIN CATCH` durante o desenvolvimento.
- Use `WITH CHECK` (o padrão) ao adicionar restrições a dados existentes.
- Prefira `NO ACTION` sobre `CASCADE` a menos que tenha uma razão de negócio clara para exclusões em cascata.

## Dicas para o Exame

> [!tip] Dicas para o Exame
> Uma chave primária garante unicidade e não-anulabilidade; uma restrição unique permite um `NULL` no SQL Server. O índice padrão para uma chave primária é clustered. Uma chave estrangeira não cria um índice. `CHECK` e `NULL` interagem via lógica de três valores: `UNKNOWN` não é `FALSE`.

## Principais Conclusões

- Restrições protegem dados no limite do banco de dados — não podem ser contornadas.
- Relacionamentos são garantidos com chaves estrangeiras; unicidade com chaves primárias e restrições unique.
- `CHECK` usa lógica de três valores: passa se TRUE ou UNKNOWN, falha apenas se FALSE.
- `DEFAULT` dispara na omissão, não em `NULL` explícito.
- Nomeie restrições para que erros sejam autodocumentados.

## Tópicos Relacionados

- [Fundamentos de índices](./10-index-fundamentals.md)
- [Database Objects](../../01-database-objects/database-objects.md)
- [Alterar dados com segurança](./07-change-data-safely.md)
- [Relacionamentos e JOINs](./05-relationships-and-joins.md)

## Documentação Oficial

- [Restrições de chave primária e estrangeira](https://learn.microsoft.com/sql/relational-databases/tables/primary-and-foreign-key-constraints)
- [Restrição CHECK](https://learn.microsoft.com/sql/relational-databases/tables/check-constraints)
- [Restrição UNIQUE](https://learn.microsoft.com/sql/relational-databases/tables/unique-constraints)
- [Restrição DEFAULT](https://learn.microsoft.com/sql/relational-databases/tables/default-constraints)

---

**[← Anterior](./07-change-data-safely.md) | [↑ Voltar à Seção](./fundamentals.md) | [Próximo →](./09-subqueries-and-ctes.md)**
