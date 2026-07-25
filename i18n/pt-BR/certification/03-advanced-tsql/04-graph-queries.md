---
title: Graph Queries
type: study-material
tags:
  - dp-800
  - graph
  - match
  - node
  - edge
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Arquitetura de Grafos & Inserção](#tipos-de-tabelas-de-grafos-graph-table-types)
>   - 🔹 [Tipos de Tabelas de Grafos (Node vs Edge)](#tipos-de-tabelas-de-grafos-graph-table-types)
>   - 🔹 [Inserindo Dados no Grafo ($node_id, $edge_id)](#inserindo-dados-no-grafo-inserting-graph-data)
> - 📍 [3. Consultas Avançadas & Algoritmos](#predicado-match-match-predicate)
>   - 🔹 [Predicado MATCH (Travessias)](#predicado-match-match-predicate)
>   - 🔹 [SHORTEST_PATH (Caminho Mais Curto)](#shortest_path)
>   - 🔹 [Edge Constraints (`CONNECTION CONSTRAINT`)](#edge-constraints-restricoes-de-aresta)
> - 📍 [4. Integração JSON & Otimização de Performance](#consultas-de-grafos-combinadas-com-json)
>   - 🔹 [Consultas de Grafos combinadas com JSON](#consultas-de-grafos-combinadas-com-json)
>   - 🔹 [Considerações de Performance em Grafos](#consideracoes-de-performance-em-consultas-de-grafos)
> - 📍 [5. Aplicação Prática & Síntese](#casos-de-uso-use-cases)
>   - 🔹 [Casos de Uso](#casos-de-uso-use-cases)
>   - 🔹 [Problemas Comuns, Práticas & Exam Tips](#problemas-comuns-e-solucoes-common-issues)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)

---

# Graph Queries

## Visão Geral (Overview)

As Tabelas de Grafo (graph tables) no SQL Server armazenam entidades lógicas em nós (Node Tables) e seus relacionamentos em arestas (Edge Tables), fazendo uso de colunas especiais do sistema (`$node_id`, `$edge_id`, `$from_id`, `$to_id`). Elas possibilitam navegar e percorrer relacionamentos complexos de forma declarativa e otimizada por meio do predicado `MATCH` — eliminando a necessidade de estruturação de complexas e lentas CTEs recursivas.

> [!abstract]
>
> - Cobre objetos de bancos de dados de grafos (tabelas do tipo `NODE` e `EDGE`) e a sintaxe de consultas de grafos (`MATCH`, `SHORTEST_PATH`).
> - As tabelas de grafos do SQL Server são tabelas normais estendidas com metadados e colunas ocultas geradas pelo sistema para navegação estrutural.
> - Tópicos chave do exame: criação física de tabelas `NODE` vs `EDGE`, sintaxe de uso do predicado `MATCH` e cenários onde o modelo de grafo supera a performance relacional tradicional (ex: grandes profundidades de hierarquias).

> [!tip] O que o Exame Testa
>
> - Comandos `CREATE TABLE … AS NODE` e `CREATE TABLE … AS EDGE` — as tabelas `EDGE` referenciam logicamente as tabelas `NODE`.
> - A sintaxe `MATCH (Pessoa)-[Conhece]->(Pessoa)` é exigida na filtragem de grafos — não é possível realizar as travessias lógicas nativas usando comandos `JOIN` convencionais no lugar do MATCH.
> - A função `SHORTEST_PATH` dentro da cláusula `MATCH` localiza a menor rota física de saltos (hops) entre dois nós dentro do grafo de conexões.

---

## Tipos de Tabelas de Grafos (Graph Table Types)

```sql
-- Tabela de Nó (Node table): representa as entidades lógicas
CREATE TABLE dbo.Person (
    PersonId    int             NOT NULL PRIMARY KEY,
    Name        nvarchar(100)   NOT NULL,
    City        nvarchar(100)   NULL
) AS NODE;

CREATE TABLE dbo.Restaurant (
    RestaurantId    int             NOT NULL PRIMARY KEY,
    Name            nvarchar(200)   NOT NULL,
    Cuisine         nvarchar(50)    NULL
) AS NODE;

-- Tabela de Aresta (Edge table): representa relacionamentos direcionados
CREATE TABLE dbo.likes    AS EDGE;
CREATE TABLE dbo.friendOf AS EDGE;

-- Edge table contendo propriedades adicionais na relação
CREATE TABLE dbo.Visited (
    VisitDate   date NOT NULL,
    Rating      int  NULL
) AS EDGE;
```

**Colunas internas do sistema (System columns):**

- Tabelas `NODE`: coluna `$node_id` (identificador exclusivo do nó no banco, representado internamente em formato JSON).
- Tabelas `EDGE`: colunas `$edge_id`, `$from_id` (nó de origem do relacionamento) e `$to_id` (nó de destino).

> [!important] Identificadores de Grafo (System IDs)
>
> - **$node_id**: É gerado automaticamente para toda linha em tabelas `NODE`. Sob o capô, é uma string JSON contendo o ID do objeto de banco de dados e o ID da linha.
> - **$from_id** e **$to_id**: São colunas de tabelas `EDGE` que contêm os `$node_id` dos nós que elas conectam. Elas aceitam qualquer `$node_id` de qualquer tabela `NODE`, a menos que restringidas por uma **Edge Constraint**.

---

## Inserindo dados no Grafo (Inserting Graph Data)

```sql
-- Inserir registros de nós (Nodes)
INSERT INTO dbo.Person (PersonId, Name) VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Carol');
INSERT INTO dbo.Restaurant (RestaurantId, Name, Cuisine)
VALUES (1, 'Sushi Palace', 'Japanese'), (2, 'Pizza Corner', 'Italian');

-- Inserir conexões de arestas (Edges) consumindo as $node_id correspondentes
INSERT INTO dbo.likes ($from_id, $to_id)
VALUES (
    (SELECT $node_id FROM dbo.Person WHERE PersonId = 1),
    (SELECT $node_id FROM dbo.Restaurant WHERE RestaurantId = 1)
);

INSERT INTO dbo.friendOf ($from_id, $to_id)
VALUES (
    (SELECT $node_id FROM dbo.Person WHERE PersonId = 1),
    (SELECT $node_id FROM dbo.Person WHERE PersonId = 2)
);

-- Inserir aresta contendo propriedades customizadas
INSERT INTO dbo.Visited ($from_id, $to_id, VisitDate, Rating)
VALUES (
    (SELECT $node_id FROM dbo.Person WHERE PersonId = 2),
    (SELECT $node_id FROM dbo.Restaurant WHERE RestaurantId = 2),
    '2025-06-01', 5
);
```

---

## Predicado MATCH (MATCH Predicate)

A cláusula `MATCH` emprega notações direcionadas por setas para expressar e percorrer as relações lógicas:

```sql
-- Sintaxe de caminhos permitidos:
-- no-(aresta)->no   : busca direcionada da origem para o destino (from → to)
-- no<-(aresta)-no   : busca direcionada reversa (to ← from)

-- Encontrar todos os restaurantes que a Alice gosta (likes)
SELECT r.Name AS Restaurant
FROM dbo.Person p, dbo.likes l, dbo.Restaurant r
WHERE MATCH(p-(l)->r)
  AND p.Name = 'Alice';

-- Localizar amigos da Alice
SELECT p2.Name AS Friend
FROM dbo.Person p1, dbo.friendOf f, dbo.Person p2
WHERE MATCH(p1-(f)->p2)
  AND p1.Name = 'Alice';

-- Encadeamento: amigos da Alice que gostam de comida japonesa
SELECT p2.Name AS Friend, r.Name AS Restaurant
FROM dbo.Person p1, dbo.friendOf f, dbo.Person p2,
     dbo.likes l, dbo.Restaurant r
WHERE MATCH(p1-(f)->p2-(l)->r)
  AND p1.Name = 'Alice'
  AND r.Cuisine = 'Japanese';
```

> [!warning] Sentido das Setas no MATCH
>
> - O sentido da seta no `MATCH` deve corresponder perfeitamente ao fluxo de dados de origem para destino gravados no Edge.
> - Se você salvou uma amizade como `Alice -(friendOf)-> Bob`, a consulta `MATCH(Bob-(friendOf)->Alice)` não trará correspondência a menos que haja um registro inverso ou você busque usando `MATCH(Bob<-(friendOf)-Alice)`. Setas incorretas retornam zero linhas silenciosamente.

> [!warning] Erro Comum
> As tabelas de grafos continuam sendo tabelas relacionais ordinárias sob o capô — elas suportam a criação de indexes comuns, triggers, constraints e JOINS normais. A cláusula MATCH é apenas um facilitador sintático a mais, e não uma substituição total da semântica SQL. Não confunda "SQL Graph tables" com sistemas de banco de dados NoSQL puros e dedicados exclusivamente a grafos.

---

## SHORTEST_PATH

A função `SHORTEST_PATH` localiza a menor rota física de saltos (hops) entre nós avaliando recursivamente a topologia das conexões. A diretiva **`FOR PATH`** deve ser obrigatoriamente associada na declaração dos aliases das tabelas de arestas e nós intermediários no padrão.

Funções agregadoras específicas para uso exclusivo com `SHORTEST_PATH`:

- `LAST_NODE()` permite encadear o último alias de nó; para projetar uma propriedade do último nó, use agregações `WITHIN GROUP (GRAPH PATH)`, como `LAST_VALUE`.
- `STRING_AGG(...) WITHIN GROUP (GRAPH PATH)` — concatena strings dos nós percorridos na sequência exata de visitação.
- `COUNT(...) WITHIN GROUP (GRAPH PATH)` — computa a quantidade de arestas ou nós intermediários percorridos na travessia.
- Modificadores de limite: o operador `+` indica um ou mais saltos; `{1,N}` impõe limites de profundidade (mínimo e máximo).

```sql
-- Encontrar a menor rota de Alice para qualquer conexão na rede social
SELECT
    Person1.Name AS Source,
    LAST_VALUE(Person2.Name) WITHIN GROUP (GRAPH PATH) AS Destination,
    COUNT(Person2.Name) WITHIN GROUP (GRAPH PATH) AS HopsCount,
    STRING_AGG(Person2.Name, '->') WITHIN GROUP (GRAPH PATH) AS Path
FROM
    Person AS Person1,
    friendOf FOR PATH AS FriendOf,
    Person FOR PATH AS Person2
WHERE
    MATCH(SHORTEST_PATH(Person1(-(FriendOf)->Person2)+))
    AND Person1.Name = 'Alice';
```

---

## Edge Constraints (Restrições de Aresta)

As Edge Constraints validam em nível de esquema do DDL quais tipos específicos de nós (`NODE` tables) podem ser conectados por meio de uma determinada aresta (`EDGE` table), prevenindo o registro de conexões lógicas inconsistentes.

- Definido pela cláusula `CONSTRAINT ... CONNECTION (NodeSource TO NodeTarget)`.
- Permite especificar múltiplos pares de relações permitidos para uma única tabela de aresta.
- A exclusão em cascata (`ON DELETE CASCADE`) remove as arestas órfãs automaticamente no banco de dados quando um nó referenciado é deletado da base.

```sql
-- Edge constraint: a aresta FriendOf só aceita conexões lógicas do tipo Person
CREATE TABLE FriendOf (
    CONSTRAINT EC_FriendOf CONNECTION (Person TO Person) ON DELETE CASCADE
) AS EDGE;

-- Múltiplas combinações aceitas em uma mesma aresta
CREATE TABLE Manages (
    CONSTRAINT EC_Manages CONNECTION (Person TO Person, Person TO Team)
) AS EDGE;
```

> [!tip] Dica para a Prova: Integridade em Grafos com Edge Constraints
>
> - Sem Edge Constraints, qualquer aresta (ex: `likes`) pode conectar qualquer tipo de nó (ex: `Person` a um `Restaurant`, ou absurdamente `Restaurant` a `Restaurant`).
> - Ao aplicar `CONNECTION (Person TO Restaurant, Person TO Book)`, você garante integridade física rígida no nível do DDL do banco.

---

## Consultas de Grafos combinadas com JSON

As tabelas de nós (`NODE`) podem conter colunas estruturadas em JSON para armazenar dados heterogêneos dinâmicos, possibilitando o design de *schema-on-read* associado à capacidade de travessia lógica do predicado `MATCH`.

- Combine o uso de `JSON_VALUE` / `JSON_QUERY` e `MATCH` na mesma query.
- As propriedades JSON podem ser referenciadas nos filtros de `WHERE` e seleções.

```sql
-- Tabela de nó Produto contendo atributos em JSON
CREATE TABLE Product (
    ProductID INT PRIMARY KEY,
    Name NVARCHAR(200),
    Attributes NVARCHAR(MAX) -- Coluna de dados JSON
) AS NODE;

-- Consultar grafos filtrando por atributos contidos no payload JSON
SELECT p.Name, JSON_VALUE(p.Attributes, '$.category') AS Category
FROM Product p, RecommendedWith r, Product p2
WHERE MATCH(p-(r)->p2)
AND JSON_VALUE(p.Attributes, '$.category') = 'Electronics';
```

---

## Considerações de Performance em Consultas de Grafos

A performance das tabelas de grafos é governada pelas mesmas regras físicas de indexes e estatísticas válidas no SQL Server.

- **Tabelas de Nós (Node Tables)**: Mantenha a coluna `$node_id` indexada (feito implicitamente ao gerar PK) e adicione indexes adicionais nas colunas de busca (ex: Nome).
- **Tabelas de Arestas (Edge Tables)**: Crie indexes nas pseudocolunas ocultas `$from_id` e `$to_id` para acelerar a leitura nas duas direções da travessia.
- **SHORTEST_PATH em redes densas**: Sempre imponha limites físicos de profundidade usando `{1,N}`. O uso do operador aberto `+` em grandes volumes pode gerar scans catastróficos.
- **Planos de Execução**: O SQL Server converte a notação do `MATCH` internamente para JOINs tradicionais. O plano final exibirá operadores padrão de joins (Hash, Nested Loops), e não operadores específicos de grafos.

```sql
-- Indexar as pontas de conexão na aresta para agilizar travessias lógicas
CREATE INDEX IX_FriendOf_From ON FriendOf($from_id);
CREATE INDEX IX_FriendOf_To ON FriendOf($to_id);

-- Indexar chaves de busca nas tabelas de nós
CREATE INDEX IX_Person_Name ON Person(Name);
```

---

## Casos de Uso (Use Cases)

- **Redes Sociais e Contatos**: Recomendações de contatos (amigo de amigo), mapeamento de influências.
- **Detecção de Fraudes**: Mapear anéis de transações circulares suspeitas ou contas bancárias compartilhando os mesmos dados cadastrais.
- **Grafos de Conhecimento (Knowledge Graphs)**: Mapear entidades correlacionadas para enriquecer o contexto de busca semântica em aplicações RAG/IA.
- **Estruturas Hierárquicas (Bill of Materials)**: Relação de montagem de peças complexas com subcomponentes compartilhados.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| Falha no comando `MATCH` | Falha ao omitir nós/arestas da cláusula `FROM` | Certifique-se de listar todas as tabelas de nós e arestas do MATCH explicitamente na cláusula `FROM`. |
| Falha ao inserir aresta | Inserção de texto em vez de metadados `$node_id` | `Utilize subqueries do tipo `(SELECT $node_id FROM ...)` para recuperar as chaves corretas dos nós`. |
| Múltiplos caminhos de busca | Tentativa de aninhamento no MATCH | Una múltiplos fluxos usando comandos `AND MATCH(...)` separados na query. |
| `SHORTEST_PATH` não retorna dados | Sentido incorreto das setas da aresta na query | Valide a direção da aresta (`$from_id` e `$to_id`) e verifique a correta atribuição do modificador `FOR PATH` nos aliases. |
| Violação de Edge Constraint | Conexão de nós inválidos não mapeados no DDL | Confirme os tipos permitidos declarados na restrição `CONNECTION` da aresta. |

---

## Melhores Práticas (Best Practices)

- Configure `CONNECTION` constraints em todas as tabelas de arestas para garantir a integridade referencial dos nós no DDL do banco.
- Crie sempre indexes físicos sobre as colunas `$from_id` e `$to_id` das tabelas `EDGE` para evitar table scans severos nas consultas.
- Adote limites definidos `{1,N}` em buscas com `SHORTEST_PATH` em ambientes produtivos.
- Utilize aliases exclusivos com a instrução `FOR PATH` apenas dentro da função `SHORTEST_PATH`.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - O predicado `MATCH` é de uso exclusivo com tabelas de grafos declaradas como `NODE` ou `EDGE`.
> - A direção das setas na cláusula `MATCH` (`-(aresta)->`) deve coincidir com o sentido físico das colunas `$from_id` → `$to_id` gravadas na aresta.
> - A função `SHORTEST_PATH` exige que a instrução `FOR PATH` seja associada aos aliases das arestas e nós intermediários envolvidos na busca recursiva.
> - A função `LAST_NODE()` recupera a identidade do último nó alcançado no SHORTEST_PATH (o destino).
> - As Edge Constraints usam a sintaxe de declaração `CONSTRAINT ... CONNECTION (NóOrigem TO NóDestino)`.

---

## Resumo dos Conceitos (Key Takeaways)

- As tabelas `NODE` expõem a coluna `$node_id`; as tabelas `EDGE` controlam as relações com `$edge_id`, `$from_id` e `$to_id`.
- `MATCH` permite expressar consultas complexas de relacionamentos de forma declarativa e simples sem CTEs.
- `SHORTEST_PATH` computa a menor rota de saltos (hops) na rede.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Você precisa localizar e mapear todos os contatos que estejam a até 3 saltos (hops) de distância de uma pessoa específica dentro de um grafo social. Qual recurso do T-SQL permite estruturar essa consulta da forma mais eficiente?

A. CTE Recursiva vinculando comandos `UNION ALL` associados a um contador incremental de saltos.

B. Cláusula `MATCH` configurada com `SHORTEST_PATH` limitando a profundidade da busca.

C. Um comando de auto-relacionamento físico contendo 3 níveis de `JOINs` aninhados na query.

D. Utilizar a função `OPENJSON` para navegar no grafo persistido em colunas de texto.

> [!success]- Resposta
> **B — Cláusula MATCH configurada com SHORTEST_PATH limitando a profundidade da busca**
>
> A função `SHORTEST_PATH` provê buscas recursivas nativas rápidas em tabelas de grafos do SQL Server, permitindo limitar a profundidade de forma explícita com sintaxes como `{1,3}`. Embora CTEs recursivas (A) consigam computar hierarquias, a sintaxe nativa de grafos com `MATCH` e `SHORTEST_PATH` é a mais adequada e otimizada pelo otimizador de plano quando se usam tabelas `AS NODE` e `AS EDGE`. Auto-joins (C) limitam a dinamicidade de saltos e escalam mal.

---

## Tópicos Relacionados

- [02-Specialized Tables — Ledger](../01-database-objects/02-specialized-tables.md)
- [01-CTEs & Window Functions](./01-ctes-window-functions.md)

---

## Documentação Oficial

- [SQL Graph Architecture](https://learn.microsoft.com/en-us/sql/relational-databases/graphs/sql-graph-architecture)
- [MATCH (SQL Graph)](https://learn.microsoft.com/en-us/sql/t-sql/queries/match-sql-graph)
- [SHORTEST_PATH (SQL Graph)](https://learn.microsoft.com/en-us/sql/t-sql/queries/shortest-path-sql-graph)

---

**[← Anterior](./03-regex-fuzzy-matching.md) | [↑ Voltar para a Seção](./advanced-tsql.md) | [Próximo →](./05-correlated-queries-error-handling.md)**
