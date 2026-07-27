---
title: "Alterar Dados com Segurança"
type: topic
tags: [sql-server, dml, transactions, fundamentals]
---

# Alterar Dados com Segurança

## Visão Geral

`UPDATE` e `DELETE` são essenciais mas potencialmente abrangentes. Revise as linhas alvo e use uma transação ao praticar ou fazer uma alteração consequente.

> [!abstract]
>
> - `UPDATE` altera valores existentes; `DELETE` remove linhas.
> - Use o mesmo predicado em um `SELECT` de visualização primeiro.
> - `BEGIN TRAN`, `COMMIT` e `ROLLBACK` tornam uma unidade de trabalho explícita.

> [!tip] O que o Exame Testa
> O DP-800 desenvolve esta base em níveis de isolamento, bloqueio, deadlocks, triggers e captura de alterações.

---

## Visualize, depois altere

```sql
BEGIN TRAN;

SELECT *
FROM study.Product
WHERE ProductName = N'Pen';

UPDATE study.Product
SET UnitPrice = 2.25
WHERE ProductName = N'Pen';

ROLLBACK; -- substitua por COMMIT apenas após verificar o resultado
```

## A regra inegociável: SELECT primeiro

Antes de escrever uma instrução destrutiva ou corretiva, escreva o `SELECT` exato que identifica seu alvo. Verifique o banco de dados, a contagem de linhas, os valores de chave e os valores antigos. Só então substitua `SELECT` por `UPDATE` ou `DELETE`, mantendo a lógica `FROM`/JOIN e `WHERE` inalterada.

```sql
-- 1. Confirme o contexto.
SELECT DB_NAME() AS current_database;

-- 2. Visualize os alvos e valores exatos.
SELECT ProductId, ProductName, UnitPrice
FROM study.Product
WHERE ProductName = N'Notebook';

-- 3. Altere exatamente as linhas que acabou de revisar.
UPDATE study.Product
SET UnitPrice = 13.50
WHERE ProductName = N'Notebook';
```

Para uma operação importante, faça os passos 2 e 3 dentro da mesma transação curta. Uma visualização feita horas antes não é garantia de que os dados não mudaram nesse intervalo.

| Verificação antes do DML | Por que importa |
| :--- | :--- |
| Banco de dados e schema | Previne alterar o ambiente/objeto errado |
| Predicado e JOIN | Previne um conjunto alvo amplo ou incorretamente relacionado |
| Contagem de linhas | Expõe um número surpreendente de linhas afetadas |
| Chaves primárias | Permite identificar exatamente quais linhas serão alteradas |
| Valores antigos | Permite verificar os novos valores e recuperar logicamente se necessário |

> [!warning] Uma instrução bem-sucedida não é prova de correção
> O SQL Server pode atualizar com sucesso 10.000 linhas não intencionadas. A mensagem de linhas afetadas apenas confirma execução, não que o predicado expressou a regra de negócio pretendida.

## O ciclo de segurança DML

Use o mesmo predicado em um `SELECT` antes de todo `UPDATE` ou `DELETE` consequente. Depois inspecione as linhas afetadas, altere-as dentro de uma transação curta, inspecione novamente e escolha `COMMIT` ou `ROLLBACK`.

```sql
BEGIN TRAN;

SELECT SalesOrderId, OrderTotal
FROM study.SalesOrder
WHERE CustomerId = 1;

UPDATE study.SalesOrder
SET OrderTotal = OrderTotal * 0.90
WHERE CustomerId = 1;

SELECT SalesOrderId, OrderTotal
FROM study.SalesOrder
WHERE CustomerId = 1;

ROLLBACK;
```

`ROLLBACK` reverte o trabalho não confirmado na transação. `COMMIT` o torna durável. Mantenha a transação curta: transações abertas podem reter locks e bloquear outras sessões.

### Um template de transação revisável

```sql
SET XACT_ABORT ON;
BEGIN TRAN;

SELECT ProductId, ProductName, UnitPrice
FROM study.Product
WHERE ProductName LIKE N'Old%';

UPDATE study.Product
SET IsDiscontinued = 1
OUTPUT inserted.ProductId, inserted.IsDiscontinued
WHERE ProductName LIKE N'Old%';

-- Inspecione o OUTPUT e um SELECT de acompanhamento.
-- COMMIT;
ROLLBACK;
```

`SET XACT_ABORT ON` é um padrão útil em muitos scripts: certos erros de tempo de execução encerram e revertem a transação em vez de deixá-la aberta. Não substitui entender erros ou testar um script. Nos laboratórios de aprendizado, deixe `ROLLBACK` ativo até que o resultado esteja inquestionavelmente correto.

## UPDATE e DELETE são operações de conjunto

Uma instrução pode afetar muitas linhas; SQL não é implicitamente uma-linha-de-cada-vez. Isso é poderoso e perigoso.

```sql
-- Atualize toda linha correspondente, não apenas a primeira visível.
UPDATE study.Product
SET IsDiscontinued = 1
WHERE ProductName LIKE N'Old%';

-- Exclua apenas as linhas pretendidas.
DELETE FROM study.Product
WHERE IsDiscontinued = 1;
```

`DELETE` remove linhas selecionadas e pode ser desfeito dentro de uma transação aberta. `TRUNCATE TABLE` remove todas as linhas de forma muito mais ampla e tem restrições diferentes; não é um substituto para um delete baseado em predicado. Não use nenhum dos dois como comando de limpeza casual.

### Semântica all-at-once

Atribuições em um `UPDATE` leem os valores originais da linha; sua ordem escrita não é processual.

```sql
-- Se col1 é 100 e col2 é 0, o resultado é col1 = 110 e col2 = 100.
UPDATE dbo.Example
SET col1 = col1 + 10,
    col2 = col1
WHERE ExampleId = 1;
```

Não espere que `col2` receba o `col1` recém-atualizado. Use uma expressão explícita quando essa for a regra desejada. Este comportamento baseado em conjunto é uma razão pela qual uma consulta de visualização é mais segura do que tentar raciocinar sobre uma atualização linha por linha.

## UPDATE e DELETE com JOINs

O T-SQL permite que uma atualização ou exclusão use tabelas relacionadas para identificar alvos. Isso é poderoso o suficiente para exigir uma regra extra: execute o JOIN e filtros exatos como um `SELECT` primeiro, incluindo a chave da tabela alvo e o valor fonte que será usado.

```sql
-- Visualize primeiro: uma linha alvo deve ter um valor fonte pretendido.
SELECT p.ProductId, p.UnitPrice, s.NewPrice
FROM study.Product AS p
INNER JOIN study.ProductPriceStage AS s
    ON s.ProductId = p.ProductId;

-- Apenas após revisão.
UPDATE p
SET UnitPrice = s.NewPrice
FROM study.Product AS p
INNER JOIN study.ProductPriceStage AS s
    ON s.ProductId = p.ProductId;
```

Se múltiplas linhas de stage correspondem a um produto, a atualização pode ser não determinística: o SQL Server não é obrigado a avisar qual valor fonte vencerá. Garanta uma linha fonte por alvo com uma chave, agregue/classifique a fonte primeiro, ou rejeite duplicatas antes da atualização.

```sql
-- Visualize duplicatas em uma fonte de staging.
SELECT ProductId, COUNT(*) AS matching_source_rows
FROM study.ProductPriceStage
GROUP BY ProductId
HAVING COUNT(*) > 1;
```

A mesma regra de visualizar-primeiro se aplica a `DELETE` com join. Use um alias de alvo explícito para que fique óbvio qual tabela perderá linhas.

## DELETE versus TRUNCATE TABLE

| Característica | `DELETE` | `TRUNCATE TABLE` |
| :--- | :--- | :--- |
| Filtrar com `WHERE` | Sim | Não |
| Escopo | Linhas selecionadas ou todas | Todas as linhas (ou partições especificadas) |
| Contador identity | Não redefine | Redefine |
| Permissão típica | `DELETE` | `ALTER` |
| Referenciado por chave estrangeira | Pode excluir linhas se regras relacionais permitirem | Não pode truncar uma tabela referenciada |
| Caso de uso | Remoção direcionada | Reinicialização completa e intencional de uma tabela descartável elegível |

Ambos são destrutivos. `TRUNCATE` não é "DELETE mas mais rápido" quando você precisa preservar algumas linhas, inspecionar alvos individuais ou manter a sequência identity. Operações `DELETE` grandes podem criar atividade substancial de log e bloqueio; agendamento em lotes e design de retenção são tópicos de performance, mas a lição para iniciantes é planejar exclusões grandes em vez de executá-las interativamente.

## INSERT seguro também

A mesma disciplina se aplica a inserts: inspecione a consulta fonte, nomeie colunas alvo e verifique valores gerados/padrão após a carga.

```sql
-- Visualize a fonte primeiro.
SELECT ProductName, UnitPrice
FROM study.ProductArchive
WHERE UnitPrice >= 10.00;

INSERT INTO study.Product (ProductName, UnitPrice)
OUTPUT inserted.ProductId, inserted.ProductName
SELECT ProductName, UnitPrice
FROM study.ProductArchive
WHERE UnitPrice >= 10.00;
```

Quando uma tabela tem um default, omitir a coluna solicita esse default; inserir explicitamente `NULL` não. Evite `SET IDENTITY_INSERT` em cargas comuns de aplicação. É uma ferramenta especializada de migração/recuperação que requer cuidado exclusivo e deve ser desligada após o uso.

## Capture o que mudou

`OUTPUT` pode retornar linhas afetadas para revisão ou auditoria:

```sql
UPDATE study.Product
SET UnitPrice = UnitPrice * 1.05
OUTPUT inserted.ProductId,
       deleted.UnitPrice AS old_price,
       inserted.UnitPrice AS new_price
WHERE ProductName = N'Notebook';
```

`deleted` representa a linha pré-alteração e `inserted` representa a linha pós-alteração. É útil para verificação; auditoria completa e triggers são tópicos posteriores.

> [!warning] Erro Comum
> Uma atualização unida a uma fonte que tem múltiplas correspondências para um alvo pode ser não determinística. Primeiro execute o join como `SELECT` e prove que a fonte fornece no máximo um valor pretendido por linha alvo.

## Casos de Uso

- Corrija um pequeno lote de linhas com uma etapa de revisão auditável.
- Experimente com segurança em um laboratório sem recriar o banco de dados.

## Problemas Comuns & Erros

> [!warning] Erro Comum
> Um `UPDATE` ou `DELETE` sem `WHERE` afeta toda linha em sua tabela alvo.

## Melhores Práticas

- Execute o `SELECT` de visualização com o predicado DML exato.
- Mantenha as transações curtas; transações abertas podem bloquear outro trabalho.

## Dicas para o Exame

> [!tip] Dicas para o Exame
> Uma transação fornece atomicidade: suas alterações são confirmadas juntas ou desfeitas juntas.

## Principais Conclusões

- Leia o alvo primeiro.
- Confirme apenas após verificar a alteração pretendida.

## Tópicos Relacionados

- [Regras de integridade](./08-integrity-rules.md)
- [Performance Optimization](../../06-performance-optimization/performance-optimization.md)

## Documentação Oficial

- [Transações](https://learn.microsoft.com/sql/t-sql/language-elements/transactions-transact-sql)

---

**[← Anterior](./06-aggregation-and-grouping.md) | [↑ Voltar à Seção](./fundamentals.md) | [Próximo →](./08-integrity-rules.md)**
