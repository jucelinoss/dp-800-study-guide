---
title: Solução de Problemas de Desempenho de Queries (Query Performance Troubleshooting)
type: study-material
tags:
  - dp-800
  - execution-plans
  - dmv
  - query-store
  - query-performance-insight
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Planos de Execução (Execution Plans)](#planos-de-execução-execution-plans)
>   - 🔹 [Habilitando Planos de Execução via T-SQL](#habilitando-planos-de-execução-via-t-sql)
>   - 🔹 [Operadores de Plano de Execução Comuns](#operadores-de-plano-de-execução-comuns)
>   - 🔹 [Analisando Percentuais de Custo no Plano](#analisando-percentuais-de-custo-no-plano)
> - 📍 [3. Diagnóstico usando Views de Gerenciamento Dinâmico (DMVs)](#diagnóstico-usando-views-de-gerenciamento-dinâmico-dmvs)
>   - 🔹 [Identificando Queries com Maior Consumo](#identificando-queries-com-maior-consumo)
>   - 🔹 [Consultando Recomendações de Índices Ausentes](#consultando-recomendações-de-índices-ausentes)
>   - 🔹 [Consultando Estatísticas de Espera Globais (Wait Stats)](#consultando-estatísticas-de-espera-globais-wait-stats)
> - 📍 [4. Query Store (Repositório de Consultas)](#query-store-repositório-de-consultas)
> - 📍 [5. Query Performance Insight (Azure SQL Database)](#query-performance-insight-azure-sql-database)
> - 📍 [6. Forçando Planos e Guias de Planos (Plan Guides)](#forçando-planos-e-guias-de-planos-plan-guides)
>   - 🔹 [sp_query_store_force_plan](#sp-query-store-force-plan)
>   - 🔹 [Guias de Planos (Plan Guides)](#guias-de-planos-plan-guides)
> - 📍 [7. Mitigação de Parameter Sniffing (Snifagem de Parâmetros)](#mitigação-de-parameter-sniffing-snifagem-de-parâmetros)
>   - 🔹 [OPTION(RECOMPILE)](#optionrecompile)
>   - 🔹 [OPTION(OPTIMIZE FOR UNKNOWN)](#optionoptimize-for-unknown)
>   - 🔹 [Variável de Escopo Local](#variável-de-escopo-local)
> - 📍 [8. Manutenção de Estatísticas do Banco](#manutenção-de-estatísticas-do-banco)
>   - 🔹 [Limiares de Atualização Automática (Auto-Update Stats)](#limiares-de-atualização-automática-auto-update-stats)
> - 📍 [9. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [10. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [11. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [12. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [13. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [14. Documentação Oficial](#documentação-oficial)

---

# Solução de Problemas de Desempenho de Queries (Query Performance Troubleshooting)

## Visão Geral (Overview)

O SQL Server oferece múltiplas ferramentas para diagnosticar gargalos e comportamentos de queries lentas: planos de execução (físicos, estimados e reais), Views de Gerenciamento Dinâmico (DMVs), histórico persistente de execução através do Query Store e interfaces gráficas como o Query Performance Insight no Azure SQL.

> [!abstract]
>
> - Cobre a análise e leitura de operadores em planos de execução, uso avançado do Query Store, diagnóstico através de DMVs e tuning de índices.
> - A resolução de problemas de performance de consultas deve seguir um fluxo metódico: Identificar → Diagnosticar → Corrigir → Verificar.
> - Tópicos chave do exame: interfaces do Query Store e sp_query_store_force_plan, DMVs de performance, index seeks vs scans e isolamento de blocking.

> [!tip] O que o Exame Testa
>
> - **Query Store**: `sys.query_store_query`, `sys.query_store_plan`, `sys.query_store_runtime_stats`; forçar planos via `sp_query_store_force_plan` (os planos forçados persistem a reinicializações).
> - **Index Seek vs Scan**: *Seek* = Otimizador busca diretamente os ponteiros das linhas desejadas no índice (eficiente); *Scan* = Otimizador varre o índice inteiro da primeira à última página (lento em tabelas grandes).
> - Bloqueios (Blocking): Rastreamento via `sys.dm_exec_requests` (coluna blocked_by) e `sys.dm_os_waiting_tasks` ( wait_type, blocking_session_id).

---

## Planos de Execução (Execution Plans)

### Habilitando Planos de Execução via T-SQL

```sql
-- Plano Estimado (Estimated Plan - não executa a query física)
SET SHOWPLAN_XML ON;
GO
SELECT * FROM dbo.Orders WHERE CustomerId = 42;
GO
SET SHOWPLAN_XML OFF;

-- Plano Real (Actual Plan - executa a query física no banco)
SET STATISTICS XML ON;
GO
SELECT * FROM dbo.Orders WHERE CustomerId = 42;
GO
SET STATISTICS XML OFF;

-- No SSMS / Azure Data Studio: Ctrl+M ativa a exibição do Plano Real de forma gráfica.
```

### Operadores de Plano de Execução Comuns

| Operador | Significado Físico | O que monitorar |
| :--- | :--- | :--- |
| **Index Seek** | Busca pontual e seletiva no índice. | Excelente sinal de query otimizada. |
| **Index Scan** | Varredura completa do índice. | Revisar se a tabela for grande. |
| **Table Scan** | Varredura completa de Heap (tabela sem Clustered Index). | Adicione um Clustered Index à tabela. |
| **Key Lookup** | Busca de colunas extras no Clustered Index. | `Adicione as colunas faltantes no INCLUDE do índice não-clusterizado`. |
| **Hash Match** | Junção ou agrupamento de grande volume em memória hash. | Normal em Data Warehouses; perigoso sob baixa RAM. |
| **Nested Loops** | Junção iterativa linha por linha. | Muito eficiente se a entrada externa for pequena. |
| **Merge Join** | Junção de duas entradas ordenadas. | Excelente eficiência; requer ordenação física prévia. |
| **Sort** | Ordenação física de dados em memória. | Operação cara; avalie se um índice estruturado evita o SORT. |
| **Spill to TempDB** | Vazamento de dados temporários para o disco. | Ocorre quando a RAM do Memory Grant concedido é insuficiente. |

> [!important] Cuidado na Prova: O que indica um Key Lookup?
>
> - Um **Key Lookup** ocorre quando o otimizador localiza a linha desejada em um índice não-clusterizado (Seek), mas precisa buscar colunas adicionais que não estão cobertas por esse índice no índice clusterizado (Tabela base).
> - **Resolução Clássica**: Adicione as colunas faltantes apontadas no Key Lookup na cláusula `INCLUDE` do índice não-clusterizado correspondente (Covering Index), eliminando o Key Lookup.

### Analisando Percentuais de Custo no Plano

```sql
-- Os percentuais de custo nos nós gráficos indicam onde a query consome mais recursos:
-- 1. Table scans em tabelas gigantes = Faltam índices adequados.
-- 2. Key lookups frequentes = Falta criar um Covering Index com INCLUDE.
-- 3. Operadores de SORT pesados = Índices ordenados de forma contrária.
-- 4. Hash Match indicando alertas de spills = Estatísticas do otimizador desatualizadas.
```

---

## Diagnóstico usando Views de Gerenciamento Dinâmico (DMVs)

### Identificando Queries com Maior Consumo

```sql
-- Listar as 10 queries com maior consumo total de CPU (Worker Time)
SELECT TOP 10
    total_worker_time / execution_count AS avg_cpu_us,
    total_worker_time AS total_cpu_us,
    execution_count,
    total_elapsed_time / execution_count AS avg_duration_us,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
         ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY avg_cpu_us DESC;

-- Listar queries com maior número de leituras lógicas em memória (Logical Reads)
SELECT TOP 10
    total_logical_reads / execution_count AS avg_reads,
    total_logical_reads,
    execution_count,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 200) AS query_snippet
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY avg_reads DESC;
```

### Consultando Recomendações de Índices Ausentes

```sql
-- Identificar índices recomendados pelo otimizador baseados em buscas reais
SELECT TOP 10
    ROUND(s.avg_total_user_cost * s.avg_user_impact * (s.user_seeks + s.user_scans), 0) AS ImpactScore,
    d.equality_columns,
    d.inequality_columns,
    d.included_columns,
    OBJECT_NAME(d.object_id) AS TableName
FROM sys.dm_db_missing_index_details d
JOIN sys.dm_db_missing_index_groups g ON g.index_handle = d.index_handle
JOIN sys.dm_db_missing_index_group_stats s ON s.group_handle = g.index_group_handle
WHERE d.database_id = DB_ID()
ORDER BY ImpactScore DESC;
```

### Consultando Estatísticas de Espera Globais (Wait Stats)

```sql
-- Listar os maiores tipos de esperas ativas no servidor SQL (Excluindo filtros ociosos)
SELECT TOP 10
    wait_type,
    wait_time_ms / 1000.0 AS wait_time_sec,
    100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS pct
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN ('SLEEP_TASK','BROKER_TO_FLUSH','CLR_AUTO_EVENT',
    'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
    'HADR_WORK_QUEUE','ONDEMAND_TASK_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH',
    'RESOURCE_QUEUE','SERVER_IDLE_CHECK','SLEEP_DBSTARTUP',
    'SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY','SLEEP_MASTERMDREADY',
    'SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP','SLEEP_TEMPDBSTARTUP',
    'SNI_HTTP_ACCEPT','SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'WAITFOR','XE_DISPATCHER_WAIT','XE_TIMER_EVENT')
ORDER BY wait_time_ms DESC;
```

---

## Query Store (Repositório de Consultas)

O Query Store grava e retém estatísticas de execução persistentes de queries e seus planos físicos de forma estruturada.

```sql
-- Ativar e parametrizar o Query Store no banco
ALTER DATABASE MyDB SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,
    MAX_STORAGE_SIZE_MB = 1000,
    INTERVAL_LENGTH_MINUTES = 60,
    SIZE_BASED_CLEANUP_MODE = AUTO,
    DATA_FLUSH_INTERVAL_SECONDS = 900
);

-- Localizar queries com regressão de planos (Queries com piora de performance recente)
SELECT TOP 10
    qsq.query_id,
    qsqt.query_sql_text,
    qsp.plan_id,
    qsrs.avg_cpu_time / 1000.0 AS avg_cpu_ms,
    qsrs.avg_duration / 1000.0 AS avg_duration_ms,
    qsrs.count_executions
FROM sys.query_store_query qsq
JOIN sys.query_store_query_text qsqt ON qsqt.query_text_id = qsq.query_text_id
JOIN sys.query_store_plan qsp ON qsp.query_id = qsq.query_id
JOIN sys.query_store_runtime_stats qsrs ON qsrs.plan_id = qsp.plan_id
ORDER BY qsrs.avg_cpu_time DESC;

-- Forçar o motor SQL a usar um plano de execução bom conhecido (plan_id = 3)
EXEC sp_query_store_force_plan @query_id = 1, @plan_id = 3;

-- Desfazer a instrução de forçar o plano
EXEC sp_query_store_unforce_plan @query_id = 1, @plan_id = 3;
```

> [!warning] Erro Comum
> O cache de planos padrão do servidor (`sys.dm_exec_cached_plans`) é volátil e se limpa em reinicializações e sob pressão de memória. O Query Store armazena dados persistidos de planos físicos em disco. Se a questão de exame exigir histórico de performance sobrevivendo a restarts, utilize o Query Store.

---

## Query Performance Insight (Azure SQL Database)

O portal do Azure fornece um dashboard amigável com gráficos consolidados dos dados retidos pelo Query Store:

```text
Azure Portal → Azure SQL Database → Intelligent Performance → Query Performance Insight
→ Filtros de Visualização: Top CPU / Top Data IO / Top Log IO
→ Clique em queries específicas para listar os planos de execução físicos e recomendações
```

---

## Forçando Planos e Guias de Planos (Plan Guides)

### sp_query_store_force_plan

Esta procedure força o uso de um plano específico em tempo de execução. O plano forçado persiste no banco de dados mesmo após reinicializações. O status de planos forçados pode ser monitorado na coluna `is_forced_plan` da tabela `sys.query_store_plan`.

### Guias de Planos (Plan Guides)

Os **Plan Guides** permitem anexar dicas de otimização (query hints) a queries específicas sem a necessidade de modificar fisicamente a string SQL de código das aplicações. Útil para queries geradas dinamicamente por ferramentas de ORM (como Entity Framework ou Hibernate), sistemas legados ou softwares terceiros.

```sql
-- Criar um Plan Guide associando Hints a uma query externa de aplicação
EXEC sp_create_plan_guide
    @name = N'PG_GetOrders',
    @stmt = N'SELECT * FROM Orders WHERE CustomerID = @CustID',
    @type = N'SQL',
    @module_or_batch = NULL,
    @params = N'@CustID int',
    @hints = N'OPTION (OPTIMIZE FOR (@CustID UNKNOWN))';

-- Verificar as guias de planos registradas no banco
SELECT name, scope_type_desc, is_disabled
FROM sys.plan_guides
WHERE name = N'PG_GetOrders';

-- Remover uma guia de planos cadastrada
EXEC sp_control_plan_guide N'DROP', N'PG_GetOrders';
```

> [!warning] Dica de Exame: Sensibilidade de Texto no Plan Guide
>
> - As correspondências de texto para Plan Guides são extremamente rígidas. O SQL Server diferencia letras maiúsculas/minúsculas, quebras de linhas e espaços em branco.
> - Se o texto passado no Plan Guide não for **exatamente igual** (caractere por caractere) à query enviada pela aplicação (ex: um ORM), o Plan Guide será sumariamente ignorado. Utilize a função `sys.fn_validate_plan_guide` para verificar e debugar.

Tipos de Plan Guides:

| Tipo | Casos de Uso |
| :--- | :--- |
| `SQL` | Instruções ad-hoc parametrizadas livres. |
| `OBJECT` | Queries internas embutidas em stored procedures ou triggers. |
| `TEMPLATE` | `Queries parametrizadas de forma automática pelo banco (esquema template)`. |

---

## Mitigação de Parameter Sniffing (Snifagem de Parâmetros)

O **parameter sniffing** ocorre quando o SQL Server compila uma stored procedure gerando um plano otimizado especificamente para os parâmetros recebidos na primeira chamada, salvando esse plano em cache. Se as próximas execuções utilizarem parâmetros com distribuições de dados muito diferentes, o plano herdado pode performar de forma ineficiente.

### OPTION(RECOMPILE)

Força o SQL Server a gerar e compilar um plano novo de execução a cada chamada da query, baseando-se nos valores exatos atuais dos parâmetros.

```sql
CREATE PROCEDURE dbo.GetOrdersByDate
    @StartDate DATE,
    @EndDate DATE
AS
    SELECT * FROM dbo.Orders
    WHERE OrderDate BETWEEN @StartDate AND @EndDate
    OPTION (RECOMPILE); -- Plano novo gerado a cada execução
```

### OPTION(OPTIMIZE FOR UNKNOWN)

Compila um plano estável baseado nas densidades médias das estatísticas do índice, ignorando o valor específico de chamada do parâmetro na compilação física.

```sql
CREATE PROCEDURE dbo.GetCustomerOrders
    @CustomerID INT
AS
    SELECT * FROM dbo.Orders
    WHERE CustomerID = @CustomerID
    OPTION (OPTIMIZE FOR (@CustomerID UNKNOWN));
```

> [!tip] Quando Usar RECOMPILE vs OPTIMIZE FOR UNKNOWN
>
> - **`OPTION(RECOMPILE)`**: Compila um plano fresco a cada execução. Use apenas em queries com distribuições de dados extremamente desiguais (skewed) que rodam raramente. Evite em queries de alta frequência para não saturar a CPU.
> - **`OPTION(OPTIMIZE FOR UNKNOWN)`**: Compila um único plano estável baseado nas estatísticas de densidade média do índice. Evita o sniffing de parâmetros sem gerar overhead de compilação constante.

### Variável de Escopo Local

Atribuir os parâmetros a variáveis locais quebra a inteligência de sniffing do compilador (o otimizador não vê o valor das variáveis internas no momento da montagem inicial do plano), forçando o uso de estatísticas padrão médias.

```sql
CREATE PROCEDURE dbo.GetOrdersByRegion
    @RegionID INT
AS
    DECLARE @LocalRegion INT = @RegionID; -- quebra o sniffing
    SELECT * FROM dbo.Orders
    WHERE RegionID = @LocalRegion;
```

---

## Manutenção de Estatísticas do Banco

As estatísticas armazenam histogramas detalhados da distribuição dos valores das colunas e chaves de índices. O otimizador de consultas as lê para estimar a cardinalidade de linhas e escolher caminhos de buscas.

### Limiares de Atualização Automática (Auto-Update Stats)

- **Tabelas menores** (menos de 500 registros): As estatísticas são atualizadas automaticamente após ocorrerem 500 alterações na tabela.
- **Tabelas maiores**: Em compatibilidade 120 ou inferior, o limiar histórico é `500 + 20%` das linhas.
- **Compatibilidade 130 ou superior**: O SQL Server usa limiar dinâmico decrescente, `MIN(500 + 20% das linhas, SQRT(1000 * linhas))`, atualizando estatísticas de tabelas grandes com mais frequência. A trace flag 2371 é relevante apenas para cenários anteriores.

```sql
-- Consultar estado e data de última atualização de estatísticas de uma tabela
SELECT OBJECT_NAME(s.object_id) AS TableName,
       s.name AS StatName,
       sp.last_updated,
       sp.rows,
       sp.rows_sampled,
       sp.modification_counter
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECT_NAME(s.object_id) = 'Orders'
ORDER BY sp.last_updated;

-- Atualizar estatísticas de forma manual forçando escaneamento total (FULLSCAN)
UPDATE STATISTICS dbo.Orders WITH FULLSCAN;

-- Atualizar estatísticas de todo o banco de dados (Amostragem padrão)
EXEC sp_updatestats;
```

O valor de `modification_counter` indica a quantidade de alterações ocorridas na coluna principal desde a última atualização das estatísticas. Valores altos indicam estatísticas desatualizadas (stale stats).

---

## Problemas Comuns e Soluções (Common Issues)

| Sintoma | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Query lenta repentinamente após rodar bem | Regressão de plano por parameter sniffing | Use hints de `OPTIMIZE FOR UNKNOWN` ou force o plano anterior com Query Store. |
| Lentidão em junções lógicas no plano | Key Lookup apontando para a tabela base | Adicione as colunas extras no `INCLUDE` do índice não-clusterizado. |
| Estatísticas de tabela defasadas | Limiar automático de 20% de alterações não atingido | Execute rotinas manuais de `UPDATE STATISTICS WITH FULLSCAN`. |
| Falha ao validar Plan Guide criado | O texto SQL passado não possui igualdade exata | Use `sys.fn_validate_plan_guide` para debugar quebras de linhas ou caracteres. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - Um **Key Lookup** indica a necessidade de criar ou alterar o índice não-clusterizado de busca adicionando colunas extras com a cláusula **`INCLUDE`**.
> - Plan Guides exigem **igualdade literal absoluta** da query de entrada (incluindo espaços).
> - Se o exame solicitar mitigação de parameter sniffing em stored procedures que executam com frequência, prefira **`OPTION(OPTIMIZE FOR UNKNOWN)`** para evitar overhead de compilação do `OPTION(RECOMPILE)`.
> - Tabelas temporais e Ledger registram logs e históricos lógicos, enquanto estatísticas atualizadas garantem estimativas físicas de dados corretas para o otimizador.

---

## Resumo dos Conceitos (Key Takeaways)

- Planos de execução sinalizam as operações físicas que oneram a consulta (scans vs seeks).
- O Query Store é a melhor ferramenta para o monitoramento e plan forcing duradouros do banco.
- O uso de Plan Guides injeta dicas em códigos fechados gerados por ORMs.
- Resolva problemas de snifagem de parâmetros adotando hints de recompilação controlada ou otimização média de valores.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

As consultas originadas de uma ferramenta de ERP de terceiros que você não pode alterar sofrem de lentidão intermitente devido a problemas de parameter sniffing. As queries enviadas possuem texto T-SQL parametrizado fixo. Qual é a melhor abordagem para estabilizar o desempenho desse cenário sem alterar o código do aplicativo?

A. Adicionar hints de `OPTION(RECOMPILE)` na stored procedure correspondente.

B. Criar um Plan Guide no banco de dados para associar a dica `OPTIMIZE FOR UNKNOWN` ao texto exato enviado pelo ERP.

C. Desabilitar a atualização automática de estatísticas do banco de dados.

D. Forçar um plano de execução de forma manual usando comandos do Query Store.

> [!success]- Resposta
> **B — Criar um Plan Guide no banco de dados para associar a dica `OPTIMIZE FOR UNKNOWN` ao texto exato enviado pelo ERP**
>
> Quando não é possível alterar fisicamente o código gerado pelas aplicações, o recurso de **Plan Guide** permite interceptar a consulta enviada no banco de dados (desde que seja passada a string literal exata) e injetar query hints lógicos, como o `OPTIMIZE FOR UNKNOWN`. Isso resolve os desvios de parameter sniffing sem demandar mudanças de código da aplicação. A alternativa A exige alteração direta. A alternativa D força um único plano físico rígido que pode não ser ideal para todas as execuções.

---

## Tópicos Relacionados

- [01-Recomendações de Configuração do Banco de Dados](./01-database-configurations.md)
- [02-Níveis de Isolamento de Transações & Concorrência](./02-transaction-isolation-concurrency.md)
- [01-Tabelas & Índices](../01-database-objects/01-tables-indexes.md)

---

## Documentação Oficial

- [Execution Plans (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/performance/execution-plans)
- [Query Store (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- [Query Performance Insight (Azure SQL)](https://learn.microsoft.com/en-us/azure/azure-sql/database/query-performance-insight-use)
- [Plan Guides (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/performance/plan-guides)
- [Parameter Sniffing (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide#parameter-sensitivity)

---

**[← Anterior](./02-transaction-isolation-concurrency.md) | [↑ Voltar para a Seção](./performance-optimization.md)**
