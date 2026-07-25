# Plano de Ação: Fork, Internacionalização (pt-BR / es) e Fluxo de Contribuição no GitHub

> **Projeto:** DP-800 Study Guide  
> **Repositório Upstream:** [kengio/dp-800-study-guide](https://github.com/kengio/dp-800-study-guide)  
> **Objetivo:** Estabelecer uma estrutura profissional de contribuição, organizar as traduções (Português e Espanhol), localizar os laboratórios práticos SQL e compartilhar o material com colegas de estudo via GitHub.

---

## 🎯 Resumo Executivo

Este plano define o passo a passo seguro para você:
1. **Criar seu Fork** no GitHub e reconfigurar o repositório local sem perder o histórico do autor original.
2. **Organizar o trabalho local em branches focadas e de curta duração**, garantindo que correções, laboratórios, ferramentas e traduções não fiquem misturados.
3. **Estruturar a internacionalização (`i18n/pt-BR` e `i18n/es`)** em conformidade com as regras do projeto ([TRANSLATING.md](./TRANSLATING.md)).
4. **Subir e compartilhar o projeto** com seus amigos de estudo via GitHub.
5. **Submeter Pull Requests (PRs)** limpos e granulares para o repositório original do `kengio`.

---

## 📐 Etapa 1: Preparação do Repositório GitHub & Remotes Git

### 1.1 Criar o Fork no GitHub
1. Acesse o repositório original: [https://github.com/kengio/dp-800-study-guide](https://github.com/kengio/dp-800-study-guide).
2. Clique no botão **Fork** (canto superior direito).
3. Selecione sua conta pessoal como destino.

### 1.2 Reconfigurar os Remotes no Git Local
No terminal do seu computador (dentro da pasta `d:\source\dp-800-study-guide`), execute:

```powershell
# 1. Renomear o 'origin' atual (que aponta para o kengio) para 'upstream'
git remote rename origin upstream

# 2. Adicionar o seu novo Fork pessoal como 'origin' (substitua SEU_USUARIO pelo seu username do GitHub)
git remote add origin https://github.com/SEU_USUARIO/dp-800-study-guide.git

# 3. Confirmar a nova estrutura de remotes
git remote -v
```

*Resultado Esperado:*
- `origin`: Aponta para a sua conta no GitHub (para onde você envia seus commits e compartilha com seus amigos).
- `upstream`: Aponta para o projeto original do `kengio` (para você baixar novidades e atualizações futuras).

### 1.3 Atualizar o `.gitignore` Local
Para evitar enviar arquivos temporários, resíduos de compilação ou arquivos do ambiente local para o GitHub, adicione os seguintes caminhos ao `.gitignore`:

```gitignore
# Saídas de compilação e arquivos temporários locais
dist/
output/
nul
.agents/
.gemini/
```

---

## 🌿 Etapa 2: Estratégia de Branches Temáticas

Para garantir que os Pull Requests sejam aceitos facilmente pelo mantenedor do projeto, dividiremos as alterações em **branches dedicadas**:

| Nome da Branch | Finalidade / Conteúdo |
| :--- | :--- |
| **`main`** | Mantida idêntica à `upstream/main` para sincronizações futuras. |
| **`chore/i18n-tooling`** | Convenções e ferramentas compartilhadas: `TRANSLATING.md`, índices i18n, `.gitignore`, scripts DOCX e arquivos batch. |
| **`fix/markdown-formatting`** | Apenas correções mecânicas de Markdown existentes: espaçamento, cabeçalhos, links e sintaxe. Não incluir conteúdo técnico novo. |
| **`feature/sql-labs`** | Os 42 scripts SQL canônicos em `practice/labs/`, alinhados a `LAB_RULES.md`. |
| **`feat/study-resources`** | Conteúdo canônico novo em inglês, como `certification/12-other-topics/` e guias adicionais em `certification/resources/`. |
| **`i18n/pt-br`** | Conteúdo teórico e labs traduzidos para Português do Brasil (`i18n/pt-BR/`). O nome da pasta preserva o locale oficial `pt-BR`. |
| **`i18n/es`** | Reservada para uma futura tradução em espanhol; não criar nem enviar enquanto não houver conteúdo revisado. |

> **Recomendação:** use branches temáticas de curta duração. Elas facilitam revisão, reversão e atualização com `upstream/main`. Não use uma única branch genérica de feature para todo o trabalho. Embora `i18n/pt-BR` seja um nome Git válido, `i18n/pt-br` é preferível como nome de branch por consistência visual entre plataformas.

---

## 🌐 Etapa 3: Arquitetura de Internacionalização (i18n)

Seguindo as diretrizes oficiais do arquivo [`TRANSLATING.md`](./TRANSLATING.md):

### 3.1 Estrutura de Diretórios
As traduções vivem dentro de `i18n/<locale>/` espelhando 1:1 a estrutura da pasta `certification/` e `practice/labs/`:

```text
i18n/
├── README.md                           # Índice global de idiomas
├── pt-BR/
│   ├── README.md                       # Página inicial da tradução pt-BR (status e mantenedor)
│   ├── certification/                  # Espelho dos 12 domínios de teoria em Português
│   │   ├── dp-800-overview.md
│   │   ├── 01-database-objects/
│   │   └── ...
│   └── practice/labs/                  # Espelho dos laboratórios SQL em Português
│       ├── 01-database-objects/
│       └── ...
└── es/
    ├── README.md                       # Página inicial da tradução em Espanhol
    ├── certification/
    └── practice/labs/
```

### 3.2 Regras de Tradução (Teoria + Labs SQL)
- **Prosa:** Traduzir 100% dos textos explicativos.
- **Sintaxe SQL & Palavras-chave:** **Manter em Inglês** (ex: `SELECT`, `CREATE TABLE`, `PERSISTED`, `SCHEMABINDING`, `datetime2`).
- **Termos de Produto Microsoft:** Manter em Inglês quando não houver tradução técnica padrão (ex: *Always Encrypted*, *RAG*, *DiskANN*, *Full-Text Catalog*).
- **Comentários nos Scripts SQL:** Traduzir os comentários e blocos `-- CONCEITOS E DEFINIÇÕES CHAVE:` e `-- [PONTO DE ATENÇÃO DP-800]` para facilitar a leitura.
- **Frontmatter YAML:** Traduzir o campo `title:`, mantendo `tags:` e `type:` inalterados.

---

## 👥 Etapa 4: Publicação no GitHub & Compartilhamento

1. **Enviar as branches para o seu Fork:**
   ```powershell
   # Enviar a branch main
   git push -u origin main

   # Enviar as branches de trabalho
   git push -u origin chore/i18n-tooling
   git push -u origin fix/markdown-formatting
   git push -u origin feature/sql-labs
   git push -u origin feat/study-resources
   git push -u origin i18n/pt-br
   ```

2. **Compartilhar com Seus Amigos:**
   - Forneça o link do seu repositório: `https://github.com/SEU_USUARIO/dp-800-study-guide`
   - Seus colegas poderão navegar no GitHub, ler o conteúdo traduzido em `i18n/pt-BR/` e baixar os labs SQL diretamente.

---

## 🚀 Etapa 5: Fluxo de Pull Requests (PRs) para o Mantenedor Original

Para que o autor original (`kengio`) avalie e integre seu trabalho:

### Passo 1: Abrir uma Issue de Comunicação (Coordenação i18n)
Antes de enviar os PRs grandes, abra uma Issue no repositório do `kengio`:
- **Título:** `i18n: Add Brazilian Portuguese (pt-BR) and Spanish (es) translations + SQL Labs`
- **Conteúdo:** Informar que você estruturou a localização em `pt-BR` e `es` seguindo o `TRANSLATING.md` e desenvolveu scripts de laboratório práticos.

### Passo 2: Submeter os Pull Requests em Ordem (Um por vez)

1. **PR #1 (Ferramentas e Convenções i18n):**
   - Branch: `chore/i18n-tooling` -> `kengio/main`
   - Descrição: Convenções de tradução, estrutura i18n e ferramentas de geração DOCX independentes de locale.
2. **PR #2 (Melhorias de Formatação):**
   - Branch: `fix/markdown-formatting` -> `kengio/main`
   - Descrição: Correções pontuais e mecânicas de formatação em arquivos Markdown existentes.
3. **PR #3 (Laboratórios SQL Nativos):**
   - Branch: `feature/sql-labs` -> `kengio/main`
   - Descrição: Adição da suite de laboratórios práticos T-SQL em `practice/labs/`.
4. **PR #4 (Recursos Canônicos em Inglês):**
   - Branch: `feat/study-resources` -> `kengio/main`
   - Descrição: Guias e recursos técnicos canônicos novos em inglês.
5. **PR #5 (Tradução Português):**
   - Branch: `i18n/pt-br` -> `kengio/main`
   - Descrição: Tradução completa do guia e laboratórios para Português do Brasil (`i18n/pt-BR/`).

> A tradução em espanhol será tratada em um PR separado somente quando estiver completa e revisada.

---

## 🧾 Etapa 5.1: Plano de Commits

Cada branch deve conter commits coesos. Não há necessidade de um commit por arquivo; agrupe arquivos que formam uma unidade revisável.

| Branch | Commits sugeridos |
| :--- | :--- |
| `chore/i18n-tooling` | `chore(i18n): document locale mirror conventions`; `chore(tools): make DOCX build locale-aware`; `chore(git): ignore local build and audit artifacts` |
| `fix/markdown-formatting` | `fix(markdown): normalize formatting in certification guides` — somente após retirar alterações de conteúdo técnico desta branch. |
| `feature/sql-labs` | `feat(labs): add database-object labs`; `feat(labs): add programmability and advanced T-SQL labs`; `feat(labs): add Azure, CI/CD, AI, search and RAG labs` — adapte os grupos aos domínios efetivamente revisados. |
| `feat/study-resources` | `feat(resources): add SQL Server and Azure architecture guides`; `feat(resources): add other-topic architecture material` |
| `i18n/pt-br` | `feat(i18n): add pt-BR locale structure and guides`; `feat(i18n): add pt-BR SQL lab mirror`; `feat(i18n): complete remaining pt-BR theory translations` |

Commits devem ser criados depois de validar seu grupo de arquivos. Cada PR deve sair diretamente de `main`/`upstream/main`, e não de outra branch temática, para permanecer independente.

---

## ⏳ Etapa 5.2: Pendências Antes de Criar PRs

- [ ] Traduzir manualmente os comentários dos **40 labs canônicos restantes** em `practice/labs/`, preservando SQL executável idêntico ao espelho pt-BR.
- [ ] Concluir os espelhos teóricos pt-BR ausentes. O inventário atual aponta **98** Markdown canônicos em `certification/` e **58** Markdown sob `i18n/pt-BR/certification/`; a comparação deve ser feita por caminho antes do commit final.
- [ ] Revisar os guias canônicos em inglês para garantir que nenhuma tradução reduziu seções, exemplos, tabelas ou observações técnicas existentes.
- [ ] Executar e validar o gerador DOCX para `--locale en` e `--locale pt-BR`.
- [ ] Separar as alterações atuais por escopo antes de fazer staging: há conteúdo novo e alterações substanciais que não pertencem à branch de formatação.
- [ ] Rodar validação de links e Markdown nos arquivos alterados.
- [ ] Confirmar que não há arquivos pessoais, backups ou saídas de build no staging.

---

## 📋 Checklist de Execução Prática

Use este checklist para acompanhar a execução:

- [ ] **Fork criado** na sua conta no GitHub.
- [ ] **Remote `upstream` e `origin` configurados** no Git local.
- [ ] **`.gitignore` atualizado** ignorando resíduos locais (`dist/`, `output/`, `nul`, `.agents/`).
- [ ] **Pendências de conteúdo concluídas e validadas.**
- [ ] **Branch `chore/i18n-tooling`** criada e commitada.
- [ ] **Branch `fix/markdown-formatting`** criada e commitada somente com ajustes mecânicos.
- [ ] **Branch `feature/sql-labs`** criada e commitada com os scripts em `practice/labs/`.
- [ ] **Branch `feat/study-resources`** criada e commitada com conteúdo canônico novo em inglês.
- [ ] **Branch `i18n/pt-br`** organizada sob `i18n/pt-BR/`.
- [ ] **`git push` realizado** para as branches concluídas no seu Fork `origin`.
- [ ] **Link compartilhado** com os colegas de estudo.
- [ ] **Issue e PRs abertos** no repositório `kengio/dp-800-study-guide`, um por vez e em ordem de dependência.

---

*Plano atualizado em 2026-07-25.*
