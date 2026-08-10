---
title: Qualidade, Governança e Linhagem de Dados
type: study-material
tags:
  - dp-800
  - data-quality
  - data-governance
  - data-lineage
  - purview
  - fabric
---

> [!info] Escopo
>
> Este tópico complementa a modelagem dimensional e os modelos semânticos. O
> foco é garantir que os dados sejam confiáveis, localizáveis, protegidos e
> rastreáveis desde a origem até o relatório ou aplicação.

# Qualidade, Governança e Linhagem de Dados

Um modelo bem desenhado não é necessariamente um modelo confiável. Qualidade e
governança definem se os consumidores conseguem descobrir, interpretar, proteger
e usar os dados de forma consistente.

```text
Origem → Ingestão → Transformação → Warehouse/Lakehouse → Modelo semântico → Relatório
   │          │             │                 │                  │              │
   └──────────┴─────────────┴─────── metadados, regras, linhagem e controles ────┘
```

## Qualidade de dados

Qualidade deve ser medida em relação ao uso pretendido. Um valor pode ser válido
para uma análise operacional e inadequado para uma métrica financeira.

| Dimensão | Pergunta | Exemplo de regra |
|---|---|---|
| Completude | Os valores obrigatórios existem? | `CustomerId IS NOT NULL` |
| Unicidade | Há duplicatas indevidas? | Uma chave natural aparece uma vez |
| Validade | O valor segue o domínio esperado? | Status em uma lista permitida |
| Consistência | As tabelas concordam? | Total da fato reconcilia com a origem |
| Exatidão | O valor representa a realidade? | Preço corresponde ao sistema oficial |
| Atualidade | O dado está dentro do prazo? | Carga concluída até o SLO definido |
| Integridade | As relações são válidas? | Toda fato possui dimensão correspondente |

Não confunda “sem `NULL`” com “boa qualidade”. Uma coluna pode estar completa e
conter valores errados, desatualizados ou duplicados.

## Regras de qualidade no warehouse

As regras devem ser executadas perto do ponto em que o dado é carregado e também
monitoradas no produto consumido. Um conjunto mínimo para uma fato dimensional pode
ser:

```sql
-- Completude e domínio
SELECT COUNT_BIG(*) AS InvalidRows
FROM dbo.FactSales
WHERE DateKey IS NULL
   OR ProductKey IS NULL
   OR Quantity < 0
   OR SalesAmount < 0;

-- Integridade referencial da dimensão de produto
SELECT COUNT_BIG(*) AS OrphanRows
FROM dbo.FactSales AS f
LEFT JOIN dbo.DimProduct AS p
  ON p.ProductKey = f.ProductKey
WHERE p.ProductKey IS NULL;

-- Duplicidade de chave natural em uma dimensão tipo 2
SELECT CustomerId, COUNT(*) AS CurrentRows
FROM dbo.DimCustomer
WHERE IsCurrent = 1
GROUP BY CustomerId
HAVING COUNT(*) > 1;
```

O pipeline deve definir o que fazer quando uma regra falhar:

- rejeitar o lote inteiro;
- colocar linhas inválidas em uma área de erro;
- aceitar com alerta e correção posterior;
- bloquear a publicação do modelo semântico.

A decisão deve ser explícita. Aceitar silenciosamente dados inválidos cria uma
falha de confiança difícil de detectar depois.

## Perfil, score e SLO de qualidade

Um perfil pode medir contagem de linhas, valores nulos, cardinalidade, distribuição,
mínimo, máximo e padrões. Um score resume indicadores, mas não substitui a análise
da regra individual.

Para dados usados em produção, defina metas operacionais:

| Indicador | Exemplo de meta |
|---|---|
| Completude | Pelo menos 99,5% dos pedidos têm cliente |
| Atualidade | A carga diária termina até 06:00 |
| Integridade | Zero fatos órfãos publicados |
| Validade | 100% dos códigos pertencem ao domínio oficial |
| Reconciliação | Total financeiro dentro da tolerância acordada |

Um SLO de qualidade deve ter proprietário, janela de medição, limiar e ação quando
for violado. Não publique apenas “qualidade alta” sem explicar como foi calculada.

## Data contract

Um **data contract** é um acordo explícito entre produtor e consumidor sobre o
formato e o comportamento de um conjunto de dados. Pode incluir:

- nome e tipo das colunas;
- significado de negócio e unidade de medida;
- chave e granularidade;
- regras de nulidade e domínio;
- frequência e atraso máximo;
- comportamento de alterações e remoções;
- classificação de sensibilidade;
- política de compatibilidade e aviso de mudanças.

O contrato não é apenas um arquivo de schema. Ele deve explicar o significado dos
dados e como o consumidor será avisado quando a mudança puder quebrar relatórios,
pipelines, APIs ou modelos de IA.

## Governança e responsabilidades

Governança define quem pode descobrir, interpretar, aprovar, alterar e usar um
ativo. Distribua responsabilidades:

| Papel | Responsabilidade |
|---|---|
| Proprietário do dado | Decide significado, uso permitido e nível de qualidade |
| Data steward | Mantém glossário, regras, classificação e resolução de problemas |
| Produtor | Publica dados conforme o contrato e informa mudanças |
| Consumidor | Usa o ativo conforme o contrato e reporta problemas |
| Administrador | Configura acesso, políticas, auditoria e plataforma |

Governança não significa conceder acesso amplo. Descoberta, autorização e uso são
decisões diferentes: o usuário pode descobrir que um produto existe sem poder ler
seu conteúdo.

## Catálogo, glossário e produto de dados

Um catálogo deve permitir localizar ativos e responder:

- quem é o proprietário;
- qual é a definição de cada termo;
- de onde o dado veio;
- quando foi atualizado;
- qual é seu nível de qualidade;
- quem pode acessá-lo;
- quais relatórios e pipelines dependem dele.

Um **glossário** conecta termos técnicos a definições de negócio. Um **produto de
dados** agrupa ativos com finalidade, proprietário, documentação, contrato e
expectativa de qualidade. A publicação de uma tabela sem contexto não cria, por si
só, um produto de dados confiável.

## Linhagem e análise de impacto

Linhagem mostra a relação entre origem, processos, tabelas, modelos e relatórios.
Ela é útil para:

- investigar a causa de uma falha de qualidade;
- descobrir quais relatórios serão afetados por uma mudança;
- comprovar origem e transformação de um indicador;
- planejar migrações e descontinuação de ativos;
- apoiar auditoria e conformidade.

```text
CRM.Customer.Email
        ↓ pipeline
Silver.Customer
        ↓ carga SCD
Gold.DimCustomer.EmailAddress
        ↓ modelo semântico
Relatório de retenção
```

Linhagem não é o mesmo que monitoramento. A linhagem explica dependências; o
monitoramento mostra execução, duração, falha e atraso. Os dois são necessários
para análise de causa raiz.

No Microsoft Purview, a linhagem depende de registrar e examinar as fontes. A
cobertura e a granularidade não são uniformes para todos os itens: alguns cenários
mostram metadados e relações em nível de item, enquanto outros oferecem detalhes
mais granulares. Confirme as limitações da fonte antes de prometer linhagem de
coluna ou de transformação.

## Classificação, proteção e uso responsável

Classifique dados sensíveis, como identificadores pessoais, dados financeiros e
segredos comerciais. Relacione classificação à proteção:

- controle de acesso e menor privilégio;
- RLS/CLS quando aplicável;
- etiquetas de sensibilidade;
- prevenção contra perda de dados;
- mascaramento ou anonimização;
- retenção e descarte;
- auditoria e revisão de uso.

Uma etiqueta ou classificação facilita governança, mas não substitui permissões.
Do mesmo modo, RLS no modelo semântico não protege automaticamente consultas
diretas à fonte por outros caminhos.

## Alterações de schema

Nem toda alteração tem o mesmo risco:

| Alteração | Risco típico | Tratamento |
|---|---|---|
| Adicionar coluna opcional | Baixo, se consumidores ignorarem extras | Documentar e validar contrato |
| Renomear coluna | Alto | Versão, migração e comunicação |
| Alterar tipo | Alto | Compatibilidade, backfill e testes |
| Alterar significado | Alto mesmo sem mudar schema | Atualizar glossário e contrato |
| Reduzir domínio permitido | Médio/alto | Validar consumidores e histórico |
| Remover coluna | Alto | Impact analysis e período de descontinuação |

Use validação de schema, testes de integração e análise de impacto antes da
publicação. Compatibilidade técnica não garante compatibilidade semântica.

## Governança para dados usados por IA

Embeddings, RAG e modelos preditivos também dependem da qualidade e da segurança
da origem. Antes de indexar dados para IA:

- confirme que o conteúdo pode ser usado nesse propósito;
- preserve origem, versão e data de ingestão;
- aplique autorização antes de recuperação e geração;
- remova ou proteja dados sensíveis desnecessários;
- monitore alterações na fonte e no índice;
- registre quais fontes fundamentaram a saída.

Dados mal classificados ou sem linhagem podem produzir uma resposta tecnicamente
plausível, porém indevida ou impossível de auditar.

## Checklist de governança

- O ativo tem proprietário e steward definidos?
- Sua granularidade, significado e unidade estão documentados?
- Há regras de qualidade automatizadas e alertas?
- O contrato define schema, atualização e compatibilidade?
- O catálogo mostra classificação, acesso e uso pretendido?
- A linhagem permite rastrear a origem até o relatório?
- As limitações de cobertura da linhagem foram registradas?
- Existe análise de impacto para alterações?
- Dados sensíveis estão protegidos nos ambientes e exportações?
- O uso em modelos de IA tem finalidade e autorização explícitas?

## Documentação oficial

- [Governança de dados com Microsoft Purview](https://learn.microsoft.com/en-us/purview/data-governance-overview)
- [Usar Microsoft Purview para governar o Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/governance/microsoft-purview-fabric)
- [Metadados e linhagem do Fabric no Microsoft Purview](https://learn.microsoft.com/en-us/purview/data-map-lineage-fabric)
- [Qualidade de dados no Unified Catalog](https://learn.microsoft.com/en-us/purview/unified-catalog-data-quality)
- [Segurança no Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/security/security-overview)

---

**[← Modelos Semânticos e Power BI](./07-semantic-models-powerbi.md) | [↑ Voltar para Outros Tópicos](./other-topics.md)**
