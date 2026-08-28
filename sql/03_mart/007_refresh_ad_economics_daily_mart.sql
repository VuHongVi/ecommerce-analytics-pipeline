CREATE OR ALTER PROCEDURE mart.refresh_ad_economics_daily
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID(
            N'mart.ad_economics_daily',
            N'U'
        ) IS NULL
        BEGIN
            THROW 51101,
                'mart.ad_economics_daily does not exist.',
                1;
        END;

        IF OBJECT_ID(
            N'ref.meta_ad_tax_rules',
            N'U'
        ) IS NULL
        BEGIN
            THROW 51102,
                'ref.meta_ad_tax_rules does not exist.',
                1;
        END;

        IF EXISTS (
            SELECT 1
            FROM mart.order_economics AS orders
            WHERE orders.order_date IS NULL
        )
        BEGIN
            THROW 51103,
                'Order Economics contains a null order date.',
                1;
        END;

        IF EXISTS (
            SELECT 1
            FROM mart.order_economics AS orders
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.dim_meta_ads AS dimension
                WHERE dimension.ad_id =
                    COALESCE(
                        NULLIF(
                            LTRIM(RTRIM(orders.ad_id)),
                            N''
                        ),
                        N'__UNATTRIBUTED__'
                    )
            )
        )
        BEGIN
            THROW 51104,
                'An order cannot be mapped to dim_meta_ads.',
                1;
        END;

        /*
         * Meta source giữ grain ngày + ad.
         * Derived ratios như CPM/CPC/CTR không được cộng dồn;
         * chúng sẽ được tính lại trong BI từ additive metrics.
         */
        SELECT
            insights.date_start AS analysis_date,
            dimension.ad_key,
            insights.source_raw_insight_version_id,
            insights.source_extracted_at_utc,
            dimension.currency,
            tax_rule.tax_rate,
            COALESCE(insights.impressions, 0)
                AS impressions,
            COALESCE(insights.reach, 0)
                AS reach,
            COALESCE(insights.clicks, 0)
                AS clicks,
            COALESCE(insights.inline_link_clicks, 0)
                AS inline_link_clicks,
            CAST(
                COALESCE(insights.spend, 0)
                AS DECIMAL(19, 6)
            ) AS meta_spend
        INTO #meta_daily
        FROM stg.meta_ad_insights AS insights
        INNER JOIN mart.dim_meta_ads AS dimension
            ON dimension.ad_id = insights.ad_id
        OUTER APPLY (
            SELECT TOP (1)
                rules.tax_rate
            FROM ref.meta_ad_tax_rules AS rules
            WHERE rules.currency = dimension.currency
              AND rules.valid_from <= insights.date_start
              AND (
                    rules.valid_to IS NULL
                    OR insights.date_start < rules.valid_to
              )
            ORDER BY rules.valid_from DESC
        ) AS tax_rule;

        IF EXISTS (
            SELECT 1
            FROM #meta_daily
            WHERE tax_rate IS NULL
        )
        BEGIN
            THROW 51105,
                'A Meta insight has no effective tax rule.',
                1;
        END;

        CREATE UNIQUE CLUSTERED INDEX
            IX_meta_daily
        ON #meta_daily (
            analysis_date,
            ad_key
        );

        /*
         * Order Economics được tổng hợp trước khi nối với
         * Meta để chi phí quảng cáo không bị nhân theo số đơn.
         */
        SELECT
            orders.order_date AS analysis_date,
            dimension.ad_key,
            COUNT(*) AS order_count,

            SUM(
                CASE
                    WHEN orders.is_finalized = 1
                    THEN 1
                    ELSE 0
                END
            ) AS finalized_order_count,

            SUM(
                CASE
                    WHEN orders.economic_status =
                         'FINAL_DELIVERED'
                    THEN 1
                    ELSE 0
                END
            ) AS delivered_order_count,

            SUM(
                CASE
                    WHEN orders.economic_status =
                         'FINAL_RETURNED'
                    THEN 1
                    ELSE 0
                END
            ) AS returned_order_count,

            SUM(
                CASE
                    WHEN orders.economic_status =
                         'FINAL_CANCELED'
                    THEN 1
                    ELSE 0
                END
            ) AS canceled_order_count,

            SUM(
                CASE
                    WHEN orders.economic_status =
                         'PROVISIONAL_RETURNING'
                    THEN 1
                    ELSE 0
                END
            ) AS returning_order_count,

            SUM(
                CASE
                    WHEN orders.economic_status =
                         'IN_PROGRESS'
                    THEN 1
                    ELSE 0
                END
            ) AS in_progress_order_count,

            CAST(
                SUM(COALESCE(orders.total_quantity, 0))
                AS BIGINT
            ) AS total_quantity,

            SUM(
                CASE
                    WHEN orders.has_estimated_cost = 1
                    THEN 1
                    ELSE 0
                END
            ) AS orders_with_estimated_cost,

            SUM(
                CASE
                    WHEN orders.has_missing_cost = 1
                    THEN 1
                    ELSE 0
                END
            ) AS orders_with_missing_cost,

            CAST(
                SUM(
                    COALESCE(
                        orders.projected_total_revenue,
                        0
                    )
                )
                AS DECIMAL(19, 2)
            ) AS projected_total_revenue,

            CAST(
                SUM(COALESCE(orders.projected_cogs, 0))
                AS DECIMAL(19, 2)
            ) AS projected_cogs,

            CAST(
                SUM(
                    COALESCE(
                        orders.projected_shipping_cost,
                        0
                    )
                )
                AS DECIMAL(19, 2)
            ) AS projected_shipping_cost,

            CAST(
                SUM(
                    COALESCE(
                        orders.projected_contribution_profit,
                        0
                    )
                )
                AS DECIMAL(19, 2)
            ) AS projected_contribution_before_ads,

            CAST(
                SUM(
                    COALESCE(
                        orders.recognized_total_revenue,
                        0
                    )
                )
                AS DECIMAL(19, 2)
            ) AS recognized_total_revenue,

            CAST(
                SUM(COALESCE(orders.recognized_cogs, 0))
                AS DECIMAL(19, 2)
            ) AS recognized_cogs,

            CAST(
                SUM(
                    COALESCE(
                        orders.recognized_shipping_cost,
                        0
                    )
                )
                AS DECIMAL(19, 2)
            ) AS recognized_shipping_cost,

            CAST(
                SUM(
                    COALESCE(
                        orders.recognized_contribution_profit,
                        0
                    )
                )
                AS DECIMAL(19, 2)
            ) AS recognized_contribution_before_ads

        INTO #order_daily
        FROM mart.order_economics AS orders
        INNER JOIN mart.dim_meta_ads AS dimension
            ON dimension.ad_id =
               COALESCE(
                    NULLIF(
                        LTRIM(RTRIM(orders.ad_id)),
                        N''
                    ),
                    N'__UNATTRIBUTED__'
               )
        GROUP BY
            orders.order_date,
            dimension.ad_key;

        CREATE UNIQUE CLUSTERED INDEX
            IX_order_daily
        ON #order_daily (
            analysis_date,
            ad_key
        );

        SELECT
            source.analysis_date,
            source.ad_key
        INTO #daily_keys
        FROM (
            SELECT
                analysis_date,
                ad_key
            FROM #meta_daily

            UNION

            SELECT
                analysis_date,
                ad_key
            FROM #order_daily
        ) AS source;

        CREATE UNIQUE CLUSTERED INDEX
            IX_daily_keys
        ON #daily_keys (
            analysis_date,
            ad_key
        );

        SELECT
            keys.analysis_date,
            keys.ad_key,

            CAST(
                CASE
                    WHEN meta.ad_key IS NOT NULL
                     AND orders.ad_key IS NOT NULL
                    THEN 'META_AND_ORDER'

                    WHEN meta.ad_key IS NOT NULL
                    THEN 'META_ONLY'

                    ELSE 'ORDER_ONLY'
                END
                AS VARCHAR(30)
            ) AS daily_presence_status,

            CAST(
                CASE
                    WHEN meta.ad_key IS NOT NULL
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS has_meta_insight,

            CAST(
                CASE
                    WHEN orders.ad_key IS NOT NULL
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS has_orders,

            meta.source_raw_insight_version_id,
            meta.source_extracted_at_utc
                AS source_meta_extracted_at_utc,
            meta.currency,

            CAST(
                COALESCE(meta.tax_rate, 0)
                AS DECIMAL(9, 6)
            ) AS tax_rate,

            COALESCE(meta.impressions, 0)
                AS impressions,
            COALESCE(meta.reach, 0)
                AS reach,
            COALESCE(meta.clicks, 0)
                AS clicks,
            COALESCE(meta.inline_link_clicks, 0)
                AS inline_link_clicks,

            costs.meta_spend,
            costs.meta_tax_amount,
            costs.actual_ad_cost,

            COALESCE(orders.order_count, 0)
                AS order_count,
            COALESCE(orders.finalized_order_count, 0)
                AS finalized_order_count,
            COALESCE(orders.delivered_order_count, 0)
                AS delivered_order_count,
            COALESCE(orders.returned_order_count, 0)
                AS returned_order_count,
            COALESCE(orders.canceled_order_count, 0)
                AS canceled_order_count,
            COALESCE(orders.returning_order_count, 0)
                AS returning_order_count,
            COALESCE(orders.in_progress_order_count, 0)
                AS in_progress_order_count,
            COALESCE(orders.total_quantity, 0)
                AS total_quantity,
            COALESCE(orders.orders_with_estimated_cost, 0)
                AS orders_with_estimated_cost,
            COALESCE(orders.orders_with_missing_cost, 0)
                AS orders_with_missing_cost,

            CAST(
                COALESCE(
                    orders.projected_total_revenue,
                    0
                )
                AS DECIMAL(19, 2)
            ) AS projected_total_revenue,

            CAST(
                COALESCE(orders.projected_cogs, 0)
                AS DECIMAL(19, 2)
            ) AS projected_cogs,

            CAST(
                COALESCE(
                    orders.projected_shipping_cost,
                    0
                )
                AS DECIMAL(19, 2)
            ) AS projected_shipping_cost,

            CAST(
                COALESCE(
                    orders.projected_contribution_before_ads,
                    0
                )
                AS DECIMAL(19, 2)
            ) AS projected_contribution_before_ads,

            CAST(
                COALESCE(
                    orders.projected_contribution_before_ads,
                    0
                ) - costs.actual_ad_cost
                AS DECIMAL(19, 6)
            ) AS projected_contribution_after_ads,

            CAST(
                COALESCE(
                    orders.recognized_total_revenue,
                    0
                )
                AS DECIMAL(19, 2)
            ) AS recognized_total_revenue,

            CAST(
                COALESCE(orders.recognized_cogs, 0)
                AS DECIMAL(19, 2)
            ) AS recognized_cogs,

            CAST(
                COALESCE(
                    orders.recognized_shipping_cost,
                    0
                )
                AS DECIMAL(19, 2)
            ) AS recognized_shipping_cost,

            CAST(
                COALESCE(
                    orders.recognized_contribution_before_ads,
                    0
                )
                AS DECIMAL(19, 2)
            ) AS recognized_contribution_before_ads,

            CAST(
                COALESCE(
                    orders.recognized_contribution_before_ads,
                    0
                ) - costs.actual_ad_cost
                AS DECIMAL(19, 6)
            ) AS recognized_contribution_after_ads

        INTO #source_ad_economics_daily
        FROM #daily_keys AS keys
        LEFT JOIN #meta_daily AS meta
            ON meta.analysis_date = keys.analysis_date
           AND meta.ad_key = keys.ad_key
        LEFT JOIN #order_daily AS orders
            ON orders.analysis_date = keys.analysis_date
           AND orders.ad_key = keys.ad_key
        CROSS APPLY (
            SELECT
                CAST(
                    COALESCE(meta.meta_spend, 0)
                    AS DECIMAL(19, 6)
                ) AS meta_spend,

                CAST(
                    COALESCE(meta.meta_spend, 0)
                    * COALESCE(meta.tax_rate, 0)
                    AS DECIMAL(19, 6)
                ) AS meta_tax_amount
        ) AS calculated_tax
        CROSS APPLY (
            SELECT
                calculated_tax.meta_spend,
                calculated_tax.meta_tax_amount,

                CAST(
                    calculated_tax.meta_spend
                    + calculated_tax.meta_tax_amount
                    AS DECIMAL(19, 6)
                ) AS actual_ad_cost
        ) AS costs;

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_ad_economics_daily
        ON #source_ad_economics_daily (
            analysis_date,
            ad_key
        );

        SELECT
            source.analysis_date,
            source.ad_key
        INTO #changed_ad_economics_daily
        FROM #source_ad_economics_daily AS source
        LEFT JOIN mart.ad_economics_daily AS target
            ON target.analysis_date = source.analysis_date
           AND target.ad_key = source.ad_key
        WHERE target.ad_key IS NULL
           OR EXISTS (
                SELECT
                    source.daily_presence_status,
                    source.has_meta_insight,
                    source.has_orders,
                    source.source_raw_insight_version_id,
                    source.source_meta_extracted_at_utc,
                    source.currency,
                    source.tax_rate,
                    source.impressions,
                    source.reach,
                    source.clicks,
                    source.inline_link_clicks,
                    source.meta_spend,
                    source.meta_tax_amount,
                    source.actual_ad_cost,
                    source.order_count,
                    source.finalized_order_count,
                    source.delivered_order_count,
                    source.returned_order_count,
                    source.canceled_order_count,
                    source.returning_order_count,
                    source.in_progress_order_count,
                    source.total_quantity,
                    source.orders_with_estimated_cost,
                    source.orders_with_missing_cost,
                    source.projected_total_revenue,
                    source.projected_cogs,
                    source.projected_shipping_cost,
                    source.projected_contribution_before_ads,
                    source.projected_contribution_after_ads,
                    source.recognized_total_revenue,
                    source.recognized_cogs,
                    source.recognized_shipping_cost,
                    source.recognized_contribution_before_ads,
                    source.recognized_contribution_after_ads

                EXCEPT

                SELECT
                    target.daily_presence_status,
                    target.has_meta_insight,
                    target.has_orders,
                    target.source_raw_insight_version_id,
                    target.source_meta_extracted_at_utc,
                    target.currency,
                    target.tax_rate,
                    target.impressions,
                    target.reach,
                    target.clicks,
                    target.inline_link_clicks,
                    target.meta_spend,
                    target.meta_tax_amount,
                    target.actual_ad_cost,
                    target.order_count,
                    target.finalized_order_count,
                    target.delivered_order_count,
                    target.returned_order_count,
                    target.canceled_order_count,
                    target.returning_order_count,
                    target.in_progress_order_count,
                    target.total_quantity,
                    target.orders_with_estimated_cost,
                    target.orders_with_missing_cost,
                    target.projected_total_revenue,
                    target.projected_cogs,
                    target.projected_shipping_cost,
                    target.projected_contribution_before_ads,
                    target.projected_contribution_after_ads,
                    target.recognized_total_revenue,
                    target.recognized_cogs,
                    target.recognized_shipping_cost,
                    target.recognized_contribution_before_ads,
                    target.recognized_contribution_after_ads
           );

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_ad_economics_daily
        ON #changed_ad_economics_daily (
            analysis_date,
            ad_key
        );

        DECLARE @inserted_row_count INT = (
            SELECT COUNT(*)
            FROM #source_ad_economics_daily AS source
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.ad_economics_daily AS target
                WHERE target.analysis_date =
                      source.analysis_date
                  AND target.ad_key = source.ad_key
            )
        );

        DECLARE @updated_row_count INT = (
            SELECT COUNT(*)
            FROM #changed_ad_economics_daily AS changed
            WHERE EXISTS (
                SELECT 1
                FROM mart.ad_economics_daily AS target
                WHERE target.analysis_date =
                      changed.analysis_date
                  AND target.ad_key = changed.ad_key
            )
        );

        DECLARE @deleted_row_count INT = (
            SELECT COUNT(*)
            FROM mart.ad_economics_daily AS target
            WHERE NOT EXISTS (
                SELECT 1
                FROM #source_ad_economics_daily AS source
                WHERE source.analysis_date =
                      target.analysis_date
                  AND source.ad_key = target.ad_key
            )
        );

        DELETE target
        FROM mart.ad_economics_daily AS target
        WHERE NOT EXISTS (
            SELECT 1
            FROM #source_ad_economics_daily AS source
            WHERE source.analysis_date =
                  target.analysis_date
              AND source.ad_key = target.ad_key
        );

        UPDATE target
        SET
            daily_presence_status =
                source.daily_presence_status,
            has_meta_insight = source.has_meta_insight,
            has_orders = source.has_orders,
            source_raw_insight_version_id =
                source.source_raw_insight_version_id,
            source_meta_extracted_at_utc =
                source.source_meta_extracted_at_utc,
            currency = source.currency,
            tax_rate = source.tax_rate,
            impressions = source.impressions,
            reach = source.reach,
            clicks = source.clicks,
            inline_link_clicks =
                source.inline_link_clicks,
            meta_spend = source.meta_spend,
            meta_tax_amount = source.meta_tax_amount,
            actual_ad_cost = source.actual_ad_cost,
            order_count = source.order_count,
            finalized_order_count =
                source.finalized_order_count,
            delivered_order_count =
                source.delivered_order_count,
            returned_order_count =
                source.returned_order_count,
            canceled_order_count =
                source.canceled_order_count,
            returning_order_count =
                source.returning_order_count,
            in_progress_order_count =
                source.in_progress_order_count,
            total_quantity = source.total_quantity,
            orders_with_estimated_cost =
                source.orders_with_estimated_cost,
            orders_with_missing_cost =
                source.orders_with_missing_cost,
            projected_total_revenue =
                source.projected_total_revenue,
            projected_cogs = source.projected_cogs,
            projected_shipping_cost =
                source.projected_shipping_cost,
            projected_contribution_before_ads =
                source.projected_contribution_before_ads,
            projected_contribution_after_ads =
                source.projected_contribution_after_ads,
            recognized_total_revenue =
                source.recognized_total_revenue,
            recognized_cogs = source.recognized_cogs,
            recognized_shipping_cost =
                source.recognized_shipping_cost,
            recognized_contribution_before_ads =
                source.recognized_contribution_before_ads,
            recognized_contribution_after_ads =
                source.recognized_contribution_after_ads,
            mart_refreshed_at_utc = SYSUTCDATETIME()
        FROM mart.ad_economics_daily AS target
        INNER JOIN #source_ad_economics_daily AS source
            ON source.analysis_date = target.analysis_date
           AND source.ad_key = target.ad_key
        INNER JOIN #changed_ad_economics_daily AS changed
            ON changed.analysis_date = source.analysis_date
           AND changed.ad_key = source.ad_key;

        INSERT INTO mart.ad_economics_daily (
            analysis_date,
            ad_key,
            daily_presence_status,
            has_meta_insight,
            has_orders,
            source_raw_insight_version_id,
            source_meta_extracted_at_utc,
            currency,
            tax_rate,
            impressions,
            reach,
            clicks,
            inline_link_clicks,
            meta_spend,
            meta_tax_amount,
            actual_ad_cost,
            order_count,
            finalized_order_count,
            delivered_order_count,
            returned_order_count,
            canceled_order_count,
            returning_order_count,
            in_progress_order_count,
            total_quantity,
            orders_with_estimated_cost,
            orders_with_missing_cost,
            projected_total_revenue,
            projected_cogs,
            projected_shipping_cost,
            projected_contribution_before_ads,
            projected_contribution_after_ads,
            recognized_total_revenue,
            recognized_cogs,
            recognized_shipping_cost,
            recognized_contribution_before_ads,
            recognized_contribution_after_ads
        )
        SELECT
            source.analysis_date,
            source.ad_key,
            source.daily_presence_status,
            source.has_meta_insight,
            source.has_orders,
            source.source_raw_insight_version_id,
            source.source_meta_extracted_at_utc,
            source.currency,
            source.tax_rate,
            source.impressions,
            source.reach,
            source.clicks,
            source.inline_link_clicks,
            source.meta_spend,
            source.meta_tax_amount,
            source.actual_ad_cost,
            source.order_count,
            source.finalized_order_count,
            source.delivered_order_count,
            source.returned_order_count,
            source.canceled_order_count,
            source.returning_order_count,
            source.in_progress_order_count,
            source.total_quantity,
            source.orders_with_estimated_cost,
            source.orders_with_missing_cost,
            source.projected_total_revenue,
            source.projected_cogs,
            source.projected_shipping_cost,
            source.projected_contribution_before_ads,
            source.projected_contribution_after_ads,
            source.recognized_total_revenue,
            source.recognized_cogs,
            source.recognized_shipping_cost,
            source.recognized_contribution_before_ads,
            source.recognized_contribution_after_ads
        FROM #source_ad_economics_daily AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM mart.ad_economics_daily AS target
            WHERE target.analysis_date =
                  source.analysis_date
              AND target.ad_key = source.ad_key
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
                         'META_AND_ORDER'
                    THEN 1
                    ELSE 0
                END
            ) AS meta_and_order_rows,

            SUM(
                CASE
                    WHEN daily_presence_status =
                         'META_ONLY'
                    THEN 1
                    ELSE 0
                END
            ) AS meta_only_rows,

            SUM(
                CASE
                    WHEN daily_presence_status =
                         'ORDER_ONLY'
                    THEN 1
                    ELSE 0
                END
            ) AS order_only_rows,

            CAST(
                SUM(meta_spend)
                AS DECIMAL(19, 2)
            ) AS meta_spend,

            CAST(
                SUM(meta_tax_amount)
                AS DECIMAL(19, 2)
            ) AS meta_tax_amount,

            CAST(
                SUM(actual_ad_cost)
                AS DECIMAL(19, 2)
            ) AS actual_ad_cost,

            CAST(
                SUM(projected_contribution_after_ads)
                AS DECIMAL(19, 2)
            ) AS projected_contribution_after_ads,

            CAST(
                SUM(recognized_contribution_after_ads)
                AS DECIMAL(19, 2)
            ) AS recognized_contribution_after_ads

        FROM mart.ad_economics_daily;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
