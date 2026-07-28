---
title: Configuração do GitHub Copilot e Copilot no Fabric (GitHub Copilot and Copilot in Fabric Setup)
type: study-material
tags:
  - dp-800
  - github-copilot
  - copilot-in-fabric
  - instruction-files
  - model-options
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visao-geral-overview)
> - 📍 [2. Habilitando Copilot no Azure Data Studio, VS Code & Fabric](#habilitando-o-github-copilot-enabling-github-copilot)
>   - 🔹 [Habilitando GitHub Copilot (Individual & Organização)](#para-desenvolvedores-individuais)
>   - 🔹 [Copilot no Microsoft Fabric](#habilitando-o-copilot-no-microsoft-fabric-enabling-copilot-in-microsoft-fabric)
> - 📍 [3. Custom Instructions & Configuração de Modelos](#arquivos-de-instrucoes-do-copilot-copilot-instruction-files)
>   - 🔹 [Arquivos `.github/copilot-instructions.md`](#arquivos-de-instrucoes-do-copilot-copilot-instruction-files)
>   - 🔹 [Configurando Modelos & Ferramentas MCP](#configurando-opcoes-de-modelos-no-chat-configuring-model-options-in-chat)
> - 📍 [4. Desenvolvimento SQL, Copilot CLI & Validação](#utilizando-o-copilot-para-desenvolvimento-sql)
>   - 🔹 [Gerando Queries, Explicações & Code Review](#utilizando-o-copilot-para-desenvolvimento-sql)
>   - 🔹 [Copilot CLI (`gh copilot suggest`) & SQL Database Projects](#copilot-cli-para-projetos-de-banco-de-dados)
>   - 🔹 [Avaliando SQL Gerado & SQL Dinâmico Seguro](#avaliando-sql-gerado-por-ia-evaluating-ai-generated-sql)
> - 📍 [5. Aplicação Prática & Síntese](#casos-de-uso-use-cases)
>   - 🔹 [Casos de Uso](#casos-de-uso-use-cases)
>   - 🔹 [Problemas Comuns, Práticas & Exam Tips](#problemas-comuns-e-solucoes-common-issues)
>   - 🔹 [Questões de Prática](#questoes-de-pratica-practice-questions)

---

# Configuração do GitHub Copilot e Copilot no Fabric (GitHub Copilot and Copilot in Fabric Setup)

## Visão Geral (Overview)

O exame DP-800 cobre a habilitação do GitHub Copilot e do Copilot no Microsoft Fabric, a configuração de modelos de inteligência artificial e ferramentas do Model Context Protocol (MCP), e a criação de arquivos de instruções do Copilot (Copilot instruction files) para fornecer contexto específico do projeto.

> [!abstract]
>
> - Cobre recursos do GitHub Copilot para o desenvolvimento de bancos de dados: sugestões inline, Copilot Chat e comandos de atalho (slash commands).
> - O Copilot atua sugerindo código; ele nunca executa comandos diretamente no banco — todas as sugestões dependem de revisão humana prévia.
> - Tópicos chave do exame: comandos de barra do Copilot Chat (/explain, /fix, /doc), comportamento de preenchimento automático inline e configuração para Azure SQL.

> [!tip] O que o Exame Testa
>
> - O Copilot pode propor ações e, quando ferramentas ou agentes estiverem habilitados, solicitar aprovação para executá-las. Revise e aprove explicitamente qualquer operação que alcance um banco de dados.
> - Comandos slash: `/explain` = explica o código selecionado; `/fix` = sugere uma correção de erro; `/doc` = gera comentários de documentação; `/tests` = gera códigos de testes unitários.
> - O uso do Copilot para Azure SQL no SSMS ou VS Code exige a instalação da extensão GitHub Copilot ativa e licenciamento correspondente.

---

## Habilitando o GitHub Copilot (Enabling GitHub Copilot)

### Para Desenvolvedores Individuais

1. Assine o plano correspondente do GitHub Copilot (Individual, Business ou Enterprise).
2. Instale a extensão oficial do GitHub Copilot na sua IDE (VS Code, Visual Studio ou Azure Data Studio).
3. Faça login na extensão utilizando sua conta autorizada do GitHub.

### Para Organizações

```yaml
# Configurações da Organização > Copilot
# - Habilitar/desabilitar recursos para os times
# - Configurar políticas de exclusão de conteúdo (content exclusion)
# - Configurar proxies de rede corporativa
# - Revisar dados de uso e logs de auditoria
```

### No Azure Data Studio e VS Code para SQL

1. Instale a extensão **GitHub Copilot**.
2. Instale a extensão **GitHub Copilot Chat**.
3. Use o painel de chat do Copilot com o atalho `Ctrl+Shift+I` no VS Code.
4. Aproveite os autocompletar de código (inline completions) ao digitar comandos T-SQL.

---

## Habilitando o Copilot no Microsoft Fabric (Enabling Copilot in Microsoft Fabric)

O Copilot no Fabric é o assistente de IA integrado diretamente para as cargas de trabalho do Fabric (SQL databases, notebooks Spark e pipelines de dados).

```text
Fabric Portal → Settings → Admin portal → Tenant settings
→ Copilot and Azure OpenAI Service → Enable
```

**Copilot em Bancos de Dados Fabric SQL (Fabric SQL database):**

- Escreve queries T-SQL a partir de descrições em linguagem natural.
- Explica o comportamento de planos de execução de consultas.
- Sugere melhorias e otimizações de queries.
- Fica disponível nativamente no editor de consultas SQL do Fabric.

---

## Arquivos de Instruções do Copilot (Copilot Instruction Files)

Os **arquivos de instruções do Copilot** fornecem contexto sobre padrões de desenvolvimento do repositório para que o Copilot os considere em todas as interações e chats de forma automática.

### Criando um Arquivo de Instruções para o GitHub Copilot

```markdown
<!-- .github/copilot-instructions.md -->

## Contexto do Projeto
Este projeto gerencia o banco de dados SQL de uma plataforma de e-commerce.
Banco de dados destino: Azure SQL Database (compatibilidade equivalente ao SQL Server 2022)

## Convenções de Desenvolvimento
- Sempre use nomes de objetos compostos por duas partes (dbo.TableName).
- Sempre inclua SET NOCOUNT ON no cabeçalho de Stored Procedures.
- Use o tipo de dado datetime2(0) no lugar de datetime para colunas de datas.
- Dê preferência para Inline TVFs sobre Scalar UDFs em operações baseadas em conjuntos.
- Use THROW para o tratamento estruturado de erros (nunca RAISERROR).
- Toda stored procedure deve utilizar blocos TRY/CATCH com gestão de transações.

## Resumo do Schema
- dbo.Customers (CustomerId, Name, Email, IsActive)
- dbo.Orders (OrderId, CustomerId, OrderDate, TotalAmount)
- dbo.OrderItems (OrderId, ProductId, Quantity, UnitPrice)
- dbo.Products (ProductId, Name, Price, CategoryId, Attributes JSON)

## Restrições (Não Fazer)
- Não utilize SELECT * em consultas produtivas.
- Não hardcodeie strings de conexão ou credenciais de acesso.
- Não utilize tipos de dados depreciados (datetime, text, image).
```

> [!important] Localização Exata das Instruções Customizadas
>
> - Para que o GitHub Copilot carregue automaticamente as instruções customizadas do projeto em cada sessão de chat do repositório, o arquivo de markdown **deve obrigatoriamente estar localizado em** `.github/copilot-instructions.md` na raiz do repositório.
> - O arquivo utiliza sintaxe Markdown comum para listar regras de codificação, versões de compatibilidade do banco, padrões e antipadrões.

---

## Configurando Opções de Modelos no Chat (Configuring Model Options in Chat)

### Selecionando o Modelo de IA

Em uma sessão do GitHub Copilot Chat, você pode alternar o modelo de inteligência artificial de suporte:

```text
Copilot Chat > Model picker (localizado no topo do painel do chat)
```

Modelos mais comuns disponíveis (variando conforme a assinatura do Copilot):

| Modelo (Model) | Vantagens para Trabalho com SQL e Bancos |
| :--- | :--- |
| GPT-4o | Geração rápida de SQL de propósito geral, respostas diretas. |
| o3-mini | `Resolução de lógicas complexas e queries de alta dificuldade`. |
| Claude 3.5 Sonnet | Análise detalhada de grandes schemas de dados e code review. |
| Claude 3.7 Sonnet | Raciocínio estendido e análises complexas de múltiplos passos. |
| Gemini 2.0 Flash | Respostas muito rápidas e suporte a contexto estendido. |

Para cenários de desenvolvimento em SQL:

- **GPT-4o**: Excelente desempenho em geração rápida de queries comuns.
- **Modelos Claude**: Recomendados para entender schemas extensos devido à janela de contexto.
- **o3-mini**: A melhor escolha para depuração e lógicas SQL complexas que exigem raciocínio estruturado.

### Configurando Ferramentas do Model Context Protocol (MCP)

As ferramentas de MCP estendem as ações que o Copilot consegue invocar, conectando-o a sistemas externos de forma direta:

```json
// Arquivo .vscode/mcp.json (Configuração de MCP no VS Code)
{
    "servers": {
        "sql-server": {
            "type": "stdio",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-mssql"],
            "env": {
                "MSSQL_CONNECTION_STRING": "${env:MSSQL_CONNECTION_STRING}"
            }
        }
    }
}
```

> [!tip] O que é o Model Context Protocol (MCP)?
>
> - O MCP é um protocolo padrão que permite conectar LLMs a ferramentas externas e fontes de dados (como bancos SQL, APIs ou filesystems) de forma segura.
> - No VS Code/Azure Data Studio, servidores MCP são registrados no arquivo de escopo do workspace `.vscode/mcp.json`.

---

## Utilizando o Copilot para Desenvolvimento SQL

### Gerando Queries a Partir de Linguagem Natural

```text
@workspace /explain este stored procedure

Escreva uma stored procedure para transferir fundos entre contas com tratamento 
estruturado de erros e controle de transações.
```

### Explicando Planos de Execução (Execution Plans)

```text
Explique este plano de execução e sugira melhorias:
[cole o XML do plano ou descreva os operadores de gargalo]
```

### Revisão de Código (Code Review)

```text
Revise este código T-SQL buscando vulnerabilidades de segurança e gargalos de performance:
[cole o código T-SQL]
```

---

## Copilot para Azure SQL e Fabric SQL

### Copilot no Portal do Azure para Azure SQL Database

O Portal do Azure incorpora o Copilot diretamente em seu Editor de Consultas web:

- **Linguagem natural para SQL**: Digite a instrução lógica e a IA gera o T-SQL.
- **Explicar consultas**: Destaque a query e peça explicações de processamento.
- **Sugestões de correção**: O Copilot sugere correções caso a query falhe.
- **Nativa do Portal**: Dispensa instalação de qualquer extensão de IDE externa.

Caminho de acesso:

```text
Azure Portal → Azure SQL Database → Query editor (preview)
→ Botão do Copilot ou sugestões inline
```

### Copilot no Microsoft Fabric para SQL

O Fabric fornece assistentes Copilot tanto para **SQL analytics endpoints** (de Lakehouses) quanto para **Fabric SQL databases**:

| Interface | Funcionalidade do Copilot |
| :--- | :--- |
| SQL analytics endpoint | Linguagem natural para T-SQL e explicação de erros de compilação. |
| Fabric SQL database | `Gera, explica e corrige T-SQL; com reconhecimento total do schema`. |
| Notebook (Spark SQL) | Geração de células em SQL e explicações de resultados. |

### Integração com o Azure AI Foundry

O Fabric Copilot pode ser integrado com modelos de machine learning implantados no Azure AI Foundry:

- Permite conectar um workspace do Fabric a um projeto do Azure AI Foundry.
- Utilização de modelos customizados ou ajustados (fine-tuned) para geração de código específico.
- Enriquece o contexto com schemas e termos proprietários de negócio.

---

## Aprofundando em Instruções Customizadas (Custom Instructions)

### O Arquivo `.github/copilot-instructions.md`

Este arquivo markdown é carregado automaticamente por toda sessão de chat do Copilot no repositório correspondente:

- Deve estar salvo na pasta raiz sob o caminho `.github/`.
- Markdown simples, sem necessidade de sintaxe especial.
- Garante que todo o time de desenvolvimento siga as mesmas diretivas no Copilot.

### Configurações de Instruções no VS Code

Para regras locais por usuário ou workspace no VS Code, configure a propriedade no `settings.json`:

```json
// .vscode/settings.json (workspace) ou settings.json (user)
{
    "github.copilot.chat.codeGeneration.instructions": [
        {
            "text": "Sempre use prefixos de schema (dbo.Tabela). Use THROW no lugar de RAISERROR."
        }
    ]
}
```

---

## Copilot CLI para Projetos de Banco de Dados

### Usando `gh copilot suggest` no Terminal

A extensão do GitHub CLI permite utilizar o Copilot para geração de comandos de forma ágil fora da IDE:

```bash
# Instalar a extensão do copilot no gh CLI
gh extension install github/gh-copilot

# Solicitar uma query T-SQL
gh copilot suggest "write a T-SQL query to find customers with no orders in 90 days"

# Obter explicações de um comando ou script administrativo
gh copilot explain "sp_WhoIsActive"
```

### Integração com SQL Database Projects (`sqlproj`)

Se o seu repositório contiver um arquivo `.sqlproj`, o Copilot atua com reconhecimento do seu schema:

- Analisa objetos e DACPAC definidos no escopo do projeto SQL.
- Sugere autocompletar usando nomes corretos de tabelas e colunas locais.
- Funciona em conjunto com a extensão **SQL Database Projects** do VS Code.

---

## Avaliando SQL Gerado por IA (Evaluating AI-Generated SQL)

### Lista de Verificação Pré-Produção

- [ ] **Risco de SQL Injection**: Garantir que queries dinâmicas usem parâmetros com `sp_executesql`.
- [ ] **Nomes de Colunas**: Validar com o banco real para barrar possíveis alucinações da IA.
- [ ] **Conversões Implícitas**: Checar compatibilidade de tipos (`NVARCHAR` vs `VARCHAR`).
- [ ] **Correção de JOINS**: Garantir que as chaves de relacionamento estejam certas.
- [ ] **Uso de Indexes**: Testar queries rodando `SET STATISTICS IO ON` no staging.

### Padrões de SQL Dinâmico Seguro vs Inseguro

```sql
-- INSEGURO: concatenação direta de variáveis (Risco grave de SQL Injection)
DECLARE @sql NVARCHAR(500) = 'SELECT * FROM dbo.Users WHERE Name = ''' + @UserInput + '''';
EXEC (@sql);

-- SEGURO: query parametrizada via sp_executesql
DECLARE @sql NVARCHAR(500) = N'SELECT * FROM dbo.Users WHERE Name = @Name';
EXEC sp_executesql @sql, N'@Name NVARCHAR(100)', @Name = @UserInput;
```

> [!warning] Dica de Exame: SQL Dinâmico Seguro contra Injeção SQL
>
> - Nunca execute SQL dinâmico usando concatenação de strings ou `EXEC(@sql)` simples se houver inputs de usuários.
> - Use sempre a Stored Procedure de sistema **`sp_executesql`** com passagem parametrizada e tipada de argumentos.

---

## Casos de Uso (Use Cases)

- **Geração de queries complexas**: Descreva as colunas e condições lógicas e receba o script pronto.
- **Exploração e explicação**: Peça para o Copilot descrever views e stored procedures com complexidade legada.
- **Documentação de banco**: Automatize a criação de comentários em triggers e funções do banco.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa | Solução |
| :--- | :--- | :--- |
| O Copilot não sugere códigos SQL | Extensão correspondente não está instalada ou logada | Instale e faça login no GitHub Copilot e Copilot Chat. |
| Instruções do projeto ignoradas | Caminho ou formato incorreto do markdown | `Certifique-se de salvar na pasta `.github/copilot-instructions.md` na raiz`. |
| Servidor MCP falha na conexão | Erro nas configurações do arquivo de conexões | Revise o arquivo `mcp.json` e as variáveis de ambiente necessárias. |
| Nomes de colunas alucinados pela IA | Falta de contexto de schemas locais | Descreva o schema no arquivo de instruções ou conecte um servidor MCP. |

---

## Melhores Práticas (Best Practices)

- Salve um arquivo `.github/copilot-instructions.md` com as regras lógicas e de sintaxe do seu banco; essa é a configuração mais impactante em um repositório SQL.
- Revise toda e qualquer query dinâmica gerada pela IA, forçando parametrizações com `sp_executesql` para afastar brechas de SQL Injection.
- Escolha o modelo de IA de acordo com a tarefa (Claude 3.7 Sonnet para análises pesadas, GPT-4o ou Gemini para códigos rápidos).
- Integre servidores MCP com arquivos de instruções para dar ao Copilot acesso em tempo real e normas de desenvolvimento.

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - O caminho correto para instruções do Copilot é `.github/copilot-instructions.md` — decore este local.
> - A alternância de modelos (model picker) fica no Copilot Chat e não no recurso de autocompletar inline.
> - Ferramentas de MCP são registradas no arquivo de workspace `.vscode/mcp.json`.
> - O Copilot no Microsoft Fabric é habilitado globalmente em nível de tenant pelo administrador do portal.
> - A propriedade de instruções de geração de código no VS Code (`github.copilot.chat.codeGeneration.instructions`) é definida no nível do usuário/workspace, enquanto o arquivo `.github/copilot-instructions.md` é no nível de repositório.

---

## Resumo dos Conceitos (Key Takeaways)

- O arquivo de instruções customiza as respostas do Copilot para todo o time do repositório.
- A seleção de modelos e servidores MCP expandem a capacidade cognitiva das sessões de chat.
- O Azure SQL Database dispõe de assistente Copilot embutido diretamente no portal da nuvem.
- Valide nomes de objetos, conversões de dados e parametrizações de seguranças nas saídas geradas por IA.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Um desenvolvedor deseja garantir que o GitHub Copilot sempre utilize o comando `THROW` em vez de `RAISERROR` ao sugerir tratamento de erros em Stored Procedures neste repositório de banco de dados. Qual abordagem persiste de forma ideal essas regras para todos os desenvolvedores deste repositório?

A. Adicionar as regras individualmente no chat a cada nova sessão.

B. Criar um arquivo `.github/copilot-instructions.md` na raiz do repositório contendo as regras.

C. Configurar as regras de geração de código no arquivo settings.json do VS Code de cada usuário.

D. Adicionar comentários com as regras de erros em cada novo arquivo SQL criado.

> [!success]- Resposta
> **B — Criar um arquivo .github/copilot-instructions.md na raiz do repositório contendo as regras**
>
> O arquivo `.github/copilot-instructions.md` é a forma padrão de centralizar e persistir regras e padrões de código para o GitHub Copilot em nível de repositório, aplicando-se de forma transparente a todos os colaboradores do projeto. Configurações locais no VS Code (C) ou sessões de chat (A) dependem de ações manuais individuais.

---

## Tópicos Relacionados

- [01-Impacto de Segurança de Ferramentas Assistidas por IA](./01-ai-security-impact.md)
- [03-Endpoints de Servidores MCP](./03-mcp-server-endpoints.md)

---

## Documentação Oficial

- [GitHub Copilot Docs](https://docs.github.com/en/copilot)
- [Copilot Custom Instructions](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot)
- [Copilot in Fabric](https://learn.microsoft.com/en-us/fabric/fundamentals/copilot-fabric-overview)
- [Copilot in Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/copilot/copilot-azure-sql-overview)
- [GitHub Copilot Extensions](https://docs.github.com/en/copilot/using-github-copilot/using-extensions-to-integrate-external-tools-with-copilot-chat)

---

**[← Anterior](./01-ai-security-impact.md) | [↑ Voltar para a Seção](./ai-assisted-tools.md) | [Lab: GitHub Copilot](../../practice/labs/04-ai-assisted-tools/02-github-copilot-setup-lab.sql) | [Próximo →](./03-mcp-server-endpoints.md)**
