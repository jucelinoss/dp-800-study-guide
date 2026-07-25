-- =================================================================================
-- DP-800 - HANDS-ON LAB: DATA ENCRYPTION (TDE, ALWAYS ENCRYPTED, AND CELL-LEVEL)
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- This script demonstrates three encryption technologies in SQL Server:
--   1. Transparent Data Encryption (TDE): Protecting files on disk (DEK and sys.dm_database_encryption_keys)
--   2. Always Encrypted: CMK + CEK hierarchy, DETERMINISTIC vs RANDOMIZED encryption, and Secure Enclaves
--   3. Cell-Level Encryption: Master Key, Certificate, Symmetric Key (ENCRYPTBYKEY/DECRYPTBYKEY)
--   4. Column Encryption Key Rotation (Metadata-Only vs Full Data Re-encryption)
--   5. Practical Project Scenarios (Protecting Medical Records and Credit Cards)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Preventive cleanup
IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = 'LabSymKey')
    CLOSE SYMMETRIC KEY LabSymKey;

IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = 'LabSymKey')
    DROP SYMMETRIC KEY LabSymKey;

IF EXISTS (SELECT * FROM sys.certificates WHERE name = 'LabCellCert')
    DROP CERTIFICATE LabCellCert;

DROP TABLE IF EXISTS lab.EncryptedUserData;
DROP TABLE IF EXISTS lab.EncryptedCellData;
GO

-- Table structure for testing
CREATE TABLE lab.EncryptedCellData (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    UserName NVARCHAR(100) NOT NULL,
    EncryptedCreditCard VARBINARY(MAX) NULL
);
GO


-- =================================================================================
-- PART 1: CELL-LEVEL ENCRYPTION (MASTER KEY, CERTIFICATE, AND SYMMETRIC KEY)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - CELL-LEVEL ENCRYPTION: Manual cell-level encryption executed via T-SQL.
--   - HIERARCHY: Database Master Key (DMK) -> Certificate -> Symmetric Key (AES_256).
--   - FUNCTIONS: `ENCRYPTBYKEY(KEY_GUID('KeyName'), Text)` to encrypt and
--     `DECRYPTBYKEY(BinaryData)` to decrypt.

-- 1. Create Database Master Key (if it doesn't exist)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssword123!';
END
GO

-- 2. Create Certificate to protect the Symmetric Key
CREATE CERTIFICATE LabCellCert 
WITH SUBJECT = 'Certificado de Protecao de Celulas';
GO

-- 3. Create Symmetric Key protected by the Certificate
CREATE SYMMETRIC KEY LabSymKey
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE LabCellCert;
GO

-- -- [DP-800 EXAM TIP]
-- 4. Insert data encrypted via ENCRYPTBYKEY
OPEN SYMMETRIC KEY LabSymKey DECRYPTION BY CERTIFICATE LabCellCert;

INSERT INTO lab.EncryptedCellData (UserName, EncryptedCreditCard)
VALUES (N'Alice Smith', ENCRYPTBYKEY(KEY_GUID('LabSymKey'), N'4532-1111-2222-3333'));

CLOSE SYMMETRIC KEY LabSymKey;
GO

-- 5. Read data decrypted via DECRYPTBYKEY
OPEN SYMMETRIC KEY LabSymKey DECRYPTION BY CERTIFICATE LabCellCert;

SELECT 
    UserID,
    UserName,
    EncryptedCreditCard AS CartaoCriptografadoBinario,
    CONVERT(NVARCHAR(50), DECRYPTBYKEY(EncryptedCreditCard)) AS CartaoDescriptografado
FROM lab.EncryptedCellData;

CLOSE SYMMETRIC KEY LabSymKey;
GO


-- =================================================================================
-- PART 2: ALWAYS ENCRYPTED (DETERMINISTIC VS RANDOMIZED AND CMK/CEK HIERARCHY)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - ALWAYS ENCRYPTED: Client-side encryption. The database NEVER sees data in plaintext.
--   - CMK (Column Master Key): Master key stored in an external key repository (e.g., Azure Key Vault / Windows Cert Store).
--   - CEK (Column Encryption Key): Key encrypted by the CMK that protects the column data.
--   - DETERMINISTIC: Same plaintext always generates the same ciphertext. Allows `=`, `JOIN`, `GROUP BY`.
--   - RANDOMIZED: Same plaintext generates different ciphertext on each write. Higher security; does NOT allow direct comparisons.
--   - SECURE ENCLAVES (VBS): Enables range queries (`BETWEEN`, `<`, `>`) and `LIKE` on RANDOMIZED columns.

-- Conceptual DDL structure for Always Encrypted (Requires provisioned external key)
/*
CREATE COLUMN MASTER KEY LabCMK
WITH (
    KEY_STORE_PROVIDER_NAME = 'MSSQL_CERTIFICATE_STORE',
    KEY_PATH = 'CurrentUser/My/A1B2C3D4E5F6...'
);

CREATE COLUMN ENCRYPTION KEY LabCEK
WITH VALUES (
    COLUMN_MASTER_KEY = LabCMK,
    ALGORITHM = 'RSA_OAEP',
    ENCRYPTED_VALUE = 0x017000...
);

CREATE TABLE lab.AlwaysEncryptedPatients (
    PatientID INT PRIMARY KEY,
    -- DETERMINISTIC: Allows searching by exact SSN (= '123-45-6789')
    SSN CHAR(11) COLLATE Latin1_General_BIN2 
        ENCRYPTED WITH (
            COLUMN_ENCRYPTION_KEY = LabCEK, 
            ENCRYPTION_TYPE = DETERMINISTIC, 
            ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
        ) NOT NULL,
    -- RANDOMIZED: No comparisons without Secure Enclaves
    Salary MONEY 
        ENCRYPTED WITH (
            COLUMN_ENCRYPTION_KEY = LabCEK, 
            ENCRYPTION_TYPE = RANDOMIZED, 
            ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
        ) NULL
);
*/
GO


-- =================================================================================
-- PART 3: TRANSPARENT DATA ENCRYPTION (TDE) AND STATUS INSPECTION
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - TDE: Encrypts data files (.mdf) and log (.ldf) at rest. Transparent to applications.
--   - Azure SQL Database: TDE is enabled by default.
--   - sys.dm_database_encryption_keys: Dynamic management view to inspect encryption state (3 = Encrypted).

-- -- [DP-800 EXAM TIP]
-- Query TDE status on server databases
SELECT 
    db_name(database_id) AS DatabaseName,
    encryption_state,
    CASE encryption_state
        WHEN 0 THEN 'Sem Chave DEK'
        WHEN 1 THEN 'Não Criptografado'
        WHEN 2 THEN 'Criptografia em Andamento'
        WHEN 3 THEN 'CRIPTOGRAFADO (TDE Ativo)'
        WHEN 4 THEN 'Troca de Chave em Andamento'
        WHEN 5 THEN 'Descriptografia em Andamento'
    END AS StatusCriptografia,
    key_algorithm,
    key_length
FROM sys.dm_database_encryption_keys;
GO


-- =================================================================================
-- PART 4: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

-- SCENARIO 1: Encryption Decision Matrix for Compliance (LGPD / HIPAA / PCI-DSS)
-- Mapping of protected tables and their respective encryption mechanisms in production.

SELECT 
    'TDE' AS Tecnologia,
    'Dados em Repouso (Discos/Backups)' AS AlvoProtecao,
    'DBA possui acesso aos dados em memória' AS EscopoSeguranca,
    'Zero impacto em consultas' AS SuporteQueries
UNION ALL
SELECT 
    'Always Encrypted (Deterministic)',
    'Colunas PII sensíveis (Ex: CPF/SSN)',
    'DBA NÃO vê texto claro. Permite busca por igualdade (=)',
    'Permite =, JOIN, GROUP BY'
UNION ALL
SELECT 
    'Always Encrypted + Enclave (Randomized)',
    'Dados altamente confidenciais com busca por intervalo',
    'Processamento isolado via VBS Enclave no servidor',
    'Permite BETWEEN, <, >, LIKE'
UNION ALL
SELECT 
    'Cell-Level (ENCRYPTBYKEY)',
    'Células específicas em colunas legadas',
    'Requer código manual OPEN/CLOSE SYMMETRIC KEY',
    'Exige chamadas explícitas de função';
GO
