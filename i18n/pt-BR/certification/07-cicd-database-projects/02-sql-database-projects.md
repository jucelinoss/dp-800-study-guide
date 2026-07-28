---
title: Projetos de Banco de Dados SQL (SDK-Style) (SQL Database Projects - SDK-Style)
type: study-material
tags:
  - dp-800
  - sql-database-projects
  - dacpac
  - sdk-style
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Formato SDK-Style de Projeto](#formato-sdk-style-de-projeto)
> - 📍 [3. Estrutura de Diretórios Recomendada](#estrutura-de-diretórios-recomendada)
> - 📍 [4. Definição de Objetos Declarativos](#definição-de-objetos-declarativos)
> - 📍 [5. Scripts Pré e Pós-Implantação (Pre and Post-Deployment)](#scripts-pré-e-pós-implantação-pre-and-post-deployment)
> - 📍 [6. Compilando via CLI do dotnet](#compilando-via-cli-do-dotnet)
> - 📍 [7. Validando e Implantando com o SqlPackage](#validando-e-implantando-com-o-sqlpackage)
>   - 🔹 [Parâmetros de Configuração Chave do SqlPackage](#parâmetros-de-configuração-chave-do-sqlpackage)
> - 📍 [8. Extraindo e Importando Estruturas Existentes](#extraindo-e-importando-estruturas-existentes)
> - 📍 [9. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [10. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [11. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [12. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [13. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [14. Documentação Oficial](#documentação-oficial)
---

# Projetos de Banco de Dados SQL (SDK-Style) (SQL Database Projects - SDK-Style)

## Visão Geral (Overview)

Os Projetos de Banco de Dados SQL (SQL Database Projects) permitem gerenciar a estrutura física do seu banco (schema) no controle de versão na forma de arquivos declarativos T-SQL individuais, compilando um artefato implantável final de extensão **`.dacpac`**. O formato SDK-Style moderno de arquivo `.sqlproj` (utilizando `Microsoft.Build.Sql`) integra-se de forma nativa com a CLI padrão de ferramentas do `dotnet build` e pipelines modernos de CI/CD.

O arquivo dacpac registra o estado desejado final do banco — o deploy computa e gera a diferença lógica (diff) de forma automatizada contra a base de destino.

> [!abstract]
>
> - Cobre projetos baseados em .sqlproj, compilação de artefatos dacpac, publicação e a lógica de scripts pré e pós-implantação.
> - Projetos SQL introduzem o gerenciamento de schema code-first e controlado por repositório para SQL Server e Azure SQL.
> - Tópicos chave do exame: estrutura do projeto, distinção física dacpac vs bacpac e o papel de scripts pré/pós-deploy.

> [!tip] O que o Exame Testa
>
> - O build compila um arquivo **`.dacpac`** (apenas o schema); o utilitário **`SqlPackage /Action:Publish`** calcula a diferença e atualiza o banco de destino de forma idempotente.
> - **dacpac** = apenas estrutura (schema); **bacpac** = estrutura + dados físicos (usado para migração e cópias físicas de bases, não para CI/CD).
> - Scripts pré/pós-implantação rodam fora do cálculo do dacpac — usados para migrar dados legados ou preencher lookups estáticos.

---

## Formato SDK-Style de Projeto

O arquivo de definição de projeto moderno SDK-style é enxuto frente ao modelo herdado clássico:

```xml
<!-- MyDatabase.sqlproj -->
<Project Sdk="Microsoft.Build.Sql/2.1.0">
  <PropertyGroup>
    <Name>MyDatabase</Name>
    <DSP>Microsoft.Data.Tools.Schema.Sql.SqlAzureV12DatabaseSchemaProvider</DSP>
    <ModelCollation>1033, CI</ModelCollation>
  </PropertyGroup>
</Project>
```

Diferenças cruciais em relação ao formato legado:

- Qualquer arquivo `.sql` presente no diretório é **automaticamente incluído** na compilação do projeto (dispensa a necessidade de registrar `<Build Include="..."/>` para cada arquivo).
- Adota convenções padrão MSBuild.
- Totalmente compatível com compilações cross-platform via CLI do `dotnet build`.
- Permite referenciar componentes externos e schemas compartilhados via referências de pacotes NuGet.

> [!important] Vantagem do Formato SDK-Style (Moderno)
>
> - Ao contrário do formato herdado do SSDT (Visual Studio), o novo formato baseado em **SDK-Style** (utilizando `<Project Sdk="Microsoft.Build.Sql/...">`) inclui automaticamente qualquer arquivo `.sql` presente no diretório.
> - Isso elimina conflitos de mesclagem (merge conflicts) no arquivo `.sqlproj` que costumavam ocorrer quando múltiplos desenvolvedores adicionavam novos arquivos no repositório ao mesmo tempo. Ele também suporta compilação multiplataforma via CLI do `dotnet build`.

---

## Estrutura de Diretórios Recomendada

```text
MyDatabase/
├── MyDatabase.sqlproj          ← arquivo de projeto
├── Schema/
│   ├── Tables/
│   │   ├── dbo.Customers.sql
│   │   ├── dbo.Orders.sql
│   │   └── dbo.OrderItems.sql
│   ├── Views/
│   │   └── dbo.vw_ActiveOrders.sql
│   ├── StoredProcedures/
│   │   ├── dbo.CreateOrder.sql
│   │   └── dbo.GetOrderSummary.sql
│   ├── Functions/
│   │   └── dbo.CalculateOrderTotal.sql
│   └── Indexes/
│       └── dbo.Orders.IX_CustomerId.sql
├── Security/
│   └── Roles/
│       └── dbo.OrdersReader.sql
├── Scripts/
│   ├── PreDeployment/
│   │   └── PreDeployment.sql   ← roda ANTES das alterações do dacpac
│   └── PostDeployment/
│       └── PostDeployment.sql  ← roda DEPOIS das alterações do dacpac
└── Tests/
    └── OrderTests/
        └── test_CreateOrder.sql
```

---

## Definição de Objetos Declarativos

Cada objeto é criado em um arquivo individual de extensão `.sql` contendo comandos padrões `CREATE` ou `CREATE OR ALTER`:

```sql
-- Schema/Tables/dbo.Orders.sql
CREATE TABLE [dbo].[Orders]
(
    [OrderId]    INT           NOT NULL IDENTITY(1,1),
    [CustomerId] INT           NOT NULL,
    [OrderDate]  DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    [Status]     NVARCHAR(20)  NOT NULL DEFAULT 'Pending',
    [TotalAmount] DECIMAL(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT [PK_Orders] PRIMARY KEY CLUSTERED ([OrderId] ASC),
    CONSTRAINT [FK_Orders_Customers]
        FOREIGN KEY ([CustomerId]) REFERENCES [dbo].[Customers] ([CustomerId])
);
```

```sql
-- Schema/StoredProcedures/dbo.CreateOrder.sql
CREATE OR ALTER PROCEDURE [dbo].[CreateOrder]
    @CustomerId INT,
    @ProductId  INT,
    @Quantity   INT,
    @OrderId    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Orders (CustomerId, Status)
    VALUES (@CustomerId, 'Pending');

    SET @OrderId = SCOPE_IDENTITY();

    INSERT INTO dbo.OrderItems (OrderId, ProductId, Quantity)
    VALUES (@OrderId, @ProductId, @Quantity);
END;
```

---

## Scripts Pré e Pós-Implantação (Pre and Post-Deployment)

Esses scripts são incluídos no dacpac, mas não são compilados nem validados no modelo de objetos. O plano de implantação é calculado antes da execução do script de pré-implantação; em seguida, o pré-deploy é executado antes do plano e o pós-deploy após a conclusão do plano:

```sql
-- Scripts/PreDeployment/PreDeployment.sql
-- Executado ANTES das modificações físicas da base — ideal para preparar e mover dados legados
PRINT 'Pre-deployment: Executando migrações de dados de colunas antigas...';

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('dbo.Orders')
             AND name = 'LegacyCode')
BEGIN
    -- Mover dados para a nova coluna antes que a dacpac exclua a coluna antiga
    UPDATE dbo.Orders
    SET Notes = CONCAT(Notes, ' [Legacy: ', LegacyCode, ']')
    WHERE LegacyCode IS NOT NULL;
END;
```

```sql
-- Scripts/PostDeployment/PostDeployment.sql
-- Executado DEPOIS de concluir as modificações do dacpac — ideal para cargas referenciais estáticas
PRINT 'Post-deployment: Carregando dados estáticos...';

:r .\..\..\Data\ReferenceData\dbo.OrderStatus.data.sql
:r .\..\..\Data\ReferenceData\dbo.Countries.data.sql

PRINT 'Post-deployment concluído.';
```

Para registrar a ação correspondente dos scripts, especifique as referências explícitas no arquivo do projeto `.sqlproj`:

```xml
<!-- MyDatabase.sqlproj — marcação das ações de build -->
<ItemGroup>
  <PreDeploy Include="Scripts\PreDeployment\PreDeployment.sql" />
  <PostDeploy Include="Scripts\PostDeployment\PostDeployment.sql" />
  <!-- Os arquivos chamados por :r não são objetos do modelo. -->
  <Build Remove="Data\ReferenceData\**\*.sql" />
  <None Include="Data\ReferenceData\**\*.sql" />
  <!-- Excluir testes da compilação do modelo, mantendo-os visíveis no projeto. -->
  <Build Remove="Tests\**\*.sql" />
  <None Include="Tests\**\*.sql" />
</ItemGroup>
```

---

## Compilando via CLI do dotnet

```bash
# Instalar a ferramenta global SqlPackage (se necessário)
dotnet tool install -g microsoft.sqlpackage

# Compilar o projeto — gera o arquivo .dacpac de saída
dotnet build MyDatabase.sqlproj

# Saída por padrão em:
# bin/Debug/MyDatabase.dacpac

# Compilar com a configuração de Release para pipelines
dotnet build MyDatabase.sqlproj --configuration Release
```

---

## Validando e Implantando com o SqlPackage

```bash
# Gerar o script T-SQL de diferenças (Action:Script) sem alterar o banco de destino
sqlpackage /Action:Script \
    /SourceFile:bin/Release/MyDatabase.dacpac \
    /TargetConnectionString:"Server=myserver.database.windows.net;Database=MyDB;Authentication=Active Directory Default" \
    /OutputPath:./deployment-script.sql

# Aplicar o deploy e atualizar o banco de destino (Action:Publish)
sqlpackage /Action:Publish \
    /SourceFile:bin/Release/MyDatabase.dacpac \
    /TargetConnectionString:"Server=myserver.database.windows.net;Database=MyDB;Authentication=Active Directory Default"

# Publicar passando flags de segurança
sqlpackage /Action:Publish \
    /SourceFile:bin/Release/MyDatabase.dacpac \
    /TargetConnectionString:"..." \
    /p:BlockOnPossibleDataLoss=true \
    /p:DropObjectsNotInSource=false \
    /p:GenerateSmartDefaults=true

# Comparar dois dacpacs e gerar relatório XML de desvios (Drift Detection)
sqlpackage /Action:DeployReport \
    /SourceFile:bin/Release/MyDatabase.dacpac \
    /TargetFile:current-schema.dacpac \
    /OutputPath:./drift-report.xml
```

> [!tip] Dica para a Prova: DACPAC vs BACPAC
>
> - **DACPAC (Data-tier Application Package)**: Contém exclusivamente a definição lógica do **schema** do banco de dados (tabelas, views, procedures). Es o artefato padrão para deploys de CI/CD baseados em comparação de estado desejado.
> - **BACPAC (Schema + Data Package)**: Contém o schema e também os **dados físicos** compactados das tabelas. Utilizado para exportação/importação de bancos completos de produção para ambientes locais, não sendo adequado para pipelines automáticos de CI/CD.

### Parâmetros de Configuração Chave do SqlPackage

| Parâmetro | Padrão | Descrição |
| :--- | :--- | :--- |
| `BlockOnPossibleDataLoss` | `true` | `Aborta o deploy caso ocorra alteração que gere perda física de dados (ex: exclusão de coluna ou tipo menor)`. |
| `DropObjectsNotInSource` | `false` | Remove do banco físico tabelas e objetos que não estão no projeto (dacpac). |
| `GenerateSmartDefaults` | `false` | Insere valores padrão automáticos ao adicionar restrições `NOT NULL` em colunas existentes. |
| `IncludeTransactionalScripts` | `false` | Usa instruções transacionais quando possível durante a publicação; scripts pré/pós-deploy e algumas operações podem não participar da mesma transação. |

> [!warning] O Risco do Parâmetro BlockOnPossibleDataLoss
>
> - Por padrão, o `sqlpackage` ativa a propriedade `BlockOnPossibleDataLoss=true`.
> - **Cuidado de Implantação**: Se a atualização de schema indicar que alguma coluna será excluída (`DROP`) ou que a alteração do tipo de dados de uma coluna possa causar perda de informações, o deploy será **abortado** com erro. Para prosseguir com segurança, prepare os scripts de `PreDeployment` correspondentes antes de liberar a compilação.

---

## Extraindo e Importando Estruturas Existentes

```bash
# Extrair apenas a estrutura DDL de um banco ativo para um arquivo dacpac
sqlpackage /Action:Extract \
    /TargetFile:./current-schema.dacpac \
    /SourceConnectionString:"Server=myserver.database.windows.net;Database=MyDB;Authentication=Active Directory Default"

# Exportar o schema e os dados completos para formato bacpac
sqlpackage /Action:Export \
    /TargetFile:./database-backup.bacpac \
    /SourceConnectionString:"..."
```

---

## Problemas Comuns e Soluções (Common Issues)

| Sintoma | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Erro `Unresolved reference to object` | Referência a tabelas ou schemas inexistentes | Declare dependências externas via NuGet ou configure referências cruzadas no projeto. |
| Deploy abortado por perda potencial de dados | `BlockOnPossibleDataLoss` barrou remoção de coluna | Faça backup dos dados via script de Pre-Deployment ou desative temporariamente a flag. |
| Scripts Pre/Post não executam no deploy | Build Action configurada incorretamente no xml | Valide se o `.sqlproj` mapeia os caminhos como `<PreDeploy>` ou `<PostDeploy>`. |
| Falha por incompatibilidade de engine de destino | Propriedade `DSP` desajustada no projeto | Configure a DSP para o alvo correto: `SqlAzureV12DatabaseSchemaProvider` para o Azure SQL. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - O formato SDK-style adota o SDK `Microsoft.Build.Sql` e não exige mapeamento explícito de cada tabela no `.sqlproj`.
> - O arquivo **dacpac** representa o **estado final desejado** (declarativo) do banco.
> - O `BlockOnPossibleDataLoss=true` resguarda dados produtivos, interrompendo deploys se houver risco de exclusões físicas.
> - O script de **Pre-Deployment** atua na movimentação de dados legados antes da execução do plano já calculado; o de **Post-Deployment** atua depois de todas as atualizações lógicas das tabelas.

---

## Resumo dos Conceitos (Key Takeaways)

- O compilador do `.sqlproj` gera um artefato compilado final `.dacpac`.
- Use a ferramenta CLI `sqlpackage` para validar scripts e implantar a dacpac via `publish`.
- Mantenha um arquivo físico `.sql` individual para cada objeto para facilitar revisões de código (pull requests).
- dacpac manipula estruturas lógicas (schemas), ao passo que o bacpac manipula dados compactados + schemas.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Você está refatorando a tabela `dbo.Orders` e precisa remover a coluna legada `OldStatusID`. Para garantir que o deploy em produção não sofra falhas por perda potencial de dados com a flag `BlockOnPossibleDataLoss` ativa, qual ação você deve adotar?

A. Mudar a flag `BlockOnPossibleDataLoss` para `false` diretamente no pipeline.

B. Configurar um script de Pre-Deployment no projeto SQL para migrar os dados históricos relevantes para a coluna correta de notas e deixar o dacpac prosseguir com o drop automático.

C. Excluir a tabela completa no banco de dados antes de iniciar o deploy da dacpac.

D. Utilizar o utilitário bacpac para exportar os dados e importá-los novamente após a exclusão.

> [!success]- Resposta
> **B — Configurar um script de Pre-Deployment no projeto SQL para migrar os dados históricos relevantes para a coluna correta de notas e deixar o dacpac prosseguir com o drop automático**
>
> A melhor prática de segurança em pipelines de banco de dados (CI/CD) é preservar informações executando transferências de valores no script de Pre-Deployment, permitindo que a exclusão física ocorra na fase sequencial do deploy de schema do dacpac de forma limpa. Desativar a flag de segurança globalmente (A) é perigoso e pode ocultar outros drops indesejados.

---

## Tópicos Relacionados

- [01-Estratégias de Testes](./01-testing-strategy.md)
- [03-Controle de Versão & Branching](./03-source-control-branching.md) *(Inglês apenas)*
- [04-Pipelines de Implantação](./04-deployment-pipelines.md) *(Inglês apenas)*

---

## Documentação Oficial

- [SQL Database Projects Overview](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-projects-overview)
- [sqlpackage CLI Reference](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage)
- [SDK-style SQL Projects](https://learn.microsoft.com/en-us/sql/tools/sql-database-projects/concepts/sdk-style-projects)

---

**[← Anterior](./01-testing-strategy.md) | [↑ Voltar para a Seção](./cicd-database-projects.md) | [Lab: Projetos de Banco de Dados SQL](../../practice/labs/07-cicd-database-projects/02-sql-database-projects-lab.sql) | [Próximo →](./03-source-control-branching.md)**
