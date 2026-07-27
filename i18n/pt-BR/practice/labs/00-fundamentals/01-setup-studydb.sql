-- ====================================================================
-- DP-800 Guia de Estudo — Laboratório 01: Criar StudyDB
-- Objetivo: Cria o banco de dados reutilizável StudyDB e o schema study.
-- ATENÇÃO: Executar este script DESTRÓI e recria o StudyDB.
-- ====================================================================

-- [OBSERVE] @@SERVERNAME mostra o nome da sua instância.
-- Se conectado ao Azure SQL, retorna o nome do servidor.
SELECT @@SERVERNAME AS server_name;
GO

USE master;
GO

-- CONCEITO CHAVE: SINGLE_USER + ROLLBACK IMMEDIATE remove
-- todas as outras conexões para que o banco de dados possa ser excluído.
IF DB_ID(N'StudyDB') IS NOT NULL
BEGIN
    ALTER DATABASE StudyDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE StudyDB;
END;
GO

CREATE DATABASE StudyDB;
GO

-- CONCEITO CHAVE: Um schema agrupa objetos relacionados. Usamos 'study'
-- para manter nossos objetos de aprendizado separados dos schemas do sistema.
USE StudyDB;
GO

CREATE SCHEMA study;
GO

-- Verifique se o banco de dados e o schema existem.
SELECT DB_NAME() AS current_database;
GO

SELECT SCHEMA_NAME(schema_id) AS schema_name,
       name AS schema_owner
FROM sys.schemas
WHERE name = 'study';
GO

-- [OBSERVE] O banco de dados StudyDB agora está pronto para o Laboratório 02.

-- ====================================================================
-- VERIFIQUE-SE:
-- 1. O que o SINGLE_USER faz? Por que é necessário antes de DROP DATABASE?
-- 2. Por que usamos um schema (study) em vez de criar tabelas no dbo?
-- 3. Qual é a diferença entre @@SERVERNAME e DB_NAME()?
-- ====================================================================
