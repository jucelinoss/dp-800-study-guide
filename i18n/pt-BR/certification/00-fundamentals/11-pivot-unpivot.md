---
title: "PIVOT e UNPIVOT"
type: study-material
tags: [sql-server, tsql, pivot, unpivot, fundamentals]
---

# PIVOT e UNPIVOT

`PIVOT` e `UNPIVOT` remodelam uma expressão que retorna uma tabela. `PIVOT` transforma valores distintos de uma coluna em colunas de saída e executa uma agregação quando necessário. `UNPIVOT` faz a transformação inversa, convertendo colunas em linhas. [Microsoft Learn](https://learn.microsoft.com/pt-br/sql/t-sql/queries/from-using-pivot-and-unpivot?view=sql-server-ver17)

## Modelo mental

Suponha que a origem tenha uma linha por venda e uma coluna `QuarterName`:

| Region | QuarterName | Amount |
| :--- | :--- | ---: |
| East | Q1 | 100 |
| East | Q2 | 120 |

`PIVOT` produz um relatório largo:

| Region | Q1 | Q2 |
| :--- | ---: | ---: |
| East | 100 | 120 |

`UNPIVOT` transforma esse relatório largo novamente em linhas de atributo/valor. Ele não é uma inversão perfeita: `PIVOT` pode agregar várias linhas de origem, e `UNPIVOT` elimina valores `NULL`.

## Sintaxe do PIVOT

```sql
SELECT <colunas_de_grupo>, [Q1], [Q2], [Q3], [Q4]
FROM
(
    SELECT Region, QuarterName, Amount
    FROM study.PivotSales
) AS source_data
PIVOT
(
    SUM(Amount)
    FOR QuarterName IN ([Q1], [Q2], [Q3], [Q4])
) AS pivot_data;
```

A consulta de origem deve expor somente as colunas de agrupamento, a coluna usada no pivot e a coluna de valor. Colunas extras podem virar colunas de agrupamento implícitas e alterar a granularidade do resultado.

`IN ([Q1], [Q2], [Q3], [Q4])` é uma lista estática. Um valor que não existe na origem ainda aparece como coluna, com `NULL` para os grupos sem aquele valor. Use PIVOT dinâmico quando as colunas de saída não forem conhecidas antecipadamente.

## Sintaxe do UNPIVOT

```sql
SELECT SalesYear, Region, QuarterName, Amount
FROM study.PivotSalesWide
UNPIVOT
(
    Amount FOR QuarterName IN ([Q1], [Q2], [Q3], [Q4])
) AS unpivot_data;
```

Os nomes listados em `IN` tornam-se valores de `QuarterName`; os valores das células tornam-se `Amount`. `UNPIVOT` omite linhas cuja célula de origem é `NULL`, portanto trimestres ausentes não reaparecem como linhas.

## PIVOT versus agregação condicional

`PIVOT` é conciso para uma tabela cruzada fixa. A agregação condicional pode ser mais fácil de estender ou depurar:

```sql
SELECT
    SalesYear,
    Region,
    SUM(CASE WHEN QuarterName = N'Q1' THEN Amount END) AS Q1,
    SUM(CASE WHEN QuarterName = N'Q2' THEN Amount END) AS Q2,
    SUM(CASE WHEN QuarterName = N'Q3' THEN Amount END) AS Q3,
    SUM(CASE WHEN QuarterName = N'Q4' THEN Amount END) AS Q4
FROM study.PivotSales
GROUP BY SalesYear, Region;
```

As duas abordagens agregam na mesma granularidade. Escolha a forma que deixe o contrato do relatório mais fácil de ler e manter. Repetir `PIVOT`/`UNPIVOT` na mesma instrução pode afetar a performance; meça relatórios complexos em vez de assumir que um formato é sempre mais rápido.

## Armadilhas comuns

- `PIVOT` exige uma agregação como `SUM`, `COUNT` ou `AVG`.
- Uma coluna deixada acidentalmente na consulta de origem vira uma coluna de agrupamento implícita.
- `NULL` em um valor pivotado continua sendo `NULL`; não vira zero automaticamente.
- `UNPIVOT` elimina células `NULL`.
- Os identificadores de coluna em `UNPIVOT` seguem as regras de collation do catálogo; conflitos podem exigir `COLLATE DATABASE_DEFAULT`.
- Remodelagens repetidas podem tornar a consulta mais difícil de otimizar e manter.

## Laboratório prático

Execute o [Laboratório 11 — PIVOT e UNPIVOT](../../practice/labs/00-fundamentals/11-pivot-unpivot.sql) depois do [Laboratório 01 — Criar StudyDB](../../practice/labs/00-fundamentals/01-setup-studydb.sql).

O lab cria uma tabela descartável `study.PivotSales`, produz uma tabela cruzada trimestral e faz o unpivot do resultado para mostrar por que trimestres `NULL` desaparecem.

## Documentação oficial

- [Usando PIVOT e UNPIVOT](https://learn.microsoft.com/pt-br/sql/t-sql/queries/from-using-pivot-and-unpivot?view=sql-server-ver17)

---

**[← Anterior](./10-index-fundamentals.md) | [↑ Voltar à Parte 0](./fundamentals.md) | [Lab: PIVOT e UNPIVOT](../../practice/labs/00-fundamentals/11-pivot-unpivot.sql) | [Próximo →](./12-ready-for-dp800.md)**
