-- =================================================================================
-- DP-800 - LAB PRÁTICO: CONSULTAS DE GRAFO (NODES, EDGES, MATCH E SHORTEST_PATH)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a arquitetura e consultas de Grafo (SQL Graph) no SQL Server:
--   1. Criação de Tabelas de Nó (AS NODE) e Aresta (AS EDGE) com Edge Constraints (CONNECTION)
--   2. Inserção de Relacionamentos via Pseudo-Colunas ($node_id, $from_id, $to_id)
--   3. Travessias de Grafo com a Cláusula MATCH (p1-(e)->p2)
--   4. Travessia de Menor Caminho com SHORTEST_PATH, LAST_NODE() e STRING_AGG WITHIN GROUP (GRAPH PATH)
--   5. Otimização com Índices de Grafo nas Pseudo-Colunas
--   6. Cenários Práticos de Projeto (Motor de Recomendação e Detecção de Redes de Fraude)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'likes' AND is_node = 0)
    DROP TABLE lab.likes;
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'friendOf' AND is_node = 0)
    DROP TABLE lab.friendOf;
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'Restaurant' AND is_node = 1)
    DROP TABLE lab.Restaurant;
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'Person' AND is_node = 1)
    DROP TABLE lab.Person;
GO


-- =================================================================================
-- PARTE 1: CRIAÇÃO DE TABELAS NODE E EDGE COM EDGE CONSTRAINTS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - NODE TABLE (Tabela de Nó): Representa entidades do domínio (ex: Pessoas, Produtos, Locais).
--     Contém automaticamente a pseudo-coluna `$node_id`.
--   - EDGE TABLE (Tabela de Aresta): Representa os relacionamentos entre os nós.
--     Contém automaticamente as pseudo-colunas `$edge_id`, `$from_id` e `$to_id`.
--   - EDGE CONSTRAINTS (CONNECTION): Restrição DDL que impõe quais tipos de Nó podem se conectar através da aresta.

-- 1. Criar Tabelas de Nó
CREATE TABLE lab.Person (
    PersonID INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    City NVARCHAR(100) NULL
) AS NODE;

CREATE TABLE lab.Restaurant (
    RestaurantID INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Cuisine NVARCHAR(50) NOT NULL
) AS NODE;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Criar Tabelas de Aresta com Restrições de Conexão (CONNECTION)
CREATE TABLE lab.friendOf (
    CONSTRAINT EC_friendOf CONNECTION (lab.Person TO lab.Person) ON DELETE CASCADE
) AS EDGE;

CREATE TABLE lab.likes (
    Rating INT NULL,
    CONSTRAINT EC_likes CONNECTION (lab.Person TO lab.Restaurant) ON DELETE CASCADE
) AS EDGE;
GO


-- =================================================================================
-- PARTE 2: INSERÇÃO DE DADOS DE GRAFO E REFERÊNCIA A $NODE_ID
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - Para conectar dois nós na tabela de Aresta, as colunas `$from_id` e `$to_id` devem receber
--     a chave primária interna `$node_id` capturada via subquery do Nó correspondente.

-- 1. Inserir Nós
INSERT INTO lab.Person (PersonID, Name, City) VALUES 
(1, 'Alice', 'São Paulo'),
(2, 'Bob', 'Rio de Janeiro'),
(3, 'Charlie', 'Belo Horizonte'),
(4, 'Daniela', 'Curitiba');

INSERT INTO lab.Restaurant (RestaurantID, Name, Cuisine) VALUES 
(101, 'Sushi Master', 'Japonesa'),
(102, 'Pizzeria Bella', 'Italiana');
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 2. Inserir Arestas mapeando $from_id e $to_id via subquery de $node_id
INSERT INTO lab.friendOf ($from_id, $to_id) VALUES 
((SELECT $node_id FROM lab.Person WHERE PersonID = 1), (SELECT $node_id FROM lab.Person WHERE PersonID = 2)),
((SELECT $node_id FROM lab.Person WHERE PersonID = 2), (SELECT $node_id FROM lab.Person WHERE PersonID = 3)),
((SELECT $node_id FROM lab.Person WHERE PersonID = 3), (SELECT $node_id FROM lab.Person WHERE PersonID = 4));

INSERT INTO lab.likes ($from_id, $to_id, Rating) VALUES 
((SELECT $node_id FROM lab.Person WHERE PersonID = 1), (SELECT $node_id FROM lab.Restaurant WHERE RestaurantID = 101), 5),
((SELECT $node_id FROM lab.Person WHERE PersonID = 2), (SELECT $node_id FROM lab.Restaurant WHERE RestaurantID = 102), 4);
GO


-- =================================================================================
-- PARTE 3: TRAVESSIAS DE GRAFO COM O PREDICADO MATCH
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PREDICADO MATCH: Sintaxe declarativa de travessia `MATCH(NoOrigem-(Aresta)->NoDestino)`.
--     Elimina a necessidade de escrever CTEs recursivas complexas ou múltiplos JOINs manuais.

-- 1. Descobrir quais restaurantes os amigos de Alice gostam
SELECT 
    P1.Name AS Pessoa,
    P2.Name AS Amigo,
    R.Name AS RestauranteRecomendado,
    R.Cuisine AS Culinaria
FROM lab.Person P1, lab.friendOf F, lab.Person P2, lab.likes L, lab.Restaurant R
WHERE MATCH(P1-(F)->P2-(L)->R)
  AND P1.Name = 'Alice';
GO


-- =================================================================================
-- PARTE 4: TRAVESSIA DE MENOR CAMINHO COM SHORTEST_PATH
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - SHORTEST_PATH: Encontra o caminho com menor número de saltos (hops) entre dois nós em um grafo.
--   - REQUISITOS: As arestas e nós intermediários na cláusula FROM DEVEM usar a palavra-chave `FOR PATH`.
--   - LAST_VALUE(... ) WITHIN GROUP (GRAPH PATH): Retorna uma propriedade do nó final atingido na travessia.
--   - STRING_AGG(...) WITHIN GROUP (GRAPH PATH): Concatena a rota percorrida em ordem sequencial.

-- -- [PONTO DE ATENÇÃO DP-800]
-- Buscar a cadeia de conexões (graus de separação) a partir de Alice
SELECT 
    P1.Name AS Origem,
    LAST_VALUE(P2.Name) WITHIN GROUP (GRAPH PATH) AS DestinoFinal,
    STRING_AGG(P2.Name, ' -> ') WITHIN GROUP (GRAPH PATH) AS RotaPercorrida
FROM 
    lab.Person AS P1,
    lab.friendOf FOR PATH AS F,
    lab.Person FOR PATH AS P2
WHERE MATCH(SHORTEST_PATH(P1(-(F)->P2)+))
  AND P1.Name = 'Alice';
GO


-- =================================================================================
-- PARTE 5: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Motor de Recomendação Social para Plataforma E-Commerce
-- Encontra produtos ou estabelecimentos favoritados por conexões indiretas do usuário.

SELECT 
    P1.Name AS Usuario,
    P2.Name AS AmigoEmComum,
    R.Name AS SugestaoRestaurante
FROM lab.Person P1, lab.friendOf F, lab.Person P2, lab.likes L, lab.Restaurant R
WHERE MATCH(P1-(F)->P2-(L)->R)
  AND R.Cuisine = 'Italiana';
GO
