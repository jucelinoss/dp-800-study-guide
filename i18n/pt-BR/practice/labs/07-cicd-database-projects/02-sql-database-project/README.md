# Laboratório executável: SDK-style SQL Project

Pré-requisitos: .NET 8 SDK, SqlPackage e uma base descartável compatível com o
`DSP` do projeto.

Na pasta deste arquivo:

```bash
dotnet build DatabaseProject.sqlproj -c Release
sqlpackage /Action:Script /SourceFile:bin/Release/DatabaseProject.dacpac \
  /TargetConnectionString:"<conexao>" /OutputPath:planned.sql
sqlpackage /Action:Publish /SourceFile:bin/Release/DatabaseProject.dacpac \
  /TargetConnectionString:"<conexao>" /p:BlockOnPossibleDataLoss=true
```

Observe que o `.sqlproj` inclui automaticamente os arquivos SQL, mas marca os
scripts de pré e pós-implantação explicitamente para que não sejam tratados como
objetos do modelo.
