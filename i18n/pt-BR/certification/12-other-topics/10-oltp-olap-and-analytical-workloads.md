---
title: OLTP, OLAP e Cargas Analíticas
type: study-material
tags:
  - dp-800
  - oltp
  - olap
  - data-warehouse
  - data-mart
  - columnstore
---

> [!info] Escopo
>
> Este tópico compara cargas transacionais e analíticas e mostra como escolher
> entre banco operacional, warehouse, data mart e análise operacional em tempo
> quase real.

# OLTP, OLAP e Cargas Analíticas

O mesmo dado pode ser consultado por aplicações transacionais e por relatórios,
mas os padrões de acesso são diferentes. Projetar a solução começa por identificar
o tipo de workload, não pelo produto ou índice favorito.

## OLTP

**OLTP (Online Transaction Processing)** atende operações do dia a dia:

- inserir um pedido;
- alterar o endereço de um cliente;
- reservar estoque;
- confirmar um pagamento;
- consultar uma entidade por sua chave.

Características comuns:

- muitas transações pequenas e concorrentes;
- leitura e escrita frequentes;
- baixa latência por operação;
- consistência transacional forte;
- consultas seletivas, geralmente por chave;
- tabelas normalizadas para reduzir anomalias de atualização.

## OLAP

**OLAP (Online Analytical Processing)** atende análise e tomada de decisão:

- totalizar vendas por mês e região;
- comparar períodos;
- calcular margem e participação;
- explorar milhões ou bilhões de eventos;
- cruzar fatos com várias dimensões.

Características comuns:

- leituras que percorrem muitas linhas;
- agregações, joins e agrupamentos;
- consultas concorrentes de longa duração;
- dados históricos e cargas incrementais;
- modelos dimensionais e índices orientados a análise.

## OLTP versus OLAP

| Critério | OLTP | OLAP |
|---|---|---|
| Objetivo | Executar o processo operacional | Analisar o processo |
| Operação típica | Inserir/atualizar poucas linhas | Ler e agregar muitas linhas |
| Modelo comum | Relacional normalizado | Dimensional, wide ou lakehouse |
| Índice comum | Rowstore/B-tree seletivo | Columnstore e estruturas de agregação |
| Histórico | Estado atual e auditoria operacional | Série histórica para comparação |
| Concorrência | Muitas transações pequenas | Consultas analíticas concorrentes |
| Latência | Milissegundos por operação | Milissegundos a minutos, conforme escopo |

Uma aplicação transacional não deve ser transformada automaticamente em warehouse.
Da mesma forma, um warehouse não deve receber diretamente todas as escritas da
aplicação sem uma decisão explícita de arquitetura.

## Normalização e desnormalização

### Normalização no OLTP

Normalização separa entidades e reduz duplicação. Isso ajuda a manter consistência:

```text
Customer ───< Order ───< OrderItem >─── Product
```

Uma alteração no produto é feita em um lugar, e as transações referenciam a
entidade por sua chave.

### Desnormalização no OLAP

No ambiente analítico, pode ser útil manter atributos juntos em dimensões ou
camadas preparadas para reduzir joins e simplificar o consumo. Desnormalizar não
significa abandonar integridade: chaves, grão, regras de qualidade e reconciliação
continuam necessários.

| Escolha | Benefício | Risco |
|---|---|---|
| Normalizar | Integridade e menor duplicação | Mais joins para análise |
| Desnormalizar | Consulta e consumo mais simples | Redundância e manutenção de cargas |

Use o desenho que atende o workload. Não aplique a regra “sempre normalize” ou
“sempre use tabelas largas” sem medir consultas e cargas.

## Data warehouse e data mart

Um **data warehouse** integra dados de vários processos ou fontes e mantém regras
de negócio, histórico e estruturas para análise corporativa.

Um **data mart** é uma área analítica focada em um domínio, departamento ou caso de
uso, como vendas, finanças ou atendimento. Pode ser:

- dependente do warehouse corporativo;
- construído a partir de uma fonte específica;
- físico ou lógico, dependendo da plataforma.

Um data mart independente pode ser rápido no início, mas aumenta o risco de:

- definições diferentes para a mesma métrica;
- dimensões não conformadas;
- cópias e cargas duplicadas;
- reconciliação difícil entre áreas.

Prefira dimensões e métricas compartilhadas quando vários marts precisam responder
às mesmas perguntas de negócio.

## HTAP e análise operacional

**HTAP (Hybrid Transactional/Analytical Processing)** combina transações e análise
no mesmo ambiente ou em cópias sincronizadas. Um cenário de análise operacional
quase em tempo real pode usar um índice columnstore não clusterizado sobre uma
tabela rowstore para manter uma estrutura analítica atualizada.

Isso pode reduzir a necessidade de ETL para uma pergunta pontual, mas não elimina
um warehouse quando a solução precisa:

- integrar várias fontes;
- aplicar histórico dimensional complexo;
- criar regras de negócio corporativas;
- suportar grande volume analítico ou dados pré-agregados;
- isolar totalmente a carga analítica da transacional.

O índice analítico também tem custo de armazenamento e manutenção. Meça o impacto
das escritas transacionais antes de adotá-lo.

## Rowstore e columnstore

### Rowstore

Rowstore armazena os valores de uma linha próximos fisicamente. É adequado para:

- seeks por chave;
- leituras de poucas linhas;
- operações OLTP;
- índices B-tree seletivos.

### Columnstore

Columnstore armazena dados por coluna e usa compressão, eliminação de colunas,
eliminação de segmentos e processamento em lote. É adequado para consultas que
leem muitas linhas, mas poucas colunas, e fazem agregações.

```sql
-- Exemplo conceitual para uma fato analítica grande
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactSales
ON dbo.FactSales;
```

Uma tabela com clustered columnstore pode receber índices rowstore adicionais
quando consultas seletivas ou chaves exigirem seeks. Um nonclustered columnstore
em uma tabela rowstore pode apoiar análise operacional, mas mantém uma cópia
analítica e aumenta o custo de manutenção das alterações.

Columnstore não garante ganho em qualquer consulta. Avalie:

- tamanho da tabela e volume de leitura;
- quantidade de colunas projetadas;
- seletividade dos filtros;
- padrão de inserção e atualização;
- tamanho dos rowgroups e eliminação de segmentos;
- plano de execução, I/O e tempo de CPU.

## Agregações e tabelas de resumo

Uma tabela de resumo armazena resultados em uma granularidade mais alta, como
vendas por dia, produto e região. Ela pode reduzir custo para consultas repetidas,
mas exige:

- definição clara do grão;
- atualização consistente com a fato detalhada;
- reconciliação de totais;
- tratamento de atraso e reprocessamento;
- decisão sobre quais consultas podem usar o resumo.

Não use uma tabela agregada para esconder uma modelagem incorreta. Se a pergunta
precisa do detalhe da transação, o resumo não substitui a fato detalhada.

## Particionamento em grandes fatos

Particionar uma tabela separa seus dados em partições administráveis, frequentemente
por data. Isso pode ajudar em:

- cargas e descarregamentos por período;
- manutenção de dados antigos;
- eliminação de partições em consultas que filtram pela chave de partição;
- operações de índice e arquivamento.

Particionamento não acelera automaticamente uma consulta. O predicado deve permitir
eliminação de partições e o número de partições precisa ser administrável. Particionar
por uma coluna que raramente aparece nos filtros pode adicionar complexidade sem
benefício relevante.

## Padrões de serving analítico

| Padrão | Fonte de consulta | Quando considerar |
|---|---|---|
| Modelo semântico sobre warehouse | Dados curados e dimensionais | Métricas governadas e relatórios corporativos |
| Data mart por domínio | Subconjunto curado | Autonomia de uma área com contratos claros |
| Lakehouse | Tabelas e arquivos analíticos | Engenharia, ciência de dados e múltiplos motores |
| Consulta operacional com columnstore | Fonte transacional e cópia analítica | Métricas recentes com baixa latência |
| API ou view de serving | Contrato de consumo estável | Aplicações e integrações controladas |

O consumidor deve acessar uma camada apropriada, não tabelas internas de staging
por conveniência.

## Matriz de decisão

```text
Precisa executar transações pequenas e concorrentes?
├── Sim → OLTP com rowstore e modelo normalizado
└── Não
    ├── Precisa integrar histórico e múltiplas fontes?
    │   ├── Sim → Warehouse/lakehouse + modelo dimensional
    │   └── Não
    ├── Precisa de análise quase em tempo real na mesma origem?
    │   ├── Sim → Avaliar HTAP/columnstore e medir impacto
    │   └── Não → OLAP dedicado, data mart ou modelo semântico
```

## Checklist de arquitetura

- O workload é transacional, analítico ou misto?
- O modelo normalizado atende a escrita sem criar joins analíticos excessivos?
- O modelo dimensional tem fatos com grão consistente?
- Existe uma fonte oficial para métricas e dimensões conformadas?
- A análise deve ser isolada da carga transacional?
- Columnstore, particionamento ou agregações foram escolhidos com evidência?
- O padrão suporta o volume, concorrência e SLO de latência?
- A carga incremental é idempotente e reprocessável?
- Os totais do serving reconciliam com a fonte autorizada?
- O plano de execução confirma o benefício dos índices e agregações?

## Documentação oficial

- [Desempenho de consultas com índices columnstore](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/columnstore-indexes-query-performance?view=sql-server-ver17)
- [Índices columnstore em data warehouses](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/columnstore-indexes-data-warehouse?view=sql-server-ver17)
- [Análise operacional em tempo real com columnstore](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/get-started-with-columnstore-for-real-time-operational-analytics?view=sql-server-ver17)
- [CREATE COLUMNSTORE INDEX](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-columnstore-index-transact-sql?view=sql-server-ver17)

---

**[← Padrões de Integração](./09-data-integration-patterns.md) | [↑ Voltar para Outros Tópicos](./other-topics.md)**
