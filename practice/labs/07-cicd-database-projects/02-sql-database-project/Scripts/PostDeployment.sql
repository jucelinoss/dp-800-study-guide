IF NOT EXISTS (SELECT 1 FROM [lab].[Customers] WHERE [CustomerId] = 1)
    INSERT INTO [lab].[Customers] ([CustomerId], [DisplayName])
    VALUES (1, N'Demo customer');
GO

PRINT N'Post-deployment executed.';
