---
title: Protegendo Endpoints de Modelos, GraphQL, REST e MCP (Securing Model, GraphQL, REST, and MCP Endpoints)
type: study-material
tags:
  - dp-800
  - managed-identity
  - graphql-security
  - rest-security
  - mcp-security
  - endpoint-security
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Protegendo Endpoints de Modelos de IA (Securing AI Model Endpoints)](#protegendo-endpoints-de-modelos-de-ia-securing-ai-model-endpoints)
>   - 🔹 [Chamando o Azure OpenAI com Identidade Gerenciada](#chamando-o-azure-openai-com-identidade-gerenciada)
>   - 🔹 [Criando a DATABASE SCOPED CREDENTIAL para Managed Identity](#criando-a-database-scoped-credential-para-managed-identity)
>   - 🔹 [Autenticação via Chave de API (Alternativa menos recomendada)](#autenticação-via-chave-de-api-alternativa-menos-recomendada)
> - 📍 [3. Protegendo o Data API Builder (REST e GraphQL)](#protegendo-o-data-api-builder-rest-e-graphql)
>   - 🔹 [Configurando Autenticação no Arquivo JSON](#configurando-autenticação-no-arquivo-json)
>   - 🔹 [Controle de Acesso Baseado em Roles no DAB](#controle-de-acesso-baseado-em-roles-no-dab)
>   - 🔹 [Controles Específicos para GraphQL](#controles-específicos-para-graphql)
> - 📍 [4. Protegendo Endpoints de Servidores MCP](#protegendo-endpoints-de-servidores-mcp)
>   - 🔹 [Normas de Segurança para MCP:](#normas-de-segurança-para-mcp)
> - 📍 [5. Segurança de Rede para Bancos de Dados](#segurança-de-rede-para-bancos-de-dados)
> - 📍 [6. Private Endpoints vs Service Endpoints](#private-endpoints-vs-service-endpoints)
> - 📍 [7. Regras de Firewall no Azure SQL Database](#regras-de-firewall-no-azure-sql-database)
> - 📍 [8. Autenticação por Managed Identity entre Serviços](#autenticação-por-managed-identity-entre-serviços)
> - 📍 [9. Criptografia de Tráfego em Trânsito (TLS)](#criptografia-de-tráfego-em-trânsito-tls)
> - 📍 [10. Microsoft Defender for SQL](#microsoft-defender-for-sql)
> - 📍 [11. Melhores Práticas (Best Practices)](#melhores-práticas-best-practices)
> - 📍 [12. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [13. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [14. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [15. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [16. Documentação Oficial](#documentação-oficial)

---

# Protegendo Endpoints de Modelos, GraphQL, REST e MCP (Securing Model, GraphQL, REST, and MCP Endpoints)

## Visão Geral (Overview)

Soluções de bancos de dados habilitadas para inteligência artificial expõem múltiplos tipos de conexões externas: endpoints de modelos de IA, APIs RESTful (via Data API Builder), endpoints GraphQL e servidores MCP. Cada canal de integração deve ser protegido utilizando identidades gerenciadas (Managed Identities), controles de firewalls e restrições rígidas de rede virtual (VNets).

> [!abstract]
>
> - Cobre segurança de rede e conexões para Azure SQL: regras de firewall, private endpoints, service endpoints e autenticação robusta.
> - A segurança de rede e autenticação de acessos atuam em camadas complementares — ambas devem estar corretas para a conexão estabelecer com sucesso.
> - Tópicos chave do exame: diferenças físicas entre private endpoints e service endpoints, autenticação Entra ID vs SQL Server Authentication e identidades gerenciadas.

> [!tip] O que o Exame Testa
>
> - **Private endpoint**: Vincula um IP privado interno do bloco da VNet corporativa ao banco; o tráfego de dados nunca trafega na internet pública; permite desativar acessos públicos.
> - **Service endpoint**: Rota otimizada pelo backbone físico da Microsoft; o IP do servidor SQL continua sendo público na internet.
> - **Managed identity**: Autenticação robusta sem senhas integrada ao Azure AD (Entra ID) dividida em System-assigned (vinculada ao recurso) vs User-assigned (independente e compartilhada).

---

## Protegendo Endpoints de Modelos de IA (Securing AI Model Endpoints)

### Chamando o Azure OpenAI com Identidade Gerenciada

```sql
-- Executar chamada segura a modelo LLM externo via sp_invoke_external_rest_endpoint
EXEC sp_invoke_external_rest_endpoint
    @url = 'https://myopenai.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-01',
    @method = 'POST',
    @credential = [https://myopenai.openai.azure.com], -- Ponteiro de credencial do banco
    @payload = N'{"messages":[{"role":"user","content":"Hello"}]}',
    @response = @response OUTPUT;
```

### Criando a DATABASE SCOPED CREDENTIAL para Managed Identity

```sql
-- Primeiro, conceda acesso na Azure OpenAI para a Managed Identity da SQL Database no portal
-- Depois, crie a credencial no banco apontando para a identidade gerenciada:
CREATE DATABASE SCOPED CREDENTIAL [https://myopenai.openai.azure.com]
WITH IDENTITY = 'Managed Identity';
```

> [!important] Dica para a Prova: DATABASE SCOPED CREDENTIAL com Managed Identity
>
> - Ao efetuar chamadas a modelos de IA externos via `sp_invoke_external_rest_endpoint`, a autenticação recomendada na prova é a de **Identidade Gerenciada**.
> - Para isso, cria-se a credencial de escopo de banco (`DATABASE SCOPED CREDENTIAL`) com o parâmetro `IDENTITY = 'Managed Identity'`, sem necessidade de passar chaves de API em texto plano.

### Autenticação via Chave de API (Alternativa menos recomendada)

```sql
-- Armazenar chaves em credenciais locais (Evite em produção)
CREATE DATABASE SCOPED CREDENTIAL [AzureOpenAIKey]
WITH IDENTITY = 'HTTPEndpointHeaders',
SECRET = '{"api-key":"sua-chave-api-aqui"}';
```

---

## Protegendo o Data API Builder (REST e GraphQL)

### Configurando Autenticação no Arquivo JSON

```json
// dab-config.json — seção de autenticação e runtime
{
    "runtime": {
        "rest": { "enabled": true },
        "graphql": { "enabled": true },
        "host": {
            "authentication": {
                "provider": "StaticWebApps"
            }
        }
    }
}
```

Provedores comuns de autenticação aceitos no DAB:

| Provedor (Provider) | Casos de Uso |
| :--- | :--- |
| `StaticWebApps` | Integrações nativas com Azure Static Web Apps. |
| `AzureAD` | `Autenticação baseada no Microsoft Entra ID (Azure AD)`. |
| `Simulator` | Ambientes locais e testes de desenvolvimento. |
| `Anonymous` | Acessos públicos sem necessidade de token de segurança. |

### Controle de Acesso Baseado em Roles no DAB

```json
// Configurar permissões por entidade e papel de usuário
{
    "entities": {
        "Order": {
            "permissions": [
                {
                    "role": "authenticated",
                    "actions": ["read"]
                },
                {
                    "role": "admin",
                    "actions": ["create", "read", "update", "delete"]
                }
            ]
        }
    }
}
```

### Controles Específicos para GraphQL

```graphql
# Desative a introspecção de schemas em produção para impedir engenharia reversa do banco
# No arquivo dab-config.json: "graphql": { "allow-introspection": false }

# Limite a profundidade de consultas encadeadas para mitigar ataques de negação de serviço (DoS)
# No arquivo dab-config.json: "graphql": { "depth-limit": 4 }
```

---

## Protegendo Endpoints de Servidores MCP

Os servidores MCP expõem tabelas e recursos de queries — garanta proteção robusta da mesma forma que protege conexões diretas do banco:

```json
// Configuração segura do MCP utilizando Managed Identity para desenvolvimento
{
    "servers": {
        "sql-secure": {
            "type": "stdio",
            "command": "dab",
            "args": ["start", "--config", "dab-config.json"],
            "env": {
                "MSSQL_CONNECTION_STRING": "Server=myserver.database.windows.net;Database=mydb;Authentication=ActiveDirectoryManagedIdentity;"
            }
        }
    }
}
```

### Normas de Segurança para MCP:

1. Utilize autenticação por Managed Identity — impeça chaves ou senhas explícitas nos arquivos.
2. Configure um usuário de acesso exclusivo para o MCP no banco com baixas permissões.
3. Exponha somente entidades autorizadas no `dab-config.json` e aplique permissões mínimas no banco.
4. Force acessos de redes por meio de Private Link ou caminhos restritos de firewall.
5. Habilite auditorias de logs no banco focando na atividade executada pelo usuário do MCP.

---

## Segurança de Rede para Bancos de Dados

```text
Azure SQL Server → Painel Networking:
├── Public endpoint: Desativar ou restringir a IPs conhecidos
├── Private endpoint: IP interno de VNet (Sem acesso via internet pública)
├── Service endpoints: Rota interna otimizada via Azure Backbone
└── Firewall rules: Limitação explícita por regras de IPs e sub-redes
```

---

## Private Endpoints vs Service Endpoints

- **Service Endpoint**: Estende a identidade da rede virtual (VNet) até o Azure SQL — o tráfego transita pelo backbone interno da Azure, mas o banco de dados continua possuindo um IP público ativo exposto na internet.
- **Private Endpoint**: Atribui um IP privado fixo (ex: `10.0.0.5`) pertencente ao bloco da sub-rede da VNet ao servidor de banco, utilizando o serviço **Azure Private Link**. O tráfego público à internet é 100% desativado.

| Característica | Service Endpoint | Private Endpoint |
| :--- | :--- | :--- |
| IP Público Ativo | Sim, exposto na internet pública. | Não, bloqueado (caso desativado). |
| Integração VNet | Rota otimizada pelo backbone. | IP privado local integrado na VNet. |
| Acesso Multiregião | Limitado. | Sim (Suportado via Private Link). |
| Custos | Gratuito. | Cobrança baseada no uso do Private Link. |
| Preferência no Exame | Abordagem clássica legada. | `Recomendável e moderna`. |

> [!tip] Diferença Crítica no Exame: Private Endpoint vs Service Endpoint
>
> - **Private Endpoint (Ponto de Extremidade Privado)**: Reduz a zero a exposição pública do banco. Ele recebe um IP privado interno do bloco da sua VNet (ex: `10.0.0.5`), permitindo desativar por completo a interface pública do SQL Server. Tráfego interno de rede total.
> - **Service Endpoint (Ponto de Extremidade de Serviço)**: Mantém o IP público do SQL Server ativo na internet, porém cria uma rota otimizada para o tráfego da VNet pelo backbone da Azure. Não privatiza o acesso de rede do banco.

---

## Regras de Firewall no Azure SQL Database

Mecanismos de firewalls suportados:

- **Server-level firewall rules**: Regras globais aplicadas a todos os bancos contidos sob a mesma instância lógica; configurável via portal ou master.
- **Database-level firewall rules** (`sp_set_database_firewall_rule`): Regras locais que se sobrepõem às gerais do servidor para uma base específica.
- **Allow Azure services (Regra 0.0.0.0)**: Permite acessos automáticos de quaisquer instâncias ou recursos Azure. Cuidado: expõe o banco a tráfegos de outros tenants na nuvem pública.
- **Virtual network rules**: Restrições de acessos a sub-redes corporativas específicas.

```sql
-- Criar regra de IP local na base correspondente
EXEC sp_set_database_firewall_rule
    @name = N'DevMachine',
    @start_ip_address = '203.0.113.0',
    @end_ip_address = '203.0.113.0';

-- Listar regras de IPs ativas na base
SELECT * FROM sys.database_firewall_rules;

-- Excluir regra
EXEC sp_delete_database_firewall_rule @name = N'DevMachine';
```

> [!warning] O Perigo da Regra de Firewall 0.0.0.0 (Allow Azure Services)
>
> - Habilitar a opção "Allow Azure services and resources to access this server" cria implicitamente uma regra de firewall para o IP `0.0.0.0`.
> - **Cuidado de Segurança**: Isso permite conexões originadas de **qualquer** recurso hospedado no Azure, incluindo assinaturas e tenants de outras empresas. Em produção, prefira regras de VNet explícitas ou Private Endpoints.

---

## Autenticação por Managed Identity entre Serviços

A utilização de identidades gerenciadas (Managed Identities) elimina a necessidade de chaves, senhas de conexão e processos complexos de rotação manual de segredos em código.

- **System-assigned (Atribuída pelo sistema)**: Ciclo de vida atrelado ao recurso Azure (ex:VM). Excluir o recurso deleta a identidade de forma automática no Azure AD.
- **User-assigned (Atribuída pelo usuário)**: Recurso independente. Pode ser compartilhado e mapeado entre múltiplos serviços.

```sql
-- No Azure SQL Database (Conectado com administrador AD):
-- Registrar a identidade como usuário do banco
CREATE USER [my-function-app] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [my-function-app];
```

---

## Criptografia de Tráfego em Trânsito (TLS)

- O Azure SQL Database exige TLS 1.2 ou superior ativo para qualquer comunicação de pacotes; conexões com TLSs antigos são abortadas de imediato.
- Configure o parâmetro `Encrypt=True` nas strings de conexões das aplicações para forçar conformidade e proteção.
- Utilize `TrustServerCertificate=False` para garantir que o driver cliente valide ativamente a cadeia de certificações do servidor, impedindo ataques de man-in-the-middle.

```sql
-- Padrão seguro de string de conexão T-SQL
-- Server=myserver.database.windows.net;Database=mydb;
-- Authentication=Active Directory Managed Identity;
-- Encrypt=True;TrustServerCertificate=False;
```

---

## Microsoft Defender for SQL

Oferece duas ferramentas integradas em um único plano de proteção ativa:

- **Advanced Threat Protection**: Rastreia padrões suspeitos de acessos lógicos, ataques por SQL Injection e anomalias de acessos fora de locais habituais.
- **Vulnerability Assessment**: Executa varreduras recorrentes no banco buscando configurações de segurança inconsistentes, excessos de privilégios ou falhas de conformidades.

Os alertas gerados são consolidados e exibidos no painel do Microsoft Defender for Cloud.

---

## Melhores Práticas (Best Practices)

- Desative a rota de endpoint público em bancos de produção do Azure SQL, substituindo o tráfego de dados por Private Endpoints (IPs privados locais).
- Privilegie a autenticação baseada em Managed Identities no tráfego entre microsserviços.
- Desative recursos de introspecção no Data API Builder em ambientes produtivos para mitigar vazamentos de schemas.
- Sempre declare `Encrypt=True` e `TrustServerCertificate=False` nas strings de conexão das aplicações.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - Para chamadas a endpoints com `sp_invoke_external_rest_endpoint` de forma passwordless, utilize a sintaxe `DATABASE SCOPED CREDENTIAL` com `IDENTITY = 'Managed Identity'`.
> - Desativar introspecção de schemas no DAB é feito configurando `"allow-introspection": false`.
> - Private Endpoints atribuem IPs internos da sub-rede da VNet ao banco; Service Endpoints apenas otimizam tráfegos mantendo o IP público ativo.
> - Para habilitar acessos a Managed Identity no banco, execute `CREATE USER [nome] FROM EXTERNAL PROVIDER`.

---

## Resumo dos Conceitos (Key Takeaways)

- Managed Identities provêm conexões confiáveis e seguras sem chaves.
- O Data API Builder isola dados estruturados via arquivos de controle JSON.
- A proteção de redes por Private Links isola os servidores SQL da internet.
- O Microsoft Defender atua alertando anomalias estruturais de queries do banco.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma empresa exige que seu banco de dados Azure SQL fique inacessível a partir de requisições originadas na internet pública, permitindo conexões lógicas de rede apenas a partir de máquinas situadas dentro de sua própria rede virtual (VNet). Qual configuração atende a essa exigência de forma completa?

A. Ativar uma regra de firewall global liberando o bloco de IP externo correspondente.

B. Configurar uma regra de Service Endpoint e desabilitar acessos gerais no firewall.

C. Criar um Private Endpoint associado ao servidor do banco de dados e desabilitar o acesso pelo endpoint público (Disable public access).

D. Exigir o tráfego por autenticações de Managed Identities desabilitando logins SQL.

> [!success]- Resposta
> **C — Criar um Private Endpoint associado ao servidor do banco de dados e desabilitar o acesso pelo endpoint público (Disable public access)**
>
> Ao criar um Private Endpoint, o Azure atribui um IP interno da sub-rede da rede virtual (VNet) ao banco. Desabilitar a interface pública (Disable public access) remove qualquer possibilidade de conexão direta via internet pública, atendendo de forma completa ao requisito. A alternativa B (Service Endpoint) mantém a interface pública e o IP externo ativos na internet.

---

## Managed Identity para endpoints REST

Para `sp_invoke_external_rest_endpoint`, Managed Identity não é API key. O `SECRET`
identifica o recurso protegido; para Azure OpenAI, o Learn usa
`{"resourceid":"https://cognitiveservices.azure.com"}`. Conceda `REFERENCES` na
credential ao principal que a usará e valide regras de URL/escopo e plataforma.

## Tópicos Relacionados

- [03-Permissões & Acessos](./03-permissions-access.md)
- [01-Data API Builder](../08-azure-services-integration/01-data-api-builder.md)
- [03-Endpoints de Servidores MCP](../04-ai-assisted-tools/03-mcp-server-endpoints.md)

---

## Documentação Oficial

- [Managed Identity for SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity)
- [DAB Authentication](https://learn.microsoft.com/en-us/azure/data-api-builder/authentication-azure-ad)
- [Database Scoped Credentials](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-database-scoped-credential-transact-sql)
- [Azure SQL Firewall Rules](https://learn.microsoft.com/en-us/azure/azure-sql/database/firewall-configure)
- [Azure Private Link for SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview)

---

**[← Anterior](./04-auditing.md) | [↑ Voltar para a Seção](./data-security-compliance.md)**
