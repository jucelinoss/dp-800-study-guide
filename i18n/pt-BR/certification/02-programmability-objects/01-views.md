---
title: Views
type: study-material
tags:
  - dp-800
  - views
  - indexed-views
  - schema-binding
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Criando Views (Creating Views)](#criando-views-creating-views)
>   - 🔹 [Schema Binding](#schema-binding)
>   - 🔹 [Indexed Views (Materialized Views)](#indexed-views-materialized-views)
>   - 🔹 [Views Atualizáveis (Updatable Views)](#views-atualizaveis-updatable-views)
>   - 🔹 [Limitações das Views](#limitacoes-das-views-view-limitations)
> - 📍 [3. Aplicação Prática & Síntese](#casos-de-uso-use-cases)
>   - 🔹 [Casos de Uso](#casos-de-uso-use-cases)
>   - 🔹 [Problemas Comuns e Soluções](#problemas-comuns-e-solucoes-common-issues)
>   - 🔹 [Melhores Práticas](#melhores-praticas-best-practices)
>   - 🔹 [Dicas para o Exame](#dicas-para-o-exame-exam-tips)
>   - 🔹 [Resumo dos Conceitos](#resumo-dos-conceitos-key-takeaways)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)

---

# Views

## Visão Geral (Overview)

As Views são consultas `SELECT` salvas no banco de dados que atuam como tabelas virtuais. O SQL Server oferece suporte a Views tradicionais (standard views), Views vinculadas a esquemas (schema-bound views) e Views indexadas (indexed/materialized views) — cada uma com características de desempenho e manutenção bem distintas.

> [!note] Escopo de plataforma
> As orientações sobre Views indexadas aplicam-se ao SQL Server, Azure SQL Database, Azure SQL Managed Instance e SQL database no Microsoft Fabric. O Azure Synapse Analytics não oferece suporte a `SCHEMABINDING`, Views atualizáveis nem triggers DML em Views.

> [!abstract]
>
> - Cobre Views tradicionais, Views indexadas e Views atualizáveis (updatable views).
> - As Views são tabelas virtuais; as Views indexadas materializam fisicamente seus resultados em disco através de um Clustered Index exclusivo.
> - Tópicos chave do exame: requisitos de criação de Indexed Views (uso de `SCHEMABINDING` e `UNIQUE CLUSTERED INDEX`), regras para Views atualizáveis e o comportamento de `WITH CHECK OPTION`.

> [!tip] O que o Exame Testa
>
> - As Indexed Views exigem obrigatoriamente a opção `WITH SCHEMABINDING` na definição da View E a criação de um `UNIQUE CLUSTERED INDEX` sobre ela. Ambas as exigências são mandatórias.
> - A cláusula `WITH CHECK OPTION` assegura que quaisquer comandos `INSERT` ou `UPDATE` submetidos através da View permaneçam válidos dentro do filtro definido na cláusula `WHERE` da View.
> - Funções não determinísticas (ex: `GETDATE()`, `NEWID()`) são proibidas em Indexed Views.

---

## Criando Views (Creating Views)

```sql
-- View tradicional (Standard view)
CREATE VIEW dbo.vw_ActiveCustomers AS
SELECT CustomerId, Name, Email, CreatedAt
FROM dbo.Customers
WHERE IsActive = 1;

-- View agregando múltiplas tabelas
CREATE VIEW dbo.vw_OrderSummary AS
SELECT
    o.OrderId,
    c.Name       AS CustomerName,
    o.OrderDate,
    SUM(oi.Quantity * oi.UnitPrice) AS TotalAmount
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
JOIN dbo.OrderItems oi ON oi.OrderId = o.OrderId
GROUP BY o.OrderId, c.Name, o.OrderDate;
```

---

## Schema Binding

A opção `WITH SCHEMABINDING` vincula rigidamente a View às tabelas base subjacentes, impedindo alterações de esquema (schema drift) que possam corromper ou quebrar o funcionamento da View. Esta propriedade é requisito obrigatório para a criação de Indexed Views.

> [!note]
> `SCHEMABINDING` não é suportado no Azure Synapse Analytics.

```sql
CREATE VIEW dbo.vw_ProductPricing
WITH SCHEMABINDING AS
SELECT
    p.ProductId,
    p.Name,
    p.Price,
    c.CategoryName
FROM dbo.Products p
JOIN dbo.Categories c ON c.CategoryId = p.CategoryId;
```

Ao ativar `SCHEMABINDING`:

- Impede a exclusão (`DROP`) ou alteração (`ALTER`) das tabelas e colunas subjacentes referenciadas pela View.
- É obrigatório o uso de nomes compostos de duas partes para referenciar as tabelas (`dbo.NomeTabela`) — o uso de `SELECT *` é proibido.
- Bloqueia modificações estruturais que invalidem as colunas da View.

> [!important] Bloqueio estrutural do SCHEMABINDING
>
> - O `WITH SCHEMABINDING` impede a exclusão (`DROP`) e modificações estruturais (`ALTER`) de qualquer tabela/coluna base que seja referenciada pela View.
> - Se for necessário alterar uma coluna base, você deve primeiro recriar a View omitindo o `SCHEMABINDING` ou remover a View antes.

> [!warning] Erro Comum
> Não é possível criar uma View indexada (Indexed View) sem declarar previamente a View com o modificador `WITH SCHEMABINDING`. O schemabinding protege o relacionamento contra alterações nas tabelas base — deve sempre vir primeiro.

---

## Indexed Views (Materialized Views)

Uma **Indexed View** é uma View comum sobre a qual se cria um Clustered Index exclusivo, o que força a gravação física (materialização) do conjunto de dados resultante no disco. Ela atua exatamente como as *materialized views* de outros sistemas gerenciadores.

```sql
-- Opções exigidas para criar e manter uma Indexed View
SET NUMERIC_ROUNDABORT OFF;
SET ANSI_PADDING, ANSI_WARNINGS, CONCAT_NULL_YIELDS_NULL,
    ARITHABORT, QUOTED_IDENTIFIER, ANSI_NULLS ON;
GO

-- Criar a View com schemabinding
CREATE VIEW dbo.vw_OrderSummary
WITH SCHEMABINDING
AS
SELECT CustomerID,
       COUNT_BIG(*) AS OrderCount,
       SUM(ISNULL(TotalAmount, 0)) AS TotalSpent
FROM dbo.Orders
GROUP BY CustomerID;
GO

-- Materializar fisicamente a View criando o index clustered
CREATE UNIQUE CLUSTERED INDEX IX_vw_OrderSummary
ON dbo.vw_OrderSummary(CustomerID);
```

**Requisitos estruturais de uma Indexed View:**

- A View deve conter a cláusula `WITH SCHEMABINDING` em sua definição.
- O primeiro index gerado sobre a View deve ser obrigatoriamente um `UNIQUE CLUSTERED INDEX`.
- As opções de sessão exigidas devem estar configuradas ao criar a View e seu índice, ao alterar as tabelas base e quando o otimizador usar a View: `ANSI_NULLS`, `ANSI_PADDING`, `ANSI_WARNINGS`, `ARITHABORT`, `CONCAT_NULL_YIELDS_NULL` e `QUOTED_IDENTIFIER` em `ON`, e `NUMERIC_ROUNDABORT` em `OFF`.
- A View e as tabelas base devem pertencer ao mesmo proprietário, e as tabelas devem ser referenciadas com nomes em duas partes.
- Somente funções determinísticas são aceitas (bloqueando o uso de `GETDATE()`, `NEWID()`, `RAND()`).
- Não aceita `OUTER JOIN`, `APPLY`, self-joins, `HAVING`, subconsultas, CTEs, `DISTINCT`, `TOP` nem operadores de conjunto como `UNION ALL`.
- `AVG`, `MIN`, `MAX` e outras agregações são restritas; `SUM` sobre uma expressão anulável exige `ISNULL` para torná-la não anulável.
- A função de agregação de contagem obrigatória é `COUNT_BIG(*)` nas Views que utilizem agrupamento (`GROUP BY`) — a função `COUNT(*)` clássica não é permitida.

### Detalhamento das Opções de Sessão Exigidas (SET Options — 6 ONs e 1 OFF)

Os valores fixos permitem manter a Indexed View e produzir resultados consistentes. Eles são exigidos na criação das tabelas base, da View e do índice; no DML das tabelas participantes; e quando o otimizador usa o índice da View.

| Opção de sessão | Valor exigido | Padrão do servidor | Padrão OLE DB / ODBC | Padrão DB-Library |
| :--- | :---: | :---: | :---: | :---: |
| `ANSI_NULLS` | `ON` | `ON` | `ON` | `OFF` |
| `ANSI_PADDING` | `ON` | `ON` | `ON` | `OFF` |
| `ANSI_WARNINGS` | `ON` | `ON` | `ON` | `OFF` |
| `ARITHABORT` | `ON` | `OFF` | `OFF` | `OFF` |
| `CONCAT_NULL_YIELDS_NULL` | `ON` | `ON` | `ON` | `OFF` |
| `QUOTED_IDENTIFIER` | `ON` | `ON` | `ON` | `OFF` |
| `NUMERIC_ROUNDABORT` | `OFF` | `OFF` | `OFF` | `OFF` |

> [!tip] Valores de conexão
> Em conexões OLE DB ou ODBC, a documentação informa que `ARITHABORT` é o único valor que precisa ser alterado. Não generalize essa conclusão para todos os drivers e ferramentas. Configurar `ANSI_WARNINGS` como `ON` também configura `ARITHABORT` como `ON` implicitamente.

> [!warning] Momento de Exigência das SET Options
> As 7 opções devem estar ativas nas seguintes 3 situações:
> 1. Na criação da View (`CREATE VIEW`) e do Índice (`CREATE UNIQUE CLUSTERED INDEX`).
> 2. Ao executar DML (`INSERT`, `UPDATE`, `DELETE`) em qualquer tabela base referenciada.
> 3. Quando o otimizador usar o índice da View durante a execução de uma consulta.

### Comportamento do Otimizador de Consultas (Indexed View Matching)

O SQL Server possui um mecanismo avançado conhecido como **Automatic Indexed View Matching** (Correspondência Automática de View Indexada):

- **Correspondência Automática (SQL Server Enterprise / Azure SQL Database / Azure SQL Managed Instance):** O Otimizador de Consultas pode identificar que o resultado de uma consulta enviada diretamente contra tabelas base pode ser resolvido de forma mais eficiente lendo o índice pré-calculado de uma Indexed View, mesmo que a View não seja mencionada pelo nome na instrução `SELECT`.
  - O otimizador intercepta a consulta na tabela base, detecta a equivalência lógica/matemática com a definição da View, calcula os custos e substitui a leitura/agregação da tabela base pesada por um Scan ou Seek direto no índice da View.
  - Isso permite acelerar drasticamente o desempenho de relatórios e aplicações legadas sem alterar uma única linha do código SQL original da aplicação.

- **Dica `WITH (NOEXPAND)` no SQL Server Standard:**
  - Ao consultar diretamente uma Indexed View no SQL Server Standard, use `WITH (NOEXPAND)` para utilizar o índice da View.
  - Azure SQL Database e Azure SQL Managed Instance podem usar Indexed Views automaticamente sem a dica. O comportamento deve ser confirmado no plano de execução da plataforma-alvo.

```sql
-- Forçar o uso do índice materializado da View (obrigatório no Standard Edition)
SELECT CustomerID, TotalSpent
FROM dbo.vw_OrderSummary WITH (NOEXPAND)
WHERE CustomerID = 42;
```

---

### Por que o `COUNT_BIG(*)` é Obrigatório em Indexed Views com `GROUP BY`?

Quando uma Indexed View inclui a cláusula `GROUP BY`, a projeção do `SELECT` **deve obrigatoriamente incluir a função de agregação `COUNT_BIG(*)`**. A tentativa de criar um índice clusterizado em uma View com `GROUP BY` omitindo `COUNT_BIG(*)` causará o erro T-SQL `Msg 10138`.

> [!important] Manutenção e agregações
> O SQL Server exige `COUNT_BIG(*)` quando a definição da Indexed View contém `GROUP BY`. `AVG` não é permitido; quando apropriado, exponha `SUM(coluna)` e `COUNT_BIG(*)` separadamente e calcule a média na consulta de leitura. A manutenção dos índices da View também aumenta o custo de DML nas tabelas base, portanto valide esse custo antes de adotá-los em cargas intensivas de escrita.

---

## Views Atualizáveis (Updatable Views)

Uma View simples pode aceitar DML (`INSERT`, `UPDATE` e `DELETE`) que é repassado à tabela base. Em uma View com múltiplas tabelas, cada comando DML pode modificar colunas de apenas uma tabela base, desde que elas sejam mapeadas diretamente. O SQL Server precisa conseguir rastrear a alteração sem ambiguidade até a tabela de destino.

```sql
CREATE VIEW dbo.vw_ActiveCustomers
AS
SELECT CustomerID, Name, Email
FROM Customers
WHERE IsActive = 1
WITH CHECK OPTION; -- Impede inserir registros inativos (IsActive != 1) através da View
```

**Regras para execução de DMLs através de Views:**

- Cada `INSERT`, `UPDATE` ou `DELETE` deve referenciar colunas de apenas uma tabela base.
- Em um `UPDATE`, as colunas alteradas devem pertencer a uma única tabela base e ter mapeamento direto.
- Não conter nenhuma função agregadora (`SUM`, `COUNT`, `AVG`, etc.).
- Não conter as instruções `DISTINCT`, `TOP`, `GROUP BY` ou `HAVING`.
- As colunas sob modificação devem ter correlação física de 1:1 com as colunas reais.

**A cláusula WITH CHECK OPTION** garante que qualquer alteração (`INSERT` ou `UPDATE`) enviada pela View satisfaça o filtro `WHERE` contido na View. Sem esta instrução, seria possível inserir um registro através da View que sumiria imediatamente da listagem da View devido ao seu filtro.

### Triggers INSTEAD OF em Views Complexas

Por padrão, o SQL Server bloqueia operações DML (`INSERT`, `UPDATE`, `DELETE`) em Views complexas que envolvam `JOIN` em múltiplas tabelas, funções de agregação (`SUM`, `COUNT`), `GROUP BY`, `DISTINCT` ou `UNION`. O motor de banco de dados não consegue inferir automaticamente como decompor ou aplicar as alterações nas tabelas base subjacentes (retornando erros como `Msg 4405` ou `Msg 4420`).

O recurso de **Triggers `INSTEAD OF`** resolve essa limitação interceptando totalmente a execução do DML e substituindo o comando padrão por um bloco de código T-SQL customizado.

#### ⚙️ Como Funciona o Mecanismo Interno:

1. **Substituição da Ação Padrão:** Diferente de um trigger tradicional `AFTER` (que roda *depois* da gravação do dado), o trigger `INSTEAD OF` **interrompe** a ação nativa do SQL Server. A gravação padrão na View é abortada e apenas o código T-SQL contido dentro do trigger é executado.
2. **Uso das Tabelas Virtuais `inserted` e `deleted`:** Dentro do trigger, o desenvolvedor acessa as tabelas temporárias em memória `inserted` (com os novos dados enviados pelo comando DML) e `deleted` (com os dados antigos).
3. **Distribuição Manual de DML:** O código do trigger decompõe os dados recebidos e distribui os comandos `INSERT`/`UPDATE`/`DELETE` manualmente entre as tabelas base envolvidas em uma transação segura.

#### 💻 Exemplo Prático: Tornando Atualizável uma View com JOIN

```sql
-- 1. View complexa unindo duas tabelas (Customers e CustomerAddresses)
CREATE VIEW dbo.vw_CustomerFullDetails
AS
SELECT 
    c.CustomerId,
    c.Name,
    c.Email,
    a.AddressLine1,
    a.City
FROM dbo.Customers c
JOIN dbo.CustomerAddresses a ON a.CustomerId = c.CustomerId;
GO

-- 2. Criar Trigger INSTEAD OF INSERT para distribuir os dados entre as 2 tabelas
CREATE TRIGGER trg_vw_CustomerFullDetails_Insert
ON dbo.vw_CustomerFullDetails
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Inserir o Cliente na primeira tabela base e capturar o CustomerId gerado
    DECLARE @NewCustomerTable TABLE (CustomerId INT);

    INSERT INTO dbo.Customers (Name, Email)
    OUTPUT INSERTED.CustomerId INTO @NewCustomerTable
    SELECT Name, Email FROM inserted;

    -- Inserir o Endereço na segunda tabela base usando o CustomerId recém-gerado
    INSERT INTO dbo.CustomerAddresses (CustomerId, AddressLine1, City)
    SELECT n.CustomerId, i.AddressLine1, i.City
    FROM inserted i
    CROSS JOIN @NewCustomerTable n;
END;
GO

-- 3. A aplicação agora pode fazer INSERT diretamente na View com JOIN!
INSERT INTO dbo.vw_CustomerFullDetails (Name, Email, AddressLine1, City)
VALUES ('Ana Silva', 'ana@email.com', 'Av. Paulista, 1000', 'São Paulo');
```

> [!warning] Pegadinhas Importantes para o Exame DP-800
> 
> * **Apenas Triggers `INSTEAD OF` em Views:** Views **NÃO** suportam triggers do tipo `AFTER`. Apenas tabelas físicas aceitam triggers `AFTER`.
> * **Limite de 1 Trigger por Operação:** Cada operação DML (`INSERT`, `UPDATE` ou `DELETE`) em uma View pode ter **no máximo um** trigger `INSTEAD OF`.
> * **Sobrescrita do `WITH CHECK OPTION`:** Se a View possui a instrução `WITH CHECK OPTION`, mas contém um trigger `INSTEAD OF`, o SQL Server **ignora** o `WITH CHECK OPTION` para aquela operação. A validação das regras passa a ser responsabilidade exclusiva do código contido no trigger!

---

## Limitações das Views (View Limitations)

O SQL Server impõe regras estritas sobre o que pode e o que não pode ser incluído na definição de uma View. As limitações variam significativamente entre **Views Tradicionais (Standard Views)** e **Views Indexadas (Indexed Views)**.

---

### 1. Limitações Universais (Views Tradicionais e Indexadas)

* **Proibição de Parâmetros:** Views não aceitam parâmetros de entrada (`CREATE VIEW dbo.vw_Test (@Id INT)` é sintaxe inválida). Se você precisa de lógica parametrizada que retorne um conjunto de linhas, deve utilizar uma **Inline Table-Valued Function (iTVF)**.
* **Proibição de Tabelas Temporárias e Variáveis de Tabela:** Uma View não pode referenciar tabelas temporárias locais ou globais (`#temp`, `##temp`) nem variáveis do tipo tabela (`@table`). Elas devem referenciar apenas objetos permanentes do banco de dados.
* **Comportamento e Proibição de Ordenação (`ORDER BY`):** 
  * Pelo padrão da álgebra relacional, uma View é uma tabela virtual que representa um conjunto não ordenado de dados.
  * A documentação de `CREATE VIEW` permite `ORDER BY` quando há `TOP` na lista de seleção. Mesmo nessa situação, a ordenação não é garantida quando a View é consultada; a consulta externa deve conter seu próprio `ORDER BY`.
  * > [!warning] Pegadinha Clássica de Exame: ORDER BY com TOP 100 PERCENT
    > Mesmo que você contorne a regra usando `CREATE VIEW ... SELECT TOP (100) PERCENT ... ORDER BY ColunaA`, o Otimizador de Consultas do SQL Server **ignora a ordenação interna da View** ao executar `SELECT * FROM sua_view`. A ordenação de exibição dos resultados só é garantida se a consulta cliente externa contiver seu próprio `ORDER BY`.

---

### 2. Limitações Específicas de Views Indexadas (Indexed Views)

Para que o SQL Server consiga materializar e manter o índice clusterizado da View de forma determinística e incremental a cada DML, as seguintes construções são **estritamente proibidas em Indexed Views**:

| Limitação | Por que é Proibido em Indexed Views? (Mecanismo Interno) | Alternativa / Regra Obrigatória |
| :--- | :--- | :--- |
| **`OUTER JOIN` (`LEFT`, `RIGHT`, `FULL`)** | Junções externas geram linhas preenchidas com `NULL` quando não há correspondência. A manutenção incremental dessas linhas durante inserções e exclusões nas tabelas base seria ambígua para o motor de índice. | Utilize apenas **`INNER JOIN`** e referencie tabelas com nomes de 2 partes (`dbo.Tabela`). |
| **Funções Não Determinísticas (`GETDATE()`, `NEWID()`, `RAND()`)** | Funções que retornam resultados diferentes a cada chamada invalidariam os dados salvos em disco na árvore B do índice clusterizado. | Utilize apenas funções determinísticas (ex: `ISNULL()`, `DATEADD()`, `YEAR()`). |
| **Subqueries no `FROM` e CTEs** | Tabelas derivadas e CTEs (`WITH CTE AS (...)`) criam estruturas lógicas intermediárias que impedem o otimizador de mapear a rastreabilidade 1:1 das chaves do índice. | Reescreva a View utilizando apenas `JOIN`s diretos entre tabelas base físicas. |
| **`DISTINCT`** | O operador `DISTINCT` exige a desduplicação dinâmica em memória, que não pode ser mantida de forma incremental a cada `INSERT`/`DELETE`. | Substitua `DISTINCT` por **`GROUP BY`** e inclua a função obrigatória **`COUNT_BIG(*)`**. |
| **`UNION`, `UNION ALL`, `EXCEPT`, `INTERSECT`** | Operações de conjunto combinam múltiplos result sets que impossibilitam rastrear qual tabela base originou cada alteração incremental. | Crie Views indexadas separadas para cada tabela e faça o `UNION` na consulta de leitura externa. |
| **Consultas Cross-Database / Cross-Server** | A Indexed View só pode referenciar tabelas base do mesmo banco de dados; a View e as tabelas também precisam ter o mesmo proprietário. | Mantenha as tabelas base no mesmo banco de dados e preserve uma cadeia de propriedade intacta. |
| **Outras Views** | Uma Indexed View não pode referenciar outra View. | Referencie diretamente as tabelas base elegíveis. |

---

## Casos de Uso (Use Cases)

- **Segurança e Mascaramento**: Expor apenas determinadas linhas ou colunas sem expor as tabelas físicas aos usuários.
- **Simplificação de Consultas**: Encapsular JOINS extensos para fácil reuso.
- **Indexed Views**: Pré-calcular somas e contagens de grandes tabelas analíticas para painéis e dashboards.
- **Abstração Atualizável**: Expor uma subseção restrita de dados enquanto valida a integridade com `WITH CHECK OPTION`.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| Bloqueio ao apagar tabela | A View utiliza o modificador `SCHEMABINDING` | Apague a View referenciada primeiro, ou remova o Schemabinding com `ALTER VIEW`. |
| A Indexed View não é utilizada na query | Requisitos de `SET` não atendidos ou uso do SQL Server Standard sem o hint | Verifique os requisitos de `SET`; no SQL Server Standard, use `WITH (NOEXPAND)` ao consultar a View diretamente. |
| Metadados da View estão desatualizados | Um objeto base de uma View sem `SCHEMABINDING` mudou de estrutura | Execute `sp_refreshview` quando aplicável. Views indexadas são mantidas quando ocorre DML nas tabelas base. |
| Falha ao criar index na View | Função não determinística na definição | Elimine o uso de `GETDATE()`, `NEWID()`, etc. por opções determinísticas. |
| Falha em DML enviado à View | A View une tabelas ou possui agregações | Implemente um trigger `INSTEAD OF` ou envie a gravação direto à tabela base correspondente. |

---

## Melhores Práticas (Best Practices)

- Adote `WITH SCHEMABINDING` em Views críticas de produção ou destinadas à indexação para impedir que desvios de esquema quebrem as aplicações.
- Utilize `WITH CHECK OPTION` em Views filtradas expostas a gravações DML para impedir a inserção de dados inconsistentes através da View.
- Utilize o prefixo `vw_` ou `v_` para diferenciar visualmente as Views das tabelas base em scripts e navegadores de objetos do SSMS.
- Evite declarar o uso de `SELECT *` na View — liste todas as colunas de forma explícita para evitar que alterações na tabela base alterem as colunas da View sem controle.
- Para consultar diretamente uma Indexed View no SQL Server Standard, use `WITH (NOEXPAND)` quando precisar garantir o uso de seu índice. Valide o plano de execução e os requisitos de `SET`.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - As Indexed Views exigem a definição `WITH SCHEMABINDING` e a criação de um `UNIQUE CLUSTERED INDEX` como primeiro index.
> - A função de contagem obrigatória em agrupamentos em Indexed Views é `COUNT_BIG(*)` — o uso do `COUNT(*)` clássico barra a criação do index.
> - No SQL Server Standard, use `WITH (NOEXPAND)` ao consultar diretamente a Indexed View. Azure SQL Database e Azure SQL Managed Instance podem usar Indexed Views automaticamente quando os requisitos de `SET` são atendidos.
> - Funções não determinísticas como `GETDATE()` impedem a indexação física de uma View.
> - O comando `WITH CHECK OPTION` impede modificações estruturais DML que fujam da cláusula `WHERE` da View, evitando "linhas invisíveis" após inserções.

---

## Resumo dos Conceitos (Key Takeaways)

- As Views comuns são meras definições lógicas virtuais — nenhum dado é gravado no disco (salvo na presença de index).
- O Schemabinding impede alterações acidentais nas estruturas das tabelas base e viabiliza a criação de indexes sobre a View.
- As Indexed Views gravam fisicamente os resultados analíticos no disco de forma materializada.
- A restrição `WITH CHECK OPTION` assegura a conformidade dos dados modificados através da View.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Um desenvolvedor declara uma View utilizando o modificador `WITH SCHEMABINDING` e tenta criar um Clustered Index exclusivo sobre ela, porém recebe uma falha de compilação. Qual dos cenários abaixo é o principal motivo dessa falha?

A. A View faz referência a uma coluna calculada baseada em uma função não determinística como `GETDATE()`.

B. A View realiza um `INNER JOIN` entre duas tabelas de dados.

C. A View inclui a coluna de chave primária em sua cláusula de `SELECT`.

D. As tabelas base associadas possuem um Columnstore Index configurado.

> [!success]- Resposta
> **A — A View faz referência a uma coluna calculada baseada em uma função não determinística como `GETDATE()`**
>
> As Indexed Views exigem que todas as colunas sejam puramente determinísticas (ou seja, retornem sempre o mesmo valor exato para o mesmo conjunto de entradas). A função `GETDATE()` é não determinística por natureza, impedindo a criação física do index sobre os dados da View. Joins tradicionais (B) e inclusão de chaves primárias (C) são permitidos normalmente. Columnstore indexes (D) nas tabelas base não restringem a indexação da View.

---

## Tópicos Relacionados

- [02-Functions](./02-functions.md) *(Inglês apenas)*
- [03-Stored Procedures](./03-stored-procedures.md) *(Inglês apenas)*

---

## Documentação Oficial

- [Views (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/views/views)
- [Create Indexed Views](https://learn.microsoft.com/en-us/sql/relational-databases/views/create-indexed-views)

---

**[↑ Voltar para a Seção](./programmability-objects.md) | [Próximo →](./02-functions.md)**
