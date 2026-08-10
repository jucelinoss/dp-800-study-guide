---
title: Recomendações de Configuração do Banco de Dados (Database Configuration Recommendations)
type: study-material
tags:
  - dp-800
  - performance
  - database-configuration
  - azure-sql
  - service-tiers
---

> [!info] 🗺️ Índice de Navegação Rápida
>
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Camadas de Serviço do Azure SQL (Azure SQL Service Tiers)](#camadas-de-serviço-do-azure-sql-azure-sql-service-tiers)
>   - 🔹 [Baseado em DTU (Modelo de precificação legado simplificado)](#baseado-em-dtu-modelo-de-precificação-legado-simplificado)
>   - 🔹 [Baseado em vCore (Modelo moderno recomendado)](#baseado-em-vcore-modelo-moderno-recomendado)
> - 📍 [3. Nível de Compatibilidade do Banco de Dados (Database Compatibility Level)](#nível-de-compatibilidade-do-banco-de-dados-database-compatibility-level)
> - 📍 [4. Configurações no Escopo do Banco (Database-Scoped Configurations)](#configurações-no-escopo-do-banco-database-scoped-configurations)
> - 📍 [5. Configurações de Memória e Recursos do Servidor](#configurações-de-memória-e-recursos-do-servidor)
> - 📍 [6. Ajuste Automático no Azure SQL (Automatic Tuning)](#ajuste-automático-no-azure-sql-automatic-tuning)
> - 📍 [7. MAXDOP e Parametrizações de Paralelismo](#maxdop-e-parametrizações-de-paralelismo)
> - 📍 [8. Concessões de Memória (Memory Grants)](#concessões-de-memória-memory-grants)
> - 📍 [9. Query Store (Repositório de Consultas)](#query-store-repositório-de-consultas)
> - 📍 [10. Quadro de Características dos Níveis de Compatibilidade](#quadro-de-características-dos-níveis-de-compatibilidade)
> - 📍 [11. Casos de Uso (Use Cases)](#casos-de-uso-use-cases)
> - 📍 [12. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [13. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [14. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [15. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [16. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [17. Documentação Oficial](#documentação-oficial)

---

# Recomendações de Configuração do Banco de Dados (Database Configuration Recommendations)

## Visão Geral (Overview)

As escolhas de configuração de um banco de dados — camadas de serviço (service tiers), nível de compatibilidade (compatibility level), concessões de memória (memory grants) e opções de escopo do banco (database-scoped configurations) — afetam drasticamente a performance. O exame DP-800 avalia a habilidade de recomendar as melhores configurações para tipos específicos de workloads.

> [!abstract]
>
> - Cobre configurações de escopo de banco de dados (MAXDOP, cost threshold, estatísticas automáticas), níveis de compatibilidade e parametrizações do Query Store.
> - Configurações aplicadas no escopo do banco de dados influenciam todas as consultas associadas, a menos que sejam sobrescritas a nível de query por meio de query hints.
> - Tópicos chave do exame: valores de MAXDOP apropriados, impactos de compatibilidade do otimizador e comportamento de criação e atualização automática de estatísticas.

> [!tip] O que o Exame Testa
>
> `MAXDOP`
>
> - `MAXDOP = 0` -> permitir o uso de todos os processadores disponíveis, sujeito aos limites do ambiente e do plano;
> - `MAXDOP = 1` -> desabilitar execução paralela;
> - `(MAXDOP n)` -> limitar o grau máximo de paralelismo a `n` processadores;
> - `ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = n` altera o comportamento padrão do banco de dados correspondente (sem afetar as configurações globais do servidor SQL).
> - **Nível de compatibilidade (compatibility level)** rege o comportamento do otimizador de consultas e a ativação de recursos lógicos — opera de forma independente da versão física instalada do engine.

---

## Camadas de Serviço do Azure SQL (Azure SQL Service Tiers)

### Baseado em DTU (Modelo de precificação legado simplificado)

| Camada (Tier) | Casos de Uso comuns | Faixa de DTUs |
| :--- | :--- | :--- |
| Basic | Desenvolvimento, testes básicos, bases pequenas. | Até 5 DTUs. |
| Standard | Workloads departamentais de média intensidade. | 10 a 3000 DTUs. |
| Premium | Sistemas de missão crítica, suporte a In-Memory OLTP. | 125 a 4000 DTUs. |

### Baseado em vCore (Modelo moderno recomendado)

| Camada (Tier) | Casos de Uso comuns | Diferencial Arquitetural |
| :--- | :--- | :--- |
| **General Purpose** | A maioria das cargas comuns corporativas. | Armazenamento remoto, suporte a auto-pause. |
| **Business Critical** | Baixíssima latência de I/O, In-Memory OLTP. | SSDs locais de alta velocidade, réplica de HA embutida gratuita. |
| **Hyperscale** | Bancos de dados de grande escala (até 128 TB). | `Escalonamento rápido de escrita/leitura, arquitetura distribuída`. |

**Serviço Serverless (Apenas General Purpose):** Pausa automática (auto-pause) quando ocioso e auto-scale de computação baseado em limites mínimos e máximos definidos pelo administrador.

```text
Azure Portal → Azure SQL → Configure → Serverless
- Min vCores: 0.5 (mínimo reservado quando em uso)
- Max vCores: 4
- Auto-pause delay: 60 minutos (inatividade antes da pausa)
```

---

## Nível de Compatibilidade do Banco de Dados (Database Compatibility Level)

O nível de compatibilidade determina quais recursos lógicos do Query Optimizer e comportamentos do compilador T-SQL estão ativos no banco:

```sql
-- Consultar o nível de compatibilidade ativo
SELECT name, compatibility_level FROM sys.databases WHERE name = DB_NAME();

-- Alterar o nível de compatibilidade do banco
ALTER DATABASE MyDB SET COMPATIBILITY_LEVEL = 160; -- SQL Server 2022 / Azure SQL
```

> [!important] Níveis de Compatibilidade vs Versões do Engine
>
> - Alterar o nível de compatibilidade de um banco (`COMPATIBILITY_LEVEL`) **não** altera a versão física instalada do SQL Server. Ele apenas ativa ou desativa recursos lógicos do otimizador de consultas (Query Optimizer).
> - **Dica de Exame**: Em caso de lentidão após um upgrade do motor do SQL Server, **nunca** retroceda a compatibilidade total do banco como primeira medida permanente. Use o Query Store para identificar planos degradados e force o plano bom anterior.

**Comportamentos por Nível de Compatibilidade:**

| Nível (Level) | Engine Equivalente | Principais Recursos do Otimizador |
| :--- | :--- | :--- |
| 160 | SQL Server 2022 | Otimização PSP (Parameter Sensitive Plan), DOP feedback, CE feedback. |
| 150 | SQL Server 2019 | Inline de Scalar UDFs, compilação adiada de variáveis de tabela. |
| 140 | SQL Server 2017 | Processamento de consultas adaptativas (adaptive joins, execução intercalada). |
| 130 | SQL Server 2016 | Modo batch para funções de agregação, `INSERT INTO ... SELECT` paralelos. |

---

## Configurações no Escopo do Banco (Database-Scoped Configurations)

```sql
-- Verificar se o RCSI está habilitado no banco
SELECT name, is_read_committed_snapshot_on FROM sys.databases WHERE name = DB_NAME();

-- Habilitar Read Committed Snapshot Isolation (RCSI) — Padrão e recomendado no Azure SQL Database
ALTER DATABASE MyDB SET READ_COMMITTED_SNAPSHOT ON;

-- Habilitar e parametrizar o Query Store
ALTER DATABASE MyDB SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,
    MAX_STORAGE_SIZE_MB = 1000
);

-- Definir limite máximo de grau de paralelismo (MAXDOP) na base
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 4;

-- Habilitar/Desabilitar o antigo Cardinality Estimator (estimador de cardinalidade)
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;

-- Otimizar cache para queries ad-hoc (SQL Server local)
EXEC sp_configure 'optimize for ad hoc workloads', 1;
RECONFIGURE;
```

> [!important] RCSI no Azure SQL vs. SQL Server On-Premises
>
> - **Ativo Por Padrão no Azure SQL Database**: No **Azure SQL Database** (Single Databases e Elastic Pools), a opção `READ_COMMITTED_SNAPSHOT` já vem **habilitada por padrão (`ON`)** na criação do banco de dados. No **SQL Server On-Premises** e no **Azure SQL Managed Instance**, o padrão histórico é **`OFF`**.
> - **Efeito do RCSI**: Em cargas que se beneficiam de versionamento de linhas, o **RCSI** pode reduzir a contenção entre leitura e escrita:
>   1. **Menos bloqueio entre leitura e escrita**: Transações de leitura (`SELECT`) acessam a versão confirmada anteriormente no Version Store (`tempdb`) sem solicitar travas compartilhadas (`Shared / S locks`) para os dados versionados. Isso não elimina travas de esquema nem bloqueios entre escritores.
>   2. **Transparente para a Aplicação**: Aplicações executando no nível de isolamento padrão (`READ COMMITTED`) se beneficiam imediatamente de leituras sem bloqueio sem requerer qualquer alteração no código T-SQL ou hints adicionais.
>   3. **Possível redução de contenção**: Pode diminuir cadeias de bloqueio entre leitores e escritores, mas não garante a eliminação de deadlocks.
>   4. **Considerações de Recursos**: O versionamento de linhas utiliza o **Version Store no `tempdb`** e pode adicionar sobrecarga de versionamento às linhas. Monitorar a utilização e o espaço do `tempdb` é essencial em workloads de escrita extremamente pesada.

---

## Configurações de Memória e Recursos do Servidor

```sql
-- Diagnosticar alocações de memória ativas por consultas
SELECT * FROM sys.dm_exec_query_memory_grants;

-- Consultar limites ativos do servidor (SQL Server On-Premises, Azure VM e SQL Managed Instance)
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN ('max server memory (MB)', 'min server memory (MB)',
               'max degree of parallelism', 'cost threshold for parallelism');
```

### Aplicabilidade por Plataforma (On-Premises vs. Azure SQL)

Nem todas as configurações de nível de servidor se aplicam ou podem ser alteradas em serviços PaaS do Azure:

| Configuração | SQL Server On-Premises / Azure VM (IaaS) | Azure SQL Managed Instance (MI) | Azure SQL Database (PaaS - Single/Elastic) | Prática Recomendada |
| :--- | :--- | :--- | :--- | :--- |
| `max server memory` | **Configurável** (`sp_configure`) | **Gerenciado pelo Azure** (Automático) | **Gerenciado pelo Azure** (Não aplicável) | Reserve de 10% a 15% da RAM física para o OS no On-Premises/IaaS. |
| `MAXDOP` | **Configurável** (Servidor, DB, Query) | **Configurável** (Servidor, DB, Query) | **Configurável** (`DATABASE SCOPED` ou Query Hint) | Avaliar um limite adequado ao workload; valores como 2 a 8 são apenas exemplos. |
| `cost threshold for parallelism` | **Configurável** (`sp_configure`) | **Configurável** (`sp_configure`) | **Não Configurável** (Sem suporte no PaaS) | O valor deve ser ajustado com base em planos e carga; 25 a 50 é apenas uma faixa de teste possível. |

> [!important] Regra de Ouro para o Exame DP-800
>
> - **No Azure SQL Database (PaaS)**, a instrução `sp_configure` a nível de servidor **não está disponível**. Portanto, o tuning de paralelismo é feito exclusivamente via `ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = n` ou `OPTION (MAXDOP n)`.
> - **No Azure SQL Managed Instance (MI)**, você tem acesso à maioria dos parâmetros de nível de servidor via `sp_configure` (como `cost threshold for parallelism`), exceto pelo gerenciamento físico da memória que é governado pelo Azure.

---

## Ajuste Automático no Azure SQL (Automatic Tuning)

O Azure SQL Database consegue analisar performance e ajustar de forma automática índices e planos:

```sql
-- Ativar opções de ajuste automatizado (Automatic Tuning)
ALTER DATABASE MyDB SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
ALTER DATABASE MyDB SET AUTOMATIC_TUNING (CREATE_INDEX = ON);
ALTER DATABASE MyDB SET AUTOMATIC_TUNING (DROP_INDEX = ON);

-- Consultar recomendações geradas pelo tuning automático
SELECT * FROM sys.dm_db_tuning_recommendations;
```

> [!tip] Automatic Tuning: FORCE_LAST_GOOD_PLAN
>
> - O recurso `FORCE_LAST_GOOD_PLAN` (Forçar Último Plano Bom) do Automatic Tuning monitora o Query Store.
> - Se o SQL Server detectar uma regressão de performance decorrente de uma mudança de plano de execução (ex: sniffing de parâmetros), ele **automaticamente** força o último plano conhecido com bom desempenho.

---

## MAXDOP e Parametrizações de Paralelismo

A configuração **MAXDOP** (Maximum Degree of Parallelism) limita a quantidade máxima de threads paralelas que o motor do SQL Server pode associar para rodar uma única consulta.

**Precedência de Escopos** (o escopo mais específico sobrescreve os demais):

1. Query hint na consulta: `OPTION(MAXDOP n)`.
2. Configuração no escopo da base: `ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = n`.
3. Configuração do servidor: `sp_configure 'max degree of parallelism'`.

**Limiar de Custo para Paralelismo (Cost Threshold for Parallelism):** O custo estimado de execução do plano (em segundos arbitrários no hardware de referência original) que a consulta deve exceder para o otimizador cogitar um plano paralelo. O valor padrão original (5) é considerado extremamente baixo para hardwares modernos, fazendo com que pequenas consultas rodem paralelas gerando overhead desnecessário de troca de contexto de threads.

> [!warning] Cuidado de Exame: MAXDOP = 0 vs MAXDOP = 1
>
> - **MAXDOP = 0**: Significa utilizar **todos** os cores de CPU disponíveis no servidor (pode causar saturação de threads em OLTP concorrido).
> - **MAXDOP = 1**: **Desativa** por completo a paralelização de consultas (força execução serial).
> - Em sistemas OLTP com muitas transações curtas, o padrão recomendado para o banco de dados é limitar o MAXDOP a valores pequenos (ex: 2 a 8) e aumentar o `cost threshold for parallelism` para evitar paralelismo desnecessário.

```sql
-- Configurar MAXDOP a nível de escopo do banco no Azure SQL
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 4;

-- Forçar execução serial em uma query específica via Hint
SELECT CustomerID, SUM(TotalAmount) AS Total
FROM Orders
GROUP BY CustomerID
OPTION(MAXDOP 1);

-- Ajustar cost threshold a nível de servidor (SQL Server e SQL MI)
EXEC sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE;
```

---

## Concessões de Memória (Memory Grants)

A concessão de memória (**Memory Grant**) é a reserva temporária de RAM física alocada para a query antes de iniciar sua execução física, utilizada principalmente para operações pesadas de ordenação (`SORT`) e junções hash (`HASH JOIN`).

- **Memory Grant muito baixo**: O SQL Server realiza operações pesadas descarregando dados temporários no disco (**spill para tempdb**), reduzindo a performance.
- **Memory Grant excessivo**: Desperdiça RAM que poderia ser alocada por outras transações concorrentes.

**Memory Grant Feedback (MGF):** O feedback em modo batch está disponível a partir da compatibilidade 140. O feedback em modo row está disponível a partir da compatibilidade 150. Em SQL Server 2022 e serviços Azure compatíveis, a persistência e o algoritmo percentil dependem do Query Store em modo de leitura e gravação.

```sql
-- Rastrear filas e grants de memória ativas
SELECT session_id, granted_memory_kb, used_memory_kb,
       ideal_memory_kb, requested_memory_kb,
       wait_time_ms, queue_id
FROM sys.dm_exec_query_memory_grants;

-- Forçar um grant mínimo para um sort de relatório
SELECT CustomerID, SUM(TotalAmount) AS Total
FROM Orders
GROUP BY CustomerID
ORDER BY Total DESC
OPTION(MIN_GRANT_PERCENT = 10);
```

Principais colunas em `sys.dm_exec_query_memory_grants`:

| Coluna | Descrição |
| :--- | :--- |
| `granted_memory_kb` | Memória física alocada de fato para a execução da query. |
| `ideal_memory_kb` | Memória ótima estimada pelo otimizador para não ter spills. |
| `used_memory_kb` | RAM efetivamente consumida no término da execução. |
| `wait_time_ms` | Tempo que a query esperou na fila por falta de RAM (> 0 indica pressão de memória). |

---

## Query Store (Repositório de Consultas)

O **Query Store** captura e mantém um histórico consolidado das queries enviadas ao banco, seus planos de execução físicos gerados e estatísticas reais de runtime. Ele é a principal ferramenta do DP-800 para diagnosticar e mitigar regressões de planos (plan regressions).

**Dados capturados pelo Query Store:**

- Texto completo das consultas executadas e seus formatos parametrizados.
- Diferentes planos de execução gerados e históricos de alterações.
- Estatísticas de runtime agregadas por intervalo (uso de CPU, tempo de execução, I/O físico, concessão de memória).
- Estatísticas de esperas de recursos (wait statistics).

**Parâmetros de Configuração Chave:**

| Parâmetro | Descrição | Valor Recomendado |
| :--- | :--- | :--- |
| `OPERATION_MODE` | `READ_WRITE` permite gravar logs; `READ_ONLY` pausa novas capturas. | `READ_WRITE` |
| `MAX_STORAGE_SIZE_MB` | Limite máximo de espaço em disco reservado para a base do Query Store. | 1024 a 2048 MB |
| `INTERVAL_LENGTH_MINUTES` | Intervalo temporal para agregar as estatísticas em tabelas de histórico. | 60 minutos |
| `QUERY_CAPTURE_MODE` | Escopo de captura: `ALL` (todas as queries), `AUTO` (queries relevantes). | `AUTO` |
| `SIZE_BASED_CLEANUP_MODE` | Purga automática de dados históricos antigos se atingir o limite físico. | `AUTO` |

```sql
-- Configurar Query Store na base
ALTER DATABASE MyDatabase
SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    MAX_STORAGE_SIZE_MB = 1024,
    INTERVAL_LENGTH_MINUTES = 60,
    QUERY_CAPTURE_MODE = AUTO, -- Ignora queries irrelevantes de execução única
    SIZE_BASED_CLEANUP_MODE = AUTO
);

-- Buscar as 10 queries com maior consumo de CPU médio
SELECT TOP 10
    qt.query_sql_text,
    qrs.avg_cpu_time,
    qrs.avg_duration,
    qrs.count_executions
FROM sys.query_store_query_text qt
JOIN sys.query_store_query q ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan qp ON q.query_id = qp.query_id
JOIN sys.query_store_runtime_stats qrs ON qp.plan_id = qrs.plan_id
ORDER BY qrs.avg_cpu_time DESC;

-- Forçar o banco a usar um plano específico (plan forcing)
EXEC sp_query_store_force_plan @query_id = 42, @plan_id = 1;
```

---

## Quadro de Características dos Níveis de Compatibilidade

| Nível | Engine SQL | Principais Recursos de Otimização no Exame |
| :--- | :--- | :--- |
| **130** | SQL Server 2016 | Agregações em modo batch, execução paralela de `INSERT INTO ... SELECT`. |
| **140** | SQL Server 2017 | Junções adaptativas (adaptive joins), execução intercalada, memory grant feedback. |
| **150** | SQL Server 2019 | Inline de Scalar UDFs, compilação adiada de variáveis de tabela. |
| **160** | SQL Server 2022 | Otimização PSP (planos sensíveis a parâmetros), feedback de DOP e CE. |

---

## Casos de Uso (Use Cases)

- **Camada Business Critical**: ERPs de missão crítica que necessitam de baixíssima latência de I/O em discos SSD locais e alta disponibilidade nativa.
- **Camada Serverless**: Bancos secundários de relatórios ou desenvolvimento com picos de tráfego imprevisíveis que se beneficiam do auto-pause.
- **RCSI**: Bancos OLTP movimentados para evitar que comandos de escrita (`UPDATE`) causem travamentos em leituras (`SELECT`).
- **Query Store**: Mitigação de regressões de queries causadas por snifagem de parâmetros logo após migrações ou trocas de compatibilidades.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Alto uso de I/O no TempDB por queries | Estouro de memória temporária (spills) | Melhore as estimativas com estatísticas novas ou use hints de grant mínimo. |
| O Query Store parou de gravar logs | O espaço máximo (`MAX_STORAGE_SIZE_MB`) foi atingido | Altere para `SIZE_BASED_CLEANUP_MODE = AUTO` ou aumente o tamanho máximo do disco. |
| Regressão grave após alteração de nível | Estimador de cardinalidade novo falha em estimar as linhas | Use o Query Store para restaurar o plano bom antigo via `sp_query_store_force_plan`. |
| Lentidão por paralelismo excessivo | Cost Threshold baixo ou MAXDOP desajustado | Eleve o cost threshold para 50 e defina um MAXDOP seguro (ex: 4). |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - Habilitar o isolamento **RCSI** remove bloqueios de leituras/escritas concorrentes em cargas OLTP.
> - O Query Store é a **ferramenta recomendada padrão** para rastrear e solucionar problemas de regressão de planos de execução.
> - O recurso de ajuste automático `FORCE_LAST_GOOD_PLAN` corrige de forma automática as instabilidades de planos no Azure SQL Database.
> - `MAXDOP = 0` autoriza o uso de toda a CPU física; use `MAXDOP = 1` se o seu objetivo for forçar a query a rodar serializada.
> - O feedback de concessão de memória (Memory grant feedback) ajusta o uso de RAM automaticamente e dispensa a colocação de hints manuais no código em cargas de trabalho estáveis.

---

## Resumo dos Conceitos (Key Takeaways)

- Selecione camadas de serviço (General Purpose vs Business Critical) baseando-se em latência e volume de escrita.
- Utilize o Query Store para blindar seu banco contra regressões lógicas após upgrades.
- Ajuste as configurações de paralelismo (MAXDOP e cost threshold) para resguardar recursos de CPU em OLTP.
- Habilite o RCSI para simplificar e mitigar gargalos de concorrência.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Logo após efetuar a alteração do nível de compatibilidade de um banco de dados Azure SQL de 130 para 150, os administradores detectaram que três consultas críticas de relatórios apresentaram degradações graves de performance devido a planos ineficientes gerados pelo novo estimador de cardinalidade. Qual é a ação recomendada para resolver o problema de forma rápida e estável?

A. Retroceder a compatibilidade do banco inteiro para 130.

B. Utilizar o Query Store para identificar as regressões de planos e forçar os planos bons executados anteriormente no nível 130.

C. Reiniciar a instância do Azure SQL Server para limpar o plano de cache.

D. Alterar a configuração de MAXDOP do banco de dados para 1.

> [!success]- Resposta
> **B — Utilizar o Query Store para identificar as regressões de planos e forçar os planos bons executados anteriormente no nível 130**
>
> O Query Store retém os planos históricos anteriores à migração. Ao detectar regressões pontuais nas queries, o administrador consegue forçar os planos antigos eficientes sem precisar abdicar dos novos recursos e melhorias trazidas pelo nível de compatibilidade 150 para todo o restante das tabelas e consultas do banco. Reverter o nível completo do banco (A) é desencorajado.

---

## Tópicos Relacionados

- [02-Isolamento de Transações & Concorrência](./02-transaction-isolation-concurrency.md) *(Inglês apenas)*
- [03-Solução de Problemas de Desempenho de Queries](./03-query-performance-troubleshooting.md) *(Inglês apenas)*

---

## Documentação Oficial

- [Azure SQL Service Tiers](https://learn.microsoft.com/en-us/azure/azure-sql/database/service-tiers-overview)
- [ALTER DATABASE SCOPED CONFIGURATION](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-scoped-configuration-transact-sql)
- [Automatic Tuning](https://learn.microsoft.com/en-us/azure/azure-sql/database/automatic-tuning-overview)
- [Query Store Overview](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- [Transaction Locking and Row Versioning Guide](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide)
- [Memory Grant Feedback](https://learn.microsoft.com/en-us/sql/relational-databases/performance/adaptive-query-processing)

---

**[↑ Voltar para a Seção](./performance-optimization.md) | [Lab: Configurações de Banco](../../practice/labs/06-performance-optimization/01-database-configurations-lab.sql) | [Próximo →](./02-transaction-isolation-concurrency.md)**
