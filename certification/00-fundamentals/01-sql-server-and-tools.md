---
title: SQL Server and Query Tools
type: topic
tags: [sql-server, ssms, fundamentals]
---

# SQL Server and Query Tools

## Overview

SQL Server is the database engine that stores and processes data. A query tool sends T-SQL statements to that engine and shows the results.

> [!abstract]
>
> - Use SQL Server Developer Edition for free local learning.
> - Use SSMS on Windows; VS Code with the SQL Server extension is a cross-platform alternative.
> - A server connection and a database are different things.

> [!tip] What the Exam Tests
> DP-800 assumes you can distinguish SQL Server, Azure SQL, and Fabric SQL. This lesson only establishes local practice.

---

## Choose the right edition

An **edition** determines the features, capacity limits, and licence terms of the SQL Server engine. It is separate from SSMS: the same SSMS installation can connect to Express, Developer, or Enterprise.

| Edition | Cost and permitted use | Practical capability | Best fit in this guide |
| :--- | :--- | :--- | :--- |
| **Express** | Free; may be used for small production applications | Deliberately capacity-limited; no SQL Server Agent | Basic T-SQL practice and small demos |
| **Developer** | Free; development and test only, never production | Enterprise-level feature set for the matching release | Recommended local environment for the full DP-800 learning path |
| **Enterprise** | Paid; production use | Highest scale and enterprise production features | Real production workloads that require its features and are properly licensed |

### Express

Express is the smallest free edition. It is a good way to learn `SELECT`, JOINs, tables, constraints, and the `StudyDB` labs because the T-SQL language is the same. In SQL Server 2025, one Express instance is limited to the lesser of one socket or four cores, approximately 1.4 GB of buffer-pool memory, and 50 GB per relational database.

Those limits make Express unsuitable for realistic performance testing, larger datasets, and some DP-800 operational scenarios. It also does not include SQL Server Agent, so it cannot schedule jobs locally in the same way as higher editions. Express is free for production use within its licence, but "free" does not mean "unlimited."

### Developer

Developer is the best default for studying. Its purpose is to let developers and learners use the same feature set as Enterprise without buying a production licence. Use it on your own workstation, a disposable VM, or a test environment only.

> [!warning] Licence boundary
> Developer is functionally rich but its licence restricts it to development and testing. Do not run an application that serves real production users on Developer just because it is free.

SQL Server 2025 names this edition **Enterprise Developer**; it is functionally equivalent to the older **Developer** edition. SQL Server 2025 also introduced Standard Developer, which mirrors Standard rather than Enterprise. When a tutorial says "Developer edition," confirm the SQL Server version and the exact installer name.

### Enterprise

Enterprise is the paid production edition with the broadest scale and enterprise operational capabilities. It is appropriate when an organization needs Enterprise-only production features, high availability, or capacity beyond lower editions and has the necessary licence.

For learning, Enterprise itself is usually unnecessary: Developer gives you the compatible feature surface without a production licence. For production, the reverse is true: a Developer installation cannot be substituted for Enterprise.

### Decision guide

```text
Need a free local environment for the complete DP-800 path?
└── Choose Developer / Enterprise Developer.

Need a very small free app or only basic SQL practice?
└── Express is sufficient; account for its limits.

Deploying a real production workload needing Enterprise capabilities or scale?
└── Choose properly licensed Enterprise, after a workload and licensing review.
```

> [!note]
> Edition limits change by major SQL Server release. The limits above are for SQL Server 2025; consult the official comparison table before making a deployment or purchasing decision.

## Your first connection

Install a local SQL Server instance, then connect to it with SQL Server Management Studio (SSMS). In the connection dialog, use the server name chosen during installation and Windows Authentication unless you deliberately configured another method.

```sql
SELECT @@SERVERNAME AS server_name, DB_NAME() AS current_database;
```

> [!note]
> Azure Data Studio retired on February 28, 2026. Use SSMS or VS Code rather than adding it to a new setup.

## VS Code with the mssql extension

Visual Studio Code with the **SQL Server (mssql)** extension is a cross-platform alternative to SSMS. It is lighter and well suited for writing and running T-SQL scripts without managing a full IDE.

### Setup steps

1. Install [VS Code](https://code.visualstudio.com/).
2. Open the Extensions view (`Ctrl+Shift+X`) and search for **SQL Server (mssql)**.
3. Install the extension by Microsoft.
4. Press `Ctrl+Shift+P` and run **MS SQL: Connect** to create a connection profile.
5. Enter the server name, authentication type, and database (or leave blank for default).

```sql
-- Run this to verify the connection
SELECT @@SERVERNAME AS server_name, DB_NAME() AS current_database;
```

> [!tip]
> The mssql extension supports T-SQL IntelliSense, code snippets, and query execution with `Ctrl+Shift+E`. You can save `.sql` files and run them directly from the editor.

## SSMS productivity shortcuts

SSMS offers keyboard shortcuts that speed up everyday query work:

| Shortcut | Action |
| :--- | :--- |
| `F5` | Execute the current query or selection |
| `Ctrl+M` | Include actual execution plan with every query run |
| `Ctrl+L` | Display estimated execution plan (without running) |
| `Ctrl+R` | Show/hide the results pane |
| `Ctrl+Shift+U` | Uppercase selected text |
| `Ctrl+Shift+L` | Lowercase selected text |
| `Ctrl+K, Ctrl+C` | Comment selected lines |
| `Ctrl+K, Ctrl+U` | Uncomment selected lines |

> [!tip]
> Make `Ctrl+M` a habit during index and performance labs — seeing the plan alongside results builds your ability to read and compare execution strategies.

## Connection troubleshooting

The most common "cannot connect" errors and their fixes:

| Error message | Likely cause | Fix |
| :--- | :--- | :--- |
| `Cannot connect to <server>` | SQL Server service not running | Start the service in SQL Server Configuration Manager |
| `Login failed for user '...'` | Invalid credentials or disabled login | Verify username/password; check if Windows Authentication is expected |
| `Cannot open database "..." requested by the login` | Login has no permission or database missing | Verify database exists and user has `CONNECT` access |
| `The network path was not found` | Named pipes or TCP/IP not enabled | Enable TCP/IP in SQL Server Configuration Manager |
| `Connection timed out` | Firewall blocking port 1433 | Add an inbound rule for port 1433 (or the custom port) |
| `SSL Security error` | Certificate trust issue | Add `TrustServerCertificate=True` or `Encrypt=False` to the connection string for local dev |

```sql
-- Check if SQL Server is listening on the default port
SELECT DISTINCT local_tcp_port
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;
```

## Azure SQL differences

When connecting to Azure SQL Database (or Azure SQL Managed Instance), several connection details change from a local SQL Server instance:

| Aspect | Local SQL Server | Azure SQL Database |
| :--- | :--- | :--- |
| Server name | `localhost` or instance name | `<server>.database.windows.net` |
| Authentication | Windows Auth or SQL Auth | SQL Auth or Azure AD (Windows Auth not supported for direct connections) |
| Firewall | Controlled by Windows Firewall | Azure SQL firewall rules (IP-level); must add your client IP |
| `USE database` | Fully supported | Not supported — connect directly to the target database |
| Editions | Express, Developer, Standard, Enterprise | DTU-based (Basic, Standard, Premium) or vCore-based (General Purpose, Business Critical, Hyperscale) |

```sql
-- Azure SQL: check your current server and database
SELECT @@SERVERNAME AS server_name, DB_NAME() AS current_database;
```

> [!note]
> DP-800 covers Azure SQL integration in depth in later sections. For the fundamentals labs, a local SQL Server Developer Edition instance is the recommended environment.

## Use Cases

- Run the beginner labs locally without cloud cost.
- Test a query before adapting it for Azure SQL or Fabric.
- Select Developer for local DP-800 study when you need features unavailable or impractical in Express.

## Common Issues & Errors

> [!warning] Common Mistake
> Installing SSMS does not install the SQL Server database engine. They are separate downloads.

## Best Practices

- Keep sample work in `StudyDB`, never in `master`.
- Keep one query window per task and save useful scripts.

## Exam Tips

> [!tip] Exam Tips
> Tool choice is rarely the point of a DP-800 question; platform capability and security requirements are.

## Key Takeaways

- The engine stores data; the client tool connects to it.
- A connection can contain many databases.

## Related Topics

- [Relational model and data types](./02-relational-model-and-data-types.md)

## Official Documentation

- [Install SQL Server](https://learn.microsoft.com/sql/database-engine/install-windows/install-sql-server)
- [SQL Server Management Studio FAQ](https://learn.microsoft.com/ssms/faq)
- [SQL Server 2025 editions and supported features](https://learn.microsoft.com/sql/sql-server/editions-and-components-of-sql-server-2025)

---

**[← Previous](./fundamentals.md) | [↑ Back to Section](./fundamentals.md) | [Next →](./02-relational-model-and-data-types.md)**
