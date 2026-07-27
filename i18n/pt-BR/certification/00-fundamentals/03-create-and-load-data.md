---
title: "Criar e Carregar Dados"
type: topic
tags: [sql-server, ddl, dml, fundamentals]
---

# Criar e Carregar Dados

## Visão Geral

Antes que uma aplicação possa consultar dados, alguém deve definir uma estrutura confiável e carregar linhas válidas nela. Este capítulo explica o primeiro ciclo de vida: criar um banco de dados e schema, criar tabelas, depois inserir e inspecionar dados de forma previsível.

> [!abstract]
>
> - DDL define objetos do banco de dados; DML insere e depois altera suas linhas.
> - `CREATE TABLE` é um contrato de dados, não apenas uma lista de colunas.
> - Listas de colunas explícitas, chaves geradas, defaults e verificações de resultado tornam o carregamento repetível.

> [!tip] O que o Exame Testa
> O DP-800 espera que você entenda tabelas, schemas, DDL e DML antes de estendê-los com objetos especializados, projetos de implantação e design avançado de banco de dados.

---

## DDL e DML: dois tipos de alteração

**Data definition language (DDL)** cria ou altera a estrutura: bancos de dados, schemas, tabelas, restrições e índices. **Data manipulation language (DML)** trabalha com as linhas dentro dessa estrutura.

| Instrução | Categoria | O que altera |
| :--- | :--- | :--- |
| `CREATE DATABASE` | DDL | Um novo contêiner de banco de dados |
| `CREATE SCHEMA` | DDL | Um namespace para objetos |
| `CREATE TABLE` | DDL | Uma definição de tabela |
| `ALTER TABLE` | DDL | Uma definição existente |
| `DROP TABLE` | DDL | Remove a tabela e seus dados |
| `INSERT` | DML | Adiciona linhas |
| `UPDATE` | DML | Altera linhas existentes |
| `DELETE` | DML | Remove linhas |

DDL não é automaticamente inofensivo. Um `DROP` ou um `ALTER` incompatível pode tornar dados indisponíveis. DML não é automaticamente mais seguro: um `UPDATE` ou `DELETE` sem um predicado correto pode afetar toda linha. A Parte 0 começa com criação e carregamento seguros; a disciplina de transação para alterações aparece em [Alterar dados com segurança](./07-change-data-safely.md).

## Crie um banco de dados de aprendizado descartável

Os laboratórios usam um banco de dados chamado `StudyDB`. Mantenha objetos de aprendizado fora do `master`, que o SQL Server usa para metadados de nível de sistema.

```sql
USE master;
GO

CREATE DATABASE StudyDB;
GO

USE StudyDB;
GO

CREATE SCHEMA study;
GO
```

`GO` é um separador de lote entendido por clientes como SSMS; não é uma instrução T-SQL enviada ao SQL Server. É útil após `CREATE DATABASE` porque o próximo comando deve conectar-se ao banco de dados recém-criado.

Verifique o contexto antes de executar um script que cria objetos:

```sql
SELECT DB_NAME() AS current_database,
       SCHEMA_NAME() AS default_schema;
```

> [!warning] Erro Comum
> `CREATE DATABASE StudyDB` falha se já existir. Em uma lição, leia o laboratório de configuração e decida se deve reutilizar, redefinir ou usar um nome diferente; não descarte cegamente um banco de dados existente.

## Leia uma definição `CREATE TABLE` como um contrato

Esta tabela diz o que uma linha de produto válida deve conter.

```sql
CREATE TABLE study.Product (
    ProductId int IDENTITY(1, 1) NOT NULL,
    ProductName nvarchar(100) NOT NULL,
    UnitPrice decimal(12, 2) NOT NULL,
    IsDiscontinued bit NOT NULL CONSTRAINT DF_Product_IsDiscontinued DEFAULT (0),
    CreatedAt datetime2 NOT NULL CONSTRAINT DF_Product_CreatedAt DEFAULT (sysdatetime()),
    CONSTRAINT PK_Product PRIMARY KEY (ProductId),
    CONSTRAINT CK_Product_UnitPrice CHECK (UnitPrice >= 0)
);
```

| Parte da definição | Significado | Por que existe |
| :--- | :--- | :--- |
| `study.Product` | Nome de tabela qualificado pelo schema | Evita ambiguidade e agrupa o objeto |
| `ProductId int` | Identificador de número inteiro | Chave estável eficiente |
| `IDENTITY(1, 1)` | Gerar valores: iniciar 1, incrementar 1 | Evita IDs atribuídos manualmente para inserts normais |
| `NOT NULL` | Um valor é obrigatório | Rejeita linhas incompletas |
| `DEFAULT (0)` | Preencher valor omitido com zero/falso | Dá um estado inicial previsível |
| `PRIMARY KEY` | Identidade de linha única e não nula | Protege a identidade e suporta relacionamentos |
| `CHECK` | Linha deve atender a um predicado | Rejeita preço negativo sem sentido |

Nomes de restrição como `PK_Product` e `CK_Product_UnitPrice` são intencionais. Quando um insert falha, um nome significativo diz qual regra foi violada. Os próximos capítulos discutem restrições e chaves mais profundamente; aqui, reconheça que uma tabela deve proteger suas verdades básicas desde sua primeira linha.

### `IDENTITY` é um gerador, não uma contagem de linhas

`IDENTITY(1, 1)` gera um valor quando um insert omite essa coluna. Não garante valores consecutivos. Um insert falho, rollback, exclusão ou atividade concorrente pode deixar lacunas, e isso é normal.

```sql
INSERT INTO study.Product (ProductName, UnitPrice)
VALUES (N'Notebook', 12.50);

SELECT ProductId, ProductName, UnitPrice
FROM study.Product;
```

Não use um valor identity como prova de quantas linhas existem e não reutilize valores identity excluídos como uma regra de negócio. A chave identifica uma linha; não é um número de nota fiscal, um ranking ou uma promessa de cronologia.

### Defaults se aplicam apenas quando uma coluna é omitida

Este insert permite que o SQL Server aplique ambos os defaults:

```sql
INSERT INTO study.Product (ProductName, UnitPrice)
VALUES (N'Pen', 2.00);
```

Este insert armazena explicitamente `NULL` e portanto **não** solicita um default. Falha porque `IsDiscontinued` é `NOT NULL`:

```sql
-- INSERT INTO study.Product (ProductName, UnitPrice, IsDiscontinued)
-- VALUES (N'Pencil', 1.50, NULL);
```

A distinção importa: um default não é um substituto para `NULL` em toda situação. É um valor que o SQL Server fornece quando a instrução não fornece um.

## Insira linhas deliberadamente

Sempre especifique as colunas alvo. Isso documenta a intenção, sobrevive a mudanças inofensivas na ordem das colunas e torna claro quais defaults ou valores identity estão sendo solicitados.

```sql
INSERT INTO study.Product (ProductName, UnitPrice)
VALUES
    (N'Notebook', 12.50),
    (N'Pen', 2.00),
    (N'Backpack', 45.00);
```

O SQL Server valida toda linha contra a definição da tabela. As instruções a seguir falham por razões úteis:

```sql
-- ProductName obrigatório está ausente.
-- INSERT INTO study.Product (UnitPrice) VALUES (10.00);

-- Restrição CHECK rejeita um preço negativo.
-- INSERT INTO study.Product (ProductName, UnitPrice) VALUES (N'Invalid', -5.00);
```

O erro é evidência de que o contrato do banco de dados funciona. Corrija os dados ou reconsidere a regra; não remova uma restrição apenas para fazer uma carga inválida ser bem-sucedida.

### Inspecione o que foi carregado

Uma mensagem `INSERT` relata uma contagem de linhas afetadas, mas inspecione dados representativos também:

```sql
SELECT ProductId,
       ProductName,
       UnitPrice,
       IsDiscontinued,
       CreatedAt
FROM study.Product
ORDER BY ProductId;
```

Verifique valores de chave gerados, defaults, tipos de dados e contagem de linhas. Faça isso antes de construir consultas que dependem dos dados; um erro é mais barato de corrigir imediatamente após ser introduzido.

## Inserir a partir de outra consulta

`INSERT ... SELECT` carrega linhas produzidas por uma consulta. As colunas alvo ainda precisam se alinhar com as expressões selecionadas por posição e tipo compatível.

```sql
CREATE TABLE study.ProductArchive (
    ProductName nvarchar(100) NOT NULL,
    UnitPrice decimal(12, 2) NOT NULL
);
GO

INSERT INTO study.ProductArchive (ProductName, UnitPrice)
SELECT ProductName, UnitPrice
FROM study.Product
WHERE IsDiscontinued = 1;
```

Este é um padrão comum para migrações e staging, mas faça três perguntas antes de usá-lo:

1. A consulta fonte retorna exatamente as linhas pretendidas?
2. Os tipos alvo e colunas obrigatórias são compatíveis?
3. Pode ser executado novamente com segurança, ou duplicará linhas?

Para um script de seed inicial, uma reexecução pode criar duplicatas. Um módulo posterior cobre projetos de banco de dados repetíveis e implantação; por enquanto, torne o comportamento visível e mantenha as cargas de amostra pequenas.

### Capture valores gerados com `OUTPUT`

Quando uma aplicação insere uma ou mais linhas, muitas vezes precisa das chaves geradas. `OUTPUT` retorna valores das linhas afetadas sem emitir uma consulta separada.

```sql
INSERT INTO study.Product (ProductName, UnitPrice)
OUTPUT inserted.ProductId, inserted.ProductName
VALUES (N'Highlighter', 3.75);
```

`inserted` é uma tabela lógica disponível para instruções DML. Em um `INSERT`, ela contém as versões recém-inseridas das linhas. `OUTPUT` é mais seguro e claro para inserts de múltiplas linhas do que adivinhar qual identity foi gerado.

## Criando uma tabela a partir de uma consulta

`SELECT INTO` cria uma nova tabela e carrega um resultado de consulta em uma operação.

```sql
SELECT ProductName, UnitPrice
INTO study.ProductPriceSnapshot
FROM study.Product;
```

Isso é útil para exploração descartável, mas copia as colunas e dados selecionados — não o contrato completo da tabela. Chaves primárias, chaves estrangeiras, restrições check, índices, triggers, permissões e defaults não vêm automaticamente junto.

| Necessidade | Prefira |
| :--- | :--- |
| Cópia descartável rápida para exploração | `SELECT INTO` |
| Design de tabela conhecido e governado | `CREATE TABLE`, depois `INSERT ... SELECT` |
| Schema de aplicação repetível | Projeto de banco de dados versionado, coberto depois |

> [!warning] Erro Comum
> Uma tabela feita com `SELECT INTO` pode parecer correta em um `SELECT` simples, enquanto silenciosamente carece das chaves e verificações que protegem o original. Trate-a como uma nova tabela que precisa de sua própria revisão de design.

## Carregando de arquivos: mantenha o limite explícito

Sistemas reais frequentemente recebem CSV e outros arquivos. O princípio iniciante é mais importante que memorizar um comando de carga em massa: não trate texto externo como linhas de banco de dados confiáveis.

Use uma abordagem de staging:

```text
Arquivo ou fonte externa
        ↓
Tabela de staging (inspecionar, validar, converter)
        ↓
Tabela alvo (chaves, tipos e restrições garantidas)
```

Uma tabela de staging pode inicialmente conter valores recebidos como texto para que datas ou valores inválidos possam ser identificados. Após validar com conversões explícitas como `TRY_CONVERT`, carregue linhas limpas no alvo tipado. Mecanismos de carga em massa, permissões e performance de alto volume estão fora deste capítulo introdutório; o hábito essencial é validar antes do insert final.

## Faça pequenas alterações estruturais com cuidado

`ALTER TABLE` altera uma definição existente. Adicionar uma coluna opcional é mais simples do que adicionar uma coluna obrigatória a uma tabela povoada porque as linhas existentes precisam de um valor válido.

```sql
ALTER TABLE study.Product
ADD SupplierCode nvarchar(30) NULL;
```

Para uma nova coluna obrigatória em uma tabela existente, decida qual valor válido as linhas mais antigas devem receber. Não adicione `NOT NULL` até que um backfill confiável ou default tenha sido projetado. Em um sistema de produção, tais alterações devem ser revisadas, testadas e implantadas através de um processo controlado.

## Um fluxo de seed repetível

Para os laboratórios da Parte 0, use este fluxo sempre que adicionar dados:

1. Confirme o banco de dados atual com `SELECT DB_NAME()`.
2. Leia a definição da tabela e restrições.
3. Insira um conjunto pequeno e nomeado de linhas.
4. Consulte essas linhas explicitamente e inspecione valores gerados/padrão.
5. Registre se o script pode ser executado novamente com segurança.

Esse último passo previne um problema comum de iniciante: um script "funciona" duas vezes mas produz duas cópias dos dados de seed. Uma estratégia de qualidade de produção pode usar uma chave natural e uma abordagem tipo upsert, mas isso introduz escolhas de concorrência e design além desta lição. Por enquanto, redefina o `StudyDB` com o laboratório de configuração quando quiser um estado limpo.

## Exercícios de Prática

### 1. Leia o contrato

Para a tabela `study.Product` acima, quais valores um insert básico pode omitir?

A. `ProductId` apenas<br>
B. `ProductId`, `IsDiscontinued` e `CreatedAt`<br>
C. `ProductName` e `UnitPrice`<br>
D. Todas as colunas

> [!success]- Resposta
> **B.** `ProductId` é gerado por `IDENTITY`; `IsDiscontinued` e `CreatedAt` têm defaults. `ProductName` e `UnitPrice` são `NOT NULL` sem defaults, então o insert deve fornecê-los.

### 2. Faça uma carga válida

Escreva um insert para um produto chamado `Desk Lamp` custando `29.90` que solicite os valores padrão para as outras colunas.

> [!success]- Resposta
>
> ```sql
> INSERT INTO study.Product (ProductName, UnitPrice)
> VALUES (N'Desk Lamp', 29.90);
> ```
>
> A lista de colunas explícita tanto omite a identity quanto permite que os defaults se apliquem.

### 3. Escolha um padrão de criação

Você precisa de uma cópia descartável de duas colunas para uma consulta exploratória. Qual padrão é apropriado, e o que você deve lembrar depois?

> [!success]- Resposta
> `SELECT INTO` é apropriado para a cópia descartável. Lembre-se de que ele não reproduz chaves, restrições, índices, defaults ou permissões da tabela fonte.

## Casos de Uso

- Crie o schema e tabelas `StudyDB` usados pelos laboratórios da Parte 0.
- Semeie um conjunto de dados de desenvolvimento previsível e inspecione os valores que o SQL Server gerou.
- Copie um resultado selecionado em uma tabela exploratória descartável enquanto entende seus limites.

## Problemas Comuns & Erros

> [!warning] Erro Comum
> Omitir a lista de colunas alvo no `INSERT` amarra o script à ordem física da tabela e torna defaults, comportamento identity e mudanças futuras de schema mais difíceis de entender.

> [!warning] Erro Comum
> Um default não é aplicado quando a instrução fornece explicitamente `NULL`. Colunas obrigatórias ainda rejeitam `NULL`.

## Melhores Práticas

- Use nomes qualificados por schema e listas de colunas explícitas.
- Dê nomes significativos às restrições e verifique as linhas imediatamente após o carregamento.
- Mantenha tabelas `SELECT INTO` exploratórias separadas das tabelas fonte governadas.
- Trate arquivos importados como entrada não confiável; valide e converta antes de carregar uma tabela final.
- Mantenha o trabalho de aprendizado no `StudyDB`, nunca em `master`.

## Dicas para o Exame

> [!tip] Dicas para o Exame
> DDL altera metadados; DML altera linhas. `IDENTITY` gera valores mas não garante numeração contínua. `SELECT INTO` copia dados e colunas selecionados, não as chaves, restrições, índices ou permissões da tabela original.

## Principais Conclusões

- Projete e crie o contrato da tabela antes de carregar dados.
- Inserts explícitos documentam a intenção e permitem que o comportamento identity/default funcione previsivelmente.
- Verifique cargas, valores gerados e comportamento de reexecução imediatamente.
- Uma cópia rápida não é um clone governado da tabela original.

## Tópicos Relacionados

- [Modelo relacional e tipos de dados](./02-relational-model-and-data-types.md)
- [Alterar dados com segurança](./07-change-data-safely.md)
- [Regras de integridade](./08-integrity-rules.md)
- [Database Objects](../../01-database-objects/database-objects.md)

## Documentação Oficial

- [CREATE TABLE](https://learn.microsoft.com/sql/t-sql/statements/create-table-transact-sql)
- [INSERT](https://learn.microsoft.com/sql/t-sql/statements/insert-transact-sql)
- [Cláusula OUTPUT](https://learn.microsoft.com/sql/t-sql/queries/output-clause-transact-sql)
- [SELECT INTO](https://learn.microsoft.com/sql/t-sql/queries/select-into-clause-transact-sql)

---

**[← Anterior](./02-relational-model-and-data-types.md) | [↑ Voltar à Seção](./fundamentals.md) | [Próximo →](./04-select-and-filter.md)**
