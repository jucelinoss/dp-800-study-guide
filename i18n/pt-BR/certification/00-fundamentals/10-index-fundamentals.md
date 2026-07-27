---
title: "Fundamentos de Índices"
type: topic
tags: [sql-server, indexes, performance, fundamentals]
---

# Fundamentos de Índices

## Visão Geral

Um índice é uma estrutura de dados auxiliar que ajuda o SQL Server a localizar linhas com menos trabalho. A compensação é clara: **melhor performance de leitura** para consultas que usam o índice, ao custo de **armazenamento adicional e manutenção de escrita** em cada insert, update e delete.

> [!abstract]
>
> - Um **índice clustered** determina a ordem física das linhas da tabela; pode haver no máximo um.
> - Um **índice nonclustered** é uma estrutura separada; uma tabela pode ter muitos.
> - Escolhas de índice devem refletir padrões reais de consulta — criar índices em toda coluna diminui as escritas e pode confundir o otimizador.
> - Meça antes e depois: use `STATISTICS IO` e planos de consulta para avaliar a eficácia.

> [!tip] O que o Exame Testa
> Esta seção estabelece o modelo mental do que é um índice e como ele acelera consultas. Design aprofundado de índices — columnstore, filtered indexes, compressão, manutenção de índices — é coberto na Seção 01. Análise de planos de execução e ajuste de índices pertencem à Seção 06.

---

## Por que índices existem

Sem um índice, o SQL Server deve examinar toda a tabela para encontrar linhas correspondentes. Isso é chamado de **table scan** (heap) ou **clustered index scan**. Um índice permite um **seek** — navegar por uma estrutura de árvore para localizar rapidamente as linhas relevantes.

### Diagrama B-tree (conceitual)

```text
Nível raiz:        [A–M]
                  /     \
Nível interm.:  [A–F]   [G–M]
               /   \    /   \
Folha:        [A][B][F] [G][K][M]   ← Cada entrada de folha aponta para uma linha de dados
```

**Seek:** Navegar raiz → intermediário → folha para encontrar valores específicos (rápido).<br>
**Scan:** Ler toda página de folha do início ao fim (lento para tabelas grandes com consultas seletivas).

> [!note] Modelo mental — índice = índice remissivo de livro
> Pense em um índice nonclustered como o índice remissivo no final de um livro. Para encontrar todas as páginas que mencionam "clustered index", você procura o termo no índice (seek) em vez de ler cada página (scan). Um índice clustered é como os números de página — o livro está fisicamente ordenado por número de página.

## Clustered vs Nonclustered

| Aspecto | Índice clustered | Índice nonclustered |
| :--- | :--- | :--- |
| **Quantidade por tabela** | No máximo um | Até 999 |
| **Ordem física** | Determina a ordem de armazenamento das linhas | Estrutura separada com chave + localizador de linha |
| **Nível folha** | Contém as linhas de dados reais | Contém colunas-chave + bookmark para a linha de dados |
| **Padrão para PK?** | Sim (a menos que `NONCLUSTERED` seja especificado) | Apenas se a PK for definida como nonclustered |
| **Tabela sem um** | Chamada de **heap** | N/A |

### Índice clustered

O índice clustered define a ordem lógica dos dados de uma tabela. Se nenhum índice clustered existir, a tabela é uma **heap** (não ordenada).

```sql
-- Padrão: chave primária cria um índice clustered
CREATE TABLE study.Customer (
    CustomerId int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Customer PRIMARY KEY,  -- cria índice clustered
    CustomerName nvarchar(100) NOT NULL
);
```

```sql
-- Crie um índice clustered em uma coluna diferente (para acesso baseado em ordem)
CREATE CLUSTERED INDEX IX_SalesOrder_OrderDate
    ON study.SalesOrder (OrderDate);
```

### Índice nonclustered

Um índice nonclustered é uma estrutura separada que armazena as colunas-chave do índice mais um **localizador de linha** (ponteiro de volta para a linha de dados completa).

```sql
-- Índice nonclustered para acelerar buscas por OrderDate
CREATE INDEX IX_SalesOrder_OrderDate
    ON study.SalesOrder (OrderDate);
```

### Inspecionando índices

```sql
-- Veja todos os índices em uma tabela
SELECT i.name                                   AS index_name,
       i.type_desc                              AS index_type,
       i.is_unique,
       i.is_primary_key,
       i.fill_factor
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'Sales.SalesOrderHeader')
ORDER BY i.type;
```

## Vendo a diferença: STATISTICS IO

`SET STATISTICS IO ON` mostra leituras lógicas — páginas lidas do cache de dados. Um índice que reduz leituras lógicas para uma consulta é benéfico.

```sql
-- Antes de criar um índice direcionado
SET STATISTICS IO ON;

SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';
```

Anote a mensagem `Table 'SalesOrderHeader'. Scan count N, logical reads M [...]`. Depois crie um índice e execute a mesma consulta novamente:

```sql
-- Crie um índice direcionado (idempotente)
DROP INDEX IF EXISTS IX_Lab_OrderDate ON Sales.SalesOrderHeader;
CREATE INDEX IX_Lab_OrderDate ON Sales.SalesOrderHeader (OrderDate);

-- Execute a mesma consulta novamente — compare leituras lógicas
SELECT SalesOrderID, OrderDate, TotalDue
FROM Sales.SalesOrderHeader
WHERE OrderDate >= '2013-06-01' AND OrderDate < '2013-07-01';

SET STATISTICS IO OFF;
```

> [!tip] Interpretando leituras lógicas
> Menos leituras lógicas geralmente significam menos trabalho. A redução exata depende da distribuição dos dados, seletividade do índice e da consulta. No laboratório (Lab 09), a diferença no AdventureWorks pode ser modesta; a habilidade importante é saber *como* medir e comparar.

## Índices covering — conceito

Diz-se que um índice **cobre** uma consulta quando todas as colunas referenciadas em `SELECT`, `WHERE` e `JOIN` estão presentes no índice. Quando uma consulta é totalmente coberta, o SQL Server pode respondê-la inteiramente a partir do índice sem tocar na linha de dados — isso elimina o **key lookup** (também chamado de bookmark lookup).

```sql
-- Sem covering: índice em OrderDate, mas TotalDue e SubTotal
-- exigem um key lookup de volta à linha de dados.
CREATE INDEX IX_Lab_OrderDate
    ON Sales.SalesOrderHeader (OrderDate);

-- Com INCLUDE: o índice agora "cobre" esta consulta específica.
CREATE INDEX IX_Lab_OrderDate_Covering
    ON Sales.SalesOrderHeader (OrderDate)
    INCLUDE (TotalDue, SubTotal, TaxAmt);
```

A cláusula `INCLUDE` adiciona colunas não-chave apenas no nível folha — elas não participam da navegação do índice (seek/scan) mas tornam o índice útil para mais consultas.

> [!warning] Erro Comum
> Adicionar toda coluna de uma tabela a um índice não é uma "estratégia covering" — é essencialmente duplicar a tabela. Escolha colunas `INCLUDE` com moderação, baseado em padrões reais de consulta.

## Compensações de índices

Índices aceleram leituras ao custo de escritas. Cada índice em uma tabela deve ser mantido durante operações `INSERT`, `UPDATE`, `DELETE` e `MERGE`.

| Padrão de carga de trabalho | Benefício | Compensação |
| :--- | :--- | :--- |
| Predicado `WHERE` seletivo | Seek para poucas linhas | Manutenção extra de escrita |
| JOIN em coluna FK | Join nested loop mais rápido | Armazenamento e manutenção |
| `ORDER BY` em coluna indexada | Evita sort explícito | Ordem do índice deve corresponder à ordem do sort |
| Tabela pequena (< 1000 páginas) | Frequentemente pouco benefício | Índice pode não ser usado, ainda mantido |
| Escritas OLTP pesadas | Risco de DML lento | Cada índice adiciona custo de escrita |

### Fill factor (conceito)

Fill factor reserva espaço livre em páginas de índice para reduzir divisões de página durante inserts. Um fill factor de 80 significa 20% de espaço livre por página. Este é um **parâmetro de ajuste de manutenção** coberto em profundidade na Seção 01.

```sql
-- Criando um índice com fill factor (conceitual)
CREATE INDEX IX_Example ON Sales.SalesOrderHeader (OrderDate)
    WITH (FILLFACTOR = 80);
```

## Quando NÃO indexar

Um índice nem sempre é a resposta. Considere pular um índice quando:

- **Tabela é pequena**: menos de ~1000 páginas; um scan é rápido o suficiente.
- **Carga de trabalho pesada de escrita**: cada índice adiciona latência a toda operação DML.
- **Baixa seletividade**: uma coluna onde a maioria dos valores é igual (por exemplo, um flag com 95% `true`) dificilmente será útil como coluna-chave principal.
- **Consulta retorna a maioria das linhas**: se uma consulta lê 50%+ da tabela, um scan pode ser mais eficiente que um seek + key lookup.

```sql
-- Candidato a índice ruim: coluna Gender com baixa seletividade
-- CREATE INDEX IX_Employee_Gender ON HumanResources.Employee (Gender);
```

> [!warning] Erro Comum
> Criar um índice para toda coluna diminui as escritas e deixa o otimizador com mais escolhas, não melhores escolhas. Comece de **padrões reais de consulta**, não de nomes de colunas.

## Verifique-se

### 1. Clustered vs nonclustered

Uma tabela tem uma chave primária em `CustomerId` (clustered padrão). Você cria um índice nonclustered em `Email`. Onde o índice nonclustered armazena seu localizador de linha no nível folha?

> [!success]- Answer
> O índice nonclustered armazena a chave clustered (`CustomerId`) como o localizador de linha. Para encontrar a linha completa, o SQL Server usa a chave clustered para navegar no índice clustered. Isso é chamado de **key lookup**.

### 2. Leituras lógicas

Você executa uma consulta com `SET STATISTICS IO ON`. Antes de criar um índice, a consulta relata 1.200 leituras lógicas. Depois de criar um índice, relata 150 leituras lógicas. Este é um índice útil para esta consulta?

> [!success]- Answer
> Sim. Uma redução de 1.200 para 150 leituras lógicas significa que o índice ajudou o SQL Server a encontrar linhas com menos I/O. O índice é benéfico para este padrão de consulta.

### 3. Conceito covering

Qual é o mínimo necessário para um índice "cobrir" uma consulta que seleciona `OrderDate`, `TotalDue` e `Status` de `Sales.SalesOrderHeader` onde `OrderDate >= '2013-01-01'`?

> [!success]- Answer
> A chave do índice deve incluir `OrderDate` (para seek) e `INCLUDE TotalDue, Status` (para evitar key lookup). Como `Status` pode já estar no índice clustered, adicioná-lo a `INCLUDE` torna o índice covering para esta consulta.

### 4. Custo de escrita

Por que adicionar um índice nonclustered diminui inserts na mesma tabela?

> [!success]- Answer
> Cada insert deve adicionar uma linha aos dados da tabela *e* atualizar cada índice nonclustered na tabela. Mais índices = mais trabalho por insert. Esta é a compensação fundamental leitura/escrita do design de índices.

## Próximos Passos

Fundamentos de índices são a base para dois tópicos mais profundos do exame DP-800:

- **Design e tipos de índices** (Seção 01) — columnstore, filtered indexes, compressão de índices e estratégias de manutenção.
- **Análise de planos de consulta** (Seção 06) — planos de execução, index spools, solicitações de índices ausentes e ajuste de índices com `sys.dm_db_missing_index_details`.

## Casos de Uso

- Acelere um relatório diário de vendas que filtra por `OrderDate`.
- Acelere JOINs entre tabelas grandes em colunas de chave estrangeira.
- Evite sobrecarga de ordenação para consultas com `ORDER BY` frequente na mesma coluna.
- Habilite a aplicação de restrição unique (índice único).

## Problemas Comuns & Erros

> [!warning] Erro Comum
> Um índice em toda coluna diminui as escritas e pode não ajudar as leituras. Comece com padrões de consulta, não nomes de colunas.

> [!warning] Erro Comum
> Uma chave primária cria um índice, mas não necessariamente um clustered. Inspecione a definição da tabela em vez de assumir.

> [!warning] Erro Comum
> Adicionar uma função em torno de uma coluna indexada na cláusula `WHERE` (por exemplo, `WHERE YEAR(OrderDate) = 2013`) pode impedir o seek do índice (não SARG). Prefira predicados de intervalo: `WHERE OrderDate >= '2013-01-01' AND OrderDate < '2014-01-01'`.

## Melhores Práticas

- Comece com o predicado da consulta, requisitos de JOIN e sort para identificar candidatos a índice.
- Meça com `SET STATISTICS IO ON` e planos de execução reais antes de declarar um índice benéfico.
- Use `INCLUDE` para colunas não-chave a fim de evitar key lookups, mas não inclua cegamente toda coluna.
- Prefira predicados de intervalo (`col >= '2026-01-01' AND col < '2026-02-01'`) em vez de colunas envolvidas em funções para melhor uso do índice.
- Remova ou desabilite periodicamente índices não utilizados; use `sys.dm_db_index_usage_stats` para encontrá-los.

## Dicas para o Exame

> [!tip] Dicas para o Exame
> Clustered vs nonclustered descreve estrutura de armazenamento, não "rápido" vs "lento." Um índice nonclustered pode ser mais rápido que um clustered para consultas covering. Conheça a compensação: velocidade de leitura vs custo de escrita. No exame, podem perguntar qual design de índice melhor suporta um dado padrão de consulta.

## Principais Conclusões

- Índices trocam custo de escrita/armazenamento por potencial eficiência de leitura.
- Um índice clustered determina a ordem física; um índice nonclustered é uma estrutura separada.
- `STATISTICS IO` mede leituras lógicas — a métrica chave para benefício de índice.
- Meça antes e depois; escolha índices a partir de evidências, não do hábito.
- O padrão covering index elimina key lookups incluindo todas as colunas necessárias.

## Tópicos Relacionados

- [Database Objects](../../01-database-objects/database-objects.md)
- [Performance Optimization](../../06-performance-optimization/performance-optimization.md)
- [Performance-monitoring-and-query-store](../../08-azure-services-integration/07-performance-monitoring-and-query-store.md)
- [Agregação e agrupamento](./06-aggregation-and-grouping.md)

## Documentação Oficial

- [Índices do SQL Server](https://learn.microsoft.com/sql/relational-databases/indexes/indexes)
- [Índices clustered e nonclustered descritos](https://learn.microsoft.com/sql/relational-databases/indexes/clustered-and-nonclustered-indexes-described)
- [CREATE INDEX](https://learn.microsoft.com/sql/t-sql/statements/create-index-transact-sql)
- [SET STATISTICS IO](https://learn.microsoft.com/sql/t-sql/statements/set-statistics-io-transact-sql)

---

**[← Anterior](./09-subqueries-and-ctes.md) | [↑ Voltar à Seção](./fundamentals.md) | [Próximo →](./11-ready-for-dp800.md)**
