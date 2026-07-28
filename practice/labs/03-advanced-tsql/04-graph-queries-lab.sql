-- =================================================================================
-- DP-800 - PRACTICAL LAB: GRAPH QUERIES (NODES, EDGES, MATCH, AND SHORTEST_PATH)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/03-advanced-tsql/04-graph-queries.md
--    Open the theory guide alongside this lab for conceptual context.
-- =================================================================================
-- CONFIGURATION NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates Graph architecture and queries (SQL Graph) in SQL Server:
--   1. Creating Node Tables (AS NODE) and Edge Tables (AS EDGE) with Edge Constraints (CONNECTION)
--   2. Inserting Relationships via Pseudo-Columns ($node_id, $from_id, $to_id)
--   3. Graph Traversals with the MATCH Clause (p1-(e)->p2)
--   4. Shortest Path Traversal with SHORTEST_PATH, LAST_NODE() and STRING_AGG WITHIN GROUP (GRAPH PATH)
--   5. Optimization with Graph Indexes on Pseudo-Columns
--   6. Practical Project Scenarios (Recommendation Engine and Fraud Network Detection)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
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
-- PART 1: CREATING NODE AND EDGE TABLES WITH EDGE CONSTRAINTS
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - NODE TABLE: Represents domain entities (e.g., People, Products, Locations).
--     Automatically contains the `$node_id` pseudo-column.
--   - EDGE TABLE: Represents the relationships between nodes.
--     Automatically contains the `$edge_id`, `$from_id`, and `$to_id` pseudo-columns.
--   - EDGE CONSTRAINTS (CONNECTION): DDL restriction that enforces which Node types can connect through the edge.

-- 1. Create Node Tables
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

-- -- [DP-800 EXAM TIP]
-- 2. Create Edge Tables with Connection Constraints (CONNECTION)
CREATE TABLE lab.friendOf (
    CONSTRAINT EC_friendOf CONNECTION (lab.Person TO lab.Person) ON DELETE CASCADE
) AS EDGE;

CREATE TABLE lab.likes (
    Rating INT NULL,
    CONSTRAINT EC_likes CONNECTION (lab.Person TO lab.Restaurant) ON DELETE CASCADE
) AS EDGE;
GO


-- =================================================================================
-- PART 2: INSERTING GRAPH DATA AND REFERENCING $NODE_ID
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - To connect two nodes in the Edge table, the `$from_id` and `$to_id` columns must receive
--     the internal `$node_id` primary key captured via subquery of the corresponding Node.

-- 1. Insert Nodes
INSERT INTO lab.Person (PersonID, Name, City) VALUES 
(1, 'Alice', 'São Paulo'),
(2, 'Bob', 'Rio de Janeiro'),
(3, 'Charlie', 'Belo Horizonte'),
(4, 'Daniela', 'Curitiba');

INSERT INTO lab.Restaurant (RestaurantID, Name, Cuisine) VALUES 
(101, 'Sushi Master', 'Japonesa'),
(102, 'Pizzeria Bella', 'Italiana');
GO

-- -- [DP-800 EXAM TIP]
-- 2. Insert Edges mapping $from_id and $to_id via $node_id subquery
INSERT INTO lab.friendOf ($from_id, $to_id) VALUES 
((SELECT $node_id FROM lab.Person WHERE PersonID = 1), (SELECT $node_id FROM lab.Person WHERE PersonID = 2)),
((SELECT $node_id FROM lab.Person WHERE PersonID = 2), (SELECT $node_id FROM lab.Person WHERE PersonID = 3)),
((SELECT $node_id FROM lab.Person WHERE PersonID = 3), (SELECT $node_id FROM lab.Person WHERE PersonID = 4));

INSERT INTO lab.likes ($from_id, $to_id, Rating) VALUES 
((SELECT $node_id FROM lab.Person WHERE PersonID = 1), (SELECT $node_id FROM lab.Restaurant WHERE RestaurantID = 101), 5),
((SELECT $node_id FROM lab.Person WHERE PersonID = 2), (SELECT $node_id FROM lab.Restaurant WHERE RestaurantID = 102), 4);
GO


-- =================================================================================
-- PART 3: GRAPH TRAVERSALS WITH THE MATCH PREDICATE
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - MATCH PREDICATE: Declarative traversal syntax `MATCH(SourceNode-(Edge)->TargetNode)`.
--     Eliminates the need to write complex recursive CTEs or multiple manual JOINs.

-- 1. Find which restaurants Alice's friends like
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
-- PART 4: SHORTEST PATH TRAVERSAL WITH SHORTEST_PATH
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - SHORTEST_PATH: Finds the path with the smallest number of hops between two nodes in a graph.
--   - REQUIREMENTS: Edge and intermediate node tables in the FROM clause MUST use the `FOR PATH` keyword.
--   - LAST_VALUE(...) WITHIN GROUP (GRAPH PATH): Returns a property of the final node reached in the traversal.
--   - STRING_AGG(...) WITHIN GROUP (GRAPH PATH): Concatenates the traversed path in sequential order.

-- -- [DP-800 EXAM TIP]
-- Find the connection chain (degrees of separation) starting from Alice
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
-- PART 5: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Social Recommendation Engine for E-Commerce Platform
-- Finds products or establishments favorited by the user's indirect connections.

SELECT 
    P1.Name AS Usuario,
    P2.Name AS AmigoEmComum,
    R.Name AS SugestaoRestaurante
FROM lab.Person P1, lab.friendOf F, lab.Person P2, lab.likes L, lab.Restaurant R
WHERE MATCH(P1-(F)->P2-(L)->R)
  AND R.Cuisine = 'Italiana';
GO

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/03-advanced-tsql/04-graph-queries.md
-- =================================================================================================
