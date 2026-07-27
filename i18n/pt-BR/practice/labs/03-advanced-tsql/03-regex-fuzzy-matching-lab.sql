-- =================================================================================
-- DP-800 - LAB PRÁTICO: REGEX, MATCHING FONÉTICO (SOUNDEX/DIFFERENCE) E FUZZY MATCHING
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra validações de padrão, Regex, Full-Text Search, limpeza de dados e correspondência aproximada.
-- Recursos opcionais (Regex, Full-Text Search e métricas fuzzy em preview) são verificados antes da execução.
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP TABLE IF EXISTS lab.RawContacts;
GO

-- Estrutura de Tabelas para Teste
CREATE TABLE lab.RawContacts (
    ContactID INT IDENTITY(1,1) CONSTRAINT PK_lab_RawContacts PRIMARY KEY,
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
('David 50% Sale', 'N/A', 'OFF-50%'),
('José Silva', '(11) 90000-0000', 'DEF-5678'),
('Jose Silva', '(11) 90000-0001', 'GHI-9012');
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

-- 3. Outros curingas e PATINDEX: sublinhado exige exatamente um caractere e [^0-9] nega uma classe.
SELECT ContactID, ProductCode
FROM lab.RawContacts
WHERE ProductCode LIKE '___-____' AND ProductCode NOT LIKE '%[^A-Z0-9-]%';

SELECT ContactID, ProductCode, PATINDEX('%[0-9][0-9][0-9][0-9]%', ProductCode) AS PosicaoDosQuatroDigitos
FROM lab.RawContacts
WHERE PATINDEX('%[0-9][0-9][0-9][0-9]%', ProductCode) > 0;

-- 4. Unicode e collation: CI_AI encontra José e Jose; CS_AS encontra somente José.
SELECT FullName
FROM lab.RawContacts
WHERE FullName = N'José Silva' COLLATE Latin1_General_100_CI_AI;

SELECT FullName
FROM lab.RawContacts
WHERE FullName = N'José Silva' COLLATE Latin1_General_100_CS_AS;
GO


-- =================================================================================
-- PARTE 2: FUNÇÕES REGEX (SQL SERVER 2025 / AZURE SQL / FABRIC)
-- =================================================================================
-- REGEXP_LIKE requer nível de compatibilidade 170. A verificação dinâmica evita erro de compilação
-- em versões sem Regex e deixa o restante do lab executável.
DECLARE @RegexDisponivel BIT = 0;

BEGIN TRY
    EXEC sys.sp_executesql N'SELECT REGEXP_LIKE(N''ABC-1234'', N''^[A-Z]{3}-\d{4}$'');';
    SET @RegexDisponivel = 1;
END TRY
BEGIN CATCH
    PRINT 'Regex nativo indisponível nesta instância ou nível de compatibilidade. A seção Regex será ignorada.';
END CATCH;

IF @RegexDisponivel = 1
BEGIN
    EXEC sys.sp_executesql N'
        -- REGEXP_LIKE: validação de formato.
        SELECT ContactID, ProductCode
        FROM lab.RawContacts
        WHERE REGEXP_LIKE(ProductCode, ''^[A-Z]{3}-\d{4}$'');

        -- REGEXP_REPLACE: limpeza e normalização de espaços.
        SELECT Phone, REGEXP_REPLACE(Phone, ''[^0-9]'', '''') AS ApenasDigitos,
               REGEXP_REPLACE(N''  muitos   espaços  '', ''\s+'', '' '') AS EspacosNormalizados
        FROM lab.RawContacts;

        -- REGEXP_SUBSTR, REGEXP_INSTR e REGEXP_COUNT: extrair, localizar e contar padrões.
        SELECT REGEXP_SUBSTR(N''Pedido #12345 e #67890'', ''[0-9]+'') AS PrimeiroPedido,
               REGEXP_INSTR(N''Pedido #12345'', ''[0-9]+'') AS PosicaoDoPedido,
               REGEXP_COUNT(N''2025-01-15 e 2025-02-20'', ''[0-9]{4}-[0-9]{2}-[0-9]{2}'') AS QuantidadeDeDatas;

        -- Funções tabulares: SELECT * também exibe metadados de captura e posição quando aplicáveis.
        SELECT * FROM REGEXP_MATCHES(N''one two three'', ''([a-z]+)'');
        SELECT value, ordinal FROM REGEXP_SPLIT_TO_TABLE(N''a,b,,c'', '',+'');';
END;
GO


-- =================================================================================
-- PARTE 3: NORMALIZAÇÃO DE STRINGS COM TRANSLATE E REPLACE
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - TRANSLATE(string, chars_origem, chars_destino): Substitui caracteres individuais em uma única passagem.
--     Evita encadeamento de múltiplos `REPLACE(REPLACE(REPLACE(...)))`.
--     Requisito: `chars_origem` e `chars_destino` devem ter exatamente o mesmo comprimento!

-- 1. Normalizar números de telefone removendo parenteses, pontos e traços de uma só vez
SELECT 
    ContactID,
    Phone AS TelefoneBruto,
    TRANSLATE(Phone, '().- ', '     ') AS TelefoneFormatado,
    REPLACE(TRANSLATE(Phone, '().- ', '     '), ' ', '') AS ApenasDigitos
FROM lab.RawContacts;
GO


-- =================================================================================
-- PARTE 4: CORRESPONDÊNCIA FONÉTICA (SOUNDEX E DIFFERENCE)
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
-- PARTE 5: ALGORITMOS DE FUZZY MATCHING (DISTÂNCIA DE EDIÇÃO E SIMILARIDADE)
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

    EXEC sys.sp_executesql N'
        -- Deduplicação: use limiares para reduzir candidatos antes de qualquer merge.
        SELECT c1.ContactID AS ID1, c1.FullName AS Nome1,
               c2.ContactID AS ID2, c2.FullName AS Nome2,
               EDIT_DISTANCE_SIMILARITY(c1.FullName, c2.FullName) AS SimilaridadeEdicao,
               JARO_WINKLER_DISTANCE(c1.FullName, c2.FullName) AS DistanciaJaroWinkler
        FROM lab.RawContacts AS c1
        JOIN lab.RawContacts AS c2 ON c1.ContactID < c2.ContactID
        WHERE EDIT_DISTANCE_SIMILARITY(c1.FullName, c2.FullName) >= 80
           OR JARO_WINKLER_DISTANCE(c1.FullName, c2.FullName) <= 0.20;';
END
ELSE
    PRINT 'PREVIEW_FEATURES está desabilitado; execute a instrução comentada acima para praticar as métricas fuzzy.';
GO


-- =================================================================================
-- PARTE 6: FULL-TEXT SEARCH (CONTAINS E FREETEXT)
-- =================================================================================
-- A instalação do serviço, um catálogo existente e as permissões para criar o índice são verificados. A população é assíncrona:
-- se a primeira consulta ainda não retornar linhas, aguarde o índice terminar de ser preenchido e execute novamente.
IF FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') = 1
BEGIN
    DECLARE @CatalogoFullText SYSNAME;
    DECLARE @ComandoFullText NVARCHAR(MAX);
    SELECT TOP (1) @CatalogoFullText = name
    FROM sys.fulltext_catalogs
    ORDER BY is_default DESC, fulltext_catalog_id;

    BEGIN TRY
        IF @CatalogoFullText IS NULL
            PRINT 'Não há catálogo Full-Text neste banco; a seção será ignorada.';
        ELSE IF NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'lab.RawContacts'))
        BEGIN
            SET @ComandoFullText = N'CREATE FULLTEXT INDEX ON lab.RawContacts (FullName LANGUAGE 1033)
                KEY INDEX PK_lab_RawContacts ON ' + QUOTENAME(@CatalogoFullText) + N' WITH CHANGE_TRACKING AUTO;';
            EXEC sys.sp_executesql @ComandoFullText;
        END;

        IF EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'lab.RawContacts'))
        BEGIN
            -- As consultas também são dinâmicas: o otimizador só valida CONTAINS/FREETEXT
            -- depois que o índice acaba de ser criado neste mesmo batch.
            EXEC sys.sp_executesql N'
                -- CONTAINS é uma busca estruturada: prefixo Smith*.
                SELECT ContactID, FullName
                FROM lab.RawContacts
                WHERE CONTAINS(FullName, ''"Smith*"'');

                -- FREETEXT delega a interpretação linguística ao mecanismo de Full-Text Search.
                SELECT ContactID, FullName
                FROM lab.RawContacts
                WHERE FREETEXT(FullName, N''Alice Smith'');';
        END;
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Full-Text Search não pôde ser configurado: ', ERROR_MESSAGE());
    END CATCH;
END
ELSE
    PRINT 'Full-Text Search não está instalado nesta instância; a seção será ignorada.';
GO


-- =================================================================================
-- PARTE 7: CENÁRIOS PRÁTICOS DE PROJETO
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
