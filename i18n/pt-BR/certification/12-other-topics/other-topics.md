---
title: Outros Tópicos de Arquitetura
type: category
tags: [arquitetura, data-vault, microsoft-fabric, medalhão, data-mesh]
status: complete
---

# Outros Tópicos de Arquitetura

Estes guias complementam as seções principais do DP-800 com padrões mais amplos de arquitetura de dados.

São materiais complementares de arquitetura, não domínios adicionais do exame DP-800. Use primeiro a comparação arquitetural para entender o papel de cada padrão; depois consulte o guia específico conforme o problema que deseja estudar.

## Porta de entrada: compare antes de escolher

Comece por [Arquitetura Data Fabric e Microsoft Fabric](./04-fabric-architecture.md). Esse guia apresenta uma visão integrada das camadas de fontes, ingestão, armazenamento, processamento, serving e governança, além de mostrar como SQL Server, Microsoft Fabric, Databricks e ferramentas especializadas podem participar da solução.

Não há uma arquitetura universalmente correta. Data Fabric conecta capacidades e dados distribuídos; Lakehouse e Warehouse resolvem necessidades de armazenamento e consulta; Medallion organiza o refinamento; Data Vault prioriza integração e histórico; Data Mesh distribui propriedade por domínios; e EAV/JSON resolvem decisões de modelagem dinâmica.

## Mapa do capítulo

Os guias podem ser lidos como uma arquitetura de dados em camadas:

```text
Decisão arquitetural
    -> fontes, OLTP e modelagem
    -> ingestão, CDC, batch, streaming e eventos
    -> armazenamento, historização e refinamento
    -> fatos, dimensões e modelo semântico
    -> qualidade, contratos, MDM, catálogo e linhagem
    -> HA/DR, migração, operação e custo
    -> BI, APIs, aplicações e IA
```

| Grupo | Pergunta que responde | Guias principais |
| --- | --- | --- |
| **Arquitetura e escolha** | Qual padrão, plataforma ou distribuição faz sentido? | Data Fabric, Microsoft Fabric, Data Mesh, Data Vault e Medallion |
| **Modelagem e serving** | Como estruturar e publicar os dados? | OLTP/OLAP, dimensional e modelos semânticos; EAV/JSON ficam nos capítulos de banco e T-SQL |
| **Integração e mudança** | Como transportar e atualizar dados? | ETL/ELT, CDC, CT, watermark, mirroring e eventos |
| **Confiança e significado** | Como tornar o dado compreensível e confiável? | Qualidade, contratos, MDM, dados de referência, catálogo e linhagem |
| **Resiliência e ciclo de vida** | Como migrar, operar, recuperar e controlar custo? | HA/DR, modernização, observabilidade e FinOps |

Os grupos se conectam, mas não precisam ser implementados com uma única ferramenta. SQL Server pode permanecer como sistema transacional, enquanto Fabric, Databricks ou outras plataformas atendem ao processamento e consumo analítico.

| Guia | Foco |
| --- | --- |
| [Arquitetura Data Fabric e Microsoft Fabric](./04-fabric-architecture.md) | Comparação arquitetural, plataformas, integração com SQL Server, OneLake, Lakehouse e Warehouse |
| [Arquitetura Data Vault](./03-data-vault-architecture.md) | Hubs, links, satellites, historização, Raw Vault e Business Vault |
| [Arquitetura Medallion](./02-medallion-architecture-fabric.md) | Bronze, Silver, Gold, progressão de qualidade e Fabric |
| [Data Mesh e SQL Server](./01-architectures-eav-datamesh-sqlserver.md) | Produtos de dados, ownership, contratos e integração com SQL Server |
| [Modelagem dimensional](./05-dimensional-modeling.md) | Grain, fatos, dimensões, star schema e snowflake schema |
| [SCD e cargas dimensionais](./06-scd-and-dimensional-loading.md) | Slowly Changing Dimensions, cargas incrementais, CDC e idempotência |
| [Modelos semânticos e Power BI](./07-semantic-models-powerbi.md) | Relacionamentos, medidas, modos de armazenamento e RLS |
| [Qualidade, governança e linhagem](./08-data-quality-governance-lineage.md) | Dimensões de qualidade, contratos, catálogo, classificação e impacto |
| [Padrões de integração de dados](./09-data-integration-patterns.md) | ETL, ELT, batch, streaming, CDC, mirroring e Medallion |
| [OLTP, OLAP e workloads analíticos](./10-oltp-olap-and-analytical-workloads.md) | Normalização, columnstore, particionamento e serving analítico |
| [Alta disponibilidade e disaster recovery](./11-high-availability-disaster-recovery.md) | RPO, RTO, Always On, backups, failover e recuperação |
| [Modernização e migração do SQL Server](./12-sql-server-modernization-migration.md) | Avaliação, destinos Azure SQL, coexistência, cutover e rollback |
| [Operação e FinOps de plataformas de dados](./13-data-platform-operations-finops.md) | SLO, observabilidade, capacidade, throttling e custo |
| [MDM, dados de referência e contratos](./14-mdm-data-contracts.md) | Golden record, qualidade, ownership e evolução de schemas |
| [Arquitetura orientada a eventos](./15-event-driven-data-architecture.md) | CDC, outbox, brokers, idempotência, replay e contratos |

## Por onde começar

| Se a pergunta principal for... | Comece por... |
| --- | --- |
| Como Data Fabric, Microsoft Fabric, OneLake, Lakehouse, Warehouse e SQL Server se encaixam? | [Arquitetura Data Fabric e Microsoft Fabric](./04-fabric-architecture.md) |
| Qual arquitetura ou plataforma devo comparar antes de escolher? | [Arquitetura Data Fabric e Microsoft Fabric](./04-fabric-architecture.md) |
| Como os dados evoluem da ingestão bruta até o consumo confiável? | [Arquitetura Medalhão](./02-medallion-architecture-fabric.md) |
| Como integrar várias fontes preservando histórico e linhagem? | [Arquitetura Data Vault](./03-data-vault-architecture.md) |
| Como representar atributos dinâmicos? | [Colunas e Índices JSON](../01-database-objects/03-json-columns.md) |
| Como publicar dados por domínio? | [Data Mesh e SQL Server](./01-architectures-eav-datamesh-sqlserver.md) |
| Como projetar recuperação, failover e continuidade? | [Alta disponibilidade e disaster recovery](./11-high-availability-disaster-recovery.md) |
| Como modernizar ou migrar um SQL Server? | [Modernização e migração do SQL Server](./12-sql-server-modernization-migration.md) |
| Como medir operação, capacidade e custo? | [Operação e FinOps de plataformas de dados](./13-data-platform-operations-finops.md) |
| Como governar clientes, produtos e contratos de dados? | [MDM, dados de referência e contratos](./14-mdm-data-contracts.md) |
| Como publicar e consumir mudanças como eventos? | [Arquitetura orientada a eventos](./15-event-driven-data-architecture.md) |

## Como estudar

Comece pela comparação Data Fabric/Microsoft Fabric. Depois estude Medallion para entender camadas de qualidade, Data Vault para integração historizada e Data Mesh para propriedade por domínio. Para decisões de modelagem dinâmica, consulte o guia de JSON do capítulo de objetos de banco. Por fim, aprofunde os modelos dimensionais, cargas incrementais, modelos semânticos e governança conforme a necessidade.

### Trilha recomendada

1. **Visão geral:** Data Fabric e Microsoft Fabric.
2. **Fundação:** OLTP/OLAP, modelagem dimensional, Lakehouse, Warehouse e Medallion.
3. **Integração:** ETL/ELT, CDC, Change Tracking, watermark e eventos.
4. **Histórico e publicação:** Data Vault, SCD, modelos semânticos e produtos de dados.
5. **Confiança:** qualidade, contratos, MDM, dados de referência, catálogo e linhagem.
6. **Produção:** HA/DR, migração, observabilidade, FinOps e runbooks.

Não é necessário ler todos os guias como se fossem uma única implementação. Escolha a trilha conforme a pergunta arquitetural e use os checklists para comparar alternativas.

## Limites do capítulo

Este capítulo é complementar ao DP-800. Ele ajuda a conectar decisões de arquitetura ao SQL Server, Azure SQL e Microsoft Fabric, mas não substitui o estudo dos domínios principais do exame nem a documentação da versão específica do produto. Recursos de preview, limites de capacidade e opções de licenciamento devem ser confirmados no Microsoft Learn antes de uma implantação.

---

**[↑ Voltar à Certificação](../dp-800-overview.md)**
