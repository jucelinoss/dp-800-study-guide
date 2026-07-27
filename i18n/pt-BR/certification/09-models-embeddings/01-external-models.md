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

O SQL Database no Microsoft Fabric, o Azure SQL Database e plataformas SQL compatíveis suportam a geração de embeddings por meio de definições de **External Models**. Um **external model** referencia um endpoint de inferência registrado no banco e é chamado pela função T-SQL `AI_GENERATE_EMBEDDINGS`.

> [!abstract]
>
> - Aborda a criação de modelos externos de embeddings e sua chamada com `AI_GENERATE_EMBEDDINGS`
> - Embeddings são gerados por meio de uma `DATABASE SCOPED CREDENTIAL` e de um endpoint de inferência
> - Tópicos-chave para o exame: `CREATE EXTERNAL MODEL`, `DATABASE SCOPED CREDENTIAL`, dimensões e permissões

> [!tip] O Que o Exame Testa
>
> - `sp_invoke_external_rest_endpoint` recebe os parâmetros `@url`, `@method`, `@headers`, `@payload`, `@credential`
> - A chave de API é armazenada em uma `DATABASE SCOPED CREDENTIAL` com `SECRET` = o bearer token — **nunca** hard-coded
> - `AI_GENERATE_EMBEDDINGS` retorna uma tabela de vetores de embedding em JSON

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
| **Multimodal** | Processa imagens, áudio ou vídeo além de texto | GPT-4o, GPT-4 Vision |
| **Multilíngue** | Qualidade de compreensão e geração em outros idiomas | GPT-4o, text-embedding-3-large |
| **Saída estruturada** | Saída JSON/schema confiável (function calling) | GPT-4o, GPT-4o-mini |
| **Dimensão do embedding** | Maior = mais precisão semântica; mais armazenamento | 1536 (3-small), 3072 (3-large) |
| **Janela de contexto** | Máximo de tokens in/out; afeta tamanho do chunk e comprimento da conversa | 8k, 128k tokens |
| **Latência** | Tempo por requisição; modelos menores são mais rápidos | GPT-4o-mini < GPT-4o < o1 |
| **Custo** | Precificação por token; modelos menores/antigos são mais baratos | GPT-4o-mini << GPT-4o |

### Modelos Atuais e Seus Casos de Uso

> **Nota:** `gpt-35-turbo` está obsoleto e sendo descontinuado. Use `gpt-4o-mini` como substituto recomendado para cargas de trabalho sensíveis ao custo e de alto volume.

| Modelo | Tipo | Melhor Para |
| :--- | :--- | :--- |
| `text-embedding-3-small` | Embedding | Equilíbrio entre precisão e custo; 1536 dims |
| `text-embedding-3-large` | Embedding | Embeddings de maior qualidade; 3072 dims |
| `text-embedding-ada-002` | Embedding | Apenas legado; superado pelo 3-small |
| `gpt-4o` | Chat completion | Raciocínio complexo, multimodal, saída estruturada |
| `gpt-4o-mini` | Chat completion | Custo-efetivo, rápido; substitui gpt-35-turbo |
| `o1` | Raciocínio | Raciocínio em múltiplas etapas, análise complexa |
| `o3-mini` | Raciocínio | Raciocínio rápido; problemas de matemática e código |

### Tradeoffs de Tamanho vs. Precisão

```text
Modelos de embedding:
text-embedding-ada-002   → 1536 dims, custo 1x, precisão base (legado)
text-embedding-3-small   → 1536 dims, custo 0.5x, maior precisão
text-embedding-3-large   → 3072 dims, custo 2x, melhor precisão

Tradeoff: modelos de embedding maiores produzem vetores mais discriminativos
ao custo de armazenamento (3072 floats × 4 bytes = 12KB por linha) e
latência de API ligeiramente maior.

Modelos de chat (início de 2026):
gpt-4o-mini → mais rápido, menor custo, suficiente para a maioria dos RAG
gpt-4o      → melhor qualidade, suporta imagens, maior custo e latência
o1/o3-mini  → modelos de raciocínio, melhores para problemas de lógica em múltiplos passos
gpt-35-turbo → DESCONTINUADO — migre para gpt-4o-mini
```

---

## Sintaxe de CREATE EXTERNAL MODEL

No SQL Database no Fabric, registre um external model para habilitar chamadas T-SQL:

```sql
-- Criar uma DATABASE SCOPED CREDENTIAL para o endpoint do Azure OpenAI
CREATE DATABASE SCOPED CREDENTIAL [MyAzureOpenAICredential]
WITH IDENTITY = 'HTTPEndpointHeaders',
SECRET = '{"api-key": "your-azure-openai-api-key"}';

-- Criar o external model (modelo de embedding)
CREATE EXTERNAL MODEL [MyEmbeddingModel]
WITH (
    LOCATION = 'https://myopenai.openai.azure.com/openai/deployments/text-embedding-3-small/embeddings',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'text-embedding-3-small',
    CREDENTIAL = [MyAzureOpenAICredential]
);

```

Parâmetros principais:

- `LOCATION`: A URL completa do endpoint REST do deployment do modelo
- `API_FORMAT`: `Azure OpenAI`, `OpenAI`, `Ollama` ou `ONNX Runtime`, conforme o provedor
- `MODEL_TYPE`: `EMBEDDINGS`
- `MODEL`: o nome do modelo de embeddings hospedado pelo provedor
- `CREDENTIAL`: Referencia a credencial que contém a chave de API

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
    create_date,
    modify_date
FROM sys.external_models;

-- Verificar detalhes de um modelo
SELECT * FROM sys.external_models WHERE name = 'MyEmbeddingModel';

-- Remover um external model
DROP EXTERNAL MODEL [MyEmbeddingModel];

-- Alterar um external model (mudar credencial ou localização)
ALTER EXTERNAL MODEL [MyEmbeddingModel]
WITH (
    CREDENTIAL = [UpdatedCredential]
);
```

---

## Permissões de External Model

As permissões seguem um modelo baseado em objetos, semelhante a stored procedures.

- **CREATE EXTERNAL MODEL**: requer permissão `ALTER ANY EXTERNAL MODEL` ou membership em `db_owner`
- **Gerar embeddings**: requer permissão `EXECUTE` no objeto de external model específico
- **Separação por schema**: crie external models em um schema dedicado (ex: `ai`) para simplificar o gerenciamento de permissões

```sql
-- Conceder permissão para usar um external model específico
GRANT EXECUTE ON EXTERNAL MODEL ai.EmbeddingModel TO DataAnalystRole;

-- Conceder permissão para criar external models
GRANT ALTER ANY EXTERNAL MODEL TO DatabaseDeveloper;

-- Verificar quais modelos existem e seus endpoints
SELECT name, location, credential_name, created_date
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

`AI_GENERATE_EMBEDDINGS` cria vetores; ela não gera respostas de chat. Para um endpoint de chat completion neste material, chame a API REST por `sp_invoke_external_rest_endpoint` e interprete o JSON conforme o contrato documentado do endpoint. Mantenha a credencial fora da procedure e não presuma um envelope de resposta de `PREDICT`.

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
> Vetores de modelos diferentes vivem em espaços dimensionais diferentes e **não podem ser comparados**. Se você trocar o modelo de embedding (ex: de `ada-002` para `3-small`), deve **regenerar TODOS os embeddings** existentes. Misturar vetores de modelos distintos produzirá resultados de busca completamente errados.

---

## Matriz de Decisão para Seleção de Modelo

Use esta tabela para escolher rapidamente o modelo certo para uma carga de trabalho:

| Caso de Uso | Modelo Recomendado | Por Quê |
| :--- | :--- | :--- |
| Geração de embedding (equilibrado) | `text-embedding-3-small` | Otimizado para similaridade vetorial; baixo custo |
| Geração de embedding (maior qualidade) | `text-embedding-3-large` | Melhor precisão; saída de 3072 dimensões |
| Raciocínio complexo / respostas RAG | `gpt-4o` | Alta qualidade, multimodal, JSON estruturado |
| Chat de alto volume sensível a custo | `gpt-4o-mini` | ~90% mais barato que GPT-4o; rápido |
| Raciocínio em múltiplas etapas / matemática | `o1` / `o3-mini` | Modelos de raciocínio construídos para problemas lógicos |
| Geração de código | `gpt-4o` | Excelente qualidade de código e explicação |
| Classificação de baixa latência | `gpt-4o-mini` | Inferência mais rápida; suficiente para tarefas simples |

Framework de decisão:

```text
Para geração de embedding:
├── Alta precisão necessária? → text-embedding-3-large (3072 dims)
├── Equilíbrio precisão/custo? → text-embedding-3-small (1536 dims)
└── Sistemas legados apenas → text-embedding-ada-002 (1536 dims)

Para geração de texto (RAG):
├── Mais rápido, mais barato, boa qualidade? → gpt-4o-mini
├── Melhor qualidade, saída JSON estruturada? → gpt-4o
├── Precisa analisar imagens? → gpt-4o (multimodal)
└── Raciocínio complexo em múltiplas etapas? → o1 ou o3-mini

Para classificação ou extração:
├── Saída JSON estruturada necessária? → gpt-4o ou gpt-4o-mini (modo JSON)
└── Binária/multiclasse simples? → gpt-4o-mini (rápido e barato)
```

---

## Gerenciamento de Deployments de Modelos no Azure

Os deployments de modelos são gerenciados através do Azure OpenAI Studio (ou Portal Azure):

- **Deployar modelos**: crie um deployment nomeado (ex: `my-gpt4o`) que mapeia para uma versão específica do modelo; o nome do deployment aparece na URL de `LOCATION`
- **Versionamento de modelos**: escolha atualização automática (sempre o último patch) ou fixe uma versão específica para reprodutibilidade
- **Gerenciamento de quota**: cada deployment tem um limite de tokens por minuto (TPM); aumentar a quota requer uma solicitação de suporte ou uso de throughput provisionado
- **Limites de tokens**: defina TPM máximo por deployment para controlar custos e evitar uso excessivo em workloads de produção
- **Monitoramento via Azure Monitor**: acompanhe consumo de tokens, latência de requisições, taxas de erro (4xx/5xx) e eventos de throttling usando métricas integradas e Log Analytics

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
| Permissão negada ao gerar embeddings | Usuário sem EXECUTE no external model | `GRANT EXECUTE ON EXTERNAL MODEL model_name TO role` |

---

## Boas Práticas

- Armazene definições de external model em um schema dedicado (ex: `ai`) e conceda `EXECUTE` apenas para roles que precisam — nunca dependa de `db_owner` para acesso rotineiro
- Use `text-embedding-3-small` como modelo de embedding padrão; só faça upgrade para `text-embedding-3-large` quando a qualidade de recuperação for mensuravelmente insuficiente
- Evite chamar `AI_GENERATE_EMBEDDINGS` linha por linha em um cursor; faça updates em lote com `WHERE Embedding IS NULL` para minimizar round-trips de API e permanecer dentro dos limites de TPM
- Fixe versões de modelos em deployments de produção para evitar mudanças de comportamento inesperadas de atualizações automáticas
- Monitore o uso de tokens e a latência do Azure OpenAI via Azure Monitor; configure alertas em erros de throttling antes que impactem a performance das queries

---

## Dicas para o Exame

> [!tip] Dicas para o Exame
>
> - `CREATE EXTERNAL MODEL` requer uma `DATABASE SCOPED CREDENTIAL` — a chave de API é armazenada na credencial, não na definição do modelo
> - `MODEL_TYPE = EMBEDDINGS` identifica o external model usado para geração de vetores
> - `AI_GENERATE_EMBEDDINGS(text USE MODEL ...)` é a interface T-SQL atual para gerar embeddings com external models
> - A dimensão do embedding deve corresponder ao tamanho da coluna `VECTOR(n)` — `text-embedding-3-small` = 1536, `text-embedding-3-large` = 3072
> - External models são objetos de escopo de banco de dados — visíveis em `sys.external_models`
> - Permissão `EXECUTE` no objeto de external model é necessária para gerar embeddings — `ALTER ANY EXTERNAL MODEL` é para criar/modificar, não para chamar
> - `gpt-35-turbo` está obsoleto — questões do exame podem referenciar `gpt-4o-mini` como seu substituto

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
- [Azure OpenAI Models](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/models)

---

**[↑ Voltar à Seção](./models-embeddings.md) | [Próximo →](./02-embedding-maintenance.md)**
