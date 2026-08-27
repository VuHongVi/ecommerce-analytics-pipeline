SET NOCOUNT ON;

IF DB_ID(N'ecommerce_analytics') IS NULL
BEGIN
    EXEC(N'CREATE DATABASE [ecommerce_analytics]');
END;

IF NOT EXISTS (
    SELECT 1
    FROM [ecommerce_analytics].sys.schemas
    WHERE [name] = N'raw'
)
BEGIN
    EXEC [ecommerce_analytics].sys.sp_executesql
        N'CREATE SCHEMA [raw] AUTHORIZATION [dbo];';
END;

IF NOT EXISTS (
    SELECT 1
    FROM [ecommerce_analytics].sys.schemas
    WHERE [name] = N'stg'
)
BEGIN
    EXEC [ecommerce_analytics].sys.sp_executesql
        N'CREATE SCHEMA [stg] AUTHORIZATION [dbo];';
END;

IF NOT EXISTS (
    SELECT 1
    FROM [ecommerce_analytics].sys.schemas
    WHERE [name] = N'mart'
)
BEGIN
    EXEC [ecommerce_analytics].sys.sp_executesql
        N'CREATE SCHEMA [mart] AUTHORIZATION [dbo];';
END;

IF NOT EXISTS (
    SELECT 1
    FROM [ecommerce_analytics].sys.schemas
    WHERE [name] = N'dq'
)
BEGIN
    EXEC [ecommerce_analytics].sys.sp_executesql
        N'CREATE SCHEMA [dq] AUTHORIZATION [dbo];';
END;

IF NOT EXISTS (
    SELECT 1
    FROM [ecommerce_analytics].sys.schemas
    WHERE [name] = N'ctl'
)
BEGIN
    EXEC [ecommerce_analytics].sys.sp_executesql
        N'CREATE SCHEMA [ctl] AUTHORIZATION [dbo];';
END;