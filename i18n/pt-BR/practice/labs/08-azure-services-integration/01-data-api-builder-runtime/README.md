# Laboratório executável: Data API Builder

Execute primeiro o script SQL `01-data-api-builder-lab.sql` em uma base
descartável. Depois instale o DAB CLI conforme a documentação oficial e defina
`DATABASE_CONNECTION_STRING` sem gravar a senha no repositório.

## Instalar a CLI do DAB no Windows

A CLI do Data API Builder é distribuída como uma ferramenta global do .NET e
depende do SDK/runtime compatível com a versão instalada do DAB. Verifique
primeiro se o .NET está instalado:

```powershell
dotnet --version
```

Se o comando não for reconhecido, instale o [.NET](https://dotnet.microsoft.com/download/dotnet).
Com o .NET disponível, instale a CLI do DAB:

```powershell
dotnet tool install --global Microsoft.DataApiBuilder
```

Se a ferramenta já estiver instalada, atualize-a:

```powershell
dotnet tool update --global Microsoft.DataApiBuilder
```

Feche e abra o terminal novamente e confirme a instalação usando `--version`:

```powershell
dab --version
```

Se aparecer uma mensagem informando que um framework ou runtime não foi
encontrado, observe o nome e a versão exibidos no campo `Framework`. Isso
indica qual componente do .NET está faltando. Instale o SDK/runtime
correspondente pelo [site oficial do .NET](https://dotnet.microsoft.com/download/dotnet)
para Windows x64, feche e abra o PowerShell e confirme:

```powershell
dotnet --list-runtimes
dab --version
```

A lista deve conter o framework solicitado pela mensagem de erro. Diferentes
versões do .NET podem permanecer instaladas lado a lado.

No Windows, `DAB -V` não é o comando recomendado; use `dab --version`. Se o
comando ainda não for encontrado, adicione temporariamente o diretório das
ferramentas globais ao `PATH` da sessão atual:

```powershell
$env:Path += ";$env:USERPROFILE\.dotnet\tools"
dab --version
```

## Configurar uma conexão local/on-premises

Para testar com um SQL Server local/on-premises no Windows, abra o PowerShell
na pasta deste laboratório e defina a variável apenas para a sessão atual:

```powershell
$env:DATABASE_CONNECTION_STRING = "Server=localhost;Database=AdventureWorks2025;User Id=sa;Password=SUA_SENHA;TrustServerCertificate=True"
```

Para uma instância nomeada, como o SQL Server Express, use o nome da instância:

```powershell
$env:DATABASE_CONNECTION_STRING = "Server=localhost\SQLEXPRESS;Database=AdventureWorks2025;User Id=sa;Password=SUA_SENHA;TrustServerCertificate=True"
```

Se o SQL Server estiver configurado para autenticação integrada do Windows,
use:

```powershell
$env:DATABASE_CONNECTION_STRING = "Server=localhost;Database=AdventureWorks2025;Integrated Security=True;TrustServerCertificate=True"
```

Em seguida, confirme que a variável foi carregada e inicie o DAB:

```powershell
if ($env:DATABASE_CONNECTION_STRING) { "DATABASE_CONNECTION_STRING configurada" } else { "Variável não configurada" }
dab validate --config dab-config.json
dab start --config dab-config.json
```

O trecho `@env('DATABASE_CONNECTION_STRING')` do `dab-config.json` lê essa
variável do processo do DAB. Não é necessário alterar o JSON. Para manter a
variável entre sessões, é possível usar `setx`, mas isso grava a credencial no
perfil do Windows; para testes locais, prefira defini-la na sessão atual.

Com o runtime iniciado, abra `requests.http` no VS Code ou use `curl`. A view
deve responder em REST e GraphQL; a procedure deve aceitar um POST autenticado.

O lab SQL de `02-rest-graphql-endpoints` é outro assunto: ele pratica chamadas
de saída do banco para uma API externa com `sp_invoke_external_rest_endpoint`.
