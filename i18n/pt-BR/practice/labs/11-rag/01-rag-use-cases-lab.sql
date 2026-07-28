-- =================================================================================
-- DP-800 - LAB PRATICO COMPLETO: ARQUITETURA E CASOS DE USO DE RAG NATIVO EM T-SQL
-- Banco de Dados: AdventureWorks2025 (ou superior / LT - versao leve tambem funciona)
-- =================================================================================
-- NOTA DE CONFIGURACAO: Para rodar este script, voce precisa do banco AdventureWorks.
-- Download oficial: https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure
-- =================================================================================
-- OBJETIVOS DE APRENDIZADO DESTE LAB (alinhados a DP-800 Dominio 3):
--   1. Dominar o padrao RAG completo: RETRIEVE -> AUGMENT -> GENERATE
--   2. Diferenciar GROUNDING (RAG) de FINE-TUNING no contexto do exame
--   3. Implementar 4 casos de uso reais do mercado com AdventureWorks
--   4. Distinguir recuperacao em dados ESTRUTURADOS vs NAO ESTRUTURADOS vs HIBRIDO
--   5. Construir pipeline RAG MULTI-TURN (conversacional) com historico persistido
--   6. Conhecer 3 padroes de ARQUITETURA e quando usar cada um
--   7. Usar tabelas de DECISAO e TROUBLESHOOTING para o dia do exame
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/11-rag/01-rag-use-cases.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================

USE AdventureWorks2025;
GO

-- =================================================================================
-- LIMPEZA PREVENTIVA (re-execucao segura do lab)
-- =================================================================================
DROP PROCEDURE IF EXISTS lab.usp_RagSupportAssistant;
DROP PROCEDURE IF EXISTS lab.usp_RagProductAdvisor;
DROP PROCEDURE IF EXISTS lab.usp_RagDocumentQA;
DROP PROCEDURE IF EXISTS lab.usp_RagDataAnalyst;
DROP PROCEDURE IF EXISTS lab.usp_RagMultiTurnConversation;
DROP TABLE IF EXISTS lab.RAGErrorLog;
DROP TABLE IF EXISTS lab.ConversationHistory;
DROP TABLE IF EXISTS lab.DocumentChunks;
DROP TABLE IF EXISTS lab.PolicyDocuments;
DROP TABLE IF EXISTS lab.ProductEmbeddings;
GO

CREATE SCHEMA IF NOT EXISTS lab AUTHORIZATION dbo;
GO

PRINT '=========================================================';
PRINT '  LAB 11-RAG PARTE 1/7: ARQUITETURA BASE E TABELAS';
PRINT '=========================================================';
GO

-- =================================================================================
-- PARTE 1: ESTRUTURA DE TABELAS PARA OS 4 CASOS DE USO
-- =================================================================================
-- CONCEITO CHAVE DP-800: RAG usa a mesma base SQL para armazenar
--   - Dados estruturados (tabelas tradicionais)
--   - Embeddings vetoriais (coluna VECTOR ou NVARCHAR para simulacao)
--   - Chunks de documentos nao estruturados
--   - Historico de conversa (multi-turn)

-- ---- Tabela 1: Politicas da empresa (dados nao estruturados / documentos) ----
CREATE TABLE lab.PolicyDocuments (
    PolicyId     INT           NOT NULL PRIMARY KEY,
    Title        NVARCHAR(500) NOT NULL,
    Content      NVARCHAR(MAX) NOT NULL,
    Category     NVARCHAR(100) NOT NULL,
    LastUpdated  DATE          NOT NULL
);
GO

-- ---- Tabela 2: Chunks (fragmentos) de documentos COM embeddings vetoriais ----
-- IMPORTANTE DP-800: Em producao use o tipo VECTOR(1536).
-- Para compatibilidade e simulacao didatica, usamos NVARCHAR(MAX).
CREATE TABLE lab.DocumentChunks (
    ChunkId      INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    PolicyId     INT           NOT NULL FOREIGN KEY REFERENCES lab.PolicyDocuments(PolicyId),
    ChunkText    NVARCHAR(MAX) NOT NULL,
    ChunkVector  NVARCHAR(MAX) NULL,       -- Vetor de 1536 dimensoes (texto JSON para simulacao)
    Keywords     NVARCHAR(500) NULL        -- Para simulacao de Full-Text Search
);
GO

-- ---- Tabela 3: Catalogo de produtos com embeddings vetoriais (dados hibridos) ----
CREATE TABLE lab.ProductEmbeddings (
    ProductId      INT           NOT NULL PRIMARY KEY,
    ProductName    NVARCHAR(200) NOT NULL,
    Category       NVARCHAR(100) NOT NULL,
    Price          DECIMAL(10,2) NOT NULL,
    InStock        BIT           NOT NULL DEFAULT 1,
    Description    NVARCHAR(MAX) NOT NULL,
    DescriptionVector NVARCHAR(MAX) NULL  -- Embedding da descricao
);
GO

-- ---- Tabela 4: Historico de conversa (RAG multi-turn / conversacional) ----
CREATE TABLE lab.ConversationHistory (
    MessageId   INT              NOT NULL IDENTITY(1,1) PRIMARY KEY,
    SessionId   UNIQUEIDENTIFIER NOT NULL,
    Role        NVARCHAR(20)     NOT NULL,  -- 'system' | 'user' | 'assistant'
    Content     NVARCHAR(MAX)    NOT NULL,
    CreatedAt   DATETIME2        NOT NULL DEFAULT GETUTCDATE()
);
GO

-- ---- Tabela 5: Log de erros RAG para troubleshooting ----
CREATE TABLE lab.RAGErrorLog (
    ErrorId    INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    ErrorMessage NVARCHAR(MAX) NOT NULL,
    SessionId  UNIQUEIDENTIFIER NULL,
    Payload    NVARCHAR(MAX) NULL,
    ErrorTime  DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);
GO

PRINT '[OK] Tabelas RAG criadas: PolicyDocuments, DocumentChunks, ProductEmbeddings, ConversationHistory, RAGErrorLog';
GO

-- =================================================================================
-- CARGA DE DADOS DE EXEMPLO (baseados em AdventureWorks)
-- =================================================================================

-- ---- Politicas de suporte ao cliente (Caso de Uso 1) ----
INSERT INTO lab.PolicyDocuments (PolicyId, Title, Content, Category, LastUpdated) VALUES
(1, N'Politica de Garantia de Produtos',
 N'Todos os capacetes de ciclismo tem garantia de 12 meses contra defeitos de fabricacao.
Bicicletas completas tem garantia de 24 meses para o quadro e 12 meses para componentes.
Roupas e acessorios (luvas, oculos, camisetas) tem garantia de 90 dias.
Para acionar a garantia, e necessario apresentar a nota fiscal original e o produto.
Danos causados por uso indevido, acidente ou modificacao NAO sao cobertos.',
 N'Suporte', '2025-06-01'),
(2, N'Politica de Devolucao e Troca',
 N'Devolucoes sao aceitas em ate 30 dias corridos apos a data da compra.
Condicoes: produto com embalagem original intacta, sem sinais de uso, acompanhado de nota fiscal.
Itens de higiene pessoal (toucas, meias, luvas de neoprene) nao aceitam devolucao por questao de saude.
O reembolso e feito no mesmo metodo de pagamento da compra em ate 15 dias uteis.
Troca por tamanho errado: frete de envio da segunda via e por conta da empresa.',
 N'Atendimento', '2025-05-15'),
(3, N'Programa de Fidelidade AdventureClube',
 N'O AdventureClube e o programa de fidelidade da AdventureWorks.
Niveis: Bronze (ate R$ 5.000 em compras), Prata (R$ 5.001 a R$ 15.000), Ouro (acima de R$ 15.000).
Beneficios: Bronze = 5% de desconto em compras futuras. Prata = 8% desconto + frete gratis.
Ouro = 12% desconto + frete gratis + atendimento prioritario + garantia extendida de 6 meses.
Pontos expiram apos 24 meses da data da compra.',
 N'Fidelidade', '2025-03-20');
GO

-- ---- Chunks vinculados as politicas (com palavras-chave para busca simulada) ----
INSERT INTO lab.DocumentChunks (PolicyId, ChunkText, Keywords) VALUES
(1, N'Capacetes: garantia de 12 meses contra defeitos de fabricacao. Bicicletas: 24 meses no quadro, 12 meses nos componentes.', N'garantia capacete bicicleta quadro componente prazo'),
(1, N'Roupas e acessorios (luvas, oculos, camisetas): garantia de 90 dias. Necessario nota fiscal. Uso indevido nao coberto.', N'garantia roupa luva oculos camiseta 90 dias nota fiscal'),
(2, N'Devolucoes: prazo de 30 dias apos compra. Embalagem original intacta, sem uso, com nota fiscal.', N'devolucao troca prazo 30 dias embalagem nota fiscal'),
(2, N'Itens de higiene (toucas, meias, luvas neoprene) nao aceitam devolucao. Reembolso em 15 dias uteis.', N'devolucao higiene touca meia neoprene reembolso 15 dias'),
(3, N'AdventureClube niveis: Bronze (ate 5k), Prata (5k-15k), Ouro (>15k). Descontos: 5%, 8%, 12%.', N'fidelidade clube bronze prata ouro desconto nivel'),
(3, N'Prata: frete gratis. Ouro: frete gratis + atendimento prioritario + garantia extendida 6 meses. Pontos expiram em 24 meses.', N'frete gratis atendimento prioritario garantia extendida pontos expiracao');
GO

-- ---- Produtos AdventureWorks com descricoes ricas (Caso de Uso 2 e 4) ----
INSERT INTO lab.ProductEmbeddings (ProductId, ProductName, Category, Price, InStock, Description) VALUES
(771, N'Capacete de Ciclismo Mountain Pro', N'Capacetes', 349.90, 1,
 N'Capacete MTB profissional com 22 ventilacoes, sistema de ajuste MIPS, peso 280g.
 Ideal para trilhas leves e moderadas. Certificado por normas brasileiras.
 Disponivel nas cores preto, vermelho e azul. Tamanhos: M (54-58cm) e G (58-62cm).
 Inclui bolsa de transporte e visera removivel.'),
(772, N'Capacete de Ciclismo Speed Aero', N'Capacetes', 499.90, 1,
 N'Capacete de estrada aerodinamico com design wind-tunnel tested. 18 ventilacoes,
 sistema MIPS integrado, peso 260g. Ideal para competicoes e longas pedaladas.
 Cores: matte black, white/red, team blue. Tamanhos: P, M, G.'),
(773, N'Luva de Ciclismo Gel Pro', N'Acessorios', 79.90, 1,
 N'Luva com palma em gel anti-vibracao, tecido respiravel, punho ajustavel.
 Ideal para ciclismo de longa distancia. Reduz fadiga e formigamento nas maos.
 Disponivel nos tamanhos P, M, G, GG. Cores: preto, azul, vermelho.'),
(774, N'Oculos de Sol Ciclismo Polarizado', N'Acessorios', 189.90, 0,
 N'Oculos polarizados anti-UV400, 3 lentes intercambiaveis (transparente, fumê, amarela).
 Estrutura em TR-90 super leve e resistente. Inclui case e cordao de seguranca.
 Sem estoque no momento - previsao de reposicao: 2 semanas.'),
(775, N'Bicicleta Mountain Bike Aro 29 - 12v', N'Bicicletas', 3499.90, 1,
 N'MTB aro 29, quadro de aluminio 6061, conjunto de transmissao 12v,
 freios a disco hidraulicos, suspensao dianteira com travas 100mm de curso.
 Ideal para trilhas de nivel intermediario. Disponivel nos tamanhos 15, 17 e 19.'),
(776, N'Camisa de Ciclismo Manga Curta DryFit', N'Vestuario', 119.90, 1,
 N'Camisa de ciclismo DryFit com 3 bolsos traseiros, zipper completo,
 tecido anti-UV e antibacteriano. Corte anatomico feminino e masculino.
 Cores: preto, azul, verde, rosa. Tamanhos: PP ao GG.');
GO

PRINT '[OK] Dados de exemplo carregados: 3 politicas, 6 chunks, 6 produtos';
GO

-- =================================================================================
-- PARTE 2/7: PADRAO RAG COMPLETO - RETRIEVE -> AUGMENT -> GENERATE
-- =================================================================================
-- CONCEITO DP-800: RAG = Retrieve (buscar) + Augment (aumentar prompt) + Generate (gerar resposta)
-- OBS: A etapa GENERATE (chamada real ao LLM via REST) sera praticada no LAB 02.
-- Aqui focamos na logica das etapas RETRIEVE e AUGMENT que sao 100% no SQL.

PRINT CHAR(13) + CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG PARTE 2/7: PADRAO RAG COMPLETO (3 ETAPAS)';
PRINT '=========================================================';
GO

-- ---- ETAPA 1: RETRIEVE (Recuperar informacoes relevantes) ----
-- Simulando busca vetorial + busca textual (busca hibrida = VECTOR + FTS)
-- Em producao: usar VECTOR_DISTANCE('cosine', ...) + CONTAINS (Full-Text Search)
DECLARE @UserQuery NVARCHAR(500) = N'Qual a garantia de capacetes de bicicleta?';
DECLARE @Keywords NVARCHAR(500) = N'%garantia%capacete%';

PRINT '> ETAPA 1: RETRIEVE - Buscando chunks relevantes para: ' + @UserQuery;

SELECT
    dc.ChunkId,
    pd.Title AS FonteDocumento,
    dc.ChunkText,
    CASE WHEN dc.Keywords LIKE @Keywords THEN 1 ELSE 0 END AS MatchKeywords
FROM lab.DocumentChunks dc
INNER JOIN lab.PolicyDocuments pd ON pd.PolicyId = dc.PolicyId
WHERE dc.Keywords LIKE @Keywords
ORDER BY MatchKeywords DESC;
GO

-- ---- ETAPA 2: AUGMENT (Montar prompt com instrucoes + contexto + pergunta) ----
DECLARE @RetrievedContext NVARCHAR(MAX);
DECLARE @SystemInstructions NVARCHAR(MAX) = N'Voce e um assistente de suporte da AdventureWorks.
REGRAS OBRIGATORIAS (LEIA ANTES DE RESPONDER):
1. Responda EXCLUSIVAMENTE com base no CONTEXTO FORNECIDO abaixo.
2. Se a resposta NAO estiver no contexto, diga exatamente: "Nao possuo informacao suficiente para responder a esta pergunta."
3. Nunca invente, adivinhe ou suponha dados que nao estejam no contexto.
4. Se houver valores numericos (prazos, porcentagens, valores), cite-os com precisao.
5. Termine a resposta citando a FONTE (nome do documento) que usou.';

SELECT @RetrievedContext = STRING_AGG(
    CONCAT('[FONTE: ', pd.Title, '] ', dc.ChunkText),
    CHAR(13) + CHAR(10)
)
FROM lab.DocumentChunks dc
INNER JOIN lab.PolicyDocuments pd ON pd.PolicyId = dc.PolicyId
WHERE dc.Keywords LIKE N'%garantia%capacete%';

DECLARE @UserQuestion NVARCHAR(500) = N'Qual a garantia de capacetes de bicicleta?';
DECLARE @FullPrompt NVARCHAR(MAX) =
    CONCAT(
        N'=== INSTRUCOES DO SISTEMA ===', CHAR(13)+CHAR(10),
        @SystemInstructions, CHAR(13)+CHAR(10), CHAR(13)+CHAR(10),
        N'=== CONTEXTO RECUPERADO DO BANCO ===', CHAR(13)+CHAR(10),
        @RetrievedContext, CHAR(13)+CHAR(10), CHAR(13)+CHAR(10),
        N'=== PERGUNTA DO USUARIO ===', CHAR(13)+CHAR(10),
        @UserQuestion
    );

PRINT CHAR(13)+CHAR(10) + '> ETAPA 2: AUGMENT - Prompt montado (pronto para envio ao LLM):';
PRINT '--------------------------------------------------------------------------------';
PRINT @FullPrompt;
PRINT '--------------------------------------------------------------------------------';
GO

-- ---- ETAPA 3: GENERATE (Simulado - resposta LLM ancorada no contexto) ----
-- OBS: Chamada real ao LLM sera no Lab 02 com sp_invoke_external_rest_endpoint
DECLARE @LlmGroundedResponse NVARCHAR(MAX) = N'Segundo a [FONTE: Politica de Garantia de Produtos],
os capacetes de ciclismo possuem garantia de 12 meses contra defeitos de fabricacao.
Para acionar a garantia, e necessario apresentar a nota fiscal original e o produto.
Danos causados por uso indevido nao sao cobertos.';

PRINT CHAR(13)+CHAR(10) + '> ETAPA 3: GENERATE - Resposta do LLM ancorada (Grounded):';
PRINT '--------------------------------------------------------------------------------';
PRINT @LlmGroundedResponse;
PRINT '--------------------------------------------------------------------------------';
GO

-- =================================================================================
-- PARTE 3/7: GROUNDING vs FINE-TUNING (Diferenca critica para o exame)
-- =================================================================================
-- DICA DP-800: Esta diferenca cai em TODAS as aplicacoes de certificacao AI.
--   GROUNDING / RAG = Injeta contexto no PROMPT durante a inferencia (pesos NAO mudam)
--   FINE-TUNING     = Altera os PESOS do modelo com dados de treinamento

PRINT CHAR(13) + CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG PARTE 3/7: GROUNDING vs FINE-TUNING';
PRINT '=========================================================';
GO

SELECT
    'GROUNDING (RAG)' AS Conceito,
    N'Injeta contexto factual diretamente no PROMPT no momento da consulta (inferencia)' AS Mecanismo,
    N'NAO. Pesos do LLM permanecem INTACTOS' AS AlteraPesosDoModelo,
    N'Por token de API consumido em cada chamada' AS ModeloCusto,
    N'Ideal para dados que mudam frequentemente: precos, estoque, politicas, dados do cliente' AS QuandoUsar,
    N'Sim - as fontes ficam registradas no contexto do prompt' AS CitacoesPossiveis
UNION ALL
SELECT
    'FINE-TUNING',
    N'Treina o modelo com dataset de pares (input/output), ajustando a camada de pesos',
    N'SIM. Gera um modelo CUSTOMIZADO com novos pesos',
    N'Horas de GPU de treinamento (inicial) + inferencia do modelo custom (por token)',
    N'Aprender estilo de resposta, tom de voz, formato de saida estrito, vocabulario especializado',
    N'Nao - o conhecimento se mistura aos pesos e nao tem rastreabilidade direta'
UNION ALL
SELECT
    'RAG + Fine-Tuning (combinados)',
    N'Fine-tuning para estilo + RAG para dados atualizados (melhor dos dois mundos)',
    N'SIM (apenas no fine-tuning; o RAG nao altera pesos)',
    N'Ambos combinados',
    N'Cenarios enterprise: chatbots corporativos com personalidade + informacao atualizada',
    N'Sim (via RAG, o fine-tuning em si nao prove citacoes)';
GO

-- Cenario de decisao: assinale a abordagem correta
PRINT CHAR(13)+CHAR(10) + N'=== EXERCICIO DE FIXACAO (questao estilo exame DP-800) ===';
PRINT 'Cenario: A AdventureWorks quer implementar um assistente que responde sobre';
PRINT 'politicas de devolucao. As politicas mudam todo trimestre. Qual abordagem?';
PRINT '';
PRINT 'A) Fine-Tuning mensal no GPT-4o com as politicas atualizadas';
PRINT 'B) RAG com as politicas armazenadas no Azure SQL, recuperadas via busca vetorial';
PRINT 'C) Prompt engeneering hardcoded, escrevendo as politicas diretamente no system message';
PRINT 'D) Nenhuma das anteriores - o LLM ja sabe tudo do treinamento';
PRINT '';
PRINT N'>>> RESPOSTA CORRETA: B (RAG) - Dados mudam frequentemente -> RAG, nao fine-tuning';
GO

-- =================================================================================
-- PARTE 4/7: 4 CASOS DE USO PRATICOS (usando dados AdventureWorks)
-- =================================================================================

PRINT CHAR(13) + CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG PARTE 4/7: 4 CASOS DE USO PRATICOS';
PRINT '=========================================================';
GO

-- =================================================================================
-- CASO DE USO 1: ASSISTENTE DE SUPORTE AO CLIENTE
-- Fonte: Documentos de politica (dados NAO ESTRUTURADOS)
-- Busca: Hibrida (Busca vetorial + Full-Text Search)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '>> CASO DE USO 1: ASSISTENTE DE SUPORTE AO CLIENTE (Documentos)';
GO

CREATE OR ALTER PROCEDURE lab.usp_RagSupportAssistant
    @UserQuestion NVARCHAR(1000),
    @TopKChunks   INT = 3
AS
BEGIN
    SET NOCOUNT ON;

    -- ---- ETAPA RETRIEVE: Busca hibrida (palavras-chave + relevancia simulada) ----
    DECLARE @RetrievedContext NVARCHAR(MAX) = '';

    SELECT @RetrievedContext = STRING_AGG(
        CONCAT('[Documento: ', pd.Title, ' | Categoria: ', pd.Category, '] ',
               CHAR(13)+CHAR(10), '  Trecho: ', dc.ChunkText),
        CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
    )
    FROM (
        SELECT TOP (@TopKChunks)
            dc.ChunkId, dc.PolicyId, dc.ChunkText,
            Relevancia = CASE
                WHEN dc.ChunkText LIKE '%garantia%' THEN 10
                WHEN dc.ChunkText LIKE '%devolucao%' THEN 9
                WHEN dc.ChunkText LIKE '%fidelidade%' OR dc.ChunkText LIKE '%clube%' THEN 8
                ELSE 1 END
            + CASE WHEN dc.Keywords LIKE N'%' + @UserQuestion + N'%' THEN 5 ELSE 0 END
        FROM lab.DocumentChunks dc
        INNER JOIN lab.PolicyDocuments pd ON pd.PolicyId = dc.PolicyId
        ORDER BY Relevancia DESC
    ) AS RankedChunks
    INNER JOIN lab.PolicyDocuments pd ON pd.PolicyId = RankedChunks.PolicyId
    INNER JOIN lab.DocumentChunks dc ON dc.ChunkId = RankedChunks.ChunkId;

    IF @RetrievedContext = '' SET @RetrievedContext = N'[Nenhum documento relevante encontrado na base]';

    -- ---- ETAPA AUGMENT: Prompt estruturado ----
    DECLARE @SystemMsg NVARCHAR(MAX) = N'Voce e um atendente de suporte tecnico da AdventureWorks.
Regras:
- Use SOMENTE os documentos fornecidos.
- Se a informacao nao estiver documentada, diga que nao sabe.
- Cite sempre o nome do documento ao responder.
- Mantenha tom profissional, claro e acolhedor.';

    DECLARE @PromptFinal NVARCHAR(MAX) =
        N'SYSTEM: ' + @SystemMsg + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
      + N'CONTEXTO (fonte: Azure SQL -> DocumentChunks):' + CHAR(13)+CHAR(10) + @RetrievedContext + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
      + N'PERGUNTA CLIENTE: ' + @UserQuestion;

    -- ---- SAIDA DO LAB (simulando GENERATE) ----
    SELECT
        'Caso Uso 1 - Suporte Cliente'  AS CasoDeUso,
        @UserQuestion                   AS PerguntaUsuario,
        @RetrievedContext               AS ContextoRecuperado,
        @PromptFinal                    AS PromptAugmentado,
        N'Resposta simulada: consultar politica aplicavel e responder com base no contexto acima.'
                                    AS RespostaLLM_Simulada;
END;
GO

-- Teste do Caso de Uso 1
EXEC lab.usp_RagSupportAssistant
    @UserQuestion = N'Quero devolver um capacete. Como funciona?';
GO

-- =================================================================================
-- CASO DE USO 2: BUSCA E RECOMENDACOES DE PRODUTOS
-- Fonte: Catalogo de produtos (dados HIBRIDOS = estruturado + embedding)
-- Busca: Busca vetorial + filtros estruturados (categoria, preco, estoque)
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '>> CASO DE USO 2: RECOMENDACAO DE PRODUTOS (Hibrido)';
GO

CREATE OR ALTER PROCEDURE lab.usp_RagProductAdvisor
    @UserNeedDescription NVARCHAR(1000),
    @MaxPrice            DECIMAL(10,2) = 5000,
    @OnlyInStock         BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    -- ---- ETAPA RETRIEVE: Busca vetorial SIMULADA + filtros estruturados ----
    -- Em producao: VECTOR_DISTANCE('cosine', DescriptionVector, @user_query_vector)
    DECLARE @RetrievedContext NVARCHAR(MAX) = '';

    SELECT @RetrievedContext = STRING_AGG(
        CONCAT(
            '[Produto ID: ', pe.ProductId, '] ',
            pe.ProductName, ' | Categoria: ', pe.Category,
            ' | Preco: R$ ', CAST(pe.Price AS VARCHAR(12)),
            ' | Estoque: ', CASE pe.InStock WHEN 1 THEN 'DISPONIVEL' ELSE 'SEM ESTOQUE' END,
            CHAR(13)+CHAR(10), '  Caracteristicas: ', pe.Description
        ),
        CHAR(13)+CHAR(10) + '---' + CHAR(13)+CHAR(10)
    )
    FROM (
        SELECT TOP 5
            pe.ProductId, pe.ProductName, pe.Category, pe.Price, pe.InStock, pe.Description,
            RelevanciaSimulada = CASE
                WHEN pe.Description LIKE N'%' + @UserNeedDescription + N'%' THEN 10
                WHEN pe.ProductName LIKE N'%' + @UserNeedDescription + N'%' THEN 9
                WHEN pe.Description LIKE N'%ventilacao%' OR pe.Description LIKE N'%MIPS%' THEN 6
                WHEN pe.Description LIKE N'%leve%' OR pe.Description LIKE N'%resistente%' THEN 5
                ELSE 2 END
        FROM lab.ProductEmbeddings pe
        WHERE pe.Price <= @MaxPrice
          AND (@OnlyInStock = 0 OR pe.InStock = 1)
        ORDER BY RelevanciaSimulada DESC, pe.Price ASC
    ) AS RankedProducts;

    IF @RetrievedContext = '' SET @RetrievedContext = N'[Nenhum produto corresponde aos filtros selecionados]';

    -- ---- ETAPA AUGMENT ----
    DECLARE @SystemMsg NVARCHAR(MAX) = N'Voce e um consultor de vendas especializado em ciclismo.
Regras:
- Recomende SOMENTE os produtos da lista fornecida.
- Explique POR QUE cada produto foi recomendado (caracteristicas correspondentes a necessidade).
- Marque claramente se houver produto SEM ESTOQUE e informe a previsao se disponivel.
- Se nenhum produto for adequado, diga honestamente que nao ha match e sugira ajustar os filtros.';

    DECLARE @PromptFinal NVARCHAR(MAX) =
        N'SYSTEM: ' + @SystemMsg + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
      + N'CATALOGO DE PRODUTOS (RECUPERADO DO AZURE SQL):' + CHAR(13)+CHAR(10) + @RetrievedContext + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
      + N'NECESSIDADE DO CLIENTE: ' + @UserNeedDescription + CHAR(13)+CHAR(10)
      + N'Preco maximo informado: R$ ' + CAST(@MaxPrice AS VARCHAR(12));

    SELECT
        'Caso Uso 2 - Recomendacao de Produtos' AS CasoDeUso,
        @UserNeedDescription                    AS NecessidadeCliente,
        @RetrievedContext                       AS ProdutosRecuperados,
        @PromptFinal                            AS PromptAugmentado;
END;
GO

-- Teste Caso de Uso 2: Cliente quer capacete leve e ventilado para trilha
EXEC lab.usp_RagProductAdvisor
    @UserNeedDescription = N'capacete leve ventilado para trilha de bicicleta',
    @MaxPrice            = 600,
    @OnlyInStock         = 1;
GO

-- =================================================================================
-- CASO DE USO 3: Q&A EM DOCUMENTOS (Knowledge Base interno)
-- Fonte: Chunks de documentos (dados NAO ESTRUTURADOS)
-- Busca: Exclusivamente vetorial por similaridade semantica
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '>> CASO DE USO 3: Q&A EM DOCUMENTOS (Knowledge Base)';
GO

CREATE OR ALTER PROCEDURE lab.usp_RagDocumentQA
    @Question   NVARCHAR(1000),
    @DocFilter  NVARCHAR(100) = NULL   -- 'IT' | 'Seguranca' | 'RH' | NULL = todos
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Context NVARCHAR(MAX) = '';

    -- Recupera top-3 chunks mais relevantes (simulando VECTOR_DISTANCE)
    SELECT @Context = STRING_AGG(
        CONCAT('CHUNK[', dc.ChunkId, '] doc="', pd.Title, '" -> ', dc.ChunkText),
        CHAR(13)+CHAR(10)
    )
    FROM (
        SELECT TOP 3 dc.ChunkId, dc.PolicyId, dc.ChunkText,
               ScoreSemanticoSimulado = ABS(CHECKSUM(@Question, dc.ChunkText)) % 100
        FROM lab.DocumentChunks dc
        INNER JOIN lab.PolicyDocuments pd ON pd.PolicyId = dc.PolicyId
        WHERE (@DocFilter IS NULL OR pd.Category = @DocFilter)
        ORDER BY ScoreSemanticoSimulado DESC
    ) TopChunks
    INNER JOIN lab.DocumentChunks dc ON dc.ChunkId = TopChunks.ChunkId
    INNER JOIN lab.PolicyDocuments pd ON pd.PolicyId = dc.PolicyId;

    DECLARE @SystemMsg NVARCHAR(MAX) = N'Voce e um assistente de base de conhecimento.
Sempre responda APENAS com base nos chunks fornecidos.
Se a resposta envolver dois chunks, mencione ambos.
Sempre termine com "Fontes: CHUNK[X] e CHUNK[Y]".';

    DECLARE @Prompt NVARCHAR(MAX) =
        N'SYSTEM: ' + @SystemMsg + CHAR(13)+CHAR(10)
      + N'CHUNKS RECUPERADOS:' + CHAR(13)+CHAR(10) + ISNULL(@Context, 'Nenhum') + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
      + N'PERGUNTA: ' + @Question;

    SELECT
        'Caso Uso 3 - Q&A Documentos' AS CasoDeUso,
        @Question                     AS Pergunta,
        ISNULL(@Context, 'Nenhum')    AS ChunksRecuperados,
        @Prompt                       AS PromptFinal;
END;
GO

EXEC lab.usp_RagDocumentQA
    @Question  = N'Quais os beneficios do nivel Ouro no programa de fidelidade?',
    @DocFilter = NULL;
GO

-- =================================================================================
-- CASO DE USO 4: ASSISTENTE DE ANALISE DE DADOS (DADOS ESTRUTURADOS)
-- Fonte: Tabelas relacionais AdventureWorks (dados ESTRUTURADOS)
-- Busca: Query SQL tradicional (SELECT, JOIN, GROUP BY) - SEM busca vetorial
-- Contexto: Resultado da query -> FOR JSON -> prompt
-- =================================================================================
PRINT CHAR(13)+CHAR(10) + '>> CASO DE USO 4: ASSISTENTE DE ANALISE DE DADOS (Estruturado)';
GO

CREATE OR ALTER PROCEDURE lab.usp_RagDataAnalyst
    @BusinessQuestion NVARCHAR(1000),
    @StartDate        DATE = '2013-01-01',
    @EndDate          DATE = '2014-12-31'
AS
BEGIN
    SET NOCOUNT ON;

    -- ---- ETAPA RETRIEVE: Query SQL diretamente em dados estruturados ----
    -- Nao ha busca vetorial aqui - os dados ja sao estruturados.
    -- A pergunta de negocio guia QUAL query rodar.

    DECLARE @SalesSummaryJSON NVARCHAR(MAX) = (
        SELECT TOP 10
            pc.Name                    AS CategoriaProduto,
            SUM(sod.LineTotal)         AS TotalVendas,
            COUNT(DISTINCT soh.SalesOrderID) AS NumeroPedidos,
            AVG(sod.LineTotal)         AS TicketMedio
        FROM Sales.SalesOrderHeader soh
        INNER JOIN Sales.SalesOrderDetail sod ON sod.SalesOrderID = soh.SalesOrderID
        INNER JOIN Production.Product p ON p.ProductID = sod.ProductID
        INNER JOIN Production.ProductSubcategory psc ON psc.ProductSubcategoryID = p.ProductSubcategoryID
        INNER JOIN Production.ProductCategory pc ON pc.ProductCategoryID = psc.ProductCategoryID
        WHERE soh.OrderDate BETWEEN @StartDate AND @EndDate
        GROUP BY pc.Name
        ORDER BY TotalVendas DESC
        FOR JSON PATH
    );

    -- Resumo tabular em texto para o prompt
    DECLARE @SummaryText NVARCHAR(MAX) = '';
    SELECT @SummaryText = STRING_AGG(
        CONCAT('- ', CategoriaProduto,
               ': Vendas R$ ', CONVERT(VARCHAR(20), CONVERT(MONEY, TotalVendas), 1),
               ' | ', NumeroPedidos, ' pedidos',
               ' | Ticket Medio R$ ', CONVERT(VARCHAR(20), CONVERT(MONEY, TicketMedio), 1)),
        CHAR(13)+CHAR(10)
    )
    FROM OPENJSON(@SalesSummaryJSON) WITH (
        CategoriaProduto NVARCHAR(100) '$.CategoriaProduto',
        TotalVendas      DECIMAL(18,2) '$.TotalVendas',
        NumeroPedidos    INT           '$.NumeroPedidos',
        TicketMedio      DECIMAL(18,2) '$.TicketMedio'
    );

    -- ---- ETAPA AUGMENT ----
    DECLARE @SystemMsg NVARCHAR(MAX) = N'Voce e um analista de dados senior.
Analise os resultados SQL fornecidos e responda a pergunta de negocios.
Inclua numeros concretos em sua resposta. Destaque o TOP 3 e o ultimo colocado.
Se algum dado estiver faltando, mencione a limitacao.';

    DECLARE @Prompt NVARCHAR(MAX) =
        N'SYSTEM: ' + @SystemMsg + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
      + N'PERGUNTA DE NEGOCIO: ' + @BusinessQuestion + CHAR(13)+CHAR(10)
      + N'Periodo analisado: ' + CAST(@StartDate AS VARCHAR) + ' ate ' + CAST(@EndDate AS VARCHAR) + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
      + N'RESULTADO DA CONSULTA SQL (Fonte: AdventureWorks SalesOrderHeader/Detail):' + CHAR(13)+CHAR(10)
      + ISNULL(@SummaryText, 'Nenhum dado retornado no periodo');

    SELECT
        'Caso Uso 4 - Analista de Dados' AS CasoDeUso,
        @BusinessQuestion                AS PerguntaNegocio,
        ISNULL(@SummaryText, 'Nenhum')   AS DadosEstruturadosRecuperados,
        @SalesSummaryJSON                AS DadosJSON_paraComparacao,
        @Prompt                          AS PromptFinal;
END;
GO

-- Teste Caso de Uso 4
EXEC lab.usp_RagDataAnalyst
    @BusinessQuestion = N'Quais categorias de produto tiveram melhor desempenho de vendas?',
    @StartDate        = '2013-01-01',
    @EndDate          = '2013-12-31';
GO

-- =================================================================================
-- PARTE 5/7: TIPOS DE DADOS NA RECUPERACAO RAG
-- =================================================================================
-- DP-800: Diferencie as 3 abordagens - isso cai no exame!

PRINT CHAR(13) + CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG PARTE 5/7: DADOS ESTRUTURADOS x NAO ESTRUTURADOS x HIBRIDO';
PRINT '=========================================================';
GO

SELECT
    N'Dados NAO ESTRUTURADOS' AS TipoDeDado,
    N'Documentos PDF/Word, emails, paginas web, manuais, artigos' AS FontesTipicas,
    N'Sim - necessario quebrar em chunks de ~512 tokens' AS NecessitaChunking,
    N'Busca VETORIAL por similaridade semantica + FULL-TEXT SEARCH por palavra-chave' AS EstrategiaRecuperacao,
    N'Caso de Uso 1 (Suporte) e Caso 3 (Q&A Documentos)' AS LaboratorioCorrespondente
UNION ALL
SELECT
    N'Dados ESTRUTURADOS',
    N'Tabelas relacionais: Orders, Products, Customers (schemas conhecidos)',
    N'Nao - use o resultado da query diretamente',
    N'SQL tradicional: SELECT / JOIN / GROUP BY / WHERE. Nao ha busca vetorial.',
    N'Caso de Uso 4 (Assistente de Analise de Dados)'
UNION ALL
SELECT
    N'HIBRIDO (Estruturado + Nao Estruturado)',
    N'Catalogo de produtos (preco/categoria = estruturado; descricao/avaliacoes = texto)',
    N'Sim para a parte NAO estruturada (embeddings de descricoes/reviews)',
    N'Vector Search em descricoes + filtros estruturados (WHERE preco < X, categoria = Y)',
    N'Caso de Uso 2 (Recomendacao de Produtos)';
GO

-- =================================================================================
-- PARTE 6/7: RAG MULTI-TURN (Conversacional) + 3 Padroes de Arquitetura
-- =================================================================================
-- DP-800: Multi-turn = o LLM lembra das perguntas anteriores.
-- IMPLEMENTACAO: Incluir historico recente no prompt (cuidado com limite de tokens!)

PRINT CHAR(13) + CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG PARTE 6/7: MULTI-TURN E PADROES DE ARQUITETURA';
PRINT '=========================================================';
GO

-- ---- Implementacao: RAG Multi-turn ----
CREATE OR ALTER PROCEDURE lab.usp_RagMultiTurnConversation
    @SessionID    UNIQUEIDENTIFIER,
    @UserQuestion NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Recuperar HISTORICO recente (MAX: ultimas 10 mensagens ou 1 hora)
    -- DICA DP-800: Nunca envie TODO o historico. Tokens acumulam rapido!
    DECLARE @RecentHistory NVARCHAR(MAX) = '';
    SELECT @RecentHistory = STRING_AGG(
        CONCAT(UPPER(Role), N': ', Content),
        CHAR(13)+CHAR(10)
    ) WITHIN GROUP (ORDER BY CreatedAt)
    FROM (
        SELECT TOP 10 Role, Content, CreatedAt
        FROM lab.ConversationHistory
        WHERE SessionId = @SessionID
          AND CreatedAt >= DATEADD(HOUR, -1, GETUTCDATE())
        ORDER BY CreatedAt DESC
    ) AS LastMessages;

    -- 2. Registrar a pergunta atual no historico
    INSERT INTO lab.ConversationHistory (SessionId, Role, Content)
    VALUES (@SessionID, N'user', @UserQuestion);

    -- 3. RETRIEVE: Buscar contexto relevante (igual ao Caso 1)
    DECLARE @RetrievedContext NVARCHAR(MAX) = '';
    SELECT @RetrievedContext = STRING_AGG(
        CONCAT('[', pd.Title, '] ', dc.ChunkText),
        CHAR(13)+CHAR(10)
    )
    FROM (
        SELECT TOP 3 dc.ChunkId, dc.PolicyId, dc.ChunkText
        FROM lab.DocumentChunks dc
        INNER JOIN lab.PolicyDocuments pd ON pd.PolicyId = dc.PolicyId
        ORDER BY ABS(CHECKSUM(@UserQuestion, dc.ChunkText))
    ) Top
    INNER JOIN lab.DocumentChunks dc ON dc.ChunkId = Top.ChunkId
    INNER JOIN lab.PolicyDocuments pd ON pd.PolicyId = Top.PolicyId;

    -- 4. AUGMENT: Incluir HISTORICO + CONTEXTO + PERGUNTA ATUAL no prompt
    DECLARE @SystemMsg NVARCHAR(MAX) = N'Voce e um agente conversacional.
Mantenha o contexto da conversa anterior. Referencie mensagens passadas se relevante.
Responda apenas com base no contexto recuperado.';

    DECLARE @PromptFinal NVARCHAR(MAX) =
        N'=== SYSTEM ===' + CHAR(13)+CHAR(10) + @SystemMsg + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
      + N'=== HISTORICO RECENTE DA CONVERSA (ULTIMAS 10 MSGS) ===' + CHAR(13)+CHAR(10)
      + ISNULL(@RecentHistory, '[Novo historico - primeira interacao]') + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
      + N'=== CONTEXTO RAG ===' + CHAR(13)+CHAR(10) + ISNULL(@RetrievedContext, 'Nenhum') + CHAR(13)+CHAR(10)+CHAR(13)+CHAR(10)
      + N'=== NOVA PERGUNTA ===' + CHAR(13)+CHAR(10) + @UserQuestion;

    -- 5. Simular resposta e gravar no historico
    DECLARE @SimulatedAnswer NVARCHAR(MAX) =
        N'[Resposta simulada do LLM considerando historico e o contexto da base SQL]';
    INSERT INTO lab.ConversationHistory (SessionId, Role, Content)
    VALUES (@SessionID, N'assistant', @SimulatedAnswer);

    SELECT
        N'RAG Multi-Turn'                       AS Modo,
        @SessionID                              AS SessaoId,
        ISNULL(@RecentHistory, '[vazia/inicio]') AS HistoricoRecente,
        ISNULL(@RetrievedContext, 'Nenhum')     AS ContextoRecuperado,
        @PromptFinal                            AS PromptFinal;
END;
GO

-- Simular conversa de 3 turnos
DECLARE @Sessao UNIQUEIDENTIFIER = NEWID();
PRINT N'--- Turno 1: Pergunta inicial ---';
EXEC lab.usp_RagMultiTurnConversation
    @SessionID = @Sessao,
    @UserQuestion = N'Qual a garantia de capacetes?';
GO

PRINT N'--- Turno 2: Pergunta de follow-up (precisa do contexto do turno 1) ---';
DECLARE @Sessao UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000000';
SELECT TOP 1 @Sessao = SessionId FROM lab.ConversationHistory ORDER BY MessageId DESC;
EXEC lab.usp_RagMultiTurnConversation
    @SessionID = @Sessao,
    @UserQuestion = N'E se for bicicleta inteira?';
GO

-- ---- 3 Padroes de Arquitetura RAG ----
PRINT CHAR(13)+CHAR(10) + N'--- PADROES DE ARQUITETURA RAG (3 abordagens) ---';

SELECT
    N'Padrao 1: RAG IN-DATABASE (Tudo no SQL)' AS NomePadrao,
    N'T-SQL + stored procedures dentro do Azure SQL/Fabric' AS OndeRoda,
    N'Azure SQL -> AI_GENERATE_EMBEDDINGS -> VECTOR_SEARCH -> FOR JSON -> sp_invoke_external_rest_endpoint -> LLM' AS Fluxo,
    N'Tudo em 1 lugar. Sem codigo de app. Baixa latencia (1 round trip). Jobs agendados.' AS Vantagens,
    N'Menos flexivel. Debug mais dificil. Menos bibliotecas utilitarias.' AS Desvantagens,
    N'lab.usp_RagSupportAssistant (este lab - se conectasse direto ao LLM)' AS ExemploLab
UNION ALL
SELECT
    N'Padrao 2: RAG NA CAMADA DE APLICACAO (Python/C#)',
    N'Aplicacao cliente (servico externo ao banco)',
    N'App -> SDK Azure OpenAI Embeddings -> SQL query (VECTOR_SEARCH) -> construir prompt em codigo -> SDK Chat -> retornar resposta',
    N'Muito flexivel. Debug facil. Tratamento de erros avancado. Frameworks (LangChain, Semantic Kernel).',
    N'Mais componentes para gerenciar. Latencia multiplos round-trips. Mais codigo.',
    N'API Flask/Django ou C# Web API que chama AdventureWorks + Azure OpenAI'
UNION ALL
SELECT
    N'Padrao 3: AZURE AI SEARCH + SQL (Search Gerenciado)',
    N'Servico Azure AI Search (middleware gerenciado)',
    N'SQL -> (indexacao sincrona/async) -> Indice AI Search -> query usuario -> AI Search Hybrid + RRF -> Azure OpenAI',
    N'Busca gerenciada, RRF nativo, ranking de alta qualidade. Escala independente do DB. Otimo para muitos documentos.',
    N'Custo adicional. Dados duplicados (SQL + indice). Latencia de sincronizacao.',
    N'Base de 100k+ documentos de politica indexada no AI Search, sincronizada do Azure SQL';
GO

-- =================================================================================
-- PARTE 7/7: TABELAS DE DECISAO E TROUBLESHOOTING (guia para o exame)
-- =================================================================================

PRINT CHAR(13) + CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG PARTE 7/7: TABELAS DE APOIO PARA O EXAME';
PRINT '=========================================================';
GO

-- ---- Tabela 1: Casos de Uso por Tipo de Dado ----
PRINT CHAR(13)+CHAR(10) + N'--- TABELA 1: CASOS DE USO x TIPO DE DADO x LATENCIA ---';

SELECT
    N'Chat FAQ / Politicas de atendimento' AS CasoDeUso,
    N'Nao estruturado (PDFs, docs)'       AS TipoDeDado,
    N'Hibrida (Full-Text + Vector Search)' AS TipoBusca,
    N'< 3 segundos'                       AS MetaLatencia,
    N'lab.usp_RagSupportAssistant'        AS ProcLaboratorio
UNION ALL SELECT N'Recomendacao de produtos catalogo', N'Hibrido (preco/estoque + descricao)', N'Vector + filtro estruturado (WHERE)', N'< 2 segundos', N'lab.usp_RagProductAdvisor'
UNION ALL SELECT N'Q&A em manuais e base de conhecimento', N'Nao estruturado', N'Vector Search puro', N'< 3 segundos', N'lab.usp_RagDocumentQA'
UNION ALL SELECT N'Resumo de vendas e relatorios BI', N'Estruturado (tabelas SQL)', N'Apenas query SQL (SELECT/JOIN/GROUP)', N'< 5 segundos', N'lab.usp_RagDataAnalyst'
UNION ALL SELECT N'Chat historico do cliente (360 CRM)', N'Estruturado', N'SQL match por CustomerID', N'< 1 segundo', N'usp_RagMultiTurnConversation + JOIN em Customer';
GO

-- ---- Tabela 2: Problemas Comuns e Correcoes ----
PRINT CHAR(13)+CHAR(10) + N'--- TABELA 2: PROBLEMAS COMUNS RAG x CAUSA x CORRECAO ---';

SELECT
    N'LLM responde errado MESMO com RAG'      AS Problema,
    N'CONTEXTO ERRADO recuperado. A busca nao trouxe os chunks certos.' AS CausaProvavel,
    N'Melhorar recuperacao: usar Busca HIBRIDA (vector + FTS), ajustar estrategia de chunking, mudar modelo de embedding, aumentar top-K de 3->5.' AS Correcao
UNION ALL
SELECT
    N'LLM inventa/inventa informacao (alucina)',
    N'Prompt sem instrucao de "limite"; ou contexto realmente nao tem a resposta.',
    N'Adicione no SYSTEM MESSAGE: "Answer ONLY from the provided context. If the answer is not found, say I do not have information."; definir temperature=0.'
UNION ALL
SELECT
    N'Alta latencia (demora > 10 segundos)',
    N'Embedding + busca + LLM tudo em sequencia; indices ruins.',
    N'Paralelizar o que for possivel. Criar indice ANN (Approximate Nearest Neighbor). Trocar modelo por gpt-4o-mini (mais rapido).'
UNION ALL
SELECT
    N'Prompt muito longo - estouro da janela de contexto do LLM',
    N'Top-K muito alto ou chunks grandes. Historico ilimitado.',
    N'Limitar a 3-5 chunks relevantes MAX. Reduzir tamanho de chunk (256-512 tokens). Limitar historico por tempo ou quantidade (ex: ultimas 10 mensagens).'
UNION ALL
SELECT
    N'Respostas inconsistentes entre chamadas iguais',
    N'Temperature > 0 introduz aleatoriedade.',
    N'Definir explicitamente "temperature": 0 no payload. Para criatividade suba para 0.2-0.3, mas para Q&A factual fique em 0.';
GO

-- ---- Verificacao final do lab ----
PRINT CHAR(13) + CHAR(10) + '=========================================================';
PRINT '  LAB 11-RAG (01): CHECKLIST DE CONCLUSAO';
PRINT '=========================================================';

SELECT N'[OK] Entendi o padrao RAG = Retrieve + Augment + Generate' AS ChecklistItem UNION ALL
SELECT N'[OK] Sei a diferenca entre GROUNDING (RAG) e FINE-TUNING' UNION ALL
SELECT N'[OK] Implementei os 4 casos de uso: Suporte, Produtos, Documentos, Analista' UNION ALL
SELECT N'[OK] Distingo recuperacao em dados Estruturados / Nao / Hibrido' UNION ALL
SELECT N'[OK] Implementei historico multi-turn com ConversationHistory' UNION ALL
SELECT N'[OK] Conheco os 3 padroes de arquitetura e seus trade-offs' UNION ALL
SELECT N'[OK] Tenho tabelas de troubleshooting para aplicar no exame';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> PROXIMO PASSO: Execute o LAB 02 para aprender a chamar';
PRINT N'    sp_invoke_external_rest_endpoint, usar DATABASE SCOPED CREDENTIAL,';
PRINT N'    e parsear respostas JSON reais do Azure OpenAI.';
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/11-rag/01-rag-use-cases.md
-- =================================================================================================
