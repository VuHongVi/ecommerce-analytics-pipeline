CREATE OR ALTER PROCEDURE
    stg.refresh_product_cost_staging
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @latest_batch_id BIGINT = (
            SELECT TOP (1)
                product_cost_import_batch_id
            FROM raw.product_cost_import_batches
            ORDER BY
                imported_at_utc DESC,
                product_cost_import_batch_id DESC
        );

        IF @latest_batch_id IS NULL
        BEGIN
            THROW 50001,
                'No product cost RAW batch exists.',
                1;
        END;

        /*
         * MASTER:
         * Một sản phẩm có nhiều giá thì lấy giá cao nhất.
         */
        ;WITH normalized_rows AS (
            SELECT
                source.raw_product_cost_master_id,
                source.product_cost_import_batch_id,
                source.product_name,
                source.unit_cost,
                source.source_row_hash,
                normalized.normalized_product_name
            FROM raw.product_cost_master_rows AS source
            CROSS APPLY (
                SELECT CAST(
                    LEFT(
                        LOWER(
                            LTRIM(
                                RTRIM(
                                    REPLACE(
                                        REPLACE(
                                            REPLACE(
                                                REPLACE(
                                                    REPLACE(
                                                        source.product_name,
                                                        NCHAR(9),
                                                        N' '
                                                    ),
                                                    NCHAR(10),
                                                    N' '
                                                ),
                                                NCHAR(13),
                                                N' '
                                            ),
                                            N'  ',
                                            N' '
                                        ),
                                        N'  ',
                                        N' '
                                    )
                                )
                            )
                        ),
                        400
                    )
                    AS NVARCHAR(400)
                ) AS normalized_product_name
            ) AS normalized
            WHERE
                source.product_cost_import_batch_id =
                    @latest_batch_id
                AND source.product_name IS NOT NULL
                AND normalized.normalized_product_name <> N''
                AND source.unit_cost > 0
        ),
        ranked_rows AS (
            SELECT
                source.*,

                COUNT(*) OVER (
                    PARTITION BY
                        source.normalized_product_name
                ) AS source_row_count,

                MIN(source.unit_cost) OVER (
                    PARTITION BY
                        source.normalized_product_name
                ) AS minimum_unit_cost,

                MAX(source.unit_cost) OVER (
                    PARTITION BY
                        source.normalized_product_name
                ) AS maximum_unit_cost,

                ROW_NUMBER() OVER (
                    PARTITION BY
                        source.normalized_product_name
                    ORDER BY
                        source.unit_cost DESC,
                        source.raw_product_cost_master_id
                            DESC
                ) AS row_number
            FROM normalized_rows AS source
        )
        SELECT
            normalized_product_name,
            product_name AS canonical_product_name,
            unit_cost AS fallback_unit_cost,
            source_row_count,

            CAST(
                CASE
                    WHEN minimum_unit_cost <>
                         maximum_unit_cost
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS has_conflicting_prices,

            product_cost_import_batch_id
                AS source_product_cost_import_batch_id,

            raw_product_cost_master_id
                AS source_raw_product_cost_master_id,

            source_row_hash
        INTO #source_cost_master
        FROM ranked_rows
        WHERE row_number = 1;

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_cost_master
        ON #source_cost_master (
            normalized_product_name
        );

        DECLARE @changed_master_count INT = (
            SELECT COUNT(*)
            FROM #source_cost_master AS source
            FULL OUTER JOIN
                stg.product_cost_master AS target
                ON target.normalized_product_name =
                   source.normalized_product_name
            WHERE source.normalized_product_name
                      IS NULL
               OR target.normalized_product_name
                      IS NULL
               OR target.canonical_product_name <>
                  source.canonical_product_name
               OR target.fallback_unit_cost <>
                  source.fallback_unit_cost
               OR target.source_row_count <>
                  source.source_row_count
               OR target.has_conflicting_prices <>
                  source.has_conflicting_prices
               OR
                  target.source_product_cost_import_batch_id
                  <>
                  source.source_product_cost_import_batch_id
               OR
                  target.source_raw_product_cost_master_id
                  <>
                  source.source_raw_product_cost_master_id
               OR target.source_row_hash <>
                  source.source_row_hash
        );

        UPDATE target
        SET
            canonical_product_name =
                source.canonical_product_name,
            fallback_unit_cost =
                source.fallback_unit_cost,
            source_row_count =
                source.source_row_count,
            has_conflicting_prices =
                source.has_conflicting_prices,
            source_product_cost_import_batch_id =
                source.source_product_cost_import_batch_id,
            source_raw_product_cost_master_id =
                source.source_raw_product_cost_master_id,
            source_row_hash =
                source.source_row_hash,
            staged_at_utc = SYSUTCDATETIME()
        FROM stg.product_cost_master AS target
        INNER JOIN #source_cost_master AS source
            ON source.normalized_product_name =
               target.normalized_product_name
        WHERE target.canonical_product_name <>
                  source.canonical_product_name
           OR target.fallback_unit_cost <>
                  source.fallback_unit_cost
           OR target.source_row_count <>
                  source.source_row_count
           OR target.has_conflicting_prices <>
                  source.has_conflicting_prices
           OR
              target.source_product_cost_import_batch_id
              <>
              source.source_product_cost_import_batch_id
           OR
              target.source_raw_product_cost_master_id
              <>
              source.source_raw_product_cost_master_id
           OR target.source_row_hash <>
              source.source_row_hash;

        INSERT INTO stg.product_cost_master (
            normalized_product_name,
            canonical_product_name,
            fallback_unit_cost,
            source_row_count,
            has_conflicting_prices,
            source_product_cost_import_batch_id,
            source_raw_product_cost_master_id,
            source_row_hash
        )
        SELECT
            source.normalized_product_name,
            source.canonical_product_name,
            source.fallback_unit_cost,
            source.source_row_count,
            source.has_conflicting_prices,
            source.source_product_cost_import_batch_id,
            source.source_raw_product_cost_master_id,
            source.source_row_hash
        FROM #source_cost_master AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.product_cost_master AS target
            WHERE target.normalized_product_name =
                  source.normalized_product_name
        );

        DELETE target
        FROM stg.product_cost_master AS target
        WHERE NOT EXISTS (
            SELECT 1
            FROM #source_cost_master AS source
            WHERE source.normalized_product_name =
                  target.normalized_product_name
        );

        /*
         * HISTORY:
         * Chỉ giữ các dòng có tên, giá và ngày hợp lệ.
         */
        SELECT
            source.raw_product_cost_history_id
                AS source_raw_product_cost_history_id,

            normalized.normalized_product_name,
            source.product_name
                AS canonical_product_name,

            source.approved_quantity,
            source.import_date,
            source.warehouse_arrival_date,
            source.actual_unit_cost,

            source.product_cost_import_batch_id
                AS source_product_cost_import_batch_id,

            source.source_row_hash
        INTO #source_cost_history
        FROM raw.product_cost_history_rows AS source
        CROSS APPLY (
            SELECT CAST(
                LEFT(
                    LOWER(
                        LTRIM(
                            RTRIM(
                                REPLACE(
                                    REPLACE(
                                        REPLACE(
                                            REPLACE(
                                                REPLACE(
                                                    source.product_name,
                                                    NCHAR(9),
                                                    N' '
                                                ),
                                                NCHAR(10),
                                                N' '
                                            ),
                                            NCHAR(13),
                                            N' '
                                        ),
                                        N'  ',
                                        N' '
                                    ),
                                    N'  ',
                                    N' '
                                )
                            )
                        )
                    ),
                    400
                )
                AS NVARCHAR(400)
            ) AS normalized_product_name
        ) AS normalized
        WHERE
            source.product_cost_import_batch_id =
                @latest_batch_id
            AND source.product_name IS NOT NULL
            AND normalized.normalized_product_name <> N''
            AND source.actual_unit_cost > 0
            AND source.import_date IS NOT NULL
            AND source.warehouse_arrival_date IS NOT NULL
            AND (
                source.approved_quantity IS NULL
                OR source.approved_quantity > 0
            );

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_cost_history
        ON #source_cost_history (
            source_raw_product_cost_history_id
        );

        DECLARE @changed_history_count INT = (
            SELECT COUNT(*)
            FROM #source_cost_history AS source
            FULL OUTER JOIN
                stg.product_cost_history AS target
                ON
                    target.source_raw_product_cost_history_id
                    =
                    source.source_raw_product_cost_history_id
            WHERE
                source.source_raw_product_cost_history_id
                    IS NULL
                OR
                target.source_raw_product_cost_history_id
                    IS NULL
                OR target.normalized_product_name <>
                   source.normalized_product_name
                OR target.canonical_product_name <>
                   source.canonical_product_name
                OR ISNULL(
                       target.approved_quantity,
                       -1
                   ) <>
                   ISNULL(
                       source.approved_quantity,
                       -1
                   )
                OR target.import_date <>
                   source.import_date
                OR target.warehouse_arrival_date <>
                   source.warehouse_arrival_date
                OR target.actual_unit_cost <>
                   source.actual_unit_cost
                OR
                   target.source_product_cost_import_batch_id
                   <>
                   source.source_product_cost_import_batch_id
                OR target.source_row_hash <>
                   source.source_row_hash
        );

        UPDATE target
        SET
            normalized_product_name =
                source.normalized_product_name,
            canonical_product_name =
                source.canonical_product_name,
            approved_quantity =
                source.approved_quantity,
            import_date =
                source.import_date,
            warehouse_arrival_date =
                source.warehouse_arrival_date,
            actual_unit_cost =
                source.actual_unit_cost,
            source_product_cost_import_batch_id =
                source.source_product_cost_import_batch_id,
            source_row_hash =
                source.source_row_hash,
            staged_at_utc = SYSUTCDATETIME()
        FROM stg.product_cost_history AS target
        INNER JOIN #source_cost_history AS source
            ON
                source.source_raw_product_cost_history_id
                =
                target.source_raw_product_cost_history_id
        WHERE target.normalized_product_name <>
                  source.normalized_product_name
           OR target.canonical_product_name <>
                  source.canonical_product_name
           OR ISNULL(
                  target.approved_quantity,
                  -1
              ) <>
              ISNULL(
                  source.approved_quantity,
                  -1
              )
           OR target.import_date <>
                  source.import_date
           OR target.warehouse_arrival_date <>
                  source.warehouse_arrival_date
           OR target.actual_unit_cost <>
                  source.actual_unit_cost
           OR
              target.source_product_cost_import_batch_id
              <>
              source.source_product_cost_import_batch_id
           OR target.source_row_hash <>
                  source.source_row_hash;

        INSERT INTO stg.product_cost_history (
            source_raw_product_cost_history_id,
            normalized_product_name,
            canonical_product_name,
            approved_quantity,
            import_date,
            warehouse_arrival_date,
            actual_unit_cost,
            source_product_cost_import_batch_id,
            source_row_hash
        )
        SELECT
            source.source_raw_product_cost_history_id,
            source.normalized_product_name,
            source.canonical_product_name,
            source.approved_quantity,
            source.import_date,
            source.warehouse_arrival_date,
            source.actual_unit_cost,
            source.source_product_cost_import_batch_id,
            source.source_row_hash
        FROM #source_cost_history AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.product_cost_history AS target
            WHERE
                target.source_raw_product_cost_history_id
                =
                source.source_raw_product_cost_history_id
        );

        DELETE target
        FROM stg.product_cost_history AS target
        WHERE NOT EXISTS (
            SELECT 1
            FROM #source_cost_history AS source
            WHERE
                source.source_raw_product_cost_history_id
                =
                target.source_raw_product_cost_history_id
        );

        COMMIT TRANSACTION;

        SELECT
            @latest_batch_id AS latest_batch_id,
            @changed_master_count
                AS changed_master_products,
            (
                SELECT COUNT(*)
                FROM stg.product_cost_master
            ) AS staged_master_products,
            (
                SELECT COUNT(*)
                FROM stg.product_cost_master
                WHERE has_conflicting_prices = 1
            ) AS conflicting_master_products,
            @changed_history_count
                AS changed_history_rows,
            (
                SELECT COUNT(*)
                FROM stg.product_cost_history
            ) AS staged_history_rows;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;