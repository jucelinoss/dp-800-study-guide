---
title: Padrões de Integração e Movimentação de Dados
type: study-material
tags:
  - dp-800
  - data-integration
  - etl
  - elt
  - batch
  - streaming
  - fabric
---

> [!info] Escopo
>
> Este tópico apresenta critérios para escolher entre carga em lote, pipelines,
> Copy job, mirroring, shortcuts e streaming no Microsoft Fabric. Ele complementa
> Medallion Architecture, SCD e Fabric Architecture.

# Padrões de Integração e Movimentação de Dados

Integração de dados é o conjunto de processos que torna dados disponíveis em um
destino para transformação, consulta, análise ou aplicação. A escolha do padrão
depende de latência, volume, transformação, governança e custo operacional.

```text
Fonte → captura/movimentação → armazenamento → transformação → consumo
             batch | CDC | streaming | shortcut | mirroring
```

## ETL versus ELT

### ETL

No **ETL**, os dados são extraídos, transformados e depois carregados no destino.
É útil quando a transformação deve ocorrer antes de gravar no destino, quando o
destino não deve receber dados brutos ou quando a ferramenta de integração já
controla a transformação.

### ELT

No **ELT**, os dados são extraídos, carregados em uma camada de aterrissagem e
transformados usando o processamento do destino. É comum em lakehouses e
warehouses modernos, nos quais manter uma camada bruta facilita reprocessamento,
auditoria e evolução das transformações.

| Critério | ETL | ELT |
|---|---|---|
| Momento da transformação | Antes da carga final | Depois da aterrissagem |
| Reprocessamento | Pode exigir nova extração | Pode reutilizar a camada bruta |
| Dependência | Motor da ferramenta de integração | Capacidade do destino |
| Uso comum | Integrações com regras na origem do fluxo | Lakehouse, warehouse e camadas Bronze/Silver/Gold |

ETL e ELT não são mutuamente exclusivos. Um pipeline pode validar e mascarar
dados durante a ingestão e aplicar transformações dimensionais no destino.

## Batch, incremental e streaming

### Batch

Uma carga em lote processa um conjunto de dados em uma janela definida. É adequada
quando minutos ou horas de latência são aceitáveis e quando o custo e a simplicidade
operacional são mais importantes que atualização contínua.

### Incremental

Uma carga incremental processa apenas o que mudou desde o último ponto confirmado.
Pode usar watermark, CDC, Change Tracking, arquivos particionados ou um cursor da
origem. O estado do processamento deve ser persistido para permitir retomada e
reprocessamento.

### Streaming

Streaming processa eventos continuamente ou em micro-lotes. É indicado quando a
latência baixa é requisito do negócio, como detecção de fraude, telemetria,
monitoramento operacional ou alertas.

Não use streaming apenas porque os dados chegam frequentemente. Primeiro defina o
SLO de latência e verifique se a complexidade operacional é justificável.

## Estratégias de integração no Fabric

O Fabric oferece diferentes caminhos. Eles não são equivalentes:

| Opção | Objetivo principal | Transformação | Latência típica |
|---|---|---|---|
| Pipeline/Copy activity | Orquestrar e mover dados | Baixa a complexa, conforme as atividades | Agendada ou acionada |
| Copy job | Ingestão e cópia em lote/incremental | Geralmente baixa | Batch ou incremental |
| Mirroring | Replicar uma base ou catálogo operacional | Pouca transformação no caminho de replicação | Próxima do tempo real |
| OneLake shortcut | Referenciar dados sem copiar | Nenhuma ou transformação de shortcut | Depende da origem |
| Eventstream | Ingerir, rotear e processar eventos | Transformações de streaming | Tempo real |
| Dataflow Gen2 | Transformação visual com Power Query | Baixa a média | Batch/agendada |

### Pipelines e Copy activity

Use pipelines quando precisar de orquestração explícita:

- dependências entre atividades;
- parâmetros e metadados de controle;
- retries e tratamento de falha;
- agendamento ou acionamento;
- execução de notebooks, procedures, cópias e validações;
- cargas dimensionais e transformação em várias etapas.

Copy activity move dados, mas não substitui o desenho de controle de carga. Uma
carga incremental deve registrar watermark, lote, origem, destino, contagens e
status.

### Copy job

Copy job é uma opção de baixa complexidade para copiar dados com suporte a cenários
como carga em massa, cópia incremental e, conforme a fonte, CDC. Use-o quando a
movimentação for o principal requisito e a orquestração personalizada for limitada.

Se o fluxo exigir muitas decisões, regras condicionais, várias etapas ou lógica de
negócio, um pipeline pode ser mais apropriado.

### Mirroring

Mirroring disponibiliza uma base ou catálogo externo no Fabric. Dependendo da
origem, o Fabric pode replicar os dados para o OneLake ou usar referências a dados
em formato aberto.

Use mirroring quando quiser:

- disponibilizar uma base operacional para análise com pouca configuração;
- manter uma cópia próxima do tempo real no OneLake;
- analisar dados replicados junto com outras cargas do Fabric;
- evitar construir uma pipeline completa para a replicação inicial.

Limitações importantes:

- replicação não substitui transformações de negócio;
- tabelas espelhadas podem ser somente leitura no destino;
- falha ou pausa na origem pode afetar consumidores e shortcuts dependentes;
- é necessário monitorar atraso, erro de replicação e cobertura da fonte.

### OneLake shortcuts

Shortcut é uma referência a tabelas, pastas ou arquivos que permanecem na origem.
É útil para:

- acessar dados de ADLS, S3, outro workspace ou outro tenant sem criar cópia;
- compartilhar dados entre domínios;
- montar padrões de Data Mesh;
- disponibilizar formatos abertos no namespace do OneLake.

Shortcut não é uma cópia independente. Se a origem ficar indisponível, ou se o
acesso mudar, o consumidor poderá ser afetado. Também não use shortcut para
substituir transformações complexas, controle de versão ou persistência histórica.

### Eventstream

Eventstream é voltado para ingestão e processamento de eventos em tempo real.
Use-o quando a solução precisa reagir a eventos, rotear dados para destinos ou
aplicar transformações de streaming.

Streaming exige decisões adicionais:

- ordenação e atraso de eventos;
- duplicidade e entrega pelo menos uma vez;
- janela de agregação;
- checkpoint e retomada;
- schema evolution;
- retenção e replay;
- destino idempotente.

## Watermark, CDC e Change Tracking

Esses mecanismos resolvem problemas relacionados, mas não idênticos:

| Mecanismo | O que informa | Quando usar |
|---|---|---|
| Watermark | Até qual posição/data a carga confirmou | Origem possui coluna ou sequência confiável |
| CDC | Inserções, alterações e exclusões detalhadas | É necessário conhecer a operação e os valores alterados |
| Change Tracking | Quais linhas mudaram desde uma versão | Basta reconsultar as linhas afetadas |
| Mirroring | Replicação contínua gerenciada | Disponibilizar a origem para análise com pouca orquestração |

Uma carga pode combinar mecanismos: CDC identifica as alterações, watermark
controla a janela processada e SCD determina como atualizar a dimensão.

## Idempotência e controle de lotes

Uma integração confiável deve ser reexecutável. Registre pelo menos:

```text
BatchId
SourceName
WatermarkStart
WatermarkEnd
StartedAt
FinishedAt
RowsRead
RowsWritten
RowsRejected
Status
ErrorMessage
```

Padrão operacional:

1. Leia o último watermark confirmado.
2. Capture uma janela com limite superior definido.
3. Grave os dados em staging identificando o `BatchId`.
4. Valide schema e regras de qualidade.
5. Faça a transformação e a publicação em uma transação ou etapa controlada.
6. Só avance o watermark depois da publicação bem-sucedida.
7. Registre o resultado e permita replay do lote.

Nunca avance o watermark antes de garantir que os dados foram persistidos. Caso
contrário, uma falha entre leitura e escrita pode causar perda silenciosa.

## Como escolher

```text
Precisa de eventos e baixa latência?
├── Sim → Eventstream/streaming
└── Não
    ├── Precisa replicar uma base quase em tempo real?
    │   ├── Sim → Mirroring
    │   └── Não
    ├── Dados já estão em formato aberto e não precisam ser copiados?
    │   ├── Sim → OneLake shortcut
    │   └── Não
    ├── Precisa de cópia incremental com pouca orquestração?
    │   ├── Sim → Copy job
    │   └── Não → Pipeline/Copy activity
```

Depois da primeira escolha, valide transformação, segurança, custo, suporte da
fonte, observabilidade, reprocessamento e SLO de latência.

## Relação com Medallion e Data Vault

Integração é o mecanismo de movimentação; Medallion é uma organização de camadas;
Data Vault é um padrão de integração e historização; modelo dimensional é um
formato de consumo analítico. Eles podem coexistir:

```text
Pipeline/Copy job/Mirroring
              ↓
        Bronze ou Raw Vault
              ↓ transformação
        Silver ou Business Vault
              ↓ curadoria
        Gold dimensional
              ↓
        Modelo semântico
```

Não transforme toda origem diretamente em uma dimensão Gold se ainda não houver
controle de qualidade, histórico, chaves e regras de negócio definidos.

## Checklist de decisão

- Qual é o SLO de latência: batch, quase real-time ou real-time?
- A origem oferece CDC, watermark ou apenas consulta completa?
- É necessário copiar os dados ou um shortcut atende?
- Mirroring é suportado e adequado para a origem?
- Há transformação simples ou orquestração complexa?
- O destino precisa receber dados brutos, curados ou ambos?
- Como duplicidades, eventos fora de ordem e retries serão tratados?
- O watermark só avança após uma publicação confirmada?
- Há observabilidade de atraso, volume, erro e qualidade?
- O desenho permite replay sem duplicar dados?

## Documentação oficial

- [Escolher uma estratégia de movimentação de dados no Fabric](https://learn.microsoft.com/en-us/fabric/data-factory/decision-guide-data-movement)
- [Unificar dados com shortcuts e mirroring no OneLake](https://learn.microsoft.com/en-us/fabric/onelake/unify-data)
- [Ciclo de vida de dados no Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/fundamentals/data-lifecycle)
- [Obter dados no Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/fundamentals/get-data)

---

**[← Qualidade, Governança e Linhagem](./08-data-quality-governance-lineage.md) | [↑ Voltar para Outros Tópicos](./other-topics.md)**
