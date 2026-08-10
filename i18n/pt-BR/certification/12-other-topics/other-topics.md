---
title: Outros Tópicos de Arquitetura
type: category
tags: [arquitetura, data-vault, microsoft-fabric, medalhão, data-mesh]
status: complete
---

# Outros Tópicos de Arquitetura

Estes guias complementam as seções principais do DP-800 com padrões mais amplos de arquitetura de dados.

São materiais complementares de arquitetura, não domínios adicionais do exame DP-800. Use-os para comparar arquitetura de plataforma, camadas de qualidade e integração historizada antes de escolher um desenho.

| Guia | Foco |
| --- | --- |
| [Arquitetura Data Vault](./03-data-vault-architecture.md) | Hubs, links, satellites, historização, Raw Vault e Business Vault |
| [Arquitetura do Microsoft Fabric](./04-fabric-architecture.md) | OneLake, Lakehouse, Warehouse, workloads, Direct Lake e governança |
| [Arquitetura Medallion](./02-medallion-architecture-fabric.md) | Bronze, Silver, Gold, progressão de qualidade e Fabric |
| [EAV, Data Mesh e SQL Server](./01-architectures-eav-datamesh-sqlserver.md) | Modelagem dinâmica, Data Mesh e integração com SQL Server |

## Por onde começar

| Se a pergunta principal for... | Comece por... |
| --- | --- |
| Como Fabric, OneLake, Lakehouse, Warehouse e Power BI se encaixam? | [Arquitetura do Microsoft Fabric](./04-fabric-architecture.md) |
| Como os dados evoluem da ingestão bruta até o consumo confiável? | [Arquitetura Medalhão](./02-medallion-architecture-fabric.md) |
| Como integrar várias fontes preservando histórico e linhagem? | [Arquitetura Data Vault](./03-data-vault-architecture.md) |

## Como estudar

Comece pela arquitetura do Fabric para obter a visão da plataforma. Depois estude Medallion para entender camadas de qualidade e Data Vault para integração historizada. Compare os dois com o guia de EAV/Data Mesh antes de escolher um padrão.

---

**[↑ Voltar à Certificação](../dp-800-overview.md)**
