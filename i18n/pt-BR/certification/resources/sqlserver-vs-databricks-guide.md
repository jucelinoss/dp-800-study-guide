# 📘 Guia de Transição Arquitetural: SQL Server (RDBMS) para Databricks (Lakehouse)

> **Objetivo**: Conectar os conceitos familiares do SQL Server (Constraints, Identity, Indexes, Graph Tables, JSON, Stored Procedures, Locks) com os equivalentes e paradigmas no ecossistema Databricks, Apache Spark e Delta Lake.

---

## 📌 Visão Geral da Mudança de Paradigma

| Conceito Arquitetural | SQL Server (RDBMS Tradicional) | Databricks / Spark (Lakehouse) |
| :--- | :--- | :--- |
| **Arquitetura Base** | Monolítica / Cluster Ativo-Passivo (*Scale-Up*) | Distribuída Multi-Nó / Spark (*Scale-Out*) |
| **Computação & Storage** | Acoplados (Servidor ligado 24/7) | Desacoplados (Storage em Nuvem + Clusters sob demanda) |
| **Abordagem de Dados** | *Schema-on-Write* (ETL rígido antes de salvar) | *Schema-on-Read* + *Schema-on-Write* (Arquitetura Medallion) |
| **Garantia de Integridade** | Validação síncrona em linha (*Row-level locks*) | Validação no pipeline ETL / *Informational Constraints* |
| **Leitura de Dados** | Índices B-Tree (Clustered/Nonclustered) | Data Skipping, Z-Ordering, Liquid Clustering |
| **Concorrência** | Gerenciador de Trincas/Locks (Shared, Exclusive) | Optimistic Concurrency Control (OCC) |

---

## 🛠️ De-Para de Recursos: SQL Server vs Databricks

### 1. Integridade de Dados & Constraints (`PRIMARY KEY`, `FOREIGN KEY`, `CHECK`)
* **SQL Server**: O motor valida `PRIMARY KEY` e `FOREIGN KEY` síncronamente durante o `INSERT/UPDATE`. Se houver violação, a transação aborta.
* **Databricks / Delta Lake**:
  * **`CHECK` e `NOT NULL`**: Totalmente suportados em nível de arquivo no Delta Lake (`ALTER TABLE ADD CONSTRAINT ... CHECK (...)`).
  * **`PRIMARY KEY` e `FOREIGN KEY` (Informational Constraints)**: No Unity Catalog, são salvas como metadados informativos. O otimizador de consultas (Photon/Catalyst) as utiliza para eliminar JOINs redundantes (*Join Elimination*), mas elas **não bloqueiam** cargas de Big Data na gravação para evitar custos massivos de comunicação em rede (*data shuffling*).
  * *Boa Prática no Databricks*: A integridade referencial é mantida nas camadas Silver/Gold via Delta Live Tables (DLT) com cláusulas `EXPECT` ou regras de quarentena.

---

### 2. Geradores de Chaves Sequenciais (`IDENTITY` e `SEQUENCE`)
* **SQL Server**: `IDENTITY(1,1)` ou `SEQUENCE` geram valores estritamente sequenciais e atômicos usando contadores em memória.
* **Databricks / Delta Lake**:
  * **`GENERATED ALWAYS AS IDENTITY`**: Suportado nativamente no Delta Lake, mas os números são gerados em blocos paralelos por nó executor (não obrigatoriamente contíguos sem ordenação).
  * **Chaves Substitutas em Big Data**: Para pipelines distribuídos, utiliza-se `uuid()` ou hashes determinísticos como `md5(concat(colA, colB))`.

---

### 3. Otimização de Leitura: B-Trees vs Data Skipping e Liquid Clustering
* **SQL Server**: Utiliza **B-Trees** (Índices Clusterizados e Não-Clusterizados) e **Columnstore Indexes** para localizar linhas específicas.
* **Databricks / Delta Lake**: Não utiliza B-Trees (inviáveis para Petabytes). A otimização ocorre por:
  * **Data Skipping**: Cada arquivo Parquet registra metadados com os valores mínimo e máximo de cada coluna. Consultas `WHERE` pulam arquivos inteiros sem lê-los.
  * **Liquid Clustering**: Substituiu o antigo *Z-Ordering* e particionamento rígido. Reorganiza dinamicamente os arquivos Parquet à medida que os dados são inseridos, otimizando consultas multidimensionais sem distorção (*data skew*).

---

### 4. Processamento de Semi-Estruturados (`JSON`)
* **SQL Server**: Funções `JSON_VALUE`, `OPENJSON`, `JSON_QUERY` operando em colunas `NVARCHAR` ou `JSON` (SQL 2022+).
* **Databricks**:
  * Funções de alta performance: `from_json()`, `to_json()`, `schema_of_json()`, sintaxe de ponto (`coluna:campo.subcampo`).
  * **Tipo de Dado `VARIANT`**: Permite armazenar estruturas JSON complexas e dinâmicas com a velocidade de colunas relacionais tipadas, sem necessidade de definir schemas previamente.

---

### 5. Grafos e Análise de Redes (`AS NODE`, `AS EDGE`)
* **SQL Server**: Tabelas de Grafo nativas com extensão T-SQL `MATCH()` e `SHORTEST_PATH()`.
* **Databricks**: **GraphFrames (PySpark)** e **GraphX**.
  * Permite converter tabelas Delta em Grafos Distribuídos.
  * Suporta algoritmos avançados de Big Data Graph (ex: *PageRank*, *Shortest Path*, *Connected Components*, *Triangle Count*, *Label Propagation*) para análise de fraudes e redes de recomendações em grande escala.

---

### 6. Programmability: Stored Procedures & Triggers vs Notebooks & CDF
* **SQL Server**: Stored Procedures T-SQL (lógica imperativa, loops, transações) e Triggers reativos (`AFTER`, `INSTEAD OF`).
* **Databricks**:
  * **Notebooks & Módulos (Python/PySpark/SQL)**: Substituem Stored Procedures com suporte a testes unitários, controle de versão (Git) e execução paralela.
  * **Delta Lake Change Data Feed (CDF)**: Substitui Triggers e CDC. Registra alterações de nível de linha (`INSERT`, `UPDATE`, `DELETE`) no log Delta, permitindo disparar pipelines reativos e streaming sem sobrecarregar a tabela principal.
  * **Materialized Views (DLT)**: Atualização incremental automática mantida pelo motor Delta Live Tables.

---

### 7. Transações e Concorrência (ACID & Locks)
* **SQL Server**: Gerenciador de Travas (Lock Manager) com bloqueios de linha/página/tabela (Shared, Exclusive) ou isolamento por versão de linha (RCSI / Snapshot Isolation).
* **Databricks**: **Optimistic Concurrency Control (OCC)** atrelado ao log de transações Delta (`_delta_log`).
  * Leituras são **100% não-bloqueantes** (leitores nunca travam gravadores).
  * Conflitos de escrita são resolvidos tentando reaplicar a transação automaticamente ou lançando exceções de concorrência se houver alteração simultânea nos mesmos arquivos.

---

## 🎯 Resumo da Estratégia de Transição

Ao transitar do SQL Server para o Databricks, lembre-se:

1. **Troque "Garantia na Inserção" por "Qualidade no Pipeline"**: Em vez de depender do banco para rejeitar registros via Foreign Keys, valide a qualidade dos dados nas camadas **Bronze → Silver** com regras de negócios explícitas (DLT / Great Expectations).
2. **Troque "Índices B-Tree" por "Layout de Arquivos (Liquid Clustering)"**: Projete o layout dos arquivos Delta pensando em como os dados serão filtrados no Data Lake.
3. **Troque "Stored Procedures T-SQL" por "Pipelines PySpark / DLT"**: Escreva código modular em Python/PySpark integrando SQL nativo onde for conveniente.
4. **Adote a Arquitetura Híbrida**: O Databricks faz o trabalho pesado de Big Data, ETL e IA; o SQL Server / Data Mart entrega os resultados sumarizados com latência de milissegundos para aplicações operacionais e dashboards.
