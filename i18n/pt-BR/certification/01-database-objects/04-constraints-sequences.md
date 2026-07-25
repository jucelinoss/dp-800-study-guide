---
title: Constraints and Sequences
type: study-material
tags:
  - dp-800
  - constraints
  - primary-key
  - foreign-key
  - sequences
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. SEQUENCE vs IDENTITY](#matriz-de-decisao-arquitetural-sequence-vs-identity)
>   - 🔹 [Matriz de Decisão Arquitetural](#matriz-de-decisao-arquitetural-sequence-vs-identity)
>   - 🔹 [Cenários Práticos Corporativos](#cenarios-praticos-corporativos-real-world-use-cases)
> - 📍 [3. Tipos de Constraints](#tipos-de-constraints-constraint-types)
>   - 🔹 [PRIMARY KEY & FOREIGN KEY](#primary-key)
>   - 🔹 [UNIQUE CONSTRAINT vs UNIQUE INDEX](#unique-constraint-vs-unique-index-qual-a-diferenca)
>   - 🔹 [CHECK & DEFAULT Constraints](#check)
> - 📍 [4. Operações Avançadas & Regras](#habilitando-e-desabilitando-constraints)
>   - 🔹 [Habilitando/Desabilitando Constraints (`WITH CHECK`)](#habilitando-e-desabilitando-constraints)
>   - 🔹 [Ações Referenciais em Cascata (`ON DELETE/UPDATE`)](#acoes-referenciais-em-cascata-cascading-referential-actions)
>   - 🔹 [Caching e Ciclos em Sequences](#caching-e-ciclos-em-sequences)
> - 📍 [5. Casos de Uso Reais & Questões](#casos-de-uso-use-cases-e-cenarios-reais-de-projeto)
>   - 🔹 [Cenário 1: Numeração Unificada de Documentos](#cenario-1-numeracao-unificada-de-documentos-fiscais-sequenciamento-multi-tabela)
>   - 🔹 [Cenário 2: Validação de Regras de Negócio](#cenario-2-validacao-de-regras-de-negocio-e-integridade-referencial-em-cascata)
>   - 🔹 [Problemas Comuns, Práticas & Questões](#problemas-comuns-e-solucoes-common-issues)
---

# Constraints and Sequences

## Visão Geral (Overview)

As constraints impõem regras de integridade de dados diretamente no banco de dados. O SQL Server oferece suporte a PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK e DEFAULT. Os objetos SEQUENCE fornecem geradores de números sequenciais independentes no escopo do banco de dados, compartilháveis entre múltiplas tabelas.

> [!abstract]
>
> - Cobre constraints do tipo PRIMARY KEY, FOREIGN KEY, CHECK, DEFAULT e UNIQUE, bem como objetos SEQUENCE.
> - As constraints impõem regras de integridade física e lógica; as sequences oferecem geradores de números desacoplados das tabelas.
> - Tópicos chave do exame: diferenças de comportamento de SEQUENCE vs IDENTITY, e tempo de execução e validação de constraints.

> [!tip] O que o Exame Testa
>
> - `SEQUENCE` é **independente de qualquer tabela** — pode ser compartilhada entre tabelas, reiniciar (cycle) e ter seu valor redefinido usando `ALTER SEQUENCE`.
> - `IDENTITY` é **vinculado à coluna de uma tabela específica** — não pode ser compartilhado diretamente, não pode ser redefinido facilmente sem `DBCC CHECKIDENT` e incrementa apenas de forma crescente por padrão.
> - `CHECK` constraints podem validar regras referenciando múltiplas colunas da mesma linha.
> - `FOREIGN KEY` assegura integridade referencial entre diferentes tabelas.

---

##  Matriz de Decisão Arquitetural: SEQUENCE vs IDENTITY

Ambos são geradores de números sequenciais no SQL Server, mas possuem diferenças de escopo e aplicação:

### Quando usar `SEQUENCE`:
1. **Compartilhamento Multitabela**: Quando você precisa de uma numeração sequencial unificada compartilhada por múltiplas tabelas (ex: numeração fiscal única para `Invoices` e `Receipts`).
2. **Obter o valor ANTES do INSERT**: Quando a aplicação precisa saber o próximo ID antes de salvar o registro (`SELECT NEXT VALUE FOR MySeq`).
3. **Reinício e Ciclos (`CYCLE`)**: Quando a numeração precisa reiniciar periodicamente (`ALTER SEQUENCE ... RESTART WITH 1`) ou rodar em ciclo continuo.
4. **Alta Performance em Cargas Massivas**: Permite configurar cache em memória (`CACHE 1000`) para reduzir a contenção de disco em inserções simultâneas em massa.

### Quando usar `IDENTITY`:
1. **Chave Primária Exclusiva de Uma Tabela**: Para chaves surrogadas simples e puramente internas de uma única tabela.
2. **Simplicidade Administrativa**: Gerenciamento nativo e automático ligado diretamente à coluna (`IDENTITY(1,1)`).

| Recurso | SEQUENCE | IDENTITY |
| :--- | :--- | :--- |
| **Escopo** | Objeto independente no banco de dados | Ligado à coluna de uma tabela específica |
| **Compartilhado entre tabelas?** | **SIM** | **NÁƒO** |
| **Valor antes do INSERT?** | **SIM** (`NEXT VALUE FOR`) | **NÁƒO** (Apenas após o `INSERT`) |
| **Ciclos (`CYCLE`) / Re-start** | **SIM** (`ALTER SEQUENCE ... RESTART`) | Requer `DBCC CHECKIDENT` |
| **Performance em Lote** | Altíssima com `CACHE 1000` | Pode sofrer contenção de latch sob alta concorrência |

---

> [!warning] PONTO DE ATENÁ‡ÁƒO ARQUITETURAL & DP-800: Chaves Incrementais (Surrogate Keys) NÁƒO Garantem Integridade Negocial!
> 
> Apenas definir uma coluna `IDENTITY` ou `SEQUENCE` como `PRIMARY KEY` **NÁƒO impede a duplicação de dados reais de negócio** na tabela.
> 
> * **A Armadilha**: A engine do SQL Server garante a unicidade do número incremental (`ID = 1`, `ID = 2`), mas aceitará felizes duas linhas com o **mesmo CPF, CNPJ ou E-mail** com IDs artificiais diferentes.
> * **Impacto em Processos de MERGE e ETL**: Se uma rotina de carga fizer junções (`MERGE / ON Target.ID = Source.ID`), a engine criará registros duplicados da mesma entidade de negócio se a origem enviar IDs nulos ou novos.
> * **A Solução Arquitetural de Boas Práticas**:
>   1. Use a Chave Incremental (`IDENTITY`/`SEQUENCE`) como **Chave Substituta (Surrogate Key / PK)** para otimizar a performance física de armazenamento e `JOIN`s relacionais.
>   2. **OBRIGATORIAMENTE crie uma `UNIQUE CONSTRAINT` ou `UNIQUE INDEX` na Chave Negocial (Business Key / Natural Key)** (ex: `UNIQUE (CPF)` ou `UNIQUE (TenantID, DocumentNumber)`).
>   3. Em cargas de dados massivas, utilize um campo de Hash de controle de carga (`RowHash`) com `UNIQUE INDEX` para evitar inserções duplicadas por falha de processo ETL.

---

## 💡 Cenários Práticos Corporativos (Real-World Use Cases)

### 🚀 1. Cenários Reais para `SEQUENCE`
* **Cenário A: Numeração Fiscal Unificada (NFe Multicanal)**:
  * *Problema*: Vendas efetuadas em e-commerce (`OnlineSales`), lojas físicas (`PosSales`) e B2B (`CorporateSales`) precisam compartilhar uma numeração única entre tabelas.
  * *Solução*: Criar `CREATE SEQUENCE dbo.FiscalInvoiceSeq AS INT START WITH 1 INCREMENT BY 1 CACHE 100` e definir a coluna `InvoiceNumber` de todas as 3 tabelas com `DEFAULT (NEXT VALUE FOR dbo.FiscalInvoiceSeq)`. Se a regra exigir ausência absoluta de lacunas, implemente um processo transacional serializado específico.
* **Cenário B: Processamento em Fila Round-Robin (`CYCLE`)**:
  * *O que é Fila Round-Robin?*: Á‰ um algoritmo clássico de distribuição circular e igualitária de carga de trabalho entre um conjunto fixo de recursos (ex: $N$ servidores, $N$ atendentes ou $N$ partições). Ele atribui as tarefas em um ciclo contínuo sem favorecimento: `1 âž” 2 âž” 3 âž” 1 âž” 2 âž” 3...`
  * *Problema*: Distribuir chamados de suporte técnico em rodízio perfeito entre 3 equipes de atendimento (`Equipe 1, 2, 3`).
  * *Solução*: Usar `CREATE SEQUENCE dbo.RoundRobinTeamSeq AS TINYINT START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 3 CYCLE`. A cada chamada de `NEXT VALUE FOR`, a engine do SQL Server retorna o número do próximo time e, ao atingir o limite `MAXVALUE 3`, o modificador `CYCLE` faz o contador retornar automaticamente ao `MINVALUE 1` sem intervenção de código.
* **Cenário C: Ingestão Massiva de Dados em Paralelo (`sp_sequence_get_range`)**:
  * *Problema*: Um processo de ETL precisa gerar 50.000 chaves primárias na memória antes de executar um `BULK INSERT` concorrente em paralelo.
  * *Solução*: A procedure de ETL chama `sp_sequence_get_range @range_size = 50000`, reservando o bloco de IDs de uma só vez com trava mínima e sem disputa linha a linha no banco.

### ¢ 2. Cenários Reais para `IDENTITY`
* **Cenário A: Chave Surrogada Simples em Tabela Transacional Isolada**:
  * *Problema*: Tabelas como `OrderItems`, `AuditLogs` ou `UserSessions` precisam de um identificador numérico único simples para junção de dados (`JOIN`).
  * *Solução*: `ProductID INT IDENTITY(1,1) PRIMARY KEY`. Menor custo de administração e nativamente gerenciado pela engine.
* **Cenário B: Carga de Testes e Reseed em Staging (`DBCC CHECKIDENT`)**:
  * *Problema*: Após rodar testes automatizados e apagar os dados da tabela staging (`TRUNCATE` / `DELETE`), é necessário reiniciar a contagem dos IDs a partir de 1.
  * *Solução*: Executar `DBCC CHECKIDENT('lab.StagingTable', RESEED, 0)`.

###  3. Cenários Reais para Constraints (PK, FK, UK, DF, CHECK)
* **PRIMARY KEY NONCLUSTERED + CLUSTERED em Data/Hora**:
  * *Problema*: Tabela de `AuditLogs` com inserção massiva gera contenção de escrita (*Last-Page Insert Spill*) se a PK for um GUID clusterizado.
  * *Solução*: Criar `PRIMARY KEY NONCLUSTERED (LogID)` e definir o `CLUSTERED INDEX` na coluna de data `LogDate` para buscas aceleradas por período.
* **PRIMARY KEY COMPOSTA (em Tabelas N:M como `UserRoles (UserID, RoleID)`)**:
  * *Problema*: Tabela de associação N:M `UserRoles (UserID, RoleID)`.
  * *Solução*: Define `CONSTRAINT PK_UserRoles PRIMARY KEY (UserID, RoleID)`. Impede que o mesmo usuário receba a mesma permissão duas vezes e agrupa fisicamente no disco os perfis de cada usuário.
  * *Diferença entre PK Composta vs UNIQUE (UserID, RoleID)*:
    * A **PK Composta** cria um **`CLUSTERED INDEX` por padrão**, armazenando fisicamente no disco todas as roles de um mesmo `UserID` lado a lado na mesma página. Uma busca `WHERE UserID = 10` lê 100% das permissões do usuário em 1 única leitura de I/O!
    * Se usássemos apenas uma **UNIQUE Constraint** (ou uma surrogate key `UserRoleID IDENTITY` + `UNIQUE`), o índice seria **`NONCLUSTERED`**, deixando a tabela em formato Heap com as permissões do usuário espalhadas pelo disco e exigindo *Key Lookups*.
    * Além disso, a **PK Composta** proíbe valores `NULL` em qualquer uma das chaves (obrigatório em junções N:M) e economiza espaço em disco ao evitar a criação de um `ID` artificial desnecessário.
* **FOREIGN KEY com `ON DELETE CASCADE`**:
  * *Problema*: Exclusão de uma sessão ou carrinho de compras deve remover automaticamente os itens selecionados.
  * *Solução*: `CONSTRAINT FK_CartItems FOREIGN KEY (CartID) REFERENCES Carts(CartID) ON DELETE CASCADE`.
* **FOREIGN KEY com `ON DELETE SET NULL`**:
  * *Problema*: Quando um funcionário/vendedor é desligado e excluído da tabela `Employees`, os pedidos gravados por ele na tabela `Orders` **não podem ser apagados**, mas o vendedor deve ficar como nulo.
  * *Solução*: `CONSTRAINT FK_Orders_Employee FOREIGN KEY (EmployeeID) REFERENCES Employees(EmployeeID) ON DELETE SET NULL`.
* **UNIQUE INDEX FILTRADO (`WHERE Coluna IS NOT NULL`)**:
  * *Problema*: Cadastro de clientes aceita nacionais (com `CPF`) e estrangeiros (sem `CPF`). A regra de negócio exige que CPFs não se repitam, mas permite cadastrar múltiplos estrangeiros com CPF nulo.
  * *Solução*: `CREATE UNIQUE NONCLUSTERED INDEX UIX_CPF ON Customers(CPF) WHERE CPF IS NOT NULL`.
* **CHECK CONSTRAINT Multi-Colunas (`EndDate >= StartDate`)**:
  * *Problema*: Impede a gravação de contratos de serviços com data de término anterior à data de início.
  * *Solução*: `CONSTRAINT CK_ContractDates CHECK (EndDate >= StartDate)`.
* **DEFAULT CONSTRAINT com `SYSUTCDATETIME()` ou `NEWSEQUENTIALID()`**:
  * *Problema*: Garantir que todos os registros salvem o horário global UTC padronizado sem depender do fuso horário da máquina do cliente.
  * *Solução*: `CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()`.

---

| Restrição | Função Principal | Permite NULL? | Ándice Criado Por Padrão | Quantas por Tabela? |
| :--- | :--- | :--- | :--- | :--- |
| **PRIMARY KEY (PK)** | Identifica unicamente cada linha | **NÁƒO** (Obriga `NOT NULL`) | Unique Clustered por padrão, se ainda não houver Clustered Index | Apenas **1** |
| **FOREIGN KEY (FK)** | Assegura integridade referencial com tabela pai | **SIM** | Nenhum (Recomendado criar manual) | Múltiplas |
| **UNIQUE (UK)** | Impede valores duplicados em colunas secundárias | **SIM** (Apenas 1 `NULL` por padrão) | Unique Nonclustered Index | Múltiplas |
| **DEFAULT (DF)** | Insere valor padrão caso a coluna seja omitida | N/A | Nenhum | 1 por Coluna |
| **CHECK (CHK)** | Valida uma expressão booleana sobre a linha | **SIM** (Aceita se for `UNKNOWN`) | Nenhum | Múltiplas |

> [!IMPORTANT]
> **Aprofundamento Completo DP-800 — Como Funcionam as `CHECK Constraints`?**  
> 
> As `CHECK Constraints` (Restrições de Checagem) impõem integridade de domínio avaliando expressões booleanas durante operações de `INSERT` e `UPDATE`. Elas possuem 5 características fundamentais:
> 
> **1. Mecanismo de Validação Booleana**:  
> Toda vez que um comando tenta gravar ou alterar uma linha, o SQL Server executa a expressão lógica definida na restrição. A validação pode envolver uma única coluna (`Idade >= 18`), múltiplos valores (`Status IN ('ativo', 'pendente')`) ou comparar colunas da mesma linha (`DataEntrega >= DataPedido`).
> 
> **2. Lógica de Três Valores (*Three-Valued Logic*) e Tratamento de `NULL`**:  
> O SQL Server utiliza a lógica booleana de 3 valores: `TRUE` (Verdadeiro), `FALSE` (Falso) e `UNKNOWN` (Desconhecido / Nulo).  
> * **Regra Fundamental**: A `CHECK Constraint` **SÁ“ REJEITA** a gravação se o resultado da expressão for estritamente **`FALSE`**.  
> * Se a expressão avalia para `TRUE`, a operação é **aceita**.  
> * Se a expressão avalia para **`UNKNOWN`** (ocorre ao comparar qualquer valor com `NULL`), a operação é **ACEITA**!  
> 
> **Tabela de Verdade na Prática (`CHECK (Idade >= 18)`)**:  
> | Valor Inserido na Coluna `Idade` | Avaliação da Expressão (`Idade >= 18`) | Resultado Booleano | O SQL Server aceita a gravação? |
> | :--- | :--- | :--- | :--- |
> | `25` | `25 >= 18` | `TRUE` | âœ… **SIM** (Operação concluída com sucesso) |
> | `15` | `15 >= 18` | `FALSE` | âŒ **NÁƒO** (Dispara Erro de violação Msg 547) |
> | `NULL` | `NULL >= 18` | `UNKNOWN` | âœ… **SIM** (Gravação permitida sem erros!) |
> 
> *Conclusão para a Prova*: A `CHECK constraint` por si só **NÁƒO impede a inserção de `NULL`**. Para proibir valores nulos em uma coluna validada por `CHECK`, a coluna deve possuir a propriedade `NOT NULL` ou o predicado deve incluir explicitamente `AND Coluna IS NOT NULL`.
> 
> **3. Sem Criação de Ándices Físicos**:  
> Diferente de `PRIMARY KEY` (que cria índice Clusterizado por padrão) ou `UNIQUE` (que cria índice Não-Clusterizado), a `CHECK constraint` **não cria nenhum índice físico** em disco. Á‰ uma instrução puramente lógica avaliada em CPU no momento da transação.
> 
> **4. Suporte a Múltiplas Restrições por Tabela**:  
> Uma mesma tabela pode possuir múltiplas `CHECK constraints` para validar diferentes regras de negócio (ex: um check para e-mail via `LIKE '%@%'`, outro para saldos não-negativos, outro para intervalos de datas).
> 
> **5. Restrições de Escopo (Limitações do `CHECK`)**:  
> * A `CHECK constraint` só pode referenciar colunas da **mesma linha da mesma tabela**.  
> * **Não pode conter subconsultas** (`SELECT ... FROM outra_tabela`). Para validar regras entre tabelas distintas, deve-se utilizar `FOREIGN KEY`, Triggers ou Indexed Views.  
> * **Não pode conter funções não-determinísticas** de sistema que variam a cada chamada sem parâmetro fixo de linha (ex: `GETDATE()`).

---

##  UNIQUE CONSTRAINT vs UNIQUE INDEX (Qual a diferença?)

No SQL Server, criar uma `UNIQUE CONSTRAINT` gera por baixo dos panos um `UNIQUE INDEX` não-clusterizado para impor a unicidade. No entanto, existem diferenças cruciais em recursos e aplicação prática:

| Recurso / Capacidade | UNIQUE CONSTRAINT | UNIQUE INDEX |
| :--- | :--- | :--- |
| **Foco de Uso** | **Integridade Lógica / Modelo Relacional** | **Performance, Tuning & Opções Avançadas** |
| **Suporte a Filtros (`WHERE`)** | âŒ **NÁƒO**. Não aceita predicados `WHERE`. | âœ… **SIM**. Permite `WHERE Coluna IS NOT NULL` (Filtered Index aceitando múltiplos NULLs). |
| **Colunas Incluídas (`INCLUDE`)** | âŒ **NÁƒO**. Não permite colunas no `INCLUDE`. | âœ… **SIM**. Permite `INCLUDE (ColA, ColB)` (Covering Index para eliminar Key Lookups). |
| **Opções de Manutenção / Compresão** | Limitadas na criação. | Completas (`DATA_COMPRESSION`, `FILLFACTOR`, `ONLINE = ON`). |
| **Tratamento do `NULL`** | Permite **apenas 1 único NULL** por padrão. | Permite **múltiplos NULLs** se criado com filtro `WHERE col IS NOT NULL`. |
| **Aparece nos Metadados** | `sys.key_constraints` e `sys.indexes`. | Apenas em `sys.indexes`. |

---

---

## Tipos de Constraints (Constraint Types)

### PRIMARY KEY

```sql
-- 1. Em linha (Single column - Clustered por padrão)
CREATE TABLE dbo.Customers (
    CustomerId  int NOT NULL IDENTITY(1,1) PRIMARY KEY,
    Name        nvarchar(100) NOT NULL
);

-- 2. Em nível de tabela (Composta ou Nomeada)
CREATE TABLE dbo.OrderItems (
    OrderId     int NOT NULL,
    ProductId   int NOT NULL,
    Quantity    int NOT NULL,
    CONSTRAINT PK_OrderItems PRIMARY KEY (OrderId, ProductId)
);

-- 3. Primary Key Não-Clusterizada (permite usar o Clustered Index em outra coluna, ex: data)
CREATE TABLE dbo.LogEntries (
    LogId       uniqueidentifier NOT NULL DEFAULT NEWID(),
    LogDate     datetime2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
    Message     nvarchar(max) NOT NULL,
    CONSTRAINT PK_LogEntries PRIMARY KEY NONCLUSTERED (LogId)
);
```

#### 📌 Quando usar cada tipo de PRIMARY KEY?

| Tipo de Primary Key | Quando Usar (Caso de Uso Reconciliado) | Vantagem Arquitetural no SQL Server |
| :--- | :--- | :--- |
| **1. PK Simples Clusterizada (`IDENTITY` / `SEQUENCE`)** | Tabelas OLTP convencionais com 1 entidade única (`Customers`, `Products`). | Cria o `CLUSTERED INDEX` na chave incremental, garantindo inserções sequenciais no final do arquivo sem *page splits*. |
| **2. PK Composta (`PRIMARY KEY (ColA, ColB)`)** | Tabelas de associação N:M (`OrderItems`, `UserRoles`). | Garante unicidade do par e **agrupa fisicamente no disco** todas as linhas pertencentes ao primeiro elemento (`OrderId`/`UserId`), acelerando consultas `WHERE OrderId = X`. |
| **3. PK Não-Clusterizada (`PRIMARY KEY NONCLUSTERED`)** | Tabelas de alta ingestão de logs/auditoria usando GUIDs (`NEWID()`) ou onde a busca principal é por intervalo de datas. | **Libera o `CLUSTERED INDEX` para outra coluna** (ex: `LogDate`), evitando o caos de fragmentação/page splits de GUIDs aleatórios no disco. |

- Cria um Unique Clustered Index por padrão quando a tabela ainda não possui um Clustered Index.
- Pode ser definida como não clusterizada: `PRIMARY KEY NONCLUSTERED`.
- Apenas uma chave primária por tabela; as colunas participantes devem ser obrigatoriamente `NOT NULL`.

### FOREIGN KEY

```sql
-- Exemplo 1: ON DELETE NO ACTION (padrão) e ON UPDATE CASCADE
CREATE TABLE dbo.Orders (
    OrderId     int NOT NULL PRIMARY KEY,
    CustomerId  int NOT NULL,
    CONSTRAINT FK_Orders_Customers
        FOREIGN KEY (CustomerId) REFERENCES dbo.Customers (CustomerId)
        ON DELETE NO ACTION
        ON UPDATE CASCADE
);

-- Exemplo 2: ON DELETE SET DEFAULT
CREATE TABLE dbo.CustomerPreferences (
    PreferenceId int NOT NULL PRIMARY KEY,
    CustomerId   int NOT NULL DEFAULT 0, -- ID 0 representa 'Cliente Anônimo/Genérico'
    Theme        nvarchar(50) NOT NULL,
    CONSTRAINT FK_CustomerPreferences_Customers
        FOREIGN KEY (CustomerId) REFERENCES dbo.Customers (CustomerId)
        ON DELETE SET DEFAULT
);
```

**Ações Referenciais (Referential actions):**

| Ação | No DELETE do Pai | No UPDATE do Pai |
| :--- | :--- | :--- |
| `NO ACTION` (padrão) | Erro se houver linhas filhas vinculadas. | Erro se a chave referenciada mudar e existirem filhos. |
| `CASCADE` | `Exclui as linhas filhas vinculadas automaticamente`. | Atualiza os valores da FK nas linhas filhas. |
| `SET NULL` | Define a FK dos filhos como NULL. | Define a FK dos filhos como NULL. |
| `SET DEFAULT` | Define a FK dos filhos para o valor padrão da coluna. | Define a FK dos filhos para o valor padrão da coluna. |

### UNIQUE

```sql
-- Unique constraint (permite apenas um valor NULL)
ALTER TABLE dbo.Customers
ADD CONSTRAINT UQ_Customers_Email UNIQUE (Email);

-- Unique index (equivalente, mas com mais opções de configuração)
CREATE UNIQUE NONCLUSTERED INDEX UIX_Customers_Email
ON dbo.Customers (Email)
WHERE Email IS NOT NULL;  -- Index filtrado: ignora NULLs permitindo múltiplos NULLs
```

### CHECK

```sql
CREATE TABLE dbo.Products (
    ProductId   int             NOT NULL PRIMARY KEY,
    Price       decimal(10,2)   NOT NULL,
    Quantity    int             NOT NULL,
    Status      varchar(20)     NOT NULL,
    CONSTRAINT CHK_Products_Price    CHECK (Price > 0),
    CONSTRAINT CHK_Products_Quantity CHECK (Quantity >= 0),
    CONSTRAINT CHK_Products_Status   CHECK (Status IN ('active', 'discontinued', 'pending'))
);

-- NOT FOR REPLICATION: Impede o disparo da validação durante replicação
ALTER TABLE dbo.Products ADD CONSTRAINT CHK_Products_SKU
    CHECK (ProductId > 0) NOT FOR REPLICATION;
```

> [!NOTE]
> **Aprofundamento DP-800 — Como funciona a cláusula `NOT FOR REPLICATION`?**  
> A instrução **`NOT FOR REPLICATION`** desativa a validação de regras de integridade (ou execução de triggers) exclusivamente durante o processo de Replicação de Dados (*Transactional Replication* ou *Merge Replication*).
> 
> **1. O Problema que Ela Resolve**:  
> Quando uma aplicação insere ou altera dados no servidor principal (*Publisher*), o SQL Server já executa e valida as restrições. Ao replicar a transação para o servidor réplica (*Subscriber*), a re-execução da mesma validação causaria overhead duplo de CPU e risco de falhas caso a ordem das sincronizações divirja. Com `NOT FOR REPLICATION`, o SQL Server no Subscriber pressupõe que o dado já foi validado no Publisher e o insere diretamente.
> 
> **2. Comportamento por Tipo de Usuário/Processo**:
> * **Aplicação / Usuários Comuns**: A `CHECK constraint` é **executada normalmente** (salva se `> 0`, aborta se `<= 0`).
> * **Agente de Replicação (*Replication Agent*)**: A validação é **ignorada**, gravando os dados sem re-checagem.
> 
> **3. Onde mais o `NOT FOR REPLICATION` se aplica?**:
> * **`CHECK Constraints`**: Evita re-validação de regras lógicas no Subscriber.
> * **`FOREIGN KEY Constraints`**: Evita falhas de integridade referencial no Subscriber se os pacotes de tabelas Pai/Filho chegarem fora de ordem.
> * **Colunas `IDENTITY`**: `IDENTITY(1,1) NOT FOR REPLICATION` permite que o agente insira o valor original do Publisher (`IDENTITY_INSERT`) sem gerar novos contadores no Subscriber.
> * **`TRIGGERS` (`AFTER` / `INSTEAD OF`)**: `CREATE TRIGGER ... NOT FOR REPLICATION` impede a execução duplicada de triggers de auditoria ou integração no Subscriber.
> 
> **4. Pegadinha do Exame (`NOT FOR REPLICATION` vs `WITH NOCHECK`)**:
> * `NOT FOR REPLICATION`: A regra **continua ativa** para aplicações e usuários, afetando apenas o Agente de Replicação (`sys.check_constraints.is_not_for_replication = 1`).
> * `WITH NOCHECK`: Desativa temporariamente a validação histórica ou desabilita a restrição para **TODOS** os usuários, deixando o estado como *untrusted* (`is_not_trusted = 1`).

### DEFAULT

```sql
CREATE TABLE dbo.AuditLog (
    LogId       int             NOT NULL IDENTITY PRIMARY KEY,
    EventType   nvarchar(50)    NOT NULL,
    CreatedAt   datetime2(0)    NOT NULL DEFAULT GETUTCDATE(),
    CreatedBy   nvarchar(128)   NOT NULL DEFAULT SUSER_SNAME(),
    IsProcessed bit             NOT NULL DEFAULT 0
);
```

---

## Padrões de CHECK Constraints

As CHECK constraints podem implementar regras de validação lógica complexas de forma declarativa.

- **CHECK Multi-coluna**: O predicado pode referenciar colunas diferentes da mesma linha, permitindo validações cruzadas.
- **Validação com LIKE**: Utiliza operadores como `[0-9]`, `[A-Z]` e curingas `%`/`_` para validar formatos de strings.
- **Apenas funções determinísticas**: Funções não determinísticas (ex: `GETDATE()`, `RAND()`) são bloqueadas em expressões de CHECK.
- **NOT FOR REPLICATION**: Impede o disparo da constraint nas rotinas dos agentes de replicação, disparando apenas em operações comuns de usuários.
- **WITH NOCHECK**: Permite aplicar a constraint sem validar os registros já existentes na tabela — agiliza a aplicação em tabelas gigantes, mas marca a constraint como "não confiável" (not trusted).

```sql
-- Validação de padrões de formato
ALTER TABLE Customers ADD CONSTRAINT CK_Phone
    CHECK (Phone LIKE '[0-9][0-9][0-9]-[0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]');

-- Multi-coluna: data final deve ser posterior à data inicial
ALTER TABLE Projects ADD CONSTRAINT CK_ProjectDates
    CHECK (EndDate IS NULL OR EndDate > StartDate);

-- Adicionar sem validar a base existente (rápido)
ALTER TABLE Orders WITH NOCHECK ADD CONSTRAINT CK_Positive> [!IMPORTANT] Impacto de NOCHECK no Otimizador (Trusted Constraints & Sintaxe Duplo CHECK)
>
> **Por que a sintaxe usa `WITH CHECK CHECK CONSTRAINT`?**
> - **`WITH CHECK` (1º CHECK)**: Define o *modo de validação*. Diz ao SQL Server para verificar se os dados **já gravados na tabela** violam a restrição antes de ativá-la.
> - **`CHECK CONSTRAINT` (2º CHECK)**: Á‰ o *comando de ação* que reativa a restrição (o oposto de `NOCHECK CONSTRAINT`).
> 
> **Impacto na Performance (`is_not_trusted`)**:
> - Se você reativar apenas com `ALTER TABLE ... CHECK CONSTRAINT <Nome>` (sem o `WITH CHECK`), a restrição é reativada, mas o SQL Server **não valida o histórico existente**. A constraint fica marcada como **não-confiável (`is_not_trusted = 1`)**.
> - O otimizador de consultas **ignora constraints não-confiáveis** ao simplificar os planos de execução (ex: não pode simplificar JOINs nem eliminar varreduras desnecessárias).
> - **Regra de Ouro da Prova DP-800**: Para reativar a restrição e restaurar a confiança do otimizador (`is_not_trusted = 0`), você deve SEMPRE usar a sintaxe `WITH CHECK CHECK CONSTRAINT`.

---

â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚ 1. Constraint Confiavel (is_not_trusted = 0)  â”€â”€â–º Permite Eliminar Joins  â”‚
â”‚                                                    e Contradicoes (0 I/O) â”‚
â”‚                                                                           â”‚
â”‚ 2. Constraint Nao-Confiavel (is_not_trusted = 1) â”€â”€â–º Otimizador IGNORA e â”‚
â”‚                                                       FORCA Leitura de    â”‚
â”‚                                                       Disco Completa!     â”‚
â”‚                                                                           â”‚
â”‚ 3. Sequence com NOCACHE  â”€â”€â–º Gera Gargalo de I/O em sysseqobj (WRITELOG)  â”‚
â”‚ 4. FK sem Indice na Filho â”€â”€â–º Delecao na Pai causa Table Scan na Filho    â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

## Ações Referenciais em Cascata (Cascading Referential Actions)

As cláusulas `ON DELETE` e `ON UPDATE` especificam o comportamento das linhas filhas quando a linha pai correspondente sofre exclusão ou alteração de chave.

| Ação | Comportamento |
| :--- | :--- |
| `NO ACTION` | Retorna erro; realiza o rollback da transação caso existam linhas filhas vinculadas. |
| `CASCADE` | Exclui ou atualiza as linhas filhas correspondentes automaticamente. |
| `SET NULL` | Define a FK das linhas filhas para NULL (requer coluna nullable). |
| `SET DEFAULT` | `Define a FK das linhas filhas para o valor DEFAULT associado à coluna`. |

**Limitações em loops (Circular references)**: O SQL Server impede ações em cascata (`CASCADE`) que gerem loops ou caminhos circulares referenciais. Tabelas autoreferenciadas ou ciclos entre FKs devem utilizar `NO ACTION` e exigir tratamento manual no código.

**Cadeias de múltiplos níveis**: O `CASCADE` atua recursivamente. A exclusão de um registro avô cascata para os filhos e netos de forma transparente, o que pode apagar mais dados do que o planejado caso não haja cuidado.

```sql
-- CASCADE: apaga os itens do pedido se o pedido pai for apagado
ALTER TABLE OrderItems
ADD CONSTRAINT FK_OrderItems_Orders
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID)
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

-- SET NULL: define gerente como nulo se o registro do gerente for removido
ALTER TABLE Employees
ADD CONSTRAINT FK_Employees_Manager
    FOREIGN KEY (ManagerID) REFERENCES Employees(EmployeeID)
    ON DELETE SET NULL;
```

---

## Habilitando e Desabilitando Constraints

```sql
-- Desabilitar uma FK durante cargas em massa (bulk load)
ALTER TABLE dbo.Orders NOCHECK CONSTRAINT FK_Orders_Customers;

-- Habilitar novamente e validar a consistência dos dados existentes (Note a dupla palavra CHECK!)
-- 1º CHECK (WITH CHECK): Valida se os dados existentes estão em conformidade.
-- 2º CHECK (CHECK CONSTRAINT): Ação de HABILITAR a constraint (oposto de NOCHECK CONSTRAINT).
ALTER TABLE dbo.Orders WITH CHECK CHECK CONSTRAINT FK_Orders_Customers;

-- Desabilitar temporariamente todos os Triggers de uma tabela
ALTER TABLE dbo.Orders DISABLE TRIGGER ALL;
```

---

## SEQUENCES

Uma **SEQUENCE** é um objeto associado a um esquema que gera sequências numéricas independentemente de tabelas — ideal para chaves ou numerações que precisem ser compartilhadas entre tabelas distintas do banco.

```sql
-- Criar uma Sequence
CREATE SEQUENCE dbo.OrderNumberSeq
    AS int
    START WITH 10000
    INCREMENT BY 1
    MINVALUE 10000
    MAXVALUE 99999
    CYCLE
    CACHE 50;

-- Usar a Sequence
INSERT INTO dbo.Orders (OrderId, CustomerId)
VALUES (NEXT VALUE FOR dbo.OrderNumberSeq, 1);

-- Consultar o valor atual sem incrementá-lo
SELECT current_value FROM sys.sequences
WHERE name = 'OrderNumberSeq';

-- Usar como valor DEFAULT em uma tabela
CREATE TABLE dbo.Invoices (
    InvoiceId   int NOT NULL DEFAULT (NEXT VALUE FOR dbo.OrderNumberSeq) PRIMARY KEY,
    Amount      decimal(10,2) NOT NULL
);
```

> [!warning] Erro Comum
> Tanto IDENTITY quanto SEQUENCE geram números sequenciais, mas a IDENTITY é restrita a uma coluna específica de uma única tabela. Se a questão de exame exigir uma numeração compartilhada entre várias tabelas, a resposta correta é o uso de SEQUENCE.

**Comparativo: SEQUENCE vs IDENTITY:**

| Aspecto | IDENTITY | SEQUENCE |
| :--- | :--- | :--- |
| Escopo | Tabela única | `Escopo do esquema, multi-tabela` |
| Reinício | Difícil redefinir sem DBCC | `ALTER SEQUENCE ... RESTART` |
| Cache | Sem controle direto | Sim (`CACHE n`) — melhor performance, mas pode gerar lacunas (gaps) em quedas do servidor |
| Uso em SELECT | Não suportado inline | `NEXT VALUE FOR` pode ser usado em instruções compatíveis, sujeito às restrições da linguagem |
| Rollback de transação | Não recupera lacunas | Não recupera lacunas (comportamento idêntico) |

---

## Caching e Ciclos em Sequences

As sequences oferecem controle fino de geração de valores, incluindo ciclos e caches de memória.

- **CYCLE / NO CYCLE**: Ao atingir o `MAXVALUE`, `CYCLE` faz a numeração voltar ao `MINVALUE`; `NO CYCLE` dispara um erro de estouro de faixa.
- **CACHE n**: Reserva `n` valores na memória do servidor, diminuindo o I/O em disco. O SQL Server grava no arquivo apenas o "início do próximo lote" em vez de registrar cada número individualmente.
- **NO CACHE**: Cada comando `NEXT VALUE FOR` persiste o valor atual nas tabelas de sistema, reduzindo lacunas causadas por falhas inesperadas e aumentando o custo de I/O. Rollbacks e valores não usados ainda podem criar lacunas.
- **Comportamento de Gaps**: Reinicializações bruscas do servidor perdem os valores reservados no cache de memória que não foram consumidos. Ao subir, a Sequence retoma a partir do lote seguinte, gerando uma lacuna (gap) correspondente ao cache perdido.
- **RESTART WITH**: Permite redefinir a numeração atual para qualquer valor válido.

```sql
-- Sequence com suporte a ciclo e cache
CREATE SEQUENCE dbo.OrderSeq
    AS INT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9999999
    CYCLE
    CACHE 50;

-- Reiniciar a Sequence
ALTER SEQUENCE dbo.OrderSeq RESTART WITH 1;

-- Verificar o valor atual sem consumir
SELECT current_value FROM sys.sequences WHERE name = 'OrderSeq';

-- Associar a Sequence como default de uma tabela
ALTER TABLE Orders ADD CONSTRAINT DF_OrderID DEFAULT (NEXT VALUE FOR dbo.OrderSeq) FOR OrderID;

> [!warning] Lacunas (Gaps) em Sequences e Identity
>
> - Ambos os geradores sequenciais (SEQUENCE e IDENTITY) sofrem perda de valores cache em reinicializações ou quedas do servidor (gaps de 50 ou mais números).
> - Nem SEQUENCE nem IDENTITY garantem ausência de lacunas (gaps) ou numeração sequencial sem falhas. Se a sua regra de negócio exigir lacuna zero absoluta (ex: numeração de notas fiscais), você deve implementar uma tabela de controle de numeração própria com concorrência serializada.

```

---

Ambos são tecnicamente equivalentes sob o capô no SQL Server — uma UNIQUE constraint é implementada fisicamente através de um Non-Clustered Unique Index.

| Recurso | UNIQUE Constraint | Filtered UNIQUE Index |
| :--- | :--- | :--- |
| Permissão de NULL | Apenas um NULL por coluna | `Permite múltiplos NULLs (exclui NULLs do index)` |
| Sintaxe | `ADD CONSTRAINT ... UNIQUE` | `CREATE UNIQUE INDEX ... WHERE col IS NOT NULL` |
| Exibição no SSMS | Exibido como Constraint | Exibido como Index |

- A UNIQUE constraint permite exatamente **um valor nulo (NULL)** pois o SQL Server avalia a segunda inserção de NULL como duplicidade.
- A criação de um **filtered unique index** com `WHERE col IS NOT NULL` remove os nulos da validação, permitindo que a coluna comporte múltiplos registros NULL enquanto assegura unicidade para os valores preenchidos.

```sql
-- Unique index filtrado: permite múltiplos nulos, valida valores preenchidos
CREATE UNIQUE NONCLUSTERED INDEX UIX_Employees_NationalID
ON dbo.Employees (NationalID)
WHERE NationalID IS NOT NULL;
```

> [!tip] Dica para a Prova: UNIQUE com Múltiplos Nulos
>
> - Uma UNIQUE constraint permite apenas **um único valor NULL**. A segunda tentativa de inserir NULL falhará por duplicidade.
> - Se o requisito for aceitar múltiplos nulos e validar a unicidade apenas para valores preenchidos, crie um **Unique Index Filtrado** (`CREATE UNIQUE INDEX ... WHERE Coluna IS NOT NULL`).

---

---

## Casos de Uso (Use Cases) e Cenários Reais de Projeto

Abaixo estão descritos e demonstrados dois cenários de uso de constraints e sequences no SQL Server.

### Cenário 1: Numeração Unificada de Documentos Fiscais (Sequenciamento Multi-Tabela)
**Contexto**: Em um sistema financeiro corporativo, faturas emitidas (`Invoices`) e recibos de pagamento (`Receipts`) são armazenados em tabelas separadas por motivos de estrutura e auditoria. No entanto, por razões legais e de contabilidade, eles devem compartilhar a mesma sequência numérica sequencial sem sobreposições.

**Solução**: Utilizar um objeto `SEQUENCE` de escopo global compartilhado como o valor padrão (`DEFAULT`) nas chaves primárias de ambas as tabelas.

```sql
-- 1. Criação do esquema
CREATE SCHEMA fin;
GO

-- 2. Criação do Sequenciador Unificado
CREATE SEQUENCE fin.DocumentNumberSeq
    AS INT
    START WITH 10001
    INCREMENT BY 1
    NO CACHE; -- reduz lacunas por valores em cache após reinicializações

-- 3. Criação das tabelas de Faturas e Recibos utilizando a SEQUENCE
CREATE TABLE fin.Invoices (
    InvoiceID INT NOT NULL CONSTRAINT DF_Invoices_ID DEFAULT (NEXT VALUE FOR fin.DocumentNumberSeq),
    CustomerName NVARCHAR(100) NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_Invoices PRIMARY KEY CLUSTERED (InvoiceID)
);

CREATE TABLE fin.Receipts (
    ReceiptID INT NOT NULL CONSTRAINT DF_Receipts_ID DEFAULT (NEXT VALUE FOR fin.DocumentNumberSeq),
    PayerName NVARCHAR(100) NOT NULL,
    AmountReceived DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_Receipts PRIMARY KEY CLUSTERED (ReceiptID)
);

-- 4. Inserindo dados alternadamente para testar a sequência compartilhada
INSERT INTO fin.Invoices (CustomerName, Amount) VALUES ('Cliente A', 1500.00); -- Recebe 10001
INSERT INTO fin.Receipts (PayerName, AmountReceived) VALUES ('Cliente B', 500.00);  -- Recebe 10002
INSERT INTO fin.Invoices (CustomerName, Amount) VALUES ('Cliente C', 3200.00); -- Recebe 10003

-- 5. Consulta unificada comprovando a ordem e unicidade dos IDs
SELECT 'Fatura' AS Tipo, InvoiceID AS DocumentID, CustomerName AS Nome, Amount FROM fin.Invoices
UNION ALL
SELECT 'Recibo' AS Tipo, ReceiptID AS DocumentID, PayerName AS Nome, AmountReceived FROM fin.Receipts
ORDER BY DocumentID;
```

---

### Cenário 2: Validação de Regras de Negócio e Integridade Referencial em Cascata
**Contexto**: Um sistema de gerenciamento de projetos acadêmicos precisa garantir que:
1. Nenhum projeto termine antes do seu próprio início.
2. Cada tarefa cadastrada seja obrigatoriamente vinculada a um projeto.
3. Se um projeto for removido do sistema, todas as suas tarefas vinculadas sejam apagadas em cascata.
4. Se o membro do projeto responsável por uma tarefa for deletado, a tarefa deve ser mantida, mas o campo de responsabilidade deve voltar a um valor default ('Sem Alocação').

```sql
-- 1. Criação da Tabela de Usuários/Membros
CREATE TABLE dbo.TeamMembers (
    MemberId INT IDENTITY(1,1) PRIMARY KEY,
    FullName NVARCHAR(100) NOT NULL
);

-- Insere um membro padrão/default
SET IDENTITY_INSERT dbo.TeamMembers ON;
INSERT INTO dbo.TeamMembers (MemberId, FullName) VALUES (0, 'Membro Não Alocado');
SET IDENTITY_INSERT dbo.TeamMembers OFF;

-- 2. Criação da Tabela de Projetos com CHECK multi-coluna
CREATE TABLE dbo.Projects (
    ProjectId INT IDENTITY(1,1) PRIMARY KEY,
    ProjectName NVARCHAR(100) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NULL,
    
    -- CHECK multi-coluna garantindo integridade lógica
    CONSTRAINT CK_Projects_Dates CHECK (EndDate IS NULL OR EndDate >= StartDate)
);

-- 3. Criação da Tabela de Tarefas com Ações Referenciais em Cascata
CREATE TABLE dbo.Tasks (
    TaskId INT IDENTITY(1,1) PRIMARY KEY,
    ProjectId INT NOT NULL,
    TaskDescription NVARCHAR(255) NOT NULL,
    AssignedMemberId INT NOT NULL DEFAULT 0,
    
    -- Exclusão do projeto apaga as tarefas dele (ON DELETE CASCADE)
    CONSTRAINT FK_Tasks_Projects FOREIGN KEY (ProjectId) REFERENCES dbo.Projects(ProjectId)
        ON DELETE CASCADE,
        
    -- Exclusão do membro alocado redefine para o padrão (ON DELETE SET DEFAULT)
    CONSTRAINT FK_Tasks_Members FOREIGN KEY (AssignedMemberId) REFERENCES dbo.TeamMembers(MemberId)
        ON DELETE SET DEFAULT
);
```

---

## Problemas Comuns e Soluções (Common Issues)

| Erro | Causa | Solução |
| :--- | :--- | :--- |
| Violação de FK no INSERT | O registro pai referenciado não existe | Insira o registro pai correspondente antes; ou desligue a FK temporariamente. |
| Violação de PK ou UNIQUE | Tentativa de inserir chave duplicada | Verifique duplicidades na origem; use rotinas com `MERGE` ou upsert. |
| Violação de CHECK constraint | O valor viola o predicado lógico | Adicione validações na aplicação antes de submeter ao banco. |
| Lacunas (gaps) na Sequence | Valores em cache perdidos, rollbacks ou valores reservados sem uso | Avalie `NO CACHE` para reduzir lacunas por falhas; para ausência absoluta de lacunas, use controle transacional serializado. |
| Erro de cascata circular | Ciclos nas chaves externas | Mude para `NO ACTION` em algum ponto da cadeia e trate na aplicação. |
| Constraint não confiável | Habilitada sem validação (`NOCHECK`) | Execute a validação com a cláusula `WITH CHECK CHECK CONSTRAINT`. |

---

## Melhores Práticas (Best Practices)

- Nomeie todas as constraints explicitamente (`CONSTRAINT PK_...`, `CONSTRAINT FK_...`) em vez de deixar o SQL Server gerar nomes aleatórios automaticamente — facilita a manutenção de migrações e scripts.
- Sempre dê preferência à instrução `WITH CHECK CHECK CONSTRAINT` ao reativar constraints para certificar-se de que os dados históricos são válidos e restaurar a confiança do otimizador (`trusted`).
- Só use `WITH NOCHECK` em migrações massivas de dados urgentes; faça a validação logo em seguida.
- Evite cascatas longas (`CASCADE DELETE`) em cadeias complexas de tabelas — deleções lógicas ou em Stored Procedures são mais fáceis de auditar e depurar.
- Mantenha `CACHE` ativo em sequences, exceto se a regra de negócio for de lacuna zero absoluta, devido ao impacto de I/O em taxas de escrita massivas.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - `PRIMARY KEY` cria um índice clustered por padrão quando a tabela ainda não possui um clustered index e `NONCLUSTERED` não foi especificado.
> - A UNIQUE constraint clássica restringe a coluna a apenas um único NULL; para comportar múltiplos NULLs use um index único filtrado (`WHERE col IS NOT NULL`).
> - CHECK constraints aplicadas com `WITH NOCHECK` recebem a flag `is_not_trusted = 1` e são ignoradas pelo otimizador de consultas na simplificação de planos.
> - `SEQUENCE` aceita as configurações de `CYCLE` (retroceder ao atingir o limite) e `CACHE`. Os valores no cache são perdidos ao reiniciar o serviço do banco de dados.
> - Relacionamentos FK cíclicos ou em loop não suportam a propriedade `CASCADE` — o SQL Server gera erro no momento da criação da chave.
> - O modificador `NOT FOR REPLICATION` nas chaves e checks evita disparos desnecessários causados pelas transações dos agentes de replicação.

---

## Resumo dos Conceitos (Key Takeaways)

- Constraints garantem a integridade relacional diretamente na camada de banco de dados, protegendo contra corrupção.
- Ações referenciais (`CASCADE`, `SET NULL`, `SET DEFAULT`) automatizam a manutenção dos registros órfãos nas tabelas filhas.
- SEQUENCES oferecem geradores de números sequenciais flexíveis desacoplados de tabelas, diferentemente da IDENTITY.
- As constraints não confiáveis (não validadas após bulk loads) degradam otimizações de planos de consultas.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma sequence configurada com `CACHE 50` possui o valor corrente de 450. O servidor de banco de dados SQL Server sofre um reinício abrupto de energia. Ao retornar, o primeiro valor obtido da sequence é 501. Qual é o motivo desse comportamento?

A. O comportamento de `CYCLE` fez a sequence retroceder e reiniciar.

B. Os valores mantidos no cache (451 a 500) foram perdidos no reinício do serviço.

C. A sequence foi modificada via comando DDL `ALTER SEQUENCE ... RESTART WITH 501`.

D. Uma transação concorrente no momento da queda consumiu os valores remanescentes.

> [!success]- Resposta
> **B — Os valores mantidos no cache (451 a 500) foram perdidos no reinício do serviço.**
>
> **Explicação Detalhada:**
> 1. **Alocação em Bloco (RAM)**: Ao configurar CACHE 50 em uma Sequence e o valor corrente ser 450, o SQL Server pré-aloca os números de **451 a 500** na memória RAM para acelerar as requisições, gravando em disco que a próxima faixa disponível começará em **501**.
> 2. **Perda de Dados em RAM (Crash)**: Com a queda abrupta de energia, o conteúdo da memória RAM é totalmente limpo. Os valores de 451 a 500 reservados em cache foram perdidos antes de serem entregues por requisições NEXT VALUE FOR.
> 3. **Retorno do Serviço**: Ao reiniciar, o SQL Server lê do disco que a faixa até 500 já havia sido previamente alocada/concedida, disponibilizando o valor **501** na chamada seguinte e gerando uma lacuna (*gap*).
>
> **Análise das Alternativas Incorretas:**
> - **A (CYCLE)**: O parâmetro CYCLE reinicia a contagem a partir do MINVALUE ao atingir o MAXVALUE, e não um salto adiante de 450 para 501.
> - **C (ALTER SEQUENCE)**: O cenário especifica uma queda de energia do servidor, não uma alteração manual via DDL.
> - **D (Transação concorrente)**: Se houvesse consumo por transações, os números teriam sido gravados/utilizados em tabelas do banco; a queda interrompeu o servidor antes que os números fossem emitidos.
---

## Tópicos Relacionados

- [01-Tables & Indexes](./01-tables-indexes.md)
- [05-Partitioning](./05-partitioning.md)

---

## Documentação Oficial

- [Constraints (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/tables/unique-constraints-and-check-constraints)
- [CREATE SEQUENCE (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-sequence-transact-sql)

---

**[← Anterior](./03-json-columns.md) | [↑ Voltar para a Seção](./database-objects.md) | [Próximo →](./05-partitioning.md)**
