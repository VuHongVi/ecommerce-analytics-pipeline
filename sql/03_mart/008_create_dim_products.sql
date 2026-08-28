SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'mart') IS NULL
    BEGIN
        EXEC(N'CREATE SCHEMA mart;');
    END;

    IF OBJECT_ID(N'mart.dim_products', N'U') IS NULL
    BEGIN
        CREATE TABLE mart.dim_products (
            product_key BIGINT IDENTITY(1, 1) NOT NULL,
            product_natural_key NVARCHAR(100) NOT NULL,
            internal_product_id BIGINT NULL,

            mapping_status VARCHAR(30) NOT NULL,
            is_product_mapped BIT NOT NULL,
            is_special_member BIT NOT NULL,

            canonical_product_name NVARCHAR(500) NOT NULL,
            normalized_product_name NVARCHAR(400) NOT NULL,
            source_first_seen_at_utc DATETIME2(3) NULL,
            source_last_seen_at_utc DATETIME2(3) NULL,
            is_active BIT NOT NULL,

            created_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_dim_products_created
                DEFAULT SYSUTCDATETIME(),
            updated_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_dim_products_updated
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_dim_products
                PRIMARY KEY CLUSTERED (product_key),
            CONSTRAINT UQ_dim_products_natural_key
                UNIQUE (product_natural_key),
            CONSTRAINT CK_dim_products_mapping_status
                CHECK (
                    mapping_status IN (
                        'PRODUCT_MAPPED',
                        'UNATTRIBUTED'
                    )
                ),
            CONSTRAINT CK_dim_products_mapping_flags
                CHECK (
                    (
                        mapping_status = 'PRODUCT_MAPPED'
                        AND is_product_mapped = 1
                        AND is_special_member = 0
                        AND internal_product_id IS NOT NULL
                    )
                    OR (
                        mapping_status = 'UNATTRIBUTED'
                        AND is_product_mapped = 0
                        AND is_special_member = 1
                        AND internal_product_id IS NULL
                    )
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'UX_dim_products_internal_product'
          AND object_id = OBJECT_ID(N'mart.dim_products')
    )
    BEGIN
        CREATE UNIQUE INDEX UX_dim_products_internal_product
            ON mart.dim_products (internal_product_id)
            WHERE internal_product_id IS NOT NULL;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_dim_products_name'
          AND object_id = OBJECT_ID(N'mart.dim_products')
    )
    BEGIN
        CREATE INDEX IX_dim_products_name
            ON mart.dim_products (
                normalized_product_name,
                product_key
            )
            INCLUDE (
                canonical_product_name,
                is_active
            );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
