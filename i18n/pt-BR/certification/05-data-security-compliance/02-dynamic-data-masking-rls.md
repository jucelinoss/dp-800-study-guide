---
title: Máscaras Dinâmicas de Dados e Segurança em Nível de Linha (Dynamic Data Masking and Row-Level Security)
type: study-material
tags:
  - dp-800
  - dynamic-data-masking
  - row-level-security
  - rls
  - ddm
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Máscaras Dinâmicas de Dados (DDM)](#máscaras-dinâmicas-de-dados-ddm)
>   - 🔹 [Funções de Mascaramento (Masking Functions)](#funções-de-mascaramento-masking-functions)
>   - 🔹 [Aplicando DDM em Colunas via DDL](#aplicando-ddm-em-colunas-via-ddl)
>   - 🔹 [Gestão de Permissões de Unmask](#gestão-de-permissões-de-unmask)
> - 📍 [3. Segurança em Nível de Linha (RLS)](#segurança-em-nível-de-linha-rls)
>   - 🔹 [Arquitetura de Execução](#arquitetura-de-execução)
>   - 🔹 [Implementando Filtro de RLS (Filter Predicate)](#implementando-filtro-de-rls-filter-predicate)
>   - 🔹 [Predicados de Bloqueio (Block Predicates)](#predicados-de-bloqueio-block-predicates)
>   - 🔹 [Padrão Multi-Tenant Utilizando SESSION_CONTEXT](#padrão-multi-tenant-utilizando-session-context)
>   - 🔹 [Gestão das Políticas de RLS](#gestão-das-políticas-de-rls)
> - 📍 [4. Quadro Comparativo: DDM vs RLS](#quadro-comparativo-ddm-vs-rls)
> - 📍 [5. Casos de Uso (Use Cases)](#casos-de-uso-use-cases)
> - 📍 [6. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [7. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [8. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [9. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [10. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [11. Documentação Oficial](#documentação-oficial)

---

# Máscaras Dinâmicas de Dados e Segurança em Nível de Linha (Dynamic Data Masking and Row-Level Security)

## Visão Geral (Overview)

O recurso de **Máscaras Dinâmicas de Dados** (DDM - Dynamic Data Masking) ofusca valores confidenciais de colunas para usuários não autorizados no momento da query, sem alterar os dados persistidos fisicamente. A **Segurança em Nível de Linha** (RLS - Row-Level Security) controla quais linhas específicas da tabela um usuário consegue ler ou modificar baseando-se em uma função de predicado de segurança.

> [!abstract]
>
> - Cobre Dynamic Data Masking (DDM) e Row-Level Security (RLS) — dois recursos complementares de controle de acessos lógicos.
> - O DDM oculta valores de colunas específicas; o RLS oculta registros inteiros (linhas) — ambos de forma transparente para as aplicações.
> - Tópicos chave do exame: tipos de máscaras do DDM, limitações de segurança do DDM, criação de funções de filtro de RLS e diferença de predicados filter vs block.

> [!tip] O que o Exame Testa
>
> - **DDM**: Mascara valores em tempo de consulta; NÃO criptografa; usuários com permissão de `UNMASK` visualizam os dados planos; dispõe de quatro funções: `default()`, `email()`, `partial()`, `random()`.
> - **RLS**: Cria políticas de segurança (`CREATE SECURITY POLICY`) vinculadas a funções inline TVFs; **filter predicate** = restringe leituras de `SELECT`; **block predicate** = bloqueia modificações DML que violem as condições.
> - A filtragem do RLS ocorre silenciosamente — o usuário restrito apenas recebe menos registros, sem nenhum alerta de que existem dados ocultados.

---

## Máscaras Dinâmicas de Dados (DDM)

O DDM aplica regras de máscara em colunas do banco — usuários comuns visualizam strings parciais ou nulos, enquanto contas autorizadas com privilégio de `UNMASK` acessam os valores reais.

### Funções de Mascaramento (Masking Functions)

| Função | Sintaxe Exemplo | Retorno da Query |
| :--- | :--- | :--- |
| **default()** | `MASKED WITH (FUNCTION = 'default()')` | Exibe `xxxx` para textos, `0` para números e `01/01/1900` para datas. |
| **email()** | `MASKED WITH (FUNCTION = 'email()')` | Retorna o formato `aXXX@XXXX.com`. |
| **random(m,n)** | `MASKED WITH (FUNCTION = 'random(1,100)')` | Substitui o valor por um número randômico na faixa de 1 a 100. |
| **partial(p,s,l)** | `MASKED WITH (FUNCTION = 'partial(2,"XXXX",2)')` | Expõe 2 caracteres iniciais, aplica string "XXXX", expõe 2 finais. |
| **datetime(format)** | `MASKED WITH (FUNCTION = 'datetime("Y-M-D")')` | Exibe apenas partes da data desejada. |

### Aplicando DDM em Colunas via DDL

```sql
-- Criar tabela especificando as regras de DDM
CREATE TABLE dbo.Customers (
    CustomerId  int             NOT NULL PRIMARY KEY,
    Name        nvarchar(100)   NOT NULL,
    Email       nvarchar(200)   MASKED WITH (FUNCTION = 'email()'),
    Phone       varchar(20)     MASKED WITH (FUNCTION = 'partial(0,"XXX-XXX-",4)'),
    CreditLimit money           MASKED WITH (FUNCTION = 'default()')
);

-- Adicionar máscara a uma coluna de tabela existente
ALTER TABLE dbo.Customers
ALTER COLUMN SSN char(11)
MASKED WITH (FUNCTION = 'partial(0,"XXX-XX-",4)');

-- Remover a regra de máscara de uma coluna
ALTER TABLE dbo.Customers
ALTER COLUMN SSN char(11) DROP MASKED;
```

> [!important] DDM Não Criptografa os Dados do Banco
>
> - O **Dynamic Data Masking** mascara os valores no momento da consulta (on-the-fly). Os dados continuam salvos de forma legível e sem criptografia no disco.
> - **Cuidado de Exame**: Usuários mal-intencionados com permissões de `SELECT` podem inferir dados mascarados por força bruta (ex: `WHERE CreditCard LIKE '4%'`). Para criptografia física real, use Always Encrypted.

### Gestão de Permissões de Unmask

```sql
-- Conceder permissão de UNMASK para um usuário visualizar dados planos de toda a tabela
GRANT UNMASK ON dbo.Customers TO [AnalystUser];

-- Conceder permissão de UNMASK apenas a nível de coluna (Disponível a partir do SQL Server 2022)
GRANT UNMASK ON dbo.Customers(Email) TO [MarketingUser];

-- Consultar colunas mascaradas ativas no banco
SELECT * FROM sys.masked_columns;
```

---

## Segurança em Nível de Linha (RLS)

O RLS isola dados em nível de registros na tabela baseando-se em uma lógica definida em uma função inline TVF.

### Arquitetura de Execução

```text
Query do Usuário → Função de Predicado RLS → Retorno das Linhas Filtradas
```

### Implementando Filtro de RLS (Filter Predicate)

```sql
-- Passo 1: Criar a função de predicado de segurança
CREATE FUNCTION Security.fn_OrderFilter (
    @CustomerId int
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT 1 AS fn_result
    WHERE
        -- Contas administrativas dbo enxergam tudo
        USER_NAME() = 'dbo'
        OR
        -- Clientes enxergam apenas seus respectivos registros via SESSION_CONTEXT
        @CustomerId = CAST(SESSION_CONTEXT(N'CustomerId') AS int)
);
GO

-- Passo 2: Criar e habilitar a Security Policy vinculando a função à tabela
CREATE SECURITY POLICY OrderFilterPolicy
ADD FILTER PREDICATE Security.fn_OrderFilter(CustomerId)
ON dbo.Orders
WITH (STATE = ON);
```

> [!tip] A Importância do SCHEMABINDING no RLS
>
> - Ao criar a função de filtro de segurança para o RLS, ela **deve** ser declarada obrigatoriamente com a opção `WITH SCHEMABINDING`.
> - O schemabinding vincula a função à estrutura da tabela, impedindo alterações acidentais de DDL na tabela que quebrem a lógica do filtro de RLS.

### Predicados de Bloqueio (Block Predicates)

Os predicados de bloqueio (Block Predicates) estendem o RLS impedindo que o usuário execute comandos `INSERT`, `UPDATE` ou `DELETE` que criem registros que ele próprio não conseguiria visualizar posteriormente:

```sql
CREATE SECURITY POLICY SalesRepPolicy
ADD FILTER PREDICATE Security.fn_SalesRepFilter(SalesRepId)
    ON dbo.Opportunities,
ADD BLOCK PREDICATE Security.fn_SalesRepFilter(SalesRepId)
    ON dbo.Opportunities AFTER INSERT,
ADD BLOCK PREDICATE Security.fn_SalesRepFilter(SalesRepId)
    ON dbo.Opportunities AFTER UPDATE
WITH (STATE = ON);
```

> [!warning] Dica de Exame: Filter vs Block Predicates
>
> - **FILTER PREDICATE**: Filtra silenciosamente as linhas retornadas em consultas `SELECT`, `UPDATE` e `DELETE`. O usuário não recebe erro, apenas enxerga menos linhas.
> - **BLOCK PREDICATE**: Bloqueia de forma ativa operações de gravação (`INSERT`, `UPDATE`, `DELETE`) que violem as condições de visualização, lançando um erro de exceção caso o usuário tente burlar a regra.

**Tipos de Operações nos Predicados:**

| Tipo | Aplica-se A | Efeito |
| :--- | :--- | :--- |
| `FILTER` | SELECT, UPDATE, DELETE | Filtra registros não elegíveis de forma silenciosa (sem erros). |
| `BLOCK AFTER INSERT` | INSERT | Bloqueia inserções de novas linhas que ficariam invisíveis para o usuário. |
| `BLOCK AFTER UPDATE` | UPDATE | Bloqueia modificações que fariam as linhas existentes sumirem do filtro. |
| `BLOCK BEFORE UPDATE` | UPDATE | Bloqueia alterações em registros que estão invisíveis no momento. |
| `BLOCK BEFORE DELETE` | DELETE | Bloqueia exclusões de registros invisíveis sob o RLS atual. |

### Padrão Multi-Tenant Utilizando SESSION_CONTEXT

```sql
-- Definir o contexto da conexão a partir da aplicação (Tenant ID = 42)
EXEC sp_set_session_context @key = N'TenantId', @value = 42, @read_only = 1;

-- Função de predicado lê o TenantId do SESSION_CONTEXT
CREATE FUNCTION Security.fn_TenantFilter (@TenantId int)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN (
    SELECT 1 AS fn_result
    WHERE @TenantId = CAST(SESSION_CONTEXT(N'TenantId') AS int)
        OR IS_MEMBER('db_owner') = 1
);
```

### Gestão das Políticas de RLS

```sql
-- Desativar temporariamente uma política
ALTER SECURITY POLICY OrderFilterPolicy WITH (STATE = OFF);

-- Habilitar novamente a política
ALTER SECURITY POLICY OrderFilterPolicy WITH (STATE = ON);

-- Excluir a política
DROP SECURITY POLICY OrderFilterPolicy;

-- Consultar metadados de políticas de segurança ativas no banco
SELECT * FROM sys.security_policies;
SELECT * FROM sys.security_predicates;
```

---

## Quadro Comparativo: DDM vs RLS

| Característica | Máscaras Dinâmicas (DDM) | Segurança de Linhas (RLS) |
| :--- | :--- | :--- |
| **O que é ocultado** | Valores específicos de colunas. | Registros/linhas inteiras. |
| **Visão do Usuário** | Exibe caracteres de máscara (ex: `xxxx`); linha retorna. | A linha inteira some silenciosamente da consulta. |
| **Evita inferências** | Não (pode inferir filtrando WHERE). | Sim (o registro não é mapeável na query). |
| **Mecanismo** | Propriedade direta da coluna. | Função Inline TVF + Security Policy. |
| **Objetivo Ideal** | Exibição de interfaces e proteção visual de PII. | `Isolamento seguro de clientes (Multi-tenant)`. |

---

## Casos de Uso (Use Cases)

- **DDM**: Painéis de suporte ao cliente — atendentes visualizam apenas os últimos 4 dígitos do telefone; cópias de bancos produtivos limpas para ambientes de testes.
- **RLS Filter**: Aplicações SaaS Multi-tenant — garantia física de que o Tenant A nunca liste dados do Tenant B.
- **RLS Block**: Evitar que vendedores de uma regional gravem oportunidades sob responsabilidade de outras regionais de vendas.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Predicado RLS não filtra dados | Lógica interna da UDF falha em retornar 1 | Teste a função de forma isolada passando IDs mockados. |
| Recursão infinita do RLS | A UDF consulta a própria tabela protegida | Crie tabelas de segurança separadas; evite consultas cíclicas na UDF. |
| DDM contornado por usuário comum | A conta possui grant de `UNMASK` ou é `db_owner` | Revise privilégios no banco; o DDM não oculta dados para administradores do banco. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - O DDM mascara a amostragem final de dados mas **não serve como barreira de segurança contra força bruta** (inferências de WHERE).
> - As UDFs do RLS exigem obrigatoriamente a opção de compilação **`WITH SCHEMABINDING`**.
> - O padrão **`SESSION_CONTEXT`** é a melhor prática recomendada para passar parâmetros de isolamento das aplicações para o RLS.
> - Conheça a diferença entre predicados: `FILTER` oculta linhas de leituras; `BLOCK` barra operações de escrita não autorizadas.

---

## Resumo dos Conceitos (Key Takeaways)

- DDM atua na camada de apresentação (ofuscamento de caracteres).
- RLS atua no isolamento físico lógico de registros (escondendo linhas).
- Combine DDM e RLS para obter políticas de segurança robustas e em conformidade com leis de privacidade de dados.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Você está modelando uma solução multi-tenant no Azure SQL Database para um ERP de vendas. Cada cliente (tenant) deve visualizar exclusivamente os seus próprios pedidos. Adicionalmente, as tentativas de inserção de novas linhas sob IDs de outros tenants devem ser ativamente bloqueadas pelo banco de dados. Qual abordagem atende a essa exigência de forma completa?

A. Criar regras de Dynamic Data Masking nas colunas de TenantId.

B. Implementar uma política de Row-Level Security (RLS) configurada exclusivamente com um FILTER PREDICATE.

C. Implementar uma política de Row-Level Security (RLS) configurada com um FILTER PREDICATE e comandos de BLOCK PREDICATE (AFTER INSERT/AFTER UPDATE).

D. Controlar os acessos realizando mapeamentos de tabelas externas em schemas distintos por Tenant.

> [!success]- Resposta
> **C — Implementar uma política de Row-Level Security (RLS) configurada com um FILTER PREDICATE e comandos de BLOCK PREDICATE (AFTER INSERT/AFTER UPDATE)**
>
> O `FILTER PREDICATE` garante que comandos de leitura (`SELECT`) exibam silenciosamente apenas os registros do respectivo tenant. Para impedir de forma ativa que um usuário grave ou altere registros que fujam ao seu escopo de visualização (lançando exceções e cancelando a escrita), a associação de `BLOCK PREDICATE` na política de RLS é indispensável. O DDM (A) oculta apenas valores e não restringe registros.

---

## Tópicos Relacionados

- [01-Criptografia de Dados](./01-encryption.md)
- [03-Permissões & Acessos](./03-permissions-access.md) *(Inglês apenas)*

---

## Documentação Oficial

- [Dynamic Data Masking](https://learn.microsoft.com/en-us/sql/relational-databases/security/dynamic-data-masking)
- [Row-Level Security (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/security/row-level-security)

---

**[← Anterior](./01-encryption.md) | [↑ Voltar para a Seção](./data-security-compliance.md) | [Próximo →](./03-permissions-access.md)**
