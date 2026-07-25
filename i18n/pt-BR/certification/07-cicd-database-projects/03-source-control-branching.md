---
title: Controle de Versão e Estratégias de Branching para Bancos de Dados (Source Control and Branching for Database Projects)
type: study-material
tags:
  - dp-800
  - git
  - branching
  - pull-requests
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Estrutura do Repositório Git para Projetos SQL](#estrutura-do-repositório-git-para-projetos-sql)
>   - 🔹 [Organização de Pastas Recomendada](#organização-de-pastas-recomendada)
>   - 🔹 [Arquivo .gitignore para Projetos de Banco de Dados](#arquivo-gitignore-para-projetos-de-banco-de-dados)
>   - 🔹 [Integração de Controle de Versão locais](#integração-de-controle-de-versão-locais)
> - 📍 [3. Estratégias de Branching](#estratégias-de-branching)
>   - 🔹 [Fluxo Git Flow (Padrão corporativo tradicional)](#fluxo-git-flow-padrão-corporativo-tradicional)
>   - 🔹 [Desenvolvimento Baseado no Tronco (Trunk-Based Development)](#desenvolvimento-baseado-no-tronco-trunk-based-development)
> - 📍 [4. Pull Requests para Alterações de Schema](#pull-requests-para-alterações-de-schema)
>   - 🔹 [Políticas de Branch (Branch Policies no Azure DevOps)](#políticas-de-branch-branch-policies-no-azure-devops)
>   - 🔹 [Revisores Obrigatórios por Caminho](#revisores-obrigatórios-por-caminho)
>   - 🔹 [O que validar em Revisões de Código (PR) de Banco de Dados](#o-que-validar-em-revisões-de-código-pr-de-banco-de-dados)
> - 📍 [5. Resolução de Conflitos em Arquivos SQL](#resolução-de-conflitos-em-arquivos-sql)
>   - 🔹 [Conflito de Merge de DDL em Tabela](#conflito-de-merge-de-ddl-em-tabela)
>   - 🔹 [Dicas para Minimizar Conflitos de Merge:](#dicas-para-minimizar-conflitos-de-merge)
> - 📍 [6. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [7. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [8. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [9. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [10. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [11. Documentação Oficial](#documentação-oficial)
---

# Controle de Versão e Estratégias de Branching para Bancos de Dados (Source Control and Branching for Database Projects)

## Visão Geral (Overview)

Armazenar projetos de banco de dados SQL em repositórios Git viabiliza o trabalho colaborativo, histórico de alterações estruturadas e revisões lógicas de schemas. As estratégias de branching organizam o fluxo de atualizações do ambiente de desenvolvimento local até a implantação em produção, e políticas de branches (branch policies) garantem revisões obrigatórias antes da mesclagem (merge).

> [!abstract]
>
> - Cobre controle de versão baseado em Git para arquivos `.sql`, estratégias de ramificação (branching) e tratamento de conflitos de merge.
> - Arquivos de código de banco de dados (`.sql`) são gerenciados no repositório com o mesmo fluxo adotado para códigos de aplicações.
> - Tópicos chave do exame: ciclo de branches de features, revisões baseadas em Pull Requests (PRs) e resolução de conflitos de versionamento.

> [!tip] O que o Exame Testa
>
> - Alterações de schema seguem o padrão clássico: Feature branch → Pull Request → Merge para a branch principal (`main`) → Implantação.
> - Conflitos de mesclagem em códigos `.sql` de tabelas e stored procedures devem ser resolvidos de forma manual — o Git não possui entendimento semântico de sintaxes T-SQL para auto-resolução.
> - O arquivo `.sqlproj` legado podia apresentar conflitos complexos; o formato moderno SDK-Style mitiga isso.

---

## Estrutura do Repositório Git para Projetos SQL

### Organização de Pastas Recomendada

```text
repo-root/
├── src/
│   └── MyDatabase/
│       ├── MyDatabase.sqlproj
│       ├── Schema/
│       │   ├── Tables/
│       │   ├── Views/
│       │   └── StoredProcedures/
│       └── Scripts/
│           ├── PreDeployment/
│           └── PostDeployment/
├── tests/
│   └── MyDatabase.Tests/
│       └── ... (Testes unitários tSQLt ou projetos separados)
├── pipelines/
│   ├── build.yml
│   └── deploy.yml
├── .gitignore
└── README.md
```

### Arquivo .gitignore para Projetos de Banco de Dados

```gitignore
# Diretórios de compilação locais do dotnet/MSBuild
bin/
obj/

# Pastas ocultas do Visual Studio
.vs/
*.user
*.suo

# Arquivos temporários de conexões do SSDT
*.publish.xml

# Arquivos de conexões com dados de segredos locais (Evite Commits de senhas!)
*.pubxml
localSettings.json
```

### Integração de Controle de Versão locais

```bash
# Inicializar um repositório Git local
git init
git remote add origin https://dev.azure.com/myorg/myproject/_git/my-database

# Clonar repositório existente
git clone https://dev.azure.com/myorg/myproject/_git/my-database
```

As extensões de SQL Database Projects no VS Code oferecem:

- Comparação gráfica de schema entre a base local de testes e o projeto.
- Atualização do projeto a partir do banco ("Update Project from Database") com um clique.
- Painel de Git integrado para stage, commit e push de DDLs.

---

## Estratégias de Branching

### Fluxo Git Flow (Padrão corporativo tradicional)

```text
main          ●────────────────────────────────────────●──→ (Produção)
               \                                      /
release/1.2     ●──────────────────────────────────●
                 \                                /
feature/add-idx   ●──────────────────────────●
                                                 \
hotfix/fix-sproc                               ●──→ (Cherry-pick para main)
```

**Funções das Branches no Ciclo de Banco:**

| Branch | Objetivo | Ambiente Alvo |
| :--- | :--- | :--- |
| `main` | `Código homologado pronto para produção`. | Produção. |
| `release/x.y` | Estabilização de versão e testes finais de homologação. | Staging / Homologação (UAT). |
| `feature/*` | Desenvolvimento de novas tabelas, colunas ou alteração de procs. | Bancos locais e Dev. |
| `hotfix/*` | Correção urgente de erros produtivos (bugs). | Produção (Via main). |

> [!important] Estratégia de Branching para Bancos de Dados
>
> - Bancos de dados exigem controle estrito no fluxo de branches de Git devido ao estado persistente dos dados.
> - **Cuidado de Exame**: A branch `main` deve representar o estado desejado aprovado para produção. Aplique políticas de Pull Request, validação de build e aprovações obrigatórias; trate desvios do ambiente produtivo como drift a ser investigado.

### Desenvolvimento Baseado no Tronco (Trunk-Based Development)

- Uso de branches de feature de vida muito curta (1 a 3 dias).
- Mesclagem frequente com a `main` por meio de Pull Requests.
- A branch `main` é mantida sempre em estado implantável.
- Recursos incompletos ou em testes são isolados via Feature Flags ou scripts desligados.

---

## Pull Requests para Alterações de Schema

O uso de Pull Requests estabelece barreiras de qualidade (quality gates) antes da mesclagem final de novas DDLs de tabelas no banco principal.

### Políticas de Branch (Branch Policies no Azure DevOps)

As regras de políticas configuradas na branch `main` impedem a alteração sem validação prévia:

- Exigência de aprovação por um número mínimo de revisores (ex: mínimo 2 engenheiros).
- Exigência de sucesso no build (a pipeline de CI deve compilar o `.sqlproj` gerando o dacpac sem erros).
- Vinculação obrigatória de itens de trabalho (Work Items / Tarefas).
- Bloqueio de commits diretos sem PR.

### Revisores Obrigatórios por Caminho

No GitHub, o arquivo `CODEOWNERS` associa caminhos a proprietários de código. No Azure DevOps, o equivalente para exigir revisão é a política **Automatically included reviewers**, configurada como obrigatória e com filtros de caminho:

```text
# Exemplo conceitual de política de revisores obrigatórios no Azure DevOps
# Branch: main
# Filtro: *.sql                    → grupo dba-team (Required)
# Filtro: /src/MyDatabase/Schema/Security/* → grupo security-team (Required)
# Filtro: /src/MyDatabase/Scripts/*          → grupo senior-dba-team (Required)
```

> [!tip] Revisão por Caminho
>
> - No Azure DevOps, configure **Automatically included reviewers** como **Required** e aplique filtros de caminho para impor a aprovação de grupos específicos.
> - Em repositórios GitHub, `CODEOWNERS` pode indicar os proprietários por caminho, mas a exigência de aprovação depende também das regras de proteção da branch.

### O que validar em Revisões de Código (PR) de Banco de Dados

```sql
-- Exemplo de alteração perigosa em produção:
-- Inserir coluna NOT NULL em tabela gigante sem default causará falha de deploy

-- Evite adicionar NOT NULL sem um plano de migração em tabelas já populadas:
-- a implantação pode falhar porque as linhas existentes não recebem valor.
ALTER TABLE dbo.Orders ADD AuditUser NVARCHAR(50) NOT NULL;

-- Prefira uma migração em etapas para controlar impacto e validação:
ALTER TABLE dbo.Orders ADD AuditUser NVARCHAR(50) NULL;
UPDATE dbo.Orders SET AuditUser = 'system' WHERE AuditUser IS NULL;
ALTER TABLE dbo.Orders ALTER COLUMN AuditUser NVARCHAR(50) NOT NULL;
```

---

## Resolução de Conflitos em Arquivos SQL

Os conflitos ocorrem quando desenvolvedores alteram o mesmo arquivo ou definem objetos com modificações conflitantes em branches separadas.

### Conflito de Merge de DDL em Tabela

```sql
<<<<<<< HEAD
-- Versão ativa na branch main
CREATE TABLE [dbo].[Orders]
(
    [OrderId]    INT NOT NULL IDENTITY(1,1),
    [CustomerId] INT NOT NULL,
    [Status]     NVARCHAR(20) NOT NULL DEFAULT 'Pending',
    CONSTRAINT [PK_Orders] PRIMARY KEY ([OrderId])
);
=======
-- Versão vinda da branch feature/add-priority
CREATE TABLE [dbo].[Orders]
(
    [OrderId]    INT NOT NULL IDENTITY(1,1),
    [CustomerId] INT NOT NULL,
    [Status]     NVARCHAR(20) NOT NULL DEFAULT 'Pending',
    [Priority]   INT NOT NULL DEFAULT 0,              -- Nova coluna adicionada
    CONSTRAINT [PK_Orders] PRIMARY KEY ([OrderId])
);
>>>>>>> feature/add-priority
```

**Resolução correta (Manter ambas as estruturas adequadas):**

```sql
CREATE TABLE [dbo].[Orders]
(
    [OrderId]    INT NOT NULL IDENTITY(1,1),
    [CustomerId] INT NOT NULL,
    [Status]     NVARCHAR(20) NOT NULL DEFAULT 'Pending',
    [Priority]   INT NOT NULL DEFAULT 0,
    CONSTRAINT [PK_Orders] PRIMARY KEY ([OrderId])
);
```

### Dicas para Minimizar Conflitos de Merge:

- **Mantenha um único objeto por arquivo**: Ter cada tabela em seu próprio arquivo `.sql` reduz drasticamente a chance de colisões de commits de desenvolvedores distintos.
- **Pull Requests menores e focados**: Evite PRs gigantescos que alteram dezenas de tabelas simultaneamente.
- **Utilize Schema Compare local**: Valide localmente se a mesclagem da branch no repositório gerará a estrutura idêntica na base de testes locais.

> [!warning] O que Mitiga Conflitos no Arquivo .sqlproj?
>
> - No SSDT clássico (legado), o arquivo `.sqlproj` continha referências rígidas de cada arquivo `.sql` do projeto. Mesclar branches causava conflitos frequentes nesse XML.
> - **Resolução Moderna**: O formato **SDK-Style** (moderno) elimina a necessidade de listar os arquivos físicos no `.sqlproj`. A compilação localiza qualquer arquivo no diretório automaticamente, reduzindo conflitos de merges a alterações simultâneas no mesmo objeto físico.

---

## Problemas Comuns e Soluções (Common Issues)

| Sintoma | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Conflitos frequentes no XML do `.sqlproj` | Projeto legado com referências estáticas | Converta o projeto para o formato SDK-Style moderno. |
| Commits acidentais contendo senhas e chaves | Falta de regras no `.gitignore` | Adicione os formatos `.pubxml` e arquivos locais de settings no `.gitignore`. |
| Modificações não testadas aplicadas na main | Ausência de políticas de branch | Ative branch protection rules no Azure DevOps ou GitHub para bloquear pushes diretos. |
| Falhas de sintaxe SQL compiladas em produção | PRs integrados sem testes de build | Adicione um passo de compilação automatizado (`dotnet build`) na pipeline de pull requests. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - A política de branch (**Branch Policy**) no Azure DevOps protege a branch `main`, exigindo aprovação de revisão e validação de compilação da pipeline.
> - O arquivo **`CODEOWNERS`** automatiza a atribuição de revisores baseado em caminhos físicos (como exigir aprovação de DBAs para a pasta de DDLs).
> - As alterações de DDLs no repositório devem seguir a premissa de um único objeto físico por arquivo `.sql`.
> - Commits em andamento devem ter suas pipelines validadas através do comando `dotnet build` do dacpac para identificar erros de compilação de chaves.

---

## Resumo dos Conceitos (Key Takeaways)

- Bancos de dados requerem o mesmo fluxo de qualidade adotado em aplicações (branches, PRs e revisões).
- A branch `main` representa o estado final espelhado da infraestrutura de produção.
- No Azure DevOps, use revisores obrigatórios com filtros de caminho para exigir especialistas de banco (DBAs) em alterações estruturais.
- O formato de projetos SDK-style simplifica mesclagens eliminando mapeamentos de arquivos XML.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Você está configurando políticas no Azure DevOps para o repositório Git de um projeto de banco de dados. A empresa exige que qualquer alteração de DDL estrutural de tabelas receba aprovação de um time corporativo de administradores de banco (DBAs), e alterações em schemas de segurança exijam aprovação do time de SecOps. Como automatizar essa governança com o menor esforço administrativo?

A. Criar scripts de validação de PRs personalizados em Bash na pipeline do Azure DevOps.

B. Configurar a política **Automatically included reviewers** como obrigatória, com filtros de caminho para DDLs e schemas de segurança direcionados aos respectivos times.

C. Forçar o uso de um único desenvolvedor com privilégios de mesclagem na branch principal.

D. Utilizar triggers de banco (DDL Triggers) para bloquear atualizações.

> [!success]- Resposta
> **B — Configurar a política Automatically included reviewers como obrigatória, com filtros de caminho**
>
> A política de revisores incluídos automaticamente do Azure DevOps pode usar filtros de caminho e exigir a aprovação de indivíduos ou grupos. Assim, mudanças em DDLs e em schemas de segurança só podem ser concluídas após a aprovação dos times responsáveis.

---

## Tópicos Relacionados

- [02-Projetos de Banco de Dados SQL](./02-sql-database-projects.md)
- [04-Pipelines de Implantação](./04-deployment-pipelines.md) *(Inglês apenas)*
- [01-Estratégias de Testes](./01-testing-strategy.md)

---

## Documentação Oficial

- [SQL Projects Source Control](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-projects-overview)
- [Azure DevOps Branch Policies](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies)
- [GitHub CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)

---

**[← Anterior](./02-sql-database-projects.md) | [↑ Voltar para a Seção](./cicd-database-projects.md) | [Próximo →](./04-deployment-pipelines.md)**
