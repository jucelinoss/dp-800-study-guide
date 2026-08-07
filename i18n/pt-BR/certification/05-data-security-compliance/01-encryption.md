---
title: Criptografia de Dados (Data Encryption)
type: study-material
tags:
  - dp-800
  - encryption
  - always-encrypted
  - column-encryption
  - tde
---

> [!info] 🗺️ Índice de Navegação Rápida
> 
> - 📍 [1. Visão Geral (Overview)](#visão-geral-overview)
> - 📍 [2. Criptografia de Dados Transparente (TDE)](#criptografia-de-dados-transparente-tde)
> - 📍 [3. Always Encrypted](#always-encrypted)
>   - 🔹 [Hierarquia de Chaves](#hierarquia-de-chaves)
>   - 🔹 [O que é a CMK (Column Master Key)?](#o-que-é-a-cmk-column-master-key)
>   - 🔹 [O que é a "Busca de CMK" (CMK Retrieval)?](#o-que-é-a-busca-de-cmk-cmk-retrieval)
>   - 🔹 [Configurando Always Encrypted via DDL](#configurando-always-encrypted-via-ddl)
>   - 🔹 [Tipos de Criptografia no Always Encrypted](#tipos-de-criptografia-no-always-encrypted)
>   - 🔹 [Executando Consultas em Colunas Criptografadas](#executando-consultas-em-colunas-criptografadas)
> - 📍 [4. Always Encrypted com Secure Enclaves (Enclaves Seguros)](#always-encrypted-com-secure-enclaves-enclaves-seguros)
>   - 🔹 [Limitações do Always Encrypted Padrão](#limitações-do-always-encrypted-padrão)
>   - 🔹 [A Solução: Enclaves Seguros (Secure Enclaves)](#a-solução-enclaves-seguros-secure-enclaves)
>   - 🔹 [Tecnologias de Enclave Suportadas](#tecnologias-de-enclave-suportadas)
>   - 🔹 [Mecanismo de Atestação (Attestation)](#mecanismo-de-atestação-attestation)
>   - 🔹 [Operações Suportadas por Enclaves Seguros](#operações-suportadas-por-enclaves-seguros)
>   - 🔹 [Requisitos da String de Conexão com Enclave](#requisitos-da-string-de-conexão-com-enclave)
>   - 🔹 [Exemplo de Configuração DDL e Consulta com Enclave](#exemplo-de-configuração-ddl-e-consulta-com-enclave)
>   - 🔹 [Comparativo: Always Encrypted Padrão vs Secure Enclaves](#comparativo-always-encrypted-padrão-vs-secure-enclaves)
> - 📍 [5. Processos de Rotação de Chaves (Key Rotation Procedures)](#processos-de-rotação-de-chaves-key-rotation-procedures)
>   - 🔹 [Por que Rotacionar Chaves](#por-que-rotacionar-chaves)
>   - 🔹 [Rotação de Column Master Key (CMK)](#rotação-de-column-master-key-cmk)
>   - 🔹 [Rotação de Column Encryption Key (CEK)](#rotação-de-column-encryption-key-cek)
>   - 🔹 [Ferramentas de Apoio](#ferramentas-de-apoio)
>   - 🔹 [Script DDL de Metadados de Rotação de Chave Mestrada](#script-ddl-de-metadados-de-rotação-de-chave-mestrada)
> - 📍 [6. Backup de Certificados do TDE (TDE Certificate Backup)](#backup-de-certificados-do-tde-tde-certificate-backup)
> - 📍 [7. Criptografia Manual no Lado do Servidor (Server-Side Column Encryption)](#criptografia-manual-no-lado-do-servidor-server-side-column-encryption)
> - 📍 [8. Tabela Comparativa de Métodos de Criptografia](#tabela-comparativa-de-métodos-de-criptografia)
> - 📍 [9. Casos de Uso (Use Cases)](#casos-de-uso-use-cases)
> - 📍 [10. Problemas Comuns e Soluções (Common Issues)](#problemas-comuns-e-soluções-common-issues)
> - 📍 [11. Dicas para o Exame (Exam Tips)](#dicas-para-o-exame-exam-tips)
> - 📍 [12. Resumo dos Conceitos (Key Takeaways)](#resumo-dos-conceitos-key-takeaways)
> - 📍 [13. Questões de Prática (Practice Questions)](#questões-de-prática-practice-questions)
> - 📍 [14. Tópicos Relacionados](#tópicos-relacionados)
> - 📍 [15. Documentação Oficial](#documentação-oficial)

---

# Criptografia de Dados (Data Encryption)

## Visão Geral (Overview)

O SQL Server oferece múltiplas camadas de proteção por criptografia: Criptografia de Dados Transparente (TDE - Transparent Data Encryption) para dados em repouso (at rest), Always Encrypted para criptografia em nível de coluna no lado do cliente (client-side) e criptografia manual em nível de coluna usando chaves simétricas e certificados.

> [!abstract]
>
> - Cobre TDE (proteção em disco para todo o banco), Always Encrypted (criptografia em nível de coluna na ponta do cliente) e criptografia manual de colunas via T-SQL.
> - Os três métodos de criptografia diferem no modelo de ameaça: de quem ou de qual vazamento físico as informações estão sendo protegidas.
> - Tópicos chave do exame: qual método de criptografia indicar para cada cenário, hierarquia de chaves CMK/CEK e o comportamento do TDE ativo por padrão no Azure SQL.

> [!tip] O que o Exame Testa
>
> - **TDE**: Protege arquivos em disco e backups contra roubo físico; o servidor SQL lê o dado descriptografado em memória; dispensa alterações no código da aplicação; ativado por padrão no Azure SQL.
> - **Always Encrypted**: O servidor SQL **nunca** vê o dado descriptografado. A chave mestra (CMK) reside na ponta do cliente (no Azure Key Vault ou Windows Cert Store). O driver cliente criptografa e descriptografa os dados de forma transparente; a aplicação exige drivers compatíveis com Always Encrypted.
> - **Criptografia manual de coluna** (`ENCRYPTBYKEY`): Exige chamadas manuais via código ou T-SQL; o servidor SQL consegue ver dados em texto plano; oferece maior flexibilidade de lógica mas exige maior esforço de desenvolvimento.

---

## Criptografia de Dados Transparente (TDE)

O TDE criptografa fisicamente os arquivos do banco de dados no disco rígido — transparente para as aplicações, sem necessidade de alterações no código.

```sql
-- Ativar TDE localmente (O Azure SQL já possui o TDE ativo por padrão)
USE master;
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssword123!';

CREATE CERTIFICATE TDECert
WITH SUBJECT = 'TDE Certificate';

USE MyDatabase;
CREATE DATABASE ENCRYPTION KEY
WITH ALGORITHM = AES_256
ENCRYPTION BY SERVER CERTIFICATE TDECert;

ALTER DATABASE MyDatabase SET ENCRYPTION ON;

-- Consultar estado do TDE nas bases
SELECT db_name(database_id) AS DatabaseName,
       encryption_state_desc,
       key_algorithm,
       key_length
FROM sys.dm_database_encryption_keys;
```

> [!important] TDE Protege Apenas Dados em Repouso (At Rest)
>
> - O **TDE** criptografa fisicamente os arquivos de banco de dados (`.mdf`, `.ldf`) e arquivos de backup em disco.
> - **Cuidado de Exame**: O TDE **não** protege os dados contra usuários conectados que possuem permissões de `SELECT`. Se um usuário tem permissão de leitura, o SQL Server descriptografa a página em memória e devolve o dado em texto plano.

**Estados de criptografia do TDE (encryption states):**

| Estado (State) | Descrição |
| :--- | :--- |
| 0 | Sem chave DEK criada; banco descriptografado |
| 1 | Chave DEK existe mas a criptografia não foi ativada |
| 2 | Criptografia em andamento |
| 3 | Banco criptografado |
| 4 | Troca de chave em andamento |
| 5 | Descriptografia em andamento |

> Azure SQL Database e Azure SQL Managed Instance possuem TDE habilitado por padrão em todos os novos bancos criados.

---

## Always Encrypted

O **Always Encrypted** criptografa as informações no lado do cliente (client-side) — o motor do banco de dados SQL recebe e armazena apenas dados criptografados (ciphertext), nunca vendo o texto plano. Isso protege informações críticas contra DBAs, administradores de infraestrutura e operadores de nuvem.

### Hierarquia de Chaves

```text
Column Master Key (CMK)
└── Column Encryption Key (CEK)
    └── Dados criptografados da coluna (Encrypted column data)
```

### O que é a CMK (Column Master Key)?

A **CMK (Column Master Key)** é uma **chave mestra de proteção** (Key-Protecting Key) mantida em um cofre externo confiável (como **Azure Key Vault** ou **Windows Certificate Store**).

#### 🎯 Qual é o papel da CMK?
- A CMK **NÃO criptografa os dados das linhas da tabela diretamente**.
- A única função da CMK é **criptografar e proteger a CEK (Column Encryption Key)**.

#### 💡 Por que o Always Encrypted usa 2 chaves (CMK + CEK)?
Se a aplicação tivesse que chamar o Azure Key Vault para criptografar/descriptografar cada registro de uma tabela, uma consulta de 10.000 linhas causaria 10.000 requisições de rede ao Key Vault, tornando a aplicação extremamente lenta.

Para resolver isso, o Always Encrypted divide as responsabilidades em duas chaves:
1. **CEK (Column Encryption Key):** É uma chave simétrica rápida (AES-256) usada para cifrar os dados reais das colunas. A CEK é armazenada dentro do banco de dados, porém em formato criptografado.
2. **CMK (Column Master Key):** É a chave mestra que protege a CEK. O driver da aplicação acessa o repositório da CMK quando precisa obter ou usar a chave, normalmente aproveitando cache da CEK para evitar uma chamada por registro. A partir daí, o driver usa a CEK local para cifrar/decifrar os dados.

#### 📍 Comparativo: CMK vs CEK

| Chave | Nome | Onde Fica Armazenada? | O que Ela Criptografa? | Quem tem Acesso? |
| :--- | :--- | :--- | :--- | :--- |
| **CMK** | Column Master Key | External Key Store (**Azure Key Vault** / Cert Store) | Apenas a **CEK** | Apenas a Aplicação Cliente |
| **CEK** | Column Encryption Key | **Banco de Dados** (em formato cifrado) | Os **Dados das Colunas** (`SSN`, `Salário`, etc.) | Driver decifra na RAM do cliente |

> [!tip] Divisão de Responsabilidade de Chaves no Always Encrypted
>
> - **Column Encryption Key (CEK)**: Fica armazenada de forma criptografada no banco de dados (o banco não possui a chave para descriptografá-la).
> - **Column Master Key (CMK)**: Fica guardada em um repositório confiável externo (como Azure Key Vault ou Windows Certificate Store). O banco de dados **nunca** tem acesso à CMK. Apenas o driver do cliente recupera a CMK para descriptografar a CEK na máquina do cliente.

### O que é a "Busca de CMK" (CMK Retrieval)?

A **"Busca da CMK"** (representada no diagrama do Always Encrypted) é o processo no qual o **driver SQL do cliente** se conecta ao cofre externo para obter permissão/chave para decifrar dados.

**Como funciona o fluxo passo a passo:**

1. **Consulta aos Metadados do Banco:** Quando a aplicação dispara um comando SQL em uma tabela criptografada, o driver cliente consulta as visões de sistema do SQL Server (`sys.column_master_keys` e `sys.column_encryption_keys`). O banco retorna apenas os **metadados** (ex.: a URL do Azure Key Vault e o valor cifrado da CEK).
2. **Conexão Direta com o Cofre de Chaves (Busca CMK):** O driver do cliente (usando a identidade da aplicação via Azure AD / Managed Identity) autentica-se diretamente no **Azure Key Vault** (ou acessa o Windows Certificate Store local) e solicita acesso à **CMK (Column Master Key)**.
3. **Descriptografia Local da CEK:** De posse da CMK, o driver descriptografa a **CEK (Column Encryption Key)** e mantém o valor da CEK em memória do processo cliente enquanto necessário.
4. **Criptografia dos Parâmetros e Leitura:**
   - Ao **enviar dados**, o driver usa a CEK para criptografar os parâmetros (`WHERE SSN = '...'`) antes de trafegar pela rede.
   - Ao **receber dados**, o driver usa a CEK em memória para converter os bytes criptografados (*ciphertext*) retornados pelo SQL Server em texto plano para a aplicação.

> [!important] Ponto Fundamental para a Prova DP-800
> O **SQL Server NUNCA faz a busca da CMK** e **NUNCA acessa o Azure Key Vault**. Toda a autenticação no cofre e o download/uso da CMK são executados exclusivamente pelo **driver da aplicação cliente**. O servidor SQL armazena e enxerga apenas o *ciphertext* (dado trancado).

### Configurando Always Encrypted via DDL

```sql
-- Passo 1: Criar o ponteiro para a Column Master Key (chave salva no Azure Key Vault)
CREATE COLUMN MASTER KEY MyCMK
WITH (
    KEY_STORE_PROVIDER_NAME = 'AZURE_KEY_VAULT',
    KEY_PATH = 'https://mykeyvault.vault.azure.net/keys/MyCMKKey/version'
);

-- Passo 2: Criar a Column Encryption Key
CREATE COLUMN ENCRYPTION KEY MyCEK
WITH VALUES (
    COLUMN_MASTER_KEY = MyCMK,
    ALGORITHM = 'RSA_OAEP',
    ENCRYPTED_VALUE = 0x01700000... -- valor criptografado gerado pela chave mestre
);

-- Passo 3: Criar tabela com colunas criptografadas
CREATE TABLE dbo.Patients (
    PatientId   int             NOT NULL PRIMARY KEY,
    -- DETERMINISTIC: permite buscas por igualdade (=, IN, JOIN)
    SSN         char(11)        COLLATE Latin1_General_BIN2
                                ENCRYPTED WITH (
                                    COLUMN_ENCRYPTION_KEY = MyCEK,
                                    ENCRYPTION_TYPE = DETERMINISTIC,
                                    ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
                                ) NOT NULL,
    -- RANDOMIZED: maior nível de segurança; não aceita nenhuma operação de igualdade
    Salary      money           ENCRYPTED WITH (
                                    COLUMN_ENCRYPTION_KEY = MyCEK,
                                    ENCRYPTION_TYPE = RANDOMIZED,
                                    ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
                                ) NULL
);
```

### Tipos de Criptografia no Always Encrypted

| Tipo | Operações Permitidas | Nível de Segurança |
| :--- | :--- | :--- |
| **DETERMINISTIC** | `=`, `IN`, `JOIN`, `GROUP BY` | Menor (mesmo dado plano gera sempre a mesma string criptografada). |
| **RANDOMIZED** | Sem enclave, não permite consultas confidenciais; com enclave e chave habilitada para enclave, permite operações adicionais como comparações, `BETWEEN`, `IN` e `LIKE`. | `Máximo (o mesmo valor de entrada gera strings criptografadas distintas)`. |

> [!warning] Erro Comum
> Não confunda TDE com Always Encrypted no exame. No TDE, o servidor SQL **descriptografa** os dados para rodar queries. No Always Encrypted, o servidor SQL **nunca** vê o dado descriptografado (a conversão ocorre estritamente no driver cliente). O divisor de águas nas questões é a necessidade de impedir que o administrador do banco (DBA) consiga visualizar dados sensíveis de clientes.

> [!note] Modelo Mental — Always Encrypted
> Imagine o Always Encrypted como o envio de uma **pasta trancada** para o seu DBA. Ele cuida do armazenamento da pasta (coluna criptografada), mas a chave física (CMK) está segura em seu Azure Key Vault ou repositório local. Apenas o driver cliente consegue destrancar a pasta usando a CMK; o banco armazena apenas o material criptografado. A criptografia **DETERMINISTIC** é como usar a mesma tranca para valores iguais, permitindo algumas operações baseadas em igualdade, como `=` e `JOIN`, conforme os recursos suportados. A criptografia **RANDOMIZED** altera o resultado a cada valor criptografado, dificultando correlação por igualdade no banco de dados.

---

### Executando Consultas em Colunas Criptografadas

O cliente que envia a consulta deve possuir acesso à CMK no Key Vault e habilitar o parâmetro correspondente em sua string de conexão:

```csharp
// String de conexão .NET configurada para Always Encrypted
"Server=...;Database=...;Column Encryption Setting=enabled;Authentication=Active Directory Integrated;"
```

```sql
-- Consultas T-SQL diretas sem driver configurado falharão em colunas Always Encrypted
-- A query abaixo exige execução a partir de cliente autorizado:
SELECT * FROM dbo.Patients WHERE SSN = '123-45-6789'; -- Funciona apenas com DETERMINISTIC
```

---

## Always Encrypted com Secure Enclaves (Enclaves Seguros)

### Limitações do Always Encrypted Padrão

O Always Encrypted padrão (apenas no lado do cliente) limita consideravelmente a flexibilidade de desenvolvimento:
* Colunas criptografadas suportam apenas filtros de igualdade (`=`, `IN`) se configuradas com o tipo **DETERMINISTIC**.
* Colunas configuradas com criptografia **RANDOMIZED** não suportam nenhum tipo de filtro ou pesquisa T-SQL.
* Consultas de intervalo (`<`, `>`, `BETWEEN`), ordenação (`ORDER BY`), pesquisas textuais parciais (`LIKE`) e alterações de esquema *in-place* falham, pois o motor do banco de dados não possui acesso aos dados em texto plano.

---

### A Solução: Enclaves Seguros (Secure Enclaves)

Um **Secure Enclave** é uma região de memória isolada e criptografada (sandbox) dentro do processo do SQL Server que atua como um **TEE (Trusted Execution Environment)**. O enclave permite que o SQL Server realize computações complexas em dados sensíveis sem expor o texto plano ao restante do motor do banco de dados, ao sistema operacional, ao hipervisor ou a usuários privilegiados (como DBAs e administradores `sysadmin`).

```mermaid
flowchart LR
    subgraph CLIENT[" "]
        direction TB
        T1["<b>Cliente & Driver</b>"]
        APP["App / Driver SQL"]
        AKV[("Azure Key Vault<br/>(CMK)")]
        ATT["Serviço de Atestação<br/>(HGS / Azure Attestation)"]
        T1 --> APP
        APP -->|"1. Valida Enclave"| ATT
        APP -->|"2. Busca CMK"| AKV
    end

    subgraph ENGINE[" "]
        direction TB
        T2["<b>SQL Server Engine</b>"]
        STORAGE[("Tabelas Criptografadas<br/>(Ciphertext em Disco)")]
        T2 --> STORAGE
    end

    subgraph ENCLAVE[" "]
        direction TB
        T3["<b>Secure Enclave (TEE)</b>"]
        MEM["Memória Isolada<br/>(Processa LIKE/BETWEEN/ALTER)"]
        T3 --> MEM
    end

    CLIENT -->|"3. Query + CEK Segura"| ENGINE
    ENGINE -->|"4. Delega cálculo"| ENCLAVE
    ENCLAVE -->|"5. Retorna IDs filtrados"| ENGINE
    ENGINE -->|"6. Retorna resultado"| CLIENT
```

---

### Tecnologias de Enclave Suportadas

1. **VBS (Virtualization-based Security Enclaves):**
   * **Implementação:** Isolamento de memória baseado em software e hipervisor (Hyper-V). Suportado no SQL Server 2019+ (Windows Server 2019+ / Windows 10/11) e no **Azure SQL Database**.
   * **Vantagem:** Dispensam hardware especial na CPU. Facilidade de implantação e menor custo de infraestrutura.
2. **Intel SGX (Software Guard Extensions):**
   * **Implementação:** Enclave baseado em instruções dedicadas de hardware da CPU Intel.
   * **Vantagem:** Nível máximo de isolamento garantido por hardware. Suportado no SQL Server 2019+ e configurações de hardware específicas.

---

### Mecanismo de Atestação (Attestation)

Antes de enviar a chave de criptografia de coluna (CEK) para o enclave, o driver da aplicação cliente executa o protocolo de **Atestação (Attestation)** para verificar cryptographicamente a integridade do enclave e garantir que ele é autêntico e não foi modificado:

* **Host Guardian Service (HGS):** Utilizado em ambientes *on-premises* ou VMs IaaS com SQL Server.
* **Microsoft Azure Attestation (MAA):** Utilizado nativamente no **Azure SQL Database** e serviços PaaS da Microsoft.

---

### Operações Suportadas por Enclaves Seguros

* **Consultas de Intervalo:** `<`, `>`, `<=`, `>=`, `BETWEEN`.
* **Filtros por Padrão de Texto:** `LIKE`, `IN`.
* **Ordenação e Agrupamentos:** `ORDER BY`, `GROUP BY` em colunas criptografadas de forma randômica (`RANDOMIZED`).
* **Criptografia In-Place (Online):** Permite alterar tipos de criptografia ou adicionar chaves via `ALTER TABLE ... ALTER COLUMN ... ENCRYPTED WITH (...)` diretamente no servidor, sem necessidade de baixar terabytes de dados para o cliente.

---

### Requisitos da String de Conexão com Enclave

O driver cliente (.NET, JDBC, ODBC, etc.) precisa especificar que deseja utilizar o enclave e indicar o serviço de atestação:

```text
Column Encryption Setting=Enabled; Attestation Protocol=HGS; Enclave Attestation Url=https://hgs.domain.com/Attestation;
```
*(Nota: No Azure SQL Database com VBS, o provedor de atestação do Azure gerencia os parâmetros de URL e protocolo de forma transparente).*

---

### Exemplo de Configuração DDL e Consulta com Enclave

```sql
-- 1. Registrar a Column Master Key habilitando suporte a enclave (ENCLAVE_COMPUTATIONS)
CREATE COLUMN MASTER KEY MyEnclaveCMK
WITH (
    KEY_STORE_PROVIDER_NAME = 'AZURE_KEY_VAULT',
    KEY_PATH = 'https://mykeyvault.vault.azure.net/keys/MyEnclaveCMK/version',
    ENCLAVE_COMPUTATIONS (SIGNATURE = 0x123456...) -- Assinatura validada pelo serviço de atestação
);

-- 2. Consulta filtrando intervalos e padrão textual em coluna RANDOMIZED via Enclave
SELECT PatientID, Name, SSN
FROM dbo.Patients
WHERE Age BETWEEN 30 AND 50
  AND SSN LIKE '123%'; -- Executa de forma transparente dentro do Secure Enclave

-- 3. Criptografia in-place ativa e online no servidor SQL via Enclave
ALTER TABLE dbo.Patients
ALTER COLUMN SSN NVARCHAR(11) ENCRYPTED WITH (
    ENCRYPTION_TYPE = RANDOMIZED,
    ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256',
    COLUMN_ENCRYPTION_KEY = EnclaveCEK
) WITH (ONLINE = ON);
```

---

### Comparativo: Always Encrypted Padrão vs Secure Enclaves

| Característica | Always Encrypted Padrão | Always Encrypted com Secure Enclaves |
| :--- | :--- | :--- |
| **Local de Descriptografia** | Estritamente na aplicação cliente | Aplicação cliente + RAM Isolada do Enclave |
| **Filtro `=` em DETERMINISTIC** | ✅ Suportado | ✅ Suportado |
| **Filtros `<`, `>`, `BETWEEN`** | ❌ Não suportado | ✅ Suportado (em DETERMINISTIC e RANDOMIZED) |
| **Busca Parcial (`LIKE`)** | ❌ Não suportado | ✅ Suportado |
| **Criptografia In-Place (`ALTER`)** | ❌ Exige download de dados no cliente | ✅ Processado online no próprio servidor SQL |
| **Requisito de Infraestrutura** | Apenas driver cliente atualizado | VBS (Hyper-V) ou Intel SGX + Serviço de Atestação |

> [!important] Ponto-Chave para a Prova DP-800
> Se o enunciado solicitar proteção total contra DBAs **E** exigir suporte a filtros de intervalo (`BETWEEN`, `>`, `<`), busca parcial (`LIKE`) ou alteração de criptografia online sem mover dados pela rede, a solução **obrigatoriamente** deve ser **Always Encrypted com Secure Enclaves**. Se exigir apenas busca por igualdade exata (`=`) com menor complexidade, o **Always Encrypted Padrão (Deterministic)** é suficiente.

---

## Processos de Rotação de Chaves (Key Rotation Procedures)

### Por que Rotacionar Chaves

- Requisitos regulatórios e políticas internas de conformidade.
- Suspeita de vazamento físico ou comprometimento da chave mestra (CMK).
- Desligamento de funcionários com privilégios de acesso ao Key Vault.

### Rotação de Column Master Key (CMK)

A rotação de CMK atua apenas nos metadados de criptografia e pode ser coordenada de forma online:

1. Gere uma nova CMK no Azure Key Vault.
2. Adicione o novo ponteiro de CMK no SQL Server.
3. Re-criptografe a chave de criptografia de coluna (CEK) usando a nova CMK.
4. Desassocie a chave antiga (Old CMK) da estrutura da CEK.
5. Remova os metadados da CMK antiga do banco de dados.

### Rotação de Column Encryption Key (CEK)

A rotação de CEK exige processamento pesado, pois obriga a descriptografar e re-criptografar fisicamente os dados das colunas com a nova chave.

### Ferramentas de Apoio

- **SSMS**: Clique com o botão direito nas pastas de chaves no Object Explorer > Rotate.
- **PowerShell**: Cmdlets `Invoke-SqlColumnMasterKeyRotation` e `Complete-SqlColumnMasterKeyRotation`.

### Script DDL de Metadados de Rotação de Chave Mestrada

```sql
-- Passo 1: Registrar a nova chave mestra do Key Vault (NewCMK)
CREATE COLUMN MASTER KEY NewCMK
WITH (KEY_STORE_PROVIDER_NAME = 'AZURE_KEY_VAULT',
      KEY_PATH = 'https://mykeyvault.vault.azure.net/keys/NewCMK/version2');

-- Passo 2: Associar a CEK atual com a nova CMK gerada
-- O novo encrypted_value é computado pelo SSMS com acesso a ambos os cofres
ALTER COLUMN ENCRYPTION KEY MyCEK
ADD VALUE (COLUMN_MASTER_KEY = NewCMK,
           ALGORITHM = 'RSA_OAEP',
           ENCRYPTED_VALUE = 0x...);

-- Passo 3: Remover a associação da CEK frente à chave antiga (OldCMK)
ALTER COLUMN ENCRYPTION KEY MyCEK
DROP VALUE (COLUMN_MASTER_KEY = OldCMK);

-- Passo 4: Dropar os metadados da chave antiga
DROP COLUMN MASTER KEY OldCMK;
```

---

## Backup de Certificados do TDE (TDE Certificate Backup)

Realizar backups consistentes dos certificados associados ao TDE é crítico. Se o certificado original do servidor for perdido, os arquivos e backups do banco criptografados sob ele tornam-se completamente ilegíveis.

- Salve o arquivo do certificado e a chave privada em cofres off-site seguros.
- No SQL Server clássico e no Managed Instance, utilize o comando `BACKUP CERTIFICATE`.
- No Azure SQL Database, os certificados do TDE são gerenciados por padrão pela Microsoft, ou você pode utilizar uma chave própria (BYOK — Bring Your Own Key) via Azure Key Vault.

```sql
-- Executar backup do certificado do TDE (SQL Server e SQL MI)
BACKUP CERTIFICATE TDECert
TO FILE = 'C:\Backup\TDECert.cer'
WITH PRIVATE KEY (
    FILE = 'C:\Backup\TDECert_pk.pvk',
    ENCRYPTION BY PASSWORD = 'StrongBk*pPassword1!'
);
```

---

## Criptografia Manual no Lado do Servidor (Server-Side Column Encryption)

Para cenários mais simples, você pode implementar funções nativas como `ENCRYPTBYKEY` e `DECRYPTBYKEY` associadas a certificados locais:

```sql
-- Criar chave simétrica
CREATE SYMMETRIC KEY MySymKey
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE MyCert;

-- Criptografar dados na tabela
OPEN SYMMETRIC KEY MySymKey DECRYPTION BY CERTIFICATE MyCert;

UPDATE dbo.Users
SET EncryptedPhone = ENCRYPTBYKEY(KEY_GUID('MySymKey'), Phone);

CLOSE SYMMETRIC KEY MySymKey;

-- Descriptografar e ler os dados planos
OPEN SYMMETRIC KEY MySymKey DECRYPTION BY CERTIFICATE MyCert;
SELECT CONVERT(nvarchar(50), DECRYPTBYKEY(EncryptedPhone)) AS Phone
FROM dbo.Users;
CLOSE SYMMETRIC KEY MySymKey;
```

---

## Tabela Comparativa de Métodos de Criptografia

![Comparativo Ilustrado dos Métodos de Criptografia no SQL Server](./images/sql_server_encryption_types_comparison.png)

```mermaid
flowchart TD
    subgraph TDE[" "]
        direction TB
        T1["<b>TDE (Data at Rest)</b>"]
        App1["Aplicação"]
        Eng1["SQL Engine (RAM)<br/><i>Descriptografa em memória</i>"]
        Disk1[("Disco / Backup<br/><b>Criptografado</b>")]
        T1 --> App1 -->|"Texto Plano"| Eng1 -->|"Criptografa"| Disk1
    end

    subgraph AE[" "]
        direction TB
        A1["<b>Always Encrypted</b>"]
        App2["App + Driver SQL<br/><b>Decifra no Cliente</b>"]
        Eng2["SQL Engine<br/><i>Nunca vê dado plano</i>"]
        Disk2[("Disco / Coluna<br/><b>Ciphertext</b>")]
        A1 --> App2 -->|"Ciphertext"| Eng2 --> Disk2
    end

    subgraph AEE[" "]
        direction TB
        E1["<b>AE + Secure Enclave</b>"]
        App3["App + Driver SQL"]
        Eng3["SQL Engine"]
        Enc3["Enclave VBS (RAM)<br/><b>Processa BETWEEN/LIKE</b>"]
        Disk3[("Disco / Coluna<br/><b>Ciphertext</b>")]
        E1 --> App3 -->|"Ciphertext"| Eng3
        Eng3 <--> Enc3
        Eng3 --> Disk3
    end

    subgraph MAN[" "]
        direction TB
        M1["<b>Criptografia Manual</b>"]
        App4["Aplicação"]
        Eng4["SQL Engine (RAM)<br/><b>ENCRYPTBYKEY / DECRYPTBYKEY</b>"]
        Disk4[("Disco / Coluna<br/><b>Varbinary</b>")]
        M1 --> App4 -->|"T-SQL"| Eng4 --> Disk4
    end
```

| Característica | TDE (Data at Rest) | Always Encrypted (Padrão) | Always Encrypted + Enclaves | Criptografia Manual (T-SQL) |
| :--- | :--- | :--- | :--- | :--- |
| **Ponto de Criptografia** | Disco / Armazenamento físico | Cliente (Driver da aplicação) | Cliente + Enclave VBS no Servidor | Servidor SQL (Funções T-SQL) |
| **Onde o Dado é Decifrado** | RAM do SQL Engine | Computador do Cliente (App) | Sandbox de Memória VBS Isolada | RAM do SQL Engine (`DECRYPTBYKEY`) |
| **Proteção Principal** | Roubo de discos e backups | Acesso indevido de DBAs e Admins | Acesso de DBAs com queries de intervalo | Usuários sem permissão na chave simétrica |
| **Localização da Chave** | Servidor SQL / Master Key | Cliente (Azure Key Vault / Cert Store) | Cliente (CMK) + Atestação de Enclave | Banco de Dados (Chave Simétrica) |
| **Transparência no Código** | 100% transparente | Transparente (requer driver compatível) | Transparente (requer driver com atestação) | Não transparente (exige alteração T-SQL) |
| **Consultas de Intervalo / LIKE** | Suportado integralmente | Não suportado (apenas igualdade se Deterministic) | Suportado (`BETWEEN`, `>`, `<`, `LIKE`) | Não suportado diretamente |
| **DBA Pode Ler o Dado Plano?** | **SIM** (tem acesso à RAM/Engine) | **NÃO** (vê apenas ciphertext) | **NÃO** (dado isolado no Enclave) | **SIM** (se tiver permissão na chave) |

---

## Casos de Uso (Use Cases)

- **TDE**: Linha de base corporativa exigida por conformidades (LGPD, HIPAA) para proteger backups físicos.
- **Always Encrypted**: Proteção de colunas com dados confidenciais financeiros e documentos de identificação pessoal (PII) contra acesso interno de DBAs.
- **Always Encrypted com Enclaves**: Cenários de proteção a PII onde buscas textuais aproximadas (`LIKE`) ou comparativos de datas são imperativos na aplicação.
- **Criptografia manual**: Aplicações de escopo específico que dependem de lógicas customizadas locais de descriptografia no SQL Server.

---

## Problemas Comuns e Soluções (Common Issues)

| Problema | Causa provável | Mitigação recomendada |
| :--- | :--- | :--- |
| Falha ao tentar filtrar coluna criptografada | Tipo configurado como RANDOMIZED em busca padrão | Altere a coluna para criptografia DETERMINISTIC ou ative o Enclave Seguro. |
| Erro ao restaurar backup em novo servidor | Certificado do TDE ausente na máquina de destino | Restaure o arquivo do certificado e chave privada antes de carregar o backup. |
| Queries com intervalo falham | Enclave Seguro inativo ou connection string sem suporte | Configure chaves prontas para enclave e atualize parâmetros de atestação do driver. |
| Falha na rotação de chaves | Chave antiga removida antes de concluir a associação da nova | Garanta que ambas as chaves coexistam no banco de dados durante os passos de re-criptografia. |

---

## Dicas para o Exame (Exam Tips)

> [!tip] Dicas para a Prova
>
> - **Always Encrypted**: A criptografia e descriptografia ocorrem no lado do cliente; o banco armazena apenas dados criptografados.
> - Sem enclave, a criptografia **DETERMINISTIC** aceita comparações de igualdade. Operações confidenciais mais ricas em colunas **RANDOMIZED** exigem enclave seguro e chave habilitada para enclave.
> - O TDE atua exclusivamente em nível de arquivos de dados físicos — não impede consultas indevidas via comandos SQL por contas autorizadas.
> - A perda do certificado original do TDE impossibilita a recuperação de qualquer backup criptografado sob ele.
> - A rotação da chave mestra (CMK) atua nos metadados de registro; a rotação da chave de criptografia de coluna (CEK) re-criptografa fisicamente o banco.

---

## Resumo dos Conceitos (Key Takeaways)

- TDE protege dados em repouso de forma automática, exigindo zero alterações de códigos.
- Always Encrypted impede visualizações confidenciais mantendo chaves de descriptografia fora do banco.
- Criptografias Randômicas exigem enclaves baseados em VBS no Azure SQL para viabilizar queries complexas.
- Sempre garanta backups independentes dos certificados do TDE com chaves privadas protegidas por senhas.

---

## Questões de Prática (Practice Questions)

**Questão de Prática**

Uma empresa possui regras de governança de dados rígidas que exigem que colunas de datas de nascimento de pacientes de um hospital permaneçam criptografadas, impedindo visualizações e leituras por administradores de banco de dados (DBAs). Adicionalmente, o sistema médico deve conseguir realizar filtros buscando pacientes nascidos em determinados intervalos de anos. Qual configuração do Azure SQL atende a essa demanda?

A. Ativar Criptografia de Dados Transparente (TDE) no banco de dados.

B. Configurar Always Encrypted com criptografia do tipo Determinística em nível de coluna.

C. Configurar Always Encrypted com criptografia do tipo Randômica associada a um Enclave Seguro (Secure Enclave).

D. Implementar criptografia de coluna local utilizando a função `ENCRYPTBYKEY`.

> [!success]- Resposta
> **C — Configurar Always Encrypted com criptografia do tipo Randômica associada a um Enclave Seguro (Secure Enclave)**
>
> O Always Encrypted impede a visualização dos dados por DBAs por reter as chaves na ponta do cliente. Para que seja possível realizar buscas em intervalos de dados (como datas nascidas entre dois limites de anos) mantendo o máximo de segurança contra correlações (criptografia Randômica), a especificação de um Enclave Seguro é mandatória no Azure SQL. A criptografia Determinística (B) suporta apenas buscas de igualdade exata. O TDE (A) descriptografa os dados para consultas do DBA.

---

## Tópicos Relacionados

- [02-Máscaras Dinâmicas de Dados & RLS](./02-dynamic-data-masking-rls.md)
- [03-Permissões & Acessos](./03-permissions-access.md) *(Inglês apenas)*

---

## Documentação Oficial

- [Always Encrypted (SQL Server)](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/always-encrypted-database-engine)
- [Always Encrypted with Secure Enclaves](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/always-encrypted-enclaves)
- [Transparent Data Encryption (TDE)](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/transparent-data-encryption)
- [Column Encryption using Always Encrypted with Azure Key Vault](https://learn.microsoft.com/en-us/azure/azure-sql/database/always-encrypted-azure-key-vault-configure)
- [Rotate Always Encrypted Keys](https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/rotate-always-encrypted-keys-using-ssms)

---

**[↑ Voltar para a Seção](./data-security-compliance.md) | [Lab: Criptografia](../../practice/labs/05-data-security-compliance/01-encryption-lab.sql) | [Próximo →](./02-dynamic-data-masking-rls.md)**
