-- =================================================================================
-- DP-800 - PRACTICAL LAB: NATIVE RAG ARCHITECTURE AND USE CASES IN T-SQL
-- Database: AdventureWorks2025 (or similar)
-- =================================================================================
-- SETUP NOTE: To run this and other lab scripts, you need
-- to restore the AdventureWorks database backup (OLTP version) available at:
-- https://learn.microsoft.com/pt-br/sql/samples/adventureworks-install-configure?view=sql-server-ver17&tabs=ssms
-- =================================================================================
-- SAFETY: Run only in a disposable lab database. This lab drops/recreates RAG tables
-- and a procedure. Retrieval and generation are intentionally simulated; the real
-- embedding/vector search and REST call are practiced in the adjacent sections/lab.
-- This script demonstrates the implementation of the Retrieval-Augmented Generation (RAG) pattern in T-SQL:
--   1. RETRIEVE Step: Retrieval of Relevant Chunks via Hybrid / Vector Search
--   2. AUGMENT Step: Formatting and Appending Context to the Prompt
--   3. GENERATE Step: LLM Call via REST Endpoint / External Model
--   4. Multi-turn Conversation History Maintenance (`ConversationHistory`)
--   5. Practical Project Scenarios (Grounding Against AI Hallucinations)
-- =================================================================================
-- THEORY REFERENCE: ../../../certification/11-rag/01-rag-use-cases.md
--    Open the theory guide alongside this lab for conceptual context.

USE AdventureWorks2025;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'lab')
    EXEC(N'CREATE SCHEMA lab AUTHORIZATION dbo;');
GO

-- Preventive cleanup
DROP PROCEDURE IF EXISTS lab.usp_RagExecuteSearchAndGenerate;
DROP TABLE IF EXISTS lab.ConversationHistory;
DROP TABLE IF EXISTS lab.KnowledgeBaseChunks;
GO

-- Table Structure for Knowledge Base and RAG History
CREATE TABLE lab.KnowledgeBaseChunks (
    ChunkID INT IDENTITY(1,1) PRIMARY KEY,
    DocumentTitle NVARCHAR(200) NOT NULL,
    ChunkContent NVARCHAR(MAX) NOT NULL,
    ChunkVector NVARCHAR(MAX) NULL -- 1536-dimension vector
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
-- PART 1: COMPLETE RAG FLOW IMPLEMENTATION (RETRIEVE - AUGMENT - GENERATE)
-- =================================================================================
-- KEY CONCEPTS AND DEFINITIONS:
--   - RETRIEVE: Searches for the most relevant text fragments in the knowledge base.
--   - AUGMENT: Builds the message containing system instructions, retrieved context, and the user's question.
--   - GENERATE: Sends the prepared request to the LLM to respond anchored exclusively in the provided data (Grounding).

-- -- [DP-800 ATTENTION POINT]
CREATE PROCEDURE lab.usp_RagExecuteSearchAndGenerate
    @SessionID UNIQUEIDENTIFIER,
    @UserQuestion NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. RETRIEVE: Retrieve the most relevant context fragments
    DECLARE @RetrievedContext NVARCHAR(MAX);
    
    SELECT @RetrievedContext = STRING_AGG(CONCAT('- Documento: ', DocumentTitle, ' | Conteudo: ', ChunkContent), CHAR(10))
    FROM lab.KnowledgeBaseChunks
    WHERE ChunkContent LIKE N'%garantia%' OR ChunkContent LIKE N'%devolucao%';

    IF @RetrievedContext IS NULL 
        SET @RetrievedContext = N'Nenhum documento relevante encontrado na base de conhecimento.';

    -- 2. AUGMENT: Build the Prompt with System Instruction + Grounding Context + Question
    DECLARE @SystemMessage NVARCHAR(MAX) = N'Voce e um assistente virtual de suporte da AdventureWorks. Responda a pergunta do usuario utilizando EXCLUSIVAMENTE o contexto fornecido abaixo. Se o contexto nao contiver a resposta, diga que nao possui essa informacao.';
    DECLARE @FullAugmentedPrompt NVARCHAR(MAX);

    SET @FullAugmentedPrompt = CONCAT(
        @SystemMessage, CHAR(10), CHAR(10),
        N'--- CONTEXTO RECUPERADO DA BASE DE DADOS ---', CHAR(10),
        @RetrievedContext, CHAR(10), CHAR(10),
        N'--- PERGUNTA DO USUARIO ---', CHAR(10),
        @UserQuestion
    );

    -- Register question in conversation history
    INSERT INTO lab.ConversationHistory (SessionID, RoleName, MessageContent)
    VALUES (@SessionID, N'user', @UserQuestion);

    -- 3. GENERATE: Display the Structured Prompt Ready for Sending to LLM (Azure OpenAI)
    PRINT '=================== PROMPT GROUNDED FINAL (PRONTO PARA ENVIO AO LLM) ===================';
    PRINT @FullAugmentedPrompt;

    -- Simulation of LLM Response generated from context
    DECLARE @SimulatedLlmResponse NVARCHAR(MAX) = N'De acordo com a nossa politica, a garantia para capacetes e de 12 meses contra defeitos de fabricacao.';

    -- Register response in conversation history
    INSERT INTO lab.ConversationHistory (SessionID, RoleName, MessageContent)
    VALUES (@SessionID, N'assistant', @SimulatedLlmResponse);

    SELECT @SimulatedLlmResponse AS RespostaGroundedDoLLM;
END;
GO

-- Test execution of the native RAG flow
DECLARE @SessionGuid UNIQUEIDENTIFIER = NEWID();
EXEC lab.usp_RagExecuteSearchAndGenerate 
    @SessionID = @SessionGuid, 
    @UserQuestion = N'Qual e o tempo de garantia dos capacetes?';
GO


-- =================================================================================
-- PART 2: PRACTICAL PROJECT SCENARIOS
-- =================================================================================

--- SCENARIO 1: Differentiation Matrix between Grounding (RAG) vs Fine-Tuning for the DP-800 Exam
-- Key decision guide for conceptual certification questions.

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

-- =================================================================================================
-- NEXT STEP: Review the theory at ../../../certification/11-rag/01-rag-use-cases.md
-- =================================================================================================
