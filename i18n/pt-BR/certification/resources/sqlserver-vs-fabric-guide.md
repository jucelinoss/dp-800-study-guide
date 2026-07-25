# 📘 Guia de Transição Arquitetural: SQL Server (RDBMS) para Microsoft Fabric (SaaS Analytics & OneLake)

> **Objetivo**: Conectar os conceitos familiares do SQL Server (T-SQL, Constraints, Indexes, Stored Procedures, RLS, Identity) com a arquitetura unificada do **Microsoft Fabric** (OneLake, Synapse Data Warehouse, Fabric Lakehouse, Fabric SQL Database e DirectLake).

---

## 📌 Visão Geral da Mudança de Paradigma

| Conceito Arquitetural | SQL Server (RDBMS Tradicional) | Microsoft Fabric (SaaS Analytics Unified) |
| :--- | :--- | :--- |
| **Arquitetura Base** | Monolítica / Cluster Ativo-Passivo (*Scale-Up*) | Plataforma SaaS Unificada Multi-Engine (*Scale-Out*) |
| **Formato de Dados** | Proprietário (`.mdf`, `.ndf`, Páginas 8KB) | **OneLake** (Formato Aberto Delta Lake / Parquet com **V-Order**) |
| **Engines de Consulta** | Motor T-SQL Único (OLTP/OLAP) | **Synapse DW** (T-SQL MPP), **Spark** (PySpark), **KQL**, **Power BI** |
| **Integração com BI** | Modo Import (Duplicação) ou DirectQuery (Lento) | **DirectLake Mode** (Leitura direta das tabelas Delta sem importar) |
| **Banco Relacional OLTP Nativo** | SQL Server Engine | **Fabric SQL Database** (Serverless T-SQL + Espelhamento em tempo real) |
| **Concorrência & Conexão** | Conexões de Soquete / Lock Manager | Concorrência Distribuída MPP / Optimistic Concurrency no Delta |

---

## 🛠️ De-Para de Recursos: SQL Server vs Microsoft Fabric

### 1. Motor T-SQL e Compatibilidade de Código
* **SQL Server**: Linguagem T-SQL nativa completa (Stored Procedures, DDL, DML, CTEs, Window Functions, Triggers, Cursors).
* **Microsoft Fabric**:
  * **Synapse Data Warehouse & SQL Analytics Endpoint**: Excelente compatibilidade T-SQL! Suporta `SELECT`, `JOIN`, `CTE`, `WINDOW FUNCTIONS`, `CREATE VIEW`, `CREATE PROCEDURE` e transações multi-tabela (`BEGIN TRANSACTION / COMMIT`).
  * **Diferença**: Não possui suporte a Triggers legadas ou cursors de linha a linha pesados, priorizando operações de conjunto (*Set-based operations*) de alto desempenho.

---

### 2. Integridade de Dados & Constraints (`PRIMARY KEY`, `FOREIGN KEY`, `CHECK`)
* **SQL Server**: Validação síncrona com bloqueio de linha/tabela (*Strict Enforcement*).
* **Microsoft Fabric**:
  * **`NOT NULL`**: Suportado nativamente.
  * **`PRIMARY KEY` e `FOREIGN KEY` (NOT ENFORCED)**: No Fabric DW e Lakehouse, as PKs e FKs são **informacionais (non-enforced)**. O otimizador de consultas MPP utiliza esses metadados para otimizações de plano como *Join Elimination*, reduzindo o tempo de consulta sem travar cargas massivas em paralelo.
  * **Fabric SQL Database (Novo)**: Oferece suporte completo a constraints ACID tradicionais para cargas operacionais OLTP!

---

### 3. Geradores de Chaves Sequenciais (`IDENTITY`)
* **SQL Server**: `IDENTITY(1,1)` ou `SEQUENCE` com contadores atômicos em memória.
* **Microsoft Fabric**:
  * **Fabric DW**: Suporta a sintaxe `IDENTITY(1,1)` em tabelas de dimensão.
  * **Diferença em MPP**: Como o Fabric opera em arquitetura distribuída, a geração de IDs ocorre em blocos atribuídos aos nós de computação.

---

### 4. Otimização de Leitura: B-Trees vs V-Order e Delta Data Skipping
* **SQL Server**: Utiliza **B-Trees** (Índices Clusterizados e Não-Clusterizados) para buscar linhas específicas em páginas de 8KB.
* **Microsoft Fabric**:
  * **V-Order (O Pulo do Gato do Fabric)**: O V-Order é um algoritmo de otimização proprietário da Microsoft aplicado no momento de gravar os arquivos Parquet no OneLake. Ele ordena e comprime os dados colunares de forma tão eficiente que permite à engine T-SQL e ao engine VertiPaq do Power BI ler os arquivos com velocidade similar à memória RAM.
  * **Data Skipping**: Pula arquivos inteiros com base nos metadados min/max de cada coluna.

---

### 5. Consumo de BI: Fim do Dilema Import vs DirectQuery (`DirectLake`)
* **SQL Server**: Para ter boa performance no Power BI, você precisava **importar** os dados (duplicando storage e exigindo atualizações agendadas) ou usar **DirectQuery** (que onerava o SQL Server com centenas de queries simultâneas).
* **Microsoft Fabric**:
  * **DirectLake Mode**: O Power BI lê os arquivos Delta/Parquet otimizados em V-Order **diretamente do OneLake** para a memória do engine VertiPaq, sem precisar importar ou fazer queries de tradução T-SQL. É o desempenho do Modo Import com os dados 100% atualizados em tempo real!

---

### 6. Segurança de Dados (RLS, DDM e Object-Level Security)
* **SQL Server**: Row-Level Security (RLS) via predicados de segurança T-SQL, Dynamic Data Masking (DDM) e permissões `GRANT/DENY` por tabela/coluna.
* **Microsoft Fabric**:
  * **Suporte T-SQL Nativo**: O Fabric DW suporta **Row-Level Security (RLS)**, **Column-Level Security (CLS)** e **Dynamic Data Masking (DDM)** definidos nativamente via T-SQL.
  * **OneSecurity**: O Fabric propaga automaticamente as regras de segurança definidas no T-SQL Endpoint até o Power BI e engines Spark!

---

### 7. Ingestão e Processamento de Dados: SSIS vs Data Factory / Pipelines
* **SQL Server**: Utilizava SQL Server Integration Services (SSIS) para pacotes ETL locais.
* **Microsoft Fabric**:
  * **Data Factory no Fabric**: Pipelines visuais modernos de ingestão + **Dataflows Gen2** (baseados em Power Query).
  * **Mirroring (Espelhamento Automático)**: Permite espelhar bancos como SQL Server, Azure SQL DB, Cosmos DB e Snowflake no OneLake em tempo real sem escrever pipelines ETL!

---

## 🎯 Por Que a Migração para o Fabric É Ainda Mais Natural para Desenvolvedores SQL Server?

Diferente do Databricks (que exige transição forte para Python/PySpark), o **Microsoft Fabric é um ambiente "T-SQL First"**:

1. **Aproveitamento de Habilidades**: Você continua escrevendo queries em **T-SQL**, criando **Views**, **Stored Procedures** e usando ferramentas familiares como **SSMS (SQL Server Management Studio)** ou **Azure Data Studio**.
2. **Sem Necessidade de Manutenção de DW Físico**: Sem `REBUILD INDEX`, sem gerenciamento de Filegroups, sem ajuste manual de `MAXDOP` ou arquivos `tempdb`.
3. **OneLake Único**: Todas as ferramentas (DW, Spark, Power BI, Data Factory) enxergam a mesma cópia do dado no OneLake, eliminando o pesadelo de ter 10 cópias duplicadas dos mesmos dados na empresa.
