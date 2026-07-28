---
title: Auditoria de Banco de Dados (Database Auditing)
type: study-material
tags:
  - dp-800
  - auditing
  - sql-audit
  - azure-sql-audit
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Arquitetura do SQL Server Audit](#arquitetura-do-sql-server-audit)
>   - 🔹 [Comportamento da Fila de Auditoria (Audit Queue)](#comportamento-da-fila-de-auditoria-audit-queue)
> - 📍 [3. SQL Server Audit (On-Premises e Azure SQL Managed Instance)](#sql-server-audit-on-premises-e-azure-sql-managed-instance)
>   - 🔹 [Criando um Server Audit](#criando-um-server-audit)
>   - 🔹 [Criando a Database Audit Specification](#criando-a-database-audit-specification)
>   - 🔹 [Criando a Server Audit Specification](#criando-a-server-audit-specification)
>   - 🔹 [Lendo Arquivos de Logs de Auditoria](#lendo-arquivos-de-logs-de-auditoria)
> - 📍 [4. Auditoria no Azure SQL Database](#auditoria-no-azure-sql-database)
>   - 🔹 [Habilitando via Portal do Azure](#habilitando-via-portal-do-azure)
>   - 🔹 [Habilitando via PowerShell](#habilitando-via-powershell)
> - 📍 [5. Principais Grupos de Ações de Auditoria (Audit Action Groups)](#principais-grupos-de-ações-de-auditoria-audit-action-groups)
> - 📍 [6. Consultando Logs de Auditoria](#consultando-logs-de-auditoria)
>   - 🔹 [Lendo Arquivos de Staging com fn_get_audit_file](#lendo-arquivos-de-staging-com-fn-get-audit-file)
>   - 🔹 [Consultando Logs via KQL no Log Analytics](#consultando-logs-via-kql-no-log-analytics)
> - 📍 [7. Tabelas Temporais como Trilhas de Auditoria (Temporal Tables)](#tabelas-temporais-como-trilhas-de-auditoria-temporal-tables)
> - 📍 [8. Melhores Práticas de Auditoria](#melhores-práticas-de-auditoria)
> - 📍 [9. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [10. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [11. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [12. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [13. Documentação Oficial](#documentação-oficial)

---

# Auditoria de Banco de Dados (Database Auditing)

## Visão Geral (Overview)

A auditoria do SQL Server (SQL Server Audit) captura eventos de atividades executadas nas bases e grava as informações em arquivos físicos, Logs de Eventos do Windows (Application ou Security Event Logs) ou no Azure Monitor (Log Analytics e Event Hubs). O Azure SQL Database dispõe de recursos gerenciados adicionais para auditorias simplificadas de nuvem.

> [!abstract]
>
> - Cobre a arquitetura do SQL Server Audit nos níveis de servidor e banco de dados, grupos de ações de auditoria e destinos de saída dos logs.
> - Auditorias documentam quem executou determinada ação, o que foi alterado e quando ocorreu — essencial para atender a conformidades regulatórias.
> - Tópicos chave do exame: distinção de escopos (server-level vs database-level), destinos de gravação e consulta aos logs de auditoria.

> [!tip] O que o Exame Testa
>
> - Hierarquia de auditoria: criar `SERVER AUDIT` (define o destino das gravações) → criar `DATABASE AUDIT SPECIFICATION` (define quais ações capturar no banco).
> - Destinos de logs no Azure SQL: **Storage Account** (Blob Storage), workspace do **Log Analytics** e **Event Hub** — todos os três são opções de nuvem válidas.
> - Consulta de logs baseados em arquivos via função de sistema **`sys.fn_get_audit_file()`** ou consultas KQL no Log Analytics.

---

## Arquitetura do SQL Server Audit

O recurso é composto fisicamente por dois blocos estruturais:

- **Server Audit**: Define ONDE as gravações de log serão salvas (caminho de arquivo, Application Event Log, Security Event Log).
- **Audit Specification**: Define O QUE capturar; divide-se em:
  - **Server Audit Specification**: Eventos de escopo de servidor (logins, alterações de papéis administrativos, comandos DDL no master).
  - **Database Audit Specification**: Eventos de escopo de banco de dados (comandos DML, SELECTs, DDL de tabelas, concessões de permissão).

### Comportamento da Fila de Auditoria (Audit Queue)

| Modo | Ação quando a fila de gravação enche |
| :--- | :--- |
| Síncrono (`QUEUE_DELAY = 0`) | `Bloqueia ativamente a sessão de usuário até que o log seja persistido no disco`. |
| Assíncrono (`QUEUE_DELAY > 0`) | Descarta logs excedentes se a fila de memória saturar; o comportamento final é regido pela flag `ON_FAILURE`. |

`ON_FAILURE = CONTINUE` — A transação do usuário continua executando mesmo se a gravação do log de auditoria falhar (prioriza disponibilidade).
`ON_FAILURE = SHUTDOWN` — Desliga imediatamente a instância do SQL Server caso o log de auditoria não possa ser persistido (prioriza segurança absoluta).

> [!important] Cuidado na Prova: ON_FAILURE e Segurança Rígida
>
> - **ON_FAILURE = SHUTDOWN**: Se o disco de logs de auditoria encher ou o sistema de gravação falhar, a instância do SQL Server é **encerrada (derrubada) imediatamente** para evitar que novas transações ocorram sem registro.
> - Utilize essa opção apenas em cenários regulatórios extremos (como PCI-DSS). Para a maioria dos ambientes comuns, `ON_FAILURE = CONTINUE` é preferido para manter a alta disponibilidade.

```sql
-- Criar o Server Audit apontando para uma pasta no Windows
CREATE SERVER AUDIT DataAudit
TO FILE (FILEPATH = 'C:\AuditLogs\', MAXSIZE = 100 MB)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);

ALTER SERVER AUDIT DataAudit WITH (STATE = ON);

-- Criar a Database Audit Specification associada
CREATE DATABASE AUDIT SPECIFICATION DataAuditSpec
FOR SERVER AUDIT DataAudit
    ADD (SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo BY PUBLIC),
    ADD (EXECUTE ON SCHEMA::dbo BY PUBLIC)
WITH (STATE = ON);
```

---

## SQL Server Audit (On-Premises e Azure SQL Managed Instance)

### Criando um Server Audit

```sql
-- Criar auditoria no nível do servidor com limite físico de arquivos
CREATE SERVER AUDIT MyServerAudit
TO FILE (FILEPATH = 'C:\Audit\',
         MAXSIZE = 100 MB,
         MAX_ROLLOVER_FILES = 5,
         RESERVE_DISK_SPACE = OFF)
WITH (QUEUE_DELAY = 1000,        -- tempo em ms antes de descarregar a fila
      ON_FAILURE = CONTINUE);    -- CONTINUE ou SHUTDOWN
GO

ALTER SERVER AUDIT MyServerAudit WITH (STATE = ON);
```

### Criando a Database Audit Specification

```sql
-- Auditar acessos específicos em tabelas e procedures
CREATE DATABASE AUDIT SPECIFICATION MyDBSpec
FOR SERVER AUDIT MyServerAudit
    ADD (SELECT ON dbo.Customers BY PUBLIC),
    ADD (INSERT, UPDATE, DELETE ON dbo.Orders BY PUBLIC),
    ADD (EXECUTE ON dbo.usp_TransferFunds BY PUBLIC),
    ADD (SCHEMA_OBJECT_ACCESS_GROUP) -- audita qualquer alteração estrutural
WITH (STATE = ON);
```

### Criando a Server Audit Specification

```sql
-- Auditar eventos globais do servidor (como logins)
CREATE SERVER AUDIT SPECIFICATION MyServerSpec
FOR SERVER AUDIT MyServerAudit
    ADD (FAILED_LOGIN_GROUP),
    ADD (SUCCESSFUL_LOGIN_GROUP),
    ADD (SERVER_PERMISSION_CHANGE_GROUP),
    ADD (DATABASE_CHANGE_GROUP)
WITH (STATE = ON);
```

### Lendo Arquivos de Logs de Auditoria

```sql
-- Consultar o conteúdo do arquivo físico .sqlaudit
SELECT
    event_time,
    action_id,
    succeeded,
    session_server_principal_name AS LoginName,
    object_name,
    statement
FROM sys.fn_get_audit_file('C:\Audit\MyServerAudit_*.sqlaudit', DEFAULT, DEFAULT)
ORDER BY event_time DESC;
```

---

## Auditoria no Azure SQL Database

A auditoria no Azure SQL Database opera com diferenças fundamentais frente ao SQL Server local:

- Não suporta caminhos de arquivos físicos (paths) — grava em **Azure Blob Storage**, **Log Analytics** ou **Event Hub**.
- Habilitada via Portal do Azure, scripts PowerShell (`Set-AzSqlDatabaseAudit`) ou DDL de políticas.
- Período de retenção de logs configurável (onde 0 indica retenção eterna).
- Integração com o **Microsoft Defender for SQL** para monitoramento inteligente de ameaças e detecção de anomalias.
- Auditorias a nível de servidor lógico no Azure SQL cobrem automaticamente qualquer base existente ou futura criada sob ele.

> [!tip] Destinos dos Logs no Azure SQL Database
>
> - Ao contrário do SQL Server local (que grava em caminhos físicos do Windows `.sqlaudit`), o Azure SQL Database aceita três destinos gerenciados: **Azure Blob Storage**, **Log Analytics** (para consultas via KQL) e **Azure Event Hub** (para transmissão a sistemas SIEM externos como Microsoft Sentinel).

### Habilitando via Portal do Azure

```text
Azure Portal → Azure SQL Database → Security → Auditing
→ Alternar "Enable Azure SQL Auditing" para ON
→ Escolher destino: Storage account / Log Analytics / Event Hub
→ Definir dias de retenção
```

### Habilitando via PowerShell

```powershell
# Ativar logs de auditoria enviando para o Log Analytics
Set-AzSqlDatabaseAudit `
    -ResourceGroupName "myRG" `
    -ServerName "myserver" `
    -DatabaseName "mydb" `
    -AuditActionGroup "SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP","FAILED_DATABASE_AUTHENTICATION_GROUP","BATCH_COMPLETED_GROUP" `
    -WorkspaceResourceId "/subscriptions/.../workspaces/myworkspace" `
    -LogAnalyticsTargetState Enabled
```

---

## Principais Grupos de Ações de Auditoria (Audit Action Groups)

Grupos essenciais mapeados no exame DP-800:

| Grupo de Ação | O que é Capturado |
| :--- | :--- |
| `BATCH_COMPLETED_GROUP` | `Qualquer lote T-SQL concluído (inclui o texto completo do SQL executado, inclusive SELECTs)`. |
| `DATABASE_OBJECT_ACCESS_GROUP` | Acesso direto a objetos de banco de dados (tabelas e views). |
| `DATABASE_OBJECT_PERMISSION_CHANGE_GROUP` | Alterações de permissões em objetos do banco. |
| `DATABASE_ROLE_MEMBER_CHANGE_GROUP` | Modificações em membros das roles de segurança. |
| `FAILED_DATABASE_AUTHENTICATION_GROUP` | Tentativas de login sem sucesso na base de dados. |
| `SCHEMA_OBJECT_ACCESS_GROUP` | Qualquer consulta ou alteração física em objetos do schema. |
| `USER_DEFINED_AUDIT_GROUP` | Disparos de logs manuais do desenvolvedor via `sp_audit_write`. |
| `SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP` | Logins efetuados com sucesso. |

---

## Consultando Logs de Auditoria

### Lendo Arquivos de Staging com fn_get_audit_file

```sql
-- Buscar atividades lidas na tabela Salaries
SELECT event_time, action_id, server_principal_name,
       database_name, object_name, statement
FROM sys.fn_get_audit_file('C:\AuditLogs\*.sqlaudit', DEFAULT, DEFAULT)
WHERE object_name = 'Salaries'
ORDER BY event_time DESC;

-- Rastrear acessos a dados efetuados por um usuário suspeito
SELECT event_time, action_id, object_name, statement
FROM sys.fn_get_audit_file('C:\AuditLogs\*.sqlaudit', DEFAULT, DEFAULT)
WHERE server_principal_name = 'DOMAIN\suspicious_user'
  AND action_id IN ('SL', 'IN', 'UP', 'DL') -- SL (SELECT), IN (INSERT), UP (UPDATE), DL (DELETE)
ORDER BY event_time;
```

> [!warning] Erro Comum
> Logs de auditoria não são consultados via views dinâmicas comuns (DMVs) como `sys.dm_exec_sessions`. Em bases baseadas em arquivos físicos, utilize exclusivamente a função de sistema **`sys.fn_get_audit_file`**. Questões de exame costumam sugerir DMVs incorretas como distração.

### Consultando Logs via KQL no Log Analytics

```kusto
// Query Kusto no Log Analytics para buscar falhas de SELECT
AzureDiagnostics
| where Category == "SQLSecurityAuditEvents"
| where database_name_s == "mydb"
| where action_name_s == "SELECT"
| where succeeded_s == "false"
| project TimeGenerated, client_ip_s, server_principal_name_s, statement_s
| order by TimeGenerated desc
```

---

## Tabelas Temporais como Trilhas de Auditoria (Temporal Tables)

As tabelas temporais (tabelas com versionamento do sistema) capturam alterações físicas nos dados gerando históricos consistentes.

Diferenças cruciais frente ao SQL Audit clássico:

- Tabelas temporais rastreiam **alterações de dados** (`INSERT`, `UPDATE`, `DELETE`) — não gravam acessos ou comandos `SELECT`.
- Elas registram **o que o dado era**, mas não salvam a identidade (login/usuário) de quem executou o comando.
- Use a sintaxe `FOR SYSTEM_TIME ALL` nas queries para listar o histórico estruturado de versões de uma linha.
- Servem para auditorias de conformidade do histórico do registro em pontos específicos do tempo.
- **Não substituem o SQL Audit**: Utilize ambos de forma complementar.

```sql
-- Listar histórico completo de alterações salariais de um funcionário
SELECT EmployeeID, Salary, ValidFrom, ValidTo
FROM dbo.Employees
FOR SYSTEM_TIME ALL
WHERE EmployeeID = 42
ORDER BY ValidFrom;
```

> [!warning] Diferença de Exame: Temporal Tables vs SQL Audit
>
> - **Temporal Tables (Tabelas Temporais)**: Rastreiam o histórico de alterações físicas do dado (ex: qual era o salário antes do update). Elas **não** registram QUEM executou a alteração nem capturam comandos `SELECT` (leituras).
> - **SQL Audit**: Registra QUEM acessou o que e QUANDO (incluindo consultas `SELECT` via `BATCH_COMPLETED_GROUP`), mas não salva os estados anteriores dos registros. Utilize ambos de forma complementar.

---

## Melhores Práticas de Auditoria

- Habilite o grupo `BATCH_COMPLETED_GROUP` caso exija capturar o texto SQL completo executado nas queries (essencial para auditar leituras de `SELECT`).
- Utilize `ON_FAILURE = CONTINUE` para garantir disponibilidade; use `SHUTDOWN` apenas em bancos com requisitos estritos de conformidade de segurança (onde transações sem log são inaceitáveis).
- Mapeie políticas corporativas de retenção de dados — valores indefinidos (0) podem elevar custos de Storage no Azure.
- Prefira auditorias habilitadas a nível de servidor lógico no Azure SQL para garantir cobertura automatizada de quaisquer novos bancos adicionados no futuro.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - Três caminhos de destinos suportados para logs no Azure SQL: **Blob Storage**, **Log Analytics** e **Event Hub**.
> - O grupo **`BATCH_COMPLETED_GROUP`** é o único que captura o texto completo da declaração SQL executada (`statement`), indispensável para auditar leituras.
> - `ON_FAILURE = SHUTDOWN` encerra a execução do servidor caso o log falhe.
> - As tabelas temporais registram o histórico de modificações físicas do dado, mas não salvam logins ou leituras de dados como o SQL Audit faz.

---

## Resumo dos Conceitos (Key Takeaways)

- O SQL Server Audit utiliza regras baseadas em especificações de banco ou servidor.
- O Azure SQL integra-se ao Azure Monitor para transmissão de trilhas a sistemas SIEM.
- A função `sys.fn_get_audit_file` lê fisicamente arquivos de logs locais.
- Combine auditoria lógica com tabelas de versionamento temporal para documentação completa de conformidade de dados.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma especificação de segurança de um banco de dados Azure SQL exige que todas as queries de consultas `SELECT` executadas em tabelas de registros de RH sejam auditadas, contendo o texto T-SQL completo do comando executado. Qual grupo de ações de auditoria atende a essa exigência?

A. DATABASE_OBJECT_ACCESS_GROUP

B. SCHEMA_OBJECT_ACCESS_GROUP

C. BATCH_COMPLETED_GROUP

D. FAILED_DATABASE_AUTHENTICATION_GROUP

> [!success]- Resposta
> **C — BATCH_COMPLETED_GROUP**
>
> O grupo `BATCH_COMPLETED_GROUP` registra todos os lotes de comandos T-SQL concluídos com sucesso no banco, incluindo o texto completo da query enviada (gravada na coluna `statement`). Os grupos `DATABASE_OBJECT_ACCESS_GROUP` (A) e `SCHEMA_OBJECT_ACCESS_GROUP` (B) rastreiam o acesso aos objetos e tabelas, mas não garantem a captura do texto completo executado no SELECT. O grupo (D) loga apenas falhas de logins.

---

## Tópicos Relacionados

- [03-Permissões & Acessos](./03-permissions-access.md)
- [02-Tabelas Especializadas — Ledger](../01-database-objects/02-specialized-tables.md)
- [03-Monitoramento](../08-azure-services-integration/03-monitoring.md) *(Inglês apenas)*

---

## Documentação Oficial

- [SQL Server Audit](https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine)
- [Azure SQL Auditing](https://learn.microsoft.com/en-us/azure/azure-sql/database/auditing-overview)

---

**[← Anterior](./03-permissions-access.md) | [↑ Voltar para a Seção](./data-security-compliance.md) | [Lab: Auditoria](../../practice/labs/05-data-security-compliance/04-auditing-lab.sql) | [Próximo →](./05-secure-endpoints.md)**
