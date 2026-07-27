---
title: "Livro de Exercícios — Fundamentos do SQL Server"
type: workbook
tags: [sql-server, tsql, fundamentals, practice]
---

# Livro de Exercícios — Fundamentos do SQL Server

Este livro de exercícios é o companheiro prático e autossuficiente da Parte 0. Leia-o enquanto executa os scripts em [`practice/labs/00-fundamentals/`](../../practice/labs/00-fundamentals/). Ele deliberadamente para antes de tipos de tabela especializados, procedimentos armazenados, planos de consulta e recursos de IA; esses são abordados nas seções mapeadas para o exame.

> [!abstract]
>
> - Aprenda o modelo mental antes de memorizar palavras-chave.
> - Construa um pequeno banco de dados de vendas e interrogue-o de vários ângulos.
> - Use os exercícios de verificação antes de prosseguir para a Seção 01.

> [!tip] Como usar este livro de exercícios
>
> Execute um bloco de código somente após lê-lo. Altere um valor, execute novamente e preveja o resultado antes de olhar a saída. Esse pequeno hábito é como a sintaxe se transforma em compreensão.

---

## 1. O modelo mental de banco de dados

Pense em um banco de dados como uma coleção cuidadosamente governada de fatos relacionados. Uma planilha pode conter colunas chamadas `Customer`, `Order` e `Product`, mas um banco de dados relacional separa cada tipo de fato em sua própria tabela e conecta as tabelas com valores chamados chaves.

```text
Instância do SQL Server
└── Banco de dados StudyDB
    └── Schema study
        ├── Tabela Customer
        ├── Tabela Product
        └── Tabela SalesOrder
```

A distinção é importante:

| Termo | Significado | Exemplo |
| :--- | :--- | :--- |
| Instância | Mecanismo SQL Server em execução | `localhost` ou `SERVER01\SQLEXPRESS` |
| Banco de dados | Coleção contida de objetos e dados | `StudyDB` |
| Schema | Namespace que agrupa objetos do banco | `study` ou `dbo` |
| Tabela | Coleção nomeada de linhas com formato similar | `study.Customer` |
| Coluna | Um atributo armazenado para cada linha | `CustomerName` |
| Linha | Um registro | um cliente |

Use um nome de duas partes como `study.Customer`. O SQL Server pode resolver um nome de uma parte como `Customer`, mas nomes de schema explícitos evitam ambiguidades e tornam-se essenciais em bancos de dados reais.

### Entidades, atributos e relacionamentos

Uma **entidade** é algo que o negócio deseja lembrar: um cliente, produto ou pedido. Um **atributo** é um fato sobre uma entidade: um cliente tem nome e email; um pedido tem data e total. Um **relacionamento** expressa como as entidades se conectam: cada pedido pertence a um cliente; um cliente pode ter zero, um ou muitos pedidos.

É por isso que `CustomerName` não deve ser copiado para cada linha de pedido. Se um nome mudar, uma linha de cliente é alterada. Repetí-lo em cada pedido arrisca um histórico inconsistente e armazenamento desperdiçado.

> [!note] Modelo mental — tabelas
> Uma tabela não é meramente uma grade. É um contrato: cada linha representa o mesmo tipo de coisa, e cada coluna tem um significado consistente.

### Chaves

Uma **chave primária** identifica unicamente uma linha. `CustomerId = 1` significa um cliente específico, independentemente de duas pessoas compartilharem o mesmo nome. Uma **chave estrangeira** armazena um valor de chave primária de outra tabela, permitindo que um pedido aponte para seu cliente.

```text
Customer                          SalesOrder
------------------------          --------------------------
CustomerId  (chave primária) <--- CustomerId (chave estrangeira)
CustomerName                      SalesOrderId (chave primária)
                                  OrderDate
```

Não confunda uma chave com um rótulo visível. Um nome de produto pode ser editado e pode ser duplicado. Identificadores numéricos ou gerados são frequentemente usados como chaves substitutas estáveis, enquanto uma restrição `UNIQUE` protege um identificador natural de negócio, como um endereço de email, quando essa regra se aplica.

## 2. Tipos de dados e informação ausente

Toda coluna precisa de um tipo de dados. Ele informa ao SQL Server o que o valor significa, como pode ser comparado e quanto espaço pode usar.

| Necessidade | Tipo inicial recomendado | Por quê |
| :--- | :--- | :--- |
| Identificador ou contagem de número inteiro | `int` | Valores inteiros exatos |
| Contagem muito grande | `bigint` | Maior intervalo de inteiros |
| Preço, valor, porcentagem | `decimal(p, s)` | Precisão fixa exata |
| Texto curto ou longo | `nvarchar(n)` | Texto Unicode |
| Apenas data | `date` | Sem parte acidental de hora |
| Data e hora | `datetime2` | Tipo moderno preciso de data/hora |
| Fato sim/não | `bit` | Armazena 0, 1 ou `NULL` |

`decimal(10, 2)` significa até dez dígitos no total, com dois dígitos após o separador decimal. É adequado para os preços de brinquedo no `StudyDB`; não é um design universal para dinheiro. Escolha a precisão baseada no maior valor de negócio válido e sua escala requerida.

### `NULL`: desconhecido, ausente ou não aplicável

`NULL` é um marcador para informação faltante. Não é `0`, `''` nem a palavra `'NULL'`. Isso muda a filtragem porque o SQL usa lógica de três valores: uma comparação pode ser verdadeira, falsa ou desconhecida. Uma linha cujo email é `NULL` não satisfaz `Email = 'ana@example.test'`, mas também não satisfaz `Email <> 'ana@example.test'`.

```sql
-- Correto: testa a presença de um valor.
SELECT CustomerName
FROM study.Customer
WHERE Email IS NULL;

-- Incorreto: igualdade não testa NULL.
SELECT CustomerName
FROM study.Customer
WHERE Email = NULL;
```

Use `NOT NULL` quando o negócio não puder criar uma linha válida sem aquele atributo. Não use um placeholder inventado como `unknown@example.test` meramente para evitar `NULL`; isso finge que um valor é conhecido quando não é.

### Verifique-se

1. Uma data de pedido deveria ser `nvarchar(20)` ou `date`? Por quê?
2. Uma string vazia é o mesmo fato que um endereço de email desconhecido?
3. O que um predicado deve usar para encontrar valores ausentes?

<details>
<summary>Respostas</summary>

1. `date`, porque carrega semântica de data e suporta comparações de data confiáveis.
2. Não. Uma string vazia é um valor de texto conhecido sem caracteres; `NULL` significa que o valor não é conhecido ou não se aplica.
3. `IS NULL`.

</details>

## 3. Defina a estrutura antes dos dados

DDL (linguagem de definição de dados) cria ou altera objetos. DML (linguagem de manipulação de dados) trabalha com linhas. A ordem é importante: primeiro defina o contrato, depois carregue fatos que estejam em conformidade com ele.

```sql
CREATE TABLE study.Product (
    ProductId int IDENTITY(1, 1) NOT NULL,
    ProductName nvarchar(100) NOT NULL,
    UnitPrice decimal(10, 2) NOT NULL,
    CreatedAt datetime2 NOT NULL DEFAULT sysdatetime(),
    CONSTRAINT PK_Product PRIMARY KEY (ProductId),
    CONSTRAINT CK_Product_UnitPrice CHECK (UnitPrice >= 0)
);
```

Leia esta definição lentamente:

- `IDENTITY(1, 1)` pede ao SQL Server para gerar valores começando em 1 e incrementando em 1. Isso **não** promete números sem lacunas.
- `NOT NULL` rejeita valores ausentes.
- `DEFAULT sysdatetime()` fornece um valor apenas quando um insert omite a coluna.
- As restrições de chave primária e check protegem regras na fronteira do banco de dados.

A ordem das colunas em uma tabela não é um contrato para o código da aplicação. Sempre nomeie colunas em uma instrução `INSERT`.

```sql
INSERT INTO study.Product (ProductName, UnitPrice)
VALUES (N'Notebook', 12.50);
```

O prefixo `N` marca um literal de string Unicode. É um hábito útil ao inserir em colunas `nvarchar`.

> [!warning] Erro Comum
> `DROP TABLE` remove tanto a definição de uma tabela quanto seus dados. Em um banco de dados de aprendizado pode ser conveniente; em um banco de dados compartilhado ou de produção é uma operação destrutiva que precisa de controle de alterações deliberado.

## 3.5 Escolha uma edição para aprendizado

Antes de instalar o SQL Server, distinga a edição do mecanismo da ferramenta de consulta. O SSMS é um aplicativo cliente; ele pode conectar-se a todas as três edições abaixo. A edição é o pacote de recursos, capacidade e licença do mecanismo.

| Edição | Licença e uso pretendido | Principais vantagens | Principal limitação |
| :--- | :--- | :--- | :--- |
| Express | Gratuita; pequenas aplicações de produção são permitidas | Banco de dados local leve, T-SQL básico, distribuição gratuita | Limites de capacidade e sem SQL Server Agent |
| Developer / Enterprise Developer | Gratuita; apenas desenvolvimento e teste | Conjunto de recursos Enterprise para aprendizado e teste | Não pode servir cargas de trabalho de produção |
| Enterprise | Paga; produção | Maior escala e capacidades de produção Enterprise | Requer a licença paga apropriada |

### Express é pequena por design

Express é suficiente para executar os primeiros laboratórios: tabelas, restrições, DML, JOINs, agregação e índices básicos funcionam. É uma escolha sensata para uma pequena aplicação desktop ou um aluno que só precisa de SQL básico.

Não a confunda com uma plataforma de teste em escala completa. No SQL Server 2025, Express é limitada ao menor de um soquete ou quatro núcleos, cerca de 1,4 GB de memória buffer-pool e 50 GB para um banco de dados relacional. Também não tem SQL Server Agent, então tarefas agendadas do SQL Agent não podem ser praticadas no Express. Essas restrições podem mudar entre versões principais; o SQL Server 2022, por exemplo, tem limites de tamanho de banco de dados diferentes.

### Developer é o ambiente de estudo recomendado

Developer dá ao aluno o conjunto de recursos Enterprise sem custo de aquisição. É o padrão correto para todo o caminho DP-800 porque módulos posteriores podem precisar de recursos, escala ou ferramentas operacionais que não estão disponíveis ou são menos representativos no Express.

A contrapartida é legal, não técnica: Developer deve ser usado apenas para desenvolvimento e teste. Um laptop pessoal de estudo, uma máquina de desenvolvimento local e uma VM descartável são apropriados. Um servidor processando pedidos ao vivo de uma empresa não é.

O SQL Server 2025 chama a edição equivalente de **Enterprise Developer**. Versões anteriores chamam-na simplesmente de **Developer**. O SQL Server 2025 também oferece **Standard Developer**, que espelha a Standard Edition em vez da Enterprise; o conselho deste livro de exercícios sobre "Developer" refere-se ao Enterprise Developer/à edição Developer histórica.

### Enterprise é para produção licenciada

Enterprise é a edição paga projetada para organizações que precisam de sua escala de produção e capacidades exclusivas do Enterprise. Não é necessária para este guia de estudo: Enterprise Developer permite que você aprenda o conjunto de recursos compatível. Por outro lado, um ambiente de produção não pode usar Developer como substituto gratuito do Enterprise.

> [!warning] Não escolha apenas pelo preço
> Express ser gratuito não a torna equivalente ao Developer, e Developer ser gratuito não o torna legal para produção. Escolha baseando-se tanto nos requisitos de carga de trabalho quanto nos direitos de licença.

### Uma escolha simples

| Sua situação | Edição recomendada |
| :--- | :--- |
| Aprender todo o caminho DP-800 localmente | Developer / Enterprise Developer |
| Aprender T-SQL básico ou construir uma aplicação pequena e limitada | Express |
| Executar uma carga de trabalho real que requer capacidades Enterprise | Enterprise devidamente licenciada |

## 4. Leia dados em uma ordem previsível

A forma de consulta mais útil é fácil de dizer em voz alta:

```text
SELECT colunas
FROM fonte
WHERE condições de linhas
GROUP BY colunas de agrupamento
HAVING condições de grupo
ORDER BY ordem final
```

Você não usa sempre todas as cláusulas. A ordem de processamento conceitual, no entanto, explica muitas surpresas: `WHERE` filtra linhas antes do agrupamento, enquanto `ORDER BY` ordena o resultado final.

```sql
SELECT p.ProductName AS product_name,
       p.UnitPrice AS unit_price
FROM study.Product AS p
WHERE p.UnitPrice >= 5.00
  AND p.ProductName LIKE N'%note%'
ORDER BY p.UnitPrice DESC, p.ProductName ASC;
```

### Predicados que você usará frequentemente

| Predicado | Significado | Exemplo |
| :--- | :--- | :--- |
| `=` / `<>` | Igual / diferente | `IsActive = 1` |
| `AND` | Ambas as condições devem ser verdadeiras | preço e status |
| `OR` | Qualquer condição pode ser verdadeira | duas cidades |
| `IN` | Corresponde a um membro de uma lista | `Status IN ('New', 'Paid')` |
| `BETWEEN` | Limites inferior e superior inclusivos | `BETWEEN 10 AND 20` |
| `LIKE` | Correspondência de padrão | `N'A%'` |
| `IS NULL` | Informação ausente | `Email IS NULL` |

`LIKE N'%note%'` encontra texto contendo `note`; `%` significa qualquer número de caracteres e `_` significa exatamente um caractere. Não é um substituto para pesquisa de texto completo, que você encontrará mais adiante no guia.

Parênteses tornam uma condição mista inequívoca:

```sql
WHERE IsActive = 1
  AND (Email IS NULL OR Email LIKE N'%@example.test')
```

`DISTINCT` remove combinações de resultado duplicadas. Se você precisar dele inesperadamente, inspecione o JOIN ou o modelo de dados primeiro; ele pode esconder um predicado de relacionamento incorreto.

### Verifique-se

Escreva uma consulta que retorne clientes ativos sem email, ordenados por nome. Então explique por que `ORDER BY` é necessário mesmo que a saída atual já pareça alfabética.

<details>
<summary>Uma resposta</summary>

```sql
SELECT CustomerName
FROM study.Customer
WHERE IsActive = 1
  AND Email IS NULL
ORDER BY CustomerName;
```

Sem `ORDER BY`, o SQL Server não promete uma ordem estável de linhas.
</details>

## 5. Combine fatos com JOINs

JOINs colocam linhas relacionadas lado a lado. Comece identificando a tabela cujas linhas você deseja preservar, então escolha o tipo de junção.

| Junção | Retorna | Pergunta típica |
| :--- | :--- | :--- |
| `INNER JOIN` | Apenas correspondências de ambos os lados | Quais clientes têm pedidos? |
| `LEFT JOIN` | Todas as linhas da esquerda; linhas da direita correspondentes quando disponíveis | Quais clientes, incluindo aqueles sem pedidos? |
| `RIGHT JOIN` | Todas as linhas da direita | Geralmente reescreva como left join para legibilidade |
| `FULL OUTER JOIN` | Correspondências mais linhas não correspondidas de ambos os lados | Conciliar duas listas |
| `CROSS JOIN` | Toda combinação esquerda/direita | Gerar uma matriz deliberada |

```sql
SELECT c.CustomerName, o.OrderDate, o.OrderTotal
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
ORDER BY c.CustomerName, o.OrderDate;
```

Quando a Carla não tem pedido, o `LEFT JOIN` retorna Carla e preenche `o.OrderDate` e `o.OrderTotal` com `NULL`. Essa é a informação esperada: nenhuma linha correspondente do lado direito existe.

### A armadilha do posicionamento do filtro

Suponha que você queira todos os clientes, mas apenas pedidos de julho. Isso é sutilmente diferente:

```sql
-- Mantém todos os clientes; pedidos não-julho simplesmente não correspondem.
SELECT c.CustomerName, o.OrderDate
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
   AND o.OrderDate >= '2026-07-01';

-- Remove clientes sem um pedido qualificado.
SELECT c.CustomerName, o.OrderDate
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
WHERE o.OrderDate >= '2026-07-01';
```

A segunda consulta filtra após a junção e rejeita linhas onde `o.OrderDate` é `NULL`; ela se comporta como um inner join para essa condição.

> [!warning] Erro Comum
> Nunca junte tabelas meramente porque ambas têm uma coluna chamada `Id`. Junte pelo relacionamento documentado, normalmente chave estrangeira para chave primária.

## 6. Resuma sem perder significado

Agregação transforma muitas linhas em um resumo menor. Primeiro declare o grão da pergunta: "uma linha por cliente", "uma linha por mês" ou "um valor para todo o banco de dados".

```sql
SELECT o.CustomerId,
       COUNT(*) AS order_count,
       SUM(o.OrderTotal) AS total_spend,
       AVG(o.OrderTotal) AS average_order
FROM study.SalesOrder AS o
GROUP BY o.CustomerId
HAVING SUM(o.OrderTotal) >= 20.00;
```

Toda expressão selecionada deve descrever o grupo (`CustomerId`) ou reduzir o grupo (`SUM`, `COUNT`, `AVG`, `MIN`, `MAX`). O SQL Server rejeita um `OrderDate` simples aqui porque um cliente pode ter muitas datas diferentes.

`COUNT(*)` conta linhas. `COUNT(Email)` conta apenas linhas onde `Email` não é `NULL`. Isso é útil, mas escolha deliberadamente.

`COALESCE(SUM(o.OrderTotal), 0.00)` transforma a soma `NULL` de um cliente sem pedidos em um zero explícito para exibição. Isso não altera os dados subjacentes.

### `WHERE` versus `HAVING`

Use `WHERE` para uma condição de pedido individual, como apenas pedidos de julho. Use `HAVING` para uma condição no grupo de cliente computado, como clientes cuja soma é pelo menos 20.

```sql
SELECT CustomerId, SUM(OrderTotal) AS july_total
FROM study.SalesOrder
WHERE OrderDate >= '2026-07-01'
  AND OrderDate < '2026-08-01'
GROUP BY CustomerId
HAVING SUM(OrderTotal) >= 20.00;
```

O intervalo de datas semi-aberto é mais seguro do que terminar em um timestamp tarde da noite quando uma coluna inclui hora.

## 7. Altere dados com segurança

`INSERT`, `UPDATE` e `DELETE` alteram estado. O hábito universal de segurança é simples: transforme o predicado em um `SELECT`, inspecione as linhas exatas, então faça a alteração em uma transação quando uma janela de rollback for útil.

```sql
BEGIN TRAN;

SELECT ProductId, ProductName, UnitPrice
FROM study.Product
WHERE ProductName = N'Pen';

UPDATE study.Product
SET UnitPrice = 2.25
WHERE ProductName = N'Pen';

SELECT ProductId, ProductName, UnitPrice
FROM study.Product
WHERE ProductName = N'Pen';

ROLLBACK;
```

`ROLLBACK` desfaz o trabalho não confirmado nesta transação. Substitua por `COMMIT` apenas quando você tiver revisado o resultado e a transação contiver exatamente o que você pretendia.

### Transações são limites

Uma transação agrupa operações que devem ter sucesso ou falhar juntas. Considere mover dinheiro de um saldo para outro: registrar apenas a subtração deixaria dados incorretos. Transações também são importantes para concorrência, mas níveis de isolamento, bloqueio e deadlocks pertencem à seção de performance.

> [!warning] Erro Comum
> Uma transação deixada aberta pode travar dados e bloquear outras sessões. Mantenha o trabalho e o tempo entre `BEGIN TRAN` e `COMMIT`/`ROLLBACK` curtos.

## 8. Coloque regras de integridade no banco de dados

Aplicações cometem erros, scripts são reexecutados e novas ferramentas podem escrever no mesmo banco de dados. Restrições protegem os dados independentemente do ponto de entrada.

| Restrição | Regra que impõe | Exemplo |
| :--- | :--- | :--- |
| `PRIMARY KEY` | identidade de linha única e não nula | um `CustomerId` por cliente |
| `FOREIGN KEY` | linha pai deve existir | pedido tem um cliente real |
| `NOT NULL` | fato é obrigatório | nome do produto |
| `UNIQUE` | nenhum valor de negócio repetido | email se regras de negócio exigirem unicidade |
| `CHECK` | predicado no nível da linha | preço não pode ser negativo |
| `DEFAULT` | coluna omitida recebe um valor | timestamp de criação |

```sql
ALTER TABLE study.SalesOrder
ADD CONSTRAINT FK_SalesOrder_Customer
    FOREIGN KEY (CustomerId)
    REFERENCES study.Customer(CustomerId);
```

Uma chave estrangeira não torna um pedido obrigatório para todo cliente. Significa que *se* um pedido tem um `CustomerId`, o cliente referenciado deve existir. Opcionalidade vem de se a coluna filha permite `NULL`, mas não a torne anulável a menos que um pedido sem um cliente faça sentido para o negócio.

Restrições rejeitam escritas inválidas precocemente. Isso é uma funcionalidade, não um inconveniente: um erro no momento da inserção é mais fácil de reparar do que dados corrompidos descobertos meses depois.

## 9. Divida consultas complexas em etapas nomeadas

Uma subconsulta está aninhada dentro de outra instrução. É útil quando uma consulta produz o conjunto ou valor necessário por outra.

```sql
SELECT CustomerId, OrderTotal
FROM study.SalesOrder
WHERE OrderTotal > (
    SELECT AVG(OrderTotal)
    FROM study.SalesOrder
);
```

Uma CTE (expressão de tabela comum) dá a uma consulta intermediária um nome para a *única instrução que a segue imediatamente*.

```sql
WITH CustomerTotals AS (
    SELECT CustomerId, SUM(OrderTotal) AS TotalSpend
    FROM study.SalesOrder
    GROUP BY CustomerId
)
SELECT c.CustomerName, ct.TotalSpend
FROM CustomerTotals AS ct
INNER JOIN study.Customer AS c
    ON c.CustomerId = ct.CustomerId
WHERE ct.TotalSpend >= 20.00;
```

A CTE não criou uma tabela, visão ou cache que você possa usar no próximo lote. É uma ferramenta de legibilidade. O otimizador escolhe como executar a instrução inteira; não assuma que uma CTE é automaticamente mais rápida ou mais lenta que uma subconsulta.

### Escolhendo uma forma

- Use uma subconsulta simples quando ela tornar o predicado imediatamente legível.
- Use uma CTE quando nomear uma etapa tornar uma consulta de múltiplas etapas mais fácil de revisar.
- Use uma tabela física apenas quando a tarefa realmente precisar de dados persistidos; essa decisão está além deste caminho pré-requisito.

## 10. Índices: cópias úteis com um custo

O SQL Server armazena linhas de tabela e pode manter estruturas adicionais chamadas índices. Um índice é útil quando ajuda a localizar um pequeno conjunto relevante em vez de ler muitas linhas. Ele consome armazenamento e deve ser mantido durante inserts, updates e deletes.

```sql
CREATE INDEX IX_SalesOrder_OrderDate
    ON study.SalesOrder (OrderDate);
```

Este índice pode ajudar consultas filtradas por data ou ordenadas por data. Se realmente ajuda depende do volume de dados, seletividade, estatísticas e do resto da consulta. Um índice em toda coluna não é uma estratégia.

| Tipo | Modelo mental para iniciantes | Limite importante |
| :--- | :--- | :--- |
| Índice clusterizado | Arranjo físico primário de linhas | Um por tabela |
| Índice não clusterizado | Estrutura de busca separada com valores de chave | Muitos são possíveis, mas cada um tem um custo |

Chaves primárias criam um índice por padrão. A escolha exata clusterizado/não clusterizado é configurável, então inspecione a definição em vez de assumir que toda chave primária é clusterizada.

> [!note] Modelo mental — índices
> Um índice se assemelha ao índice de um livro: ajuda a encontrar um tópico rapidamente, mas alguém precisa atualizá-lo quando o conteúdo do livro muda.

O design detalhado de índices, colunas incluídas, columnstore, índices JSON e análise de planos de execução começam nas próximas seções.

## 11. Capstone: responda a uma pergunta de negócio

Use os dados do `StudyDB` para escrever um relatório com uma linha por cliente. Deve mostrar o nome do cliente, número de pedidos, total gasto, e incluir clientes que nunca pediram. Ordene do maior gasto para o menor e exiba zero em vez de `NULL` para pedidos ausentes.

<details>
<summary>Uma solução</summary>

```sql
SELECT c.CustomerName,
       COUNT(o.SalesOrderId) AS order_count,
       COALESCE(SUM(o.OrderTotal), 0.00) AS total_spend
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
GROUP BY c.CustomerName
ORDER BY total_spend DESC, c.CustomerName ASC;
```

`LEFT JOIN` retém todos os clientes; `COUNT(o.SalesOrderId)` retorna zero para um cliente sem pedidos correspondentes; `SUM` precisa de `COALESCE` porque a soma de nenhum valor correspondente é `NULL`.
</details>

## 12. Antes de prosseguir

Você não precisa memorizar toda palavra-chave. Você precisa ser capaz de explicar as escolhas em seu código e detectar consultas inseguras ou ambíguas.

- [ ] Consigo distinguir uma instância, banco de dados, schema, tabela, coluna e linha.
- [ ] Consigo escolher tipos básicos e lidar com `NULL` deliberadamente.
- [ ] Consigo criar uma tabela, inserir linhas e ler um resultado filtrado e ordenado.
- [ ] Consigo selecionar um JOIN apropriado e explicar suas linhas não correspondidas.
- [ ] Consigo declarar o nível de agrupamento de uma consulta agregada e escolher `WHERE` ou `HAVING`.
- [ ] Eu pré-visualizo DML e sei quando usar `ROLLBACK`.
- [ ] Consigo explicar como chaves e restrições protegem dados.
- [ ] Sei que índices trocam custo de manutenção por eficiência potencial de leitura.

Se alguma resposta for incerta, repita o laboratório relevante e altere os dados de amostra para observar o resultado. Quando a lista de verificação parecer confortável, continue para [01 — Database Objects](../01-database-objects/database-objects.md).

## Tópicos Relacionados

- [Parte 0 — Rota de aprendizado](./fundamentals.md)
- [Database Objects](../01-database-objects/database-objects.md)
- [Advanced T-SQL](../03-advanced-tsql/advanced-tsql.md)

---

**[← Voltar à Parte 0](./fundamentals.md) | [Iniciar Seção 01 →](../01-database-objects/database-objects.md)**
