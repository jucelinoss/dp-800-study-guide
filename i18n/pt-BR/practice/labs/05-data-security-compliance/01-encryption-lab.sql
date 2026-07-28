-- =================================================================================
-- DP-800 - LAB PRÁTICO: CRIPTOGRAFIA DE DADOS (TDE, ALWAYS ENCRYPTED E CELL-LEVEL)
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/05-data-security-compliance/01-encryption.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra as três tecnologias de criptografia no SQL Server:
--   1. Transparent Data Encryption (TDE): Proteção de arquivos em disco (DEK e sys.dm_database_encryption_keys)
--   2. Always Encrypted: Hierarquia CMK + CEK, Criptografia DETERMINISTIC vs RANDOMIZED e Secure Enclaves
--   3. Criptografia em Nível de Célula (Cell-Level): Master Key, Certificado, Chave Simétrica (ENCRYPTBYKEY/DECRYPTBYKEY)
--   4. Rotação de Chaves de Criptografia de Coluna (Metadata-Only vs Full Data Re-encryption)
--   5. Cenários Práticos de Projeto (Proteção de Prontuários Médicos e Cartões de Crédito)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = 'LabSymKey')
    CLOSE SYMMETRIC KEY LabSymKey;

IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = 'LabSymKey')
    DROP SYMMETRIC KEY LabSymKey;

IF EXISTS (SELECT * FROM sys.certificates WHERE name = 'LabCellCert')
    DROP CERTIFICATE LabCellCert;

DROP TABLE IF EXISTS lab.EncryptedUserData;
DROP TABLE IF EXISTS lab.EncryptedCellData;
GO

-- Estrutura de Tabela para Teste
CREATE TABLE lab.EncryptedCellData (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    UserName NVARCHAR(100) NOT NULL,
    EncryptedCreditCard VARBINARY(MAX) NULL
);
GO


-- =================================================================================
-- PARTE 1: CELL-LEVEL ENCRYPTION (MASTER KEY, CERTIFICADO E CHAVE SIMÉTRICA)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - CELL-LEVEL ENCRYPTION: Criptografia manual em nível de célula executada via T-SQL.
--   - HIERARQUIA: Database Master Key (DMK) -> Certificado -> Chave Simétrica (AES_256).
--   - FUNÇÕES: `ENCRYPTBYKEY(KEY_GUID('NomeChave'), Texto)` para criptografar e
--     `DECRYPTBYKEY(DadoBinario)` para descriptografar.

-- 1. Criar Master Key do Banco de Dados (se não existir)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssword123!';
END
GO

-- 2. Criar Certificado para proteger a Chave Simétrica
CREATE CERTIFICATE LabCellCert 
WITH SUBJECT = 'Certificado de Protecao de Celulas';
GO

-- 3. Criar Chave Simétrica protegida pelo Certificado
CREATE SYMMETRIC KEY LabSymKey
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE LabCellCert;
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 4. Inserir dados criptografando via ENCRYPTBYKEY
OPEN SYMMETRIC KEY LabSymKey DECRYPTION BY CERTIFICATE LabCellCert;

INSERT INTO lab.EncryptedCellData (UserName, EncryptedCreditCard)
VALUES (N'Alice Smith', ENCRYPTBYKEY(KEY_GUID('LabSymKey'), N'4532-1111-2222-3333'));

CLOSE SYMMETRIC KEY LabSymKey;
GO

-- 5. Ler dados descriptografando via DECRYPTBYKEY
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
-- PARTE 2: ALWAYS ENCRYPTED (DETERMINISTIC VS RANDOMIZED E HIERARQUIA CMK/CEK)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - ALWAYS ENCRYPTED: Criptografia no lado do cliente. O banco de dados NUNCA vê os dados em texto claro.
--   - CMK (Column Master Key): Chave mestre mantida no repositório de chaves externo (ex: Azure Key Vault / Windows Cert Store).
--   - CEK (Column Encryption Key): Chave criptografada pela CMK que protege os dados da coluna.
--   - DETERMINISTIC: O mesmo texto claro gera sempre o mesmo texto cifrado. Permite `=`, `JOIN`, `GROUP BY`.
--   - RANDOMIZED: O mesmo texto claro gera textos cifrados diferentes a cada gravação. Maior segurança; NÃO permite comparações diretas.
--   - SECURE ENCLAVES (VBS): Permite consultas de intervalo (`BETWEEN`, `<`, `>`) e `LIKE` em colunas RANDOMIZED.

-- Estruturação conceitual da DDL para Always Encrypted (Requer chave externa provisionada)
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
    -- DETERMINISTIC: Permite buscar por SSN exato (= '123-45-6789')
    SSN CHAR(11) COLLATE Latin1_General_BIN2 
        ENCRYPTED WITH (
            COLUMN_ENCRYPTION_KEY = LabCEK, 
            ENCRYPTION_TYPE = DETERMINISTIC, 
            ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
        ) NOT NULL,
    -- RANDOMIZED: Sem comparações sem Secure Enclaves
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
-- PARTE 3: TRANSPARENT DATA ENCRYPTION (TDE) E INSPEÇÃO DE STATUS
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - TDE: Criptografa arquivos de dados (.mdf) e log (.ldf) em repouso. Transparente para aplicações.
--   - Azure SQL Database: TDE é ativado por padrão.
--   - sys.dm_database_encryption_keys: Visão de gerenciamento dinâmico para inspecionar o estado de criptografia (3 = Encrypted).

-- -- [PONTO DE ATENÇÃO DP-800]
-- Consultar o estado do TDE nos bancos de dados do servidor
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
-- PARTE 4: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz de Decisão de Criptografia para Conformidade (LGPD / HIPAA / PCI-DSS)
-- Mapeamento das tabelas protegidas e seus respectivos mecanismos de criptografia em produção.

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

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/05-data-security-compliance/01-encryption.md
-- =================================================================================================
