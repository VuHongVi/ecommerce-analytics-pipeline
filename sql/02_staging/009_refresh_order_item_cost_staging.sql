CREATE OR ALTER PROCEDURE
    stg.refresh_order_item_cost_staging
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            items.shop_id,
            items.order_id,
            items.source_item_id,
            items.internal_product_id,
            items.source_raw_order_version_id,

            CAST(
                orders.source_inserted_at AS DATE
            ) AS order_created_date,

            items.quantity,

            resolved.resolved_unit_cost,

            CAST(
                CASE
                    WHEN resolved.resolved_unit_cost
                         IS NULL
                    THEN NULL
                    ELSE
                        resolved.resolved_unit_cost
                        * items.quantity
                END
                AS DECIMAL(19, 2)
            ) AS line_product_cost,

            resolved.cost_source,

            CAST(
                CASE
                    WHEN resolved.cost_source IN (
                        'ESTIMATED_DEFAULT',
                        'MANUAL_ESTIMATE'
                    )
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS is_estimated,

            resolved.cost_effective_date,

            resolved
                .source_product_cost_import_batch_id,

            resolved
                .source_raw_product_cost_master_id,

            resolved
                .source_raw_product_cost_history_id

        INTO #source_item_costs

        FROM stg.pancake_order_items AS items

        INNER JOIN stg.pancake_orders AS orders
            ON orders.shop_id = items.shop_id
           AND orders.order_id = items.order_id

        LEFT JOIN stg.product_cost_master AS master
            ON master.normalized_product_name =
               items.normalized_product_name

        LEFT JOIN stg.product_cost_estimates AS estimate
            ON estimate.internal_product_id =
               items.internal_product_id

        OUTER APPLY (
            SELECT TOP (1)
                cost.actual_unit_cost,
                cost.warehouse_arrival_date,
                cost
                    .source_product_cost_import_batch_id,
                cost
                    .source_raw_product_cost_history_id
            FROM stg.product_cost_history AS cost
            WHERE
                cost.normalized_product_name =
                    items.normalized_product_name
                AND cost.warehouse_arrival_date <=
                    CAST(
                        orders.source_inserted_at
                        AS DATE
                    )
            ORDER BY
                cost.warehouse_arrival_date DESC,
                cost.import_date DESC,
                cost
                    .source_raw_product_cost_history_id
                    DESC
        ) AS history

        CROSS APPLY (
            SELECT
                CAST(
                    CASE
                        WHEN
                            COALESCE(
                                orders.is_cancelled,
                                0
                            ) = 1
                        THEN 0

                        WHEN history.actual_unit_cost
                             IS NOT NULL
                        THEN history.actual_unit_cost

                        WHEN master.fallback_unit_cost
                             IS NOT NULL
                        THEN master.fallback_unit_cost

                        WHEN estimate.estimated_unit_cost
                             IS NOT NULL
                        THEN estimate.estimated_unit_cost

                        ELSE NULL
                    END
                    AS DECIMAL(19, 2)
                ) AS resolved_unit_cost,

                CAST(
                    CASE
                        WHEN
                            COALESCE(
                                orders.is_cancelled,
                                0
                            ) = 1
                        THEN 'NOT_REQUIRED_CANCELED'

                        WHEN history.actual_unit_cost
                             IS NOT NULL
                        THEN 'HISTORY'

                        WHEN master.fallback_unit_cost
                             IS NOT NULL
                        THEN 'MASTER_FALLBACK'

                        WHEN estimate.estimated_unit_cost
                             IS NOT NULL
                        THEN estimate.estimate_method

                        ELSE 'MISSING_COST'
                    END
                    AS VARCHAR(30)
                ) AS cost_source,

                CASE
                    WHEN
                        COALESCE(
                            orders.is_cancelled,
                            0
                        ) = 0
                        AND history.actual_unit_cost
                            IS NOT NULL
                    THEN history.warehouse_arrival_date

                    ELSE NULL
                END AS cost_effective_date,

                CASE
                    WHEN
                        COALESCE(
                            orders.is_cancelled,
                            0
                        ) = 0
                        AND history.actual_unit_cost
                            IS NOT NULL
                    THEN history
                        .source_product_cost_import_batch_id

                    WHEN
                        COALESCE(
                            orders.is_cancelled,
                            0
                        ) = 0
                        AND history.actual_unit_cost
                            IS NULL
                        AND master.fallback_unit_cost
                            IS NOT NULL
                    THEN master
                        .source_product_cost_import_batch_id

                    ELSE NULL
                END
                    AS source_product_cost_import_batch_id,

                CASE
                    WHEN
                        COALESCE(
                            orders.is_cancelled,
                            0
                        ) = 0
                        AND history.actual_unit_cost
                            IS NULL
                        AND master.fallback_unit_cost
                            IS NOT NULL
                    THEN master
                        .source_raw_product_cost_master_id

                    ELSE NULL
                END
                    AS source_raw_product_cost_master_id,

                CASE
                    WHEN
                        COALESCE(
                            orders.is_cancelled,
                            0
                        ) = 0
                        AND history.actual_unit_cost
                            IS NOT NULL
                    THEN history
                        .source_raw_product_cost_history_id

                    ELSE NULL
                END
                    AS source_raw_product_cost_history_id
        ) AS resolved;

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_item_costs
        ON #source_item_costs (
            shop_id,
            order_id,
            source_item_id
        );

        SELECT
            COALESCE(
                source.shop_id,
                target.shop_id
            ) AS shop_id,

            COALESCE(
                source.order_id,
                target.order_id
            ) AS order_id,

            COALESCE(
                source.source_item_id,
                target.source_item_id
            ) AS source_item_id

        INTO #changed_item_costs

        FROM #source_item_costs AS source

        FULL OUTER JOIN
            stg.pancake_order_item_costs AS target
            ON target.shop_id = source.shop_id
           AND target.order_id = source.order_id
           AND target.source_item_id =
               source.source_item_id

        WHERE source.source_item_id IS NULL
           OR target.source_item_id IS NULL
           OR target.internal_product_id <>
              source.internal_product_id
           OR target.source_raw_order_version_id <>
              source.source_raw_order_version_id
           OR target.order_created_date <>
              source.order_created_date
           OR target.quantity <>
              source.quantity
           OR ISNULL(
                  target.resolved_unit_cost,
                  -1
              ) <>
              ISNULL(
                  source.resolved_unit_cost,
                  -1
              )
           OR ISNULL(
                  target.line_product_cost,
                  -1
              ) <>
              ISNULL(
                  source.line_product_cost,
                  -1
              )
           OR target.cost_source <>
              source.cost_source
           OR target.is_estimated <>
              source.is_estimated
           OR ISNULL(
                  target.cost_effective_date,
                  CONVERT(DATE, '19000101')
              ) <>
              ISNULL(
                  source.cost_effective_date,
                  CONVERT(DATE, '19000101')
              )
           OR ISNULL(
                  target
                    .source_product_cost_import_batch_id,
                  -1
              ) <>
              ISNULL(
                  source
                    .source_product_cost_import_batch_id,
                  -1
              )
           OR ISNULL(
                  target
                    .source_raw_product_cost_master_id,
                  -1
              ) <>
              ISNULL(
                  source
                    .source_raw_product_cost_master_id,
                  -1
              )
           OR ISNULL(
                  target
                    .source_raw_product_cost_history_id,
                  -1
              ) <>
              ISNULL(
                  source
                    .source_raw_product_cost_history_id,
                  -1
              );

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_item_costs
        ON #changed_item_costs (
            shop_id,
            order_id,
            source_item_id
        );

        DECLARE @changed_item_count INT = (
            SELECT COUNT(*)
            FROM #changed_item_costs
        );

        UPDATE target
        SET
            internal_product_id =
                source.internal_product_id,
            source_raw_order_version_id =
                source.source_raw_order_version_id,
            order_created_date =
                source.order_created_date,
            quantity = source.quantity,
            resolved_unit_cost =
                source.resolved_unit_cost,
            line_product_cost =
                source.line_product_cost,
            cost_source =
                source.cost_source,
            is_estimated =
                source.is_estimated,
            cost_effective_date =
                source.cost_effective_date,
            source_product_cost_import_batch_id =
                source
                    .source_product_cost_import_batch_id,
            source_raw_product_cost_master_id =
                source
                    .source_raw_product_cost_master_id,
            source_raw_product_cost_history_id =
                source
                    .source_raw_product_cost_history_id,
            refreshed_at_utc = SYSUTCDATETIME()

        FROM stg.pancake_order_item_costs AS target

        INNER JOIN #source_item_costs AS source
            ON source.shop_id = target.shop_id
           AND source.order_id = target.order_id
           AND source.source_item_id =
               target.source_item_id

        INNER JOIN #changed_item_costs AS changed
            ON changed.shop_id = target.shop_id
           AND changed.order_id = target.order_id
           AND changed.source_item_id =
               target.source_item_id;

        INSERT INTO stg.pancake_order_item_costs (
            shop_id,
            order_id,
            source_item_id,
            internal_product_id,
            source_raw_order_version_id,
            order_created_date,
            quantity,
            resolved_unit_cost,
            line_product_cost,
            cost_source,
            is_estimated,
            cost_effective_date,
            source_product_cost_import_batch_id,
            source_raw_product_cost_master_id,
            source_raw_product_cost_history_id
        )
        SELECT
            source.shop_id,
            source.order_id,
            source.source_item_id,
            source.internal_product_id,
            source.source_raw_order_version_id,
            source.order_created_date,
            source.quantity,
            source.resolved_unit_cost,
            source.line_product_cost,
            source.cost_source,
            source.is_estimated,
            source.cost_effective_date,
            source.source_product_cost_import_batch_id,
            source.source_raw_product_cost_master_id,
            source.source_raw_product_cost_history_id

        FROM #source_item_costs AS source

        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.pancake_order_item_costs AS target
            WHERE target.shop_id = source.shop_id
              AND target.order_id = source.order_id
              AND target.source_item_id =
                  source.source_item_id
        );

        DELETE target
        FROM stg.pancake_order_item_costs AS target
        WHERE NOT EXISTS (
            SELECT 1
            FROM #source_item_costs AS source
            WHERE source.shop_id = target.shop_id
              AND source.order_id = target.order_id
              AND source.source_item_id =
                  target.source_item_id
        );

        COMMIT TRANSACTION;

        SELECT
            @changed_item_count AS changed_item_costs,

            COUNT(*) AS staged_item_costs,

            SUM(
                CASE
                    WHEN cost_source =
                        'NOT_REQUIRED_CANCELED'
                    THEN 1 ELSE 0
                END
            ) AS cancelled_rows,

            SUM(
                CASE
                    WHEN cost_source = 'HISTORY'
                    THEN 1 ELSE 0
                END
            ) AS history_rows,

            SUM(
                CASE
                    WHEN cost_source =
                        'MASTER_FALLBACK'
                    THEN 1 ELSE 0
                END
            ) AS fallback_rows,

            SUM(
                CASE
                    WHEN cost_source IN (
                        'ESTIMATED_DEFAULT',
                        'MANUAL_ESTIMATE'
                    )
                    THEN 1 ELSE 0
                END
            ) AS estimated_rows,

            SUM(
                CASE
                    WHEN cost_source = 'MISSING_COST'
                    THEN 1 ELSE 0
                END
            ) AS missing_rows,

            SUM(
                COALESCE(
                    line_product_cost,
                    0
                )
            ) AS total_line_product_cost

        FROM stg.pancake_order_item_costs;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;