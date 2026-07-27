---
title: "SQL Server e Ferramentas de Consulta"
type: topic
tags: [sql-server, ssms, fundamentals]
---

# SQL Server e Ferramentas de Consulta

## Visão Geral

O SQL Server é o mecanismo de banco de dados que armazena e processa dados. Uma ferramenta de consulta envia instruções T-SQL para esse mecanismo e mostra os resultados.

> [!abstract]
>
> - Use a edição Developer do SQL Server para aprendizado local gratuito.
> - Use SSMS no Windows; VS Code com a extensão SQL Server é uma alternativa multiplataforma.
> - Uma conexão de servidor e um banco de dados são coisas diferentes.

> [!tip] O que o Exame Testa
> O DP-800 assume que você consegue distinguir SQL Server, Azure SQL e Fabric SQL. Esta lição apenas estabelece a prática local.

---

## Escolha a edição certa

Uma **edição** determina os recursos, limites de capacidade e termos de licença do mecanismo SQL Server. Ela é separada do SSMS: a mesma instalação do SSMS pode conectar-se a Express, Developer ou Enterprise.

| Edição | Custo e uso permitido | Capacidade prática | Melhor uso neste guia |
| :--- | :--- | :--- | :--- |
| **Express** | Gratuito; pode ser usado para pequenas aplicações de produção | Limitado intencionalmente; sem SQL Server Agent | Prática básica de T-SQL e demonstrações pequenas |
| **Developer** | Gratuito; apenas desenvolvimento e teste, nunca produção | Conjunto completo de recursos Enterprise para a versão correspondente | Ambiente local recomendado para todo o caminho DP-800 |
| **Enterprise** | Pago; uso em produção | Maior escala e recursos de produção Enterprise | Cargas de trabalho reais de produção que exigem seus recursos |

### Express

Express é a menor edição gratuita. É uma boa maneira de aprender `SELECT`, JOINs, tabelas, restrições e os laboratórios `StudyDB` porque a linguagem T-SQL é a mesma. No SQL Server 2025, uma instância Express é limitada a no máximo um soquete ou quatro núcleos, aproximadamente 1,4 GB de memória buffer-pool e 50 GB por banco de dados relacional.

Esses limites tornam o Express inadequado para testes de performance realistas, conjuntos de dados maiores e alguns cenários operacionais do DP-800. Ele também não inclui o SQL Server Agent, portanto não pode agendar tarefas localmente como as edições superiores. O Express é gratuito para uso em produção dentro de sua licença, mas "gratuito" não significa "ilimitado".

### Developer

Developer é o melhor padrão para estudo. Seu propósito é permitir que desenvolvedores e alunos usem o mesmo conjunto de recursos do Enterprise sem comprar uma licença de produção. Use-o em seu próprio computador, uma VM descartável ou ambiente de teste.

> [!warning] Limite de licença
> Developer é funcionalmente rico, mas sua licença o restringe a desenvolvimento e teste. Não execute uma aplicação que atenda usuários reais de produção no Developer apenas porque é gratuito.

O SQL Server 2025 nomeia esta edição como **Enterprise Developer**; ela é funcionalmente equivalente à edição **Developer** anterior. O SQL Server 2025 também introduziu o Standard Developer, que espelha o Standard em vez do Enterprise. Quando um tutorial disser "edição Developer", confirme a versão do SQL Server e o nome exato do instalador.

### Enterprise

Enterprise é a edição paga de produção com a maior escala e capacidades operacionais empresariais. É apropriada quando uma organização precisa de recursos exclusivos do Enterprise em produção, alta disponibilidade ou capacidade além das edições inferiores e possui a licença necessária.

Para aprendizado, o Enterprise geralmente é desnecessário: o Developer oferece a superfície de recursos compatível sem licença de produção. Para produção, o inverso é verdadeiro: uma instalação Developer não pode substituir o Enterprise.

### Guia de decisão

```text
Precisa de um ambiente local gratuito para todo o caminho DP-800?
└── Escolha Developer / Enterprise Developer.

Precisa de uma aplicação gratuita muito pequena ou apenas prática básica de SQL?
└── Express é suficiente; considere seus limites.

Implantando uma carga de trabalho real de produção que precisa de recursos ou escala Enterprise?
└── Escolha Enterprise devidamente licenciado, após revisão de carga de trabalho e licenciamento.
```

> [!note]
> Os limites de edição mudam a cada versão principal do SQL Server. Os limites acima são para SQL Server 2025; consulte a tabela comparativa oficial antes de tomar uma decisão de implantação ou compra.

## Sua primeira conexão

Instale uma instância local do SQL Server e conecte-se a ela com o SQL Server Management Studio (SSMS). Na caixa de diálogo de conexão, use o nome do servidor escolhido durante a instalação e a Autenticação do Windows, a menos que tenha configurado deliberadamente outro método.

```sql
SELECT @@SERVERNAME AS server_name, DB_NAME() AS current_database;
```

> [!note]
> O Azure Data Studio foi descontinuado em 28 de fevereiro de 2026. Use SSMS ou VS Code em vez de adicioná-lo a uma nova instalação.

## VS Code com a extensão mssql

O Visual Studio Code com a extensão **SQL Server (mssql)** é uma alternativa multiplataforma ao SSMS. É mais leve e adequado para escrever e executar scripts T-SQL sem gerenciar um IDE completo.

### Passos de configuração

1. Instale o [VS Code](https://code.visualstudio.com/).
2. Abra a visualização de Extensões (`Ctrl+Shift+X`) e procure por **SQL Server (mssql)**.
3. Instale a extensão da Microsoft.
4. Pressione `Ctrl+Shift+P` e execute **MS SQL: Connect** para criar um perfil de conexão.
5. Insira o nome do servidor, tipo de autenticação e banco de dados (ou deixe em branco para o padrão).

```sql
-- Execute para verificar a conexão
SELECT @@SERVERNAME AS server_name, DB_NAME() AS current_database;
```

> [!tip]
> A extensão mssql oferece suporte a IntelliSense T-SQL, snippets de código e execução de consultas com `Ctrl+Shift+E`. Você pode salvar arquivos `.sql` e executá-los diretamente do editor.

## Atalhos de produtividade do SSMS

O SSMS oferece atalhos de teclado que aceleram o trabalho diário com consultas:

| Atalho | Ação |
| :--- | :--- |
| `F5` | Executar a consulta ou seleção atual |
| `Ctrl+M` | Incluir plano de execução real em toda execução de consulta |
| `Ctrl+L` | Exibir plano de execução estimado (sem executar) |
| `Ctrl+R` | Mostrar/esconder o painel de resultados |
| `Ctrl+Shift+U` | Maiúsculas no texto selecionado |
| `Ctrl+Shift+L` | Minúsculas no texto selecionado |
| `Ctrl+K, Ctrl+C` | Comentar linhas selecionadas |
| `Ctrl+K, Ctrl+U` | Descomentar linhas selecionadas |

> [!tip]
> Torne o `Ctrl+M` um hábito durante os laboratórios de índice e performance — ver o plano junto com os resultados desenvolve sua capacidade de ler e comparar estratégias de execução.

## Solução de problemas de conexão

Os erros de "não é possível conectar" mais comuns e suas soluções:

| Mensagem de erro | Causa provável | Solução |
| :--- | :--- | :--- |
| `Cannot connect to <server>` | Serviço SQL Server não está em execução | Inicie o serviço no SQL Server Configuration Manager |
| `Login failed for user '...'` | Credenciais inválidas ou login desabilitado | Verifique usuário/senha; confirme se é esperada autenticação Windows |
| `Cannot open database "..." requested by the login` | Login sem permissão ou banco de dados ausente | Verifique se o banco existe e o usuário tem acesso `CONNECT` |
| `The network path was not found` | Named pipes ou TCP/IP não habilitados | Habilite TCP/IP no SQL Server Configuration Manager |
| `Connection timed out` | Firewall bloqueando a porta 1433 | Adicione uma regra de entrada para a porta 1433 (ou porta personalizada) |
| `SSL Security error` | Problema de confiança do certificado | Adicione `TrustServerCertificate=True` ou `Encrypt=False` à string de conexão para desenvolvimento local |

```sql
-- Verifique se o SQL Server está ouvindo na porta padrão
SELECT DISTINCT local_tcp_port
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;
```

## Diferenças do Azure SQL

Ao conectar-se ao Azure SQL Database (ou Azure SQL Managed Instance), vários detalhes de conexão mudam em relação a uma instância local do SQL Server:

| Aspecto | SQL Server Local | Azure SQL Database |
| :--- | :--- | :--- |
| Nome do servidor | `localhost` ou nome da instância | `<servidor>.database.windows.net` |
| Autenticação | Autenticação Windows ou SQL | SQL Auth ou Azure AD (Windows Auth não é suportado) |
| Firewall | Controlado pelo Firewall do Windows | Regras de firewall do Azure SQL (nível IP); deve adicionar seu IP |
| `USE database` | Totalmente suportado | Não suportado — conecte-se diretamente ao banco alvo |
| Edições | Express, Developer, Standard, Enterprise | Baseadas em DTU (Basic, Standard, Premium) ou vCore (General Purpose, Business Critical, Hyperscale) |

```sql
-- Azure SQL: verifique seu servidor e banco de dados atuais
SELECT @@SERVERNAME AS server_name, DB_NAME() AS current_database;
```

> [!note]
> O DP-800 cobre a integração com Azure SQL em profundidade nas seções seguintes. Para os laboratórios de fundamentos, uma instância local do SQL Server Developer Edition é o ambiente recomendado.

## Casos de Uso

- Execute os laboratórios iniciantes localmente sem custo de nuvem.
- Teste uma consulta antes de adaptá-la para Azure SQL ou Fabric.
- Selecione Developer para estudo local do DP-800 quando precisar de recursos indisponíveis ou impraticáveis no Express.

## Problemas Comuns & Erros

> [!warning] Erro Comum
> Instalar o SSMS não instala o mecanismo de banco de dados SQL Server. São downloads separados.

## Melhores Práticas

- Mantenha o trabalho de aprendizado no `StudyDB`, nunca em `master`.
- Mantenha uma janela de consulta por tarefa e salve scripts úteis.

## Dicas para o Exame

> [!tip] Dicas para o Exame
> A escolha da ferramenta raramente é o ponto central de uma questão DP-800; os requisitos de plataforma e segurança são.

## Principais Conclusões

- O mecanismo armazena dados; a ferramenta cliente conecta-se a ele.
- Uma conexão pode conter muitos bancos de dados.

## Tópicos Relacionados

- [Modelo relacional e tipos de dados](./02-relational-model-and-data-types.md)

## Documentação Oficial

- [Instalar SQL Server](https://learn.microsoft.com/sql/database-engine/install-windows/install-sql-server)
- [FAQ do SQL Server Management Studio](https://learn.microsoft.com/ssms/faq)
- [Edições do SQL Server 2025 e recursos suportados](https://learn.microsoft.com/sql/sql-server/editions-and-components-of-sql-server-2025)

---

**[← Anterior](./fundamentals.md) | [↑ Voltar à Seção](./fundamentals.md) | [Próximo →](./02-relational-model-and-data-types.md)**
