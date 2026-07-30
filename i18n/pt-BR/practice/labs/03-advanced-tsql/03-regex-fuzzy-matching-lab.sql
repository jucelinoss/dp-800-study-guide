-- =================================================================================
-- DP-800 - LAB PRÁTICO: REGEX, MATCHING FONÉTICO (SOUNDEX/DIFFERENCE) E FUZZY MATCHING
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/03-advanced-tsql/03-regex-fuzzy-matching.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
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
-- As consultas abaixo usam diretamente os recursos do SQL Server 2025.
-- Execute cada bloco separadamente para observar o resultado de cada função.

-- 1. REGEXP_LIKE: testa se o valor inteiro segue o padrão ABC-1234.
-- Como REGEXP_LIKE é um predicado, CASE transforma o resultado lógico em 1 ou 0.
SELECT CASE
           WHEN REGEXP_LIKE(N'ABC-1234', N'^[A-Z]{3}-\d{4}$')
           THEN 1 ELSE 0
       END AS IsMatch;
GO

-- 2. REGEXP_LIKE no WHERE: retorna somente os códigos com três letras maiúsculas,
-- hífen e quatro dígitos.
SELECT ContactID, ProductCode
FROM lab.RawContacts
WHERE REGEXP_LIKE(ProductCode, N'^[A-Z]{3}-\d{4}$');
GO

-- 3. REGEXP_REPLACE: remove todos os caracteres que não sejam dígitos do telefone.
-- A expressão [^0-9] representa qualquer caractere fora do intervalo de 0 a 9.
SELECT Phone,
       REGEXP_REPLACE(Phone, N'[^0-9]', N'') AS ApenasDigitos
FROM lab.RawContacts;
GO

-- 4. REGEXP_REPLACE: substitui uma ou mais ocorrências consecutivas de espaço
-- por um único espaço, ajudando a normalizar textos.
SELECT REGEXP_REPLACE(N'  muitos   espaços  ', N'\s+', N' ') AS EspacosNormalizados;
GO

-- 5. REGEXP_SUBSTR: extrai a primeira sequência numérica encontrada no texto.
SELECT REGEXP_SUBSTR(N'Pedido #12345 e #67890', N'[0-9]+') AS PrimeiroPedido;
GO

-- 6. REGEXP_INSTR: retorna a posição inicial, baseada em 1, da primeira sequência
-- numérica encontrada no texto.
SELECT REGEXP_INSTR(N'Pedido #12345', N'[0-9]+') AS PosicaoDoPedido;
GO

-- 7. REGEXP_COUNT: conta quantas ocorrências de datas no formato AAAA-MM-DD
-- existem na string informada.
SELECT REGEXP_COUNT(N'2025-01-15 e 2025-02-20', N'[0-9]{4}-[0-9]{2}-[0-9]{2}') AS QuantidadeDeDatas;
GO

-- 8. REGEXP_MATCHES: retorna uma linha para cada ocorrência que corresponde
-- ao padrão informado. SELECT * exibe todas as colunas fornecidas pela função.
SELECT *
FROM REGEXP_MATCHES(N'one two three', N'([a-z]+)');
GO

-- 9. REGEXP_SPLIT_TO_TABLE: divide o texto usando uma expressão regular como
-- separador e retorna o valor de cada parte junto com sua posição ordinal.
SELECT value, ordinal
FROM REGEXP_SPLIT_TO_TABLE(N'a,b,,c', N',+');
GO
GO


-- =================================================================================
-- PARTE 3: NORMALIZAÇÃO DE STRINGS COM TRANSLATE E REPLACE
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - TRANSLATE(string, chars_origem, chars_destino): Substitui caracteres individuais em uma única passagem.
--     Evita encadeamento de múltiplos `REPLACE(REPLACE(REPLACE(...)))`.
--     Requisito: `chars_origem` e `chars_destino` devem ter exatamente o mesmo comprimento!

-- 1. Exemplo posicional: o primeiro caractere do segundo argumento é trocado
--    pelo primeiro caractere do terceiro argumento, o segundo pelo segundo, e assim por diante.
--    Os caracteres de entrada podem ser mapeados para o mesmo caractere de saída
--    ou para caracteres de saída diferentes.
SELECT TRANSLATE('2*[3+4]/{7-2}', '[]{}', '()()') AS ExpressaoNormalizada;
-- Resultado: 2*(3+4)/(7-2)
GO

-- 2. Cada caractere de entrada é mapeado para um caractere diferente de saída:
--    a -> X, b -> Y, c -> Z e 1 -> 9.
SELECT TRANSLATE('abc-123', 'abc1', 'XYZ9') AS Resultado;
-- Resultado: XYZ-923
GO

-- 3. Caracteres diferentes de entrada podem compartilhar o mesmo destino.
--    Tanto '/' quanto '.' são convertidos em '-', pois os destinos nas posições
--    correspondentes são iguais.
SELECT TRANSLATE('2025/07.30', '/.', '--') AS DataNormalizada;
-- Resultado: 2025-07-30
GO

-- 4. No telefone, quatro caracteres de entrada são mapeados para quatro espaços.
--    Os argumentos precisam ter o mesmo tamanho: '().-' tem 4 e '    ' tem 4.
SELECT 
    ContactID,
    Phone AS TelefoneBruto,
    TRANSLATE(Phone, '().-', '    ') AS TelefoneFormatado
FROM lab.RawContacts;
GO

-- 5. TRANSLATE troca a pontuação por espaços; REPLACE remove os espaços.
SELECT ContactID,
       Phone,
       REPLACE(TRANSLATE(Phone, '().-', '    '), ' ', '') AS ApenasDigitos
FROM lab.RawContacts;
GO

-- Erro 9828: '().- ' tem 5 caracteres, mas ' ' tem apenas 1.
-- TRANSLATE(Phone, '().- ', ' ') não é válido.


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
    DIFFERENCE('Smidt', 'Smyth') AS ScoreSmidtBrown, -- Retorna 1 ou 0
    DIFFERENCE('Smith', 'Brown') AS ScoreSmithBrown; -- Retorna 1 ou 0
GO

-- Buscar contatos cujo sobrenome soe semelhante a 'Smith'. Bob Smyth é um
-- exemplo prático: DIFFERENCE('Smyth', 'Smith') retorna 4.
SELECT r.ContactID,
       r.FullName,
       s.LastName AS Sobrenome,
       DIFFERENCE(s.LastName, 'Smith') AS PontuacaoFonetica
FROM lab.RawContacts AS r
CROSS APPLY (VALUES (PARSENAME(REPLACE(r.FullName, ' ', '.'), 1))) AS s(LastName)
WHERE DIFFERENCE(s.LastName, 'Smith') >= 4;
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

-- OBSERVAÇÃO IMPORTANTE SOBRE AS ESCALAS:
--   - EDIT_DISTANCE é uma contagem absoluta de operações; seu valor depende do tamanho das strings.
--   - EDIT_DISTANCE_SIMILARITY é uma pontuação normalizada de 0 a 100.
--   - JARO_WINKLER_DISTANCE varia de 0 a 1; quanto menor, maior a proximidade.
--   - JARO_WINKLER_SIMILARITY varia de 0 a 100; quanto maior, maior a proximidade.
--   - Para Jaro-Winkler, a similaridade é aproximadamente (1 - distância) * 100.
--     Exemplo: distância 0,33 corresponde a aproximadamente 67% de similaridade.
--   - Não compare diretamente EDIT_DISTANCE = 6 com JARO_WINKLER_DISTANCE = 0,33:
--     são métricas diferentes e estão em escalas diferentes.
--   - Use limiares adequados à métrica, por exemplo SimilaridadeEdicao >= 80
--     ou DistanciaJaroWinkler <= 0,20.

-- Comparar as métricas modernas. Distância menor significa maior proximidade;
-- similaridade maior significa melhor correspondência.
SELECT FullName,
       EDIT_DISTANCE(FullName, N'Alice Smith') AS DistanciaEdicao,
       EDIT_DISTANCE_SIMILARITY(FullName, N'Alice Smith') AS SimilaridadeEdicao,
       JARO_WINKLER_DISTANCE(FullName, N'Alice Smith') AS DistanciaJaroWinkler,
       JARO_WINKLER_SIMILARITY(FullName, N'Alice Smith') AS SimilaridadeJaroWinkler
FROM lab.RawContacts;
GO

-- Deduplicação: os limiares reduzem os candidatos antes de qualquer merge.
-- `SimilaridadeEdicao >= 80` aceita pares com pelo menos 80% de similaridade
-- de edição. `DistanciaJaroWinkler <= 0,20` aceita pares com no máximo 20% de
-- distância Jaro-Winkler, aproximadamente 80% ou mais de similaridade.
-- Esses valores são pontos de partida para a triagem, não regras universais:
-- ajuste-os conforme a qualidade dos dados e o custo dos falsos positivos.
-- O valor 80 busca equilibrar falsos positivos e falsos negativos: abaixo de 80,
-- mais pares diferentes podem ser considerados iguais; acima de 80, duplicatas
-- com mais erros podem ser perdidas. Em dados sensíveis, considere 95 ou 98;
-- em dados muito sujos, 70 ou 75 pode ser mais adequado, sempre com revisão antes
-- de executar o MERGE.
-- O `OR` retorna o par quando qualquer métrica aprova; com `AND`, as duas
-- métricas precisariam aprovar o par.
SELECT c1.ContactID AS ID1,
       c1.FullName AS Nome1,
       c2.ContactID AS ID2,
       c2.FullName AS Nome2,
       EDIT_DISTANCE_SIMILARITY(c1.FullName, c2.FullName) AS SimilaridadeEdicao,
       JARO_WINKLER_DISTANCE(c1.FullName, c2.FullName) AS DistanciaJaroWinkler
FROM lab.RawContacts AS c1
JOIN lab.RawContacts AS c2 ON c1.ContactID < c2.ContactID
WHERE EDIT_DISTANCE_SIMILARITY(c1.FullName, c2.FullName) >= 80
   OR JARO_WINKLER_DISTANCE(c1.FullName, c2.FullName) <= 0.20;
GO


-- =================================================================================
-- PARTE 6: FULL-TEXT SEARCH (CONTAINS E FREETEXT)
-- =================================================================================
-- O Full-Text é criado somente quando o recurso está instalado, existe um
-- catálogo Full-Text padrão e a tabela ainda não possui um índice.
-- A população é assíncrona; se não houver resultados, aguarde e execute novamente.
IF FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE is_default = 1)
        PRINT 'Crie ou designe um catálogo Full-Text padrão antes de executar esta seção.';
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1
                       FROM sys.fulltext_indexes
                       WHERE object_id = OBJECT_ID(N'lab.RawContacts'))
        BEGIN
            BEGIN TRY
                CREATE FULLTEXT INDEX ON lab.RawContacts (FullName LANGUAGE 1033)
                KEY INDEX PK_lab_RawContacts
                WITH CHANGE_TRACKING AUTO;
            END TRY
            BEGIN CATCH
                PRINT CONCAT('O índice Full-Text não pôde ser criado: ', ERROR_MESSAGE());
            END CATCH;
        END;

    END;
END
ELSE
    PRINT 'Full-Text Search não está instalado nesta instância; a seção será ignorada.';
GO

-- Batch 2: executar as buscas depois que o batch de criação do índice terminar.
-- A população do Full-Text é assíncrona; se não houver resultados, aguarde e repita.
-- IMPACTO NO PLANO:
--   - CONTAINS e FREETEXT usam o índice Full-Text invertido. No plano, procure
--     uma operação Full-Text Match e uma junção de volta à tabela pela chave
--     exclusiva do Full-Text. O acesso à tabela pode ser lookup quando as colunas
--     selecionadas não estiverem cobertas pela chave do índice.
--   - CONTAINS é mais preciso: termos, frases, prefixos, operadores booleanos
--     e NEAR são transformados em uma condição estruturada de busca.
--   - FREETEXT é mais amplo: analisa a frase com word breaker e stemmer e busca
--     significado/formas flexionadas. Pode retornar mais candidatos e exigir mais
--     processamento Full-Text que um termo exato.
--   - Predicados apenas filtram linhas e não retornam relevância. Use CONTAINSTABLE
--     ou FREETEXTTABLE quando precisar da coluna RANK para ordenar resultados.
--   - LIKE não usa o índice Full-Text. `LIKE '%Smith%'` normalmente exige scan
--     por começar com curinga; um prefixo `LIKE 'Smith%'` pode usar seek com
--     um índice comum adequado.
IF FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') = 1
   AND EXISTS (SELECT 1 FROM sys.fulltext_indexes
               WHERE object_id = OBJECT_ID(N'lab.RawContacts'))
BEGIN
    -- Busca por prefixo: encontra palavras que começam com Smith.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, '"Smith*"');

    -- Busca por termo exato: encontra a palavra Smith, não uma substring arbitrária.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, '"Smith"');

    -- Busca por frase: as palavras devem aparecer juntas e nesta ordem.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, '"Alice Smith"');

    -- Buscas booleanas: os dois termos 
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, '"Alice" AND "Smith"');

        -- Buscas booleanas: pelo menos um dos termos.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, '"Smith" OR "Smyth"');

    -- Busca por proximidade: Alice e Smith em até cinco termos, nesta ordem.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE CONTAINS(FullName, 'NEAR((Alice, Smith), 5, TRUE)');

    -- FREETEXT delega a interpretação linguística ao mecanismo Full-Text Search.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE FREETEXT(FullName, N'Alice Smith');

    -- CONTAINSTABLE retorna a chave correspondente e RANK para ordenar os resultados.
    -- A chave permite juntar o resultado Full-Text novamente à tabela de origem.
    SELECT c.ContactID, c.FullName, ft.RANK AS RelevanceRank
    FROM CONTAINSTABLE(lab.RawContacts, FullName, N'"Smith"') AS ft
    JOIN lab.RawContacts AS c ON c.ContactID = ft.[KEY]
    ORDER BY ft.RANK DESC;

    -- FREETEXTTABLE faz a busca linguística mais ampla e também retorna RANK.
    SELECT c.ContactID, c.FullName, ft.RANK AS RelevanceRank
    FROM FREETEXTTABLE(lab.RawContacts, FullName, N'Alice Smith') AS ft
    JOIN lab.RawContacts AS c ON c.ContactID = ft.[KEY]
    ORDER BY ft.RANK DESC;

    -- LIKE é o equivalente à busca por substring: % encontra Smith em qualquer posição.
    -- CONTAINS com "Smith*" procura prefixo de palavra, não uma substring arbitrária.
    SELECT ContactID, FullName FROM lab.RawContacts
    WHERE FullName LIKE N'%Smith%';
END
ELSE
    PRINT 'Não foi possível encontrar um índice Full-Text em lab.RawContacts.';
GO


-- =================================================================================
-- PARTE 7: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

-- CENÁRIO 1: Deduplicação e preparação de nomes antes da vetorização (Embeddings/RAG).
-- O fluxo é somente leitura: gera candidatos, calcula pontuações, classifica a
-- confiança e permite revisão antes de qualquer UPDATE ou MERGE.

-- 1. Normalizar o texto usado pelos pipelines de matching e embeddings.
--    O valor original é preservado para exibição e auditoria.
SELECT ContactID,
       FullName AS NomeOriginal,
       UPPER(LTRIM(RTRIM(REPLACE(FullName, '  ', ' ')))) AS NomeNormalizado,
       SOUNDEX(FullName) AS CodigoSoundex
FROM lab.RawContacts;
GO

-- 2. Gerar pares candidatos. ContactID < ContactID evita comparar uma linha
--    consigo mesma e evita retornar o mesmo par duas vezes.
WITH Preparados AS
(
    SELECT ContactID,
           FullName,
           UPPER(LTRIM(RTRIM(REPLACE(FullName, '  ', ' ')))) AS NomeNormalizado
    FROM lab.RawContacts
), ParesCandidatos AS
(
    SELECT p1.ContactID AS ID1,
           p1.FullName AS Nome1,
           p2.ContactID AS ID2,
           p2.FullName AS Nome2,
           EDIT_DISTANCE_SIMILARITY(p1.NomeNormalizado, p2.NomeNormalizado) AS SimilaridadeEdicao,
           JARO_WINKLER_DISTANCE(p1.NomeNormalizado, p2.NomeNormalizado) AS DistanciaJaroWinkler,
           DIFFERENCE(p1.NomeNormalizado, p2.NomeNormalizado) AS DiferencaSoundex
    FROM Preparados AS p1
    JOIN Preparados AS p2 ON p1.ContactID < p2.ContactID
)
SELECT ID1, Nome1, ID2, Nome2,
       SimilaridadeEdicao,
       DistanciaJaroWinkler,
       DiferencaSoundex
FROM ParesCandidatos
WHERE SimilaridadeEdicao >= 80
   OR DistanciaJaroWinkler <= 0.20
   OR DiferencaSoundex >= 3;
GO

-- 3. Classificar candidatos em vez de fazer merge automaticamente.
--    HIGH exige evidência mais forte de duas métricas; REVIEW forma uma fila
--    para análise manual.
WITH Preparados AS
(
    SELECT ContactID,
           FullName,
           UPPER(LTRIM(RTRIM(REPLACE(FullName, '  ', ' ')))) AS NomeNormalizado
    FROM lab.RawContacts
), ParesPontuados AS
(
    SELECT p1.ContactID AS ID1, p1.FullName AS Nome1,
           p2.ContactID AS ID2, p2.FullName AS Nome2,
           EDIT_DISTANCE_SIMILARITY(p1.NomeNormalizado, p2.NomeNormalizado) AS SimilaridadeEdicao,
           JARO_WINKLER_DISTANCE(p1.NomeNormalizado, p2.NomeNormalizado) AS DistanciaJaroWinkler,
           DIFFERENCE(p1.NomeNormalizado, p2.NomeNormalizado) AS DiferencaSoundex
    FROM Preparados AS p1
    JOIN Preparados AS p2 ON p1.ContactID < p2.ContactID
)
SELECT ID1, Nome1, ID2, Nome2,
       SimilaridadeEdicao,
       DistanciaJaroWinkler,
       DiferencaSoundex,
       CASE
           WHEN SimilaridadeEdicao >= 95 AND DistanciaJaroWinkler <= 0.10 THEN 'HIGH'
           WHEN SimilaridadeEdicao >= 80 OR DistanciaJaroWinkler <= 0.20
                OR DiferencaSoundex >= 3 THEN 'REVIEW'
           ELSE 'LOW'
       END AS ConfiancaMatch
FROM ParesPontuados
WHERE SimilaridadeEdicao >= 80
   OR DistanciaJaroWinkler <= 0.20
   OR DiferencaSoundex >= 3;
GO

-- 4. Preparar uma lista de nomes normalizados para embeddings ou pesquisa.
--    A consulta não mescla as linhas de origem; apenas demonstra a granularidade
--    desejada para uma representação normalizada.
SELECT UPPER(LTRIM(RTRIM(REPLACE(FullName, '  ', ' ')))) AS NomeNormalizado,
       COUNT(*) AS QuantidadeLinhasOrigem,
       STRING_AGG(CONVERT(varchar(12), ContactID), ', ') AS IDsContatosOrigem
FROM lab.RawContacts
GROUP BY UPPER(LTRIM(RTRIM(REPLACE(FullName, '  ', ' '))))
ORDER BY NomeNormalizado;
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/03-advanced-tsql/03-regex-fuzzy-matching.md
-- =================================================================================================
