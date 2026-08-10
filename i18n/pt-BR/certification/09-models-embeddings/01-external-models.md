---
title: Modelos Externos no SQL Database (External Models in SQL Database)
type: study-material
tags:
  - dp-800
  - external-models
  - azure-openai
  - model-management
---

> [!info] 🗺️ Índice de Navegação Rápida
>
> - 📍 [1. Visão Geral](#visão-geral)
> - 📍 [2. Avaliando Modelos](#avaliando-modelos)
>   - 🔹 [Dimensões de Capacidade do Modelo](#dimensões-de-capacidade-do-modelo)
>   - 🔹 [Modelos Atuais e Seus Casos de Uso](#modelos-atuais-e-seus-casos-de-uso)
>   - 🔹 [Tradeoffs de Tamanho vs. Precisão](#tradeoffs-de-tamanho-vs-precisão)
> - 📍 [3. Sintaxe de CREATE EXTERNAL MODEL](#sintaxe-de-create-external-model)
> - 📍 [4. Gerenciando External Models](#gerenciando-external-models)
> - 📍 [5. Permissões de External Model](#permissões-de-external-model)
> - 📍 [6. Gerando Embeddings com External Model](#gerando-embeddings-com-external-model)
> - 📍 [7. Chamando Endpoints de Chat](#chamando-endpoints-de-chat)
> - 📍 [8. Armazenando Embeddings Gerados](#armazenando-embeddings-gerados)
> - 📍 [10. Matriz de Decisão para Seleção de Modelo](#matriz-de-decisão-para-seleção-de-modelo)
> - 📍 [11. Gerenciamento de Deployments de Modelos no Azure](#gerenciamento-de-deployments-de-modelos-no-azure)
> - 📍 [12. Casos de Uso](#casos-de-uso)
> - 📍 [13. Problemas Comuns e Erros](#problemas-comuns-e-erros)
> - 📍 [14. Boas Práticas](#boas-práticas)
> - 📍 [15. Dicas para o Exame](#dicas-para-o-exame)
> - 📍 [16. Principais Conclusões](#principais-conclusões)
> - 📍 [17. Questão de Prática](#questão-de-prática)
> - 📍 [18. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [19. Documentação Oficial](#documentação-oficial)

---

# Modelos Externos no SQL Database

## Visão Geral

O SQL Server 2025 (17.x), o Azure SQL Database, o Azure SQL Managed Instance (com a política Always-up-to-date) e o SQL database no Microsoft Fabric suportam a geração de embeddings por meio de definições de **External Models**. Um **external model** é um objeto do banco que registra localização, autenticação e finalidade de um endpoint de inferência e é chamado pela função T-SQL `AI_GENERATE_EMBEDDINGS`.

> [!abstract]
>
> - Aborda a criação de modelos externos de embeddings e sua chamada com `AI_GENERATE_EMBEDDINGS`
> - Embeddings são gerados por meio de uma `DATABASE SCOPED CREDENTIAL` e de um endpoint de inferência
> - Tópicos-chave para o exame: `CREATE EXTERNAL MODEL`, `DATABASE SCOPED CREDENTIAL`, dimensões e permissões

> [!tip] O Que o Exame Testa
>
> - `sp_invoke_external_rest_endpoint` recebe os parâmetros `@url`, `@method`, `@headers`, `@payload`, `@credential`
> - A chave de API é armazenada em uma `DATABASE SCOPED CREDENTIAL`; o nome da credencial deve ser um prefixo de URL compatível com o endpoint
> - `AI_GENERATE_EMBEDDINGS` retorna uma tabela de uma coluna, cujas linhas contêm arrays de embedding em JSON

---

## Fundamentos: embeddings, vetores e modelos

Um **embedding** é uma representação numérica densa do significado de um texto. O modelo transforma, por exemplo, uma descrição de produto em um vetor — uma lista ordenada de números — para que buscas posteriores encontrem descrições semanticamente próximas, mesmo quando não usam as mesmas palavras. O vetor não substitui o texto: ele serve para localizar o texto original, que deve ser armazenado junto com identificador e metadados.

Cada vetor tem uma quantidade fixa de números, chamada de **dimensão**. A dimensão é definida pelo modelo e precisa coincidir com a coluna que recebe o resultado. Consequentemente, trocar de modelo ou de dimensão exige regerar embeddings; vetores produzidos por modelos diferentes não devem ser misturados na mesma busca. O tipo `VECTOR(n)` armazena esses valores e a busca usa uma métrica de distância ou similaridade para ordenar candidatos — o score é comparável apenas dentro da mesma métrica e do mesmo espaço vetorial.

Também separe três papéis: o **modelo de embedding** converte texto em vetor; o **modelo de chat** usa instruções e contexto para escrever uma resposta; e o **deployment/endpoint** é a instância acessável de um modelo no provedor. Um external model é o objeto de banco que registra essa ponte para o endpoint. A `DATABASE SCOPED CREDENTIAL` mantém o segredo ou a identidade de acesso fora do código e das consultas.

> [!note] Por que isso importa
>
> O modelo não “entende” sua tabela automaticamente. Você escolhe o texto relevante, gera o vetor, persiste texto e vetor, e depois gera outro vetor para a pergunta do usuário. A comparação entre os vetores recupera candidatos; somente então uma aplicação ou modelo de chat decide como apresentar a resposta.

## Avaliando Modelos

Escolher o modelo correto para uma tarefa depende de várias dimensões:

### Dimensões de Capacidade do Modelo

| Dimensão | Considerações | Exemplos |
| :--- | :--- | :--- |
| **Multimodal** | Processa imagens, áudio ou vídeo além de texto | Use um modelo que documente a modalidade necessária |
| **Multilíngue** | Qualidade de compreensão e geração em outros idiomas | Faça benchmark com dados representativos do idioma |
| **Saída estruturada** | Saída JSON/schema confiável (function calling) | Use um modelo/API que documente esse recurso |
| **Dimensão do embedding** | Maior = mais precisão semântica; mais armazenamento | 1536 (3-small), 3072 (3-large) |
| **Janela de contexto** | Máximo de tokens de entrada/saída; afeta o tamanho dos chunks e da conversa | Consulte o catálogo atual do provedor |
| **Latência** | Depende do modelo, região, carga e quota | Meça com requisições representativas |
| **Custo** | Depende do modelo, deployment e região | Consulte o preço atual antes de escolher |

### Modelos Atuais e Seus Casos de Uso

> **Nota:** disponibilidade, aposentadoria, limites de contexto e preço mudam. Os nomes abaixo são exemplos; confirme o catálogo atual do Azure AI Foundry e use o nome exato de modelo/deployment suportado pelo recurso.

| Modelo | Tipo | Melhor Para |
| :--- | :--- | :--- |
| `text-embedding-3-small` | Embedding | Equilíbrio entre precisão e custo; 1536 dims |
| `text-embedding-3-large` | Embedding | Embeddings de maior qualidade; 3072 dims |
| `text-embedding-ada-002` | Embedding | Apenas legado; superado pelo 3-small |
| Um modelo de chat/raciocínio atualmente suportado | Chat ou raciocínio | Selecione por qualidade, latência, modalidade e quota |

### Tradeoffs de Tamanho vs. Precisão

```text
Modelos de embedding:
text-embedding-ada-002   → 1536 dims, custo 1x, precisão base (legado)
text-embedding-3-small   → 1536 dims, custo menor que 3-large, precisão maior que ada-002
text-embedding-3-large   → 3072 dims, custo 2x, melhor precisão

Tradeoff: modelos de embedding maiores produzem vetores mais discriminativos
ao custo de armazenamento (3072 floats × 4 bytes = 12KB por linha) e
latência de API ligeiramente maior.

Modelos de chat/raciocínio:
Use o catálogo atual do provedor para comparar modelos suportados, modalidades,
limites de contexto, latência, preço e datas de aposentadoria. Não fixe uma classificação
permanente na lógica da aplicação.
```

---

## Sintaxe de CREATE EXTERNAL MODEL

No SQL Database no Fabric, registre um external model para habilitar chamadas T-SQL:

```sql
-- Criar uma DATABASE SCOPED CREDENTIAL para o endpoint do Azure OpenAI
CREATE DATABASE SCOPED CREDENTIAL [https://myopenai.openai.azure.com/]
WITH IDENTITY = 'HTTPEndpointHeaders',
SECRET = '{"api-key":"your-azure-openai-api-key"}';

-- Criar o external model (modelo de embedding)
CREATE EXTERNAL MODEL [MyEmbeddingModel]
WITH (
    LOCATION = 'https://myopenai.openai.azure.com/openai/deployments/my-embedding-deployment/embeddings?api-version=2024-02-01',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'text-embedding-3-small',
    CREDENTIAL = [https://myopenai.openai.azure.com/],
    PARAMETERS = '{"dimensions":1536}'
);

```

Parâmetros principais:

- `LOCATION`: A URL completa do endpoint REST, incluindo a versão da API exigida pelo provedor
- `API_FORMAT`: `Azure OpenAI`, `OpenAI`, `Ollama` ou `ONNX Runtime`, conforme o provedor
- `MODEL_TYPE`: `EMBEDDINGS`
- `MODEL`: o nome do modelo de embeddings hospedado pelo provedor
- `CREDENTIAL`: Referencia uma credencial nomeada com URL compatível com `LOCATION` e que contém a chave de API

> [!note] Separação Lógica por Schema
>
> Crie external models em um schema dedicado (ex: `ai`) para simplificar o gerenciamento de permissões. Isso evita conceder `db_owner` para todos que precisam gerar embeddings.

---

## Gerenciando External Models

```sql
-- Listar todos os external models no banco de dados
SELECT
    name,
    model_type_desc,
    location,
    create_time,
    modify_time
FROM sys.external_models;

-- Verificar detalhes de um modelo
SELECT * FROM sys.external_models WHERE name = 'MyEmbeddingModel';

-- Remover um external model
DROP EXTERNAL MODEL [MyEmbeddingModel];

-- Alterar um external model (mudar credencial ou localização)
ALTER EXTERNAL MODEL [MyEmbeddingModel]
SET (
    CREDENTIAL = [https://myopenai.openai.azure.com/]
);
```

---

## Permissões de External Model

As permissões seguem um modelo baseado em objetos, semelhante a stored procedures.

- **Criar ou alterar**: requer `CREATE EXTERNAL MODEL` ou `ALTER ANY EXTERNAL MODEL` (ou uma permissão superior equivalente)
- **Gerar embeddings**: requer permissão `EXECUTE` no objeto de external model específico
- **Separação por schema**: crie external models em um schema dedicado (ex: `ai`) para simplificar o gerenciamento de permissões

```sql
-- Conceder permissão para usar um external model específico
GRANT EXECUTE ON EXTERNAL MODEL::[MyEmbeddingModel] TO DataAnalystRole;

-- Conceder permissão para criar external models
GRANT ALTER ANY EXTERNAL MODEL TO DatabaseDeveloper;

-- Verificar quais modelos existem e seus endpoints
SELECT name, location, credential_id, create_time, modify_time
FROM sys.external_models;
```

> [!important] EXECUTE vs ALTER ANY EXTERNAL MODEL
>
> - `EXECUTE ON EXTERNAL MODEL` → permite **usar** o modelo de embeddings (menor privilégio — use isso)
> - `ALTER ANY EXTERNAL MODEL` → permite **criar/modificar** modelos — **não** é necessário para chamá-los
>
> O exame vai testar se você conhece a diferença!

---

## Gerando Embeddings com External Model

Use `AI_GENERATE_EMBEDDINGS` com um external model cujo `MODEL_TYPE` seja `EMBEDDINGS`. A função recebe uma expressão de texto e retorna o vetor gerado como JSON; o SQL pode atribuí-lo diretamente a uma coluna `VECTOR(n)` compatível. `PREDICT` não é a interface atual para esses external models.

No SQL Server 2025, habilite a configuração de endpoint REST externo antes de usar a função. No Azure SQL Database e no SQL database no Fabric essa opção vem habilitada por padrão:

```sql
EXECUTE sp_configure 'external rest endpoint enabled', 1;
RECONFIGURE WITH OVERRIDE;
```

O chamador também precisa de `EXECUTE` no external model. O `PARAMETERS` do modelo e o `PARAMETERS` opcional da função podem enviar configurações específicas do provedor, como `dimensions` ou `sql_rest_options.retry_count` (de 0 a 10).

### Request Direta à API vs. `AI_GENERATE_EMBEDDINGS`

As duas abordagens podem chamar o mesmo provedor e o mesmo modelo de embedding. A diferença está na camada de integração:

| Aspecto | Request direta à API | `AI_GENERATE_EMBEDDINGS` |
| :--- | :--- | :--- |
| Invocação | Aplicação, script ou `sp_invoke_external_rest_endpoint` | Função T-SQL |
| Configuração | Você monta URL, payload, headers e parsing da resposta | `CREATE EXTERNAL MODEL` armazena metadados do endpoint e do modelo |
| Autenticação | Você gerencia a chamada e a credencial | `DATABASE SCOPED CREDENTIAL` é associada ao external model |
| Resultado | Resposta do provedor, normalmente um documento JSON | Tabela de uma coluna contendo arrays de embedding em JSON |
| Integração com SQL | Você interpreta a resposta e persiste o vetor | Pode ser usada diretamente em `SELECT` ou `UPDATE` baseado em conjunto |

Use `AI_GENERATE_EMBEDDINGS` quando os dados e o fluxo de persistência estiverem no SQL. Use uma request direta quando precisar de controle total do payload, tiver de chamar um endpoint incompatível com `CREATE EXTERNAL MODEL` ou precisar chamar um endpoint de chat. Nos dois casos, os pesos do modelo permanecem no servidor do provedor; apenas a entrada e o vetor retornado atravessam o limite do serviço.

```sql
-- Gerar embedding para um único texto
SELECT AI_GENERATE_EMBEDDINGS(
    N'What is vector search?' USE MODEL ai.EmbeddingModel
) AS embedding;

-- Lote: gerar embeddings para todos os documentos
UPDATE Documents
SET Embedding = AI_GENERATE_EMBEDDINGS(Content USE MODEL ai.EmbeddingModel)
WHERE Embedding IS NULL;
```

---

## Chamando Endpoints de Chat

`AI_GENERATE_EMBEDDINGS` cria vetores; ela não gera respostas de chat. A função retorna uma tabela de uma coluna, com arrays de embedding em JSON, e o SQL Server pode atribuir o resultado a uma coluna `VECTOR(n)` compatível. Para chat, chame a API REST por `sp_invoke_external_rest_endpoint` e interprete o contrato documentado da resposta.

## Armazenando Embeddings Gerados

```sql
-- Adicionar uma coluna vetorial para armazenar embeddings
ALTER TABLE dbo.Products
ADD DescriptionEmbedding VECTOR(1536);  -- 1536 dims para text-embedding-3-small

-- Gerar e armazenar embeddings para todos os produtos
UPDATE p
SET DescriptionEmbedding = AI_GENERATE_EMBEDDINGS(
    p.Description USE MODEL [MyEmbeddingModel]
)
FROM dbo.Products AS p
WHERE p.DescriptionEmbedding IS NULL;
```

> [!caution] Nunca misture embeddings de modelos diferentes
>
> Vetores de modelos diferentes, ou gerados com dimensões/parâmetros incompatíveis, não devem ser comparados no mesmo índice. Se trocar o modelo ou suas dimensões, regenere o corpus afetado e mantenha metadados do modelo e da métrica junto aos vetores.

---

## Matriz de Decisão para Seleção de Modelo

Use esta tabela para escolher rapidamente o modelo certo para uma carga de trabalho:

| Caso de Uso | Modelo Recomendado | Por Quê |
| :--- | :--- | :--- |
| Geração de embedding (equilibrado) | `text-embedding-3-small` | Otimizado para similaridade vetorial; baixo custo |
| Geração de embedding (maior qualidade) | `text-embedding-3-large` | Melhor precisão; saída de 3072 dimensões |
| Geração de respostas de chat ou RAG | Um modelo de chat atualmente suportado | Escolha por qualidade, contexto, latência, modalidade e custo medidos |
| Raciocínio em múltiplas etapas / matemática | Um modelo de raciocínio atualmente suportado | Verifique suporte e latência no catálogo atual |
| Geração de código | Um modelo atualmente suportado para código | Avalie com tarefas de código representativas |
| Classificação de baixa latência | Um modelo menor atualmente suportado | Valide precisão e suporte a saída estruturada |

Framework de decisão:

```text
Para geração de embedding:
├── Alta precisão necessária? → text-embedding-3-large (3072 dims)
├── Equilíbrio precisão/custo? → text-embedding-3-small (1536 dims)
└── Sistemas legados apenas → text-embedding-ada-002 (1536 dims)

Para geração de texto (RAG):
├── Precisa de baixa latência/custo? → escolha um modelo menor suportado e faça benchmark
├── Precisa de entrada multimodal? → escolha um modelo que documente essa modalidade
├── Precisa de saída estruturada? → verifique o suporte do modelo e da API
└── Precisa de raciocínio complexo? → escolha um modelo suportado e faça benchmark

Para classificação ou extração:
├── Saída JSON estruturada necessária? → escolha um modelo/API que documente esse recurso
└── Binária/multiclasse simples? → faça benchmark com um modelo menor suportado
```

---

## Gerenciamento de Deployments de Modelos no Azure

Os deployments de modelos são gerenciados através do Azure OpenAI Studio (ou Portal Azure):

- **Deployar modelos**: crie um deployment nomeado (ex: `my-gpt4o`) que mapeia para uma versão específica do modelo; o nome do deployment aparece na URL de `LOCATION`
- **Versionamento de modelos**: escolha atualização automática (sempre o último patch) ou fixe uma versão específica para reprodutibilidade
- **Gerenciamento de quota**: quota e limites dependem do modelo, tipo de deployment, assinatura e região; confirme a orientação atual do Azure
- **Limites de tokens**: configure limites no aplicativo/provedor e monitore o consumo para controlar custo e throttling
- **Monitoramento via Azure Monitor**: acompanhe consumo de tokens, latência de requisições, taxas de erro (4xx/5xx) e eventos de throttling usando métricas integradas e Log Analytics

### Erros de Throttling

Throttling ocorre quando o provedor limita temporariamente as requisições porque um deployment excedeu uma quota disponível, como tokens por minuto (TPM), requisições por minuto ou conexões simultâneas. O endpoint normalmente retorna HTTP `429 Too Many Requests`. Isso indica controle de capacidade ou taxa de chamadas, não um erro de autenticação.

Trate throttling agrupando o trabalho em lotes, limitando a concorrência, respeitando o cabeçalho de resposta `Retry-After` e repetindo a chamada com backoff exponencial. Monitore as requisições limitadas e verifique a quota atual do deployment antes de aumentar a carga. Para `AI_GENERATE_EMBEDDINGS`, o comportamento de retry pode ser configurado em `PARAMETERS` com `sql_rest_options.retry_count` (de 0 a 10).

### Fixando uma Versão de Modelo em Produção

Fixar uma versão significa selecionar uma versão específica do modelo para o deployment, em vez de permitir que o Azure o mova automaticamente para uma nova versão padrão. No Azure AI Foundry ou no Portal do Azure, abra as configurações do deployment, escolha a versão específica do modelo e selecione `NoAutoUpgrade` quando for necessário impedir atualizações automáticas. Teste uma nova versão em um deployment separado antes de alterar a produção.

`NoAutoUpgrade` não prolonga a vida útil do modelo: quando a versão selecionada for aposentada, o deployment poderá deixar de aceitar requisições e precisará ser migrado manualmente. Mantenha a versão do modelo e a data de aposentadoria no inventário de deployments. Essa versão do modelo é diferente da `api-version` REST usada pelo endpoint.

Depois de validar uma nova versão, atualize o external model registrado se o identificador do modelo ou o endpoint mudar:

```sql
ALTER EXTERNAL MODEL [MyEmbeddingModel]
SET
(
    MODEL = 'nova-versao-do-modelo'
);
```

---

## Casos de Uso

- **Busca de produtos**: gere embeddings para descrições de produtos; armazene em coluna vetorial; habilite busca semântica
- **Classificação de documentos**: use um modelo de completions para classificar documentos recebidos sem modelos de ML customizados
- **Análise de feedback de clientes**: processe em lote linhas de feedback para gerar pontuações de sentimento usando T-SQL
- **Grounding RAG**: embedded queries de usuários em tempo de consulta para encontrar documentos similares no banco de dados

---

## Problemas Comuns e Erros

| Problema | Causa | Correção |
| :--- | :--- | :--- |
| `Invalid API key` | Secret errado na credencial | Atualize a DATABASE SCOPED CREDENTIAL com a chave correta |
| `Model not found` | Nome de deployment errado na URL de LOCATION | Verifique o nome do deployment no Azure OpenAI Studio |
| `Dimension mismatch` | Modelo de embedding retorna dimensões diferentes da coluna VECTOR | Faça o VECTOR(n) corresponder às dimensões reais do modelo |
| `Rate limit exceeded` | Muitas chamadas de API/minuto | Implemente batching; aumente a quota do Azure OpenAI |
| Erro de `AI_GENERATE_EMBEDDINGS` | Texto ou external model incompatível | Verifique `MODEL_TYPE = EMBEDDINGS`, o texto de entrada e a dimensão da coluna `VECTOR(n)` |
| Permissão negada ao gerar embeddings | Usuário sem EXECUTE no external model | `GRANT EXECUTE ON EXTERNAL MODEL::[model_name] TO role` |

---

## Boas Práticas

- Armazene definições de external model em um schema dedicado (ex: `ai`) e conceda `EXECUTE` apenas para roles que precisam — nunca dependa de `db_owner` para acesso rotineiro
- Use `text-embedding-3-small` como modelo de embedding padrão; só faça upgrade para `text-embedding-3-large` quando a qualidade de recuperação for mensuravelmente insuficiente
- Evite chamar `AI_GENERATE_EMBEDDINGS` linha por linha em um cursor; faça updates em lote com `WHERE Embedding IS NULL` para minimizar round-trips de API (cada ida e volta entre o banco e o endpoint externo) e permanecer dentro dos limites de TPM
- Fixe versões de modelos em deployments de produção para evitar mudanças de comportamento inesperadas de atualizações automáticas
- Monitore o uso de tokens e a latência do Azure OpenAI via Azure Monitor; configure alertas em erros de throttling antes que impactem a performance das queries

---

## Dicas para o Exame

> [!tip] Dicas para o Exame
>
> - `CREATE EXTERNAL MODEL` registra metadados do endpoint; a autenticação remota usa uma `DATABASE SCOPED CREDENTIAL` compatível
> - `MODEL_TYPE = EMBEDDINGS` identifica o external model usado para geração de vetores
> - `AI_GENERATE_EMBEDDINGS(text USE MODEL ...)` é a interface T-SQL atual para gerar embeddings com external models
> - A dimensão do embedding deve corresponder ao tamanho da coluna `VECTOR(n)` — `text-embedding-3-small` = 1536, `text-embedding-3-large` = 3072
> - External models são objetos de escopo de banco de dados — visíveis em `sys.external_models`
> - Permissão `EXECUTE` no objeto de external model é necessária para gerar embeddings — `ALTER ANY EXTERNAL MODEL` é para criar/modificar, não para chamar
> - Nomes e ciclo de vida dos modelos do provedor mudam; consulte o catálogo atual em vez de memorizar um substituto fixo

---

## Principais Conclusões

- External models registram endpoints de IA como objetos do banco de dados — chamáveis via T-SQL sem código customizado
- `CREATE EXTERNAL MODEL` + `DATABASE SCOPED CREDENTIAL` é o padrão de configuração
- `AI_GENERATE_EMBEDDINGS(text USE MODEL ...)` chama um modelo externo de embeddings inline com queries SQL
- Use um modelo com `MODEL_TYPE = EMBEDDINGS` para geração de vetores
- Use permissão `EXECUTE` (não `ALTER ANY EXTERNAL MODEL`) para permitir que roles chamem o modelo de embeddings

---

## Questão de Prática

**Questão de Prática**

Um banco de dados tem um EXTERNAL MODEL configurado para o Azure OpenAI text-embedding-3-small. Um usuário no ReportingRole pode consultar tabelas de documentos mas recebe "permission denied" ao gerar um embedding. Qual permissão é necessária?

A. Permissão SELECT em sys.external_models

B. Permissão EXECUTE no EXTERNAL MODEL

C. Permissão ALTER ANY EXTERNAL MODEL

D. Membership no papel db_owner

> [!success]- Resposta
> **B — Permissão EXECUTE no EXTERNAL MODEL**
>
> Gerar embeddings por um external model requer permissão EXECUTE no objeto de external model específico — similar a precisar de EXECUTE em uma stored procedure. SELECT em sys.external_models (A) apenas permite visualizar metadados do modelo. ALTER ANY EXTERNAL MODEL (C) permite criar/modificar modelos, não usá-los. db_owner (D) funcionaria, mas é excessivamente amplo.

---

## Ciclo de vida e evidência operacional

Mantenha deployment, dimensões, credencial, contrato e avaliação sob controle de
mudança. Faça rollout gradual, compare qualidade/latência/custo/erros e planeje
re-embedding e compatibilidade do índice ao trocar modelo. Monitore freshness,
falhas de geração, recall/precision, latência e validação de resposta.

## Tópicos Relacionados

- [02-Manutenção de Embeddings](./02-embedding-maintenance.md)
- [03-Chunking e Geração](./03-chunking-generation.md)
- [02-Prompts e Respostas](../11-rag/02-prompts-and-responses.md)

---

## Documentação Oficial

- [External Models in Fabric SQL](https://learn.microsoft.com/en-us/fabric/database/sql/ai-external-model)
- [CREATE EXTERNAL MODEL](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-external-model-transact-sql)
- [ALTER EXTERNAL MODEL](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-external-model-transact-sql)
- [AI_GENERATE_EMBEDDINGS](https://learn.microsoft.com/en-us/sql/t-sql/functions/ai-generate-embeddings-transact-sql)
- [sys.external_models](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-external-models-transact-sql)
- [sp_invoke_external_rest_endpoint](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-invoke-external-rest-endpoint-transact-sql)
- [Azure OpenAI Models](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/models)

---

**[↑ Voltar à Seção](./models-embeddings.md) | [Lab: Modelos Externos](../../practice/labs/09-models-embeddings/01-external-models-lab.sql) | [Próximo →](./02-embedding-maintenance.md)**
