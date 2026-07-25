-- =================================================================================
-- DP-800 - LAB PRÁTICO: ARQUITETURA E CASOS DE USO DE RAG NATIVO EM T-SQL
-- Banco de Dados: AdventureWorks2025 (ou similar)
-- =================================================================================
-- NOTA DE CONFIGURAÇÃO: Para rodar este e outros scripts de laboratório, você precisa
-- restaurar o backup do banco de dados AdventureWorks (versão OLTP) disponível em:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- Este script demonstra a implementação do padrão Retrieval-Augmented Generation (RAG) em T-SQL:
--   1. Etapa RETRIEVE: Recuperação de Chunks Relevantes via Busca Híbrida / Vetorial
--   2. Etapa AUGMENT: Formatação e Anexação do Contexto no Prompt
--   3. Etapa GENERATE: Chamada ao LLM via REST Endpoint / External Model
--   4. Manutenção de Histórico de Conversação Multi-turn (`ConversationHistory`)
--   5. Cenários Práticos de Projeto (Grounding contra Alucinações de IA)
-- =================================================================================

USE AdventureWorks2025;
GO

-- Limpeza preventiva
DROP PROCEDURE IF EXISTS lab.usp_RagExecuteSearchAndGenerate;
DROP TABLE IF EXISTS lab.ConversationHistory;
DROP TABLE IF EXISTS lab.KnowledgeBaseChunks;
GO

-- Estrutura de Tabelas para Base de Conhecimento e Histórico RAG
CREATE TABLE lab.KnowledgeBaseChunks (
    ChunkID INT IDENTITY(1,1) PRIMARY KEY,
    DocumentTitle NVARCHAR(200) NOT NULL,
    ChunkContent NVARCHAR(MAX) NOT NULL,
    ChunkVector NVARCHAR(MAX) NULL -- Vetor de 1536 dimensões
);

CREATE TABLE lab.ConversationHistory (
    MessageID INT IDENTITY(1,1) PRIMARY KEY,
    SessionID UNIQUEIDENTIFIER NOT NULL,
    RoleName NVARCHAR(20) NOT NULL, -- 'system', 'user', 'assistant'
    MessageContent NVARCHAR(MAX) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
GO

INSERT INTO lab.KnowledgeBaseChunks (DocumentTitle, ChunkContent) VALUES 
(N'Politica de Garantia', N'A garantia de todos os capacetes e de 12 meses contra defeitos de fabricacao.'),
(N'Politica de Devolucao', N'Devolucoes sao aceitas em ate 30 dias apos a compra com embalagem original intacta.');
GO


-- =================================================================================
-- PARTE 1: IMPLEMENTAÇÃO DO FLUXO COMPLETO RAG (RETRIEVE - AUGMENT - GENERATE)
-- =================================================================================
-- CONCEITOS E DEFINIÇÕES CHAVE:
--   - RETRIEVE: Busca os fragmentos de texto mais relevantes na base de conhecimento.
--   - AUGMENT: Constrói a mensagem contendo as instruções do sistema, o contexto recuperado e a pergunta do usuário.
--   - GENERATE: Envia a requisição pronta para o LLM responder ancorado exclusivamente nos dados fornecidos (Grounding).

-- -- [PONTO DE ATENÇÃO DP-800]
CREATE PROCEDURE lab.usp_RagExecuteSearchAndGenerate
    @SessionID UNIQUEIDENTIFIER,
    @UserQuestion NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. RETRIEVE: Recuperar fragmentos de contexto mais relevantes
    DECLARE @RetrievedContext NVARCHAR(MAX);
    
    SELECT @RetrievedContext = STRING_AGG(CONCAT('- Documento: ', DocumentTitle, ' | Conteudo: ', ChunkContent), CHAR(10))
    FROM lab.KnowledgeBaseChunks
    WHERE ChunkContent LIKE N'%garantia%' OR ChunkContent LIKE N'%devolucao%';

    IF @RetrievedContext IS NULL 
        SET @RetrievedContext = N'Nenhum documento relevante encontrado na base de conhecimento.';

    -- 2. AUGMENT: Montar o Prompt com System Instruction + Grounding Context + Question
    DECLARE @SystemMessage NVARCHAR(MAX) = N'Voce e um assistente virtual de suporte da AdventureWorks. Responda a pergunta do usuario utilizando EXCLUSIVAMENTE o contexto fornecido abaixo. Se o contexto nao contiver a resposta, diga que nao possui essa informacao.';
    DECLARE @FullAugmentedPrompt NVARCHAR(MAX);

    SET @FullAugmentedPrompt = CONCAT(
        @SystemMessage, CHAR(10), CHAR(10),
        N'--- CONTEXTO RECUPERADO DA BASE DE DADOS ---', CHAR(10),
        @RetrievedContext, CHAR(10), CHAR(10),
        N'--- PERGUNTA DO USUARIO ---', CHAR(10),
        @UserQuestion
    );

    -- Registrar pergunta no histórico de conversa
    INSERT INTO lab.ConversationHistory (SessionID, RoleName, MessageContent)
    VALUES (@SessionID, N'user', @UserQuestion);

    -- 3. GENERATE: Exibir o Prompt Estruturado Pronto para Envio ao LLM (Azure OpenAI)
    PRINT '=================== PROMPT GROUNDED FINAL (PRONTO PARA ENVIO AO LLM) ===================';
    PRINT @FullAugmentedPrompt;

    -- Simulação da Resposta do LLM gerada a partir do contexto
    DECLARE @SimulatedLlmResponse NVARCHAR(MAX) = N'De acordo com a nossa politica, a garantia para capacetes e de 12 meses contra defeitos de fabricacao.';

    -- Registrar resposta no histórico de conversa
    INSERT INTO lab.ConversationHistory (SessionID, RoleName, MessageContent)
    VALUES (@SessionID, N'assistant', @SimulatedLlmResponse);

    SELECT @SimulatedLlmResponse AS RespostaGroundedDoLLM;
END;
GO

-- Testar execução do fluxo RAG nativo
DECLARE @SessionGuid UNIQUEIDENTIFIER = NEWID();
EXEC lab.usp_RagExecuteSearchAndGenerate 
    @SessionID = @SessionGuid, 
    @UserQuestion = N'Qual e o tempo de garantia dos capacetes?';
GO


-- =================================================================================
-- PARTE 2: CENÁRIOS PRÁTICOS DE PROJETO
-- =================================================================================

--- CENÁRIO 1: Matriz de Diferenciação entre Grounding (RAG) vs Fine-Tuning para o Exame DP-800
-- Guia de decisão fundamental para questões conceituais da certificação.

SELECT 
    'Grounding (RAG)' AS Conceito,
    'Injeta contexto atualizado no Prompt durante a inferencia' AS Mecanismo,
    'NÃO altera os pesos ou o modelo de IA' AS AlteracaoModelo,
    'Prevenir alucinações e consultar dados proprietários dinâmicos' AS Objetivo
UNION ALL
SELECT 
    'Fine-Tuning',
    'Treina o modelo com novos pares de exemplos de entrada e saída',
    'SIM (Altera os pesos internos do modelo)',
    'Ajustar tom de voz, formato estrito de saída ou vocabulário especializado';
GO
