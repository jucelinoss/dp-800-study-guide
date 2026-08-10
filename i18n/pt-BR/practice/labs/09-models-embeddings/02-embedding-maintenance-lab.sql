-- =================================================================================
-- DP-800 - LAB PRATICO COMPLETO: MANUTENCAO E REGENERACAO DE EMBEDDINGS
-- (Dirty Tracking, Triggers, Change Tracking, CDC, CES, Foundry, Azure Functions)
-- Banco de Dados: AdventureWorks2025 (ou versao LT - Light)
-- =================================================================================
-- SEGURANÇA: Execute somente em um banco descartável. O script remove/recria a
-- tabela e o trigger do lab e usa dados sintéticos. As chamadas à API externa ficam
-- comentadas até que um external model de teste seja configurado.
-- OBJETIVOS DE APRENDIZADO (alinhados DP-800 Dominio 3):
--   1. Conceito de EMBEDDING DRIFT e por que manutencao nao e opcional
--   2. Dirty tracking: coluna BIT flag + watermarks timestamps
--   3. 6 METODOS COMPLETOS de manutencao (com codigo funcional ou didatico)
--   4. Trigger SINCRONO (Table Trigger) com AI_GENERATE_EMBEDDINGS
--   5. Change Tracking (CT) com CHANGETABLE, watermark versionado, coluna mask
--   6. CDC (Change Data Capture) com __$operation e LSN watermark
--   7. CES (Change Event Streaming) - SQL Server 2025+ / Azure SQL DB preview
--   8. Microsoft Foundry (seção COMPLETA: arquitetura, quando usar/evitar, Foundry vs CES)
--   9. Azure Functions SQL Trigger Binding (exemplo C# completo)
--  10. Logic Apps low-code + procedure GetProductsNeedingEmbedding
--  11. Flowchart decisao (volume >1000 linhas/min? Fabric? Latencia <30s? Low-code?)
--  12. Problemas comuns tabela 4 + 4 dicas exame
-- =================================================================================
-- REFERENCIAS MICROSOFT LEARN:
--   - About Change Tracking SQL:
--     https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-tracking-sql-server
--   - Azure Functions SQL Trigger Binding:
--     https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-azure-sql-trigger
--   - Fabric Change Event Streaming (CES):
--     https://learn.microsoft.com/en-us/fabric/database/sql/change-event-streaming
--   - Microsoft Foundry (RAG and Vector Search solutions):
--     https://learn.microsoft.com/en-us/foundry/
-- =================================================================================
-- REFERÊNCIA TEÓRICA: ../../../certification/09-models-embeddings/02-embedding-maintenance.md
--    Abra o guia teórico junto com este laboratório para contexto conceitual.
-- =================================================================================

USE AdventureWorks2025;
GO

-- =================================================================================
-- LIMPEZA PREVENTIVA
-- =================================================================================
DROP PROCEDURE IF EXISTS lab.usp_ReembedModelMigration;
DROP PROCEDURE IF EXISTS lab.usp_GetProductsNeedingEmbedding;
DROP PROCEDURE IF EXISTS lab.usp_RunChangeTrackingEmbeddingMaintenance;
DROP TABLE IF EXISTS lab.EmbeddingWatermark;
DROP TABLE IF EXISTS lab.EmbeddingCDCWatermark;
DROP TABLE IF EXISTS lab.EmbeddingOutbox;
DROP TABLE IF EXISTS lab.ProductVectorCatalog;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'lab')
    EXEC(N'CREATE SCHEMA lab AUTHORIZATION dbo;');
GO

PRINT '=========================================================';
PRINT '  LAB 09-ME (02) PARTE 1/8: DRIFT + EMBEDDINGS COMO DADOS DERIVADOS';
PRINT '=========================================================';
GO

-- =================================================================================
-- PARTE 1: Fundamentos - Embeddings = Dados Derivados, nao Verdade de Negocio
-- =================================================================================

SELECT
    N'Embedding = snapshot pontual do significado do TEXTO naquela VERSAO do modelo.'                                 AS Conceito,
    N'Drift = texto de origem MUDOU (ou modelo mudou) mas o VETOR antigo continua ali.' AS OQueEDrift,
    N'Busca semantica parece "funcionar" mas retorna resultados desatualizados / errados.' AS EfeitoNoUsuario
UNION ALL
SELECT
    N'Trigger que detecta mudancas de texto no UPDATE',
    N'Flag IsEmbeddingStale BIT = 1',
    N'Job roda UPDATE ... WHERE IsEmbeddingStale = 1 para regenerar'
UNION ALL
SELECT
    N'Quando mudar de MODELO (ex: ada-002 -> 3-small) ou DIMENSAO',
    N'NAO HA COMO reaproveitar vetores antigos. Espacos vetoriais SAO DIFERENTES.',
    N'>>> REGRA OBRIGATORIA EXAME: REGERAR TODOS os embeddings (limpar tudo, reprocessar 100% das linhas).'
UNION ALL
SELECT
    N'Trocar CHUNKING (tamanho/overlap) ou TEXTO formatado do TextToEmbed',
    N'Conteudo semantico do input MUDOU, vetor nao corresponde mais.',
    N'Re-embed TOTAL tambem. Nao e possivel "converter" vetores entre estrategias.';
GO

-- ---- Tabela principal de trabalho com TODAS as colunas de manutencao ----
CREATE TABLE lab.ProductVectorCatalog (
    ProductID              INT           NOT NULL PRIMARY KEY,
    ProductName            NVARCHAR(200) NOT NULL,
    Description            NVARCHAR(MAX) NOT NULL,
    DescriptionEmbedding   VECTOR(1536)  NULL,        -- 1536 = 3-small
    ModelVersionUsed       NVARCHAR(100) NULL,        -- qual modelo gerou este vetor (auditoria!)
    -- ============== FLAGS DE MANUTENCAO ==============
    IsEmbeddingStale       BIT           NOT NULL DEFAULT 1,    -- 1 = precisa re-embedar
    LastUpdated            DATETIME2     NOT NULL DEFAULT GETUTCDATE(),   -- mudou texto
    EmbeddingGeneratedAt   DATETIME2     NULL,                    -- quando foi embeddado
    EmbeddingAttempts      INT           NOT NULL DEFAULT 0,     -- qtd tentativas (ajuda rate-limit)
    LastEmbeddingError     NVARCHAR(500) NULL                   -- ultima msg erro (se houver)
);
GO

INSERT INTO lab.ProductVectorCatalog (ProductID, ProductName, Description) VALUES
(101, N'Capacete Premium',   N'Capacete aerodinamico com fibra de carbono e ventilacao extra.'),
(102, N'Luvas de Ciclismo',  N'Luvas acolchoadas com gel e tecido respiravel para longas pedaladas.'),
(103, N'Kit Troca Pneu',     N'Kit com 2 espátulas de nylon, câmara extra e mini bomba CO2 de 16g.'),
(104, N'Farol Led Dianteiro',N'Farol led 1000 lumens USB-C recarregavel, 4 modos de iluminacao.');
GO

SELECT ProductID, ProductName, IsEmbeddingStale, LastUpdated, EmbeddingGeneratedAt
FROM lab.ProductVectorCatalog;
GO

-- =================================================================================
-- PARTE 2: TABELA COMPARATIVA DOS 6 METODOS + REGRA DE OURO DO EXAME
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (02) PARTE 2/8: 6 METODOS E REGRA DE OURO DO EXAME';
PRINT '=========================================================';
GO

SELECT
    N'Table Trigger (AFTER INSERT/UPDATE)' AS Metodo,
    N'Quase real-time (sub-segundos)'     AS Latencia,
    N'Baixa - T-SQL nativo'               AS Complexidade,
    N'Nenhuma (in-DB)'                    AS Infraestrutura,
    N'Tabelas PEQUENAS, baixissimo volume de escrita' AS MelhorPara,
    N'SINCRONO. Se o endpoint de IA CAIR, a TRANSACAO de INSERT/UPDATE FALHA.' AS Risco
UNION ALL SELECT
    N'Dirty Tracking + SQL Agent Job (Batch)',
    N'Zero latencia na escrita (assincrono)',
    N'Baixa',
    N'SQL Agent (ou Automation Runbook)',
    N'Padrão para bancos on-premises e Azure SQL com volume médio; valide o volume real.',
    N'Vetor fica "velho" ate a proxima execucao do job (1 minuto a varias horas).'
UNION ALL SELECT
    N'Change Tracking (CHANGETABLE polling)',
    N'Baixa (segundos a minutos, dependendo schedule)',
    N'Media',
    N'SQL Agent / WebJob / Scheduler',
    N'Volume MODERADO / precisa saber QUAIS LINHAS mudaram desde ultima vez.',
    N'Se SyncVersion mais antiga que CHANGE_RETENTION -> re-embedar TUDO de novo!'
UNION ALL SELECT
    N'CDC (Change Data Capture)',
    N'Media (mesmo CT - polling)',
    N'Media',
    N'SQL Agent / CDC jobs',
    N'Precisa de AUDITORIA (before + after values), historico, conformidade LGPD.',
    N'Overhead de storage maior; requer agente CDC; retencao de LSNs pode ficar complexa.'
UNION ALL SELECT
    N'Azure Functions + SQL Trigger Binding',
    N'Quase real-time (polling CT automatico)',
    N'Media',
    N'Azure Functions + Connection string',
    N'Arquitetura serverless cloud-native, escala sob demanda.',
    N'Nao e push real! Faz polling internamente. Requer Change Tracking ativo.'
UNION ALL SELECT
    N'CES (Change Event Streaming) - preview',
    N'Quase real-time (push via Event Hubs / Eventstream)',
    N'Media',
    N'Azure Event Hubs / Fabric Eventstream',
    N'SQL Server 2025+ / Azure SQL DB. Consumidores downstream Fabric.';
UNION ALL SELECT
    N'Microsoft Foundry (declarativo, pipeline)',
    N'Segundos a minutos (agendado / on-demand)',
    N'Baixa (sem codigo!)',
    N'Foundry + conexoes',
    N'Workflows IA multiplos (RAG indexing + evaluation + batch scoring).',
    N'Nao para latencia sub-30s. Acompanhe lock-in de plataforma.';
GO

PRINT CHAR(13)+CHAR(10) + N'====================== REGRA DE OURO DO EXAME ======================';
PRINT N'';
PRINT N'  TRIGGERS (Table Trigger) = SIMPLES, mas SINCRONOS.';
PRINT N'    -> Se o Azure OpenAI ficar OFFLINE -> sua aplicacao tambem fica OFFLINE.';
PRINT N'    -> Alto volume = 1 chamada API por escrita = latencia + custo altos.';
PRINT N'';
PRINT N'  CHANGE TRACKING / CDC = DESACOPLADOS (assincronos).';
PRINT N'    -> Escrita no banco continua RAPIDA e FUNCIONA mesmo se IA cair.';
PRINT N'    -> Atraso = polling interval (1 min -> 15 min).';
PRINT N'';
PRINT N'  CES (Change Event Streaming) = PUSH-based.';
PRINT N'    -> Em PREVIEW para SQL Server 2025 / Azure SQL Database.';
PRINT N'    -> Nao e exclusivo do Fabric. Nao confundir com CDC ou CT.';
PRINT N'===================================================================';
GO

-- =================================================================================
-- PARTE 3: Metodo 1 - TABLE TRIGGER (Dirty Flag + AI_GENERATE_EMBEDDINGS)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (02) PARTE 3/8: METODO 1 - TABLE TRIGGER';
PRINT '=========================================================';
GO

-- 3.1 Trigger para MARCAR dirty flag (SEMPRE execute esse, seguro!)
CREATE OR ALTER TRIGGER lab.trg_ProductVectorCatalog_MarkStale
ON lab.ProductVectorCatalog
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(Description) OR UPDATE(ProductName)
    BEGIN
        UPDATE p
        SET
            IsEmbeddingStale     = 1,
            LastUpdated          = GETUTCDATE(),
            EmbeddingGeneratedAt = NULL   -- limpa a data, afinal agora esta stale
        FROM lab.ProductVectorCatalog p
        INNER JOIN inserted i ON p.ProductID = i.ProductID;
    END
END;
GO

-- 3.2 Trigger OPTATIVO para EMBEDAR na hora (SINCRONO, use apenas para tabelas PEQUENAS!)
PRINT N'--- Trigger 2 (optativo): gera embedding DURANTE o UPDATE (sincrono!) ---';
PRINT N'/*';
PRINT N'CREATE OR ALTER TRIGGER lab.trg_ProductVectorCatalog_EmbedSync';
PRINT N'ON lab.ProductVectorCatalog';
PRINT N'AFTER INSERT, UPDATE';
PRINT N'AS';
PRINT N'BEGIN';
PRINT N'    SET NOCOUNT ON;';
PRINT N'    IF UPDATE(Description)';
PRINT N'    BEGIN';
PRINT N'        UPDATE p';
PRINT N'        SET DescriptionEmbedding = AI_GENERATE_EMBEDDINGS(
                 i.Description USE MODEL [lab].[AzureOpenAI_Embedding3Small] ),';
PRINT N'            ModelVersionUsed     = N''text-embedding-3-small'',';
PRINT N'            IsEmbeddingStale     = 0,';
PRINT N'            EmbeddingGeneratedAt = SYSUTCDATETIME()';
PRINT N'        FROM lab.ProductVectorCatalog p';
PRINT N'        INNER JOIN inserted i ON p.ProductID = i.ProductID;';
PRINT N'    END;';
PRINT N'END;';
PRINT N'*/';
GO

-- 3.3 Teste do mark stale
UPDATE lab.ProductVectorCatalog
SET Description = N'Capacete aerodinamico com fibra de carbono, ventilacao extra e LUZ LED traseira integrada.'
WHERE ProductID = 101;
GO

SELECT ProductID, ProductName, IsEmbeddingStale, EmbeddingGeneratedAt, LastUpdated
FROM lab.ProductVectorCatalog
ORDER BY ProductID;
GO

-- =================================================================================
-- PARTE 4: Metodo 2 - CHANGE TRACKING (Com Watermark de versao BIGINT)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (02) PARTE 4/8: METODO 2 - CHANGE TRACKING';
PRINT '=========================================================';
GO

-- Tabela WATERMARK
CREATE TABLE lab.EmbeddingWatermark (
    TableName    NVARCHAR(128) NOT NULL PRIMARY KEY,
    SyncVersion  BIGINT        NOT NULL,
    LastRunAt    DATETIME2     NOT NULL DEFAULT GETUTCDATE()
);
GO

PRINT CHAR(13)+CHAR(10) + N'--- BLOCO DIDATICO: Habilitar CT + Watermark Inicial ---';
PRINT N'/*';
PRINT N'  -- Requer permissao ALTER DATABASE';
PRINT N'  ALTER DATABASE AdventureWorks2025';
PRINT N'  SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON);';
PRINT N'';
PRINT N'  ALTER TABLE lab.ProductVectorCatalog';
PRINT N'  ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON); -- importante!'
PRINT N'';
PRINT N'  INSERT INTO lab.EmbeddingWatermark (TableName, SyncVersion)';
PRINT N'  VALUES (N''lab.ProductVectorCatalog'', CHANGE_TRACKING_CURRENT_VERSION());';
PRINT N'*/';
GO

-- Procedure MANUTENCAO por CT (passivel de rodar via SQL Agent a cada 2 minutos)
CREATE OR ALTER PROCEDURE lab.usp_RunChangeTrackingEmbeddingMaintenance
    @BatchSize INT = 200
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TableName NVARCHAR(128) = N'lab.ProductVectorCatalog';
    DECLARE @LastVersion  BIGINT;
    DECLARE @CurVersion   BIGINT = CHANGE_TRACKING_CURRENT_VERSION();
    DECLARE @RetentionDays INT = 7;

    SELECT @LastVersion = SyncVersion
    FROM lab.EmbeddingWatermark
    WHERE TableName = @TableName;

    -- Se a versao de watermark for muito antiga, re-embedar TUDO
    DECLARE @EstimatedRetainedVersion BIGINT = CHANGE_TRACKING_MIN_VALID_VERSION(OBJECT_ID(@TableName));
    IF @LastVersion < @EstimatedRetainedVersion
    BEGIN
        PRINT '! WARNING: SyncVersion mais antiga que retencao! Re-embedando TUDO...';
        UPDATE lab.ProductVectorCatalog SET IsEmbeddingStale = 1;
    END

    -- Usar um CTE com CHANGETABLE para pegar as linhas alteradas E verificar se Description mudou
    WITH ChangedRows AS (
        SELECT
            ct.ProductID,
            MudouDescricao = CASE
                WHEN ct.SYS_CHANGE_COLUMNS IS NULL THEN 1   -- insert/update sem mask = tudo mudou
                ELSE CHANGE_TRACKING_IS_COLUMN_IN_MASK(
                        COLUMNPROPERTY(OBJECT_ID(@TableName), 'Description', 'ColumnId'),
                        ct.SYS_CHANGE_COLUMNS)
            END
        FROM CHANGETABLE(CHANGES lab.ProductVectorCatalog, @LastVersion) AS ct
        WHERE ct.SYS_CHANGE_OPERATION IN ('I', 'U')   -- Insert ou Update
    )
    UPDATE TOP (@BatchSize) pvc
    SET
        IsEmbeddingStale = 1
    FROM lab.ProductVectorCatalog pvc
    INNER JOIN ChangedRows cr ON cr.ProductID = pvc.ProductID
    WHERE cr.MudouDescricao = 1;

    -- Atualizar watermark
    UPDATE lab.EmbeddingWatermark
    SET SyncVersion = @CurVersion,
        LastRunAt   = SYSUTCDATETIME()
    WHERE TableName = @TableName;

    SELECT
        @LastVersion                                 AS VersaoAnterior,
        @CurVersion                                  AS VersaoAtual,
        @@ROWCOUNT                                   AS LinhasMarcadasStale;
END;
GO

PRINT CHAR(13)+CHAR(10) + N'--- Simulando re-marked (para uso real com CT ativo, rode a proc acima via SQL Agent) ---';
EXEC lab.usp_RunChangeTrackingEmbeddingMaintenance @BatchSize = 100;
GO

-- =================================================================================
-- PARTE 5: Metodo 3 - CDC (LSN Watermark + __$operation)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (02) PARTE 5/8: METODO 3 - CDC';
PRINT '=========================================================';
GO

CREATE TABLE lab.EmbeddingCDCWatermark (
    CaptureInstance NVARCHAR(200) NOT NULL PRIMARY KEY,
    LastProcessedLSN BINARY(10)   NOT NULL
);
GO

PRINT N'--- BLOCO DIDATICO CDC: Habilitar + Processar ---';
PRINT N'/*';
PRINT N'  -- Habilita CDC no DB (uma vez); requer SQL Server Agent rodando';
PRINT N'  EXEC sys.sp_cdc_enable_db;';
PRINT N'';
PRINT N'  -- Habilita CDC numa tabela (cria capture instance lab_ProductVectorCatalog)';
PRINT N'  EXEC sys.sp_cdc_enable_table';
PRINT N'      @source_schema = N''lab'',';
PRINT N'      @source_name   = N''ProductVectorCatalog'',';
PRINT N'      @role_name     = NULL,            -- role para ler a tabela CDC';
PRINT N'      @capture_instance = N''lab_ProductVectorCatalog'';';
PRINT N'';
PRINT N'  -- Watermark inicial';
PRINT N'  INSERT INTO lab.EmbeddingCDCWatermark (CaptureInstance, LastProcessedLSN)';
PRINT N'  VALUES (N''lab_ProductVectorCatalog'', sys.fn_cdc_get_min_lsn(N''lab_ProductVectorCatalog''));';
PRINT N'';
PRINT N'  -- Job de processamento CDC (rodar via SQL Agent):';
PRINT N'  DECLARE @from_lsn BINARY(10), @to_lsn BINARY(10) = sys.fn_cdc_get_max_lsn();';
PRINT N'';
PRINT N'  SELECT @from_lsn = LastProcessedLSN';
PRINT N'  FROM lab.EmbeddingCDCWatermark';
PRINT N'  WHERE CaptureInstance = N''lab_ProductVectorCatalog'';';
PRINT N'';
PRINT N'  -- net changes = estado FINAL de cada linha (mesmo que tenha mudado varias vezes)';
PRINT N'  WITH ChangedProducts AS (';
PRINT N'      SELECT ProductID, __$operation';
PRINT N'      FROM cdc.fn_cdc_get_net_changes_lab_ProductVectorCatalog(@from_lsn, @to_lsn, N''all'')';
PRINT N'      WHERE __$operation IN (2, 5)   -- 2 = INSERT, 5 = INSERT_OR_UPDATE';
PRINT N'  )';
PRINT N'  UPDATE p SET IsEmbeddingStale = 1';
PRINT N'  FROM lab.ProductVectorCatalog p';
PRINT N'  INNER JOIN ChangedProducts cp ON cp.ProductID = p.ProductID;';
PRINT N'';
PRINT N'  UPDATE lab.EmbeddingCDCWatermark';
PRINT N'  SET LastProcessedLSN = @to_lsn';
PRINT N'  WHERE CaptureInstance = N''lab_ProductVectorCatalog'';';
PRINT N'*/';
GO

-- =================================================================================
-- PARTE 6: Metodos 4, 5, 6 + MICROSOFT FOUNDRY (toda a secao!)
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (02) PARTE 6/8: METODO 4 AZURE FUNCTIONS + METODO 5 CES';
PRINT '=========================================================';
GO

-- --- Outbox Pattern (genericamente utilizado por todos os metodos async) ---
CREATE TABLE lab.EmbeddingOutbox (
    EventId     BIGINT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    ProductID   INT              NOT NULL,
    EventType   NVARCHAR(50)     NOT NULL,     -- 'EmbeddingRefreshRequested'
    PayloadJSON NVARCHAR(MAX)    NOT NULL,     -- description + etc
    CreatedAt   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    ProcessedAt DATETIME2        NULL,         -- consumidor marca aqui
    ConsumedBy  NVARCHAR(200)    NULL          -- 'AzureFunction' / 'CES_Notebook' / 'Foundry'
);
GO

CREATE OR ALTER TRIGGER lab.trg_ProductVectorCatalog_OutboxPublisher
ON lab.ProductVectorCatalog
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(Description) OR UPDATE(ProductName)
    BEGIN
        INSERT INTO lab.EmbeddingOutbox (ProductID, EventType, PayloadJSON)
        SELECT
            i.ProductID,
            N'EmbeddingRefreshRequested',
            (SELECT
                i.ProductID       AS ProductID,
                i.ProductName     AS ProductName,
                i.Description     AS Description,
                GETUTCDATE()      AS EventTime
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM inserted i;
    END
END;
GO

-- Teste trigger outbox
UPDATE lab.ProductVectorCatalog SET Description = Description + N' (Atualizado: estoque em Porto Alegre RS).'
WHERE ProductID = 104;
GO

SELECT EventId, ProductID, EventType, ProcessedAt, ConsumedBy, PayloadJSON
FROM lab.EmbeddingOutbox ORDER BY EventId;
GO

-- --- 6.1 Metodo 4 - AZURE FUNCTIONS C# (SQL Trigger Binding) ---
PRINT CHAR(13)+CHAR(10) + N'--- METODO 4: Azure Functions C# (SQL Trigger Binding) ---';
PRINT N'';
PRINT N'O SQL Trigger binding do Azure Functions USA Change Tracking internamente';
PRINT N'via polling. Ele NAO e um push trigger real. Precisa de Change Tracking ativo.';
PRINT N'';
PRINT N'[FunctionName("UpdateProductEmbeddings")]';
PRINT N'public static async Task Run(';
PRINT N'    [SqlTrigger("[lab].[ProductVectorCatalog]", "SqlConnectionString")]';
PRINT N'    IReadOnlyList<SqlChange<ProductVectorCatalog>> changes,';
PRINT N'    ILogger log)';
PRINT N'{';
PRINT N'    // SDK Azure.AI.OpenAI';
PRINT N'    var client = new AzureOpenAIClient(new Uri(endpoint), new AzureKeyCredential(apiKey));';
PRINT N'    var embedClient = client.GetEmbeddingClient("text-embedding-3-small");';
PRINT N'';
PRINT N'    foreach (var change in changes.Where(c => c.Operation == SqlChangeOperation.Insert';
PRINT N'                                    || c.Operation == SqlChangeOperation.Update))';
PRINT N'    {';
PRINT N'        if (string.IsNullOrWhiteSpace(change.Item.Description)) continue;';
PRINT N'';
PRINT N'        var resp = await embedClient.GenerateEmbeddingAsync(change.Item.Description);';
PRINT N'        float[] vec = resp.Value.Vector.ToArray();  // 1536 floats';
PRINT N'        change.Item.DescriptionEmbedding = vec;';
PRINT N'        change.Item.ModelVersionUsed = "text-embedding-3-small";';
PRINT N'        change.Item.IsEmbeddingStale = 0;';
PRINT N'        change.Item.EmbeddingGeneratedAt = DateTime.UtcNow;';
PRINT N'        await productsOut.AddAsync(change.Item);  // grava de volta no SQL';
PRINT N'    }';
PRINT N'}';
GO

-- --- 6.2 Metodo 5 - CES (Change Event Streaming) SQL Server 2025 / Azure SQL DB (preview) ---
PRINT CHAR(13)+CHAR(10) + N'--- METODO 5: CES (Change Event Streaming - preview) ---';
PRINT N'';
PRINT N'Arquitetura: (SQL DB) -> CES publica em Event Hubs / Fabric Eventstream';
PRINT N'                              -> Consumer (Notebook Python / Azure Function)';
PRINT N'                                 -> chama OpenAI embedding';
PRINT N'                                 -> UPDATE tabela SQL devolta';
PRINT N'';
PRINT N'--- Notebook Python (Fabric / Synapse): ---';
PRINT N'import pyodbc, openai';
PRINT N'openai_client = openai.AzureOpenAI(api_version="2024-08-01", ...)';
PRINT N'';
PRINT N'for event in eventstream_batch:   # Eventos de CES (payload JSON)';
PRINT N'    pid     = event["ProductId"]';
PRINT N'    desc    = event["Description"]';
PRINT N'    vec = openai_client.embeddings.create(model="text-embedding-3-small", input=desc).data[0].embedding';
PRINT N'    cursor.execute("""';
PRINT N'        UPDATE lab.ProductVectorCatalog';
PRINT N'        SET DescriptionEmbedding = ?, ModelVersionUsed = ?, IsEmbeddingStale = 0,';
PRINT N'            EmbeddingGeneratedAt = SYSUTCDATETIME()';
PRINT N'        WHERE ProductId = ?""", (str(vec), "text-embedding-3-small", pid));';
PRINT N'';
PRINT N'>>> CES != CDC != Change Tracking. 3 recursos diferentes. Exame cobra a diferenca!';
GO

-- =================================================================================
-- PARTE 7: MICROSOFT FOUNDRY (secao GRANDE, cai no exame!) + Metodo 6 Logic Apps
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (02) PARTE 7/8: MICROSOFT FOUNDRY + LOGIC APPS';
PRINT '=========================================================';
GO

-- --- 7.1 Arquitetura Foundry ---
PRINT CHAR(13)+CHAR(10) + N'--- MICROSOFT FOUNDRY: Arquitetura Pipeline Declarativo ---';
PRINT N'';
PRINT N'Foundry Project (conecta recursos Azure/Fabric/SQL):';
PRINT N'';
PRINT N'  Connections:';
PRINT N'    |-> Azure SQL DB / Fabric SQL (via SQL Authentication ou Entra)';
PRINT N'    |-> Azure OpenAI deployment (text-embedding-3-small / large / ada-002)';
PRINT N'';
PRINT N'  Pipeline / Flow:';
PRINT N'    [1] Source (SQL) : SELECT ProductId, Description, LastUpdated';
PRINT N'                     FROM lab.ProductVectorCatalog';
PRINT N'                     WHERE IsEmbeddingStale = 1 OR EmbeddingGeneratedAt IS NULL;';
PRINT N'';
PRINT N'    [2] Chunk (opcional): dividir Description se > 8192 tokens por entrada';
PRINT N'';
PRINT N'    [3] Embed (step integrado) : chamar Azure OpenAI em lote (2048 input max)';
PRINT N'';
PRINT N'    [4] Sink (SQL UPDATE) :';
PRINT N'        SET DescriptionEmbedding = @vec,';
PRINT N'            IsEmbeddingStale = 0,';
PRINT N'            EmbeddingGeneratedAt = SYSUTCDATETIME(),';
PRINT N'            ModelVersionUsed = "text-embedding-3-small"';
PRINT N'        WHERE ProductId = @id;';
PRINT N'';
PRINT N'  Trigger do pipeline:';
PRINT N'    - Scheduled recurrence (cron: 5 min / 15 min)';
PRINT N'    - Event-driven (Fabric Eventstream -> CES -> pipe)';
PRINT N'    - On-demand (run manual / API Foundry SDK)';
GO

-- --- 7.2 Quando usar Foundry, quando evitar ---
SELECT
    N'✓ Vc quer SEM codigo (pipeline declarativo > triggers/jobs T-SQL)'                     AS Motivo,
    N'Foundry: EH UMA OPCAO CERTA'                                                           AS Decisao
UNION ALL SELECT
    N'✓ Manutencao embedding so UM DOS workflows de IA do projeto (RAG indexing, eval, batch score)',
    N'Foundry: Centraliza tudo num lugar so.'
UNION ALL SELECT
    N'✓ Time sem experiencia com Python/Functions, prefere UI.',
    N'Foundry (low-code) OU Logic Apps.'
UNION ALL SELECT
    N'✗ Precisa de LATENCIA SUB-30 SEGUNDOS entre mudanca de texto e vetor.',
    N'NAO use Foundry. Use CES + Notebook PUSH ou Table Trigger sincrono (tabela pequena).'
UNION ALL SELECT
    N'✗ Logica customizada pre-processamento (NLP, extracao regex complexa).',
    N'NAO use Foundry. Escreva Azure Functions (Python/C#) ou Fabric Notebook custom.'
UNION ALL SELECT
    N'✗ Tudo on-premises sem SHIR (Self-Hosted Integration Runtime).',
    N'NAO use Foundry sem SHIR. Rode CT + SQL Agent Job on-premises.'
UNION ALL SELECT
    N'✗ Compliance cross-region proibindo trafego de dados para servico gerenciado.',
    N'NAO use Foundry embedding step gerenciado. Keep-it in-DB: CT + CT + sp_invoke...';
GO

-- --- 7.3 TABELA CANONICA: FOUNDry vs CES (IMPORTANTE EXAME!) ---
PRINT CHAR(13)+CHAR(10) + N'================= TABELA CANONICA FOUNDRY vs CES =================';
SELECT
    N'Plataforma de Origem Suportada'      AS Aspecto,
    N'Foundry'                             AS ValorFoundry,
    N'CES (Change Event Streaming)'        AS ValorCES
UNION ALL SELECT
    N'Origem SQL suportada',
    N'Azure SQL DB / Fabric SQL DB / SQL Server on-prem (via SHIR)',
    N'SQL Server 2025+ / Azure SQL Database (ambos em preview)'
UNION ALL SELECT
    N'Codigo necessario?',
    N'NAO (pipeline declarativo UI + templates)',
    N'SIM (escrever codigo Notebook Python ou Azure Function)'
UNION ALL SELECT
    N'Tipo de trigger',
    N'Schedule (cron) / Event-driven / On-demand',
    N'STREAMING PUSH (publica em Event Hubs / Eventstream automaticamente)'
UNION ALL SELECT
    N'Latencia caracteristica',
    N'Segundos ~ minutos (depende de trigger)',
    N'Quase real-time (push based, subsegundo a segundos)'
UNION ALL SELECT
    N'Logica de embedding',
    N'Step "Embed" nativo do Foundry (managed)',
    N'Vc implementa no consumidor (Python SDK openai, etc.)'
UNION ALL SELECT
    N'Monitoramento',
    N'Foundry centraliza historico runs, custo, erro por workflow',
    N'Eventstream + Historico Notebook/Fabric separados'
UNION ALL SELECT
    N'Melhor para',
    N'Projetos IA multi-workflow, times sem codigo, refresh agendado em lote',
    N'Streaming para consumidores downstream, baixa latencia, Fabric Eventstream';
GO

-- --- Modelo Mental 4 metaforas ---
PRINT CHAR(13)+CHAR(10) + N'--- Modelo Mental (para fixar): ---';
PRINT N'  Foundry          = Cartao de Credito  (paga pela ergonomia, lock-in, pipeline no-code)';
PRINT N'  CES              = Pagamento por Tap  (preview, push-based, Event Hubs / Fabric)';
PRINT N'  CT / CDC         = Transferencia TED  (funciona em qualquer lugar, mas vc escreve o plumbing)';
PRINT N'  Table Trigger    = Dinheiro vivo       (imediatos, mas adicionam latencia na escrita)';
GO

-- --- 7.4 Logic Apps (6o. metodo) + Procedure GetProductsNeedingEmbedding ---
CREATE OR ALTER PROCEDURE lab.usp_GetProductsNeedingEmbedding
    @BatchSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@BatchSize)
        ProductID,
        ProductName,
        Description,
        EmbeddingAttempts,
        LastEmbeddingError
    FROM lab.ProductVectorCatalog
    WHERE IsEmbeddingStale = 1
       OR DescriptionEmbedding IS NULL
       OR (LastUpdated > EmbeddingGeneratedAt AND EmbeddingGeneratedAt IS NOT NULL)
    ORDER BY
        EmbeddingAttempts ASC,     -- linhas que tentamos menos primeiro
        LastUpdated ASC            -- mais antigas primeiro;
END;
GO

PRINT CHAR(13)+CHAR(10) + N'--- Logic Apps (Metodo 6 - low-code): ---';
PRINT N'';
PRINT N'Logic App Designer:';
PRINT N' [Trigger] Recurrence (a cada 5 minutos)';
PRINT N'      |';
PRINT N' [Acao SQL] Executar Stored Procedure: lab.usp_GetProductsNeedingEmbedding';
PRINT N'      |  (@BatchSize = 50)';
PRINT N' [Loop For Each (product)]';
PRINT N'      |- HTTP POST: https://.../openai/deployments/text-embedding-3-small/embeddings';
PRINT N'      |       (Autenticacao via Managed Identity / Active Directory OAuth)';
PRINT N'      |';
PRINT N'      |- Acao SQL: Executar Query (UPDATE ... SET Embedding = vector, Stale=0)';
PRINT N' [Fim]';
GO

-- =================================================================================
-- PARTE 8: Migracao de Modelo (ada-002 -> 3-small) + Problemas + Dicas Exame
-- =================================================================================

PRINT CHAR(13)+CHAR(10) + '=========================================================';
PRINT '  LAB 09-ME (02) PARTE 8/8: MIGRACAO DE MODELO + DICAS EXAME';
PRINT '=========================================================';
GO

-- Procedure MIGRACAO TOTAL (troca de modelo = re-embedar 100%!)
CREATE OR ALTER PROCEDURE lab.usp_ReembedModelMigration
    @NewModelName NVARCHAR(100) = N'text-embedding-3-small',
    @NewDims      INT           = 1536
AS
BEGIN
    SET NOCOUNT ON;

    IF @NewDims <> 1536 AND @NewDims <> 3072
    BEGIN; THROW 50001, N'Dimensao invalida. Esperado 1536 ou 3072.', 1; END;

    PRINT N'>>> Etapa 1: Marcar TUDO como stale + resetar vetor para NULL.';
    UPDATE lab.ProductVectorCatalog
    SET
        DescriptionEmbedding = NULL,
        IsEmbeddingStale     = 1,
        ModelVersionUsed     = NULL,
        EmbeddingGeneratedAt = NULL,
        EmbeddingAttempts    = 0,
        LastEmbeddingError   = NULL;

    PRINT N'>>> Etapa 2: Re-gerar embeddings com NOVO modelo em Lotes (safe para TPM).';
    PRINT N'/*';
    PRINT N'  WHILE EXISTS(SELECT 1 FROM lab.ProductVectorCatalog WHERE IsEmbeddingStale = 1)';
    PRINT N'  BEGIN';
    PRINT N'      UPDATE TOP (50) p';
    PRINT N'      SET DescriptionEmbedding = AI_GENERATE_EMBEDDINGS(p.Description USE MODEL [ModeloNovo_' + @NewModelName + N']),';
    PRINT N'          ModelVersionUsed     = ''' + @NewModelName + N''',';
    PRINT N'          IsEmbeddingStale     = 0,';
    PRINT N'          EmbeddingGeneratedAt = SYSUTCDATETIME(),';
    PRINT N'          EmbeddingAttempts    = EmbeddingAttempts + 1';
    PRINT N'      FROM lab.ProductVectorCatalog p WHERE IsEmbeddingStale = 1;';
    PRINT N'      WAITFOR DELAY ''00:00:02'';   -- pausa de 2s para nao estourar rate-limit';
    PRINT N'  END;';
    PRINT N'*/';

    PRINT N'>>> Etapa 3: Validar. Nao pode sobrar linha vetor NULL ou ModelVersionUsed errada.';
    PRINT N'    SELECT * FROM lab.ProductVectorCatalog';
    PRINT N'     WHERE DescriptionEmbedding IS NULL OR IsEmbeddingStale = 1 OR ModelVersionUsed <> ''' + @NewModelName + N'''';
END;
GO

EXEC lab.usp_ReembedModelMigration @NewModelName = N'text-embedding-3-small', @NewDims = 1536;
GO

-- --- Tabela Problemas Comuns 4 (DP-800) ---
PRINT CHAR(13)+CHAR(10) + N'--- Problemas Comuns Manutencao Embeddings ---';
SELECT
    N'Trigger sincrono causa timeout em bulk-loads (BULK INSERT 100k linhas)' AS Problema,
    N'Trigger dispara 1 chamada API por LINHA durante o bulk.' AS Causa,
    N'DISABLE TRIGGER lab.trg_... ON lab.ProductVectorCatalog. Bulk load terminou -> re-enable + re-embed em lote (UPDATE WHERE NULL).' AS Correcao
UNION ALL SELECT
    N'Change Tracking - Versao minima excedida / CHANGE_RETENTION estourado',
    N'SyncVersion do watermark mais antiga que CT_MIN_VALID_VERSION (limpeza rodou).',
    N'RE-EMBED COMPLETO (marcar tudo stale = 1 + novo watermark CHANGE_TRACKING_CURRENT_VERSION()).'
UNION ALL SELECT
    N'Embedding Drift nao detectado (produto atualizado mas busca volta errado)',
    N'Texto mudou mas nenhum trigger/CT marcou IsEmbeddingStale = 1.',
    N'Adicionar coluna LastUpdated vs EmbeddingGeneratedAt. Query: WHERE LastUpdated > EmbeddingGeneratedAt.'
UNION ALL SELECT
    N'Azure Function SQL Trigger Binding nunca dispara',
    N'Change Tracking nao habilitado ou Connection string sem db_owner para habilita-lo.',
    N'Ative CT manualmente: ALTER DATABASE ... CHANGE_TRACKING = ON; ALTER TABLE ... ENABLE CHANGE_TRACKING...';
GO

-- --- 4 Dicas de Exame ---
PRINT CHAR(13)+CHAR(10) + N'--- 4 Dicas para o EXAME DP-800 ---';
PRINT N'';
PRINT N'  1. TRIGGERS = SINCRONOS. SEMPRE que a pergunta disser "alta disponibilidade' + CHAR(13)+CHAR(10)
    + N'     ou endpoint IA pode falhar" -> EVITE trigger. Use CT/CDC assincrono.';
PRINT N'';
PRINT N'  2. CHANGE TRACKING = PADRAO para lote. Pergunta sobre "volume medio,' + CHAR(13)+CHAR(10)
    + N'     polling, watermark de versao, desacoplar escritas da IA" -> marca Change Tracking.';
PRINT N'';
PRINT N'  3. AZURE FUNCTIONS SQL TRIGGER = NAO E PUSH! Ela faz polling usando CT internamente.';
PRINT N'     CES = e SIM push, em preview SQL Server 2025 / Azure SQL Database.';
PRINT N'';
PRINT N'  4. Foundry: "sem codigo + varios workflows IA" = FOUNDRY.';
PRINT N'     Trocar modelo / dimensao -> SEMPRE re-embed TUDOS (questao recorrente!).';
GO

PRINT CHAR(13)+CHAR(10) + N'--- Flowchart Decisao Final ---';
PRINT N'';
PRINT N'Texto origem MUDOU';
PRINT N'  |';
PRINT N'  +-> > 1000 escritas/min ?';
PRINT N'        |  Sim  -> BATCH (CHANGE TRACKING OU CDC)  -> desacopla embed da escrita';
PRINT N'        |  Nao  -> Plataforma e SQL Server 2025+ / Azure SQL DB?';
PRINT N'                    |  Sim -> Quer push real-time? Sim -> CES ou Azure Functions';
PRINT N'                    |  Nao -> Latencia < 30s obrigatoria?';
PRINT N'                                  |  Sim -> Table Trigger sincrono (cuidado: dependencia IA!)';
PRINT N'                                  |  Nao -> Prefere no-code/low-code?';
PRINT N'                                                |  Sim -> MICROSOFT FOUNDRY ou Logic Apps';
PRINT N'                                                |  Nao -> CT + SQL Agent Job (padrao robusto)';
GO

PRINT CHAR(13)+CHAR(10) + '>>> CHECKLIST CONCLUSAO LAB 09-ME (02):';
SELECT N'[OK] Entendi drift e por que embeddings ficam obsoletos' AS Item UNION ALL
SELECT N'[OK] Sei implementar dirty flag + trigger mark stale' UNION ALL
SELECT N'[OK] Dominar Table Trigger vs CT vs CDC vs Functions vs CES vs Foundry' UNION ALL
SELECT N'[OK] Change Tracking: watermark, CHANGETABLE, CHANGE_RETENTION -> re-embed total' UNION ALL
SELECT N'[OK] CDC: __$operation, LSN watermark, net changes' UNION ALL
SELECT N'[OK] CES = push preview; Foundry = no-code declarativo' UNION ALL
SELECT N'[OK] Tabela canonica Foundry vs CES (7 aspectos)' UNION ALL
SELECT N'[OK] Sei migrar modelo: re-embed 100% + validacao final.';
GO

PRINT CHAR(13)+CHAR(10) + N'>>> PROXIMO: Lab 09-ME (03) - Chunking & Geracao & Batch JSON parsing.';
GO

-- =================================================================================================
-- PRÓXIMO PASSO: Revise a teoria em ../../../certification/09-models-embeddings/02-embedding-maintenance.md
-- =================================================================================================
