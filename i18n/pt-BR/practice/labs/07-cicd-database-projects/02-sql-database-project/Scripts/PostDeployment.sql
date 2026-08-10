IF NOT EXISTS (SELECT 1 FROM [lab].[Customers] WHERE [CustomerId] = 1)
    INSERT INTO [lab].[Customers] ([CustomerId], [DisplayName])
    VALUES (1, N'Cliente de demonstração');
GO

PRINT N'Post-deployment executado.';
