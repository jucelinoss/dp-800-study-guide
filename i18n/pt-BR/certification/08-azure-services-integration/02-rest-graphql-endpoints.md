---
title: Endpoints REST e GraphQL no Data API Builder (DAB) (REST and GraphQL Endpoints in DAB)
type: study-material
tags:
  - dp-800
  - rest
  - graphql
  - endpoints
  - pagination
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Configuração do Endpoint REST](#configuração-do-endpoint-rest)
>   - 🔹 [Configurações Globais do REST](#configurações-globais-do-rest)
>   - 🔹 [Configurações de Entidade no REST](#configurações-de-entidade-no-rest)
> - 📍 [3. Métodos HTTP no REST do DAB](#métodos-http-no-rest-do-dab)
>   - 🔹 [Consultas de Leitura (GET)](#consultas-de-leitura-get)
>   - 🔹 [Inserção de Registros (POST)](#inserção-de-registros-post)
>   - 🔹 [Substituição Completa (PUT)](#substituição-completa-put)
>   - 🔹 [Atualização Parcial (PATCH)](#atualização-parcial-patch)
>   - 🔹 [Expondo Stored Procedures via REST](#expondo-stored-procedures-via-rest)
> - 📍 [4. Configuração do Endpoint GraphQL](#configuração-do-endpoint-graphql)
>   - 🔹 [Configurações Globais do GraphQL](#configurações-globais-do-graphql)
>   - 🔹 [Mapeamento das Entidades para GraphQL](#mapeamento-das-entidades-para-graphql)
>   - 🔹 [Escrita de Queries no GraphQL](#escrita-de-queries-no-graphql)
>   - 🔹 [Escrita de Mutations (Gravações) no GraphQL](#escrita-de-mutations-gravações-no-graphql)
>   - 🔹 [Consultas Aninhadas via Relacionamentos (Nested Queries)](#consultas-aninhadas-via-relacionamentos-nested-queries)
>   - 🔹 [Chamadas de Stored Procedures no GraphQL](#chamadas-de-stored-procedures-no-graphql)
> - 📍 [5. Configurações e Gerenciamento de Cache](#configurações-e-gerenciamento-de-cache)
> - 📍 [6. Paginação Baseada em Cursores](#paginação-baseada-em-cursores)
> - 📍 [7. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [8. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [9. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [10. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [11. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [12. Documentação Oficial](#documentação-oficial)

---

# Endpoints REST e GraphQL no Data API Builder (DAB) (REST and GraphQL Endpoints in DAB)

## Visão Geral (Overview)

O Data API Builder expõe endpoints REST e GraphQL de forma simultânea a partir das mesmas definições do arquivo de configuração JSON. O REST adota convenções OData para filtros passados diretamente na URL da requisição; o GraphQL oferece consultas flexíveis com tipagem e esquemas estruturados. Ambos contam com paginação nativa, caching e políticas de segurança.

> [!abstract]
>
> - Cobre os padrões de endpoints REST e GraphQL gerados pelo DAB, incluindo consultas, paginação, filtros e escritas (mutations).
> - REST e GraphQL retornam os mesmos dados utilizando estilos de consultas distintos — REST emprega variáveis de URL; GraphQL adota o corpo da requisição.
> - Tópicos chave do exame: padrões de URLs do REST, sintaxes de query/mutation do GraphQL, paginação e filtros em formato OData.

> [!tip] O que o Exame Testa
>
> - REST: `GET /api/Book` = lista todos; `GET /api/Book/1` = busca por chave primária (PK); filtros via `?$filter=year eq 2024` com suporte a `$orderby`, `$select` e paginação.
> - GraphQL: Rota única no endpoint `/graphql`; as mutações de escrita são auto-geradas no padrão `create{Entidade}`, `update{Entidade}` e `delete{Entidade}`.
> - Paginação no GraphQL adota cursores baseados em parâmetros `first` e `after`, em vez de offsets tradicionais baseados em pulos.

---

## Configuração do Endpoint REST

### Configurações Globais do REST

```json
{
  "runtime": {
    "rest": {
      "enabled": true,
      "path": "/api",
      "request-body-strict": true
    }
  }
}
```

- `path`: Caminho raiz base das chamadas de API (padrão é `/api`).
- `request-body-strict`: Quando ativo (`true`), o DAB rejeita requisições JSON que contenham chaves não mapeadas nas colunas físicas da tabela.

### Configurações de Entidade no REST

```json
"Order": {
  "source": { "object": "dbo.Orders", "type": "table" },
  "fields": [{ "name": "OrderId", "primary-key": true }],
  "rest": {
    "enabled": true,
    "path": "orders"
  }
}
```

O caminho da rota REST assume por padrão o próprio nome da entidade mapeada, podendo ser alterado manualmente pela propriedade `path` do bloco.

---

## Métodos HTTP no REST do DAB

| Método | Ação do Banco | Padrão de URL | Corpo do Request |
| :--- | :--- | :--- | :--- |
| GET | Consulta de registros (um ou vários) | `/api/Order` ou `/api/Order/42` | Vazio |
| POST | Inserção de novo registro | `/api/Order` | JSON com dados da linha |
| PUT | Substituição integral (full replace) | `/api/Order/42` | JSON completo do registro |
| PATCH | `Atualização parcial` | `/api/Order/42` | JSON com apenas campos modificados |
| DELETE | Remoção de registro | `/api/Order/42` | Vazio |

> [!important] Comportamento Crucial de Escrita: PUT vs PATCH no DAB
>
> - **PUT**: Substitui um recurso existente ou pode criá-lo se ele não existir e a tabela aceitar uma chave primária explícita.
> - **PATCH**: Atualiza parcialmente um recurso existente ou pode criá-lo nas mesmas condições. Em tabelas com chave autogerada, uma chave inexistente retorna `404`; use `POST` para criar.

### Consultas de Leitura (GET)

```bash
# Obter todas as ordens (Paginadas por padrão)
GET /api/Order

# Obter uma ordem específica por chave primária (PK)
GET /api/Order/42

# Filtrar registros: Status = 'Active' e CustomerId = 100
GET /api/Order?$filter=Status eq 'Active' and CustomerId eq 100

# Selecionar colunas específicas no retorno
GET /api/Order?$select=OrderId,Status,OrderDate

# Ordenar por data de forma decrescente
GET /api/Order?$orderby=OrderDate desc

# Limitar e paginar: obter os primeiros 10 registros
GET /api/Order?$first=10&$orderby=OrderDate desc

# Carregar a próxima página passando o token de cursor recebido
GET /api/Order?$first=10&$after=eyJPcmRlcklkIjoxMH0=
```

### Inserção de Registros (POST)

```bash
POST /api/Order
Content-Type: application/json

{
  "CustomerId": 42,
  "Status": "Pending",
  "TotalAmount": 99.99
}
```

Resposta de sucesso (201 Created):

```json
{
  "value": [
    { "OrderId": 1001, "CustomerId": 42, "Status": "Pending", "TotalAmount": 99.99 }
  ]
}
```

### Substituição Completa (PUT)

```bash
PUT /api/Order/1001
Content-Type: application/json

{
  "CustomerId": 42,
  "Status": "Shipped",
  "TotalAmount": 99.99
}
```

*Nota*: O uso de `PUT` representa substituição do recurso. Teste o payload no schema e no ambiente-alvo; para alterar somente campos específicos, prefira `PATCH`.

### Atualização Parcial (PATCH)

```bash
PATCH /api/Order/1001
Content-Type: application/json

{
  "Status": "Delivered"
}
```

*Nota*: Apenas o campo `Status` sofrerá modificação no banco de dados, mantendo os outros dados da linha intactos.

### Expondo Stored Procedures via REST

```json
"SearchProducts": {
  "source": {
    "object": "dbo.SearchProducts",
    "type": "stored-procedure",
    "parameters": {
      "SearchTerm": "string",
      "MaxPrice": "number"
    }
  },
  "rest": {
    "enabled": true,
    "methods": ["GET"]
  },
  "permissions": [{ "role": "anonymous", "actions": ["execute"] }]
}
```

Para invocar a stored procedure configurada para requisições GET, forneça os parâmetros na URL:

```bash
GET /api/SearchProducts?SearchTerm=widget&MaxPrice=50
```

Se a stored procedure realizar modificações ou inserções de dados, altere a configuração para usar o método `post`:

```bash
POST /api/CreateOrder
Content-Type: application/json

{
  "CustomerId": 42,
  "ProductId": 7,
  "Quantity": 3
}
```

> [!tip] Métodos REST para Stored Procedures
>
> - Por padrão, stored procedures são expostas no REST utilizando o método **`POST`**.
> - Caso a procedure seja estritamente de leitura, você pode configurar explicitamente `"methods": ["GET"]` no JSON de entidades. Para execuções via GET, passe os parâmetros de entrada diretamente no formato query string da URL.

---

## Configuração do Endpoint GraphQL

### Configurações Globais do GraphQL

```json
{
  "runtime": {
    "graphql": {
      "enabled": true,
      "path": "/graphql",
      "allow-introspection": true,
      "depth-limit": 4
    }
  }
}
```

- `depth-limit`: Impede o envio de consultas aninhadas excessivamente profundas que possam degradar a performance do banco.
- `allow-introspection`: Permite inspecionar o esquema de dados; deve ser desligado (`false`) em produção.

### Mapeamento das Entidades para GraphQL

```json
"Product": {
  "source": { "object": "dbo.Products", "type": "table", "key-fields": ["ProductId"] },
  "graphql": {
    "enabled": true,
    "type": {
      "singular": "Product",
      "plural": "Products"
    }
  }
}
```

### Escrita de Queries no GraphQL

O DAB cria automaticamente queries tipadas para listagens e buscas unitárias baseadas na chave primária (PK):

```graphql
# Obter produtos de forma paginada
query {
  products {
    items {
      productId
      name
      price
    }
    hasNextPage
    endCursor
  }
}

# Obter um produto individual informando a PK
query {
  product_by_pk(ProductId: 7) {
    productId
    name
    price
  }
}

# Filtrar dados no GraphQL
query {
  products(filter: { Price: { lt: 50 } }) {
    items {
      productId
      name
      price
    }
  }
}

# Ordenação e paginação no GraphQL
query {
  products(orderBy: { Price: ASC }, first: 10) {
    items { productId name price }
    hasNextPage
    endCursor
  }
}
```

### Escrita de Mutations (Gravações) no GraphQL

O DAB monta mutações de escrita padrão para inserção, atualização e exclusão de linhas das entidades:

```graphql
# Inserir Registro (Create)
mutation {
  createOrder(item: { CustomerId: 42, Status: "Pending", TotalAmount: 99.99 }) {
    orderId
    status
    orderDate
  }
}

# Atualizar Registro (Update)
mutation {
  updateOrder(OrderId: 1001, item: { Status: "Shipped" }) {
    orderId
    status
  }
}

# Deletar Registro (Delete)
mutation {
  deleteOrder(OrderId: 1001) {
    orderId
  }
}
```

### Consultas Aninhadas via Relacionamentos (Nested Queries)

Caso o JSON de configuração registre relacionamentos, o GraphQL pode realizar as buscas aninhadas em uma chamada única:

```graphql
query {
  orders(filter: { Status: { eq: "Active" } }) {
    items {
      orderId
      orderDate
      customer {        # Relação de um para um (cardinality: one)
        name
        email
      }
      items {           # Relação de um para muitos (cardinality: many)
        productId
        quantity
        unitPrice
      }
    }
  }
}
```

### Chamadas de Stored Procedures no GraphQL

```json
"CreateOrder": {
  "source": {
    "object": "dbo.CreateOrder",
    "type": "stored-procedure",
    "parameters": { "CustomerId": "number", "ProductId": "number", "Quantity": "number" }
  },
  "graphql": {
    "enabled": true,
    "operation": "mutation",
    "type": { "singular": "CreateOrderResult" }
  },
  "permissions": [{ "role": "authenticated", "actions": ["execute"] }]
}
```

Invocando a Stored Procedure como mutation no GraphQL:

```graphql
mutation {
  executeCreateOrder(CustomerId: 42, ProductId: 7, Quantity: 3) {
    orderId
  }
}
```

---

## Configurações e Gerenciamento de Cache

```json
{
  "runtime": {
    "cache": {
      "enabled": true,
      "ttl-seconds": 300
    }
  },
  "entities": {
    "Product": {
      "cache": {
        "enabled": true,
        "ttl-seconds": 600
      }
    },
    "Order": {
      "cache": {
        "enabled": false
      }
    }
  }
}
```

> [!warning] Dica de Exame: Caching vs Mutations no DAB
>
> - O cache de nível 1 documentado pelo DAB é aplicado a endpoints **REST**, por rota e parâmetros; habilite-o globalmente e também por entidade.
> - Operações REST de criação, atualização e exclusão invalidam o cache da entidade. Não presuma que consultas GraphQL usam essa mesma configuração de cache.

---

## Paginação Baseada em Cursores

O DAB resolve paginações volumosas de bancos através de cursores nativos para impedir impactos de performance:

- **REST**: Fornece a propriedade `@nextLink` na URL contendo o parâmetro `$after`.
- **GraphQL**: Fornece metadados `hasNextPage` e `endCursor` no retorno do array de registros da busca.

---

## Problemas Comuns e Soluções (Common Issues)

| Sintoma | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Erro `Method not allowed` no REST | Método incompatível com o tipo de entidade ou com as permissões | Para stored procedures, configure `methods` com `GET` e/ou `POST`; para tabelas e views, revise as permissões da entidade. |
| Dados não atualizam após alterações de escrita | Cache ativado em tabelas transacionais de alta escrita | Configure o cache como `false` especificamente nessa entidade. |
| Retornos com campos nulos no GraphQL | Relacionamento físico de chaves não foi mapeado no config | Declare as origens e destinos lógicos no array `relationships`. |
| Parâmetros de Stored Procedures ignorados | Falta mapear os parâmetros correspondentes no JSON | Verifique se as propriedades e tipos (`number`/`string`) estão corretos. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - `PUT` e `PATCH` podem ter comportamento de upsert quando a tabela aceita chave explícita; com chaves autogeradas, use `POST` para criar registros.
> - O parâmetro `allow-introspection: false` protege a visualização pública de schemas do GraphQL no ambiente de produção.
> - O cache de nível 1 do DAB é configurado para endpoints REST e é invalidado por gravações REST da entidade.
> - Procedures de alteração de dados no GraphQL devem ser mapeadas com a propriedade `"operation": "mutation"`.

---

## Resumo dos Conceitos (Key Takeaways)

- O REST do DAB usa parâmetros de consulta na URL para filtro, ordenação, projeção e paginação.
- O GraphQL expõe um endpoint único e auto-gera mutations de inserções e exclusões.
- A paginação do DAB é síncrona e orientada a cursores para suportar grandes tabelas.
- O cache do DAB melhora a performance de leitura em tabelas estáticas de cadastros.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Você está expondo uma stored procedure chamada `dbo.UpdateStock` por meio do Data API Builder (DAB) no formato GraphQL. A stored procedure altera valores de inventário e aceita o parâmetro `@ProductId` e `@NewStock`. Você precisa garantir que a stored procedure seja exposta de forma adequada no GraphQL. Como você deve configurar a propriedade `operation` no arquivo de configuração do DAB?

A. Mapear a propriedade `operation` como `query`.

B. Mapear a propriedade `operation` como `mutation`.

C. Configurar o método REST como `get`.

D. Habilitar o cache com tempo de expiração (TTL) nulo.

> [!success]- Resposta
> **B — Mapear a propriedade `operation` como `mutation`**
>
> No padrão GraphQL do Data API Builder, operações que efetuam modificações de estado de dados física (como atualizações de tabelas executadas por stored procedures de gravação) devem ser mapeadas especificando a propriedade de tipo de operação como `mutation`. O tipo `query` (A) é recomendado estritamente para procedimentos de consulta e leitura de dados.

---

## Autorização do GraphQL no Fabric

**Run Queries and Mutations** concede Execute na API; View/Edit não bastam para
consultar dados. Com saved credential, ela fornece acesso à fonte; com SSO, o
chamador também precisa de read/write apropriado no datasource.

## Tópicos Relacionados

- [01-Construtor de APIs de Dados (DAB)](./01-data-api-builder.md)
- [03-Monitoramento](./03-monitoring.md) *(Inglês apenas)*
- [04-Captura e Tratamento de Eventos (CDC)](./04-change-event-handling.md) *(Inglês apenas)*

---

## Documentação Oficial

- [DAB REST Endpoints](https://learn.microsoft.com/en-us/azure/data-api-builder/rest)
- [DAB GraphQL Endpoints](https://learn.microsoft.com/en-us/azure/data-api-builder/graphql)
- [DAB Pagination](https://learn.microsoft.com/en-us/azure/data-api-builder/pagination)

---

**[← Anterior](./01-data-api-builder.md) | [↑ Voltar para a Seção](./azure-services-integration.md) | [Lab: Endpoints REST e GraphQL](../../practice/labs/08-azure-services-integration/02-rest-graphql-endpoints-lab.sql) | [Próximo →](./03-monitoring.md)**
