CREATE OR ALTER PROCEDURE mart.refresh_order_item_economics
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID(N'mart.order_item_economics', N'U') IS NULL
        BEGIN
            THROW 51301,
                'mart.order_item_economics does not exist.',
                1;
        END;

        IF OBJECT_ID(N'mart.order_economics', N'U') IS NULL
           OR OBJECT_ID(N'mart.dim_products', N'U') IS NULL
           OR OBJECT_ID(N'mart.dim_meta_ads', N'U') IS NULL
        BEGIN
            THROW 51302,
                'A required MART dependency does not exist.',
                1;
        END;

        DECLARE @unattributed_product_key BIGINT = (
            SELECT product_key
            FROM mart.dim_products
            WHERE product_natural_key =
                  N'__UNATTRIBUTED_PRODUCT__'
        );

        IF @unattributed_product_key IS NULL
        BEGIN
            THROW 51303,
                'The unattributed product member is missing.',
                1;
        END;

        IF EXISTS (
            SELECT 1
            FROM stg.pancake_order_items AS items
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.dim_products AS products
                WHERE products.internal_product_id =
                      items.internal_product_id
            )
        )
        BEGIN
            THROW 51304,
                'An order item cannot be mapped to dim_products.',
                1;
        END;

        IF EXISTS (
            SELECT 1
            FROM stg.pancake_order_items AS items
            WHERE NOT EXISTS (
                SELECT 1
                FROM stg.pancake_order_item_costs AS costs
                WHERE costs.shop_id = items.shop_id
                  AND costs.order_id = items.order_id
                  AND costs.source_item_id = items.source_item_id
            )
        )
        BEGIN
            THROW 51305,
                'An order item has no cost-resolution row.',
                1;
        END;

        IF EXISTS (
            SELECT 1
            FROM mart.order_economics AS orders
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.dim_meta_ads AS ads
                WHERE ads.ad_id = COALESCE(
                    NULLIF(LTRIM(RTRIM(orders.ad_id)), N''),
                    N'__UNATTRIBUTED__'
                )
            )
        )
        BEGIN
            THROW 51306,
                'An order cannot be mapped to dim_meta_ads.',
                1;
        END;

        ;WITH item_base AS (
            SELECT
                items.shop_id,
                items.order_id,
                items.source_item_id,
                products.product_key,
                ads.ad_key,
                orders.order_date,
                orders.economic_status,
                orders.is_finalized,
                items.source_raw_order_version_id,
                items.source_product_id,
                items.source_variation_id,
                items.quantity,
                items.unit_retail_price,
                CAST(
                    COALESCE(items.unit_retail_price, 0)
                    * items.quantity
                    AS DECIMAL(19, 2)
                ) AS gross_line_revenue,
                CAST(
                    COALESCE(
                        orders.source_total_price_after_discount,
                        0
                    )
                    AS DECIMAL(19, 2)
                ) AS order_source_product_revenue,
                orders.projected_total_revenue
                    AS order_projected_revenue,
                orders.projected_cogs
                    AS order_projected_cogs,
                orders.projected_shipping_cost
                    AS order_projected_shipping,
                orders.recognized_total_revenue
                    AS order_recognized_revenue,
                orders.recognized_cogs
                    AS order_recognized_cogs,
                orders.recognized_shipping_cost
                    AS order_recognized_shipping,
                costs.resolved_unit_cost,
                costs.line_product_cost,
                costs.cost_source,
                costs.is_estimated,
                CAST(
                    CASE
                        WHEN costs.cost_source = 'MISSING_COST'
                        THEN 1
                        ELSE 0
                    END
                    AS BIT
                ) AS is_missing_cost
            FROM stg.pancake_order_items AS items
            INNER JOIN mart.order_economics AS orders
                ON orders.shop_id = items.shop_id
               AND orders.order_id = items.order_id
            INNER JOIN mart.dim_products AS products
                ON products.internal_product_id =
                   items.internal_product_id
            INNER JOIN mart.dim_meta_ads AS ads
                ON ads.ad_id = COALESCE(
                    NULLIF(LTRIM(RTRIM(orders.ad_id)), N''),
                    N'__UNATTRIBUTED__'
                )
            INNER JOIN stg.pancake_order_item_costs AS costs
                ON costs.shop_id = items.shop_id
               AND costs.order_id = items.order_id
               AND costs.source_item_id = items.source_item_id
        )
        SELECT
            base.*,
            CAST(
                SUM(base.gross_line_revenue) OVER (
                    PARTITION BY base.shop_id, base.order_id
                )
                AS DECIMAL(19, 2)
            ) AS order_gross_item_revenue,
            COUNT(*) OVER (
                PARTITION BY base.shop_id, base.order_id
            ) AS order_item_count,
            ROW_NUMBER() OVER (
                PARTITION BY base.shop_id, base.order_id
                ORDER BY
                    base.gross_line_revenue DESC,
                    base.source_item_id ASC
            ) AS allocation_rank
        INTO #item_base
        FROM item_base AS base;

        CREATE UNIQUE CLUSTERED INDEX IX_item_base
            ON #item_base (
                shop_id,
                order_id,
                source_item_id
            );

        SELECT
            base.*,
            CAST(
                CASE
                    WHEN base.order_gross_item_revenue > 0
                    THEN
                        base.gross_line_revenue
                        / base.order_gross_item_revenue
                    ELSE
                        CAST(1 AS DECIMAL(19, 12))
                        / NULLIF(base.order_item_count, 0)
                END
                AS DECIMAL(19, 12)
            ) AS allocation_weight,
            CAST(
                CASE
                    WHEN base.order_gross_item_revenue > 0
                    THEN 'GROSS_REVENUE_SHARE'
                    ELSE 'EQUAL_SHARE_ZERO_GROSS'
                END
                AS VARCHAR(40)
            ) AS allocation_method
        INTO #item_weights
        FROM #item_base AS base;

        CREATE UNIQUE CLUSTERED INDEX IX_item_weights
            ON #item_weights (
                shop_id,
                order_id,
                source_item_id
            );

        SELECT
            weights.*,
            CAST(
                ROUND(
                    weights.order_source_product_revenue
                    * weights.allocation_weight,
                    2
                )
                AS DECIMAL(19, 2)
            ) AS pre_source_revenue,
            CAST(
                ROUND(
                    weights.order_projected_revenue
                    * weights.allocation_weight,
                    2
                )
                AS DECIMAL(19, 2)
            ) AS pre_projected_revenue,
            CAST(
                CASE
                    WHEN weights.order_projected_cogs = 0
                    THEN 0
                    ELSE COALESCE(weights.line_product_cost, 0)
                END
                AS DECIMAL(19, 2)
            ) AS projected_line_cogs,
            CAST(
                ROUND(
                    weights.order_projected_shipping
                    * weights.allocation_weight,
                    2
                )
                AS DECIMAL(19, 2)
            ) AS pre_projected_shipping,
            CAST(
                CASE
                    WHEN weights.is_finalized = 1
                    THEN ROUND(
                        weights.order_recognized_revenue
                        * weights.allocation_weight,
                        2
                    )
                    ELSE NULL
                END
                AS DECIMAL(19, 2)
            ) AS pre_recognized_revenue,
            CAST(
                CASE
                    WHEN weights.is_finalized = 1
                         AND weights.order_recognized_cogs <> 0
                    THEN COALESCE(weights.line_product_cost, 0)
                    WHEN weights.is_finalized = 1
                    THEN 0
                    ELSE NULL
                END
                AS DECIMAL(19, 2)
            ) AS recognized_line_cogs,
            CAST(
                CASE
                    WHEN weights.is_finalized = 1
                    THEN ROUND(
                        weights.order_recognized_shipping
                        * weights.allocation_weight,
                        2
                    )
                    ELSE NULL
                END
                AS DECIMAL(19, 2)
            ) AS pre_recognized_shipping
        INTO #item_preallocated
        FROM #item_weights AS weights;

        CREATE UNIQUE CLUSTERED INDEX IX_item_preallocated
            ON #item_preallocated (
                shop_id,
                order_id,
                source_item_id
            );

        SELECT
            pre.*,
            SUM(pre.pre_source_revenue) OVER (
                PARTITION BY pre.shop_id, pre.order_id
            ) AS sum_pre_source_revenue,
            SUM(pre.pre_projected_revenue) OVER (
                PARTITION BY pre.shop_id, pre.order_id
            ) AS sum_pre_projected_revenue,
            SUM(pre.pre_projected_shipping) OVER (
                PARTITION BY pre.shop_id, pre.order_id
            ) AS sum_pre_projected_shipping,
            SUM(
                COALESCE(pre.pre_recognized_revenue, 0)
            ) OVER (
                PARTITION BY pre.shop_id, pre.order_id
            ) AS sum_pre_recognized_revenue,
            SUM(
                COALESCE(pre.pre_recognized_shipping, 0)
            ) OVER (
                PARTITION BY pre.shop_id, pre.order_id
            ) AS sum_pre_recognized_shipping
        INTO #item_allocation_totals
        FROM #item_preallocated AS pre;

        CREATE UNIQUE CLUSTERED INDEX IX_item_allocation_totals
            ON #item_allocation_totals (
                shop_id,
                order_id,
                source_item_id
            );

        /*
         * Copy the target metadata explicitly. In particular,
         * Recognized fields must remain nullable for non-finalized
         * orders. Synthetic rows use an explicit NOT_APPLICABLE cost
         * source so their meaning does not depend on inferred nullability.
         */
        SELECT TOP (0)
            target.shop_id,
            target.order_id,
            target.source_item_id,
            target.product_key,
            target.ad_key,
            target.order_date,
            target.item_attribution_status,
            target.allocation_method,
            target.economic_status,
            target.is_finalized,
            target.source_raw_order_version_id,
            target.source_product_id,
            target.source_variation_id,
            target.quantity,
            target.unit_retail_price,
            target.gross_line_revenue,
            target.order_gross_item_revenue,
            target.order_source_product_revenue,
            target.revenue_allocation_weight,
            target.allocated_source_product_revenue,
            target.allocated_discount_adjustment,
            target.resolved_unit_cost,
            target.source_line_product_cost,
            target.cost_source,
            target.is_estimated_cost,
            target.is_missing_cost,
            target.projected_total_revenue,
            target.projected_cogs,
            target.projected_shipping_cost,
            target.projected_contribution_before_ads,
            target.recognized_total_revenue,
            target.recognized_cogs,
            target.recognized_shipping_cost,
            target.recognized_contribution_before_ads
        INTO #source_order_item_economics
        FROM mart.order_item_economics AS target;

        INSERT INTO #source_order_item_economics (
            shop_id,
            order_id,
            source_item_id,
            product_key,
            ad_key,
            order_date,
            item_attribution_status,
            allocation_method,
            economic_status,
            is_finalized,
            source_raw_order_version_id,
            source_product_id,
            source_variation_id,
            quantity,
            unit_retail_price,
            gross_line_revenue,
            order_gross_item_revenue,
            order_source_product_revenue,
            revenue_allocation_weight,
            allocated_source_product_revenue,
            allocated_discount_adjustment,
            resolved_unit_cost,
            source_line_product_cost,
            cost_source,
            is_estimated_cost,
            is_missing_cost,
            projected_total_revenue,
            projected_cogs,
            projected_shipping_cost,
            projected_contribution_before_ads,
            recognized_total_revenue,
            recognized_cogs,
            recognized_shipping_cost,
            recognized_contribution_before_ads
        )
        SELECT
            allocated.shop_id,
            allocated.order_id,
            allocated.source_item_id,
            allocated.product_key,
            allocated.ad_key,
            allocated.order_date,
            CAST('ITEM_MAPPED' AS VARCHAR(30))
                AS item_attribution_status,
            allocated.allocation_method,
            allocated.economic_status,
            allocated.is_finalized,
            allocated.source_raw_order_version_id,
            allocated.source_product_id,
            allocated.source_variation_id,
            allocated.quantity,
            allocated.unit_retail_price,
            allocated.gross_line_revenue,
            allocated.order_gross_item_revenue,
            allocated.order_source_product_revenue,
            allocated.allocation_weight
                AS revenue_allocation_weight,
            final_values.allocated_source_revenue
                AS allocated_source_product_revenue,
            CAST(
                allocated.gross_line_revenue
                - final_values.allocated_source_revenue
                AS DECIMAL(19, 2)
            ) AS allocated_discount_adjustment,
            allocated.resolved_unit_cost,
            allocated.line_product_cost
                AS source_line_product_cost,
            CAST(
                NULLIF(allocated.cost_source, '')
                AS VARCHAR(30)
            ) AS cost_source,
            allocated.is_estimated AS is_estimated_cost,
            allocated.is_missing_cost,
            final_values.projected_revenue
                AS projected_total_revenue,
            allocated.projected_line_cogs
                AS projected_cogs,
            final_values.projected_shipping
                AS projected_shipping_cost,
            CAST(
                final_values.projected_revenue
                - allocated.projected_line_cogs
                - final_values.projected_shipping
                AS DECIMAL(19, 2)
            ) AS projected_contribution_before_ads,
            final_values.recognized_revenue
                AS recognized_total_revenue,
            allocated.recognized_line_cogs
                AS recognized_cogs,
            final_values.recognized_shipping
                AS recognized_shipping_cost,
            CAST(
                CASE
                    WHEN allocated.is_finalized = 1
                    THEN
                        final_values.recognized_revenue
                        - allocated.recognized_line_cogs
                        - final_values.recognized_shipping
                    ELSE NULL
                END
                AS DECIMAL(19, 2)
            ) AS recognized_contribution_before_ads
        FROM #item_allocation_totals AS allocated
        CROSS APPLY (
            SELECT
                CAST(
                    allocated.pre_source_revenue
                    + CASE
                        WHEN allocated.allocation_rank = 1
                        THEN
                            allocated.order_source_product_revenue
                            - allocated.sum_pre_source_revenue
                        ELSE 0
                      END
                    AS DECIMAL(19, 2)
                ) AS allocated_source_revenue,
                CAST(
                    allocated.pre_projected_revenue
                    + CASE
                        WHEN allocated.allocation_rank = 1
                        THEN
                            allocated.order_projected_revenue
                            - allocated.sum_pre_projected_revenue
                        ELSE 0
                      END
                    AS DECIMAL(19, 2)
                ) AS projected_revenue,
                CAST(
                    allocated.pre_projected_shipping
                    + CASE
                        WHEN allocated.allocation_rank = 1
                        THEN
                            allocated.order_projected_shipping
                            - allocated.sum_pre_projected_shipping
                        ELSE 0
                      END
                    AS DECIMAL(19, 2)
                ) AS projected_shipping,
                CAST(
                    CASE
                        WHEN allocated.is_finalized = 1
                        THEN
                            allocated.pre_recognized_revenue
                            + CASE
                                WHEN allocated.allocation_rank = 1
                                THEN
                                    allocated.order_recognized_revenue
                                    - allocated.sum_pre_recognized_revenue
                                ELSE 0
                              END
                        ELSE NULL
                    END
                    AS DECIMAL(19, 2)
                ) AS recognized_revenue,
                CAST(
                    CASE
                        WHEN allocated.is_finalized = 1
                        THEN
                            allocated.pre_recognized_shipping
                            + CASE
                                WHEN allocated.allocation_rank = 1
                                THEN
                                    allocated.order_recognized_shipping
                                    - allocated.sum_pre_recognized_shipping
                                ELSE 0
                              END
                        ELSE NULL
                    END
                    AS DECIMAL(19, 2)
                ) AS recognized_shipping
        ) AS final_values;

        INSERT INTO #source_order_item_economics (
            shop_id,
            order_id,
            source_item_id,
            product_key,
            ad_key,
            order_date,
            item_attribution_status,
            allocation_method,
            economic_status,
            is_finalized,
            source_raw_order_version_id,
            source_product_id,
            source_variation_id,
            quantity,
            unit_retail_price,
            gross_line_revenue,
            order_gross_item_revenue,
            order_source_product_revenue,
            revenue_allocation_weight,
            allocated_source_product_revenue,
            allocated_discount_adjustment,
            resolved_unit_cost,
            source_line_product_cost,
            cost_source,
            is_estimated_cost,
            is_missing_cost,
            projected_total_revenue,
            projected_cogs,
            projected_shipping_cost,
            projected_contribution_before_ads,
            recognized_total_revenue,
            recognized_cogs,
            recognized_shipping_cost,
            recognized_contribution_before_ads
        )
        SELECT
            orders.shop_id,
            orders.order_id,
            CAST(-1 AS BIGINT),
            @unattributed_product_key,
            ads.ad_key,
            orders.order_date,
            CAST('UNATTRIBUTED_PRODUCT' AS VARCHAR(30)),
            CAST('UNATTRIBUTED_ORDER' AS VARCHAR(40)),
            orders.economic_status,
            orders.is_finalized,
            orders.source_raw_order_version_id,
            CAST(NULL AS NVARCHAR(100)),
            CAST(NULL AS NVARCHAR(100)),
            CAST(0 AS INT),
            CAST(NULL AS DECIMAL(19, 2)),
            CAST(0 AS DECIMAL(19, 2)),
            CAST(0 AS DECIMAL(19, 2)),
            CAST(
                COALESCE(
                    orders.source_total_price_after_discount,
                    0
                )
                AS DECIMAL(19, 2)
            ),
            CAST(1 AS DECIMAL(19, 12)),
            CAST(
                COALESCE(
                    orders.source_total_price_after_discount,
                    0
                )
                AS DECIMAL(19, 2)
            ),
            CAST(
                -COALESCE(
                    orders.source_total_price_after_discount,
                    0
                )
                AS DECIMAL(19, 2)
            ),
            CAST(NULL AS DECIMAL(19, 2)),
            CAST(NULL AS DECIMAL(19, 2)),
            CAST('NOT_APPLICABLE' AS VARCHAR(30)),
            orders.has_estimated_cost,
            orders.has_missing_cost,
            orders.projected_total_revenue,
            orders.projected_cogs,
            orders.projected_shipping_cost,
            orders.projected_contribution_profit,
            orders.recognized_total_revenue,
            orders.recognized_cogs,
            orders.recognized_shipping_cost,
            orders.recognized_contribution_profit
        FROM mart.order_economics AS orders
        INNER JOIN mart.dim_meta_ads AS ads
            ON ads.ad_id = COALESCE(
                NULLIF(LTRIM(RTRIM(orders.ad_id)), N''),
                N'__UNATTRIBUTED__'
            )
        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.pancake_order_items AS items
            WHERE items.shop_id = orders.shop_id
              AND items.order_id = orders.order_id
        );

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_order_item_economics
        ON #source_order_item_economics (
            shop_id,
            order_id,
            source_item_id
        );

        IF EXISTS (
            SELECT 1
            FROM (
                SELECT
                    source.shop_id,
                    source.order_id,
                    SUM(source.allocated_source_product_revenue)
                        AS source_revenue,
                    SUM(source.projected_total_revenue)
                        AS projected_revenue,
                    SUM(source.projected_cogs)
                        AS projected_cogs,
                    SUM(source.projected_shipping_cost)
                        AS projected_shipping,
                    SUM(COALESCE(source.recognized_total_revenue, 0))
                        AS recognized_revenue,
                    SUM(COALESCE(source.recognized_cogs, 0))
                        AS recognized_cogs,
                    SUM(COALESCE(source.recognized_shipping_cost, 0))
                        AS recognized_shipping
                FROM #source_order_item_economics AS source
                GROUP BY source.shop_id, source.order_id
            ) AS item_totals
            INNER JOIN mart.order_economics AS orders
                ON orders.shop_id = item_totals.shop_id
               AND orders.order_id = item_totals.order_id
            WHERE ABS(
                    item_totals.source_revenue
                    - COALESCE(
                        orders.source_total_price_after_discount,
                        0
                    )
                  ) > 0.01
               OR ABS(
                    item_totals.projected_revenue
                    - orders.projected_total_revenue
                  ) > 0.01
               OR ABS(
                    item_totals.projected_cogs
                    - orders.projected_cogs
                  ) > 0.01
               OR ABS(
                    item_totals.projected_shipping
                    - orders.projected_shipping_cost
                  ) > 0.01
               OR ABS(
                    COALESCE(item_totals.recognized_revenue, 0)
                    - COALESCE(orders.recognized_total_revenue, 0)
                  ) > 0.01
               OR ABS(
                    COALESCE(item_totals.recognized_cogs, 0)
                    - COALESCE(orders.recognized_cogs, 0)
                  ) > 0.01
               OR ABS(
                    COALESCE(item_totals.recognized_shipping, 0)
                    - COALESCE(orders.recognized_shipping_cost, 0)
                  ) > 0.01
        )
        BEGIN
            THROW 51307,
                'Item allocations do not reconcile to Order Economics.',
                1;
        END;

        SELECT
            source.shop_id,
            source.order_id,
            source.source_item_id
        INTO #changed_order_item_economics
        FROM #source_order_item_economics AS source
        LEFT JOIN mart.order_item_economics AS target
            ON target.shop_id = source.shop_id
           AND target.order_id = source.order_id
           AND target.source_item_id = source.source_item_id
        WHERE target.source_item_id IS NULL
           OR EXISTS (
                SELECT
                    source.product_key,
                    source.ad_key,
                    source.order_date,
                    source.item_attribution_status,
                    source.allocation_method,
                    source.economic_status,
                    source.is_finalized,
                    source.source_raw_order_version_id,
                    source.source_product_id,
                    source.source_variation_id,
                    source.quantity,
                    source.unit_retail_price,
                    source.gross_line_revenue,
                    source.order_gross_item_revenue,
                    source.order_source_product_revenue,
                    source.revenue_allocation_weight,
                    source.allocated_source_product_revenue,
                    source.allocated_discount_adjustment,
                    source.resolved_unit_cost,
                    source.source_line_product_cost,
                    source.cost_source,
                    source.is_estimated_cost,
                    source.is_missing_cost,
                    source.projected_total_revenue,
                    source.projected_cogs,
                    source.projected_shipping_cost,
                    source.projected_contribution_before_ads,
                    source.recognized_total_revenue,
                    source.recognized_cogs,
                    source.recognized_shipping_cost,
                    source.recognized_contribution_before_ads

                EXCEPT

                SELECT
                    target.product_key,
                    target.ad_key,
                    target.order_date,
                    target.item_attribution_status,
                    target.allocation_method,
                    target.economic_status,
                    target.is_finalized,
                    target.source_raw_order_version_id,
                    target.source_product_id,
                    target.source_variation_id,
                    target.quantity,
                    target.unit_retail_price,
                    target.gross_line_revenue,
                    target.order_gross_item_revenue,
                    target.order_source_product_revenue,
                    target.revenue_allocation_weight,
                    target.allocated_source_product_revenue,
                    target.allocated_discount_adjustment,
                    target.resolved_unit_cost,
                    target.source_line_product_cost,
                    target.cost_source,
                    target.is_estimated_cost,
                    target.is_missing_cost,
                    target.projected_total_revenue,
                    target.projected_cogs,
                    target.projected_shipping_cost,
                    target.projected_contribution_before_ads,
                    target.recognized_total_revenue,
                    target.recognized_cogs,
                    target.recognized_shipping_cost,
                    target.recognized_contribution_before_ads
           );

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_order_item_economics
        ON #changed_order_item_economics (
            shop_id,
            order_id,
            source_item_id
        );

        DECLARE @inserted_row_count INT = (
            SELECT COUNT(*)
            FROM #source_order_item_economics AS source
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.order_item_economics AS target
                WHERE target.shop_id = source.shop_id
                  AND target.order_id = source.order_id
                  AND target.source_item_id = source.source_item_id
            )
        );

        DECLARE @updated_row_count INT = (
            SELECT COUNT(*)
            FROM #changed_order_item_economics AS changed
            WHERE EXISTS (
                SELECT 1
                FROM mart.order_item_economics AS target
                WHERE target.shop_id = changed.shop_id
                  AND target.order_id = changed.order_id
                  AND target.source_item_id = changed.source_item_id
            )
        );

        DECLARE @deleted_row_count INT = (
            SELECT COUNT(*)
            FROM mart.order_item_economics AS target
            WHERE NOT EXISTS (
                SELECT 1
                FROM #source_order_item_economics AS source
                WHERE source.shop_id = target.shop_id
                  AND source.order_id = target.order_id
                  AND source.source_item_id = target.source_item_id
            )
        );

        DELETE target
        FROM mart.order_item_economics AS target
        WHERE NOT EXISTS (
            SELECT 1
            FROM #source_order_item_economics AS source
            WHERE source.shop_id = target.shop_id
              AND source.order_id = target.order_id
              AND source.source_item_id = target.source_item_id
        );

        UPDATE target
        SET
            product_key = source.product_key,
            ad_key = source.ad_key,
            order_date = source.order_date,
            item_attribution_status =
                source.item_attribution_status,
            allocation_method = source.allocation_method,
            economic_status = source.economic_status,
            is_finalized = source.is_finalized,
            source_raw_order_version_id =
                source.source_raw_order_version_id,
            source_product_id = source.source_product_id,
            source_variation_id = source.source_variation_id,
            quantity = source.quantity,
            unit_retail_price = source.unit_retail_price,
            gross_line_revenue = source.gross_line_revenue,
            order_gross_item_revenue =
                source.order_gross_item_revenue,
            order_source_product_revenue =
                source.order_source_product_revenue,
            revenue_allocation_weight =
                source.revenue_allocation_weight,
            allocated_source_product_revenue =
                source.allocated_source_product_revenue,
            allocated_discount_adjustment =
                source.allocated_discount_adjustment,
            resolved_unit_cost = source.resolved_unit_cost,
            source_line_product_cost =
                source.source_line_product_cost,
            cost_source = source.cost_source,
            is_estimated_cost = source.is_estimated_cost,
            is_missing_cost = source.is_missing_cost,
            projected_total_revenue =
                source.projected_total_revenue,
            projected_cogs = source.projected_cogs,
            projected_shipping_cost =
                source.projected_shipping_cost,
            projected_contribution_before_ads =
                source.projected_contribution_before_ads,
            recognized_total_revenue =
                source.recognized_total_revenue,
            recognized_cogs = source.recognized_cogs,
            recognized_shipping_cost =
                source.recognized_shipping_cost,
            recognized_contribution_before_ads =
                source.recognized_contribution_before_ads,
            mart_refreshed_at_utc = SYSUTCDATETIME()
        FROM mart.order_item_economics AS target
        INNER JOIN #source_order_item_economics AS source
            ON source.shop_id = target.shop_id
           AND source.order_id = target.order_id
           AND source.source_item_id = target.source_item_id
        INNER JOIN #changed_order_item_economics AS changed
            ON changed.shop_id = source.shop_id
           AND changed.order_id = source.order_id
           AND changed.source_item_id = source.source_item_id;

        INSERT INTO mart.order_item_economics (
            shop_id,
            order_id,
            source_item_id,
            product_key,
            ad_key,
            order_date,
            item_attribution_status,
            allocation_method,
            economic_status,
            is_finalized,
            source_raw_order_version_id,
            source_product_id,
            source_variation_id,
            quantity,
            unit_retail_price,
            gross_line_revenue,
            order_gross_item_revenue,
            order_source_product_revenue,
            revenue_allocation_weight,
            allocated_source_product_revenue,
            allocated_discount_adjustment,
            resolved_unit_cost,
            source_line_product_cost,
            cost_source,
            is_estimated_cost,
            is_missing_cost,
            projected_total_revenue,
            projected_cogs,
            projected_shipping_cost,
            projected_contribution_before_ads,
            recognized_total_revenue,
            recognized_cogs,
            recognized_shipping_cost,
            recognized_contribution_before_ads
        )
        SELECT
            source.shop_id,
            source.order_id,
            source.source_item_id,
            source.product_key,
            source.ad_key,
            source.order_date,
            source.item_attribution_status,
            source.allocation_method,
            source.economic_status,
            source.is_finalized,
            source.source_raw_order_version_id,
            source.source_product_id,
            source.source_variation_id,
            source.quantity,
            source.unit_retail_price,
            source.gross_line_revenue,
            source.order_gross_item_revenue,
            source.order_source_product_revenue,
            source.revenue_allocation_weight,
            source.allocated_source_product_revenue,
            source.allocated_discount_adjustment,
            source.resolved_unit_cost,
            source.source_line_product_cost,
            source.cost_source,
            source.is_estimated_cost,
            source.is_missing_cost,
            source.projected_total_revenue,
            source.projected_cogs,
            source.projected_shipping_cost,
            source.projected_contribution_before_ads,
            source.recognized_total_revenue,
            source.recognized_cogs,
            source.recognized_shipping_cost,
            source.recognized_contribution_before_ads
        FROM #source_order_item_economics AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM mart.order_item_economics AS target
            WHERE target.shop_id = source.shop_id
              AND target.order_id = source.order_id
              AND target.source_item_id = source.source_item_id
        );

        COMMIT TRANSACTION;

        SELECT
            @inserted_row_count AS inserted_rows,
            @updated_row_count AS updated_rows,
            @deleted_row_count AS deleted_rows,
            COUNT(*) AS fact_rows,
            SUM(
                CASE
                    WHEN item_attribution_status = 'ITEM_MAPPED'
                    THEN 1
                    ELSE 0
                END
            ) AS mapped_item_rows,
            SUM(
                CASE
                    WHEN item_attribution_status =
                         'UNATTRIBUTED_PRODUCT'
                    THEN 1
                    ELSE 0
                END
            ) AS unattributed_order_rows,
            SUM(allocated_source_product_revenue)
                AS allocated_source_revenue,
            SUM(projected_total_revenue)
                AS projected_total_revenue,
            SUM(projected_cogs) AS projected_cogs,
            SUM(projected_shipping_cost)
                AS projected_shipping_cost,
            SUM(projected_contribution_before_ads)
                AS projected_contribution_before_ads,
            SUM(COALESCE(recognized_total_revenue, 0))
                AS recognized_total_revenue,
            SUM(
                COALESCE(
                    recognized_contribution_before_ads,
                    0
                )
            )
                AS recognized_contribution_before_ads
        FROM mart.order_item_economics;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
