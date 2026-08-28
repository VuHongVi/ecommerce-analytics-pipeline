CREATE OR ALTER PROCEDURE mart.refresh_dim_products
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID(N'mart.dim_products', N'U') IS NULL
        BEGIN
            THROW 51201,
                'mart.dim_products does not exist.',
                1;
        END;

        IF OBJECT_ID(N'stg.product_registry', N'U') IS NULL
        BEGIN
            THROW 51202,
                'stg.product_registry does not exist.',
                1;
        END;

        SELECT
            CONCAT(
                N'INTERNAL:',
                CONVERT(NVARCHAR(30), registry.internal_product_id)
            ) AS product_natural_key,
            registry.internal_product_id,
            CAST('PRODUCT_MAPPED' AS VARCHAR(30))
                AS mapping_status,
            CAST(1 AS BIT) AS is_product_mapped,
            CAST(0 AS BIT) AS is_special_member,
            registry.canonical_product_name,
            registry.normalized_product_name,
            registry.first_seen_at_utc
                AS source_first_seen_at_utc,
            registry.last_seen_at_utc
                AS source_last_seen_at_utc,
            registry.is_active
        INTO #source_dim_products
        FROM stg.product_registry AS registry

        UNION ALL

        SELECT
            CAST(N'__UNATTRIBUTED_PRODUCT__' AS NVARCHAR(100)),
            CAST(NULL AS BIGINT),
            CAST('UNATTRIBUTED' AS VARCHAR(30)),
            CAST(0 AS BIT),
            CAST(1 AS BIT),
            CAST(N'Unattributed product' AS NVARCHAR(500)),
            CAST(N'__unattributed_product__' AS NVARCHAR(400)),
            CAST(NULL AS DATETIME2(3)),
            CAST(NULL AS DATETIME2(3)),
            CAST(1 AS BIT);

        CREATE UNIQUE CLUSTERED INDEX IX_source_dim_products
            ON #source_dim_products (product_natural_key);

        IF EXISTS (
            SELECT 1
            FROM #source_dim_products
            GROUP BY internal_product_id
            HAVING internal_product_id IS NOT NULL
               AND COUNT(*) > 1
        )
        BEGIN
            THROW 51203,
                'An internal product maps to multiple dimension members.',
                1;
        END;

        SELECT source.product_natural_key
        INTO #changed_dim_products
        FROM #source_dim_products AS source
        LEFT JOIN mart.dim_products AS target
            ON target.product_natural_key =
               source.product_natural_key
        WHERE target.product_key IS NULL
           OR EXISTS (
                SELECT
                    source.internal_product_id,
                    source.mapping_status,
                    source.is_product_mapped,
                    source.is_special_member,
                    source.canonical_product_name,
                    source.normalized_product_name,
                    source.source_first_seen_at_utc,
                    source.source_last_seen_at_utc,
                    source.is_active

                EXCEPT

                SELECT
                    target.internal_product_id,
                    target.mapping_status,
                    target.is_product_mapped,
                    target.is_special_member,
                    target.canonical_product_name,
                    target.normalized_product_name,
                    target.source_first_seen_at_utc,
                    target.source_last_seen_at_utc,
                    target.is_active
           );

        CREATE UNIQUE CLUSTERED INDEX IX_changed_dim_products
            ON #changed_dim_products (product_natural_key);

        DECLARE @inserted_product_count INT = (
            SELECT COUNT(*)
            FROM #source_dim_products AS source
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.dim_products AS target
                WHERE target.product_natural_key =
                      source.product_natural_key
            )
        );

        DECLARE @updated_product_count INT = (
            SELECT COUNT(*)
            FROM #changed_dim_products AS changed
            WHERE EXISTS (
                SELECT 1
                FROM mart.dim_products AS target
                WHERE target.product_natural_key =
                      changed.product_natural_key
            )
        );

        UPDATE target
        SET
            internal_product_id = source.internal_product_id,
            mapping_status = source.mapping_status,
            is_product_mapped = source.is_product_mapped,
            is_special_member = source.is_special_member,
            canonical_product_name =
                source.canonical_product_name,
            normalized_product_name =
                source.normalized_product_name,
            source_first_seen_at_utc =
                source.source_first_seen_at_utc,
            source_last_seen_at_utc =
                source.source_last_seen_at_utc,
            is_active = source.is_active,
            updated_at_utc = SYSUTCDATETIME()
        FROM mart.dim_products AS target
        INNER JOIN #source_dim_products AS source
            ON source.product_natural_key =
               target.product_natural_key
        INNER JOIN #changed_dim_products AS changed
            ON changed.product_natural_key =
               source.product_natural_key;

        INSERT INTO mart.dim_products (
            product_natural_key,
            internal_product_id,
            mapping_status,
            is_product_mapped,
            is_special_member,
            canonical_product_name,
            normalized_product_name,
            source_first_seen_at_utc,
            source_last_seen_at_utc,
            is_active
        )
        SELECT
            source.product_natural_key,
            source.internal_product_id,
            source.mapping_status,
            source.is_product_mapped,
            source.is_special_member,
            source.canonical_product_name,
            source.normalized_product_name,
            source.source_first_seen_at_utc,
            source.source_last_seen_at_utc,
            source.is_active
        FROM #source_dim_products AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM mart.dim_products AS target
            WHERE target.product_natural_key =
                  source.product_natural_key
        );

        COMMIT TRANSACTION;

        SELECT
            @inserted_product_count AS inserted_products,
            @updated_product_count AS updated_products,
            COUNT(*) AS dimension_rows,
            SUM(
                CASE
                    WHEN mapping_status = 'PRODUCT_MAPPED'
                    THEN 1
                    ELSE 0
                END
            ) AS mapped_products,
            SUM(
                CASE
                    WHEN mapping_status = 'UNATTRIBUTED'
                    THEN 1
                    ELSE 0
                END
            ) AS unattributed_members
        FROM mart.dim_products;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
