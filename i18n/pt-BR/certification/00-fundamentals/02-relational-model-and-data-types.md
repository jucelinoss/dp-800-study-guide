---
title: "Modelo Relacional e Tipos de Dados"
type: topic
tags: [sql-server, relational-model, data-types, fundamentals]
---

# Modelo Relacional e Tipos de Dados

## Visão Geral

Um banco de dados relacional armazena fatos em tabelas e conecta esses fatos através de chaves. Este capítulo fornece o vocabulário de modelagem e seleção de tipos necessário para criar tabelas com confiança na próxima lição.

> [!abstract]
>
> - Aprenda a hierarquia desde a instância do SQL Server até a linha, além do papel dos schemas.
> - Modele entidades, atributos, chaves e relacionamentos um-para-muitos antes de escrever DDL.
> - Escolha tipos básicos do SQL Server deliberadamente e lide com `NULL` corretamente.

> [!tip] O que o Exame Testa
> O DP-800 constrói sobre schemas, tabelas, relacionamentos de chaves, escolhas de tipo e manipulação de `NULL`. Tabelas especializadas, JSON, particionamento e indexação avançada vêm depois; este capítulo estabelece a base que eles compartilham.

---

## A hierarquia dos dados armazenados

Antes de criar um objeto, seja capaz de dizer onde ele vive.

```text
Instância SQL Server
└── Database: StudyDB
    └── Schema: study
        └── Tabela: Customer
            ├── Coluna: CustomerId
            ├── Coluna: CustomerName
            └── Linha: um registro de cliente
```

| Termo | O que é | Exemplo | O que não é |
| :--- | :--- | :--- | :--- |
| Instância | Um mecanismo de banco de dados SQL Server em execução | `localhost` | Um único banco de dados |
| Database | Um contêiner para objetos, dados, usuários e configurações | `StudyDB` | Um schema |
| Schema | Um namespace dentro de um banco de dados | `dbo`, `study`, `Sales` | Um diagrama de design de tabela |
| Tabela | Linhas com um conjunto definido de colunas | `study.Customer` | Uma aba de planilha com colunas arbitrárias |
| Coluna | Um fato de um tipo definido por linha | `CustomerName` | Uma chave por padrão |
| Linha | Uma ocorrência da entidade da tabela | um cliente | Uma tabela |

Use nomes de duas partes como `study.Customer`. Um schema é útil para organização e limites de permissão: `Sales.Order` e `Archive.Order` podem coexistir porque seus schemas diferem. `dbo` é o schema padrão comum, mas não significa "o banco de dados inteiro".

> [!note] Modelo mental — schema
> Um banco de dados é um prédio comercial; um schema é um andar identificado; tabelas são as salas naquele andar. O schema agrupa objetos, mas não cria um banco de dados separado.

## Da linguagem de negócios a um modelo relacional

Comece com uma declaração curta de fatos, não com a sintaxe `CREATE TABLE`:

> Um cliente pode fazer muitos pedidos. Cada pedido pertence a um cliente. Um pedido contém uma data e um valor total. Um cliente tem um nome e pode ter um endereço de email.

Isso identifica três coisas:

| Termo de modelagem | Significado | Exemplo |
| :--- | :--- | :--- |
| Entidade | Uma coisa sobre a qual fatos são armazenados | Customer, SalesOrder |
| Atributo | Um fato que descreve uma entidade | CustomerName, OrderDate |
| Relacionamento | Uma conexão entre entidades | cliente faz pedido |

O relacionamento é **um-para-muitos**: um cliente pode estar associado a muitos pedidos; um pedido pertence a um cliente. No modelo relacional, a chave estrangeira fica no lado "muitos":

```text
Customer                                      SalesOrder
-----------------------------------------     --------------------------------
CustomerId  (primary key)                 1 ───< CustomerId (foreign key)
CustomerName                                      SalesOrderId (primary key)
Email                                             OrderDate
                                                  OrderTotal
```

A notação `1 ───<` indica "um cliente para muitos pedidos". Não exige que todo cliente tenha um pedido; zero pedidos ainda é compatível com o relacionamento.

### Mantenha um fato em um lugar

Evite esta primeira tentativa:

```text
OrderId | OrderDate | CustomerName | CustomerEmail | ProductName | Quantity
```

Parece conveniente, mas repete fatos do cliente para cada pedido. Corrigir um email exigiria alterar múltiplas linhas; perder uma cria dados contraditórios. Em vez disso, armazene um cliente uma vez e use sua chave em cada pedido. Esta é a razão central pela qual designs relacionais reduzem duplicação e inconsistência.

Isso não significa que toda palavra repetida seja ruim. Um pedido pode intencionalmente registrar um endereço de entrega histórico ou preço unitário, mesmo que o cliente ou produto mude depois. A questão é se o valor repetido representa o *fato atual da entidade* ou um *snapshot deliberado no momento da transação*.

## Chaves: identidade e relacionamentos

### Chaves primárias

Uma chave primária identifica unicamente cada linha e não pode ser `NULL`. `CustomerId` é uma boa chave porque é estável mesmo quando um cliente muda de nome ou email.

```sql
CREATE TABLE study.Customer (
    CustomerId int NOT NULL,
    CustomerName nvarchar(100) NOT NULL,
    Email nvarchar(320) NULL,
    CONSTRAINT PK_Customer PRIMARY KEY (CustomerId)
);
```

O valor pode ser gerado por `IDENTITY` na próxima lição. Não assuma que um inteiro gerado deve ser contínuo ou que sua sequência indica importância comercial; rollbacks, linhas excluídas e inserts concorrentes podem deixar lacunas.

### Chaves naturais versus substitutas

Uma **chave natural** vem do negócio, como um identificador governamental imutável. Uma **chave substituta** é criada apenas para identificar uma linha, comumente um inteiro `CustomerId`.

| Escolha | Benefício | Risco |
| :--- | :--- | :--- |
| Chave natural | O significado de negócio é visível | Valores podem mudar, estar ausentes, ser longos ou ser sensíveis |
| Chave substituta | Valor de relacionamento estável e compacto | Deve-se adicionar uma regra separada de unicidade quando necessário |

Para um modelo iniciante, use uma chave primária substituta e adicione uma regra `UNIQUE` apenas se o negócio genuinamente exigir que um valor seja único. Por exemplo, um endereço de email não deve ser automaticamente declarado único se múltiplas pessoas podem legitimamente compartilhar uma caixa de entrada.

### Chaves estrangeiras

Uma chave estrangeira armazena um valor de chave de uma tabela pai. O banco de dados pode garantir que o pai referenciado existe.

```sql
CREATE TABLE study.SalesOrder (
    SalesOrderId int NOT NULL,
    CustomerId int NOT NULL,
    OrderDate date NOT NULL,
    OrderTotal decimal(12, 2) NOT NULL,
    CONSTRAINT PK_SalesOrder PRIMARY KEY (SalesOrderId),
    CONSTRAINT FK_SalesOrder_Customer
        FOREIGN KEY (CustomerId) REFERENCES study.Customer(CustomerId)
);
```

`CustomerId` é obrigatório aqui porque a regra estabelecida diz que todo pedido pertence a um cliente. Se um pedido pudesse ser criado antes de o cliente ser conhecido, permita `NULL` apenas se esse for um estado de negócio temporário real e projete um processo para resolvê-lo.

> [!warning] Erro Comum
> Uma coluna chamada `CustomerId` não é uma chave estrangeira apenas por causa de seu nome. Ela se torna um relacionamento garantido apenas quando uma restrição `FOREIGN KEY` é definida.

### Outras formas de relacionamento

| Forma | Exemplo | Implementação típica |
| :--- | :--- | :--- |
| Um-para-um | Pessoa e um passaporte atual | Chave estrangeira mais restrição `UNIQUE` |
| Um-para-muitos | Cliente e pedidos | Chave estrangeira na tabela do lado muitos |
| Muitos-para-muitos | Pedidos e produtos | Uma tabela de ponte como `SalesOrderItem` |

Um relacionamento muitos-para-muitos precisa de uma terceira tabela porque um pedido pode conter muitos produtos e um produto pode aparecer em muitos pedidos:

```text
SalesOrder  1 ───< SalesOrderItem >─── 1  Product
```

A ponte contém pelo menos ambas as chaves e geralmente fatos específicos do relacionamento, como quantidade e preço unitário. Você criará apenas tabelas simples na Parte 0; este padrão é incluído para que o design subjacente não seja misterioso quando você o encontrar depois.

## Escolha tipos de dados pelo significado

Um tipo é uma promessa sobre o que uma coluna pode representar. Não escolha `nvarchar` para todo valor apenas porque aceita quase tudo; você perde validação, comparações precisas e operações úteis.

| Fato de negócio | Bom tipo inicial | Por quê | Evite como padrão |
| :--- | :--- | :--- | :--- |
| Identificador interno / contagem | `int` | Número inteiro exato | Identificadores textuais sem motivo |
| Contagem muito grande | `bigint` | Maior intervalo de inteiros exatos | `decimal` quando não há parte fracionária |
| Preço, quantidade, porcentagem | `decimal(p, s)` | Escala fixa exata | `float` / `real` para valores exatos |
| Nome ou descrição | `nvarchar(n)` | Caracteres Unicode | `varchar` quando Unicode é necessário |
| Código fixo com tamanho garantido | `char(n)` ou `nchar(n)` | Semântica de armazenamento fixo | Tipos fixos para nomes de tamanho variável |
| Apenas data | `date` | Sem componente de hora | Data em texto como `nvarchar(10)` |
| Timestamp | `datetime2` | Tipo moderno e preciso | `datetime` para novo design sem necessidade de compatibilidade |
| Sim/não/desconhecido | `bit` | Valor compacto tipo Booleano | Strings como `Yes` e `No` |
| Dados binários | `varbinary(max)` | Arquivo ou payload binário | Codificação textual de dados binários |

### Números: exatos versus aproximados

`int` e `decimal` são tipos numéricos exatos. `float` e `real` são tipos de ponto flutuante binário aproximados. Valores aproximados são úteis para medições científicas onde pequenas diferenças de representação são aceitáveis, mas não devem ser usados para moeda ou valores que devem ser comparados exatamente.

```sql
DECLARE @exact decimal(10, 2) = 0.10 + 0.20;
DECLARE @approximate float = 0.10 + 0.20;

SELECT @exact AS exact_result, @approximate AS approximate_result;
```

A exibição do resultado aproximado pode ocultar uma diferença de arredondamento binário. Para um valor monetário, defina uma precisão e escala `decimal` apropriadas. `decimal(12, 2)` permite dez dígitos antes do ponto decimal e dois depois; é um exemplo, não um padrão financeiro universal.

### Texto: Unicode e comprimento

Use `nvarchar` para nomes, endereços, texto livre e outros valores que podem incluir acentos ou caracteres fora de uma página de código estreita. `nvarchar(100)` significa até 100 caracteres, não uma instrução para preencher todo valor até esse tamanho.

Use um comprimento máximo deliberado baseado no fato de negócio. `nvarchar(max)` não é uma versão mais segura de toda coluna de texto; reserve-o para conteúdo genuinamente grande. Um código de país pode ser `char(2)`, mas o nome de uma pessoa não deve ser `char(100)` porque nomes variam em comprimento.

### Datas e horas

Use `date` para data de nascimento, data de vencimento ou data de pedido quando a hora não é significativa. Use `datetime2` quando for. O tipo não decide automaticamente a semântica de fuso horário: documente se um `datetime2` é hora local de negócios ou UTC e mantenha a convenção consistente.

```sql
CREATE TABLE study.EventExample (
    EventId int NOT NULL,
    EventDate date NOT NULL,
    RecordedAt datetime2 NOT NULL
);
```

`timestamp` é um sinônimo histórico do SQL Server para `rowversion`; **não** é um tipo de data/hora. Evite-o quando você quer dizer hora de um evento.

### Valores tipo Booleano

`bit` armazena `0`, `1` ou `NULL`. Prefira um nome claramente fraseado como `IsActive` ou `HasAcceptedTerms`, depois defina se desconhecido é permitido. Uma coluna `bit NOT NULL` com um padrão é comum quando toda linha deve ser explicitamente verdadeira ou falsa.

## `NULL` e lógica de três valores

`NULL` representa informação desconhecida, ausente ou não aplicável. Não é zero, string vazia ou uma string contendo as letras `NULL`.

| Expressão | Resultado quando `Email` é `NULL` | Por quê |
| :--- | :--- | :--- |
| `Email = N'a@example.test'` | Desconhecido | Valor ausente não pode igualar um valor conhecido |
| `Email <> N'a@example.test'` | Desconhecido | Também não pode ser provado diferente |
| `Email IS NULL` | Verdadeiro | Isso testa a ausência explicitamente |
| `Email IS NOT NULL` | Falso | Isso testa a presença explicitamente |

`WHERE` retorna apenas linhas cujo predicado é verdadeiro. Linhas com predicados falsos **ou desconhecidos** são excluídas, e é por isso que esta consulta não encontra emails ausentes:

```sql
-- Incorreto: nenhuma linha satisfaz a igualdade com NULL.
SELECT CustomerName
FROM study.Customer
WHERE Email = NULL;

-- Correto.
SELECT CustomerName
FROM study.Customer
WHERE Email IS NULL;
```

### Decida se uma coluna é opcional

Faça uma pergunta: *Uma linha válida pode existir sem este fato no momento em que é salva?*

- Nome do cliente: normalmente `NOT NULL`.
- Endereço de email: possivelmente `NULL` se não foi coletado.
- Cliente do pedido: normalmente `NOT NULL` se todo pedido tem um cliente.
- Data de término de uma assinatura ativa: pode ser `NULL` até terminar.

Não armazene um placeholder falso para evitar `NULL`. `unknown@example.test` é um valor reivindicado, não informação ausente; pode colidir com um valor real e tornar análises enganosas.

### `NULL` em agregação e expressões

Muitas funções agregadas ignoram entradas `NULL`. `COUNT(*)` conta linhas; `COUNT(Email)` conta apenas emails não nulos. `SUM` de um conjunto vazio retorna `NULL`, que é distinto de um total conhecido de zero.

```sql
SELECT COUNT(*) AS customer_rows,
       COUNT(Email) AS customers_with_email
FROM study.Customer;
```

Use `COALESCE` apenas quando a saída deve substituir um valor pela ausência:

```sql
SELECT CustomerName,
       COALESCE(Email, N'Nenhum email registrado') AS email_display
FROM study.Customer;
```

Isso altera o resultado da consulta, não o valor `NULL` armazenado.

## Conversões e comparações

O SQL Server às vezes pode converter entre tipos automaticamente, mas conversões implícitas podem falhar ou causar trabalho inesperado de performance. Torne o tipo pretendido claro quando um literal é ambíguo.

```sql
DECLARE @orderDate date = '2026-07-26';
DECLARE @amount decimal(12, 2) = 19.95;

SELECT @orderDate AS order_date, @amount AS amount;
```

Use `CAST` ou `CONVERT` quando a conversão faz parte da tarefa:

```sql
SELECT CAST(OrderTotal AS decimal(14, 2)) AS normalized_total
FROM study.SalesOrder;
```

`TRY_CAST` e `TRY_CONVERT` retornam `NULL` em vez de gerar um erro quando uma conversão falha. Eles são valiosos ao limpar dados de entrada incertos, mas não esconda dados ruins silenciosamente sem registrá-los ou investigá-los.

```sql
SELECT TRY_CONVERT(date, N'not a date') AS parsed_value;
```

### Collation em linguagem simples

Uma **collation** define regras de comparação e ordenação de texto, incluindo sensibilidade a maiúsculas/minúsculas e acentos. Muitas instalações do SQL Server usam uma collation insensível a maiúsculas/minúsculas, então `Ana` pode ser comparada igual a `ana`; não confie nisso sem conhecer a collation do banco de dados. Escolhas de collation importam para identificadores e comparação de texto, mas um iniciante deve primeiro lembrar que o comportamento de uma comparação de texto pode depender da configuração.

## Um modelo trabalhado para o `StudyDB`

A definição a seguir une os conceitos. É pequena o suficiente para entender e robusta o suficiente para praticar.

```sql
CREATE SCHEMA study;
GO

CREATE TABLE study.Customer (
    CustomerId int IDENTITY(1, 1) NOT NULL,
    CustomerName nvarchar(100) NOT NULL,
    Email nvarchar(320) NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Customer_IsActive DEFAULT (1),
    CONSTRAINT PK_Customer PRIMARY KEY (CustomerId)
);
GO

CREATE TABLE study.SalesOrder (
    SalesOrderId int IDENTITY(1, 1) NOT NULL,
    CustomerId int NOT NULL,
    OrderDate date NOT NULL,
    OrderTotal decimal(12, 2) NOT NULL,
    CONSTRAINT PK_SalesOrder PRIMARY KEY (SalesOrderId),
    CONSTRAINT CK_SalesOrder_OrderTotal CHECK (OrderTotal >= 0),
    CONSTRAINT FK_SalesOrder_Customer
        FOREIGN KEY (CustomerId) REFERENCES study.Customer(CustomerId)
);
GO
```

Leia as regras em vez de apenas a sintaxe:

- `CustomerId` identifica um cliente e é gerado pelo SQL Server.
- Um nome é obrigatório; email é opcional.
- Um pedido precisa de um cliente real, data e valor não negativo.
- A chave estrangeira protege o relacionamento, mesmo que uma aplicação futura ignore sua própria validação.

## Questões de Prática

### 1. Modelagem

Um cliente pode ter muitos tickets de suporte, e todo ticket pertence a um cliente. Qual tabela deve armazenar `CustomerId` como chave estrangeira?

A. `Customer`<br>
B. `SupportTicket`<br>
C. Ambas as tabelas<br>
D. Nenhuma tabela

> [!success]- Resposta
> **B. `SupportTicket`** é a tabela do lado muitos. Cada ticket armazena o cliente ao qual pertence; um cliente pode ser referenciado por muitas linhas de ticket.

### 2. Seleção de tipo

Qual tipo é mais apropriado para um preço que deve somar e comparar exatamente com duas casas decimais?

A. `float`<br>
B. `nvarchar(20)`<br>
C. `decimal(12, 2)`<br>
D. `bit`

> [!success]- Resposta
> **C. `decimal(12, 2)`** é um tipo exato de escala fixa. Valores de ponto flutuante são aproximados e texto não carrega semântica numérica.

### 3. Valores ausentes

Qual predicado retorna linhas cujo email não foi registrado?

A. `Email = NULL`<br>
B. `Email <> NULL`<br>
C. `Email IS NULL`<br>
D. `Email = ''`

> [!success]- Resposta
> **C. `Email IS NULL`** testa explicitamente o marcador de valor ausente. Uma string vazia é um valor de texto diferente e conhecido.

## Casos de Uso

- Traduza uma descrição curta de negócio em tabelas, atributos e um relacionamento.
- Escolha tipos que preservem significado numérico, textual e temporal.
- Decida se um valor desconhecido deve ser permitido ou rejeitado.

## Problemas Comuns & Erros

> [!warning] Erro Comum
> Usar um nome, email ou descrição como chave primária porque parece único hoje torna os relacionamentos frágeis quando esse valor de negócio muda ou é duplicado.

> [!warning] Erro Comum
> `WHERE Email = NULL` nunca testa email ausente. Use `IS NULL`; lembre-se de que `WHERE` mantém apenas condições verdadeiras, não desconhecidas.

## Melhores Práticas

- Modele uma entidade por tabela e coloque cada fato onde ele tem um significado claro.
- Use `NOT NULL` para fatos obrigatórios, mas não invente valores falsos para evitar `NULL`s opcionais.
- Prefira tipos numéricos exatos para valores que devem ser exatos e `datetime2` para novas colunas de data e hora.
- Nomeie chaves e restrições para que erros identifiquem a regra que foi violada.
- Especifique schemas em nomes de objetos e use-os consistentemente.

## Dicas para o Exame

> [!tip] Dicas para o Exame
> Um schema é um namespace dentro de um banco de dados, não outro banco de dados. Uma chave estrangeira descreve e pode garantir um relacionamento; ela não cria automaticamente um índice na coluna filha. Seções posteriores cobrem escolhas de índice e objetos especializados.

## Principais Conclusões

- Um modelo relacional separa entidades e as reconecta com chaves.
- A cardinalidade determina qual tabela contém uma chave estrangeira.
- Tipos expressam significado e restringem operações válidas; selecione-os antes de carregar dados.
- `NULL` requer `IS NULL`/`IS NOT NULL` e introduz um estado lógico desconhecido.

## Tópicos Relacionados

- [Workbook de Fundamentos de SQL Server](./00-foundations-workbook.md)
- [Criar e carregar dados](./03-create-and-load-data.md)
- [Regras de integridade](./08-integrity-rules.md)
- [Database Objects](../../01-database-objects/database-objects.md)

## Documentação Oficial

- [Tipos de dados](https://learn.microsoft.com/sql/t-sql/data-types/data-types-transact-sql)
- [Restrições de chave primária e estrangeira](https://learn.microsoft.com/sql/relational-databases/tables/primary-and-foreign-key-constraints)
- [NULL e UNKNOWN](https://learn.microsoft.com/sql/t-sql/language-elements/null-and-unknown-transact-sql)

---

**[← Anterior](./01-sql-server-and-tools.md) | [↑ Voltar à Seção](./fundamentals.md) | [Próximo →](./03-create-and-load-data.md)**
