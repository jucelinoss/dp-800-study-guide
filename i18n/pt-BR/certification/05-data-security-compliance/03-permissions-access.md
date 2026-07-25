---
title: Permissões em Nível de Objeto e Acesso Seguro (Object-Level Permissions and Secure Access)
type: study-material
tags:
  - dp-800
  - permissions
  - rbac
  - managed-identity
  - passwordless
  - azure-ad
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Hierarquia de Permissões (Permission Hierarchy)](#hierarquia-de-permissões-permission-hierarchy)
> - 📍 [3. Principais de Servidor e Banco (Server and Database Principals)](#principais-de-servidor-e-banco-server-and-database-principals)
> - 📍 [4. Roles de Banco de Dados (Database Roles)](#roles-de-banco-de-dados-database-roles)
> - 📍 [5. Comandos de Permissão em Nível de Objeto](#comandos-de-permissão-em-nível-de-objeto)
> - 📍 [6. Acesso Sem Senha com Identidade Gerenciada (Managed Identity)](#acesso-sem-senha-com-identidade-gerenciada-managed-identity)
>   - 🔹 [Tipos de Managed Identity](#tipos-de-managed-identity)
>   - 🔹 [Mapeando Managed Identity no Azure SQL](#mapeando-managed-identity-no-azure-sql)
>   - 🔹 [Métodos de Autenticação Entra ID (Azure AD)](#métodos-de-autenticação-entra-id-azure-ad)
> - 📍 [7. Princípio do Menor Privilégio (Least Privilege)](#princípio-do-menor-privilégio-least-privilege)
> - 📍 [8. Contained Database Users (Usuários de Banco Contidos)](#contained-database-users-usuários-de-banco-contidos)
> - 📍 [9. Contexto de Execução com EXECUTE AS](#contexto-de-execução-com-execute-as)
>   - 🔹 [Escopos do EXECUTE AS](#escopos-do-execute-as)
> - 📍 [10. Cadeia de Propriedade (Ownership Chaining)](#cadeia-de-propriedade-ownership-chaining)
> - 📍 [11. Quadro de Roles de Banco vs Servidor](#quadro-de-roles-de-banco-vs-servidor)
> - 📍 [12. Melhores Práticas (Best Practices)](#melhores-práticas-best-practices)
> - 📍 [13. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [14. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [15. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [16. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [17. Documentação Oficial](#documentação-oficial)

---

# Permissões em Nível de Objeto e Acesso Seguro (Object-Level Permissions and Secure Access)

## Visão Geral (Overview)

O SQL Server utiliza um modelo hierárquico e granular de permissões: logins no nível do servidor (server-level logins), usuários no nível de banco de dados (database-level users), roles e comandos de objeto DDL (`GRANT`, `DENY`, `REVOKE`). O Azure SQL Database estende esse mecanismo integrando autenticação baseada no Microsoft Entra ID (antigo Azure Active Directory) e identidades gerenciadas (Managed Identities) para acesso sem senha (passwordless).

> [!abstract]
>
> - Cobre comandos `GRANT`/`DENY`/`REVOKE`, roles padrão do banco, cadeias de propriedade (ownership chaining) e contexto de execução com `EXECUTE AS`.
> - O SQL Server organiza permissões em cascata: Servidor → Banco de Dados → Schema → Objeto.
> - Tópicos chave do exame: precedência do comando `DENY` sobre o `GRANT`, roles padrão do banco e comportamento de ownership chaining.

> [!tip] O que o Exame Testa
>
> - **DENY sempre ganha (wins)** de um GRANT — se houver um `DENY` direto no usuário, o acesso será bloqueado mesmo que ele pertença a uma role com permissão `GRANT SELECT`.
> - **REVOKE** remove uma permissão concedida ou negada anteriormente — ele apenas anula um comando prévio, não bloqueando novos acessos herdados.
> - Roles fixas: `db_datareader` = SELECT em todas as tabelas; `db_datawriter` = INSERT/UPDATE/DELETE; `db_owner` = controle total; `db_ddladmin` = permissões para DDL.

---

## Hierarquia de Permissões (Permission Hierarchy)

```text
Nível Servidor (Login) → Nível Banco (User/Role) → Nível Schema → Nível Objeto (GRANT/DENY)
```

---

## Principais de Servidor e Banco (Server and Database Principals)

```sql
-- Login de SQL Server comum (Não recomendado para nuvem; use autenticação Entra ID)
CREATE LOGIN AppLogin WITH PASSWORD = 'P@ssword123!';

-- Login baseado no Azure AD / Entra ID (Azure SQL)
CREATE LOGIN [user@contoso.com] FROM EXTERNAL PROVIDER;

-- Usuário mapeado para o Login
CREATE USER AppUser FOR LOGIN AppLogin;

-- Usuário baseado em Managed Identity (Entra ID)
CREATE USER [app-service-identity] FROM EXTERNAL PROVIDER;

-- Usuário sem Login de servidor (Contained Database User)
CREATE USER ReportUser WITH PASSWORD = 'Report#2025!';
```

---

## Roles de Banco de Dados (Database Roles)

```sql
-- Mapear usuários para as roles nativas do sistema
ALTER ROLE db_datareader ADD MEMBER ReportUser;     -- SELECT em qualquer tabela/view
ALTER ROLE db_datawriter ADD MEMBER ETLUser;        -- INSERT/UPDATE/DELETE
ALTER ROLE db_ddladmin   ADD MEMBER SchemaOwner;    -- CREATE/ALTER/DROP

-- Criar Role customizada e aplicar regras granulares
CREATE ROLE OrdersReadOnly;
GRANT SELECT ON SCHEMA::dbo TO OrdersReadOnly;
DENY  SELECT ON dbo.CustomerPayments TO OrdersReadOnly;
ALTER ROLE OrdersReadOnly ADD MEMBER [analyst@contoso.com];
```

> [!important] Cuidado na Prova: DENY Sempre Sobrescreve (Wins)
>
> - Se um usuário pertencer a uma Role que tem acesso `GRANT SELECT` a uma tabela, mas pertencer a outra Role (ou tiver em seu usuário) um `DENY SELECT` na mesma tabela, o acesso será **negado**.
> - O `DENY` tem precedência absoluta sobre qualquer concessão `GRANT` direta ou herdada por Roles no SQL Server. A única exceção são os membros da role de sistema `sysadmin`, que ignoram qualquer restrição do banco.

---

## Comandos de Permissão em Nível de Objeto

```sql
-- GRANT: Concessão explícita de acesso
GRANT SELECT ON dbo.Customers TO ReportUser;
GRANT EXECUTE ON dbo.usp_GetOrders TO AppUser;
GRANT SELECT, INSERT, UPDATE ON dbo.Orders TO ETLUser;
GRANT VIEW DEFINITION ON dbo.vw_Summary TO ReportUser;

-- DENY: Bloqueio explícito (sobrescreve GRANTS inclusive de roles herdadas)
DENY SELECT ON dbo.CustomerPayments TO ReportUser;
DENY DELETE ON dbo.Orders TO ReportUser;

-- REVOKE: Remove um comando de GRANT ou DENY anterior
REVOKE SELECT ON dbo.Customers FROM ReportUser;
-- Importante: REVOKE não bloqueia acessos; apenas limpa regras.
-- Se o usuário continuar possuindo acesso via Role, ele ainda poderá consultar.

-- Permissões a nível de Schema completo
GRANT SELECT ON SCHEMA::Reports TO ReportUser;
GRANT EXECUTE ON SCHEMA::dbo TO AppUser;

-- Consultar permissões ativas
SELECT * FROM fn_my_permissions('dbo.Orders', 'OBJECT');
SELECT * FROM sys.database_permissions WHERE grantee_principal_id = USER_ID('ReportUser');
```

> [!warning] Erro Comum
> REVOKE não é o mesmo que DENY. O `REVOKE` desfaz uma regra (devolvendo a decisão de acesso às regras herdadas das Roles). O `DENY` bloqueia explicitamente no nível mais alto de precedência. Para barrar acessos com segurança absoluta, use `DENY`.

> [!note] Modelo Mental — GRANT / DENY / REVOKE
> Pense nisso como a **portaria de um prédio**. O `GRANT` é o crachá de liberação de entrada. O `DENY` é a lista de banidos da portaria — mesmo que você tenha crachá ou esteja acompanhado por um amigo (Role), o banimento overrules e você não entra. O `REVOKE` é apenas o ato de recolher o crachá de alguém (ou apagá-lo da lista de banimento) — ele não cria novas proibições. O único comando que barra ativamente é o `DENY`. A única forma de anular um `DENY` é dar um `REVOKE` especificamente daquele DENY.

---

## Acesso Sem Senha com Identidade Gerenciada (Managed Identity)

O uso de **Managed Identity** elimina o armazenamento de senhas e credenciais em arquivos locais de código, substituindo por tokens seguros do Azure Active Directory (Entra ID).

### Tipos de Managed Identity

| Tipo | Ciclo de Vida | Casos de Uso comuns |
| :--- | :--- | :--- |
| **System-assigned** | Vinculado exclusivamente ao recurso do Azure | Autenticação dedicada para um único serviço. |
| **User-assigned** | Recurso Azure independente e compartilhado | `Múltiplos microsserviços dividindo a mesma identidade lógica`. |

> [!tip] Identidades Gerenciadas no Azure: System-Assigned vs User-Assigned
>
> - **System-assigned (Atribuída pelo sistema)**: Criada e vinculada diretamente a um recurso específico do Azure (ex: uma VM ou App Service). Se o recurso for excluído, a identidade é deletada automaticamente.
> - **User-assigned (Atribuída pelo usuário)**: Criada como um recurso Azure independente. Pode ser associada a múltiplos recursos compartilhando o mesmo escopo de permissões lógicas de banco.

### Mapeando Managed Identity no Azure SQL

```sql
-- Criar usuário para a identidade gerenciada do App Service
CREATE USER [my-app-service] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [my-app-service];
GRANT EXECUTE ON SCHEMA::dbo TO [my-app-service];
```

```csharp
// String de conexão de aplicação (sem necessidade de senhas ou chaves)
var connectionString = "Server=myserver.database.windows.net;Database=mydb;Authentication=Active Directory Managed Identity;";
```

### Métodos de Autenticação Entra ID (Azure AD)

| Método | Casos de Uso |
| :--- | :--- |
| `Active Directory Integrated` | Máquinas no domínio corporativo com SSO. |
| `Active Directory Interactive` | Contas de usuários que exigem autenticação MFA. |
| `Active Directory Managed Identity` | Aplicações e serviços hospedados na nuvem Azure. |
| `Active Directory Service Principal` | Integrações com aplicativos externos (Client ID + Secrets). |
| `Active Directory Default` | Tenta múltiplos métodos de forma sequencial automatizada. |

---

## Princípio do Menor Privilégio (Least Privilege)

```sql
-- INADEQUADO: Dar permissão de db_owner para aplicações
ALTER ROLE db_owner ADD MEMBER AppUser; -- Nunca execute isso em produção

-- RECOMENDÁVEL: Conceder apenas os privilégios estritamente necessários
GRANT SELECT ON dbo.Products TO AppUser;
GRANT EXECUTE ON dbo.usp_PlaceOrder TO AppUser;
GRANT INSERT ON dbo.OrderItems TO AppUser;
```

---

## Contained Database Users (Usuários de Banco Contidos)

Um **contained database user** possui dados cadastrais salvos no próprio banco de dados, dispensando a presença de um login mapeado a nível do master no servidor SQL.

**Vantagens:**

- **Portabilidade**: O usuário e suas permissões migram junto com o banco de dados em backups, restores ou failovers, evitando "logins órfãos".
- **Azure SQL**: É o padrão recomendado pelo Azure, facilitando a portabilidade em bancos elétricos (Elastic Pools).
- **Facilidade**: Permite provisionar acessos sem necessidade de tocar no master.

```sql
-- Ativar autenticação contida (SQL Server local)
EXEC sp_configure 'contained database authentication', 1;
RECONFIGURE;

ALTER DATABASE MyDatabase SET CONTAINMENT = PARTIAL;

-- Criar usuário contido sem necessidade de LOGIN no servidor master
USE MyDatabase;
CREATE USER AppUser WITH PASSWORD = 'SecureP@ssword1!';
ALTER ROLE db_datareader ADD MEMBER AppUser;

-- No Azure SQL Database (Entra ID usa contidos por padrão)
CREATE USER [user@domain.com] FROM EXTERNAL PROVIDER;
```

---

## Contexto de Execução com EXECUTE AS

O comando `EXECUTE AS` permite personificar temporariamente outro usuário do banco de dados para fins de validação de segurança ou elevação de privilégios.

### Escopos do EXECUTE AS

| Contexto | Escopo | Descrição |
| :--- | :--- | :--- |
| `EXECUTE AS USER` | Banco de Dados | Personificar um usuário específico do banco. |
| `EXECUTE AS LOGIN` | Servidor | Personificar uma conta de login do servidor. |
| `EXECUTE AS CALLER` | Módulo | Executa sob a identidade do chamador (padrão). |
| `EXECUTE AS OWNER` | Módulo | `Executa sob o contexto do dono do objeto`. |
| `EXECUTE AS SELF` | Módulo | Executa sob o contexto de quem definiu o objeto. |

A instrução `REVERT` encerra o escopo de personificação retornando ao login original.

```sql
-- Personificar usuário para testar restrições
EXECUTE AS USER = 'ReportingUser';
SELECT * FROM SensitiveView; -- Executa como se fosse o ReportingUser
REVERT; -- Retorna ao login administrador

-- Stored Procedure rodando com privilégios de OWNER
CREATE PROCEDURE dbo.sp_SensitiveReport
WITH EXECUTE AS OWNER
AS SELECT * FROM dbo.SalaryData;

-- Verificar o usuário atual e login original da sessão
SELECT ORIGINAL_LOGIN(), SUSER_SNAME(), USER_NAME();
```

---

## Cadeia de Propriedade (Ownership Chaining)

O **ownership chaining** é um mecanismo do SQL Server que pula a validação de permissões intermediárias de leitura caso dois objetos relacionados compartilhem do mesmo dono (Owner).

- **Cadeia ativa (Mesmo dono)**: Se uma stored procedure e a tabela consultada por ela pertencerem ao mesmo dono (ex: ambos sob `dbo`), o SQL Server não valida se o usuário possui grant `SELECT` na tabela base ao rodar a procedure. Basta ter permissão `EXECUTE` na stored procedure.
- **Cadeia quebrada (Donos distintos)**: Se a procedure pertence a um dono e a tabela pertence a outro (ex: schemas diferentes pertencentes a donos distintos), o SQL Server bloqueia e exige que o usuário final possua grants explícitos de `SELECT` na tabela base.

```sql
-- Mesmo Dono: Cadeia Ativa (Funciona)
-- O usuário RestrictedUser só precisa de GRANT EXECUTE na procedure
CREATE PROCEDURE dbo.sp_GetOrders AS SELECT * FROM dbo.Orders;
GRANT EXECUTE ON dbo.sp_GetOrders TO RestrictedUser;

-- Donos Diferentes: Cadeia Quebrada (Falhará sem SELECT na tabela)
CREATE PROCEDURE dbo.sp_GetHRData AS SELECT * FROM hr.Employees;
-- Exigirá GRANT EXECUTE na proc AND GRANT SELECT na tabela hr.Employees
```

> [!warning] O que quebra a Cadeia de Propriedade (Ownership Chain)?
>
> - A cadeia de propriedade é mantida quando objetos adjacentes (ex: Stored Procedure chamando uma Tabela) possuem o mesmo dono (ex: ambos pertencem a `dbo`). Nesses casos, o usuário precisa apenas de permissão de `EXECUTE` na procedure.
> - Se a stored procedure for de outro dono (ex: pertencente a `usr_proc`) e tentar acessar tabelas do `dbo`, a cadeia é quebrada. O usuário final precisará de privilégios de `SELECT` diretamente nas tabelas base, o que viola o princípio do menor privilégio. Resolva usando `WITH EXECUTE AS OWNER`.

---

## Quadro de Roles de Banco vs Servidor

| Role | Escopo | Privilégios |
| :--- | :--- | :--- |
| `db_owner` | Banco de Dados | `Controle absoluto e total do banco de dados`. |
| `db_datareader` | Banco de Dados | Permissão `SELECT` em qualquer tabela/view do banco. |
| `db_datawriter` | Banco de Dados | `INSERT`/`UPDATE`/`DELETE` em qualquer tabela. |
| `db_ddladmin` | Banco de Dados | Criar, alterar ou dropar objetos (DDL). |
| `db_securityadmin` | Banco de Dados | Gerenciar roles e concessões de permissões. |
| `public` | Banco de Dados | Permissões básicas herdadas por todo usuário do banco. |
| `sysadmin` | Servidor | Controle absoluto e administrativo do servidor SQL. |
| `securityadmin` | Servidor | Gerenciar logins do servidor. |

---

## Melhores Práticas (Best Practices)

- Implemente **Managed Identities** no lugar de SQL logins clássicos para autenticar serviços Azure sem precisar gerenciar chaves e credenciais em arquivos.
- Dê preferência a **contained database users** no Azure SQL Database para evitar problemas de logins órfãos em migrações e backups.
- Utilize a cláusula `WITH EXECUTE AS OWNER` em Stored Procedures que realizem acessos cruzados em schemas de proprietários distintos, mantendo o princípio de menor privilégio.
- Evite adicionar usuários em roles administrativas como `db_owner` ou `sysadmin` sem necessidade explícita.
- Varra periodicamente permissões ativas mapeando roles de usuários via views do sistema (`sys.database_role_members`).

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - O `DENY` tem prioridade e precedência absoluta sobre concessões `GRANT`.
> - A sintaxe para registrar Managed Identity é `CREATE USER [nome] FROM EXTERNAL PROVIDER`.
> - A função de sistema `fn_my_permissions` lista os privilégios reais ativos do usuário chamador.
> - A cadeia de propriedade (ownership chain) exige que os objetos compartilhados possuam **estritamente o mesmo dono (Owner)** para pular checagens lógicas.
> - Contained database users exigem a flag `SET CONTAINMENT = PARTIAL` em servidores on-premises.

---

## Resumo dos Conceitos (Key Takeaways)

- O modelo de segurança do SQL Server baseia-se em GRANT, DENY e REVOKE.
- Managed Identities fornecem autenticação passwordless robusta integrada ao Azure AD / Entra ID.
- Ownership chaining facilita a delegação de leituras omitindo grants diretos em tabelas.
- O `EXECUTE AS` habilita personificações controladas para testes e elevações lógicas de privilégios.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma Stored Procedure criada no schema `dbo` executa consultas a uma tabela pertencente ao schema `hr_schema` (com donos distintos). Um usuário restrito do banco possui permissão `EXECUTE` na stored procedure, mas não tem acesso direto à tabela de RH. O que ocorrerá quando ele tentar rodar a procedure?

A. A procedure executará com sucesso por conta do ownership chaining automático.

B. A procedure falhará porque o ownership chaining não funciona entre schemas distintos.

C. A procedure falhará porque a cadeia de propriedade é quebrada por possuírem donos distintos.

D. A procedure executará se o usuário possuir a role `db_datareader`.

> [!success]- Resposta
> **C — A procedure falhará porque a cadeia de propriedade é quebrada por possuírem donos distintos**
>
> O ownership chaining pula a verificação de permissões nas tabelas base apenas quando todos os objetos adjacentes compartilham o mesmo dono (Owner). Como a procedure e a tabela base possuem proprietários diferentes, a cadeia é quebrada e o SQL Server exige que o usuário final possua privilégios explícitos de leitura na tabela de RH. Para corrigir sem conceder broad grants na tabela, o desenvolvedor deve configurar a procedure com `WITH EXECUTE AS OWNER`.

---

## Tópicos Relacionados

- [04-Auditoria](./04-auditing.md)
- [05-Endpoints de Rede Protegidos](./05-secure-endpoints.md) *(Inglês apenas)*
- [03-Endpoints de Servidores MCP](../04-ai-assisted-tools/03-mcp-server-endpoints.md)

---

## Documentação Oficial

- [Permissions (Database Engine)](https://learn.microsoft.com/en-us/sql/relational-databases/security/permissions-database-engine)
- [Azure AD Authentication for Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview)
- [Managed Identity for Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity)
- [Contained Database Users](https://learn.microsoft.com/en-us/sql/relational-databases/security/contained-database-users-making-your-database-portable)
- [EXECUTE AS (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/execute-as-transact-sql)
- [Ownership Chaining](https://learn.microsoft.com/en-us/sql/relational-databases/security/ownership-and-user-schema-separation)

---

**[← Anterior](./02-dynamic-data-masking-rls.md) | [↑ Voltar para a Seção](./data-security-compliance.md) | [Próximo →](./04-auditing.md)**
