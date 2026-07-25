-- =================================================================================
-- DP-800 - LAB PRÁTICO: REGEX, MATCHING FONÉTICO (SOUNDEX/DIFFERENCE) E FUZZY MATCHING
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra validações de padrão, limpeza de dados e correspondência aproximada:
--   1. Validação de Padrões: LIKE com Classes de Caracteres ([A-Z], [^0-9]) e Cláusula ESCAPE
--   2. Normalização e Limpeza: TRANSLATE vs REPLACE e STRING_SPLIT com Habilitação de Ordinal (SQL 2022+)
--   3. Correspondência Fonética: SOUNDEX e a Função DIFFERENCE (Escala 0 a 4)
--   4. Algoritmos de Fuzzy Matching: EDIT_DISTANCE (Levenshtein), SIMILARITY e JARO_WINKLER_DISTANCE
--   5. Cenários Práticos de Projeto (Deduplicação de Cadastros e Preparação de Dados para Embeddings/RAG)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.RawContacts;
GO

-- Estrutura de Tabelas para Teste
CREATE TABLE lab.RawContacts (
    ContactID INT IDENTITY(1,1) PRIMARY KEY,
    FullName NVARCHAR(100) NOT NULL,
    Phone NVARCHAR(50) NULL,
    ProductCode NVARCHAR(20) NULL
);
GO


-- =================================================================================
-- PARTE 1: VALIDAÇÃO DE PADRÕES COM LIKE AVANÇADO E ESCAPE
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - PATTERN MATCHING COM LIKE: O T-SQL nativo suporta classes de caracteres:
--     * `[A-Z]`: Qualquer caractere no intervalo alfabético.
--     * `[0-9]`: Qualquer dígito.
--     * `[^0-9]`: Qualquer caractere que NÃO seja dígito.
--   - CLÁUSULA ESCAPE: Permite buscar caracteres curingas literais (como `%`, `_`, `[`) usando um caractere de escape (ex: `ESCAPE '\'`).

INSERT INTO lab.RawContacts (FullName, Phone, ProductCode) VALUES 
('Alice Smith', '(11) 98765-4321', 'ABC-1234'),
('Bob Smyth', '11.98765.4321', 'XYZ-9999'),
('Charlie Brown', '11987654321', 'INVALID-12'),
('David 50% Sale', 'N/A', 'OFF-50%');
GO

-- -- [PONTO DE ATENÇÃO DP-800]
-- 1. Validar Códigos de Produto: Exatamente 3 letras maiúsculas, traço e 4 números (ex: ABC-1234)
SELECT ContactID, ProductCode
FROM lab.RawContacts
WHERE ProductCode LIKE '[A-Z][A-Z][A-Z]-[0-9][0-9][0-9][0-9]';

-- 2. Buscar o caractere % literal usando ESCAPE
SELECT ContactID, FullName
FROM lab.RawContacts
WHERE FullName LIKE '%\%%' ESCAPE '\';
GO

-- 3. SQL Server 2025: a mesma regra com expressão regular.
-- REGEXP_LIKE requer nível de compatibilidade 170. Confirme antes de executar em outro banco:
-- SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME();
SELECT ContactID, ProductCode
FROM lab.RawContacts
WHERE REGEXP_LIKE(ProductCode, '^[A-Z]{3}-\d{4}$');
GO


-- =================================================================================
-- PARTE 2: NORMALIZAÇÃO DE STRINGS COM TRANSLATE E STRING_SPLIT ORDINAL
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - TRANSLATE(string, chars_origem, chars_destino): Substitui caracteres individuais em uma única passagem.
--     Evita encadeamento de múltiplos `REPLACE(REPLACE(REPLACE(...)))`.
--     Requisito: `chars_origem` e `chars_destino` devem ter exatamente o mesmo comprimento!
--   - STRING_SPLIT(string, delimitador, 1): A partir do SQL Server 2022, o parâmetro `enable_ordinal = 1`
--     adiciona a coluna `ordinal` que preserva a posição original do item no vetor.

-- 1. Normalizar números de telefone removendo parenteses, pontos e traços de uma só vez
SELECT 
    ContactID,
    Phone AS TelefoneBruto,
    TRANSLATE(Phone, '().- ', '     ') AS TelefoneFormatado,
    REPLACE(TRANSLATE(Phone, '().- ', '     '), ' ', '') AS ApenasDigitos
FROM lab.RawContacts;
GO

-- 2. STRING_SPLIT com preservação de posição (SQL Server 2022+)
DECLARE @tags NVARCHAR(200) = N'SQL,Azure,Database,Security,AI';

SELECT value AS TagName, ordinal AS Posicao
FROM STRING_SPLIT(@tags, ',', 1);
GO


-- =================================================================================
-- PARTE 3: CORRESPONDÊNCIA FONÉTICA (SOUNDEX E DIFFERENCE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - SOUNDEX(): Converte uma string em um código fonético de 4 caracteres (uma letra + 3 números).
--     Identifica como as palavras soam em inglês.
--   - DIFFERENCE(str1, str2): Compara os códigos SOUNDEX de duas palavras e retorna um inteiro de 0 a 4:
--     * 4: Sons praticamente idênticos (ex: 'Smith' vs 'Smyth').
--     * 0: Sons completamente diferentes.

-- -- [PONTO DE ATENÇÃO DP-800]
SELECT 
    SOUNDEX('Smith') AS SoundexSmith,
    SOUNDEX('Smyth') AS SoundexSmyth,
    DIFFERENCE('Smith', 'Smyth') AS ScoreSmithSmyth, -- Retorna 4 (Máxima similaridade)
    DIFFERENCE('Smith', 'Brown') AS ScoreSmithBrown; -- Retorna 1 ou 0
GO

-- Buscar contatos cujo nome soe semelhante a 'Smith'
SELECT ContactID, FullName, DIFFERENCE(FullName, 'Smith') AS PontuacaoFonetica
FROM lab.RawContacts
WHERE DIFFERENCE(FullName, 'Smith') >= 3;
GO


-- =================================================================================
-- PARTE 4: ALGORITMOS DE FUZZY MATCHING (DISTÂNCIA DE EDIÇÃO E SIMILARIDADE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - EDIT_DISTANCE (Levenshtein): Retorna o número absoluto de inserções, remoções e substituições de caracteres.
--   - EDIT_DISTANCE_SIMILARITY: Retorna uma pontuação normalizada de 0 (diferentes) a 100 (idênticos).
--   - JARO_WINKLER_DISTANCE: Retorna um valor entre 0.0 e 1.0 dando peso aos caracteres iniciais idênticos.

-- Nota de Compatibilidade: EDIT_DISTANCE, EDIT_DISTANCE_SIMILARITY e as funções JARO_WINKLER
-- estão em preview no SQL Server 2025. Os valores de entrada não podem ser varchar(max)/nvarchar(max).
-- Em versões anteriores, SOUNDEX/DIFFERENCE são as alternativas nativas disponíveis.
-- Para habilitar os recursos de preview neste banco de estudo, execute separadamente (requer permissão ALTER ANY DATABASE):
-- ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;

-- Comparar as métricas modernas. Distância menor significa maior proximidade; similaridade maior significa melhor match.
-- O SQL dinâmico permite que o restante do lab rode mesmo se PREVIEW_FEATURES estiver desabilitado.
IF EXISTS (
    SELECT 1
    FROM sys.database_scoped_configurations
    WHERE name = 'PREVIEW_FEATURES' AND value = 1
)
BEGIN
    EXEC sys.sp_executesql N'
        SELECT
            FullName,
            EDIT_DISTANCE(FullName, N''Alice Smith'') AS DistanciaEdicao,
            EDIT_DISTANCE_SIMILARITY(FullName, N''Alice Smith'') AS SimilaridadeEdicao,
            JARO_WINKLER_DISTANCE(FullName, N''Alice Smith'') AS DistanciaJaroWinkler,
            JARO_WINKLER_SIMILARITY(FullName, N''Alice Smith'') AS SimilaridadeJaroWinkler
        FROM lab.RawContacts;';
END
ELSE
    PRINT 'PREVIEW_FEATURES está desabilitado; execute a instrução comentada acima para praticar as métricas fuzzy.';
GO


-- =================================================================================
-- PARTE 5: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Deduplicação e Limpeza de Nomes antes da Vetorização (Embeddings para RAG)
-- Em pipelines de Inteligência Artificial, nomes duplicados com grafias incorretas devem ser 
-- limpos via TRANSLATE e agrupados por código SOUNDEX/DIFFERENCE para evitar ruído nos vetores.

SELECT 
    c1.ContactID AS ID1, c1.FullName AS Nome1,
    c2.ContactID AS ID2, c2.FullName AS Nome2,
    DIFFERENCE(c1.FullName, c2.FullName) AS GrauSimilaridade
FROM lab.RawContacts c1
JOIN lab.RawContacts c2 ON c1.ContactID < c2.ContactID
WHERE DIFFERENCE(c1.FullName, c2.FullName) >= 3;
GO
