CREATE OR ALTER PROCEDURE
    mart.refresh_product_ad_economics_daily
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID(
            N'mart.product_ad_economics_daily',
            N'U'
        ) IS NULL
        BEGIN
            THROW 51401,
                'mart.product_ad_economics_daily does not exist.',
                1;
        END;

        IF OBJECT_ID(N'mart.order_item_economics', N'U') IS NULL
           OR OBJECT_ID(N'mart.ad_economics_daily', N'U') IS NULL
           OR OBJECT_ID(N'mart.dim_products', N'U') IS NULL
        BEGIN
            THROW 51402,
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
            THROW 51403,
                'The unattributed product member is missing.',
                1;
        END;

        /*
         * First aggregate item rows to product + order. This keeps
         * product_order_count correct when an order contains the same
         * product on more than one source item line.
         */
        SELECT
            items.order_date AS analysis_date,
            items.ad_key,
            items.product_key,
            items.shop_id,
            items.order_id,
            SUM(
                CASE
                    WHEN items.item_attribution_status = 'ITEM_MAPPED'
                    THEN 1
                    ELSE 0
                END
            ) AS item_line_count,
            CAST(SUM(items.quantity) AS BIGINT)
                AS total_quantity,
            MAX(CAST(items.is_finalized AS INT))
                AS is_finalized,
            MAX(
                CASE
                    WHEN items.economic_status = 'FINAL_DELIVERED'
                    THEN 1 ELSE 0
                END
            ) AS is_delivered,
            MAX(
                CASE
                    WHEN items.economic_status = 'FINAL_RETURNED'
                    THEN 1 ELSE 0
                END
            ) AS is_returned,
            MAX(
                CASE
                    WHEN items.economic_status = 'FINAL_CANCELED'
                    THEN 1 ELSE 0
                END
            ) AS is_canceled,
            MAX(
                CASE
                    WHEN items.economic_status =
                         'PROVISIONAL_RETURNING'
                    THEN 1 ELSE 0
                END
            ) AS is_returning,
            MAX(
                CASE
                    WHEN items.economic_status = 'IN_PROGRESS'
                    THEN 1 ELSE 0
                END
            ) AS is_in_progress,
            MAX(CAST(items.is_estimated_cost AS INT))
                AS has_estimated_cost,
            MAX(CAST(items.is_missing_cost AS INT))
                AS has_missing_cost,
            CAST(
                SUM(items.allocated_source_product_revenue)
                AS DECIMAL(19, 2)
            ) AS allocated_source_product_revenue,
            CAST(
                SUM(items.projected_total_revenue)
                AS DECIMAL(19, 2)
            ) AS projected_total_revenue,
            CAST(
                SUM(items.projected_cogs)
                AS DECIMAL(19, 2)
            ) AS projected_cogs,
            CAST(
                SUM(items.projected_shipping_cost)
                AS DECIMAL(19, 2)
            ) AS projected_shipping_cost,
            CAST(
                SUM(items.projected_contribution_before_ads)
                AS DECIMAL(19, 2)
            ) AS projected_contribution_before_ads,
            CAST(
                SUM(COALESCE(items.recognized_total_revenue, 0))
                AS DECIMAL(19, 2)
            ) AS recognized_total_revenue,
            CAST(
                SUM(COALESCE(items.recognized_cogs, 0))
                AS DECIMAL(19, 2)
            ) AS recognized_cogs,
            CAST(
                SUM(COALESCE(items.recognized_shipping_cost, 0))
                AS DECIMAL(19, 2)
            ) AS recognized_shipping_cost,
            CAST(
                SUM(
                    COALESCE(
                        items.recognized_contribution_before_ads,
                        0
                    )
                )
                AS DECIMAL(19, 2)
            ) AS recognized_contribution_before_ads
        INTO #product_order
        FROM mart.order_item_economics AS items
        GROUP BY
            items.order_date,
            items.ad_key,
            items.product_key,
            items.shop_id,
            items.order_id;

        CREATE UNIQUE CLUSTERED INDEX IX_product_order
            ON #product_order (
                analysis_date,
                ad_key,
                product_key,
                shop_id,
                order_id
            );

        SELECT
            product_order.analysis_date,
            product_order.ad_key,
            product_order.product_key,
            COUNT(*) AS product_order_count,
            SUM(product_order.item_line_count)
                AS item_line_count,
            CAST(SUM(product_order.total_quantity) AS BIGINT)
                AS total_quantity,
            SUM(product_order.is_finalized)
                AS finalized_product_order_count,
            SUM(product_order.is_delivered)
                AS delivered_product_order_count,
            SUM(product_order.is_returned)
                AS returned_product_order_count,
            SUM(product_order.is_canceled)
                AS canceled_product_order_count,
            SUM(product_order.is_returning)
                AS returning_product_order_count,
            SUM(product_order.is_in_progress)
                AS in_progress_product_order_count,
            SUM(product_order.has_estimated_cost)
                AS product_orders_with_estimated_cost,
            SUM(product_order.has_missing_cost)
                AS product_orders_with_missing_cost,
            CAST(
                SUM(
                    product_order.allocated_source_product_revenue
                )
                AS DECIMAL(19, 2)
            ) AS allocated_source_product_revenue,
            CAST(
                SUM(product_order.projected_total_revenue)
                AS DECIMAL(19, 2)
            ) AS projected_total_revenue,
            CAST(
                SUM(product_order.projected_cogs)
                AS DECIMAL(19, 2)
            ) AS projected_cogs,
            CAST(
                SUM(product_order.projected_shipping_cost)
                AS DECIMAL(19, 2)
            ) AS projected_shipping_cost,
            CAST(
                SUM(
                    product_order.projected_contribution_before_ads
                )
                AS DECIMAL(19, 2)
            ) AS projected_contribution_before_ads,
            CAST(
                SUM(product_order.recognized_total_revenue)
                AS DECIMAL(19, 2)
            ) AS recognized_total_revenue,
            CAST(
                SUM(product_order.recognized_cogs)
                AS DECIMAL(19, 2)
            ) AS recognized_cogs,
            CAST(
                SUM(product_order.recognized_shipping_cost)
                AS DECIMAL(19, 2)
            ) AS recognized_shipping_cost,
            CAST(
                SUM(
                    product_order.recognized_contribution_before_ads
                )
                AS DECIMAL(19, 2)
            ) AS recognized_contribution_before_ads
        INTO #product_daily
        FROM #product_order AS product_order
        GROUP BY
            product_order.analysis_date,
            product_order.ad_key,
            product_order.product_key;

        CREATE UNIQUE CLUSTERED INDEX IX_product_daily
            ON #product_daily (
                analysis_date,
                ad_key,
                product_key
            );

        IF EXISTS (
            SELECT 1
            FROM #product_daily AS products
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.ad_economics_daily AS ads
                WHERE ads.analysis_date = products.analysis_date
                  AND ads.ad_key = products.ad_key
            )
        )
        BEGIN
            THROW 51404,
                'Ad Economics must be refreshed before Product-Ad Economics.',
                1;
        END;

        SELECT
            products.analysis_date,
            products.ad_key,
            CAST(
                SUM(
                    CASE
                        WHEN products.allocated_source_product_revenue > 0
                        THEN products.allocated_source_product_revenue
                        ELSE 0
                    END
                )
                AS DECIMAL(19, 2)
            ) AS positive_source_revenue
        INTO #ad_allocation_basis
        FROM #product_daily AS products
        GROUP BY
            products.analysis_date,
            products.ad_key;

        CREATE UNIQUE CLUSTERED INDEX IX_ad_allocation_basis
            ON #ad_allocation_basis (
                analysis_date,
                ad_key
            );

        SELECT
            source.analysis_date,
            source.ad_key,
            source.product_key
        INTO #product_ad_keys
        FROM (
            SELECT
                products.analysis_date,
                products.ad_key,
                products.product_key
            FROM #product_daily AS products

            UNION

            SELECT
                ads.analysis_date,
                ads.ad_key,
                @unattributed_product_key
            FROM mart.ad_economics_daily AS ads
            LEFT JOIN #ad_allocation_basis AS basis
                ON basis.analysis_date = ads.analysis_date
               AND basis.ad_key = ads.ad_key
            WHERE NOT EXISTS (
                    SELECT 1
                    FROM #product_daily AS products
                    WHERE products.analysis_date = ads.analysis_date
                      AND products.ad_key = ads.ad_key
                  )
               OR (
                    ads.actual_ad_cost > 0
                    AND COALESCE(
                        basis.positive_source_revenue,
                        0
                    ) = 0
                  )
        ) AS source;

        CREATE UNIQUE CLUSTERED INDEX IX_product_ad_keys
            ON #product_ad_keys (
                analysis_date,
                ad_key,
                product_key
            );

        SELECT
            keys.analysis_date,
            keys.ad_key,
            keys.product_key,
            CAST(
                CASE
                    WHEN ads.has_meta_insight = 1
                     AND products.product_key IS NOT NULL
                    THEN 'META_AND_PRODUCT_ORDER'
                    WHEN ads.has_meta_insight = 1
                    THEN 'META_ONLY_UNATTRIBUTED'
                    ELSE 'ORDER_ONLY_PRODUCT'
                END
                AS VARCHAR(40)
            ) AS daily_presence_status,
            CAST(
                CASE
                    WHEN ads.actual_ad_cost = 0
                    THEN 'NO_META_COST'
                    WHEN COALESCE(basis.positive_source_revenue, 0) > 0
                    THEN 'SOURCE_REVENUE_SHARE'
                    ELSE 'UNATTRIBUTED_NO_BASIS'
                END
                AS VARCHAR(40)
            ) AS ad_cost_allocation_method,
            ads.has_meta_insight,
            CAST(
                CASE
                    WHEN products.product_key IS NOT NULL
                    THEN 1 ELSE 0
                END
                AS BIT
            ) AS has_product_orders,
            CAST(
                CASE
                    WHEN ads.actual_ad_cost > 0
                     AND calculated.allocation_weight > 0
                    THEN 1 ELSE 0
                END
                AS BIT
            ) AS has_allocated_ad_cost,
            calculated.allocation_weight
                AS ad_cost_allocation_weight,
            COALESCE(products.product_order_count, 0)
                AS product_order_count,
            COALESCE(products.item_line_count, 0)
                AS item_line_count,
            COALESCE(products.total_quantity, 0)
                AS total_quantity,
            COALESCE(products.finalized_product_order_count, 0)
                AS finalized_product_order_count,
            COALESCE(products.delivered_product_order_count, 0)
                AS delivered_product_order_count,
            COALESCE(products.returned_product_order_count, 0)
                AS returned_product_order_count,
            COALESCE(products.canceled_product_order_count, 0)
                AS canceled_product_order_count,
            COALESCE(products.returning_product_order_count, 0)
                AS returning_product_order_count,
            COALESCE(products.in_progress_product_order_count, 0)
                AS in_progress_product_order_count,
            COALESCE(products.product_orders_with_estimated_cost, 0)
                AS product_orders_with_estimated_cost,
            COALESCE(products.product_orders_with_missing_cost, 0)
                AS product_orders_with_missing_cost,
            CAST(
                COALESCE(
                    products.allocated_source_product_revenue,
                    0
                )
                AS DECIMAL(19, 2)
            ) AS allocated_source_product_revenue,
            CAST(
                COALESCE(products.projected_total_revenue, 0)
                AS DECIMAL(19, 2)
            ) AS projected_total_revenue,
            CAST(
                COALESCE(products.projected_cogs, 0)
                AS DECIMAL(19, 2)
            ) AS projected_cogs,
            CAST(
                COALESCE(products.projected_shipping_cost, 0)
                AS DECIMAL(19, 2)
            ) AS projected_shipping_cost,
            CAST(
                COALESCE(
                    products.projected_contribution_before_ads,
                    0
                )
                AS DECIMAL(19, 2)
            ) AS projected_contribution_before_ads,
            CAST(
                COALESCE(products.recognized_total_revenue, 0)
                AS DECIMAL(19, 2)
            ) AS recognized_total_revenue,
            CAST(
                COALESCE(products.recognized_cogs, 0)
                AS DECIMAL(19, 2)
            ) AS recognized_cogs,
            CAST(
                COALESCE(products.recognized_shipping_cost, 0)
                AS DECIMAL(19, 2)
            ) AS recognized_shipping_cost,
            CAST(
                COALESCE(
                    products.recognized_contribution_before_ads,
                    0
                )
                AS DECIMAL(19, 2)
            ) AS recognized_contribution_before_ads,
            ads.meta_spend,
            ads.meta_tax_amount,
            ads.actual_ad_cost,
            CAST(
                ROUND(
                    ads.meta_spend
                    * calculated.allocation_weight,
                    6
                )
                AS DECIMAL(19, 6)
            ) AS pre_allocated_meta_spend,
            CAST(
                ROUND(
                    ads.meta_tax_amount
                    * calculated.allocation_weight,
                    6
                )
                AS DECIMAL(19, 6)
            ) AS pre_allocated_meta_tax,
            ROW_NUMBER() OVER (
                PARTITION BY keys.analysis_date, keys.ad_key
                ORDER BY
                    calculated.allocation_weight DESC,
                    keys.product_key ASC
            ) AS allocation_rank
        INTO #product_ad_preallocated
        FROM #product_ad_keys AS keys
        INNER JOIN mart.ad_economics_daily AS ads
            ON ads.analysis_date = keys.analysis_date
           AND ads.ad_key = keys.ad_key
        LEFT JOIN #product_daily AS products
            ON products.analysis_date = keys.analysis_date
           AND products.ad_key = keys.ad_key
           AND products.product_key = keys.product_key
        LEFT JOIN #ad_allocation_basis AS basis
            ON basis.analysis_date = keys.analysis_date
           AND basis.ad_key = keys.ad_key
        CROSS APPLY (
            SELECT
                CAST(
                    CASE
                        WHEN ads.actual_ad_cost = 0
                        THEN 0
                        WHEN COALESCE(
                            basis.positive_source_revenue,
                            0
                        ) > 0
                        THEN
                            CASE
                                WHEN COALESCE(
                                    products
                                        .allocated_source_product_revenue,
                                    0
                                ) > 0
                                THEN
                                    products
                                        .allocated_source_product_revenue
                                    / basis.positive_source_revenue
                                ELSE 0
                            END
                        WHEN keys.product_key =
                             @unattributed_product_key
                        THEN 1
                        ELSE 0
                    END
                    AS DECIMAL(19, 12)
                ) AS allocation_weight
        ) AS calculated;

        CREATE UNIQUE CLUSTERED INDEX IX_product_ad_preallocated
            ON #product_ad_preallocated (
                analysis_date,
                ad_key,
                product_key
            );

        SELECT
            pre.*,
            SUM(pre.pre_allocated_meta_spend) OVER (
                PARTITION BY pre.analysis_date, pre.ad_key
            ) AS sum_pre_meta_spend,
            SUM(pre.pre_allocated_meta_tax) OVER (
                PARTITION BY pre.analysis_date, pre.ad_key
            ) AS sum_pre_meta_tax
        INTO #product_ad_allocation_totals
        FROM #product_ad_preallocated AS pre;

        CREATE UNIQUE CLUSTERED INDEX
            IX_product_ad_allocation_totals
        ON #product_ad_allocation_totals (
            analysis_date,
            ad_key,
            product_key
        );

        SELECT
            totals.analysis_date,
            totals.ad_key,
            totals.product_key,
            totals.daily_presence_status,
            totals.ad_cost_allocation_method,
            totals.has_meta_insight,
            totals.has_product_orders,
            totals.has_allocated_ad_cost,
            totals.ad_cost_allocation_weight,
            totals.product_order_count,
            totals.item_line_count,
            totals.total_quantity,
            totals.finalized_product_order_count,
            totals.delivered_product_order_count,
            totals.returned_product_order_count,
            totals.canceled_product_order_count,
            totals.returning_product_order_count,
            totals.in_progress_product_order_count,
            totals.product_orders_with_estimated_cost,
            totals.product_orders_with_missing_cost,
            totals.allocated_source_product_revenue,
            totals.projected_total_revenue,
            totals.projected_cogs,
            totals.projected_shipping_cost,
            totals.projected_contribution_before_ads,
            totals.recognized_total_revenue,
            totals.recognized_cogs,
            totals.recognized_shipping_cost,
            totals.recognized_contribution_before_ads,
            allocated.meta_spend AS allocated_meta_spend,
            allocated.meta_tax AS allocated_meta_tax_amount,
            CAST(
                allocated.meta_spend + allocated.meta_tax
                AS DECIMAL(19, 6)
            ) AS allocated_actual_ad_cost,
            CAST(
                totals.projected_contribution_before_ads
                - allocated.meta_spend
                - allocated.meta_tax
                AS DECIMAL(19, 6)
            ) AS projected_contribution_after_ads,
            CAST(
                totals.recognized_contribution_before_ads
                - allocated.meta_spend
                - allocated.meta_tax
                AS DECIMAL(19, 6)
            ) AS recognized_contribution_after_ads
        INTO #source_product_ad_economics_daily
        FROM #product_ad_allocation_totals AS totals
        CROSS APPLY (
            SELECT
                CAST(
                    totals.pre_allocated_meta_spend
                    + CASE
                        WHEN totals.allocation_rank = 1
                        THEN
                            totals.meta_spend
                            - totals.sum_pre_meta_spend
                        ELSE 0
                      END
                    AS DECIMAL(19, 6)
                ) AS meta_spend,
                CAST(
                    totals.pre_allocated_meta_tax
                    + CASE
                        WHEN totals.allocation_rank = 1
                        THEN
                            totals.meta_tax_amount
                            - totals.sum_pre_meta_tax
                        ELSE 0
                      END
                    AS DECIMAL(19, 6)
                ) AS meta_tax
        ) AS allocated;

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_product_ad_economics_daily
        ON #source_product_ad_economics_daily (
            analysis_date,
            ad_key,
            product_key
        );

        IF EXISTS (
            SELECT 1
            FROM (
                SELECT
                    source.analysis_date,
                    source.ad_key,
                    SUM(source.allocated_meta_spend)
                        AS meta_spend,
                    SUM(source.allocated_meta_tax_amount)
                        AS meta_tax,
                    SUM(source.allocated_actual_ad_cost)
                        AS actual_ad_cost,
                    SUM(source.projected_total_revenue)
                        AS projected_revenue,
                    SUM(source.projected_cogs)
                        AS projected_cogs,
                    SUM(source.projected_shipping_cost)
                        AS projected_shipping,
                    SUM(source.projected_contribution_before_ads)
                        AS projected_before_ads,
                    SUM(source.recognized_total_revenue)
                        AS recognized_revenue,
                    SUM(source.recognized_cogs)
                        AS recognized_cogs,
                    SUM(source.recognized_shipping_cost)
                        AS recognized_shipping,
                    SUM(source.recognized_contribution_before_ads)
                        AS recognized_before_ads
                FROM #source_product_ad_economics_daily AS source
                GROUP BY source.analysis_date, source.ad_key
            ) AS product_totals
            INNER JOIN mart.ad_economics_daily AS ads
                ON ads.analysis_date = product_totals.analysis_date
               AND ads.ad_key = product_totals.ad_key
            WHERE ABS(product_totals.meta_spend - ads.meta_spend)
                    > 0.000001
               OR ABS(product_totals.meta_tax - ads.meta_tax_amount)
                    > 0.000001
               OR ABS(
                    product_totals.actual_ad_cost
                    - ads.actual_ad_cost
                  ) > 0.000001
               OR ABS(
                    product_totals.projected_revenue
                    - ads.projected_total_revenue
                  ) > 0.01
               OR ABS(
                    product_totals.projected_cogs
                    - ads.projected_cogs
                  ) > 0.01
               OR ABS(
                    product_totals.projected_shipping
                    - ads.projected_shipping_cost
                  ) > 0.01
               OR ABS(
                    product_totals.projected_before_ads
                    - ads.projected_contribution_before_ads
                  ) > 0.01
               OR ABS(
                    product_totals.recognized_revenue
                    - ads.recognized_total_revenue
                  ) > 0.01
               OR ABS(
                    product_totals.recognized_cogs
                    - ads.recognized_cogs
                  ) > 0.01
               OR ABS(
                    product_totals.recognized_shipping
                    - ads.recognized_shipping_cost
                  ) > 0.01
               OR ABS(
                    product_totals.recognized_before_ads
                    - ads.recognized_contribution_before_ads
                  ) > 0.01
        )
        BEGIN
            THROW 51405,
                'Product-Ad allocations do not reconcile to Ad Economics.',
                1;
        END;

        SELECT
            source.analysis_date,
            source.ad_key,
            source.product_key
        INTO #changed_product_ad_economics
        FROM #source_product_ad_economics_daily AS source
        LEFT JOIN mart.product_ad_economics_daily AS target
            ON target.analysis_date = source.analysis_date
           AND target.ad_key = source.ad_key
           AND target.product_key = source.product_key
        WHERE target.product_key IS NULL
           OR EXISTS (
                SELECT
                    source.daily_presence_status,
                    source.ad_cost_allocation_method,
                    source.has_meta_insight,
                    source.has_product_orders,
                    source.has_allocated_ad_cost,
                    source.ad_cost_allocation_weight,
                    source.product_order_count,
                    source.item_line_count,
                    source.total_quantity,
                    source.finalized_product_order_count,
                    source.delivered_product_order_count,
                    source.returned_product_order_count,
                    source.canceled_product_order_count,
                    source.returning_product_order_count,
                    source.in_progress_product_order_count,
                    source.product_orders_with_estimated_cost,
                    source.product_orders_with_missing_cost,
                    source.allocated_source_product_revenue,
                    source.projected_total_revenue,
                    source.projected_cogs,
                    source.projected_shipping_cost,
                    source.projected_contribution_before_ads,
                    source.recognized_total_revenue,
                    source.recognized_cogs,
                    source.recognized_shipping_cost,
                    source.recognized_contribution_before_ads,
                    source.allocated_meta_spend,
                    source.allocated_meta_tax_amount,
                    source.allocated_actual_ad_cost,
                    source.projected_contribution_after_ads,
                    source.recognized_contribution_after_ads

                EXCEPT

                SELECT
                    target.daily_presence_status,
                    target.ad_cost_allocation_method,
                    target.has_meta_insight,
                    target.has_product_orders,
                    target.has_allocated_ad_cost,
                    target.ad_cost_allocation_weight,
                    target.product_order_count,
                    target.item_line_count,
                    target.total_quantity,
                    target.finalized_product_order_count,
                    target.delivered_product_order_count,
                    target.returned_product_order_count,
                    target.canceled_product_order_count,
                    target.returning_product_order_count,
                    target.in_progress_product_order_count,
                    target.product_orders_with_estimated_cost,
                    target.product_orders_with_missing_cost,
                    target.allocated_source_product_revenue,
                    target.projected_total_revenue,
                    target.projected_cogs,
                    target.projected_shipping_cost,
                    target.projected_contribution_before_ads,
                    target.recognized_total_revenue,
                    target.recognized_cogs,
                    target.recognized_shipping_cost,
                    target.recognized_contribution_before_ads,
                    target.allocated_meta_spend,
                    target.allocated_meta_tax_amount,
                    target.allocated_actual_ad_cost,
                    target.projected_contribution_after_ads,
                    target.recognized_contribution_after_ads
           );

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_product_ad_economics
        ON #changed_product_ad_economics (
            analysis_date,
            ad_key,
            product_key
        );

        DECLARE @inserted_row_count INT = (
            SELECT COUNT(*)
            FROM #source_product_ad_economics_daily AS source
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.product_ad_economics_daily AS target
                WHERE target.analysis_date = source.analysis_date
                  AND target.ad_key = source.ad_key
                  AND target.product_key = source.product_key
            )
        );

        DECLARE @updated_row_count INT = (
            SELECT COUNT(*)
            FROM #changed_product_ad_economics AS changed
            WHERE EXISTS (
                SELECT 1
                FROM mart.product_ad_economics_daily AS target
                WHERE target.analysis_date = changed.analysis_date
                  AND target.ad_key = changed.ad_key
                  AND target.product_key = changed.product_key
            )
        );

        DECLARE @deleted_row_count INT = (
            SELECT COUNT(*)
            FROM mart.product_ad_economics_daily AS target
            WHERE NOT EXISTS (
                SELECT 1
                FROM #source_product_ad_economics_daily AS source
                WHERE source.analysis_date = target.analysis_date
                  AND source.ad_key = target.ad_key
                  AND source.product_key = target.product_key
            )
        );

        DELETE target
        FROM mart.product_ad_economics_daily AS target
        WHERE NOT EXISTS (
            SELECT 1
            FROM #source_product_ad_economics_daily AS source
            WHERE source.analysis_date = target.analysis_date
              AND source.ad_key = target.ad_key
              AND source.product_key = target.product_key
        );

        UPDATE target
        SET
            daily_presence_status = source.daily_presence_status,
            ad_cost_allocation_method =
                source.ad_cost_allocation_method,
            has_meta_insight = source.has_meta_insight,
            has_product_orders = source.has_product_orders,
            has_allocated_ad_cost = source.has_allocated_ad_cost,
            ad_cost_allocation_weight =
                source.ad_cost_allocation_weight,
            product_order_count = source.product_order_count,
            item_line_count = source.item_line_count,
            total_quantity = source.total_quantity,
            finalized_product_order_count =
                source.finalized_product_order_count,
            delivered_product_order_count =
                source.delivered_product_order_count,
            returned_product_order_count =
                source.returned_product_order_count,
            canceled_product_order_count =
                source.canceled_product_order_count,
            returning_product_order_count =
                source.returning_product_order_count,
            in_progress_product_order_count =
                source.in_progress_product_order_count,
            product_orders_with_estimated_cost =
                source.product_orders_with_estimated_cost,
            product_orders_with_missing_cost =
                source.product_orders_with_missing_cost,
            allocated_source_product_revenue =
                source.allocated_source_product_revenue,
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
            allocated_meta_spend = source.allocated_meta_spend,
            allocated_meta_tax_amount =
                source.allocated_meta_tax_amount,
            allocated_actual_ad_cost =
                source.allocated_actual_ad_cost,
            projected_contribution_after_ads =
                source.projected_contribution_after_ads,
            recognized_contribution_after_ads =
                source.recognized_contribution_after_ads,
            mart_refreshed_at_utc = SYSUTCDATETIME()
        FROM mart.product_ad_economics_daily AS target
        INNER JOIN #source_product_ad_economics_daily AS source
            ON source.analysis_date = target.analysis_date
           AND source.ad_key = target.ad_key
           AND source.product_key = target.product_key
        INNER JOIN #changed_product_ad_economics AS changed
            ON changed.analysis_date = source.analysis_date
           AND changed.ad_key = source.ad_key
           AND changed.product_key = source.product_key;

        INSERT INTO mart.product_ad_economics_daily (
            analysis_date,
            ad_key,
            product_key,
            daily_presence_status,
            ad_cost_allocation_method,
            has_meta_insight,
            has_product_orders,
            has_allocated_ad_cost,
            ad_cost_allocation_weight,
            product_order_count,
            item_line_count,
            total_quantity,
            finalized_product_order_count,
            delivered_product_order_count,
            returned_product_order_count,
            canceled_product_order_count,
            returning_product_order_count,
            in_progress_product_order_count,
            product_orders_with_estimated_cost,
            product_orders_with_missing_cost,
            allocated_source_product_revenue,
            projected_total_revenue,
            projected_cogs,
            projected_shipping_cost,
            projected_contribution_before_ads,
            recognized_total_revenue,
            recognized_cogs,
            recognized_shipping_cost,
            recognized_contribution_before_ads,
            allocated_meta_spend,
            allocated_meta_tax_amount,
            allocated_actual_ad_cost,
            projected_contribution_after_ads,
            recognized_contribution_after_ads
        )
        SELECT
            source.analysis_date,
            source.ad_key,
            source.product_key,
            source.daily_presence_status,
            source.ad_cost_allocation_method,
            source.has_meta_insight,
            source.has_product_orders,
            source.has_allocated_ad_cost,
            source.ad_cost_allocation_weight,
            source.product_order_count,
            source.item_line_count,
            source.total_quantity,
            source.finalized_product_order_count,
            source.delivered_product_order_count,
            source.returned_product_order_count,
            source.canceled_product_order_count,
            source.returning_product_order_count,
            source.in_progress_product_order_count,
            source.product_orders_with_estimated_cost,
            source.product_orders_with_missing_cost,
            source.allocated_source_product_revenue,
            source.projected_total_revenue,
            source.projected_cogs,
            source.projected_shipping_cost,
            source.projected_contribution_before_ads,
            source.recognized_total_revenue,
            source.recognized_cogs,
            source.recognized_shipping_cost,
            source.recognized_contribution_before_ads,
            source.allocated_meta_spend,
            source.allocated_meta_tax_amount,
            source.allocated_actual_ad_cost,
            source.projected_contribution_after_ads,
            source.recognized_contribution_after_ads
        FROM #source_product_ad_economics_daily AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM mart.product_ad_economics_daily AS target
            WHERE target.analysis_date = source.analysis_date
              AND target.ad_key = source.ad_key
              AND target.product_key = source.product_key
        );

        COMMIT TRANSACTION;

        SELECT
            @inserted_row_count AS inserted_rows,
            @updated_row_count AS updated_rows,
            @deleted_row_count AS deleted_rows,
            COUNT(*) AS fact_rows,
            SUM(
                CASE
                    WHEN daily_presence_status =
                         'META_AND_PRODUCT_ORDER'
                    THEN 1 ELSE 0
                END
            ) AS meta_and_product_rows,
            SUM(
                CASE
                    WHEN daily_presence_status =
                         'META_ONLY_UNATTRIBUTED'
                    THEN 1 ELSE 0
                END
            ) AS meta_only_unattributed_rows,
            SUM(
                CASE
                    WHEN daily_presence_status =
                         'ORDER_ONLY_PRODUCT'
                    THEN 1 ELSE 0
                END
            ) AS order_only_product_rows,
            CAST(SUM(allocated_actual_ad_cost) AS DECIMAL(19, 2))
                AS allocated_actual_ad_cost,
            CAST(
                SUM(projected_contribution_after_ads)
                AS DECIMAL(19, 2)
            ) AS projected_contribution_after_ads,
            CAST(
                SUM(recognized_contribution_after_ads)
                AS DECIMAL(19, 2)
            ) AS recognized_contribution_after_ads
        FROM mart.product_ad_economics_daily;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
