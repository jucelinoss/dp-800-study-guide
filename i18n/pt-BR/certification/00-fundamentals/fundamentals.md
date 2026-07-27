---
title: "Fundamentos de SQL Server para DP-800"
type: category
tags: [dp-800, sql-server, tsql, fundamentals]
status: complete
---

# Parte 0 — Fundamentos de SQL Server

Este caminho opcional de pré-requisitos é para alunos que são novos em bancos de dados relacionais ou T-SQL. Não é um domínio separado do exame DP-800; ele fornece o vocabulário e os hábitos práticos necessários antes da Seção 01.

> [!abstract]
>
> - Construa e consulte um pequeno banco de dados relacional com segurança.
> - Aprenda os conceitos SQL assumidos pelo material do DP-800.
> - Complete os laboratórios em ordem; eles compartilham o banco de dados `StudyDB`.

> [!tip] Comece aqui se você ainda não sabe criar uma tabela, escrever um JOIN e explicar o que é uma chave primária.
> Desenvolvedores SQL experientes podem revisar a lista de verificação e ir diretamente para a [Seção 01](../../01-database-objects/database-objects.md).

## O que a Parte 0 é — e não é

A Parte 0 é um curso pré-requisito autossuficiente de SQL Server e T-SQL. Ela ensina a linguagem e os hábitos de modelagem de dados assumidos pelo material do DP-800; ela não pretende mapear diretamente para um domínio do exame ou substituir as seções mapeadas para o exame.

| A Parte 0 fornece | Continue depois para |
| :--- | :--- |
| Modelagem relacional básica e tipos de dados | Tabelas especializadas, JSON, particionamento, sequências |
| Vocabulário completo de consultas de leitura | Funções janela, regex, consultas grafo, T-SQL avançado |
| DDL/DML seguros e restrições | Segurança, concorrência, implantação e monitoramento |
| Compensações básicas de índices | Planos de execução, DMVs, Query Store e ajuste de performance |

## Caminho de aprendizado

> [!info] Aprofundamento
> Leia o [Workbook de Fundamentos de SQL Server](./00-foundations-workbook.md) junto com as lições abaixo. Ele explica cada conceito central em profundidade, inclui exercícios de verificação e soluções, e usa apenas os laboratórios `StudyDB` deste repositório.

| Etapa | Tópico | Resultado |
| :---: | :--- | :--- |
| 00 | [Workbook de Fundamentos](./00-foundations-workbook.md) | Lição autossuficiente e projeto final |
| 01 | [SQL Server e ferramentas](./01-sql-server-and-tools.md) | Conecte-se com SSMS ou VS Code |
| 02 | [Modelo relacional e tipos de dados](./02-relational-model-and-data-types.md) | Modele linhas, colunas, chaves e `NULL` |
| 03 | [Criar e carregar dados](./03-create-and-load-data.md) | Use DDL e inserts seguros |
| 04 | [SELECT, filtros, subconsultas e operações de conjunto](./04-select-and-filter.md) | Componha consultas de leitura completas |
| 05 | [Relacionamentos e JOINs](./05-relationships-and-joins.md) | Combine tabelas relacionadas |
| 06 | [Agregação](./06-aggregation-and-grouping.md) | Sumarize corretamente |
| 07 | [Alterar dados com segurança](./07-change-data-safely.md) | Use transações com DML |
| 08 | [Regras de integridade](./08-integrity-rules.md) | Proteja dados válidos |
| 09 | [CTEs e estruturas temporárias de consulta](./09-subqueries-and-ctes.md) | Nomeie e reutilize resultados intermediários |
| 10 | [Fundamentos de índices](./10-index-fundamentals.md) | Entenda as compensações leitura/escrita |
| 11 | [Pronto para o DP-800](./11-ready-for-dp800.md) | Escolha seu próximo módulo |

## Ritmo de estudo recomendado

1. Leia a lição correspondente antes de executar seu laboratório.
2. Execute o laboratório no `StudyDB`, depois modifique um valor ou predicado e preveja o resultado.
3. Complete as questões de prática da lição sem olhar a resposta primeiro.
4. Ao final de cada sessão de estudo, explique um conceito em voz alta em linguagem simples; se não conseguir, revisite o exemplo.
5. Use a Lição 11 para diagnosticar lacunas antes de passar para a Seção 01.

> [!note]
> Os laboratórios numerados são intencionalmente progressivos. Execute `01-setup-studydb.sql` primeiro. Se seus experimentos deixarem os dados em estado desconhecido, execute novamente o script de configuração e continue a partir do laboratório relevante.

## Laboratórios

Execute os scripts em `practice/labs/00-fundamentals/`. Comece com `01-setup-studydb.sql`; os scripts posteriores podem ser executados novamente com segurança porque usam o mesmo banco de dados descartável `StudyDB`.

## Conceitos-chave

- Uma **tabela** armazena linhas de uma entidade; um **relacionamento** conecta entidades através de chaves.
- `SELECT` lê dados; DDL define objetos; DML insere, altera ou remove linhas.
- Uma transação permite revisar uma alteração e escolher `COMMIT` ou `ROLLBACK`.
- Uma consulta tem um **grain** (granularidade) intencional: o significado de uma linha de resultado. Defina-o antes de adicionar JOINs ou agregados.
- Estruturas temporárias resolvem um problema de tempo de vida; use uma CTE, variável de tabela ou tabela temporária apenas quando seu escopo for necessário.

## Recursos relacionados

- [Database Objects](../01-database-objects/database-objects.md)
- [Advanced T-SQL](../../03-advanced-tsql/advanced-tsql.md)
- [Hands-on Labs](../../practice/labs/)

---

**[↑ Caminho de estudo DP-800](../dp-800-overview.md) | [Próximo →](./01-sql-server-and-tools.md)**
