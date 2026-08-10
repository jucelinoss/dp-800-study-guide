---
title: Other Architecture Topics
type: category
tags: [architecture, data-vault, microsoft-fabric, medallion, data-mesh]
status: complete
---

# Other Architecture Topics

These guides complement the DP-800 core sections with broader data architecture patterns.

They are supplemental architecture material, not additional DP-800 exam domains. Use them to compare platform architecture, data-quality layering, and historized integration before choosing a design.

| Guide | Focus |
| --- | --- |
| [Data Vault Architecture](./03-data-vault-architecture.md) | Hubs, links, satellites, historization, Raw Vault, and Business Vault |
| [Microsoft Fabric Architecture](./04-fabric-architecture.md) | OneLake, Lakehouse, Warehouse, workloads, Direct Lake, and governance |
| [Medallion Architecture](./02-medallion-architecture-fabric.md) | Bronze, Silver, Gold, quality progression, and Fabric implementation |
| [Data Mesh and SQL Server](./01-architectures-eav-datamesh-sqlserver.md) | Data products, ownership, contracts, and SQL Server integration |

## Choosing a starting point

| If the main question is... | Start with... |
| --- | --- |
| How should Fabric workloads, OneLake, Lakehouse, Warehouse, and Power BI fit together? | [Microsoft Fabric Architecture](./04-fabric-architecture.md) |
| How should data move from raw ingestion to trusted consumption? | [Medallion Architecture](./02-medallion-architecture-fabric.md) |
| How do we integrate many sources while preserving history and lineage? | [Data Vault Architecture](./03-data-vault-architecture.md) |

## How to study

Start with Fabric architecture for the platform view. Then study Medallion for data-quality layers, Data Vault for historized integration, and Data Mesh for domain ownership. For dynamic modeling decisions, use the JSON guide in the database-objects chapter.

---

**[↑ Back to Certification](../dp-800-overview.md)**
