# Executable lab: SDK-style SQL Project

Prerequisites: .NET 8 SDK, SqlPackage, and a disposable database compatible
with the project's `DSP`.

From this folder:

```bash
dotnet build DatabaseProject.sqlproj -c Release
sqlpackage /Action:Script /SourceFile:bin/Release/DatabaseProject.dacpac \
  /TargetConnectionString:"<connection>" /OutputPath:planned.sql
sqlpackage /Action:Publish /SourceFile:bin/Release/DatabaseProject.dacpac \
  /TargetConnectionString:"<connection>" /p:BlockOnPossibleDataLoss=true
```

The `.sqlproj` automatically includes SQL files, while explicitly marking the
pre/post-deployment scripts so they are not treated as model objects.
