---
title: Pipelines de Implantação para Projetos de Banco de Dados (Deployment Pipelines for Database Projects)
type: study-material
tags:
  - dp-800
  - deployment
  - schema-drift
  - secrets-management
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Arquitetura de Pipelines de Banco de Dados](#arquitetura-de-pipelines-de-banco-de-dados)
> - 📍 [3. Pipeline de Build (CI) - Compilação e Testes](#pipeline-de-build-ci---compilação-e-testes)
> - 📍 [4. Rastreamento de Desvios (Schema Drift)](#rastreamento-de-desvios-schema-drift)
>   - 🔹 [Validação Manual Prévia Gerando Scripts T-SQL](#validação-manual-prévia-gerando-scripts-t-sql)
> - 📍 [5. Gestão Segura de Credenciais com Azure Key Vault](#gestão-segura-de-credenciais-com-azure-key-vault)
>   - 🔹 [Mapeando Segredos do Key Vault em Pipelines](#mapeando-segredos-do-key-vault-em-pipelines)
> - 📍 [6. Controle de Fluxo e Lançamentos (CD)](#controle-de-fluxo-e-lançamentos-cd)
>   - 🔹 [Ambientes de Aprovação Manual (Approval Gates)](#ambientes-de-aprovação-manual-approval-gates)
>   - 🔹 [Parametrizações do SqlPackage por Ambiente](#parametrizações-do-sqlpackage-por-ambiente)
> - 📍 [7. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [8. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [9. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [10. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [11. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [12. Documentação Oficial](#documentação-oficial)
---

# Pipelines de Implantação para Projetos de Banco de Dados (Deployment Pipelines for Database Projects)

## Visão Geral (Overview)

Pipelines de CI/CD automatizam o build, validação, execução de testes unitários e o deploy seguro de projetos de banco de dados SQL. Aspectos críticos a considerar incluem: detecção de desvios lógicos estruturais (schema drift) entre o repositório Git e as bases produtivas, gerenciamento de chaves e strings de conexão confidenciais via Azure Key Vault e o controle de lançamentos por meio de aprovações obrigatórias (approval gates).

> [!abstract]
>
> - Cobre a montagem de pipelines de CI/CD para projetos de banco: etapas de build, testes e deploy no GitHub Actions ou Azure Pipelines.
> - A implantação automatizada emprega o utilitário SqlPackage.exe aplicando perfis de publicação específicos (.publish.xml) por ambiente.
> - Tópicos chave do exame: comandos executores do SqlPackage, arquivos publish.xml e ordenação ideal de etapas na pipeline.

> [!tip] O que o Exame Testa
>
> - O utilitário **`SqlPackage.exe /Action:Publish`** publica um dacpac no banco; `/Action:Extract` extrai a DDL do banco em dacpac; `/Action:Export` exporta schema+dados em bacpac.
> - O arquivo **Publish Profile** (`.publish.xml`) armazena parametrizações de variáveis de deploy e segurança específicas do ambiente, impedindo commits de dados sigilosos no YAML da pipeline.
> - Ordem padrão de execução na pipeline: Compilar o dacpac (Build) → Rodar testes unitários (tSQLt) → Implantar em homologação (Staging) → Aguardar aprovação humana → Implantar em Produção.

---

## Arquitetura de Pipelines de Banco de Dados

```text
Commit de código na branch de feature
          │
          ▼
┌─────────────────────────────────┐
│     Pipeline de Build (CI)      │  ← Dispara no Pull Request
│  - dotnet build (dacpac)        │
│  - Executa testes do tSQLt      │
│  - Publica o artefato dacpac    │
└─────────┬───────────────────────┘
          │ Artefato: MyDatabase.dacpac
          ▼
┌─────────────────────────────────┐
│       Deploy em Dev (CD)        │  ← Deploy automático após Merge
│  - sqlpackage /Action:Publish   │
│  - Testes básicos pós-deploy    │
└─────────┬───────────────────────┘
          │ Aguarda aprovação (Approval Gate)
          ▼
┌─────────────────────────────────┐
│     Deploy em Staging (CD)      │  ← Aprovação manual
│  - Detecção de Schema Drift     │
│  - sqlpackage /Action:Publish   │
└─────────┬───────────────────────┘
          │ Janela de mudança + aprovação DBA
          ▼
┌─────────────────────────────────┐
│    Deploy em Produção (CD)      │  ← Aprovação estrita
│  - sqlpackage com transações quando possível │
└─────────────────────────────────┘
```

---

## Pipeline de Build (CI) - Compilação e Testes

```yaml
# pipelines/ci.yml (YAML para Azure DevOps)
trigger:
  branches:
    include:
      - main
      - feature/*
  paths:
    include:
      - src/MyDatabase/**

pool:
  vmImage: 'ubuntu-latest'

variables:
  buildConfiguration: 'Release'

steps:
  - task: UseDotNet@2
    displayName: 'Instalar .NET SDK'
    inputs:
      version: '8.x'

  - script: dotnet build src/MyDatabase/MyDatabase.sqlproj --configuration $(buildConfiguration)
    displayName: 'Compilar Projeto SQL'

  - task: SqlAzureDacpacDeployment@1
    displayName: 'Implantar base temporária de testes em Dev'
    inputs:
      azureSubscription: 'MyServiceConnection'
      AuthenticationType: 'servicePrincipal'
      ServerName: '$(DEV_SERVER)'
      DatabaseName: '$(DEV_DATABASE)'
      deployType: 'DacpacTask'
      DeploymentAction: 'Publish'
      DacpacFile: 'src/MyDatabase/bin/Release/MyDatabase.dacpac'
      AdditionalArguments: '/p:BlockOnPossibleDataLoss=true'

  - script: |
      sqlcmd -S $(DEV_SERVER) -d $(DEV_DATABASE) \
        -Q "EXEC tSQLt.RunAll;" \
        --authentication-method ActiveDirectoryDefault
    displayName: 'Executar testes unitários do tSQLt'

  - task: PublishBuildArtifacts@1
    displayName: 'Publicar artefato DACPAC compilado'
    inputs:
      PathtoPublish: 'src/MyDatabase/bin/Release/MyDatabase.dacpac'
      ArtifactName: 'dacpac'
```

---

## Rastreamento de Desvios (Schema Drift)

O **Schema Drift** ocorre se o banco de dados ativo sofrer modificações físicas manuais por fora das esteiras formais de CI/CD (ex: um hotfix emergencial de index criado via SSMS direto em produção). Rastrear e alertar desvios antes do deploy impede sobrescritas de dados indesejados.

```yaml
# Etapa do pipeline executada antes do deploy:
  - script: |
      # 1. Extrair o schema físico atual de produção para um dacpac temporário
      sqlpackage /Action:Extract \
        /TargetFile:$(Agent.TempDirectory)/current.dacpac \
        /SourceConnectionString:"Server=$(TARGET_SERVER);Database=$(TARGET_DB);Authentication=Active Directory Default"

      # 2. Computar a diferença gerando o DeployReport
      sqlpackage /Action:DeployReport \
        /SourceFile:$(Pipeline.Workspace)/dacpac/MyDatabase.dacpac \
        /TargetFile:$(Agent.TempDirectory)/current.dacpac \
        /OutputPath:$(Agent.TempDirectory)/drift-report.xml

      # 3. Chamar script local para analisar o XML; falhar a pipeline se houver desvios
      python3 check-drift.py $(Agent.TempDirectory)/drift-report.xml
    displayName: 'Detectar Schema Drift'
```

```python
# check-drift.py — Script auxiliar de parsing do relatório
import sys
import xml.etree.ElementTree as ET

report_path = sys.argv[1]
tree = ET.parse(report_path)
root = tree.getroot()

operations = root.findall('.//{http://schemas.microsoft.com/sqlserver/dac/DeployReport/2012/02}Operation')

if operations:
    print(f"ATENÇÃO: Detectado {len(operations)} alteração(ões) manual(ais) (Drift):")
    for op in operations:
        print(f"  - {op.get('Name')}: {op.text}")
    sys.exit(1) # Aborta o pipeline
else:
    print("Zero desvios (drift) detectados.")
    sys.exit(0)
```

> [!important] Rastreamento de Desvios (Schema Drift) na Pipeline
>
> - **Schema Drift** ocorre quando mudanças estruturais são efetuadas diretamente no banco de dados de produção (ex: hotfix manual via SSMS), desregulando-o frente ao código do repositório Git.
> - **Como Detectar**: Antes do deploy, a pipeline executa o `sqlpackage /Action:DeployReport` comparando a dacpac do repositório contra uma extração temporária do banco produtivo. Se houver desvios, a pipeline aborta para que a equipe revise a alteração manual e evite sobrescrever dados acidentais.

### Validação Manual Prévia Gerando Scripts T-SQL

```bash
# Gerar o script T-SQL de diferenças (Action:Script) sem alterar o banco de destino
# Permite à equipe validar o script final antes de aplicar de fato
sqlpackage /Action:Script \
    /SourceFile:bin/Release/MyDatabase.dacpac \
    /TargetConnectionString:"Server=prod.database.windows.net;Database=MyDB;Authentication=Active Directory Default" \
    /OutputPath:./planned-changes.sql
```

---

## Gestão Segura de Credenciais com Azure Key Vault

Nunca registre dados de conexões ou senhas de banco em arquivos de código ou definições YAML expostas.

### Mapeando Segredos do Key Vault em Pipelines

```yaml
# Referenciar grupos de variáveis seguros vinculados ao Key Vault
variables:
  - group: 'MyDatabase-KeyVault' # Grupo configurado no Library do Azure DevOps

# Configuração lógica:
# 1. Biblioteca (Library) → Variable Groups → Ativar "Link secrets from an Azure key vault as variables".
# 2. Mapear as variáveis desejadas: sql-connection-string, etc.
# 3. O Azure DevOps recupera os valores de forma segura em runtime usando $(sql-connection-string).
```

```yaml
# Alternativa: Usar a task nativa AzureKeyVault
steps:
  - task: AzureKeyVault@2
    inputs:
      azureSubscription: 'MyServiceConnection'
      KeyVaultName: 'my-keyvault'
      SecretsFilter: 'sql-connection-string'
      RunAsPreJob: true

  - script: |
      sqlpackage /Action:Publish \
        /SourceFile:MyDatabase.dacpac \
        /TargetConnectionString:"$(sql-connection-string)"
    displayName: 'Publicar dacpac com credenciais seguras'
```

> [!tip] Segurança de Credenciais na Pipeline
>
> - **Nunca** grave strings de conexão com senhas diretamente no arquivo YAML da pipeline ou em arquivos XML do projeto.
> - **Prática Recomendada**: Mapeie segredos dinamicamente a partir de um **Azure Key Vault** por meio de Grupos de Variáveis vinculados ou da task `AzureKeyVault@2`. Prefira conexões de serviço com federação de identidade de carga de trabalho; para publicar em um banco existente, o SqlPackage requer `db_owner`, portanto limite essa identidade ao banco-alvo e à pipeline autorizada.

---

## Controle de Fluxo e Lançamentos (CD)

### Ambientes de Aprovação Manual (Approval Gates)

```yaml
stages:
  - stage: DeployStaging
    displayName: 'Implantar em Staging'
    dependsOn: BuildAndTest
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployToStaging
        environment: 'Staging' # O ambiente 'Staging' possui regras de aprovação manual no portal
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: dacpac
                - script: |
                    sqlpackage /Action:Publish \
                      /SourceFile:$(Pipeline.Workspace)/dacpac/MyDatabase.dacpac \
                      /TargetConnectionString:"$(staging-connection-string)" \
                      /p:BlockOnPossibleDataLoss=true
                  displayName: 'Deploy Staging'

  - stage: DeployProduction
    displayName: 'Implantar em Produção'
    dependsOn: DeployStaging
    jobs:
      - deployment: DeployToProduction
        environment: 'Production' # Exige aprovação e janela do time de DBAs
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: dacpac
                - script: |
                    sqlpackage /Action:Publish \
                      /SourceFile:$(Pipeline.Workspace)/dacpac/MyDatabase.dacpac \
                      /TargetConnectionString:"$(prod-connection-string)" \
                      /p:BlockOnPossibleDataLoss=true \
                      /p:IncludeTransactionalScripts=true
                  displayName: 'Deploy Produção'
```

### Parametrizações do SqlPackage por Ambiente

```bash
# Ambiente de Desenvolvimento (Dev): Permissivo para agilizar testes
sqlpackage /Action:Publish \
    /SourceFile:MyDatabase.dacpac \
    /TargetConnectionString:"$(dev-connection-string)" \
    /p:BlockOnPossibleDataLoss=false \
    /p:DropObjectsNotInSource=true

# Ambiente de Staging (Homologação): Moderado
sqlpackage /Action:Publish \
    /SourceFile:MyDatabase.dacpac \
    /TargetConnectionString:"$(staging-connection-string)" \
    /p:BlockOnPossibleDataLoss=true \
    /p:DropObjectsNotInSource=false

# Ambiente de Produção (Prod): Rígido e Seguro
sqlpackage /Action:Publish \
    /SourceFile:MyDatabase.dacpac \
    /TargetConnectionString:"$(prod-connection-string)" \
    /p:BlockOnPossibleDataLoss=true \
    /p:DropObjectsNotInSource=false \
    /p:IncludeTransactionalScripts=true
```

> [!warning] Dica de Exame: Parâmetros do SqlPackage por Ambiente
>
> - **Desenvolvimento (Dev)**: Costuma usar `/p:BlockOnPossibleDataLoss=false` e `/p:DropObjectsNotInSource=true` para agilizar testes locais limpando tabelas obsoletas.
> - **Produção (Prod)**: Exige rigor absoluto. Utilize `/p:BlockOnPossibleDataLoss=true` e `/p:DropObjectsNotInSource=false`. `/p:IncludeTransactionalScripts=true` solicita instruções transacionais quando possível, mas não substitui a revisão do script gerado nem garante uma única transação para todas as operações e scripts pré/pós-deploy.

---

## Problemas Comuns e Soluções (Common Issues)

| Sintoma | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Falha no deploy devido a alteração crítica de tipo | `BlockOnPossibleDataLoss` barrou a publicação | Crie um script de Pre-Deployment para migrar dados com segurança. |
| Erro de acesso negado no Azure Key Vault | A Service Connection não possui permissões no cofre | Em cofres com RBAC, atribua à conexão o papel `Key Vault Secrets User`; em cofres com políticas de acesso, conceda Get/List. |
| Alterações manuais sobrescritas pelo deploy | Falta de verificação de Schema Drift | Execute `sqlpackage /Action:DeployReport` antes de implantar. |
| Erro de autenticação de banco na pipeline | Conta sem privilégios administrativos no banco | Conceda o papel `db_owner` para o Service Principal correspondente no Azure SQL. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - O comando `sqlpackage` com a opção **`/Action:DeployReport`** gera o arquivo XML detalhando desvios de schemas.
> - Sempre proteja senhas vinculando as variáveis do pipeline a segredos do **Azure Key Vault**.
> - Configurar **`IncludeTransactionalScripts=true`** solicita transações onde houver suporte, mas não garante rollback integral de scripts pré/pós-deploy ou de todas as operações.
> - Lembre-se da ordem do ciclo: compilação física da dacpac (Build) → Testes (tSQLt) → Homologação (Staging) → Produção.

---

## Resumo dos Conceitos (Key Takeaways)

- Automatize a compilação do banco gerando artefatos compilados reutilizáveis.
- Valide modificações em ambientes isolados rodando testes unitários a cada Pull Request.
- Proteja bases produtivas barrando deploys se houver risco de perdas físicas de dados.
- Rastreie desvios lógicos no banco (drift) para impedir que atualizações manuais quebrem a automação da esteira.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Você está configurando o pipeline de deploy (CD) para produção de um projeto de banco de dados Azure SQL. Você quer que o SqlPackage use instruções transacionais quando possível durante a publicação. Qual propriedade deve configurar, sem assumir que todos os scripts e operações participarão de uma única transação?

A. `/p:BlockOnPossibleDataLoss=true`

B. `/p:IncludeTransactionalScripts=true`

C. `/p:GenerateSmartDefaults=true`

D. `/Action:Script`

> [!success]- Resposta
> **B — `/p:IncludeTransactionalScripts=true`**
>
> O parâmetro `IncludeTransactionalScripts` instrui o SqlPackage a usar instruções transacionais quando possível. Ele não garante rollback integral de toda a publicação: scripts pré/pós-deploy e algumas operações podem ficar fora dessa transação. Por isso, gere e revise o script de implantação e teste-o em homologação.

---

## Sequência de deployment de referência

1. Commit e validação de branch.
2. Build e validação do DACPAC.
3. Testes e relatórios de drift/deploy.
4. Revisão do script, avisos e aprovações.
5. Deploy controlado e monitoração.

É uma sequência de segurança de referência, não uma imposição do produto.

## Tópicos Relacionados

- [02-Projetos de Banco de Dados SQL](./02-sql-database-projects.md)
- [03-Controle de Versão & Branching](./03-source-control-branching.md)
- [01-Estratégias de Testes](./01-testing-strategy.md)

---

## Documentação Oficial

- [Azure Pipelines with SQL Database Projects](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-projects-pipelines)
- [sqlpackage Reference](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage)
- [Azure Key Vault in Pipelines](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/azure-key-vault)

---

**[← Anterior](./03-source-control-branching.md) | [↑ Voltar para a Seção](./cicd-database-projects.md)**
