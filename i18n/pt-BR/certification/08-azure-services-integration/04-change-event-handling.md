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
> - 📍 [5. Streaming de Eventos de Alteração (CES) para Azure Event Hubs e Fabric](#streaming-de-eventos-de-alteração-ces-para-azure-event-hubs-e-fabric)
> - 📍 [6. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [7. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [8. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [9. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [10. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [11. Documentação Oficial](#documentação-oficial)

---

# Captura de Alterações e Tratamento de Eventos (Change and Event Handling)

## Visão Geral (Overview)

Reagir a alterações de dados em tempo real é fundamental no desenvolvimento de arquiteturas orientadas a eventos. O SQL Server e o Azure SQL oferecem mecanismos nativos em diferentes níveis de complexidade: o **Change Tracking** (indica se uma linha mudou), o **Change Data Capture (CDC)** (captura alterações em tabelas de captura) e o **Change Event Streaming (CES)** (envia eventos para Azure Event Hubs). Esses recursos alimentam serviços de consumo downstream via Azure Functions (SQL triggers), Logic Apps, Fabric Eventstream ou pipelines de streaming de eventos.

> [!abstract]
>
> - Cobre o Change Data Capture (CDC) e o Change Tracking (CT): cenários de uso, configurações, consumo de dados e diferenças de performance.
> - CDC e CT monitoram atualizações, mas divergem na quantidade de detalhes de dados retidos e nos requisitos de infraestrutura física.
> - Tópicos chave do exame: diferenças técnicas de CDC vs CT, dependência do SQL Server Agent e casos leves com Change Tracking.

> [!tip] O que o Exame Testa
>
> - **CDC**: Pode expor valores antes/depois da alteração usando `all update old`; exige SQL Server Agent ativo no SQL Server e no Azure SQL Managed Instance. No Azure SQL Database, um agendador CDC gerenciado executa captura e limpeza sem SQL Agent; indicado para auditorias e pipelines de ETL.
> - **Change Tracking**: Registra apenas que uma linha sofreu modificação (chave primária da linha + tipo da operação); não precisa do Agent; indicado para sincronizações locais rápidas (cache).
> - CDC opera de forma assíncrona, inclusive no Azure SQL Database, onde a captura é executada por agendador gerenciado; CT opera de forma síncrona junto ao commit da transação.

---

## Captura de Dados de Alteração (Change Data Capture - CDC)

O **Change Data Capture (CDC)** registra alterações detalhadas de `INSERT`,
`UPDATE` e `DELETE` realizadas nas tabelas. Ele captura os dados necessários
para saber qual linha mudou, qual operação ocorreu e quais eram os valores
antes e depois da alteração.

O CDC lê o log de transações de forma assíncrona e grava os eventos em tabelas
de captura que espelham as colunas da tabela de origem. Funções como
`cdc.fn_cdc_get_all_changes...` e `cdc.fn_cdc_get_net_changes...` permitem
consumir esse histórico.

Use CDC quando precisar de histórico ou dos valores alterados, por exemplo em
ETL incremental, data warehouses, auditoria, replicação e integração com
sistemas externos. Como ele preserva mais informações, seu consumo de
armazenamento e processamento é maior que o do Change Tracking.

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
FROM cdc.fn_cdc_get_net_changes_dbo_Orders(@from_lsn, @to_lsn, 'all with merge');
```

### Processamento Incremental Baseado em LSN (Watermark)

O **LSN (Log Sequence Number)** é um identificador sequencial usado pelo CDC
para ordenar as alterações capturadas no log de transações. O watermark é o
LSN persistido que informa até onde o pipeline já processou os dados. Assim, a
próxima execução lê somente o intervalo posterior, em vez de reler a tabela
inteira.

O fluxo é:

```text
1. Ler o último LSN processado
2. Capturar o LSN atual como limite da execução
3. Ler e processar as alterações entre os dois pontos
4. Atualizar o watermark somente após o processamento bem-sucedido
```

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

Por exemplo, se o watermark armazenar o LSN 100 e a execução encontrar
alterações até o LSN 120, ela processará o intervalo 101–120 e gravará 120
como o novo watermark. Alterações geradas depois da captura de
`@current_lsn` ficarão para a próxima execução.

O watermark só deve avançar depois que a carga no destino terminar com
sucesso. Se a execução falhar antes do `UPDATE`, a próxima tentativa relerá o
mesmo intervalo. Isso pode processar uma alteração mais de uma vez, mas evita
perda de dados; por isso, o destino deve ser idempotente ou usar uma transação
com controle de chaves/LSN.
Funções de CDC:

- `fn_cdc_get_all_changes` retorna todas as alterações do intervalo. Com
  `all update old`, um `UPDATE` aparece como imagem anterior (`3`) e imagem
  posterior (`4`).
- `fn_cdc_get_net_changes` retorna somente o estado final da linha no intervalo.
  Com `all with merge`, `__$operation = 5` significa inserção ou atualização,
  sem distinguir as duas operações. Isso reduz o volume, mas não preserva todas
  as alterações intermediárias.

---

## Rastreamento de Alterações (Change Tracking - CT)

O **Change Tracking (CT)** é uma alternativa mais leve ao CDC. Ele registra
que uma linha mudou, a operação realizada (`I`, `U` ou `D`) e a versão da
alteração, mas não armazena os valores anteriores e posteriores da linha.

Para obter os dados atuais, a aplicação consulta a tabela original usando a
chave primária retornada por `CHANGETABLE`. Se uma linha for atualizada várias
vezes, o CT não preserva todas as etapas; ele serve para descobrir quais linhas
precisam ser sincronizadas.

Use CT para sincronização entre bancos e aplicações, atualização de cache,
replicação simples e cenários em que somente o estado atual importa. Ele é
mais econômico em armazenamento e processamento, mas não substitui o CDC para
auditoria ou histórico detalhado.

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
> | Característica | CDC | CT |
> | :--- | :--- | :--- |
> | Registra `INSERT`, `UPDATE` e `DELETE` | Sim | Sim |
> | Armazena valores anteriores e novos | Sim | Não |
> | Mantém histórico intermediário | Sim | Não |
> | Identifica colunas alteradas | Sim | Sim, opcionalmente |
> | Marcador de sincronização | LSN | Versão `BIGINT` |
> | Captura | Assíncrona | Síncrona |
> | Armazenamento | Maior | Menor |
> | Uso principal | Auditoria, ETL e histórico | Sincronização e cache |
>
> Regra prática: use **CDC** quando precisar saber o que mudou e quais eram os valores; use **CT** quando precisar apenas descobrir quais linhas devem ser sincronizadas. CDC e CT podem ser habilitados simultaneamente no mesmo banco.

### Escolha por volumetria e cenário

As faixas abaixo são **orientativas para planejamento**, não limites impostos
pelo SQL Server. A decisão real também depende do tamanho das linhas, da taxa
de alterações por minuto, da latência desejada, do período de retenção e da
capacidade do consumidor.

| Cenário aproximado | Mecanismo recomendado | Motivo |
| :--- | :--- | :--- |
| Até 10 mil alterações por execução, sincronização periódica e necessidade apenas do estado atual | CT | Menor armazenamento e custo operacional; a aplicação busca as linhas atuais pela chave primária. |
| De 10 mil a 1 milhão de alterações por execução, com ETL ou necessidade de histórico | CDC | Permite ler o intervalo por LSN e preservar operações e valores antes/depois. |
| Mais de 1 milhão de alterações por execução ou alto volume diário | CDC com processamento em lotes, watermark e, quando apropriado, `net changes` | Reduz a carga sobre a origem e permite controlar o backlog; avalie particionamento, retenção e consumo paralelo. |
| Sincronização de cache, aplicativo móvel ou réplica que precisa apenas saber quais linhas recarregar | CT | O consumidor obtém a chave alterada e consulta o estado atual, sem armazenar todo o histórico. |
| Auditoria, conformidade, reconstrução de eventos ou integração que precisa de `before`/`after` | CDC | O histórico detalhado é necessário; CT não consegue recuperar valores intermediários. |
| Baixa latência e grande fluxo contínuo de eventos | CDC ou CES, conforme a plataforma | CDC atende processamento baseado em polling/LSN; CES é mais adequado quando o cenário exige streaming de eventos. |

#### Cuidados em volumes altos

- No **CDC**, monitore o atraso entre o LSN produzido e o LSN consumido, o tamanho das tabelas de captura e a retenção do histórico.
- No **CT**, configure a retenção para ser maior que o pior intervalo esperado entre sincronizações. Se o consumidor ficar atrás do período de retenção, será necessário executar uma carga completa novamente.
- Para ambos, processe em lotes, persista o watermark somente após sucesso e torne o destino idempotente para suportar reprocessamentos.
- Se o requisito for apenas o estado final, `fn_cdc_get_net_changes` pode reduzir o volume de dados; se cada evento intermediário for importante, use `fn_cdc_get_all_changes`.

---

## SQL Trigger para Azure Functions

O SQL Trigger binding para Azure Functions executa chamadas serverless de código sempre que registros sob uma tabela física sofrem inserções, atualizações ou exclusões.

### Implementação de Código C# (C-Sharp)

```csharp
[Function("ProcessarAlteracoesPedidos")]
public static async Task Run(
    [SqlTrigger("[dbo].[Orders]", "SqlConnectionString")]
    IReadOnlyList<SqlChange<Order>> changes,
    FunctionContext context)
{
    ILogger log = context.GetLogger("ProcessarAlteracoesPedidos");
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
> - A extensão depende do **Change Tracking (CT)** estar habilitado no banco e na tabela monitorada. O trigger também cria tabelas internas de estado no schema `az_func`.
> - `db_owner` é uma forma ampla de conceder acesso, mas não é obrigatório. Em produção, prefira as permissões mínimas documentadas: `CREATE TABLE`, `CREATE SCHEMA`, `SELECT`, `VIEW CHANGE TRACKING` e permissões no schema `az_func`.
> - O exemplo de C# deve preferir o modelo **isolated worker** em novos projetos; o modelo in-process entra em fim de suporte em 10 de novembro de 2026.

---

## Streaming de Eventos de Alteração (CES) para Azure Event Hubs e Fabric

O **Change Event Streaming (CES)** é um recurso em visualização para SQL Server 2025, Azure SQL Database e Azure SQL Managed Instance. Ele transmite alterações de tabelas para o **Azure Event Hubs** usando AMQP ou Kafka. Um Eventstream do Microsoft Fabric pode consumir esses eventos por meio do Event Hubs.

O CES transmite eventos CloudEvents quase em tempo real, contendo:

- Nome da tabela de origem e tipo da operação (Insert/Update/Delete).
- Dados atuais e, conforme o tipo de evento, dados anteriores da linha.
- Metadados como LSN de commit e timestamp.
- Serialização em JSON ou Avro.

Para usar CES, é necessário habilitar o recurso no banco, criar um grupo de
streaming, configurar o Event Hubs, as credenciais e as tabelas monitoradas.
CES não faz snapshot inicial: somente alterações ocorridas depois da ativação
são transmitidas. No SQL Server 2025, o banco precisa usar recovery model
`FULL` e a configuração de preview correspondente.

CES não pode ser habilitado em um banco que já usa CDC. Para dados históricos
anteriores à ativação, faça uma carga inicial separada e use CES apenas para as
alterações posteriores.

---

## Problemas Comuns e Soluções (Common Issues)

| Sintoma | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Logs do CDC ausentes no SQL Server/MI | SQL Server Agent inativo | Inicie o serviço do Agent para reativar os jobs automáticos de captura. |
| Perda de sincronismo no Change Tracking | Versão salva de sincronismo ultrapassou a retenção configurada | Use `CHANGE_TRACKING_MIN_VALID_VERSION()` para validar. Execute carga cheia se necessário. |
| O SQL Trigger da Function falha na inicialização | CT desabilitado ou permissões insuficientes no schema `az_func` | Habilite CT no banco e na tabela e conceda as permissões mínimas documentadas. |
| Sobrecarga severa de disco | CDC ativado em tabelas transacionais massivas | Monitore as tabelas de captura e verifique se o job `cdc.<nome_do_banco>_cleanup` está rodando conforme planejado. |
| SQL Trigger não inicia | CT desabilitado ou permissões insuficientes no schema `az_func` | Habilite CT no banco e na tabela e conceda as permissões mínimas documentadas. |
| CES indisponível | Plataforma, configuração ou destino incompatível | Confirme SQL Server 2025/Azure SQL Database/Azure SQL Managed Instance, Azure Event Hubs, recovery model e limitações do preview. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - O **CDC** grava alterações em tabelas de captura; use `all update old` quando precisar da imagem anterior e posterior. Exige SQL Agent ativo em infraestruturas físicas/MI.
> - O **Change Tracking (CT)** é leve, síncrono e grava apenas as chaves PKs modificadas.
> - O **Azure Functions SQL Trigger** depende do Change Tracking ativado na tabela-alvo sob o capô.
> - No CT, use a função `CHANGETABLE(CHANGES...)` para buscar os dados incrementais desde a última versão sincronizada.

---

## Resumo dos Conceitos (Key Takeaways)

- O CDC provê auditoria rica de dados, ideal para pipelines incrementais de ETL.
- O Change Tracking é a ferramenta recomendada para sincronização rápida de caches.
- Use a extensão de trigger SQL no Azure Functions para arquiteturas de microsserviços orientados a eventos.
- O CES envia eventos para Azure Event Hubs; o Fabric Eventstream pode encaminhá-los para Lakehouse, KQL Database ou outros destinos.

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
- [Change Event Streaming (CES)](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/change-event-streaming/overview)
- [Enviar eventos SQL para o Fabric Eventstream](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/stream-sql-change-events-to-eventstream)

---

**[← Anterior](./03-monitoring.md) | [↑ Voltar para a Seção](./azure-services-integration.md) | [Lab: Manipulação de Eventos](../../practice/labs/08-azure-services-integration/04-change-event-handling-lab.sql)**
