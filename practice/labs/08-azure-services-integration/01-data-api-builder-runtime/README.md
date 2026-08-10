# Executable lab: Data API Builder

Run `01-data-api-builder-lab.sql` first against a disposable database. Install
the DAB CLI from the official documentation and set
`DATABASE_CONNECTION_STRING` without storing the password in the repository.

## Install the DAB CLI on Windows

The Data API builder CLI is distributed as a global .NET tool and depends on a
.NET SDK/runtime compatible with the installed DAB version. First check whether
.NET is installed:

```powershell
dotnet --version
```

If the command is not found, install [.NET](https://dotnet.microsoft.com/download/dotnet).
Then install the DAB CLI:

```powershell
dotnet tool install --global Microsoft.DataApiBuilder
```

If the tool is already installed, update it:

```powershell
dotnet tool update --global Microsoft.DataApiBuilder
```

Close and reopen the terminal, then verify the installation with `--version`:

```powershell
dab --version
```

If the output says that a framework or runtime could not be found, check the
name and version shown in the `Framework` field. This identifies the missing
.NET component. Install the corresponding SDK/runtime from the [official .NET
site](https://dotnet.microsoft.com/download/dotnet) for Windows x64, close and
reopen PowerShell, then verify:

```powershell
dotnet --list-runtimes
dab --version
```

The list should contain the framework requested by the error message. Different
.NET versions can remain installed side by side.

On Windows, use `dab --version` instead of `DAB -V`. If the command is still
not found, temporarily add the global tools directory to the current session's
`PATH`:

```powershell
$env:Path += ";$env:USERPROFILE\.dotnet\tools"
dab --version
```

## Configure a local/on-premises connection

From this folder:

```bash
dab validate --config dab-config.json
dab start --config dab-config.json
```

With the runtime running, open `requests.http` in VS Code or use `curl`. The
view should respond through REST and GraphQL; the procedure accepts an
authenticated POST.

The SQL lab `02-rest-graphql-endpoints` covers a different topic: outbound
database calls to an external API using `sp_invoke_external_rest_endpoint`.
