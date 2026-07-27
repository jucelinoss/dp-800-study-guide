---
title: "Relacionamentos e JOINs"
type: topic
tags: [sql-server, joins, relationships, foreign-key, fundamentals]
---

# Relacionamentos e JOINs

## Visão Geral

Relacionamentos definem quais fatos pertencem juntos; JOINs transformam essas linhas relacionadas em um resultado de consulta. Bons JOINs começam a partir de uma cardinalidade conhecida e uma escolha deliberada sobre quais linhas não correspondidas devem sobreviver.

> [!abstract]
>
> - Junte tabelas pai e filha através de sua relação de chave documentada.
> - Escolha `INNER`, `LEFT`, `RIGHT`, `FULL` ou `CROSS JOIN` a partir do resultado necessário, não do hábito.
> - Aprenda a distinção `ON` versus `WHERE`, comportamento `NULL`, multiplicação de JOIN e armadilhas de multi-join.

> [!tip] O que o Exame Testa
> Tópicos posteriores do DP-800 usam JOINs em views, funções, predicados de segurança, consultas de manutenção de embeddings e análise de performance. O fundamental crucial é prever preservação de linha e cardinalidade.

---

## Comece pelo relacionamento, não pela sintaxe

O modelo `StudyDB` tem um relacionamento um-para-muitos: um cliente pode ter muitos pedidos; cada pedido pertence a um cliente.

```text
study.Customer                         study.SalesOrder
-------------------------------        --------------------------------
CustomerId (primary key)          1 ──< CustomerId (foreign key)
CustomerName                              SalesOrderId (primary key)
                                          OrderDate
                                          OrderTotal
```

O predicado de JOIN é portanto `o.CustomerId = c.CustomerId`. Não junte meramente porque duas colunas têm nomes semelhantes ou o mesmo tipo de dados. Um predicado correto segue uma relação de negócio e normalmente junta uma chave estrangeira a uma chave primária ou única.

```sql
SELECT c.CustomerName, o.SalesOrderId, o.OrderDate, o.OrderTotal
FROM study.Customer AS c
INNER JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId;
```

Aliases não são cosméticos. Eles tornam a propriedade da coluna visível e evitam nomes ambíguos como `CustomerId` aparecendo em ambas as tabelas.

## Os cinco tipos básicos de JOIN

| JOIN | Mantém linhas correspondentes | Mantém linhas esquerdas não correspondidas | Mantém linhas direitas não correspondidas | Pergunta típica |
| :--- | :---: | :---: | :---: | :--- |
| `INNER JOIN` | Sim | Não | Não | Quais clientes têm pedidos? |
| `LEFT [OUTER] JOIN` | Sim | Sim | Não | Mostre todo cliente e quaisquer pedidos |
| `RIGHT [OUTER] JOIN` | Sim | Não | Sim | Mesma ideia, mas preserve a tabela direita |
| `FULL [OUTER] JOIN` | Sim | Sim | Sim | Reconciliar duas listas |
| `CROSS JOIN` | Toda combinação | N/A | N/A | Gerar uma matriz deliberada |

`OUTER` é sintaxe opcional: `LEFT JOIN` e `LEFT OUTER JOIN` significam a mesma coisa. Prefira `LEFT JOIN` em código novo porque lê naturalmente a partir da tabela que você quer preservar.

### INNER JOIN: apenas fatos correspondentes

```sql
SELECT c.CustomerName, o.OrderDate, o.OrderTotal
FROM study.Customer AS c
INNER JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId;
```

Se Carla não tem pedido, ela não está neste resultado. Se o `CustomerId` de um pedido não pode corresponder a um cliente, também não está neste resultado. Com uma chave estrangeira esse caso filho inválido não deve ocorrer, mas um inner join ainda expressa claramente a regra do resultado: apenas pares que correspondem.

### LEFT JOIN: preserve o conjunto inicial da pergunta

```sql
SELECT c.CustomerName, o.OrderDate, o.OrderTotal
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
ORDER BY c.CustomerName, o.OrderDate;
```

Carla agora aparece uma vez com colunas de pedido `NULL`. Isso não é uma linha quebrada; comunica que nenhum pedido relacionado existe. Comece pela entidade que o relatório deve preservar, depois coloque-a à esquerda.

### RIGHT JOIN: legal mas geralmente menos legível

Um right join preserva a tabela direita. Pode sempre ser reescrito como um left join trocando a ordem das tabelas:

```sql
-- Prefira a forma LEFT JOIN equivalente em novas consultas.
SELECT c.CustomerName, o.OrderDate
FROM study.SalesOrder AS o
LEFT JOIN study.Customer AS c
    ON c.CustomerId = o.CustomerId;
```

Esta convenção torna consultas multi-join mais fáceis de ler porque a tabela preservada aparece primeiro.

### FULL JOIN: encontre diferenças em ambos os lados

`FULL JOIN` retorna correspondências mais linhas não correspondidas de ambas as fontes. É valioso para reconciliação, como comparar IDs de cliente importados com IDs de cliente mestre. É menos comum em relatórios pai-filho ordinários porque eles normalmente têm um lado preservado claro.

```sql
SELECT c.CustomerId AS customer_id,
       o.CustomerId AS order_customer_id
FROM study.Customer AS c
FULL JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId;
```

### CROSS JOIN: produto cartesiano intencional

`CROSS JOIN` retorna toda combinação esquerda/direita. Se há 3 cores e 4 tamanhos, retorna 12 linhas — útil para uma grade de produto-variante.

```sql
SELECT c.CustomerName, p.ProductName
FROM study.Customer AS c
CROSS JOIN study.Product AS p;
```

> [!warning] Erro Comum
> A sintaxe antiga separada por vírgula `FROM Customer, Product` pode acidentalmente criar um cross join quando um predicado é esquecido. Use sintaxe explícita `JOIN ... ON` para que os relacionamentos sejam visíveis.

## `ON` versus `WHERE`: a regra mais importante de outer join

`ON` diz como as linhas estão relacionadas e, para um outer join, quais linhas no lado opcional contam como correspondência. `WHERE` filtra linhas *depois* que o resultado do join foi formado. Eles podem parecer intercambiáveis para inner joins, mas não são intercambiáveis para outer joins.

Suponha que você queira todo cliente, apenas com pedidos de julho quando existirem:

```sql
-- Correto: todo cliente é preservado.
SELECT c.CustomerName, o.OrderDate
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
   AND o.OrderDate >= '2026-07-01'
   AND o.OrderDate <  '2026-08-01';
```

Aqui o predicado de data decide se um pedido corresponde. Um cliente sem pedido de julho ainda tem uma linha esquerda preservada com colunas de pedido `NULL`.

```sql
-- Resultado diferente: clientes sem pedido de julho desaparecem.
SELECT c.CustomerName, o.OrderDate
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
WHERE o.OrderDate >= '2026-07-01'
  AND o.OrderDate <  '2026-08-01';
```

O predicado `WHERE` rejeita os valores `NULL` introduzidos para pedidos não correspondidos, efetivamente transformando este resultado em um inner join para a condição de data.

> [!note] Regra prática
> Coloque condições de relacionamento em `ON`. Coloque filtros para a tabela preservada em `WHERE`. Coloque filtros para uma tabela opcional em `ON` quando linhas preservadas não correspondidas devem permanecer visíveis.

## `NULL` em predicados JOIN

Uma comparação de igualdade envolvendo `NULL` é desconhecida, não verdadeira. `NULL = NULL` não corresponde em um predicado JOIN normal. Isso geralmente está correto: um ID de cliente desconhecido não deve ser tratado como o mesmo cliente conhecido.

```sql
-- Não faça isso para forçar NULLs a corresponder.
-- ON ISNULL(a.Code, 0) = ISNULL(b.Code, 0)
```

Aplicar uma função a colunas de JOIN pode mudar a semântica e dificultar o uso de índice. Primeiro pergunte se um relacionamento anulável é um problema de modelagem. Se uma regra especial de nulo-igual-nulo for verdadeiramente necessária, expresse-a explicitamente e teste-a:

```sql
ON a.Code = b.Code
OR (a.Code IS NULL AND b.Code IS NULL)
```

Esta é uma regra de negócio especializada, não um padrão JOIN padrão.

## Cardinalidade: preveja o número de linhas

JOINs combinam linhas; eles não preservam automaticamente uma forma de uma-linha-por-cliente. Preveja a cardinalidade antes de confiar no resultado.

| Relacionamento | Comportamento esperado do resultado |
| :--- | :--- |
| Um cliente → muitos pedidos | Cliente repete uma vez por pedido |
| Um pedido → um cliente | Cada pedido junta um cliente |
| Muitos-para-muitos sem predicado de ponte adequado | Linhas podem multiplicar-se inesperadamente |
| Chave pai duplicada (dados/modelo ruins) | Linhas filhas multiplicam-se para cada pai duplicado |

```sql
SELECT c.CustomerName, o.SalesOrderId
FROM study.Customer AS c
INNER JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId;
```

Se Ana tem dois pedidos, Ana deve aparecer duas vezes. Isso não é um erro de duplicação; a granularidade da consulta é **uma linha por pedido**. Se a granularidade necessária é uma linha por cliente, agregue pedidos primeiro ou use `EXISTS` quando apenas a existência importa.

```sql
SELECT c.CustomerName, SUM(o.OrderTotal) AS total_spend
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
GROUP BY c.CustomerName;
```

Não aplique `DISTINCT` meramente para esconder multiplicação inesperada. Encontre o relacionamento e o predicado ausente que a causou.

## Múltiplos JOINs: cada resultado alimenta o próximo

Conceitualmente, uma consulta multi-join combina duas fontes, depois combina esse resultado com a próxima fonte. Misturar outer e inner joins pode descartar inesperadamente linhas preservadas anteriormente.

```sql
-- Um cliente sem pedido pode desaparecer no segundo INNER JOIN.
SELECT c.CustomerName, o.SalesOrderId, p.ProductName
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId
INNER JOIN study.Product AS p
    ON p.ProductId = o.SalesOrderId; -- ilustrativo; use a chave real em um modelo real
```

O inner join precisa de um valor não nulo correspondente de `o`; portanto as linhas estendidas com nulo do left join não sobrevivem. Se o relatório deve reter todo cliente, a relação opcional posterior também deve ser left-joined, ou a porção inner deve ser agrupada separadamente antes de ser juntada aos clientes.

```sql
SELECT c.CustomerName, o.SalesOrderId
FROM study.Customer AS c
LEFT JOIN study.SalesOrder AS o
    ON o.CustomerId = c.CustomerId;
```

Ao escrever três ou mais joins, declare a granularidade desejada e a tabela preservada em um comentário ou em suas próprias palavras antes de adicionar sintaxe. Isso detecta a maioria dos erros de outer join.

## Joins, `EXISTS` e operadores de conjunto

Vários construtos podem responder a perguntas relacionadas, mas suas saídas diferem.

| Necessidade | Prefira | Por quê |
| :--- | :--- | :--- |
| Mostrar colunas de ambas as entidades | JOIN | Produz linhas combinadas |
| Encontrar clientes com pelo menos um pedido | `EXISTS` | Evita repetir linhas de cliente |
| Encontrar clientes sem pedido | `NOT EXISTS` ou `EXCEPT` | Expressa ausência claramente |
| Comparar duas listas compatíveis | `INTERSECT` / `EXCEPT` | Compara linhas de resultado, não colunas lado a lado |

```sql
-- Uma linha por cliente qualificado, independentemente de quantos pedidos existem.
SELECT c.CustomerName
FROM study.Customer AS c
WHERE EXISTS (
    SELECT 1
    FROM study.SalesOrder AS o
    WHERE o.CustomerId = c.CustomerId
);
```

A mecânica de subconsulta e operadores de conjunto é coberta na [Lição 04](./04-select-and-filter.md); esta comparação ajuda você a escolher a forma correta do resultado.

## Chaves estrangeiras e índices

Uma chave estrangeira protege a integridade referencial: impede que um pedido refira-se a um cliente que não existe. Ela **não** cria automaticamente um índice na coluna de chave filha no SQL Server.

Isso é intencional. Um índice tem custos de escrita e armazenamento, e a escolha certa depende de padrões reais de JOIN, filtro e exclusão/atualização. Para um `SalesOrder.CustomerId` frequentemente consultado, um índice é frequentemente útil; design e medição são cobertos em [Fundamentos de índices](./10-index-fundamentals.md) e no módulo de performance.

## Questões de Prática

### 1. Preservando linhas não correspondidas

Qual JOIN retorna todo cliente, incluindo clientes que não têm pedidos?

A. `INNER JOIN`<br>
B. `LEFT JOIN` com `Customer` à esquerda<br>
C. `RIGHT JOIN` com `Customer` à esquerda<br>
D. `CROSS JOIN`

> [!success]- Answer
> **B.** Um left join preserva toda linha de sua entrada esquerda. Coloque `Customer` à esquerda quando clientes são o conjunto inicial necessário.

### 2. Posicionamento de filtro

Você precisa de todo cliente, mas apenas pedidos após 1º de julho quando presentes. Onde a condição de data do pedido deve ir?

A. Em `WHERE` apenas<br>
B. Na cláusula `ON` do `LEFT JOIN`<br>
C. Em `ORDER BY`<br>
D. Não importa

> [!success]- Answer
> **B.** Um filtro do lado direito em `ON` controla correspondências enquanto preserva clientes esquerdos não correspondidos. Em `WHERE`, ele remove linhas estendidas com nulo.

### 3. Contagens inesperadas de linhas

Ana tem três pedidos. Um inner join de cliente para pedido retorna Ana três vezes. Qual é a explicação mais provável?

A. O SQL Server duplicou Ana por erro<br>
B. A granularidade da consulta é uma linha por pedido<br>
C. A chave primária está necessariamente quebrada<br>
D. `DISTINCT` deve sempre ser adicionado

> [!success]- Answer
> **B.** O relacionamento um-para-muitos repete a linha do lado um para cada linha correspondente do lado muitos. Agregue ou use `EXISTS` apenas se a granularidade do resultado desejado for uma linha por cliente.

## Casos de Uso

- Exiba fatos de pedido ao lado de fatos de cliente.
- Encontre entidades com ou sem linhas relacionadas.
- Reconciliar duas listas com um full join ou operador de conjunto.
- Construa um relatório que preserve uma entidade pai mesmo quando filhos estão ausentes.

## Problemas Comuns & Erros

> [!warning] Erro Comum
> Esquecer um predicado `ON` ou juntar em colunas não únicas não relacionadas pode criar uma multiplicação cartesiana. Verifique a cardinalidade esperada antes de executar uma consulta em tabelas grandes.

> [!warning] Erro Comum
> Uma condição `WHERE` no lado opcional de um `LEFT JOIN` pode desfazer o outer join. Mova essa condição para `ON` quando linhas preservadas não correspondidas forem necessárias.

## Melhores Práticas

- Use sintaxe ANSI explícita `JOIN ... ON` e aliases significativos.
- Junte chaves primárias/únicas documentadas a chaves estrangeiras.
- Declare a granularidade do resultado pretendido antes de escrever a consulta.
- Prefira left joins sobre right joins para direção de leitura consistente.
- Evite funções em colunas de JOIN a menos que sua semântica e impacto na performance sejam compreendidos.

## Dicas para o Exame

> [!tip] Dicas para o Exame
> `INNER JOIN` preserva apenas correspondências; `LEFT JOIN` preserva a entrada esquerda; `FULL JOIN` preserva ambas. Chaves estrangeiras garantem referências pai válidas mas não indexam automaticamente a chave filha. Em um outer join, `ON` e `WHERE` têm diferentes efeitos de preservação de linha.

## Principais Conclusões

- Um JOIN correto começa com um relacionamento correto e cardinalidade esperada.
- O tipo JOIN decide quais linhas não correspondidas sobrevivem.
- `ON` define correspondências; `WHERE` filtra o resultado do join completo.
- Relacionamentos um-para-muitos naturalmente repetem a linha do lado um na granularidade da linha filha.

## Tópicos Relacionados

- [Modelo relacional e tipos de dados](./02-relational-model-and-data-types.md)
- [SELECT, filtros, subconsultas e operações de conjunto](./04-select-and-filter.md)
- [Agregação e agrupamento](./06-aggregation-and-grouping.md)
- [Fundamentos de índices](./10-index-fundamentals.md)

## Documentação Oficial

- [FROM e JOIN](https://learn.microsoft.com/sql/t-sql/queries/from-transact-sql)
- [Restrições de chave primária e estrangeira](https://learn.microsoft.com/sql/relational-databases/tables/primary-and-foreign-key-constraints)

---

**[← Anterior](./04-select-and-filter.md) | [↑ Voltar à Seção](./fundamentals.md) | [Próximo →](./06-aggregation-and-grouping.md)**
