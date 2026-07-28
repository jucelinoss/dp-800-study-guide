---
title: Monitoramento no Azure SQL e Fabric SQL (Monitoring Azure SQL and Fabric SQL)
type: study-material
tags:
  - dp-800
  - azure-monitor
  - application-insights
  - log-analytics
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Azure Monitor para SQL](#azure-monitor-para-sql)
>   - 🔹 [Configurações de Diagnóstico (Diagnostic Settings)](#configurações-de-diagnóstico-diagnostic-settings)
>   - 🔹 [Métricas Chave do Monitor](#métricas-chave-do-monitor)
> - 📍 [3. Workspace do Log Analytics e KQL (Kusto Query Language)](#workspace-do-log-analytics-e-kql-kusto-query-language)
>   - 🔹 [Consultando Logs de Diagnóstico](#consultando-logs-de-diagnóstico)
>   - 🔹 [Exemplos Úteis de Queries KQL para DBA](#exemplos-úteis-de-queries-kql-para-dba)
> - 📍 [4. Integração com Application Insights](#integração-com-application-insights)
>   - 🔹 [Encaminhando Eventos Customizados do Banco](#encaminhando-eventos-customizados-do-banco)
> - 📍 [5. Query Performance Insight (QPI)](#query-performance-insight-qpi)
>   - 🔹 [Habilitando o Query Store para habilitar o QPI](#habilitando-o-query-store-para-habilitar-o-qpi)
> - 📍 [6. Configuração de Regras de Alertas (Alerts)](#configuração-de-regras-de-alertas-alerts)
>   - 🔹 [Exemplo de Configuração de Alerta via CLI do Azure](#exemplo-de-configuração-de-alerta-via-cli-do-azure)
> - 📍 [7. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [8. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [9. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [10. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [11. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [12. Documentação Oficial](#documentação-oficial)

---

# Monitoramento no Azure SQL e Fabric SQL (Monitoring Azure SQL and Fabric SQL)

## Visão Geral (Overview)

O Azure Monitor é a plataforma unificada de observabilidade e telemetria para os recursos de nuvem da Microsoft. No contexto de bancos de dados SQL, o monitoramento compreende a utilização de recursos físicos (CPU, memória, disco), performance de consultas (queries), erros, bloqueios e disponibilidade de serviços. Os principais pilares são: as **Configurações de Diagnóstico (Diagnostic Settings)**, **Workspaces do Log Analytics** (consultas de logs via KQL), **Application Insights** (telemetria da aplicação) e o **Query Performance Insight** (análise gráfica de queries).

> [!abstract]
>
> - Cobre a coleta de métricas do Azure Monitor, diagnósticos baseados em DMVs, Query Store para análise de execução e alertas.
> - O monitoramento unifica métricas de infraestrutura (Azure Monitor) com diagnósticos internos da engine (DMVs e Query Store).
> - Tópicos chave do exame: aplicação de DMVs corretas, detecção de regressões pelo Query Store e regras de alertas do Azure Monitor.

> [!tip] O que o Exame Testa
>
> - A DMV `sys.dm_exec_requests` exibe sessões rodando em tempo real e bloqueios ativos; `sys.dm_os_wait_stats` mostra estatísticas de esperas acumuladas da instância.
> - O Query Store detecta automaticamente **regressões de planos de execução** e pode forçar o último plano rápido através do Automatic Tuning (`FORCE_LAST_GOOD_PLAN`).
> - Métricas do Azure Monitor (CPU, DTU e armazenamento) provêm da plataforma do Azure; estatísticas internas (DMVs e Query Store) vêm de dentro do engine de banco de dados.

---

## Azure Monitor para SQL

### Configurações de Diagnóstico (Diagnostic Settings)

As Configurações de Diagnóstico encaminham métricas e logs do Azure SQL Database para destinos como Log Analytics, Event Hubs ou Contas de Armazenamento:

```text
Azure SQL Database → Monitoramento (Monitoring) → Configurações de Diagnóstico → Adicionar Configuração
 
Categorias importantes para ativação:
|── AutomaticTuning             ← Histórico de índices criados e planos forçados pelo tuning
├── QueryStoreRuntimeStatistics ← Estatísticas de execução do Query Store
├── QueryStoreWaitStatistics    ← Estatísticas de esperas de queries do Query Store
├── Errors                      ← Registros de logs de erros do SQL Server
├── DatabaseWaitStatistics      ← Estatísticas gerais de esperas do banco
├── Timeouts                    ← Ocorrências de timeouts de queries
├── Blocks                      ← Logs de eventos de bloqueio (blocking)
└── Deadlocks                   ← Gráficos XML detalhados de deadlocks
```

> **Observação:** o Azure SQL Insights foi aposentado. Para monitoramento de baixa latência, em escala e com detalhes de consultas, a recomendação atual é o Database Watcher.

> [!important] Ativação e Roteamento de Telemetria no Azure SQL
>
> - Por padrão, o Azure SQL Database **não** envia logs detalhados de diagnóstico automaticamente para o Log Analytics.
> - **Cuidado de Exame**: Você deve configurar explicitamente as **Configurações de Diagnóstico (Diagnostic Settings)** nas propriedades do recurso no Portal do Azure e marcar as categorias desejadas (ex: `Deadlocks`, `Blocks`, `Errors`) apontando para o Workspace do Log Analytics de destino.

### Métricas Chave do Monitor

Disponíveis diretamente na aba de métricas do recurso no Azure Monitor:

| Métrica | Descrição | Limite Recomendado para Alertas |
| :--- | :--- | :--- |
| `cpu_percent` | Porcentagem de consumo de CPU do banco | > 80% de uso contínuo |
| `dtu_consumption_percent` | Consumo geral de recursos (Modelo DTU) | > 80% de uso |
| `storage_percent` | Espaço consumido frente ao limite configurado | > 85% de ocupação |
| `connection_successful` | Taxa de conexões com sucesso por segundo | Validar quedas abruptas |
| `connection_failed` | Taxa de falhas de autenticação/conexão | > 0 exige auditoria imediata |
| `deadlock` | Ocorrências de deadlocks por segundo | `Qualquer valor > 0 exige atenção` |
| `workers_percent` | Threads de execução de Workers em uso | > 80% de capacidade |
| `sessions_percent` | Quantidade de conexões ativas simultâneas | > 80% do limite de sessões |

---

## Workspace do Log Analytics e KQL (Kusto Query Language)

### Consultando Logs de Diagnóstico

Após mapear o envio dos logs de diagnóstico ao Log Analytics, utilize consultas escritas em KQL para recuperar estatísticas lógicas:

> [!tip] Diferenciando AzureDiagnostics e AzureMetrics no KQL
>
> - **`AzureDiagnostics`**: Armazena logs de eventos detalhados e disparos de exceções estruturadas (como logs de erros, queries lentas, deadlocks e timeouts).
> - **`AzureMetrics`**: Armazena métricas agregadas de telemetria contínua de recursos de infraestrutura física (como consumo de CPU%, utilização de espaço em disco e estatísticas de memória).

### Exemplos Úteis de Queries KQL para DBA

```kql
// Identificar as 20 consultas que mais consumiram CPU (QueryStoreRuntimeStatistics)
AzureDiagnostics
| where Category == "QueryStoreRuntimeStatistics"
| where ResourceType == "SERVERS/DATABASES"
| project TimeGenerated, query_id_d, avg_cpu_time_d, count_executions_d,
          avg_duration_d, DatabaseName = Resource
| top 20 by avg_cpu_time_d desc
```

```kql
// Listar eventos de Deadlocks nas últimas 24 horas
AzureDiagnostics
| where Category == "Deadlocks"
| where TimeGenerated >= ago(24h)
| project TimeGenerated, Resource, deadlock_xml_s
| order by TimeGenerated desc
```

```kql
// Monitorar falhas de conexões por hora nos últimos 7 dias
AzureMetrics
| where MetricName == "connection_failed"
| where TimeGenerated >= ago(7d)
| summarize TotalFailures = sum(Total) by bin(TimeGenerated, 1h), Resource
| render timechart
```

```kql
// Média e pico de uso de CPU do banco nas últimas 24 horas
AzureMetrics
| where MetricName == "cpu_percent"
| where TimeGenerated >= ago(24h)
| summarize AvgCPU = avg(Average), MaxCPU = max(Maximum)
    by bin(TimeGenerated, 5m), Resource
| render timechart
```

```kql
// Top 10 categorias de estatísticas de espera (Wait Stats)
AzureDiagnostics
| where Category == "DatabaseWaitStatistics"
| where TimeGenerated >= ago(1h)
| summarize TotalWaitMs = sum(delta_wait_time_ms_d) by wait_type_s
| top 10 by TotalWaitMs desc
| render barchart
```

```kql
// Identificar bloqueios prolongados ocorridos na última hora
AzureDiagnostics
| where Category == "Blocks"
| where TimeGenerated >= ago(1h)
| project TimeGenerated, Resource, duration_d, blocked_process_report_s
| order by duration_d desc
```

---

## Integração com Application Insights

O Application Insights rastreia telemetrias da aplicação do usuário, capturando as chamadas SQL externas como dependências:

```text
Application Insights → Desempenho (Performance) → Dependências → SQL
 
Exibe graficamente:
- Tempos médios de resposta de cada consulta SQL.
- Taxa de falhas de banco detectadas por exceções.
- Rastreamento fim a fim (End-to-end trace) unindo o request web à query SQL.
```

### Encaminhando Eventos Customizados do Banco

```sql
-- Encaminhe o evento a uma Azure Function ou Logic App autorizada.
-- A aplicação intermediária pode então enviar telemetria ao Application Insights.
DECLARE @body NVARCHAR(MAX) = N'{
    "name": "LongRunningQuery",
    "properties": {
        "duration_ms": 5000,
        "query_hash": "abc123",
        "database": "MyDB"
    }
}';

-- Executa chamada REST externa caso a procedure de endpoint esteja habilitada
EXEC sys.sp_invoke_external_rest_endpoint
    @url = 'https://my-monitoring-function.azurewebsites.net/api/track',
    @method = 'POST',
    @headers = '{"Content-Type":"application/json"}',
    @payload = @body;
```

> [!warning] Segurança de chamadas externas
>
> `sys.sp_invoke_external_rest_endpoint` transfere dados para fora do banco. Use apenas endpoints HTTPS autorizados, credenciais de escopo de banco ou identidade gerenciada e o princípio do menor privilégio. O endpoint direto de ingestão do Application Insights não está na lista de domínios permitidos pelo Azure SQL.

---

## Query Performance Insight (QPI)

O Query Performance Insight (QPI) no Portal do Azure fornece uma interface web simplificada alimentada por estatísticas do Query Store:

```text
Azure SQL Database → Desempenho Inteligente (Intelligent Performance) → Query Performance Insight
 
Abas Disponíveis:
├── Consultas de Execução Longa (Long Running Queries)
├── Maiores Consumidores de Recursos (Top Resource Consumers) (CPU, I/O de dados, I/O de logs)
└── Configuração Customizada (Janela temporal)
```

### Habilitando o Query Store para habilitar o QPI

```sql
-- O Query Store deve estar ativo em modo leitura e escrita (READ_WRITE)
ALTER DATABASE MyDB SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,
    MAX_STORAGE_SIZE_MB = 1000,
    INTERVAL_LENGTH_MINUTES = 60
);

-- Validar a ativação
SELECT name, is_query_store_on FROM sys.databases WHERE name = 'MyDB';
```

> [!warning] Dica de Exame: Requisitos para o Query Performance Insight (QPI)
>
> - A ferramenta **Query Performance Insight (QPI)** exibe relatórios visuais ricos sobre o consumo de recursos das queries diretamente no portal.
> - **Dependência Obrigatória**: O QPI depende de o **Query Store** estar ativado (`SET QUERY_STORE = ON`) e em modo de leitura e escrita (`OPERATION_MODE = READ_WRITE`). Caso o Query Store fique cheio ou seja desligado, o QPI deixará de exibir novos dados no gráfico.

---

## Configuração de Regras de Alertas (Alerts)

Configure alertas automáticos no Azure Monitor para notificar engenheiros antes que lentidões afetem sistemas produtivos:

```text
Azure Monitor → Alertas (Alerts) → Criar Regra de Alerta
 
Sinais de monitoramento:
├── Métrica: cpu_percent > 80% sustentada por 5 minutos
├── Métrica: deadlock > 0 (Dispara com qualquer ocorrência)
└── Consulta KQL: Categoria erros contendo gravidade severa > 0 ocorridos no minuto
```

### Exemplo de Configuração de Alerta via CLI do Azure

```bash
# Criar um alerta de alta utilização de CPU para banco Azure SQL
az monitor metrics alert create \
  --name "Alerta-CPU-Alta" \
  --resource-group myRG \
  --scopes "/subscriptions/{sub}/resourceGroups/myRG/providers/Microsoft.Sql/servers/myserver/databases/MyDB" \
  --condition "avg cpu_percent > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action-group "/subscriptions/{sub}/resourceGroups/myRG/providers/Microsoft.Insights/actionGroups/TimeDBAs" \
  --description "Disparar e-mail se o uso de CPU passar de 80% por mais de 5 minutos."
```

---

## Problemas Comuns e Soluções (Common Issues)

| Sintoma | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Ausência de dados nos logs do Log Analytics | Configurações de Diagnóstico inativas no banco | Valide e salve o roteamento das categorias do banco para o Workspace do Log Analytics. |
| Gráficos do QPI vazios no Portal do Azure | Query Store está inativo ou configurado em READ_ONLY | Execute o comando `ALTER DATABASE [db] SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE)`. |
| KQL falha ao retornar linhas de deadlocks | Falta selecionar a categoria correspondente de logs | Confirme que o filtro `where Category == "Deadlocks"` está presente na query KQL. |
| Atraso na amostragem de dados de métricas | Atraso inerente de sincronização do Azure Monitor | Métricas do Azure Monitor possuem atraso padrão de ~1 minuto; logs de diagnósticos levam até ~5 minutos. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - Para capturar e consultar logs de deadlocks e erros estruturados via KQL, as **Configurações de Diagnóstico** do banco devem ser ativadas previamente.
> - A ferramenta **Query Performance Insight (QPI)** depende de o Query Store estar em modo de gravação ativa (`READ_WRITE`).
> - A tabela **`AzureDiagnostics`** no Log Analytics abriga eventos lógicos do banco (esperas, deadlocks e bloqueios). A tabela **`AzureMetrics`** armazena estatísticas de uso físico (CPU, rede, disco).
> - O **Intelligent Insights** automatiza a descoberta de desvios, disparando detecção de anomalias sem exigir escrita de KQL manual.

---

## Resumo dos Conceitos (Key Takeaways)

- O Azure Monitor coleta dados, o Log Analytics os armazena e o KQL realiza buscas de eventos.
- Mapeie e ative diagnósticos de banco para garantir visibilidade histórica.
- QPI mapeia os picos de consumo de hardware causados por queries específicas de forma visual.
- Alertas automatizados de DTU, CPU e deadlocks resguardam o SLA de sistemas produtivos.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Você gerencia um banco de dados Azure SQL Database que está sofrendo com lentidão intermitente. Um aplicativo relata que algumas consultas falham devido a timeouts (tempo de execução esgotado). Você precisa configurar um alerta automatizado que notifique a equipe de DBA sempre que uma query sofrer timeout no banco. Como você deve proceder com essa configuração?

A. Ativar o Query Store e validar o gráfico de regressão visual do Query Performance Insight (QPI).

B. Criar uma trigger de DDL para enviar e-mails de dentro do Azure SQL Database a cada erro.

C. Configurar as Configurações de Diagnóstico no banco de dados para enviar a categoria `Timeouts` ao Log Analytics, e criar uma regra de alerta baseada em uma consulta KQL direcionada à tabela `AzureDiagnostics`.

D. Consultar periodicamente a DMV `sys.dm_os_wait_stats` via script manual executado no Scheduler do Windows.

> [!success]- Resposta
> **C — Configurar as Configurações de Diagnóstico no banco de dados para enviar a categoria `Timeouts` ao Log Analytics, e criar uma regra de alerta baseada em uma consulta KQL direcionada à tabela `AzureDiagnostics`**
>
> A melhor prática de observabilidade integrada no Azure SQL é rotear os logs de eventos nativos de banco de dados por meio de Configurações de Diagnóstico (Diagnostic Settings) para o Log Analytics. Com a categoria `Timeouts` ativa, o log correspondente é alimentado na tabela `AzureDiagnostics`, autorizando a criação de regras de alerta nativas baseadas em queries KQL de monitoramento.

---

## Tópicos Relacionados

- [01-Construtor de APIs de Dados (DAB)](./01-data-api-builder.md)
- [02-Endpoints REST e GraphQL no DAB](./02-rest-graphql-endpoints.md)
- [03-Otimização de Performance - Query Performance Troubleshooting](../06-performance-optimization/03-query-performance-troubleshooting.md)

---

## Documentação Oficial

- [Azure SQL Monitoring](https://learn.microsoft.com/en-us/azure/azure-sql/database/monitoring-overview)
- [Log Analytics with Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/metrics-diagnostic-telemetry-logging-streaming-export-configure)
- [Query Performance Insight](https://learn.microsoft.com/en-us/azure/azure-sql/database/query-performance-insight-use)
- [Intelligent Insights](https://learn.microsoft.com/en-us/azure/azure-sql/database/intelligent-insights-overview)

---

**[← Anterior](./02-rest-graphql-endpoints.md) | [↑ Voltar para a Seção](./azure-services-integration.md) | [Lab: Monitoramento](../../practice/labs/08-azure-services-integration/03-monitoring-lab.sql) | [Próximo →](./04-change-event-handling.md)**
