---
title: Labs de Otimização de Performance
type: lab-guide
---

# Labs de Otimização de Performance

Os scripts usam SQL Server 2022+ e a amostra AdventureWorks OLTP. Execute-os em uma base descartável de laboratório, nunca em uma base compartilhada ou de produção.

## Ordem recomendada

1. `01-database-configurations-lab.sql`: configurações de escopo do banco, Query Store, escopo do tuning automático e concessões de memória.
2. `02-transaction-isolation-concurrency-lab.sql`: versionamento de linhas e concorrência otimista.
3. `03-query-performance-troubleshooting-lab.sql`: planos, estatísticas, parameter sniffing e plan guides.

## Exercício de concorrência em duas sessões

O segundo lab possui diagnósticos, mas uma cadeia de bloqueio só pode ser observada quando duas sessões se sobrepõem. Abra duas janelas do SSMS conectadas à `AdventureWorks2025`.

Sessão A:

```sql
USE AdventureWorks2025;
BEGIN TRANSACTION;
UPDATE lab.InventoryStock SET Quantity = Quantity + 1 WHERE ItemID = 1;
-- Deixe a transação aberta.
```

Sessão B, primeiro com RCSI desabilitado em uma cópia descartável:

```sql
USE AdventureWorks2025;
SELECT ItemID, Quantity FROM lab.InventoryStock WHERE ItemID = 1;
```

Execute a DMV de bloqueios da Parte 3 em uma terceira janela e depois execute `ROLLBACK` na Sessão A. Habilite RCSI e repita a Sessão B. Compare a espera; depois repita com uma transação explícita em `SNAPSHOT` para observar a consistência no nível da transação.

## Limpeza

Ao terminar, feche todas as transações e remova apenas os objetos do laboratório. Restaure as opções do banco somente se ele for dedicado ao laboratório:

```sql
USE master;
ALTER DATABASE AdventureWorks2025 SET READ_COMMITTED_SNAPSHOT OFF;
ALTER DATABASE AdventureWorks2025 SET ALLOW_SNAPSHOT_ISOLATION OFF;
```

Desabilitar RCSI também exige acesso exclusivo; não execute a limpeza às cegas em uma base compartilhada.

## Referências oficiais

- [Guia de bloqueios e versionamento de linhas](https://learn.microsoft.com/pt-br/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide)
- [Monitorar desempenho usando o Query Store](https://learn.microsoft.com/pt-br/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
