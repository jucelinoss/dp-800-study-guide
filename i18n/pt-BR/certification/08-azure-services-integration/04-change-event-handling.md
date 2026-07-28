---
title: Captura de Alterações e Tratamento de Eventos (Change and Event Handling)
type: study-material
tags:
  - dp-800
  - cdc
  - change-tracking
  - azure-functions
  - ces
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Captura de Dados de Alteração (Change Data Capture - CDC)](#captura-de-dados-de-alteração-change-data-capture---cdc)
>   - 🔹 [Habilitando o CDC no Banco e Tabelas](#habilitando-o-cdc-no-banco-e-tabelas)
>   - 🔹 [Consultando Histórico de Mudanças no CDC](#consultando-histórico-de-mudanças-no-cdc)
>   - 🔹 [Processamento Incremental Baseado em LSN (Watermark)](#processamento-incremental-baseado-em-lsn-watermark)
> - 📍 [3. Rastreamento de Alterações (Change Tracking - CT)](#rastreamento-de-alterações-change-tracking---ct)
>   - 🔹 [Habilitando o Change Tracking (CT)](#habilitando-o-change-tracking-ct)
>   - 🔹 [Executando Sincronizações com Change Tracking](#executando-sincronizações-com-change-tracking)
> - 📍 [4. SQL Trigger para Azure Functions](#sql-trigger-para-azure-functions)
>   - 🔹 [Implementação de Código C# (C-Sharp)](#implementação-de-código-c-c-sharp)
> - 📍 [5. Streaming de Eventos de Alteração (CES) para o Fabric](#streaming-de-eventos-de-alteração-ces-para-o-fabric)
> - 📍 [6. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [7. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [8. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [9. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [10. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [11. Documentação Oficial](#documentação-oficial)

---

# Captura de Alterações e Tratamento de Eventos (Change and Event Handling)

## Visão Geral (Overview)

Reagir a alterações de dados em tempo real é fundamental no desenvolvimento de arquiteturas orientadas a eventos. O SQL Server e o Azure SQL oferecem mecanismos nativos em diferentes níveis de complexidade: o **Change Tracking** (indica se uma linha mudou), o **Change Data Capture (CDC)** (indica os valores de dados antes e depois da mudança) e o **Change Event Streaming (CES)** no Microsoft Fabric (streaming de dados push-based). Esses recursos alimentam serviços de consumo downstream via Azure Functions (SQL triggers), Logic Apps ou pipelines de streaming de eventos.

> [!abstract]
>
> - Cobre o Change Data Capture (CDC) e o Change Tracking (CT): cenários de uso, configurações, consumo de dados e diferenças de performance.
> - CDC e CT monitoram atualizações, mas divergem na quantidade de detalhes de dados retidos e nos requisitos de infraestrutura física.
> - Tópicos chave do exame: diferenças técnicas de CDC vs CT, dependência do SQL Server Agent e casos leves com Change Tracking.

> [!tip] O que o Exame Testa
>
> - **CDC**: Grava valores de registros antes/depois da alteração; exige SQL Server Agent ativo no SQL Server e no Azure SQL Managed Instance. No Azure SQL Database, um agendador CDC gerenciado executa captura e limpeza sem SQL Agent; indicado para auditorias e pipelines de ETL.
> - **Change Tracking**: Registra apenas que uma linha sofreu modificação (chave primária da linha + tipo da operação); não precisa do Agent; indicado para sincronizações locais rápidas (cache).
> - CDC opera de forma assíncrona, inclusive no Azure SQL Database, onde a captura é executada por agendador gerenciado; CT opera de forma síncrona junto ao commit da transação.

---

## Captura de Dados de Alteração (Change Data Capture - CDC)

O CDC grava dados lógicos detalhados sobre todas as instruções de `INSERT`, `UPDATE` e `DELETE` em tabelas do sistema dedicadas.

### Habilitando o CDC no Banco e Tabelas

```sql
-- 1. Habilitar o CDC no nível de banco de dados
EXEC sys.sp_cdc_enable_db;

-- Confirmar ativação
SELECT is_cdc_enabled FROM sys.databases WHERE name = DB_NAME();

-- 2. Habilitar o CDC em uma tabela específica
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name   = N'Orders',
    @role_name     = N'cdc_reader',  -- Role do banco que pode ler; NULL = sem restrições
    @supports_net_changes = 1;       -- 1 = permite consultar mudanças líquidas (net changes)

-- Listar tabelas monitoradas por CDC
SELECT source_schema, source_name, capture_instance, has_drop_pending
FROM cdc.change_tables;
```

> [!important] Relação do CDC com o SQL Server Agent
>
> - O **Change Data Capture (CDC)** faz a varredura assíncrona do log de transações do banco de dados para capturar as modificações físicas das tabelas.
> - **Cuidado de Exame**: Em servidores físicos (on-premises) ou Azure SQL Managed Instance, o CDC exige que o serviço do **SQL Server Agent** esteja rodando continuamente para acionar os jobs de captura e limpeza. No Azure SQL Database, um agendador CDC gerenciado executa esses processos automaticamente, mas a captura continua assíncrona.

### Consultando Histórico de Mudanças no CDC

O CDC expõe funções que retornam registros filtrados por um intervalo de LSN (Log Sequence Number):

```sql
-- Descobrir o intervalo de LSNs
DECLARE @from_lsn BINARY(10) = sys.fn_cdc_get_min_lsn('dbo_Orders');
DECLARE @to_lsn   BINARY(10) = sys.fn_cdc_get_max_lsn();

-- Obter todas as alterações ocorridas (1=DELETE, 2=INSERT, 3=UPDATE_BEFORE, 4=UPDATE_AFTER)
SELECT
    sys.fn_cdc_map_lsn_to_time(__$start_lsn) AS DataModificacao,
    CASE __$operation
        WHEN 1 THEN 'DELETE'
        WHEN 2 THEN 'INSERT'
        WHEN 3 THEN 'UPDATE_BEFORE'
        WHEN 4 THEN 'UPDATE_AFTER'
    END AS TipoOperacao,
    OrderId,
    CustomerId,
    Status,
    TotalAmount
FROM cdc.fn_cdc_get_all_changes_dbo_Orders(@from_lsn, @to_lsn, 'all update old')
ORDER BY __$start_lsn;
```

```sql
-- Consultar apenas mudanças líquidas (Net Changes - estado final de linhas editadas várias vezes)
SELECT
    CASE __$operation
        WHEN 1 THEN 'DELETE'
        WHEN 5 THEN 'INSERT_OR_UPDATE'
    END AS TipoOperacao,
    OrderId,
    Status
FROM cdc.fn_cdc_get_net_changes_dbo_Orders(@from_lsn, @to_lsn, 'all');
```

### Processamento Incremental Baseado em LSN (Watermark)

```sql
-- Criar tabela de controle de Watermark LSN
CREATE TABLE dbo.CDCWatermark (
    TableName   NVARCHAR(100) PRIMARY KEY,
    LastLSN     BINARY(10)    NOT NULL
);

-- Gravar LSN mínimo inicial
INSERT INTO dbo.CDCWatermark VALUES ('dbo_Orders', sys.fn_cdc_get_min_lsn('dbo_Orders'));

-- Lógica para execução de carga incremental de ETL
DECLARE @last_lsn BINARY(10);
DECLARE @current_lsn BINARY(10) = sys.fn_cdc_get_max_lsn();

SELECT @last_lsn = LastLSN FROM dbo.CDCWatermark WHERE TableName = 'dbo_Orders';

-- Selecionar apenas alterações geradas desde a última varredura
SELECT * FROM cdc.fn_cdc_get_all_changes_dbo_Orders(@last_lsn, @current_lsn, 'all')
WHERE __$start_lsn > @last_lsn;

-- Atualizar o marcador após o processamento bem-sucedido
UPDATE dbo.CDCWatermark
SET LastLSN = @current_lsn
WHERE TableName = 'dbo_Orders';
```

---

## Rastreamento de Alterações (Change Tracking - CT)

O **Change Tracking** é uma alternativa mais leve do que o CDC. Ele grava apenas a ocorrência e a direção do comando, não armazenando histórico de valores antigos das colunas.

### Habilitando o Change Tracking (CT)

```sql
-- 1. Habilitar a nível de banco de dados
ALTER DATABASE MyDB SET CHANGE_TRACKING = ON
    (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON);

-- 2. Habilitar em tabelas específicas
ALTER TABLE dbo.Products
ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);

-- Validar status
SELECT * FROM sys.change_tracking_databases;
SELECT * FROM sys.change_tracking_tables;
```

### Executando Sincronizações com Change Tracking

```sql
-- Registrar a versão atual da transação antes de exportar dados
DECLARE @sync_version BIGINT = CHANGE_TRACKING_CURRENT_VERSION();

-- ... (Fluxo de carga inicial executada pela aplicação) ...

-- Próxima execução: obter apenas registros alterados desde a versão salva
SELECT
    ct.OrderId,
    ct.SYS_CHANGE_OPERATION,   -- I = Insert, U = Update, D = Delete
    ct.SYS_CHANGE_VERSION,
    o.Status,
    o.TotalAmount
FROM CHANGETABLE(CHANGES dbo.Orders, @sync_version) AS ct
LEFT JOIN dbo.Orders o ON o.OrderId = ct.OrderId  -- Retornará NULL se for exclusão (DELETE)
ORDER BY ct.SYS_CHANGE_VERSION;

-- Salvar o novo número da versão após o processamento
SET @sync_version = CHANGE_TRACKING_CURRENT_VERSION();
```

> [!tip] Dica para a Prova: CDC vs Change Tracking (CT)
>
> - **CDC**: Armazena os valores de dados físicos antes (`UPDATE_BEFORE`) e depois (`UPDATE_AFTER`) da modificação. Requer tabelas do sistema adicionais (`cdc.*`) e gera consumo de disco moderado/alto.
> - **Change Tracking (CT)**: Extremamente leve e síncrono. Captura apenas o identificador da chave primária (PK) alterada e a direção da ação (`I` = Insert, `U` = Update, `D` = Delete). Não guarda histórico de valores históricos anteriores.

---

## SQL Trigger para Azure Functions

O SQL Trigger binding para Azure Functions executa chamadas serverless de código sempre que registros sob uma tabela física sofrem inserções, atualizações ou exclusões.

### Implementação de Código C# (C-Sharp)

```csharp
[FunctionName("ProcessarAlteracoesPedidos")]
public static async Task Run(
    [SqlTrigger("[dbo].[Orders]", "SqlConnectionString")]
    IReadOnlyList<SqlChange<Order>> changes,
    ILogger log)
{
    foreach (SqlChange<Order> change in changes)
    {
        Order order = change.Item;
        log.LogInformation($"Operação: {change.Operation} PedidoID={order.OrderId}");

        switch (change.Operation)
        {
            case SqlChangeOperation.Insert:
                await ProcessarNovoPedido(order);
                break;
            case SqlChangeOperation.Update:
                await ProcessarAtualizacao(order);
                break;
            case SqlChangeOperation.Delete:
                await TratarExclusao(order.OrderId);
                break;
        }
    }
}
```

> [!warning] O que Viabiliza o SQL Trigger no Azure Functions?
>
> - O SQL Trigger binding no Azure Functions responde a inserções, edições ou exclusões em tabelas físicas.
> - **Ativação Oculta**: Sob o capô, a extensão de trigger depende do **Change Tracking (CT)** estar ativado na tabela monitorada. Ao ser inicializado, o runtime tenta habilitar o CT de forma automática na tabela-alvo, exigindo que as credenciais do usuário do banco possuam a role `db_owner`.

---

## Streaming de Eventos de Alteração (CES) para o Fabric

O **Change Event Streaming (CES)** é um recurso em visualização para SQL Server 2025 e Azure SQL Database. Ele transmite alterações de tabelas para Azure Event Hubs e pode entregar eventos diretamente ao endpoint personalizado de um Eventstream do Fabric.

O CES transmite eventos CloudEvents quase em tempo real, contendo:

- Nome da tabela de origem e tipo da operação (Insert/Update/Delete).
- Dados da tabela no payload do evento.
- Metadados do evento para processamento downstream.

---

## Problemas Comuns e Soluções (Common Issues)

| Sintoma | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Logs do CDC ausentes no SQL Server/MI | SQL Server Agent inativo | Inicie o serviço do Agent para reativar os jobs automáticos de captura. |
| Perda de sincronismo no Change Tracking | Versão salva de sincronismo ultrapassou a retenção configurada | Use `CHANGE_TRACKING_MIN_VALID_VERSION()` para validar. Execute carga cheia se necessário. |
| O SQL Trigger da Function falha na inicialização | A conta de conexão não possui permissão `db_owner` | Conceda direitos de `db_owner` para autorizar a Function a criar tabelas internas de rastreamento. |
| Sobrecarga severa de disco | CDC ativado em tabelas transacionais massivas | Monitore os logs do cdc e verifique se o job de limpeza (`cdc.cleanup_job`) está rodando conforme planejado. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - O **CDC** grava o histórico completo de valores modificados (antes/depois). Exige SQL Agent ativo em infraestruturas físicas/MI.
> - O **Change Tracking (CT)** é leve, síncrono e grava apenas as chaves PKs modificadas.
> - O **Azure Functions SQL Trigger** depende do Change Tracking ativado na tabela-alvo sob o capô.
> - No CT, use a função `CHANGETABLE(CHANGES...)` para buscar os dados incrementais desde a última versão sincronizada.

---

## Resumo dos Conceitos (Key Takeaways)

- O CDC provê auditoria rica de dados, ideal para pipelines incrementais de ETL.
- O Change Tracking é a ferramenta recomendada para sincronização rápida de caches.
- Use a extensão de trigger SQL no Azure Functions para arquiteturas de microsserviços orientados a eventos.
- O CES no Fabric abstrai a complexidade operacional de envio de eventos para Lakehouses na nuvem.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Você está projetando uma solução de sincronização de dados entre o Azure SQL Database e um banco de dados móvel local offline. A solução requer apenas identificar quais IDs de clientes foram criados, editados ou excluídos desde a última sincronização do dispositivo, para que os dados sejam atualizados. Você precisa adotar a abordagem de menor overhead de gravação no Azure SQL. O que você deve habilitar?

A. Change Data Capture (CDC).

B. Change Tracking (CT).

C. Auditoria do SQL Server.

D. Triggers DDL de tabelas.

> [!success]- Resposta
> **B — Change Tracking (CT)**
>
> O Change Tracking (CT) é projetado especificamente para cenários de sincronização unidirecional ou bidirecional onde a aplicação só necessita saber quais chaves primárias sofreram atualizações. Por não reter cópias históricas de valores anteriores (ao contrário do CDC, que geraria sobrecargas extras de gravação em disco e CPU), ele atende à premissa de menor overhead para o Azure SQL Database.

---

## Tópicos Relacionados

- [03-Monitoramento](./03-monitoring.md)
- [02-Níveis de Isolamento e Concorrência](../06-performance-optimization/02-transaction-isolation-concurrency.md)
- [02-Manutenção de Embeddings em AI](../09-models-embeddings/02-embedding-maintenance.md) *(Inglês apenas)*

---

## Documentação Oficial

- [CDC in SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-data-capture-sql-server)
- [Change Tracking](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-tracking-sql-server)
- [Azure Functions SQL Trigger Binding](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-azure-sql-trigger)
- [Fabric Change Event Streaming](https://learn.microsoft.com/en-us/fabric/database/sql/change-event-streaming)

---

**[← Anterior](./03-monitoring.md) | [↑ Voltar para a Seção](./azure-services-integration.md) | [Lab: Manipulação de Eventos](../../practice/labs/08-azure-services-integration/04-change-event-handling-lab.sql)**
