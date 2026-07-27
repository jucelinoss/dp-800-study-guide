-- ====================================================================
-- DP-800 Study Guide — Lab 01: Create StudyDB
-- Purpose: Creates the reusable StudyDB database and study schema.
-- WARNING: Running this script DESTROYS and recreates StudyDB.
-- ====================================================================

-- [OBSERVE] @@SERVERNAME shows your instance name.
-- If connected to Azure SQL, this returns the server name.
SELECT @@SERVERNAME AS server_name;
GO

USE master;
GO

-- KEY CONCEPT: SINGLE_USER + ROLLBACK IMMEDIATE kicks out
-- all other connections so the database can be dropped.
IF DB_ID(N'StudyDB') IS NOT NULL
BEGIN
    ALTER DATABASE StudyDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE StudyDB;
END;
GO

CREATE DATABASE StudyDB;
GO

-- KEY CONCEPT: A schema groups related objects. We use 'study'
-- to keep our learning objects separate from system schemas.
USE StudyDB;
GO

CREATE SCHEMA study;
GO

-- Verify the database and schema exist.
SELECT DB_NAME() AS current_database;
GO

SELECT SCHEMA_NAME(schema_id) AS schema_name,
       name AS schema_owner
FROM sys.schemas
WHERE name = 'study';
GO

-- [OBSERVE] The StudyDB database is now ready for Lab 02.

-- ====================================================================
-- CHECK YOURSELF:
-- 1. What does SINGLE_USER do? Why is it needed before DROP DATABASE?
-- 2. Why do we use a schema (study) instead of creating tables in dbo?
-- 3. What's the difference between @@SERVERNAME and DB_NAME()?
-- ====================================================================
