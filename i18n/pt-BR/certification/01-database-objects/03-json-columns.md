---
title: Colunas e Índices JSON
type: study-material
tags:
  - dp-800
  - json
  - json-columns
  - indexes
---

# Colunas e Índices JSON

## Visão geral

O SQL Server pode armazenar texto JSON em colunas `varchar` ou `nvarchar`. O
tipo nativo `json` está disponível de forma geral no Azure SQL Database e no
Azure SQL Managed Instance sob a política SQL Server 2025 ou Always-up-to-date;
no SQL Server 2025 (17.x), ele continua em preview. Este capítulo trata da
escolha de armazenamento, integridade persistente e indexação de atributos JSON.

> [!abstract]
>
> - Escolha entre colunas relacionais, documentos JSON em `nvarchar` e o tipo nativo `json`.
> - Valide documentos no limite de escrita e defina quais atributos precisam de acesso relacional.
> - Indexe propriedades JSON consultadas com frequência por colunas computadas; funções de leitura e transformação ficam no capítulo de funções JSON.

> [!tip] O que o exame testa
>
> - Um documento JSON não substitui colunas relacionais que precisam de chaves, restrições, joins e filtros frequentes.
> - `ISJSON` e `CHECK` protegem a validade do documento, mas não comprovam que todas as propriedades de negócio existam.
> - Índices em colunas computadas tornam um atributo JSON frequentemente filtrado acessível por um índice B-tree comum.

---

## Armazenando dados JSON

```sql
-- Abordagem tradicional: texto JSON em nvarchar.
CREATE TABLE dbo.Products (
    ProductId   int             NOT NULL PRIMARY KEY,
    Name        nvarchar(200)   NOT NULL,
    Attributes  nvarchar(max)   NULL,
    CONSTRAINT CK_Products_Attributes
        CHECK (ISJSON(Attributes) = 1)
);

-- Tipo nativo json: GA em serviços Azure elegíveis e preview no SQL Server 2025.
CREATE TABLE dbo.Events (
    EventId     int     NOT NULL PRIMARY KEY CLUSTERED,
    Payload     json    NULL
);
```

## Acessando documentos armazenados

A decisão de armazenamento é diferente da decisão de consulta. Armazene um
conjunto flexível de atributos em `Attributes` e use a função adequada para
extrair, desmembrar, filtrar, montar ou alterar o documento. Funções, caminhos
JSON, `OPENJSON`, modos de caminho e `FOR JSON` são detalhados em
[Funções JSON](../03-advanced-tsql/02-json-functions.md).

Para este capítulo, o ponto central é que o padrão de acesso determina o índice.
Se uma consulta filtra repetidamente `$.color`, exponha esse escalar em uma
coluna computada e a indexe, em vez de esperar uma busca eficiente em uma
expressão não indexada do documento.

---

## Índices JSON

Para filtrar ou ordenar propriedades JSON com eficiência, crie uma coluna
computada e um índice sobre ela:

```sql
ALTER TABLE dbo.Products
ADD Color AS JSON_VALUE(Attributes, '$.color');

CREATE INDEX IX_Products_Color ON dbo.Products (Color);

SELECT *
FROM dbo.Products
WHERE Color = N'blue';
```

A abordagem com coluna computada funciona com texto JSON e com o tipo nativo
`json`. O SQL Server 2025 (17.x) Preview também introduz `CREATE JSON INDEX`
para uma coluna do tipo nativo `json`. Um índice JSON exige chave primária
clusterizada e, no SQL Server, ainda é um recurso preview:

```sql
CREATE JSON INDEX IX_Events_Payload
ON dbo.Events (Payload)
FOR ('$.userId');
```

---

## Colunas computadas para indexação

**Problema:** sem um índice padrão ou índice JSON adequado, um filtro com
`JSON_VALUE` pode exigir a varredura das linhas candidatas.

> [!note] Scan de tabela e scan de índice clusterizado
>
> Um filtro em `JSON_VALUE(...)` sem índice adequado pode levar o mecanismo a
> inspecionar cada linha e avaliar a expressão.
>
> - Em uma heap, o plano pode exibir **Table Scan**.
> - Em uma tabela com índice clusterizado, o plano pode exibir **Clustered Index Scan**.
>
> O operador real depende da estrutura, das estatísticas e da consulta. Use o
> plano de execução real e as leituras lógicas para confirmar o comportamento.

**Solução:** extraia a propriedade para uma coluna computada e crie um índice
quando ela atender aos requisitos de indexabilidade. Uma coluna `PERSISTED`
armazena fisicamente o resultado e pode ser escolhida conforme o custo de
escrita e armazenamento; ela não é pré-requisito universal para indexar.

```sql
ALTER TABLE Orders
ADD ShipCountry AS JSON_VALUE(ShippingJSON, '$.country') PERSISTED;

CREATE INDEX IX_Orders_ShipCountry ON Orders(ShipCountry);

SELECT OrderID, TotalAmount
FROM Orders
WHERE JSON_VALUE(ShippingJSON, '$.country') = N'US';

CREATE INDEX IX_Orders_UK_Country
ON Orders(ShipCountry, TotalAmount)
WHERE ShipCountry = N'UK';
```

---

## Casos de uso

- **Catálogos de produtos:** atributos variáveis por tipo de produto.
- **Eventos:** payloads com esquema flexível.
- **Integração de APIs:** armazenamento de respostas REST.
- **Configuração:** propriedades estruturadas de uma aplicação.

---

## Problemas comuns

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| Consultas JSON lentas | Não há índice para uma propriedade muito consultada | Crie coluna computada e índice para a propriedade |
| `ISJSON` retorna 0 | Há JSON malformado na coluna | Adicione `CHECK` na escrita e valide também na aplicação quando necessário |
| Resultado inesperado em consulta JSON | Caminho, modo ou função incompatível com o formato esperado | Revise caminhos e `JSON_VALUE` versus `JSON_QUERY` em [Funções JSON](../03-advanced-tsql/02-json-functions.md) |

---

## Melhores práticas

- Use `CHECK (ISJSON(coluna) = 1)` em colunas `nvarchar` que devem conter JSON válido.
- Mantenha em colunas relacionais os atributos frequentemente filtrados, unidos, restringidos ou sensíveis à segurança.
- Use coluna computada e índice quando um escalar JSON é pesquisado repetidamente.
- Desmembre JSON durante a carga quando os valores precisam de acesso relacional durável.
- Consulte o capítulo de funções para extração, modo de caminho e serialização.

---

## Dicas para o exame

> [!tip] Dicas para o exame
>
> - JSON é adequado para atributos flexíveis ou orientados a documento; fatos fortemente relacionais permanecem relacionais.
> - `ISJSON` valida a sintaxe do documento; regras adicionais são necessárias para propriedades obrigatórias.
> - Para filtrar um escalar JSON com eficiência, exponha-o por coluna computada e índice.
> - `JSON_VALUE`, `OPENJSON`, caminhos `strict`/`lax` e saída JSON são tratados em [Funções JSON](../03-advanced-tsql/02-json-functions.md).

---

## Resumo

- JSON pode ser texto em `varchar` ou `nvarchar`; o tipo nativo `json` tem disponibilidade específica por plataforma.
- Sintaxe JSON válida é uma preocupação de integridade de armazenamento; funções JSON são uma preocupação de consulta.
- Índices em colunas computadas fornecem um caminho relacional para escalares JSON consultados com frequência.
- Padrões de funções, caminhos, parsing e serialização estão em [Funções JSON](../03-advanced-tsql/02-json-functions.md).

---

## Questão de prática

Uma tabela possui a coluna JSON `Metadata` e uma consulta filtra
`JSON_VALUE(Metadata, '$.region') = 'EU'`. A consulta está lenta. Qual é a
melhor solução?

A. Usar `FOR JSON PATH` para reformatar os dados

B. Adicionar uma coluna computada para `JSON_VALUE(Metadata, '$.region')` e indexá-la

C. Trocar por `OPENJSON` para melhorar o desempenho

D. Habilitar o modo strict do caminho JSON

> [!success]- Resposta
> **B — Adicionar uma coluna computada para `JSON_VALUE(Metadata, '$.region')` e indexá-la**
>
> Uma coluna computada expõe o valor extraído e um índice pode atender ao predicado quando expressão e consulta são compatíveis. `OPENJSON` desmembra arrays e não melhora esse filtro. O modo strict altera o comportamento de erro, não a velocidade.

---

## Tópicos relacionados

- [Funções JSON](../03-advanced-tsql/02-json-functions.md)
- [Tabelas e índices](./01-tables-indexes.md)

## Documentação oficial

- [Dados JSON no SQL Server](https://learn.microsoft.com/pt-br/sql/relational-databases/json/json-data-sql-server)
- [Indexar dados JSON](https://learn.microsoft.com/pt-br/sql/relational-databases/json/index-json-data)
- [CREATE JSON INDEX (Transact-SQL)](https://learn.microsoft.com/pt-br/sql/t-sql/statements/create-json-index-transact-sql)

---

**[← Anterior](./02-specialized-tables.md) | [↑ Voltar à seção](./database-objects.md) | [Lab: Colunas e Índices JSON](../../practice/labs/01-database-objects/03-json-columns-lab.sql) | [Próximo →](./04-constraints-sequences.md)**
