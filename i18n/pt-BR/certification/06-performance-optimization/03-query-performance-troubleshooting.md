---
title: Solução de Problemas de Desempenho de Queries (Query Performance Troubleshooting)
type: study-material
tags:
  - dp-800
  - execution-plans
  - dmv
  - query-store
  - query-performance-insight
---

> [!info] 🗺️ Índice de Navegação Rápida
>
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Planos de Execução (Execution Plans)](#planos-de-execução-execution-plans)
>   - 🔹 [Habilitando Planos de Execução via T-SQL](#habilitando-planos-de-execução-via-t-sql)
>   - 🔹 [Operadores de Plano de Execução Comuns (Quadro Resumo)](#operadores-de-plano-de-execução-comuns-quadro-resumo)
>   - 🔹 [Guia Intuitivo e Detalhado dos Operadores Físicos](#guia-intuitivo-e-detalhado-dos-operadores-físicos)
>     - 🔸 [1. Operadores Físicos Mais Comuns (Fundamentais)](#1-operadores-físicos-mais-comuns-fundamentais)
>     - 🔸 [2. Operadores Físicos Intermediários e Avançados](#2-operadores-físicos-intermediários-e-avançados)
>   - 🔹 [Entendendo o Conceito de Data Spill (Spill para TempDB)](#entendendo-o-conceito-de-data-spill-spill-para-tempdb)
>   - 🔹 [Analisando Percentuais de Custo no Plano](#analisando-percentuais-de-custo-no-plano)
> - 📍 [3. Diagnóstico usando Views de Gerenciamento Dinâmico (DMVs)](#diagnóstico-usando-views-de-gerenciamento-dinâmico-dmvs)
>   - 🔹 [Identificando Queries com Maior Consumo](#identificando-queries-com-maior-consumo)
>   - 🔹 [Consultando Recomendações de Índices Ausentes](#consultando-recomendações-de-índices-ausentes)
>   - 🔹 [Consultando Estatísticas de Espera Globais (Wait Stats)](#consultando-estatísticas-de-espera-globais-wait-stats)
> - 📍 [4. Query Store (Repositório de Consultas)](#query-store-repositório-de-consultas)
> - 📍 [5. Query Performance Insight (Azure SQL Database)](#query-performance-insight-azure-sql-database)
> - 📍 [6. Forçando Planos e Guias de Planos (Plan Guides)](#forçando-planos-e-guias-de-planos-plan-guides)
>   - 🔹 [sp_query_store_force_plan](#sp_query_store_force_plan)
>   - 🔹 [Guias de Planos (Plan Guides)](#guias-de-planos-plan-guides)
> - 📍 [7. Mitigação de Parameter Sniffing (Snifagem de Parâmetros)](#mitigação-de-parameter-sniffing-snifagem-de-parâmetros)
>   - 🔹 [OPTION(RECOMPILE)](#optionrecompile)
>   - 🔹 [OPTION(OPTIMIZE FOR UNKNOWN)](#optionoptimize-for-unknown)
>   - 🔹 [Variável de Escopo Local](#variável-de-escopo-local)
> - 📍 [8. Manutenção de Estatísticas do Banco](#manutenção-de-estatísticas-do-banco)
>   - 🔹 [Quando e Como são Criadas Novas Estatísticas?](#quando-e-como-são-criadas-novas-estatísticas)
>   - 🔹 [Limiares de Atualização Automática (Auto-Update Stats)](#limiares-de-atualização-automática-auto-update-stats)
>   - 🔹 [Como Calcular e Escolher o Tamanho da Amostra (FULLSCAN vs SAMPLE)](#como-calcular-e-escolher-o-tamanho-da-amostra-fullscan-vs-sample)
>   - 🔹 [Quando Manter no Automático (Default e Modo Assíncrono)](#quando-manter-no-automático-default-e-modo-assíncrono)
>   - 🔹 [Quando Executar Manutenção Manual (UPDATE STATISTICS)](#quando-executar-manutenção-manual-update-statistics)
>   - 🔹 [Quando Desligar a Atualização Automática (Exceções Cirúrgicas)](#quando-desligar-a-atualização-automática-exceções-cirúrgicas)
> - 📍 [9. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [10. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [11. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [12. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [13. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [14. Documentação Oficial](#documentação-oficial)

---

# Solução de Problemas de Desempenho de Queries (Query Performance Troubleshooting)

## Visão Geral (Overview)

O SQL Server oferece múltiplas ferramentas para diagnosticar gargalos e comportamentos de queries lentas: planos de execução (físicos, estimados e reais), Views de Gerenciamento Dinâmico (DMVs), histórico persistente de execução através do Query Store e interfaces gráficas como o Query Performance Insight no Azure SQL.

> [!abstract]
>
> - Cobre a análise e leitura de operadores em planos de execução, uso avançado do Query Store, diagnóstico através de DMVs e tuning de índices.
> - A resolução de problemas de performance de consultas deve seguir um fluxo metódico: Identificar → Diagnosticar → Corrigir → Verificar.
> - Tópicos chave do exame: interfaces do Query Store e sp_query_store_force_plan, DMVs de performance, index seeks vs scans e isolamento de blocking.

> [!tip] O que o Exame Testa
>
> - **Query Store**: `sys.query_store_query`, `sys.query_store_plan`, `sys.query_store_runtime_stats`; forçar planos via `sp_query_store_force_plan` (os planos forçados persistem a reinicializações).
> - **Index Seek vs Scan**:
>   - *Seek* = Otimizador busca diretamente os ponteiros das linhas desejadas no índice (eficiente);
>   - *Scan* = Otimizador varre o índice inteiro da primeira à última página (lento em tabelas grandes).
> - Bloqueios (Blocking): Rastreamento via `sys.dm_exec_requests` (coluna blocked_by) e `sys.dm_os_waiting_tasks` ( wait_type, blocking_session_id).

---

## Planos de Execução (Execution Plans)

### Habilitando Planos de Execução via T-SQL

```sql
-- Plano Estimado (Estimated Plan - não executa a query física)
SET SHOWPLAN_XML ON;
GO
SELECT * FROM dbo.Orders WHERE CustomerId = 42;
GO
SET SHOWPLAN_XML OFF;

-- Plano Real (Actual Plan - executa a query física no banco)
SET STATISTICS XML ON;
GO
SELECT * FROM dbo.Orders WHERE CustomerId = 42;
GO
SET STATISTICS XML OFF;

-- No SSMS / Azure Data Studio: Ctrl+M ativa a exibição do Plano Real de forma gráfica.
```

### Operadores de Plano de Execução Comuns (Quadro Resumo)

| Operador | Significado Físico | O que monitorar |
| :--- | :--- | :--- |
| **Index Seek** | Busca pontual e seletiva no índice. | Excelente sinal de query otimizada. |
| **Index Scan** | Varredura completa do índice. | Revisar se a tabela for grande. |
| **Table Scan** | Varredura completa de Heap (tabela sem Clustered Index). | Adicione um Clustered Index à tabela. |
| **Key Lookup** | Busca de colunas extras no Clustered Index. | Adicione as colunas faltantes no `INCLUDE` do índice não-clusterizado. |
| **Hash Match** | Junção ou agrupamento de grande volume em memória hash. | Normal em Data Warehouses; perigoso sob baixa RAM. |
| **Nested Loops** | Junção iterativa linha por linha. | Muito eficiente se a entrada externa for pequena. |
| **Merge Join** | Junção de duas entradas ordenadas. | Excelente eficiência; requer ordenação física prévia. |
| **Sort** | Ordenação física de dados em memória. | Operação cara; avalie se um índice estruturado evita o SORT. |
| **Spill to TempDB** | Vazamento de dados temporários para o disco. | Ocorre quando a RAM do Memory Grant concedido é insuficiente. |

---

### Guia Intuitivo e Detalhado dos Operadores Físicos

Os **operadores físicos de execução** são os algoritmos reais executados pelo motor do SQL Server para ler dados, realizar junções, ordenar e calcular resultados. Entender o comportamento de cada operador é a chave para identificar gargalos de I/O, CPU e memória.

---

#### 1. Operadores Físicos Mais Comuns (Fundamentais)

##### 🟢 Acesso a Dados (Data Access Operators)

1. **Clustered Index Seek / Index Seek (Busca Direta em Índice)**
   - **Metáfora:** O índice remissivo no final do livro. Você vai direto para o capítulo e página exatos sem precisar folhear o livro todo.
   - **Como funciona:** O motor navega na estrutura da Árvore-B (*B-Tree*) a partir do nó raiz (*root*), descendo pelos nós intermediários até alcançar os nós folha (*leaf*) contendo os valores exatos especificados no predicado `WHERE`.
   - **Desempenho:** Extremamente rápido ($O(\log N)$). É o operador ideal para consultas pontuais em cargas OLTP.

2. **Clustered Index Scan / Index Scan / Table Scan (Varredura de Tabela/Índice)**
   - **Metáfora:** Ler um livro inteiro da primeira à última linha para encontrar a menção a uma palavra.
   - **Como funciona:** O motor lê **todas as páginas de dados** de um índice ou de uma Heap (tabela sem índice clusterizado), da primeira à última página.
   - **Desempenho:** Eficiente para tabelas pequenas ou relatórios que exigem ler 100% dos dados. **Péssimo** para buscas pontuais em tabelas com milhões de linhas (indica ausência de índice seletivo).

3. **Key Lookup / RID Lookup (Busca de Marcador no Índice)**
   - **Metáfora:** É como encontrar a referência no índice remissivo, mas precisar voltar à página original do livro porque o índice secundário só continha o título.
   - **Como funciona:** O índice usado encontrou as linhas, mas não contém todas as colunas solicitadas. O SQL Server precisa buscar os dados restantes no clustered index (`Key Lookup`) ou na Heap (`RID Lookup`).
   - **Solução:** Adicione as colunas necessárias à cláusula `INCLUDE` para criar um índice de cobertura. Veja os detalhes em [Tabelas e Índices](../01-database-objects/01-tables-indexes.md).

> [!tip] 💡 Diferenciais do Grupo: Acesso a Dados (Como Escolher / Identificar)
> - **`Index Seek` vs `Index Scan`:** O *Seek* é pontual (busca rápida via Árvore-B por chave); o *Scan* percorre as páginas do índice ou da tabela. Se o otimizador usar *Scan* para buscar 1 linha em uma tabela de 10 milhões, investigue seletividade, colunas retornadas, estimativas e índices; isso pode indicar um índice ausente, mas não é prova isolada.
> - **`Index Scan` vs `Table Scan`:** O *Index Scan* varre um índice (agrupado ou não); o *Table Scan* varre uma Heap (tabela sem chave primária/índice clusterizado).
> - **`Key Lookup` vs `RID Lookup`:** O *Key Lookup* busca dados no índice clusterizado (B-Tree); o *RID Lookup* busca dados em uma Heap (sem B-Tree) usando o identificador de linha `RowID`.
> - **`Key Lookup`:** Mostra que o índice secundário foi útil para encontrar a linha, mas **incompleto** para retornar todas as colunas da query. Se o custo do Lookup for alto, o otimizador pode desistir do Seek e forçar um *Table/Index Scan* direto na tabela inteira.

> [!note] Heaps, `Key Lookup` e `RID Lookup`
> O plano pode exibir `Table Scan` quando a tabela é uma Heap e não há caminho seletivo. A explicação estrutural de Heaps, RIDs, forwarding pointers e o uso adequado de tabelas sem clustered index está em [Tabelas e Índices](../01-database-objects/01-tables-indexes.md).

##### 🔵 Junções Físicas (Join Operators)

4. **Nested Loops Join (Junção por Laços Aninhados)**
   - **Metáfora:** Dois laços `FOR` aninhados no código (`for item in TabelaA: for match in TabelaB`).
   - **Como funciona:** Para cada linha individual lida da tabela externa (*Outer input*), o motor executa uma busca (*Seek*) na tabela interna (*Inner input*).
   - **Desempenho:** É a junção mais rápida do banco quando a tabela externa é pequena (poucas linhas) e a tabela interna possui um índice Seek direto.

5. **Hash Match Join (Junção por Hash)**
   - **Metáfora:** Montar uma tabela hash de dicionário em memória RAM com os elementos da primeira lista e depois passar a segunda lista comparando os hashes instantaneamente.
   - **Como funciona:** Opera em duas fases:
     1. *Build Phase:* Lê a menor tabela e monta uma tabela Hash na memória RAM.
     2. *Probe Phase:* Lê a segunda tabela e compara os valores com a tabela Hash na RAM.
   - **Desempenho:** Excelente para grandes volumes de dados não ordenados. Exige concessão de memória (*Memory Grant*). Se a RAM alocada for insuficiente, sofre **Spill para TempDB**.

6. **Merge Join (Junção por Mesclagem)**
   - **Metáfora:** Juntar duas listas de presença que já estão em ordem alfabética (basta percorrer as duas em paralelo avançando os ponteiros).
   - **Como funciona:** Lê as duas entradas simultaneamente e mescla os valores correspondentes.
   - **Desempenho:** O algoritmo de junção mais eficiente da CPU, mas exige que **ambas as entradas estejam previamente ordenadas** pela chave de junção.

7. **Adaptive Join (Junção Adaptativa)**
   - **Metáfora:** O câmbio automático do carro. Troca a marcha entre Nested Loops e Hash Join dinamicamente durante a viagem.
   - **Como funciona:** O otimizador agenda o operador mantendo um limiar de contagem de linhas. Se a leitura inicial trouxer poucas linhas, ele executa **Nested Loops**; se trouxer muitas linhas, ele alterna para **Hash Join**.

> [!tip] 💡 Diferenciais do Grupo: Junções Físicas (Quando o Motor Escolha Cada Um)
> - **`Nested Loops`**: Escolhido para **Conjuntos Pequenos** onde a tabela interna tem busca direta por índice ($O(N \log M)$). Custo de CPU e memória baixíssimo.
> - **`Merge Join`**: Escolhido quando **Ambas as Entradas Já Estão Ordenadas** (ex: por índices clusterizados nas chaves de join). Lê os dados linearmente ($O(N + M)$) sem gastar RAM de hash.
> - **`Hash Match`**: O "trator pesado" do motor. Escolhido para **Grandes Volumes Não Ordenados**. Exige alocação de memória RAM (*Memory Grant*) e corre risco de desacelerar gravando dados temporários no disco (*Spill no TempDB*).
> - **`Adaptive Join`**: Adia a decisão para o tempo de execução (runtime), trocando entre Loops e Hash dependendo do volume real lido na primeira entrada.

##### 🟣 Agregação e Ordenação (Aggregation & Sort)

8. **Stream Aggregate (Agregação em Fluxo)**
   - **Metáfora:** Contar moedas organizadas em pilhas separadas por valor enquanto elas passam na esteira.
   - **Como funciona:** Calcula agregações (`SUM`, `COUNT`, `AVG`, `GROUP BY`) em dados que já vêm ordenados pela chave do `GROUP BY`.
   - **Desempenho:** Extremamente rápido e não consome memória RAM adicional.

9. **Hash Match Aggregate (Agregação por Hash)**
   - **Metáfora:** Jogar moedas misturadas em recipientes etiquetados na mesa conforme vão chegando.
   - **Como funciona:** Cria buckets de hash na memória RAM para agrupar e somar valores de dados não ordenados.
   - **Desempenho:** Usado para agregações em grandes volumes. Pode estourar **Spill no TempDB** se a memória RAM reservada for insuficiente.

10. **Sort (Ordenação Física)**
    - **Metáfora:** Reordenar um maço de cartas completamente misturado antes de entregar o jogo.
    - **Como funciona:** Reordena fisicamente o conjunto de dados na memória RAM para atender a um `ORDER BY`, `GROUP BY` ou preparar a entrada para um `Merge Join`.
    - **Desempenho:** É um operador bloqueante (*stop-and-wait*). Ele deve ler 100% das linhas de entrada antes de liberar a primeira linha de saída. É uma operação cara de CPU e memória.

> [!tip] 💡 Diferenciais do Grupo: Agregação e Ordenação
> - **`Stream Aggregate` vs `Hash Aggregate`:** O *Stream Aggregate* exige dados **previamente ordenados** (consumo de RAM zero); o *Hash Aggregate* processa dados **não ordenados** criando tabelas de hash na memória (consumo de RAM alto).
> - **`Sort`:** É um dos operadores mais caros do banco. Se uma query usa `Sort` para ordenar dados gigantes, avalie criar um índice cuja chave já esteja na ordem do `ORDER BY` ou `GROUP BY` desejado, eliminando o operador `Sort` do plano.

---

#### 2. Operadores Físicos Intermediários e Avançados

##### 🟡 Paralelismo e Distribuição de Fluxo (Parallelism Operators)

11. **Gather Streams (Reunir Fluxos)**
    - **Como funciona:** Agrupa os resultados processados em paralelo por múltiplas threads de CPU e os consolida em uma única thread serial no topo do plano.
12. **Repartition Streams (Redistribuir Fluxos)**
    - **Como funciona:** Redistribui e re-balanceia as linhas entre as threads de CPU ativas para otimizar a distribuição de carga paralela.

> [!tip] 💡 Diferenciais do Grupo: Paralelismo
> - **`Gather Streams`:** É o nó de fechamento do paralelismo (transição N Threads -> 1 Thread).
> - **`Repartition Streams`:** É o nó de redistribuição entre threads ativas (transição N Threads -> N Threads) para evitar que 1 core de CPU fique sobrecarregado enquanto outros ficam ociosos.

##### 🟠 Operadores de Filtro e Transformação

13. **Compute Scalar (Calcular Escalar)**
    - **Como funciona:** Executa uma função ou cálculo matemático/lógico linha a linha (ex: `Preco * Quantidade`, concatenação de strings ou conversão de tipos `CAST`). É um operador extremamente leve.
14. **Filter (Filtro)**
    - **Como funciona:** Avalia um predicado adicional de filtro nas linhas que não pôde ser resolvido diretamente no operador inicial de busca do índice.
15. **Concatenation (Concatenação / UNION ALL)**
    - **Como funciona:** Combina dois ou mais fluxos de entrada em um único fluxo contínuo (comportamento clássico de um `UNION ALL`).
16. **Top / Top N Sort (Limitação e Ordenação Parcial)**
    - **Top:** Limita a quantidade de linhas transmitidas (`TOP (N)`).
    - **Top N Sort:** Em vez de ordenar a tabela inteira na memória, mantém um pequeno buffer interno apenas com as top N linhas desejadas, reduzindo imensamente o consumo de RAM.

##### 🔴 Operadores Avançados, Batch Mode e Spools

17. **Columnstore Index Scan / Filter (Modo Batch)**
    - **Como funciona:** Processa dados em colunas vetoriais compactadas em blocos de até 900+ linhas por lote (*Batch Mode*), utilizando instruções SIMD de CPU modernas.
18. **Segment Skip / Online (Eliminação de Segmentos)**
    - **Como funciona:** Lê os metadados dos blocos de um índice Columnstore (valores Mínimo e Máximo) e ignora/pula segmentos inteiros de dados que não contêm os valores buscados, sem ler o disco.
19. **Bitmap Filter (Filtro Bitmap)**
    - **Como funciona:** Cria uma máscara de bits na fase de construção de um *Hash Join* e a injeta diretamente na árvore de busca da outra tabela, descartando linhas incompatíveis antes mesmo do join ser processado.
20. **Table Spool / Index Spool / Lazy Spool / Eager Spool (Carretel no TempDB)**
    - **Como funciona:** Salva temporariamente resultados intermediários de uma query no `tempdb` para reutilização em subqueries correlacionadas, CTEs recursivas ou atualizações complexas.
    - **Alerta:** Spools em excesso indicam que o otimizador está com dificuldades para estimar cardinalidade ou criando estruturas temporárias custosas.

> [!tip] 💡 Diferenciais do Grupo: Batch Mode vs Spools
> - **Columnstore Batch Mode:** Focado em **alta performance analítica** (processamento vetorial em memória sem travar linha a linha).
> - **Spools no TempDB:** Salvam tabelas temporárias físicas no disco do `tempdb`. Spools em consultas normais (não-recursivas) sinalizam estimativas imprecisas ou necessidade de refatoração T-SQL.

---

### Entendendo o Conceito de Data Spill (Spill para TempDB)

O **Data Spill (ou TempDB Spill)** é um dos eventos de degradação mais severos em planos de execução do SQL Server e Azure SQL.

#### 1. A Metáfora do Copo D'água Transbordando
- **Concessão de Memória (*Memory Grant*):** Antes de executar uma consulta, o otimizador lê as estatísticas das tabelas e calcula a quantidade exata de memória RAM necessária para processar operadores em memória (como `Sort`, `Hash Match Join` e `Hash Match Aggregate`). Esse valor reservado na RAM é o *Memory Grant* (o "copo" de memória).
- **O Spill (O Transbordo):** Se durante a execução física o volume real de dados processados for muito maior que o espaço reservado no "copo" de RAM, o operador transborda (*spills*). O motor é obrigado a gravar e ler os dados excedentes no disco, utilizando o banco de dados temporário **`tempdb`**.

#### 2. Os Operadores Suscetíveis a Spill
- **Sort Warning / Sort Spill:** Ocorre quando o operador `Sort` descobre em tempo de execução que a quantidade de dados a ordenar é maior do que o *Memory Grant* reservado na RAM.
- **Hash Warning / Hash Spill:** Ocorre durante a fase de construção (*Build*) ou investigação (*Probe*) de um `Hash Match` quando a tabela Hash na RAM estoura a memória alocada, sendo forçada a gravar partições temporárias no `tempdb`.

#### 3. Causas Raiz do Data Spill
1. **Subestimativa de Cardinalidade (Estatísticas Desatualizadas ou Amostragem Imprecisa):**
   - O otimizador lê estatísticas antigas e estima que a query retornará apenas **100 linhas**, alocando 1 MB de RAM.
   - Na prática, a consulta retorna **5.000.000 de linhas** (exigindo 500 MB). O excesso de 499 MB é descarregado no disco do `tempdb`.
2. **Uso de Variáveis de Tabela (`@TableVariable`):**
   - Variáveis de tabela não mantêm estatísticas tradicionais; em versões anteriores ou sem compilação adiada, isso podia produzir estimativas muito baixas e uma concessão de RAM pequena.
3. **Parameter Sniffing:**
   - O plano foi compilado originalmente para um parâmetro que trazia 10 linhas (RAM pequena) e reutilizado para uma chamada com parâmetro de 10 milhões de linhas.

#### 4. Impacto Severo de Desempenho
- Acesso à memória RAM opera na escala de **nanossegundos**.
- Acesso a I/O de disco no `tempdb` opera na escala de **milissegundos** (milhares de vezes mais lento).
- Um Data Spill faz uma consulta de 100ms demorar **mais de 30 segundos**, saturando os discos do servidor e gerando contenção de páginas de alocação no `tempdb` (PFS/GAM/SGAM).

> [!important] Identificando Spills no SSMS / Azure Data Studio
> No plano de execução gráfico, os nós de `Sort` ou `Hash Match` afetados por Spills exibem um **ícone de alerta de triângulo amarelo com ponto de exclamação** (`⚠️ Warning: Spill to TempDB`). Nas propriedades do operador XML, constam as métricas `SpillLevel` e `SpillThreadCount`.

#### 5. Como Resolver o Data Spill?
- **Atualizar Estatísticas com `FULLSCAN`:** Garante estimativas de cardinalidade corretas para que o otimizador calcule a concessão de memória RAM ideal na compilação.
- **Memory Grant Feedback (SQL Server 2017+ / Azure SQL):** Recurso de processamento adaptativo que detecta Spills e ajusta dinamicamente a concessão de RAM nas execuções seguintes da consulta.
- **Eliminar Operadores `Sort` Desnecessários:** Criar índices cujas chaves já estejam na ordem solicitada pelo `ORDER BY` ou `GROUP BY`.
- **Substituir Variáveis de Tabela por Tabelas Temporárias (`#TempTable`).**

---

### Analisando Percentuais de Custo no Plano

Os percentuais de custo exibidos sobre os nós nos planos gráficos (SSMS, Azure Data Studio e Query Store) indicam o consumo relativo estimado de recursos (CPU e I/O) para cada etapa da consulta:

1. **`Table Scan` / `Index Scan` com Custo Elevado (ex: 80%+ do plano):** Indica que o otimizador está varrendo a tabela inteira por ausência de um índice seletivo.
2. **`Key Lookup` com Custo Elevado (ex.: parcela relevante do plano):** Indica que o índice secundário foi utilizado para localizar as linhas, mas a consulta exige colunas adicionais da tabela base. **Possível solução:** avaliar as colunas solicitadas na cláusula `INCLUDE` de um índice não clusterizado (*Covering Index*), comparando o custo de manutenção e o plano resultante.
3. **Operadores de `Sort` Pesados:** Indicam que o motor precisa reordenar dados em memória porque nenhum índice existente satisfaz a ordem do `ORDER BY` ou `GROUP BY`. **Solução:** Criar um índice com as chaves ordenadas na mesma sequência da consulta.
4. **`Hash Match` com Alertas de Spill (⚠️):** Indicam estimativas de cardinalidade incorretas decorrentes de estatísticas desatualizadas ou ausentes, forçando o vazamento de memória RAM para o `tempdb`. **Solução:** Atualizar estatísticas com `FULLSCAN`.

---

## Diagnóstico usando Views de Gerenciamento Dinâmico (DMVs)

### Identificando Queries com Maior Consumo

```sql
-- Listar as 10 queries com maior consumo total de CPU (Worker Time)
SELECT TOP 10
    total_worker_time / execution_count AS avg_cpu_us,
    total_worker_time AS total_cpu_us,
    execution_count,
    total_elapsed_time / execution_count AS avg_duration_us,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
         ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY avg_cpu_us DESC;

-- Listar queries com maior número de leituras lógicas em memória (Logical Reads)
SELECT TOP 10
    total_logical_reads / execution_count AS avg_reads,
    total_logical_reads,
    execution_count,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 200) AS query_snippet
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY avg_reads DESC;
```

### Consultando Recomendações de Índices Ausentes

```sql
-- Identificar índices recomendados pelo otimizador baseados em buscas reais
SELECT TOP 10
    ROUND(s.avg_total_user_cost * s.avg_user_impact * (s.user_seeks + s.user_scans), 0) AS ImpactScore,
    d.equality_columns,
    d.inequality_columns,
    d.included_columns,
    OBJECT_NAME(d.object_id) AS TableName
FROM sys.dm_db_missing_index_details d
JOIN sys.dm_db_missing_index_groups g ON g.index_handle = d.index_handle
JOIN sys.dm_db_missing_index_group_stats s ON s.group_handle = g.index_group_handle
WHERE d.database_id = DB_ID()
ORDER BY ImpactScore DESC;
```

### Consultando Estatísticas de Espera Globais (Wait Stats)

```sql
-- Listar os maiores tipos de esperas ativas no servidor SQL (Excluindo filtros ociosos)
SELECT TOP 10
    wait_type,
    wait_time_ms / 1000.0 AS wait_time_sec,
    100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS pct
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN ('SLEEP_TASK','BROKER_TO_FLUSH','CLR_AUTO_EVENT',
    'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
    'HADR_WORK_QUEUE','ONDEMAND_TASK_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH',
    'RESOURCE_QUEUE','SERVER_IDLE_CHECK','SLEEP_DBSTARTUP',
    'SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY','SLEEP_MASTERMDREADY',
    'SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP','SLEEP_TEMPDBSTARTUP',
    'SNI_HTTP_ACCEPT','SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'WAITFOR','XE_DISPATCHER_WAIT','XE_TIMER_EVENT')
ORDER BY wait_time_ms DESC;
```

---

## Query Store (Repositório de Consultas)

O Query Store grava e retém estatísticas de execução persistentes de queries e seus planos físicos de forma estruturada.

```sql
-- Ativar e parametrizar o Query Store no banco
ALTER DATABASE MyDB SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,
    MAX_STORAGE_SIZE_MB = 1000,
    INTERVAL_LENGTH_MINUTES = 60,
    SIZE_BASED_CLEANUP_MODE = AUTO,
    DATA_FLUSH_INTERVAL_SECONDS = 900
);

-- Localizar queries com regressão de planos (Queries com piora de performance recente)
SELECT TOP 10
    qsq.query_id,
    qsqt.query_sql_text,
    qsp.plan_id,
    qsrs.avg_cpu_time / 1000.0 AS avg_cpu_ms,
    qsrs.avg_duration / 1000.0 AS avg_duration_ms,
    qsrs.count_executions
FROM sys.query_store_query qsq
JOIN sys.query_store_query_text qsqt ON qsqt.query_text_id = qsq.query_text_id
JOIN sys.query_store_plan qsp ON qsp.query_id = qsq.query_id
JOIN sys.query_store_runtime_stats qsrs ON qsrs.plan_id = qsp.plan_id
ORDER BY qsrs.avg_cpu_time DESC;

-- Forçar o motor SQL a usar um plano de execução bom conhecido (plan_id = 3)
EXEC sp_query_store_force_plan @query_id = 1, @plan_id = 3;

-- Desfazer a instrução de forçar o plano
EXEC sp_query_store_unforce_plan @query_id = 1, @plan_id = 3;
```

> [!warning] Erro Comum
> O cache de planos padrão do servidor (`sys.dm_exec_cached_plans`) é volátil e se limpa em reinicializações e sob pressão de memória. O Query Store armazena dados persistidos de planos físicos em disco. Se a questão de exame exigir histórico de performance sobrevivendo a restarts, utilize o Query Store.

---

## Query Performance Insight (Azure SQL Database)

O portal do Azure fornece um dashboard amigável com gráficos consolidados dos dados retidos pelo Query Store:

```text
Azure Portal → Azure SQL Database → Intelligent Performance → Query Performance Insight
→ Filtros de Visualização: Top CPU / Top Data IO / Top Log IO
→ Clique em queries específicas para listar os planos de execução físicos e recomendações
```

---

## Forçando Planos e Guias de Planos (Plan Guides)

### sp_query_store_force_plan

Esta procedure força o uso de um plano específico em tempo de execução. O plano forçado persiste no banco de dados mesmo após reinicializações. O status de planos forçados pode ser monitorado na coluna `is_forced_plan` da tabela `sys.query_store_plan`.

### Guias de Planos (Plan Guides)

Os **Plan Guides** permitem anexar dicas de otimização (query hints) a queries específicas sem a necessidade de modificar fisicamente a string SQL de código das aplicações. Útil para queries geradas dinamicamente por ferramentas de ORM (como Entity Framework ou Hibernate), sistemas legados ou softwares terceiros.

```sql
-- Criar um Plan Guide associando Hints a uma query externa de aplicação
EXEC sp_create_plan_guide
    @name = N'PG_GetOrders',
    @stmt = N'SELECT * FROM Orders WHERE CustomerID = @CustID',
    @type = N'SQL',
    @module_or_batch = NULL,
    @params = N'@CustID int',
    @hints = N'OPTION (OPTIMIZE FOR (@CustID UNKNOWN))';

-- Verificar as guias de planos registradas no banco
SELECT name, scope_type_desc, is_disabled
FROM sys.plan_guides
WHERE name = N'PG_GetOrders';

-- Remover uma guia de planos cadastrada
EXEC sp_control_plan_guide N'DROP', N'PG_GetOrders';
```

> [!warning] Dica de Exame: Sensibilidade de Texto no Plan Guide
>
> - As correspondências de texto para Plan Guides são extremamente rígidas. O SQL Server diferencia letras maiúsculas/minúsculas, quebras de linhas e espaços em branco.
> - Se o texto passado no Plan Guide não for **exatamente igual** (caractere por caractere) à query enviada pela aplicação (ex: um ORM), o Plan Guide será sumariamente ignorado. Utilize a função `sys.fn_validate_plan_guide` para verificar e debugar.

Tipos de Plan Guides:

| Tipo | Casos de Uso |
| :--- | :--- |
| `SQL` | Instruções ad-hoc parametrizadas livres. |
| `OBJECT` | Queries internas embutidas em stored procedures ou triggers. |
| `TEMPLATE` | `Queries parametrizadas de forma automática pelo banco (esquema template)`. |

---

## Mitigação de Parameter Sniffing (Snifagem de Parâmetros)

O **parameter sniffing** ocorre quando o SQL Server compila uma stored procedure gerando um plano otimizado especificamente para os parâmetros recebidos na primeira chamada, salvando esse plano em cache. Se as próximas execuções utilizarem parâmetros com distribuições de dados muito diferentes, o plano herdado pode performar de forma ineficiente.

### OPTION(RECOMPILE)

Força o SQL Server a gerar e compilar um plano novo de execução a cada chamada da query, baseando-se nos valores exatos atuais dos parâmetros.

```sql
CREATE PROCEDURE dbo.GetOrdersByDate
    @StartDate DATE,
    @EndDate DATE
AS
    SELECT * FROM dbo.Orders
    WHERE OrderDate BETWEEN @StartDate AND @EndDate
    OPTION (RECOMPILE); -- Plano novo gerado a cada execução
```

### OPTION(OPTIMIZE FOR UNKNOWN)

Compila um plano estável baseado nas densidades médias das estatísticas do índice, ignorando o valor específico de chamada do parâmetro na compilação física.

```sql
CREATE PROCEDURE dbo.GetCustomerOrders
    @CustomerID INT
AS
    SELECT * FROM dbo.Orders
    WHERE CustomerID = @CustomerID
    OPTION (OPTIMIZE FOR (@CustomerID UNKNOWN));
```

> [!tip] Quando Usar RECOMPILE vs OPTIMIZE FOR UNKNOWN
>
> - **`OPTION(RECOMPILE)`**: Compila um plano fresco a cada execução. Use apenas em queries com distribuições de dados extremamente desiguais (skewed) que rodam raramente. Evite em queries de alta frequência para não saturar a CPU.
> - **`OPTION(OPTIMIZE FOR UNKNOWN)`**: Compila um único plano estável baseado nas estatísticas de densidade média do índice. Evita o sniffing de parâmetros sem gerar overhead de compilação constante.

### Variável de Escopo Local

Atribuir os parâmetros a variáveis locais quebra a inteligência de sniffing do compilador (o otimizador não vê o valor das variáveis internas no momento da montagem inicial do plano), forçando o uso de estatísticas padrão médias.

```sql
CREATE PROCEDURE dbo.GetOrdersByRegion
    @RegionID INT
AS
    DECLARE @LocalRegion INT = @RegionID; -- quebra o sniffing
    SELECT * FROM dbo.Orders
    WHERE RegionID = @LocalRegion;
```

### Processamento Adaptativo de Consultas (SQL Server 2017+)

- **Execução intercalada**: reestima funções com valor de tabela de múltiplas instruções em tempo de execução.
- **Junções adaptativas em modo batch**: alterna entre Hash Join e Nested Loops com base na quantidade real de linhas.
- **Memory grant feedback**: ajusta as concessões de memória após a primeira execução com base no uso real.

#### Junções Adaptativas (Adaptive Joins)

Uma junção adaptativa adia a escolha entre **Hash Join** e **Nested Loops** até que a primeira entrada tenha sido lida. O operador mantém um limiar de quantidade de linhas no plano de execução:

- Se a entrada de construção ficar abaixo do limiar, o plano usa **Nested Loops**, normalmente mais eficiente para poucas linhas.
- Se a entrada ultrapassar o limiar, o plano continua com **Hash Join**, normalmente mais eficiente para muitas linhas.

Essa decisão em tempo de execução permite que o mesmo plano em cache se adapte a cargas que alternam entre conjuntos pequenos e grandes, sem recompilação nem alteração de código. A junção adaptativa pode solicitar mais memória do que um plano equivalente de Nested Loops com índice, pois precisa estar preparado também para o caminho de Hash Join.

O recurso está disponível em modo batch a partir do SQL Server 2017, com nível de compatibilidade 140. No plano de execução real, ele aparece como o operador `Adaptive Join`.

> **Resumo para o exame:** O SQL Server decide durante a execução usando o limiar do operador
> - **Nested Loops** →  poucas linhas
> - **Hash Join** → muitas linhas

---

## Manutenção de Estatísticas do Banco

As estatísticas armazenam histogramas detalhados da distribuição dos valores das colunas e chaves de índices. O otimizador de consultas as lê para estimar a cardinalidade de linhas e escolher caminhos de buscas.

---

### Quando e Como são Criadas Novas Estatísticas?

O SQL Server cria **novas estatísticas** (histogramas e matrizes de densidade) através de três mecanismos principais:

1. **Criação Automática por Índices (`CREATE INDEX` - Estatísticas de Índice):**
   - Sempre que um índice (clusterizado ou não-clusterizado) é criado, o SQL Server gera **automaticamente** um objeto de estatística com o mesmo nome do índice.
   - Ela armazena o histograma detalhado da primeira coluna do índice e os vetores de densidade para todas as combinações de chaves.
   - *Nota Importante:* Essas estatísticas atreladas a índices não podem ser removidas com `DROP STATISTICS`; são destruídas apenas quando o índice for excluído (`DROP INDEX`).

2. **Criação Automática por Consultas (`AUTO_CREATE_STATISTICS` - Coluna Única):**
   - Com `AUTO_CREATE_STATISTICS ON` (ativado por padrão no banco), quando uma consulta executa um predicado (`WHERE`, `JOIN`, `GROUP BY`, `HAVING`) usando uma coluna que **ainda não possui estatísticas**, o otimizador gera **automaticamente** uma estatística de coluna única na compilação.
   - O nome das estatísticas automáticas de coluna normalmente usa o prefixo **`_WA_Sys_`** (ex: `_WA_Sys_00000002_178D7908`).

3. **Criação Manual Explícita (`CREATE STATISTICS` - Multicolunas e Filtradas):**
   - DBAs e desenvolvedores criam estatísticas manualmente para cobrir cenários onde o automático de coluna única é insuficiente:
     - **Estatísticas Multicolunas:** Criadas para consultas que filtram múltiplas colunas correlacionadas simultaneamente (ex: `WHERE Country = 'BR' AND State = 'SP'`). Fornecem a densidade combinada exata das colunas:
       ```sql
       CREATE STATISTICS stat_Country_State ON dbo.Customers(Country, State);
       ```
     - **Estatísticas Filtradas (*Filtered Statistics*):** Criadas com uma cláusula `WHERE` para otimizar subconjuntos de dados específicos (ex: apenas registros ativos), reduzindo o tamanho do histograma:
       ```sql
       CREATE STATISTICS stat_Active_Orders ON dbo.Orders(OrderDate) WHERE Status = 'Active';
       ```

> [!important] Cuidado no Exame: Objetos que NÃO Geram Estatísticas
> - **Variáveis de Tabela (`@TableVariable`):** O SQL Server **não mantém estatísticas tradicionais** para variáveis de tabela. Em versões e níveis de compatibilidade anteriores, isso podia levar a estimativas fixas muito baixas; no nível de compatibilidade 150, a compilação adiada pode usar a cardinalidade observada na primeira compilação. Para volumes maiores, avalie `#TempTable` ou `OPTION(RECOMPILE)` conforme o caso.
> - **Tabelas Temporárias (`#TempTable`):** Tabelas temporárias reais com `#` **geram** estatísticas automáticas normalmente no `tempdb`.

---

### Limiares de Atualização Automática (Auto-Update Stats)

- **Tabelas menores** (menos de 500 registros): As estatísticas são atualizadas automaticamente após ocorrerem 500 alterações na tabela.
- **Tabelas maiores**: Em compatibilidade 120 ou inferior, o limiar histórico é `500 + 20%` das linhas.
- **Compatibilidade 130 ou superior**: O SQL Server usa limiar dinâmico decrescente, `MIN(500 + 20% das linhas, SQRT(1000 * linhas))`, atualizando estatísticas de tabelas grandes com mais frequência. A trace flag 2371 é relevante apenas para cenários anteriores.

```sql
-- Consultar estado e data de última atualização de estatísticas de uma tabela
SELECT OBJECT_NAME(s.object_id) AS TableName,
       s.name AS StatName,
       sp.last_updated,
       sp.rows,
       sp.rows_sampled,
       sp.modification_counter
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECT_NAME(s.object_id) = 'Orders'
ORDER BY sp.last_updated;

-- Atualizar estatísticas de forma manual forçando escaneamento total (FULLSCAN)
UPDATE STATISTICS dbo.Orders WITH FULLSCAN;

-- Atualizar estatísticas de todo o banco de dados (Amostragem padrão)
EXEC sp_updatestats;
```

O valor de `modification_counter` indica a quantidade de alterações ocorridas na coluna principal desde a última atualização das estatísticas. Valores altos indicam estatísticas desatualizadas (*stale stats*).

---

### Como Calcular e Escolher o Tamanho da Amostra (FULLSCAN vs SAMPLE)

Ao executar a manutenção manual de estatísticas via `UPDATE STATISTICS`, você pode controlar a quantidade de linhas lidas pelo motor através das opções:
- **`FULLSCAN`**: Lê 100% das linhas ($100\%$).
- **`SAMPLE N PERCENT`**: Lê a porcentagem $N\%$ especificada das linhas (ex: `SAMPLE 25 PERCENT`).
- **`SAMPLE N ROWS`**: Lê a quantidade exata $N$ de linhas (ex: `SAMPLE 2000000 ROWS`).
- **Default Sampling (Sem Parâmetro)**: O SQL Server calcula dinamicamente o tamanho da amostra.

#### 1. Como o SQL Server Calcula a Amostragem Padrão (Default Sampling)?

Quando o `AUTO_UPDATE_STATISTICS` executa ou quando você roda `UPDATE STATISTICS` sem especificar o tamanho da amostra, o SQL Server calcula a amostra dinamicamente. Como regra prática, tabelas pequenas podem acabar sendo lidas integralmente quando isso for barato, mas o tamanho exato não deve ser tratado como um limiar contratual:
- **Tabelas Pequenas:** O motor pode realizar **`FULLSCAN` (100%)** quando a varredura completa for barata.
- **Tabelas Médias e Grandes:** O SQL Server normalmente utiliza uma amostra calculada pelo otimizador:
  - Quanto **maior** o número de linhas da tabela, **menor é a porcentagem** de linhas lidas na amostragem padrão.
  - Em tabelas muito grandes, a porcentagem efetiva pode ser pequena; não existe uma taxa padrão fixa aplicável a todos os bancos.
  - **Pró:** Leitura ultra-rápida sem impacto de CPU/disco.
  - **Contra:** Em tabelas com distribuição desigual de dados (*Data Skew*), amostrar apenas 1% pode ignorar valores raros ou concentrados, gerando histogramas imprecisos e planos de execução ruins.

#### 2. Guia de Decisão: Quando usar FULLSCAN vs SAMPLE?

| Tipo de Tabela / Cenário | Recomendação de Amostragem | Comando T-SQL Recomendado | Racional Técnico |
| :--- | :--- | :--- | :--- |
| **Tabelas de Dimensão / Médias** | **Considere `FULLSCAN` (100%) quando houver benefício comprovado** | `UPDATE STATISTICS dbo.Orders WITH FULLSCAN;` | Pode melhorar a informação do histograma, ao custo de mais leitura e compilação. |
| **Tabelas Grandes com *Data Skew*** | **Considere aumentar a amostra ou usar `FULLSCAN` após medir o problema** | `UPDATE STATISTICS dbo.Sales WITH FULLSCAN;` | Distribuições muito desiguais podem se beneficiar de uma amostra maior, mas a decisão depende do plano e da carga. |
| **Após `ALTER INDEX REBUILD`** | **Verifique o tipo de índice e a partição** | Executado como efeito do `REBUILD` | Em índices rowstore não particionados, a estatística do índice é atualizada com varredura completa; cenários particionados podem usar a amostragem padrão. |
| **Tabelas Gigantes de Fatos** | **Escolha uma amostra maior apenas após medir o custo e a qualidade das estimativas** | `UPDATE STATISTICS dbo.FactSales WITH SAMPLE 25 PERCENT;` | `FULLSCAN` pode ser caro; o percentual deve ser ajustado ao volume, à distribuição e ao plano observado. |

#### 3. Como Calcular a Porcentagem Ideal para Tabelas Gigantes?

Para tabelas gigantes onde o `FULLSCAN` é inviável pelo tempo de execução, use os números abaixo apenas como ponto de partida para um teste controlado:

1. **Diagnóstico:** Verifique `sp.rows_sampled` na DMV `sys.dm_db_stats_properties` e compare a estimativa com a execução real. Uma amostra menor não significa, por si só, que a amostragem falhou.
2. **Teste da Amostra Alvo:**
   - Os percentuais de **20–30%** e **10–20%** podem ser usados como exemplos de teste para tabelas de tamanhos diferentes, mas não são limiares prescritos pelo SQL Server.
   - Compare também `SAMPLE N ROWS`, custo da atualização e qualidade do plano antes de adotar uma configuração.

#### 4. Fixando a Amostragem com `PERSIST_SAMPLE_PERCENT = ON` (SQL Server 2016 SP1+)

Se um DBA definir manualmente um `UPDATE STATISTICS ... WITH SAMPLE 30 PERCENT`, uma atualização automática futura poderá usar outra taxa de amostragem, caso a porcentagem não seja persistida.

Para evitar isso, utilize a cláusula **`PERSIST_SAMPLE_PERCENT = ON`**:

```sql
-- Garante que todas as atualizações futuras (sejam manuais ou do AUTO_UPDATE automático)
-- mantenham a amostragem de 30% fixada
UPDATE STATISTICS dbo.FactSales
WITH SAMPLE 30 PERCENT, PERSIST_SAMPLE_PERCENT = ON;

-- Para reverter e voltar ao padrão automático dinâmico:
UPDATE STATISTICS dbo.FactSales
WITH PERSIST_SAMPLE_PERCENT = OFF;
```

#### 5. Entendendo o Impacto do Data Skew (Distribuição Desigual de Dados)

O **Data Skew (Inclinabilidade / Distribuição Desigual de Dados)** ocorre quando uma coluna possui valores distribuídos de forma desproporcional.

##### 📌 Exemplo Prático de Data Skew:
Em uma tabela de 50 milhões de pedidos (`Orders`), a coluna `StatusID` possui os seguintes dados:
- **`StatusID = 1` ("Entregue"):** 49.500.000 linhas ($99\%$).
- **`StatusID = 2` ("Em Trânsito"):** 450.000 linhas ($0.9\%$).
- **`StatusID = 3` ("Suspeita de Fraude"):** 50.000 linhas ($0.1\%$).

##### 💥 Exemplo hipotético de amostragem insuficiente:
Suponha, apenas para ilustrar o risco, que uma atualização automática use uma amostra de 1% (500.000 linhas) nessa tabela:
1. Por azar amostral, a varredura aleatória pode capturar apenas 2 linhas de `StatusID = 3` ("Fraude").
2. O histograma poderá representar mal a frequência de `StatusID = 3`, levando a uma estimativa inferior à quantidade real.
3. Nesse cenário, o otimizador poderá escolher um plano com **`Nested Loops`** e **`Key Lookup`** que não seja adequado para as 50.000 linhas reais.
4. **Impacto possível:** muitos *Key Lookups* podem aumentar bastante o I/O e a CPU. A duração final depende do plano, dos índices, do cache e do hardware.

##### 🛡️ As 2 Soluções Recomendadas para Data Skew:

1. **Forçar `FULLSCAN` (100% de Amostragem):**
   ```sql
   UPDATE STATISTICS dbo.Orders(IX_Orders_StatusID) WITH FULLSCAN, PERSIST_SAMPLE_PERCENT = ON;
   ```
   *Racional:* Ao ler 100% das linhas, o histograma recebe a informação mais completa possível sobre os valores raros (`StatusID = 3`). O plano escolhido ainda depende de índices, predicados, cardinalidade e custos estimados.

2. **Criar Estatísticas Filtradas (*Filtered Statistics*):**
   Se rodar `FULLSCAN` na tabela inteira for pesado demais pelo tamanho do banco, crie uma estatística dedicada cobrindo apenas o valor raro/desproporcional:
   ```sql
   CREATE STATISTICS stat_Orders_Fraud
   ON dbo.Orders(StatusID)
   WHERE StatusID = 3;
   ```
   *Racional:* Concentra as estatísticas no subconjunto relevante e pode melhorar a estimativa sem exigir a mesma leitura da tabela inteira; não constitui garantia de 100% de precisão em todos os planos.

---

### Quando Manter no Automático (Default e Modo Assíncrono)

As opções `AUTO_CREATE_STATISTICS ON` e `AUTO_UPDATE_STATISTICS ON` vêm habilitadas por padrão no SQL Server e no Azure SQL.

- **Quando manter ativado:** Na **imensa maioria dos bancos de dados e aplicações OLTP de uso geral**. O motor cria e atualiza estatísticas automaticamente à medida que os dados mudam, garantindo estimativas razoáveis sem intervenção humana diária.
- **Modo Assíncrono (`AUTO_UPDATE_STATISTICS_ASYNC ON`):**
  - **Quando usar:** Em sistemas OLTP de altíssima frequência de transações e baixíssima tolerância a picos de latência.
  - **Como funciona:** Quando uma query atinge o limiar de alteração de estatística, o modo síncrono tradicional força a consulta a esperar a atualização ser concluída antes de rodar. No modo **Assíncrono**, a consulta executa imediatamente utilizando a estatística antiga, enquanto uma thread em segundo plano atualiza a estatística para as próximas execuções.

---

### Quando Executar Manutenção Manual (UPDATE STATISTICS)

A atualização automática utiliza uma **amostragem dinâmica (sample rate)** que pode se tornar insuficiente em tabelas grandes ou com distribuição desigual de dados. A manutenção manual agendada (via Jobs noturnos ou semanais) deve ser executada nos seguintes cenários:

1. **Após Cargas Massivas de Dados (ETL / Bulk Insert / Migrações):**
   - Inseriu ou atualizou grandes volumes via `BULK INSERT`, `bcp` ou pipelines do Azure Data Factory. Execute imediatamente `UPDATE STATISTICS dbo.Tabela WITH FULLSCAN` antes que relatórios e procedimentos comecem a ser executados com planos ruins baseados no histórico antigo.
2. **Após Reorganização de Índices (`ALTER INDEX REORGANIZE`):**
   - O comando `REORGANIZE` **não atualiza estatísticas**! (Ao contrário do `ALTER INDEX REBUILD`, que atualiza estatísticas com `FULLSCAN` automaticamente). É necessário rodar `UPDATE STATISTICS` após um `REORGANIZE`.
3. **Tabelas Gigantes com Distribuição Desigual (Data Skew):**
   - Quando a amostragem pequena do `AUTO_UPDATE` (ex: 1% das linhas) não reflete a realidade de colunas com valores altamente concentrados. Execute rotinas manuais com `WITH FULLSCAN` ou `WITH SAMPLE X PERCENT`.
4. **Variáveis de Tabela (`@TableVariable`):**
   - Variáveis de tabela não mantêm estatísticas tradicionais. Em compatibilidade 150, a compilação adiada pode melhorar a estimativa; para cenários que exigem estatísticas completas, avalie `#TempTables` ou `OPTION (RECOMPILE)`.

---

### Quando Desligar a Atualização Automática (Exceções Cirúrgicas)

Desabilitar a atualização automática no banco de dados inteiro é **altamente desencorajado**. No entanto, desligar de forma cirúrgica (em nível de tabela ou estatística específica) é recomendado em exceções muito específicas:

1. **Tabelas Gigantes de Carga Contínua (Evitar Locks / Timeouts em Pico):**
   - Em tabelas de fatos com centenas de milhões de linhas, o disparo síncrono do `AUTO_UPDATE_STATISTICS` no horário de pico pode fazer com que a query que o disparou sofra *timeout* enquanto tenta compilar a estatística de milhões de registros.
   - **Mitigação:** Desabilitar o auto-update apenas nas estatísticas dessa tabela específica:
     ```sql
     EXEC sys.sp_autostats N'dbo.SalesFact', 'OFF';
     ```
     *(E manter obrigatoriamente um Job noturno agendado de `UPDATE STATISTICS WITH FULLSCAN` fora do horário de pico).*
2. **"Congelar" uma Estatística Específica para Preservar um Plano Estável (Freeze Stats):**
   - Uma estatística específica foi calculada com `FULLSCAN` gerando o plano perfeito. Para evitar que o `AUTO_UPDATE` automático a substitua por uma amostragem menor que degrade o plano de execução, desativa-se o auto-update apenas nessa estatística (`NORECOMPUTE`):
     ```sql
     UPDATE STATISTICS dbo.Orders IX_Orders_CustomerId WITH FULLSCAN, NORECOMPUTE;
     ```
3. **Bancos de Dados Somente Leitura (Read-Only):**
   - Bancos configurados como `READ_ONLY` não conseguem gravar estatísticas no disco base (salvo se redirecionadas para o `tempdb`).

> [!warning] Perigo no Exame
> Nunca desabilite `AUTO_UPDATE_STATISTICS` globalmente no banco de dados sem possuir uma rotina manual agendada de manutenção rigorosa. Ficar sem atualização automática e sem job manual fará o otimizador gerar estimativas catastróficas de cardinalidade (estimando 1 linha para tabelas gigantes).

---

## Problemas Comuns e Soluções (Common Issues)

| Sintoma | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Query lenta repentinamente após rodar bem | Regressão de plano por parameter sniffing | Use hints de `OPTIMIZE FOR UNKNOWN` ou force o plano anterior com Query Store. |
| Lentidão em junções lógicas no plano | Key Lookup apontando para a tabela base | Adicione as colunas extras no `INCLUDE` do índice não-clusterizado. |
| Estatísticas de tabela defasadas | Limiar automático de 20% de alterações não atingido | Execute rotinas manuais de `UPDATE STATISTICS WITH FULLSCAN`. |
| Falha ao validar Plan Guide criado | O texto SQL passado não possui igualdade exata | Use `sys.fn_validate_plan_guide` para debugar quebras de linhas ou caracteres. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - Um **Key Lookup** indica a necessidade de criar ou alterar o índice não-clusterizado de busca adicionando colunas extras com a cláusula **`INCLUDE`**.
> - Plan Guides exigem **igualdade literal absoluta** da query de entrada (incluindo espaços).
> - Se o exame solicitar mitigação de parameter sniffing em stored procedures que executam com frequência, prefira **`OPTION(OPTIMIZE FOR UNKNOWN)`** para evitar overhead de compilação do `OPTION(RECOMPILE)`.
> - Tabelas temporais e Ledger registram logs e históricos lógicos, enquanto estatísticas atualizadas garantem estimativas físicas de dados corretas para o otimizador.

---

## Resumo dos Conceitos (Key Takeaways)

- Planos de execução sinalizam as operações físicas que oneram a consulta (scans vs seeks).
- O Query Store é a melhor ferramenta para o monitoramento e plan forcing duradouros do banco.
- O uso de Plan Guides injeta dicas em códigos fechados gerados por ORMs.
- Resolva problemas de snifagem de parâmetros adotando hints de recompilação controlada ou otimização média de valores.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

As consultas originadas de uma ferramenta de ERP de terceiros que você não pode alterar sofrem de lentidão intermitente devido a problemas de parameter sniffing. As queries enviadas possuem texto T-SQL parametrizado fixo. Qual é a melhor abordagem para estabilizar o desempenho desse cenário sem alterar o código do aplicativo?

A. Adicionar hints de `OPTION(RECOMPILE)` na stored procedure correspondente.

B. Criar um Plan Guide no banco de dados para associar a dica `OPTIMIZE FOR UNKNOWN` ao texto exato enviado pelo ERP.

C. Desabilitar a atualização automática de estatísticas do banco de dados.

D. Forçar um plano de execução de forma manual usando comandos do Query Store.

> [!success]- Resposta
> **B — Criar um Plan Guide no banco de dados para associar a dica `OPTIMIZE FOR UNKNOWN` ao texto exato enviado pelo ERP**
>
> Quando não é possível alterar fisicamente o código gerado pelas aplicações, o recurso de **Plan Guide** permite interceptar a consulta enviada no banco de dados (desde que seja passada a string literal exata) e injetar query hints lógicos, como o `OPTIMIZE FOR UNKNOWN`. Isso resolve os desvios de parameter sniffing sem demandar mudanças de código da aplicação. A alternativa A exige alteração direta. A alternativa D força um único plano físico rígido que pode não ser ideal para todas as execuções.

---

## Tópicos Relacionados

- [01-Recomendações de Configuração do Banco de Dados](./01-database-configurations.md)
- [02-Níveis de Isolamento de Transações & Concorrência](./02-transaction-isolation-concurrency.md)
- [01-Tabelas & Índices](../01-database-objects/01-tables-indexes.md)
- [Manutenção de Índices e Fragmentação](../01-database-objects/01-tables-indexes.md#fragmentação-de-índices-e-estratégias-de-manutenção)

---

## Documentação Oficial

- [Execution Plans (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/performance/execution-plans)
- [Query Store (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- [Query Performance Insight (Azure SQL)](https://learn.microsoft.com/en-us/azure/azure-sql/database/query-performance-insight-use)
- [Plan Guides (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/performance/plan-guides)
- [Parameter Sniffing (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide#parameter-sensitivity)
- [Joins — Junções Adaptativas (Microsoft Learn)](https://learn.microsoft.com/en-us/sql/relational-databases/performance/joins?view=sql-server-ver17#adaptive-joins)

---

**[← Anterior](./02-transaction-isolation-concurrency.md) | [↑ Voltar para a Seção](./performance-optimization.md) | [Lab: Troubleshooting de Performance](../../practice/labs/06-performance-optimization/03-query-performance-troubleshooting-lab.sql)**
