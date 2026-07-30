---
title: "Pronto para o Caminho de Estudo DP-800"
type: topic
tags: [dp-800, fundamentals, roadmap]
---

# Pronto para o Caminho de Estudo DP-800

## Visão Geral

Você está pronto para iniciar o guia mapeado para o exame quando conseguir modelar um pequeno problema relacional, consultá-lo e fazer alterações com segurança. O resto do guia constrói sobre essas habilidades em vez de repeti-las.

> [!abstract]
>
> - A Parte 0 é preparação, não um domínio do exame DP-800.
> - A Seção 01 é seu próximo destino.
> - Use o diagnóstico abaixo para decidir se deve avançar ou revisitar uma lição específica.

> [!tip] O que o Exame Testa
> O exame testa design avançado de banco de dados, segurança, implantação e recursos habilitados para IA; ele assume estas habilidades básicas de T-SQL.

---

## Lista de verificação de prontidão

- [ ] Consigo explicar um banco de dados, schema, tabela, linha, coluna, chave primária e chave estrangeira.
- [ ] Consigo criar uma tabela com tipos básicos apropriados, `IDENTITY` e um `DEFAULT`.
- [ ] Consigo escrever consultas `SELECT`, `WHERE`, `ORDER BY`, JOIN e `GROUP BY`.
- [ ] Sei que `NULL` requer `IS NULL` ou `IS NOT NULL`.
- [ ] Eu pré-visualizo um `UPDATE` ou `DELETE` com `SELECT` e entendo `ROLLBACK`.
- [ ] Entendo por que restrições e índices existem, mesmo que não tenha dominado suas formas avançadas.

## Uma verificação prática de prontidão

Você não precisa memorizar cada variante de sintaxe. Você está pronto quando consegue trabalhar de uma pergunta de negócio curta para uma consulta ou definição de tabela correta e explicável.

Tente isto sem copiar uma resposta anterior:

1. Explique o relacionamento um-para-muitos entre `Customer` e `SalesOrder`, incluindo onde a chave estrangeira pertence.
2. Crie uma tabela de produto com uma chave gerada, um nome obrigatório, um preço exato não negativo e uma flag de ativo padrão.
3. Retorne todo cliente com seu total gasto, incluindo clientes sem pedidos como zero.
4. Retorne clientes que não têm pedidos, usando `NOT EXISTS`.
5. Pré-visualize e reverta uma alteração de preço para um produto conhecido.

| Se isto foi difícil | Revisite | O que dominar |
| :--- | :--- | :--- |
| Relacionamento e chave estrangeira | [Lição 02](./02-relational-model-and-data-types.md), [Lição 05](./05-relationships-and-joins.md) | Cardinalidade, predicados JOIN, preservação de linhas |
| Definição de tabela | [Lição 02](./02-relational-model-and-data-types.md), [Lição 03](./03-create-and-load-data.md) | Tipos, `IDENTITY`, `DEFAULT`, restrições |
| Total do cliente | [Lição 05](./05-relationships-and-joins.md), [Lição 06](./06-aggregation-and-grouping.md) | Left joins, grão do resultado, `COUNT`/`SUM` e `NULL` |
| Consulta de pedidos ausentes | [Lição 04](./04-select-and-filter.md) | `NOT EXISTS` correlacionado e comportamento de `NULL` |
| Alteração segura | [Lição 07](./07-change-data-safely.md) | Pré-visualização, transação, `ROLLBACK` |

## Inicie o caminho mapeado para o exame intencionalmente

Comece com [01 — Database Objects](../01-database-objects/database-objects.md). Ele assume que você já consegue criar e consultar tabelas comuns, então avança para o escopo DP-800: design de índices, tipos de tabela especializados, JSON, restrições, sequências e particionamento.

Não pule diretamente para os capítulos de IA só porque parecem mais alinhados com a certificação. Cenários de Vector, RAG e modelo externo ainda requerem tabelas, junções, segurança e raciocínio de consulta corretos.

## Onde cada habilidade continua

| Fundação | Continua em |
| :--- | :--- |
| Tabelas, chaves, restrições, índices | [01 — Database Objects](../01-database-objects/database-objects.md) |
| CTEs e lógica de consulta | [03 — Advanced T-SQL](../03-advanced-tsql/advanced-tsql.md) |
| Transações e concorrência | [06 — Performance Optimization](../06-performance-optimization/performance-optimization.md) |
| Consultas habilitadas para IA | [09–11 — AI Capabilities](../09-models-embeddings/models-embeddings.md) |

## Continue usando seu sandbox

O `StudyDB` permanece útil após a Parte 0. Antes de executar um exemplo não familiar de um módulo posterior, isole a menor versão reproduzível naquele banco de dados. Use um novo schema ou tabela com nome claro para evitar colisão com os laboratórios iniciantes, inspecione os dados antes de DML e limpe apenas objetos que você criou.

Esta abordagem transforma exemplos posteriores em experimentos em vez de exercícios de copiar-colar. Quando um resultado te surpreender, reduza a tabela a algumas linhas e escreva o resultado esperado antes de reexecutar a consulta.

## Casos de Uso

- Decidir se deve iniciar a Seção 01 ou revisitar uma lição anterior.

## Problemas Comuns & Erros

> [!warning] Erro Comum
> Não espere dominar todo recurso do SQL Server antes de começar o DP-800. Prossiga assim que conseguir trabalhar com esta lista de verificação.

> [!warning] Erro Comum
> Tratar a Parte 0 como conteúdo do exame pode distorcer o tempo de estudo. Seu propósito é remover atrito dos módulos mapeados para o exame, não substituir a prática específica de seus recursos.

## Melhores Práticas

- Mantenha o `StudyDB` como um sandbox seguro para testar exemplos de módulos posteriores.
- Revisite uma lição pré-requisito de cada vez quando um conceito posterior expor uma lacuna; não recomece todo o caminho desnecessariamente.

## Dicas para o Exame

> [!tip] Dicas para o Exame
> Use esta Parte 0 para reduzir a carga cognitiva, então gaste seu tempo de preparação para o exame nos tópicos do blueprint DP-800.

## Principais Conclusões

- Você agora tem o vocabulário e os hábitos pré-requisito para o guia.
- Você pode diagnosticar uma lacuna por habilidade e retornar diretamente à sua lição.
- A próxima seção mapeada para o exame é Database Objects.

## Tópicos Relacionados

- [Visão geral do DP-800](../dp-800-overview.md)

## Documentação Oficial

- [Guia de estudo DP-800](https://learn.microsoft.com/credentials/certifications/resources/study-guides/dp-800)

---

**[← Anterior](./11-pivot-unpivot.md) | [↑ Voltar à Seção](./fundamentals.md) | [Iniciar Seção 01 →](../01-database-objects/database-objects.md)**
