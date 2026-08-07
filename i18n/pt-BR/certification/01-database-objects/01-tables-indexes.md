---
title: Tables, Data Types, and Indexes
type: study-material
tags:
  - dp-800
  - tables
  - indexes
  - column-store
  - data-types
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Projeto de Tabelas (Table Design)](#projeto-de-tabelas-table-design)
>   - 🔹 [Escolha e Mapeamento de Tipos de Dados](#escolha-e-mapeamento-de-tipos-de-dados)
>   - 🔹 [Precedência e Conversão Implícita de Tipos de Dados](#precedencia-e-conversao-implicita-de-tipos-de-dados)
>   - 🔹 [Considerações sobre Tamanho das Colunas](#consideracoes-sobre-tamanho-das-colunas)
> - 📍 [3. Tipos de Indexes (Index Types)](#tipos-de-indexes-index-types)
>   - 🔹 [Clustered Index](#clustered-index)
>   - 🔹 [Non-Clustered Index](#non-clustered-index)
>   - 🔹 [ColumnStore Index](#column-store-index)
> - 📍 [4. Arquitetura de Tabelas & Técnicas de Indexação](#heap-vs-clustered-table)
>   - 🔹 [Heap vs Clustered Table](#heap-vs-clustered-table)
>   - 🔹 [Filtered Indexes](#filtered-indexes)
>   - 🔹 [Included Columns](#included-columns)
>   - 🔹 [Index Compression](#index-compression)
>   - 🔹 [Considerações de Design de Index](#consideracoes-de-design-de-index-index-design)
>   - 🔹 [Fragmentação de Índices e Estratégias de Manutenção](#fragmentação-de-índices-e-estratégias-de-manutenção)
> - 📍 [5. Aplicação Prática & Síntese](#casos-de-uso-use-cases)
>   - 🔹 [Casos de Uso](#casos-de-uso-use-cases)
>   - 🔹 [Problemas Comuns e Soluções](#problemas-comuns-e-solucoes-common-issues)
>   - 🔹 [Melhores Práticas](#melhores-praticas-best-practices)
>   - 🔹 [Dicas para o Exame](#dicas-para-o-exame-exam-tips)
>   - 🔹 [Resumo dos Conceitos](#resumo-dos-conceitos-key-takeaways)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)
---


# Tables, Data Types, and Indexes

## Visão Geral (Overview)

O projeto e a implementação de Tables é fundamental para o exame DP-800. Esta seção cobre a escolha apropriada de tipos de dados, o design de B-tree Indexes (Clustered e Non-Clustered) e quando utilizar Column Store Indexes para cargas de trabalho analíticas.

> [!abstract]
>
> - Cobre B-tree Indexes (Clustered, Non-Clustered), Columnstore Indexes (CCI, NCCI) e manutenção de Indexes.
> - Tabelas Heap não possuem Clustered Index; adicionar um Clustered Index converte a Heap.
> - Tópicos chave do exame: escolha do tipo de Index para OLTP vs analytics, fill factor (fator de preenchimento) e fragmentação de Index.

> [!tip] O que o Exame Testa
>
> - Escolher entre **Clustered Columnstore (CCI)** e Clustered B-tree com base na carga de trabalho: CCI = analytics/cargas em massa (bulk-load); B-tree = consultas pontuais (point lookups) típicas de OLTP.
> - Reconhecer que um **Non-Clustered Columnstore Index (NCCI)** pode ser adicionado a uma tabela rowstore existente para cargas de trabalho mistas (HTAP).
> - Compreender que o **fill factor** reduz as divisões de página (page splits) ao deixar espaço livre nas páginas folha (leaf pages) — um menor fill factor = menos splits, mas maior consumo de espaço.

---

## Projeto de Tabelas (Table Design)

### Escolha e Mapeamento de Tipos de Dados

O projeto de tabela eficiente exige a seleção precisa do menor tipo de dados capaz de comportar a regra de negócio com segurança. Abaixo está o mapeamento detalhado dos tipos de dados nativos do SQL Server e Azure SQL baseado no MS Learn.

#### Mapeamento Detalhado de Tipos de Dados (MS Learn Reference)

| Tipo de Dado | Tamanho (Bytes) | Faixa de Valores / Especificação | Onde Usar (Casos de Uso) | Recomendações | Pontos de Atenção & Armadilhas (DP-800) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`bit`** | 1 byte (até 8 cols por byte) | `0`, `1` ou `NULL` | Flags booleanos (`IsActive`, `HasDiscount`). | Agrupar colunas `bit` juntas na DDL para otimizar espaço físico de linha. | Possui precedência 19. Comparar com string (ex: `'1'`) gera conversão implícita. |
| **`tinyint`** | 1 byte | `0` a `255` | Status de pedidos, meses do ano (1-12), códigos pequenos de categoria. | Usar em substituição ao `int` quando a faixa for estritamente < 256. | Não aceita valores negativos (estouro em tentativas de inserir -1). |
| **`smallint`** | 2 bytes | `-32.768` a `32.767` | Anos (`2026`), contadores médios, códigos de estado ou país numéricos. | Ideal para colunas numéricas de volume intermediário sem decimais. | Se comparado com `int` em JOINs/WHERE, sofre conversão implícita para `int`. |
| **`int`** | 4 bytes | `-2.147.483.648` a `2.147.483.647` (~2,14 bilhões) | Chaves primárias/estrangeiras padrão (surrogate keys), IDs de entidade. | Escolha padrão para chaves de tabela OLTP de médio porte. | Pode ocorrer Integer Overflow em tabelas de alto volume. Avalie `bigint` com antecedência. |
| **`bigint`** | 8 bytes | `-9,22x10¹⁸` a `9,22x10¹⁸` | Tabelas de fatos (Data Warehouse), logs de auditoria, contadores de telemetria. | Usar para `IDENTITY` ou `SEQUENCE` em tabelas com bilhões de registros. | Ocupa o dobro do espaço de `int` em memória RAM, cache e B-Tree Indexes. |
| **`decimal(p,s)`** / **`numeric(p,s)`** | 5 a 17 bytes (P:1-9=5B, 10-19=9B, 20-28=13B, 29-38=17B) | `-10³⁸+1` a `10³⁸-1` (P = precisão total 1-38; S = escala decimal 0-P) | Dados financeiros, moedas, taxas de juros, medidas fiscais e contábeis exatas. | **Sempre definir `(p,s)` explicitamente** (ex: `decimal(18,2)`). O padrão omisso é `decimal(18,0)`. | Único tipo numérico exato recomendado para dinheiro. Operações entre decimais ajustam precisão/escala automaticamente. |
| **`money`** / **`smallmoney`** | 8 bytes (`money`) / 4 bytes (`smallmoney`) | `money`: -922.337.203.685.477,5808 a 922.337.203.685.477,5807 | Armazenamento de valores monetários legados. | **EVITAR em projetos novos**. Preferir `decimal(19,4)` ou `decimal(18,2)`. | Sujeito a erros de arredondamento intermediário em multiplicações e divisões encadeadas. |
| **`float(n)`** / **`real`** | 4 bytes (`n`=1..24 / `real`) ou 8 bytes (`n`=25..53 / `float`) | IEEE 754 aproximado (`float(53)`: 15 dígitos de precisão; `real`: 7 dígitos) | Dados científicos, coordenadas geográficas, medições de sensores IoT. | NUNCA usar para valores financeiros ou colunas de junção (JOIN/PRIMARY KEY). | **Tipo aproximado (não exato)**. Comparações diretas de igualdade (`WHERE float_col = 1.23`) podem falhar. |
| **`date`** | 3 bytes | `0001-01-01` a `9999-12-31` (Precisão de 1 dia) | Datas de nascimento, datas fiscais, quando o horário for irrelevante. | Preferir `date` em relação ao `datetime` (economiza 5 bytes por linha). | Excelente para particionamento de tabelas por intervalo diário/mensal. |
| **`time(n)`** | 3 a 5 bytes (dependendo de `n`: 0-7) | `00:00:00.0000000` a `23:59:59.9999999` (Precisão de até 100 nanosegundos) | Horários de funcionamento, turnos, registros diários sem data. | Usar `time(0)` para precisão de segundos (3 bytes). | Não armazena componente de data nem fuso horário. |
| **`datetime2(n)`** | 6 a 8 bytes (6B: n=0..2, 7B: n=3..4, 8B: n=5..7) | `0001-01-01` a `9999-12-31` (Precisão de até 100 nanosegundos) | Timestamps de criação/modificação, logs transacionais modernos. | **Substituto padrão recomendado pelo MS Learn** para o tipo legado `datetime`. | Precedência 4. Se comparado com `datetime` (precedência 6), o `datetime` é promovido. |
| **`datetimeoffset(n)`** | 8 a 10 bytes | `0001-01-01` a `9999-12-31` com offset UTC (`-14:00` a `+14:00`) | Aplicações globais, e-commerce internacional, auditorias multi-região. | Usar para registrar a hora com preservação do fuso horário original. | Permite normalização direta para UTC utilizando `AT TIME ZONE` ou `SWITCHOFFSET`. |
| **`datetime`** *(Legado)* | 8 bytes | `1753-01-01` a `9999-12-31` (Precisão de 3,33 milissegundos) | Manutenção de sistemas SQL Server legados. | **EVITAR em novos projetos**. Usar `datetime2`. | Arredonda milissegundos (ex: `.999` vira `.000` do próximo segundo). Ocupa 8 bytes fixos. |
| **`smalldatetime`** *(Legado)* | 4 bytes | `1900-01-01` a `2079-06-06` (Precisão de 1 minuto) | Sistemas legados. | Substituir por `date` ou `datetime2(0)`. | Segundos `:30` ou superiores arredondam para o minuto seguinte automaticamente. |
| **`char(n)`** | `n` bytes fixos (1 a 8.000) | Texto ANSI/ASCII não-Unicode de tamanho fixo. | Códigos estritamente fixos (UF de 2 letras `'SP'`, códigos ISO `'BRA'`, MD5 hash). | Usar somente se 100% das linhas preencherem exatamente `n` caracteres. | Preenche com espaços à direita (right-padded) se o texto inserido for menor que `n`. |
| **`varchar(n)`** / **`varchar(max)`** | Tamanho real + 2 bytes overhead (max 8.000B; `max` até 2 GB) | Texto ANSI/ASCII não-Unicode de comprimento variável. | Nomes, e-mails, descrições sem caracteres internacionais/especiais. | Definir tamanho explícito (ex: `varchar(100)`). Evitar `max` sem necessidade. | **ARMADILHA DP-800**: Filtrar `varchar` com parâmetro `NVARCHAR` causa conversão implícita na coluna → **INDEX SCAN**. |
| **`nchar(n)`** | `2 * n` bytes fixos (1 a 4.000 chars / max 8.000B) | Texto Unicode UTF-16 de comprimento fixo. | Códigos internacionais de tamanho fixo com símbolos Unicode. | Usar apenas para códigos curtos estáticos com suporte a múltiplos idiomas. | Ocupa o dobro do espaço em disco/RAM comparado ao `char`. |
| **`nvarchar(n)`** / **`nvarchar(max)`** | `(2 * tamanho real) + 2` bytes (max 4.000 chars; `max` até 2 GB) | Texto Unicode UTF-16 de comprimento variável. | Padrão para campos de texto modernos, nomes multilingues, comentários. | Usar tamanhos explícitos. No SQL Server 2019+, avalie collations UTF-8 em `varchar`. | Colunas `nvarchar(max)` não podem fazer parte da chave de um B-Tree Index (limite de 1.700 bytes). |
| **`binary(n)`** / **`varbinary(n)`** / **`varbinary(max)`** | Tamanho real + 2 bytes overhead (`max` até 2 GB) | Stream de bytes binários puros. | Hashes criptográficos (SHA2_256 = `varbinary(32)`), tokens binários, BLOBs. | Para arquivos > 1 MB, armazenar no Azure Blob Storage e manter apenas a URL no banco. | Dados em `varbinary(max)` off-row exigem I/O adicional separado do buffer pool. |
| **`uniqueidentifier`** | 16 bytes | GUID / UUID de 128 bits | Identificadores únicos globais distribuídos (microserviços, sync offline). | **Usar `NEWSEQUENTIALID()`** como valor padrão em Clustered Indexes. | **NUNCA usar `NEWID()` como Clustered Index** (causa Page Splits massivos e fragmentação grave). |
| **`xml`** | Variável (até 2 GB) | Documentos XML estruturados. | Payloads e configurações de sistemas legados. | Criar XML Indexes secundários se realizar consultas XQuery/XPath frequentes. | Alto consumo de CPU para parsing. Dar preferência ao formato JSON em projetos novos. |
| **`json`** *(SQL 2025+ / Azure SQL)* | Variável (até 2 GB) | Documentos JSON nativos (formato binário JSONB). | Schemas semi-estruturados, atributos dinâmicos de produto. | No SQL 2016-2022 use `nvarchar(max)` com `ISJSON()`. No SQL 2025+ use o tipo `JSON` nativo. | Indexar atributos específicos criando Computed Columns persistidas com Non-Clustered Indexes. |

```sql
CREATE TABLE dbo.Orders (
    OrderId     INT             NOT NULL IDENTITY(1,1),
    CustomerId  INT             NOT NULL,
    OrderDate   datetime2(0)    NOT NULL DEFAULT GETUTCDATE(),
    TotalAmount decimal(18,2)   NOT NULL,
    Notes       nvarchar(1000)  NULL,
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderId)
);
```

---

### Precedência e Conversão Implícita de Tipos de Dados

No SQL Server e Azure SQL, quando duas expressões com tipos de dados diferentes são combinadas por operadores (como `=`, `+`, `JOIN` ou em cláusulas `WHERE`), o T-SQL aplica regras estritas de **Precedência de Tipos de Dados (Data Type Precedence)**.

#### Hierarquia Oficial de Precedência MS Learn

O SQL Server sempre converte automaticamente o tipo de **menor precedência** para o tipo de **maior precedência**.

```
[MAIOR PRECEDÊNCIA (1)] 
  1. Tipos de dados definidos pelo usuário (User-defined data types)
  2. sysname
  3. xml
  4. datetime2
  5. datetimeoffset
  6. datetime
  7. smalldatetime
  8. date
  9. time
 10. float
 11. real
 12. decimal / numeric
 13. money
 14. smallmoney
 15. bigint
 16. int
 17. smallint
 18. tinyint
 19. bit
 20. ntext (Depreciado)
 21. text (Depreciado)
 22. image (Depreciado)
 23. timestamp / rowversion
 24. uniqueidentifier
 25. nvarchar (incluindo nvarchar(max))
 26. nchar
 27. varchar
 28. char
 29. varbinary
 30. binary
[MENOR PRECEDÊNCIA (30)]
```

#### Matriz de Compatibilidade de Conversão Implícita (MS Learn)

A tabela a seguir resume se a conversão entre tipos de dados ocorre de forma **Implícita**, exige **Conversão Explícita** (`CAST` / `CONVERT`), ou resulta em **Erro de Execução**.

| Origem \ Destino | `int` / `bigint` | `decimal` | `float` | `datetime2` | `varchar` | `nvarchar` | `uniqueidentifier` | `varbinary` |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`int` / `bigint`** | Implícito | Implícito | Implícito | Erro Explícito | Implícito | Implícito | Erro | Explícito |
| **`decimal`** | Implícito* | Implícito | Implícito | Erro | Implícito | Implícito | Erro | Explícito |
| **`float`** | Implícito* | Implícito* | Implícito | Erro | Implícito | Implícito | Erro | Erro |
| **`datetime2`** | Erro | Erro | Erro | Implícito | Implícito | Implícito | Erro | Erro |
| **`varchar`** | Implícito* | Implícito* | Implícito* | Implícito* | Implícito | **Implícito (Promove)** | Implícito* | Implícito |
| **`nvarchar`** | Implícito* | Implícito* | Implícito* | Implícito* | Explícito | Implícito | Implícito* | Implícito |
| **`uniqueidentifier`** | Erro | Erro | Erro | Erro | Implícito | Implícito | Implícito | Explícito |
| **`varbinary`** | Explícito | Explícito | Erro | Erro | Implícito | Implícito | Explícito | Implícito |

*\*Nota: Conversões implícitas marcadas com `*` dependem da validade dos dados (ex: string contendo apenas dígitos ao converter para numérico); do contrário, geram erro de tempo de execução (runtime conversion failure).*

#### Armadilhas Críticas para o Exame DP-800

> [!CAUTION] 🚨 O Bug de Performance: Conversão Implícita e Non-Sargable Queries
> 
> Quando uma coluna do tipo `VARCHAR` (precedência 27) é filtrada por um valor do tipo `NVARCHAR` (precedência 25, como literais `N'texto'` ou parâmetros de ORM em C#/Java), o SQL Server eleva o tipo da **coluna da tabela** para `NVARCHAR`.
>
> **Exemplo com Problema:**
> ```sql
> -- Coluna CustomerCode é VARCHAR(20) com Non-Clustered Index
> DECLARE @Code NVARCHAR(20) = N'CUST_9941';
> 
> SELECT CustomerID, AccountBalance 
> FROM dbo.Customers 
> WHERE CustomerCode = @Code; -- IMPLICIT CONVERSION!
> ```
> O otimizador transforma a consulta internamente em:
> `WHERE CONVERT_IMPLICIT(nvarchar(20), CustomerCode) = @Code`
>
> **Consequência:** A função implícita aplicada sobre a coluna impede a navegação na B-Tree da chave do index, convertendo um **INDEX SEEK (rápido e direto)** em um **INDEX SCAN (varredura completa da tabela)**.
>
> **Como Corrigir:**
> ```sql
> -- Opção 1: Garantir que o tipo da variável/parâmetro seja VARCHAR
> DECLARE @Code VARCHAR(20) = 'CUST_9941';
> 
> -- Opção 2: Fazer o CAST explícito da variável (NÃO da coluna)
> SELECT CustomerID, AccountBalance 
> FROM dbo.Customers 
> WHERE CustomerCode = CAST(@Code AS VARCHAR(20));
> ```

---

### Considerações sobre Tamanho das Colunas

- O uso de `nvarchar(max)` limita a indexação como coluna-chave; dados armazenados fora da linha não são comprimidos. Utilize tamanhos explícitos sempre que possível.
- Colunas do tipo `varchar(max)` / `varbinary(max)` são armazenadas fora da linha (off-row) quando excedem 8.000 bytes.
- Utilize colunas `SPARSE` para colunas que são predominantemente nulas (NULL) para economizar espaço físico em disco.

---

## Tipos de Indexes (Index Types)

### Clustered Index

- Define a ordem lógica das chaves na B-tree e armazena as páginas de dados no nível folha (apenas um por tabela).
- Normalmente criado sobre a Primary Key (chave primária).
- Estrutura em árvore B (B-tree); as páginas de dados constituem o nível folha (leaf level).

```sql
-- O Clustered index já existe através da definição de PRIMARY KEY CLUSTERED acima.
-- Ou pode ser criado explicitamente:
CREATE CLUSTERED INDEX CIX_Orders_OrderDate
ON dbo.Orders (OrderDate);
```

### Non-Clustered Index

- Estrutura B-tree separada contendo ponteiros que referenciam o Clustered Index ou o RID da tabela Heap correspondente.
- Suporta até 999 Non-Clustered Indexes por tabela.

```sql
CREATE NONCLUSTERED INDEX NIX_Orders_CustomerId
ON dbo.Orders (CustomerId)
INCLUDE (OrderDate, TotalAmount);
```

### Column Store Index

Os **Columnstore Indexes** armazenam os dados por coluna em vez de por linha, permitindo alta taxa de compressão e execução vetorial (vectorized execution) — ideal para consultas analíticas que varrem grandes conjuntos de dados.

| Tipo | Caso de Uso |
| :--- | :--- |
| **Clustered Columnstore Index (CCI)** | `Tabelas puramente analíticas ou Data Warehouse (DW); substitui o Clustered Index tradicional em árvore B`. |
| **Non-Clustered Columnstore Index (NCCI)** | Adiciona capacidade analítica a tabelas OLTP sem substituir a estrutura de armazenamento em linhas (rowstore). |

```sql
-- Clustered Columnstore (substitui o index clustered tradicional)
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactSales
ON dbo.FactSales;

-- Non-Clustered Columnstore (coexiste com indexes existentes)
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Orders_Analytics
ON dbo.Orders (OrderDate, CustomerId, TotalAmount);
```

**Principais recursos do Columnstore:**

- Execução em modo lote (Batch mode execution) — processa aproximadamente 900 linhas por lote (em vez de processamento linha por linha).
- Delta store — buffer temporário em rowstore para buffering das linhas recém-inseridas antes de serem comprimidas.
- Eliminação de grupos de linhas (Row group elimination) — ignora grupos de linhas comprimidos onde os valores mínimo e máximo da coluna não correspondem aos filtros da consulta.
- Não recomendado para buscas pontuais de uma única linha (single-row lookups); utilize soluções mistas para HTAP.

> [!warning] Erro Comum
> Um CCI aplicado sobre uma tabela OLTP com atualizações frequentes de uma única linha gera uma sobrecarga de gravação muito alta — o delta store ajuda, mas não é isento de custos. Não recomende CCI para cenários puros de OLTP na prova.

---

## Heap vs Clustered Table

| Aspecto | Heap (sem Clustered Index) | Clustered Table (com Clustered Index) |
| :--- | :--- | :--- |
| **Armazenamento** | IAM + páginas de dados em qualquer ordem | Páginas ordenadas em B-tree |
| **INSERT** | Rápido (apenas anexa no final) | Pode causar divisões de página (page splits) |
| **SELECT por chave** | Pode usar Heap Scan ou um índice Non-Clustered, conforme os índices existentes e o plano | `Busca eficiente (Index Seek)` quando o predicado é seletivo e o índice é adequado |
| **Ponteiros de encaminhamento (Forwarding pointers)** | Sim (ocorrem após atualizações/UPDATEs) | Não |
| **Ideal para** | Tabelas de staging/carga em massa temporária | A maioria das tabelas OLTP |

### Detalhes de Armazenamento de Heaps

Uma Heap não possui uma árvore B para organizar as linhas. O SQL Server usa páginas de dados e mapas de alocação, e cada linha é identificada por um **RID (Row Identifier)** de 8 bytes no formato `FileID:PageID:SlotID` — por exemplo, `FileID 1, PageID 350, Slot 4`.

- Um índice não clusterizado sobre uma Heap mantém RIDs como ponteiros para as linhas.
- As páginas de dados de uma Heap são vinculadas por mapas de alocação, como o **IAM (Index Allocation Map)**.
- Se um `UPDATE` aumentar uma linha e ela não couber mais na página original, o SQL Server pode mover a linha e deixar um **forwarding pointer** na página antiga. Ao consultar essa linha, o motor pode precisar de duas leituras físicas em vez de uma.
- A exclusão de linhas de uma Heap nem sempre devolve as páginas ao sistema operacional; a liberação pode exigir operações específicas, como `TABLOCK` ou a recriação da tabela (`ALTER TABLE ... REBUILD`).
- Sem um índice seletivo, a busca pode resultar em um `Table Scan`, percorrendo a Heap inteira por meio dos mapas IAM.
- Heaps podem ser adequadas para tabelas temporárias de staging carregadas em massa, lidas sequencialmente e descartadas ou truncadas em seguida. Para a maioria das tabelas OLTP, um clustered index bem escolhido tende a ser mais apropriado.

---

## Filtered Indexes

Um **filtered index** é um Non-Clustered Index contendo um predicado de filtragem na cláusula `WHERE`, indexando apenas as linhas que atendem a esse critério. Isso diminui consideravelmente o tamanho do Index e o custo de manutenção.

**Quando utilizar:**

- Colunas esparsas (sparse columns) onde apenas uma pequena fração das linhas contém valores significativos.
- Subconjuntos parciais de dados (ex: apenas registros ativos ou pendentes).
- Eliminação de valores nulos (NULL) de colunas opcionais.

**Sintaxe:**

```sql
-- Index apenas para pedidos ativos
CREATE NONCLUSTERED INDEX IX_Orders_Active
ON Orders(CustomerID, OrderDate)
WHERE Status = 'Active';

-- Index para colunas opcionais não nulas
CREATE NONCLUSTERED INDEX IX_Employees_Manager
ON Employees(ManagerID)
WHERE ManagerID IS NOT NULL;
```

**Limitações:**

- O otimizador pode utilizar um filtered index quando o predicado compilado implica com segurança o filtro do índice; valide o plano de execução para consultas parametrizadas.
- Não pode ser utilizado como cobertura (covering index) para consultas que precisem de linhas fora do filtro.
- Não é suportado em todos os cenários (ex: restrições com predicados `OR` em alguns casos).

---

## Included Columns

A cláusula `INCLUDE` adiciona colunas sem chave (non-key columns) ao nível folha de um Non-Clustered Index, criando um **covering index** (index de cobertura) que atende à consulta inteiramente a partir do Index, eliminando a necessidade de buscar os dados na tabela base (key lookup).

**Decisões entre colunas chave (Key) vs. incluídas (Included):**

| Aspecto | Key Column | Included Column |
| :--- | :--- | :--- |
| **Ordenado** | Sim — na ordem da árvore B | Não — armazenado apenas no nível folha |
| **Limite de 16 colunas** | Conta para o limite da chave | `Não conta para o limite` |
| **Usado para** | Cláusulas WHERE, JOIN ON, ORDER BY | Apenas colunas de saída do SELECT |
| **Tamanho do Index** | Afeta todos os níveis da B-tree | Afeta apenas o nível folha |

```sql
-- Index de cobertura (covering index) para padrões comuns de consulta
CREATE NONCLUSTERED INDEX IX_Orders_Customer_Covering
ON Orders(CustomerID, OrderDate)
INCLUDE (TotalAmount, Status, ShipDate);
```

> **Dica de exame:** Colunas incluídas eliminam os operadores de busca de chave (RID Lookup ou Key Lookup no plano de execução). Quando uma consulta seleciona colunas que não estão na chave do Index, o SQL Server faz um lookup para cada linha — adicionar essas colunas ao `INCLUDE` elimina essa operação extra.

---

## Index Compression

A compressão reduz o tamanho físico em disco e na memória de tabelas e indexes, trocando um pequeno custo de CPU por uma redução significativa nas operações de I/O.

**ROW compression:** Armazena tipos de dados de tamanho fixo em formato de tamanho variável, eliminando o armazenamento de espaços em branco e zeros à direita. Compatível com a maioria dos tipos de index.
- **Quando usar:**
  - Cargas de trabalho com escrita frequente (OLTP), pois o impacto de CPU para compressão/descompressão é mínimo.
  - Tabelas contendo dados de tamanho fixo (`CHAR`, `INT`, `DECIMAL`) que armazenam valores bem abaixo do limite máximo permitido pelo tipo.
  - Ambientes com restrições e gargalos de processamento de CPU.

**PAGE compression:** Estende a ROW compression e adiciona:
- **Prefix compression** — armazena um prefixo comum por coluna uma única vez por página, substituindo os valores repetidos por referências curtas.
- **Dictionary compression** — substitui valores repetidos em qualquer lugar da página por entradas em um dicionário local da página.
- **Quando usar:**
  - Tabelas e índices com leitura intensa e poucas atualizações (read-heavy/históricos), onde o ganho de I/O e cache de memória compensa o uso extra de CPU.
  - Quando há muita repetição de valores entre as linhas e colunas na mesma página.
  - Ambientes em que o principal gargalo de performance é o I/O de disco.

**COLUMNSTORE compression:** Gerenciada separadamente da compressão row/page. Columnstore possui sua própria codificação (delta store para novas linhas → grupos de linhas comprimidos após aproximadamente 1 milhão de linhas). Não aplique ROW/PAGE compression sobre Columnstore indexes.
- **Quando usar:**
  - Cargas de trabalho analíticas (OLAP/DW) realizando varreduras em grandes volumes de dados (milhões de linhas).
  - Consultas analíticas que agregam ou filtram colunas específicas (evitando a leitura da linha completa).

**Avaliando antes de aplicar:**

```sql
-- Estimar economia de espaço primeiro
EXEC sp_estimate_data_compression_savings
    @schema_name = 'dbo',
    @object_name = 'Orders',
    @index_id = NULL,
    @partition_number = NULL,
    @data_compression = 'PAGE';

-- Aplicar a compressão
ALTER TABLE Orders REBUILD WITH (DATA_COMPRESSION = PAGE);
ALTER INDEX IX_Orders_Customer ON Orders REBUILD WITH (DATA_COMPRESSION = ROW);
```

---

## Considerações de Design de Index (Index Design)

A escolha de quais colunas indexar — e como — tem um impacto significativo no desempenho das consultas e no custo de escrita.

- **Indexe primeiro as colunas de WHERE, JOIN ON e ORDER BY** — essas são as colunas que o otimizador mais precisa buscar (seek) e ordenar.
- **Evite o excesso de indexes** — cada Non-Clustered Index adiciona sobrecarga de manutenção para as operações de `INSERT`, `UPDATE` e `DELETE`.
- **Fill factor (Fator de Preenchimento)** — percentual de cada página folha deixado livre durante a criação ou reconstrução do Index (o padrão `0` ou `100` significa 100% cheia); usar um fill factor menor (ex: 80) deixa espaço livre para inserções, reduzindo as divisões de página (page splits) em tabelas com muita escrita.
- **Statistics (Estatísticas)** — o SQL Server cria estatísticas automaticamente para colunas indexadas; as estatísticas alimentam as estimativas de cardinalidade do otimizador de consultas.
- **A ordem das colunas da chave importa** — para indexes compostos, coloque as colunas de igualdade mais seletivas (maior cardinalidade) primeiro, seguidas pelas colunas de intervalo (range).

---

## Fragmentação de Índices e Estratégias de Manutenção

A **fragmentação de índices** surge quando `INSERT`, `UPDATE` e `DELETE` alteram a organização das páginas físicas da árvore B. O impacto é maior em índices grandes usados por leituras sequenciais; fragmentação em objetos pequenos normalmente não justifica manutenção.

### Conceito: Fragmentação Lógica vs Densidade de Página

1. **Fragmentação lógica/externa (`avg_fragmentation_in_percent`)**: a ordem lógica das chaves deixa de acompanhar a ordem física das páginas, prejudicando leituras sequenciais.
2. **Densidade de página (`avg_page_space_used_in_percent`)**: as páginas ficam parcialmente vazias, exigindo mais páginas no Buffer Pool e mais I/O para ler o mesmo volume de dados.

### Causas: Page Splits e Inserções Aleatórias

Quando uma página folha de 8 KB está cheia e uma nova chave precisa ser inserida no meio da árvore — cenário comum com `GUID`/`NEWID()` aleatório — o SQL Server divide a página, move aproximadamente 50% das linhas para uma nova página e atualiza os ponteiros da árvore. Isso pode deixar as páginas fisicamente desalinhadas e parcialmente vazias.

- A fragmentação lógica faz com que leituras que poderiam ser sequenciais se tornem mais aleatórias; o cabeçote de leitura ou subsistema de I/O precisa fazer mais acessos dispersos, prejudicando especialmente `Index Scan` e `Table Scan`.
- A baixa densidade de página força o SQL Server a carregar mais páginas no Buffer Pool para retornar o mesmo volume de dados, aumentando I/O e consumo de cache.

### Diagnóstico com `sys.dm_db_index_physical_stats`

```sql
SELECT
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    ips.avg_page_space_used_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i
    ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.page_count > 1000 -- Menos de 1.000 páginas (~8 MB) raramente justificam manutenção
ORDER BY ips.avg_fragmentation_in_percent DESC;
```

> **Dica prática:** Ignore a fragmentação de tabelas pequenas. Se o objeto cabe confortavelmente no Buffer Pool, o custo de reorganizar ou reconstruir o índice tende a ser maior que o benefício.

### Decisão de Manutenção: `REORGANIZE` vs `REBUILD`

| Fragmentação | Ação | Características |
| :--- | :--- | :--- |
| **< 5%** | Nenhuma | Evita gastar CPU e I/O sem benefício relevante. |
| **5% a 30%** | `REORGANIZE` | Operação incremental e online; reorganiza as páginas, mas não atualiza estatísticas automaticamente. |
| **> 30%** | `REBUILD` | Recria a árvore, pode consumir mais log/`tempdb` e atualiza a estatística do índice com `FULLSCAN`. |

```sql
ALTER INDEX IX_Orders_CustomerId
ON dbo.Orders REORGANIZE;

ALTER INDEX IX_Orders_CustomerId
ON dbo.Orders REBUILD;

-- Disponível apenas quando a edição/serviço oferecer suporte a operações online
ALTER INDEX IX_Orders_CustomerId
ON dbo.Orders REBUILD WITH (ONLINE = ON);
```

| Característica | `REORGANIZE` | `REBUILD` |
| :--- | :--- | :--- |
| Bloqueio | Operação online, com menor impacto | Offline por padrão; `ONLINE = ON` depende da edição/serviço (por exemplo, Enterprise ou Azure SQL) |
| Estatísticas | Não atualiza automaticamente | Atualiza a estatística do índice com `FULLSCAN` |
| Recursos | Menor consumo | Maior uso de CPU, log e `tempdb` |
| Cancelamento | Pode preservar o trabalho já realizado | Pode exigir rollback da operação |

> **Pegadinha de prova:** `ALTER INDEX ... REBUILD` atualiza a estatística daquele índice, não todas as estatísticas da tabela nem as estatísticas automáticas de colunas. Para atualizar todas, use `UPDATE STATISTICS dbo.Tabela WITH FULLSCAN`.

### Prevenção: Escolha de Chaves e `FILLFACTOR`

- Prefira chaves clusterizadas crescentes, como `IDENTITY`, `BIGINT` ou `DATE`, quando o padrão de inserção for sequencial.
- Evite `GUID`/`NEWID()` aleatório como chave clusterizada; quando necessário, avalie `NEWSEQUENTIALID()`.
- `FILLFACTOR` reserva espaço nas páginas folha durante a criação ou reconstrução do índice. Valores menores podem reduzir page splits em tabelas com atualizações e inserções no meio, ao custo de mais páginas e I/O.
- O valor adequado depende do padrão de escrita; não aplique `FILLFACTOR = 80` ou `90` indiscriminadamente.

---

## Casos de Uso (Use Cases)

- **Column store indexes**: Tabelas fatos de Data Warehouse, agregações para relatórios sobre milhões de linhas.
- **Non-clustered com INCLUDE**: Indexes de cobertura para evitar key lookups em padrões comuns de consulta.
- **Heaps**: Tabelas de staging temporárias para inserções rápidas em massa antes do processamento final.
- **Filtered indexes**: Padrões de registros ativos/inativos, chaves estrangeiras que admitem nulos, consultas a subconjuntos de dados.
- **Index compression**: Grandes tabelas com dados repetitivos onde o I/O é o principal gargalo.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| Fragmentação de Index | Frequentes INSERT/UPDATE/DELETE | Reconstruir (`REBUILD`) ou reorganizar (`REORGANIZE`) o Index. |
| Page splits (Divisões de página) | GUIDs aleatórios (`NEWID()`) como chave de ordenação física | `Utilizar `NEWSEQUENTIALID()` ou `INT IDENTITY``. |
| Delta store muito grande | Inserções de poucas linhas no Columnstore | Realizar inserções em lotes (mínimo de 102.400 linhas) para preencher os grupos de linhas de forma ideal. |
| `nvarchar(max)` fora de linha | O valor excede 8.000 bytes | Comportamento esperado; considere segmentar grandes volumes de texto. |
| Filtered index não utilizado | O predicado compilado não implica com segurança o filtro do índice | Revise o predicado, as estatísticas e o plano; `OPTION (RECOMPILE)` pode ser apropriado em casos específicos. |
| Key lookup no plano de execução | O Index não contém colunas especificadas no SELECT | Adicione as colunas ausentes na cláusula `INCLUDE` do Index. |

---

## Melhores Práticas (Best Practices)

- Prefira chaves substitutas numéricas (`INT IDENTITY`) ou GUIDs sequenciais (`NEWSEQUENTIALID()`) em vez de GUIDs normais (`NEWID()`) como chaves de ordenação física (Clustered key) para evitar page splits aleatórios.
- Sempre execute `sp_estimate_data_compression_savings` antes de aplicar compressão em tabelas de produção.
- Adicione as colunas necessárias apenas na cláusula `SELECT` à cláusula `INCLUDE` e não à chave do Index, mantendo a chave estreita.
- Utilize filtered indexes quando um subconjunto pequeno e estável de linhas (ex.: registros ativos ou pendentes) for consultado com frequência.
- Analise os planos de execução buscando por operadores de Key Lookup e RID Lookup — eles indicam oportunidades de indexes de cobertura.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - Compreenda a diferença prática entre um **Clustered Columnstore** (que armazena fisicamente a tabela como coluna) e um **Non-Clustered Columnstore** (uma estrutura complementar de colunas ao lado da tabela rowstore tradicional).
> - O processamento em modo lote (Batch mode execution) está intimamente atrelado ao uso de Columnstore indexes — diferencial de desempenho crucial.
> - O tipo `datetime2` deve ser a escolha padrão em relação ao `datetime` tradicional para novos projetos devido à maior precisão e faixa de datas.
> - A inclusão de colunas (`INCLUDE`) em Non-Clustered Indexes permite criar indexes de cobertura sem estourar o limite de tamanho da chave.
> - Filtered indexes não são utilizados pelo otimizador quando as consultas comparam a coluna filtrada com parâmetros ou variáveis — use literais.
> - PAGE compression inclui ROW compression mais compressão de prefixo e de dicionário; estime o ganho com `sp_estimate_data_compression_savings` previamente.

---

## Resumo dos Conceitos (Key Takeaways)

- Escolha o menor tipo de dados adequado às regras de negócio.
- Clustered index define a ordenação física das linhas da tabela (apenas um por tabela).
- Column store indexes viabilizam a execução em modo lote para análises de grande porte.
- Non-clustered columnstore pode coexistir com tabelas OLTP para suportar cargas mistas (HTAP).
- Filtered indexes limitam a indexação a um subconjunto de linhas, economizando recursos.
- Colunas incluídas com `INCLUDE` evitam operadores de Key Lookup mantendo a busca no nível folha.
- As compressões ROW e PAGE minimizam o armazenamento e I/O à custa de pequeno consumo de CPU.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma consulta `SELECT CustomerID, TotalAmount FROM Orders WHERE Status = 'Pending'` apresenta o operador de *Key Lookup* em seu plano de execução. Qual modificação de Index elimina este operador?

A. Adicionar um filtered index com a cláusula `Status = 'Pending'`

B. Adicionar CustomerID e TotalAmount como colunas `INCLUDE` no index existente sobre a coluna Status

C. Reconstruir o Clustered Index configurando `PAGE` compression

D. Criar um segundo Clustered Index sobre a coluna Status

> [!success]- Resposta
> **B — Adicionar CustomerID e TotalAmount como colunas `INCLUDE` no index existente sobre a coluna Status**
>
> Incluir as colunas de retorno do SELECT (CustomerID, TotalAmount) no index existente o transforma em um *covering index* (index de cobertura) para esta consulta — o otimizador localiza todos os dados diretamente na página folha do index, dispensando o lookup. Um filtered index (A) ajudaria na seletividade, mas não eliminaria o lookup sem incluir as colunas adicionais. Uma tabela aceita apenas um Clustered Index (D).

---

## Tópicos Relacionados

- [02-Specialized Tables](./02-specialized-tables.md)
- [04-Constraints & Sequences](./04-constraints-sequences.md)
- [05-Partitioning](./05-partitioning.md)

---

## Documentação Oficial

- [Tables (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/tables/tables)
- [Columnstore Indexes Guide](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/columnstore-indexes-overview)
- [Index Design Guide](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-index-design-guide)
- [Create Filtered Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/create-filtered-indexes)
- [Data Compression](https://learn.microsoft.com/en-us/sql/relational-databases/data-compression/data-compression)

---

**[↑ Voltar para a Seção](./database-objects.md) | [Lab: Tabelas, Tipos de Dados e Índices](../../practice/labs/01-database-objects/01-tables-indexes-lab.sql) | [Próximo →](./02-specialized-tables.md)**
