CREATE OR ALTER PROCEDURE mart.refresh_order_economics
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        /*
         * Tổng hợp giá vốn từ grain order item
         * lên grain order.
         *
         * line_product_cost đã bằng:
         * quantity * resolved_unit_cost
         *
         * Không nhân quantity thêm lần nữa.
         */
        SELECT
            costs.shop_id,
            costs.order_id,
            COUNT(*) AS item_line_count,
            SUM(costs.quantity) AS total_quantity,

            SUM(
                CASE
                    WHEN costs.source_raw_product_cost_history_id
                         IS NOT NULL
                    THEN 1
                    ELSE 0
                END
            ) AS history_cost_line_count,

            SUM(
                CASE
                    WHEN costs.source_raw_product_cost_master_id
                         IS NOT NULL
                    THEN 1
                    ELSE 0
                END
            ) AS fallback_cost_line_count,

            SUM(
                CASE
                    WHEN costs.is_estimated = 1
                    THEN 1
                    ELSE 0
                END
            ) AS estimated_cost_line_count,

            SUM(
                CASE
                    WHEN costs.line_product_cost IS NULL
                    THEN 1
                    ELSE 0
                END
            ) AS missing_cost_line_count,

            CAST(
                SUM(
                    COALESCE(
                        costs.line_product_cost,
                        0
                    )
                )
                AS DECIMAL(19, 2)
            ) AS resolved_product_cost
        INTO #item_cost_summary
        FROM stg.pancake_order_item_costs AS costs
        GROUP BY
            costs.shop_id,
            costs.order_id;

        CREATE UNIQUE CLUSTERED INDEX
            IX_item_cost_summary
        ON #item_cost_summary (
            shop_id,
            order_id
        );

        /*
         * Chuẩn hóa trạng thái kinh tế của đơn hàng.
         */
        SELECT
            orders.shop_id,
            orders.order_id,

            orders.source_raw_order_version_id,
            orders.source_inserted_at,
            orders.source_updated_at,
            CAST(
                orders.source_inserted_at AS DATE
            ) AS order_date,

            orders.source_status,
            orders.status_name,
            economics.economic_status,
            CAST(
                CASE
                    WHEN economics.economic_status IN (
                        'FINAL_DELIVERED',
                        'FINAL_RETURNED',
                        'FINAL_CANCELED'
                    )
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS is_finalized,

            orders.is_cancelled,
            orders.is_delivered,
            orders.is_returning,
            orders.is_returned,

            orders.page_id,
            orders.page_name,
            orders.ad_id,
            orders.post_id,
            orders.ads_source,
            orders.order_source_name,

            orders.utm_campaign,
            orders.utm_content,
            orders.utm_id,
            orders.utm_medium,
            orders.utm_source,
            orders.utm_term,

            orders.shipping_partner_name,

            COALESCE(
                item_costs.item_line_count,
                0
            ) AS item_line_count,

            COALESCE(
                item_costs.total_quantity,
                0
            ) AS total_quantity,

            COALESCE(
                item_costs.history_cost_line_count,
                0
            ) AS history_cost_line_count,

            COALESCE(
                item_costs.fallback_cost_line_count,
                0
            ) AS fallback_cost_line_count,

            COALESCE(
                item_costs.estimated_cost_line_count,
                0
            ) AS estimated_cost_line_count,

            COALESCE(
                item_costs.missing_cost_line_count,
                0
            ) AS missing_cost_line_count,

            CAST(
                CASE
                    WHEN COALESCE(
                        item_costs.estimated_cost_line_count,
                        0
                    ) > 0
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS has_estimated_cost,

            CAST(
                CASE
                    WHEN COALESCE(
                        item_costs.missing_cost_line_count,
                        0
                    ) > 0
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS has_missing_cost,

            orders.total_price
                AS source_total_price,

            orders.total_price_after_discount
                AS source_total_price_after_discount,

            orders.buyer_total_amount
                AS source_buyer_total_amount,

            orders.customer_shipping_fee
                AS source_customer_shipping_fee,

            orders.partner_fee
                AS source_partner_fee,

            orders.partner_total_fee
                AS source_partner_total_fee,

            orders.surcharge
                AS source_surcharge,

            orders.advanced_platform_fee
                AS source_advanced_platform_fee,

            orders.marketplace_fee
                AS source_marketplace_fee,

            orders.customer_pay_fee
                AS source_customer_pay_fee,

            CAST(
                COALESCE(
                    item_costs.resolved_product_cost,
                    0
                )
                AS DECIMAL(19, 2)
            ) AS resolved_product_cost,

            /*
             * Phí ship cơ sở:
             * 1. Ưu tiên partner.total_fee khi lớn hơn 0.
             * 2. Fallback sang partner_fee.
             * 3. Đơn hủy luôn bằng 0.
             */
            CAST(
                CASE
                    WHEN economics.economic_status =
                         'FINAL_CANCELED'
                    THEN 0
                    ELSE
                        CASE
                            WHEN COALESCE(
                                orders.partner_total_fee,
                                0
                            ) > 0
                            THEN orders.partner_total_fee
                            ELSE COALESCE(
                                orders.partner_fee,
                                0
                            )
                        END
                END
                AS DECIMAL(19, 2)
            ) AS base_shipping_cost,

            /*
             * Phụ phí hoàn được lấy từ bảng quy tắc
             * có ngày hiệu lực.
             */
            CAST(
                CASE
                    WHEN economics.economic_status IN (
                        'PROVISIONAL_RETURNING',
                        'FINAL_RETURNED'
                    )
                    THEN COALESCE(
                        return_fee.return_surcharge,
                        0
                    )
                    ELSE 0
                END
                AS DECIMAL(19, 2)
            ) AS applied_return_surcharge
        INTO #order_economics_base
        FROM stg.pancake_orders AS orders
        LEFT JOIN #item_cost_summary AS item_costs
            ON item_costs.shop_id = orders.shop_id
           AND item_costs.order_id = orders.order_id
        CROSS APPLY (
            SELECT
                CAST(
                    CASE
                        WHEN orders.is_cancelled = 1
                          OR orders.source_status = 6
                        THEN 'FINAL_CANCELED'

                        WHEN orders.is_returned = 1
                          OR orders.source_status = 5
                        THEN 'FINAL_RETURNED'

                        WHEN orders.is_returning = 1
                          OR orders.source_status = 4
                        THEN 'PROVISIONAL_RETURNING'

                        WHEN orders.is_delivered = 1
                          OR orders.source_status = 3
                        THEN 'FINAL_DELIVERED'

                        ELSE 'IN_PROGRESS'
                    END
                    AS VARCHAR(30)
                ) AS economic_status
        ) AS economics
        OUTER APPLY (
            SELECT TOP (1)
                rules.return_surcharge
            FROM ref.shipping_return_fee_rules AS rules
            WHERE rules.shipping_partner_code =
                CASE
                    WHEN
                        COALESCE(
                            orders.shipping_partner_name,
                            N''
                        ) COLLATE Latin1_General_100_CI_AI
                            LIKE N'%giao hang tiet kiem%'
                        OR UPPER(
                            COALESCE(
                                orders.shipping_partner_name,
                                N''
                            )
                        ) LIKE N'%GHTK%'
                    THEN 'GHTK'

                    WHEN
                        UPPER(
                            COALESCE(
                                orders.shipping_partner_name,
                                N''
                            )
                        ) LIKE N'%SHOPEE XPRESS%'
                        OR UPPER(
                            COALESCE(
                                orders.shipping_partner_name,
                                N''
                            )
                        ) LIKE N'%SPX%'
                    THEN 'SPX'

                    ELSE 'OTHER'
                END
              AND rules.valid_from <=
                    CAST(orders.source_inserted_at AS DATE)
              AND (
                    rules.valid_to IS NULL
                    OR CAST(
                        orders.source_inserted_at AS DATE
                    ) < rules.valid_to
              )
            ORDER BY rules.valid_from DESC
        ) AS return_fee;

        CREATE UNIQUE CLUSTERED INDEX
            IX_order_economics_base
        ON #order_economics_base (
            shop_id,
            order_id
        );

        /*
         * Tính projected economics.
         *
         * Đơn hủy, đang hoàn và đã hoàn:
         * - doanh thu sản phẩm = 0
         * - doanh thu ship = 0
         * - COGS = 0
         *
         * Đơn đang hoàn/đã hoàn vẫn chịu phí ship.
         */
        SELECT
            base.shop_id,
            base.order_id,

            base.source_raw_order_version_id,
            base.source_inserted_at,
            base.source_updated_at,
            base.order_date,

            base.source_status,
            base.status_name,
            base.economic_status,
            base.is_finalized,

            base.is_cancelled,
            base.is_delivered,
            base.is_returning,
            base.is_returned,

            base.page_id,
            base.page_name,
            base.ad_id,
            base.post_id,
            base.ads_source,
            base.order_source_name,

            base.utm_campaign,
            base.utm_content,
            base.utm_id,
            base.utm_medium,
            base.utm_source,
            base.utm_term,

            base.shipping_partner_name,

            base.item_line_count,
            base.total_quantity,

            base.history_cost_line_count,
            base.fallback_cost_line_count,
            base.estimated_cost_line_count,
            base.missing_cost_line_count,

            base.has_estimated_cost,
            base.has_missing_cost,

            base.source_total_price,
            base.source_total_price_after_discount,
            base.source_buyer_total_amount,
            base.source_customer_shipping_fee,
            base.source_partner_fee,
            base.source_partner_total_fee,
            base.source_surcharge,
            base.source_advanced_platform_fee,
            base.source_marketplace_fee,
            base.source_customer_pay_fee,

            base.resolved_product_cost,
            base.base_shipping_cost,
            base.applied_return_surcharge,

            projected.projected_product_revenue,
            projected.projected_shipping_revenue,

            CAST(
                projected.projected_product_revenue
                + projected.projected_shipping_revenue
                AS DECIMAL(19, 2)
            ) AS projected_total_revenue,

            projected.projected_cogs,

            CAST(
                base.base_shipping_cost
                + base.applied_return_surcharge
                AS DECIMAL(19, 2)
            ) AS projected_shipping_cost,

            CAST(
                projected.projected_product_revenue
                + projected.projected_shipping_revenue
                - projected.projected_cogs
                - base.base_shipping_cost
                - base.applied_return_surcharge
                AS DECIMAL(19, 2)
            ) AS projected_contribution_profit,

            CAST(
                CASE
                    WHEN base.is_finalized = 1
                    THEN projected.projected_product_revenue
                    ELSE NULL
                END
                AS DECIMAL(19, 2)
            ) AS recognized_product_revenue,

            CAST(
                CASE
                    WHEN base.is_finalized = 1
                    THEN projected.projected_shipping_revenue
                    ELSE NULL
                END
                AS DECIMAL(19, 2)
            ) AS recognized_shipping_revenue,

            CAST(
                CASE
                    WHEN base.is_finalized = 1
                    THEN
                        projected.projected_product_revenue
                        + projected.projected_shipping_revenue
                    ELSE NULL
                END
                AS DECIMAL(19, 2)
            ) AS recognized_total_revenue,

            CAST(
                CASE
                    WHEN base.is_finalized = 1
                    THEN projected.projected_cogs
                    ELSE NULL
                END
                AS DECIMAL(19, 2)
            ) AS recognized_cogs,

            CAST(
                CASE
                    WHEN base.is_finalized = 1
                    THEN
                        base.base_shipping_cost
                        + base.applied_return_surcharge
                    ELSE NULL
                END
                AS DECIMAL(19, 2)
            ) AS recognized_shipping_cost,

            CAST(
                CASE
                    WHEN base.is_finalized = 1
                    THEN
                        projected.projected_product_revenue
                        + projected.projected_shipping_revenue
                        - projected.projected_cogs
                        - base.base_shipping_cost
                        - base.applied_return_surcharge
                    ELSE NULL
                END
                AS DECIMAL(19, 2)
            ) AS recognized_contribution_profit
        INTO #source_order_economics
        FROM #order_economics_base AS base
        CROSS APPLY (
            SELECT
                CAST(
                    CASE
                        WHEN base.economic_status IN (
                            'FINAL_CANCELED',
                            'FINAL_RETURNED',
                            'PROVISIONAL_RETURNING'
                        )
                        THEN 0
                        ELSE COALESCE(
                            base.source_total_price_after_discount,
                            0
                        )
                    END
                    AS DECIMAL(19, 2)
                ) AS projected_product_revenue,

                /*
                 * shipping_fee chỉ được giữ làm trường
                 * đối soát nguồn, không được tính vào doanh thu.
                 */
                CAST(
                    0
                    AS DECIMAL(19, 2)
                ) AS projected_shipping_revenue,

                CAST(
                    CASE
                        WHEN base.economic_status IN (
                            'FINAL_CANCELED',
                            'FINAL_RETURNED',
                            'PROVISIONAL_RETURNING'
                        )
                        THEN 0
                        ELSE base.resolved_product_cost
                    END
                    AS DECIMAL(19, 2)
                ) AS projected_cogs
        ) AS projected;

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_order_economics
        ON #source_order_economics (
            shop_id,
            order_id
        );

        /*
         * Chỉ cập nhật những đơn có thay đổi.
         */
        SELECT
            source.shop_id,
            source.order_id
        INTO #changed_orders
        FROM #source_order_economics AS source
        LEFT JOIN mart.order_economics AS target
            ON target.shop_id = source.shop_id
           AND target.order_id = source.order_id
        WHERE target.order_id IS NULL
           OR EXISTS (
                SELECT
                    source.source_raw_order_version_id,
                    source.economic_status,
                    source.is_finalized,
                    source.item_line_count,
                    source.total_quantity,
                    source.history_cost_line_count,
                    source.fallback_cost_line_count,
                    source.estimated_cost_line_count,
                    source.missing_cost_line_count,
                    source.resolved_product_cost,
                    source.base_shipping_cost,
                    source.applied_return_surcharge,
                    source.projected_total_revenue,
                    source.projected_cogs,
                    source.projected_shipping_cost,
                    source.projected_contribution_profit,
                    source.recognized_total_revenue,
                    source.recognized_cogs,
                    source.recognized_shipping_cost,
                    source.recognized_contribution_profit

                EXCEPT

                SELECT
                    target.source_raw_order_version_id,
                    target.economic_status,
                    target.is_finalized,
                    target.item_line_count,
                    target.total_quantity,
                    target.history_cost_line_count,
                    target.fallback_cost_line_count,
                    target.estimated_cost_line_count,
                    target.missing_cost_line_count,
                    target.resolved_product_cost,
                    target.base_shipping_cost,
                    target.applied_return_surcharge,
                    target.projected_total_revenue,
                    target.projected_cogs,
                    target.projected_shipping_cost,
                    target.projected_contribution_profit,
                    target.recognized_total_revenue,
                    target.recognized_cogs,
                    target.recognized_shipping_cost,
                    target.recognized_contribution_profit
           );

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_order_economics
        ON #changed_orders (
            shop_id,
            order_id
        );

        DECLARE @changed_order_count INT = (
            SELECT COUNT(*)
            FROM #changed_orders
        );

        DECLARE @deleted_order_count INT = (
            SELECT COUNT(*)
            FROM mart.order_economics AS target
            WHERE NOT EXISTS (
                SELECT 1
                FROM #source_order_economics AS source
                WHERE source.shop_id = target.shop_id
                  AND source.order_id = target.order_id
            )
        );

        DELETE target
        FROM mart.order_economics AS target
        WHERE NOT EXISTS (
            SELECT 1
            FROM #source_order_economics AS source
            WHERE source.shop_id = target.shop_id
              AND source.order_id = target.order_id
        );

        UPDATE target
        SET
            source_raw_order_version_id =
                source.source_raw_order_version_id,
            source_inserted_at =
                source.source_inserted_at,
            source_updated_at =
                source.source_updated_at,
            order_date = source.order_date,

            source_status = source.source_status,
            status_name = source.status_name,
            economic_status = source.economic_status,
            is_finalized = source.is_finalized,

            is_cancelled = source.is_cancelled,
            is_delivered = source.is_delivered,
            is_returning = source.is_returning,
            is_returned = source.is_returned,

            page_id = source.page_id,
            page_name = source.page_name,
            ad_id = source.ad_id,
            post_id = source.post_id,
            ads_source = source.ads_source,
            order_source_name = source.order_source_name,

            utm_campaign = source.utm_campaign,
            utm_content = source.utm_content,
            utm_id = source.utm_id,
            utm_medium = source.utm_medium,
            utm_source = source.utm_source,
            utm_term = source.utm_term,

            shipping_partner_name =
                source.shipping_partner_name,

            item_line_count = source.item_line_count,
            total_quantity = source.total_quantity,

            history_cost_line_count =
                source.history_cost_line_count,
            fallback_cost_line_count =
                source.fallback_cost_line_count,
            estimated_cost_line_count =
                source.estimated_cost_line_count,
            missing_cost_line_count =
                source.missing_cost_line_count,

            has_estimated_cost =
                source.has_estimated_cost,
            has_missing_cost =
                source.has_missing_cost,

            source_total_price =
                source.source_total_price,
            source_total_price_after_discount =
                source.source_total_price_after_discount,
            source_buyer_total_amount =
                source.source_buyer_total_amount,
            source_customer_shipping_fee =
                source.source_customer_shipping_fee,
            source_partner_fee =
                source.source_partner_fee,
            source_partner_total_fee =
                source.source_partner_total_fee,
            source_surcharge =
                source.source_surcharge,
            source_advanced_platform_fee =
                source.source_advanced_platform_fee,
            source_marketplace_fee =
                source.source_marketplace_fee,
            source_customer_pay_fee =
                source.source_customer_pay_fee,

            resolved_product_cost =
                source.resolved_product_cost,
            base_shipping_cost =
                source.base_shipping_cost,
            applied_return_surcharge =
                source.applied_return_surcharge,

            projected_product_revenue =
                source.projected_product_revenue,
            projected_shipping_revenue =
                source.projected_shipping_revenue,
            projected_total_revenue =
                source.projected_total_revenue,
            projected_cogs =
                source.projected_cogs,
            projected_shipping_cost =
                source.projected_shipping_cost,
            projected_contribution_profit =
                source.projected_contribution_profit,

            recognized_product_revenue =
                source.recognized_product_revenue,
            recognized_shipping_revenue =
                source.recognized_shipping_revenue,
            recognized_total_revenue =
                source.recognized_total_revenue,
            recognized_cogs =
                source.recognized_cogs,
            recognized_shipping_cost =
                source.recognized_shipping_cost,
            recognized_contribution_profit =
                source.recognized_contribution_profit,

            mart_refreshed_at_utc =
                SYSUTCDATETIME()
        FROM mart.order_economics AS target
        INNER JOIN #source_order_economics AS source
            ON source.shop_id = target.shop_id
           AND source.order_id = target.order_id
        INNER JOIN #changed_orders AS changed
            ON changed.shop_id = source.shop_id
           AND changed.order_id = source.order_id;

        INSERT INTO mart.order_economics (
            shop_id,
            order_id,
            source_raw_order_version_id,
            source_inserted_at,
            source_updated_at,
            order_date,
            source_status,
            status_name,
            economic_status,
            is_finalized,
            is_cancelled,
            is_delivered,
            is_returning,
            is_returned,
            page_id,
            page_name,
            ad_id,
            post_id,
            ads_source,
            order_source_name,
            utm_campaign,
            utm_content,
            utm_id,
            utm_medium,
            utm_source,
            utm_term,
            shipping_partner_name,
            item_line_count,
            total_quantity,
            history_cost_line_count,
            fallback_cost_line_count,
            estimated_cost_line_count,
            missing_cost_line_count,
            has_estimated_cost,
            has_missing_cost,
            source_total_price,
            source_total_price_after_discount,
            source_buyer_total_amount,
            source_customer_shipping_fee,
            source_partner_fee,
            source_partner_total_fee,
            source_surcharge,
            source_advanced_platform_fee,
            source_marketplace_fee,
            source_customer_pay_fee,
            resolved_product_cost,
            base_shipping_cost,
            applied_return_surcharge,
            projected_product_revenue,
            projected_shipping_revenue,
            projected_total_revenue,
            projected_cogs,
            projected_shipping_cost,
            projected_contribution_profit,
            recognized_product_revenue,
            recognized_shipping_revenue,
            recognized_total_revenue,
            recognized_cogs,
            recognized_shipping_cost,
            recognized_contribution_profit
        )
        SELECT
            source.shop_id,
            source.order_id,
            source.source_raw_order_version_id,
            source.source_inserted_at,
            source.source_updated_at,
            source.order_date,
            source.source_status,
            source.status_name,
            source.economic_status,
            source.is_finalized,
            source.is_cancelled,
            source.is_delivered,
            source.is_returning,
            source.is_returned,
            source.page_id,
            source.page_name,
            source.ad_id,
            source.post_id,
            source.ads_source,
            source.order_source_name,
            source.utm_campaign,
            source.utm_content,
            source.utm_id,
            source.utm_medium,
            source.utm_source,
            source.utm_term,
            source.shipping_partner_name,
            source.item_line_count,
            source.total_quantity,
            source.history_cost_line_count,
            source.fallback_cost_line_count,
            source.estimated_cost_line_count,
            source.missing_cost_line_count,
            source.has_estimated_cost,
            source.has_missing_cost,
            source.source_total_price,
            source.source_total_price_after_discount,
            source.source_buyer_total_amount,
            source.source_customer_shipping_fee,
            source.source_partner_fee,
            source.source_partner_total_fee,
            source.source_surcharge,
            source.source_advanced_platform_fee,
            source.source_marketplace_fee,
            source.source_customer_pay_fee,
            source.resolved_product_cost,
            source.base_shipping_cost,
            source.applied_return_surcharge,
            source.projected_product_revenue,
            source.projected_shipping_revenue,
            source.projected_total_revenue,
            source.projected_cogs,
            source.projected_shipping_cost,
            source.projected_contribution_profit,
            source.recognized_product_revenue,
            source.recognized_shipping_revenue,
            source.recognized_total_revenue,
            source.recognized_cogs,
            source.recognized_shipping_cost,
            source.recognized_contribution_profit
        FROM #source_order_economics AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM mart.order_economics AS target
            WHERE target.shop_id = source.shop_id
              AND target.order_id = source.order_id
        );

        COMMIT TRANSACTION;

        SELECT
            @changed_order_count AS changed_orders,
            @deleted_order_count AS deleted_orders,
            COUNT(*) AS staged_orders,

            SUM(
                CASE
                    WHEN economic_status =
                         'FINAL_DELIVERED'
                    THEN 1
                    ELSE 0
                END
            ) AS delivered_orders,

            SUM(
                CASE
                    WHEN economic_status =
                         'FINAL_RETURNED'
                    THEN 1
                    ELSE 0
                END
            ) AS returned_orders,

            SUM(
                CASE
                    WHEN economic_status =
                         'FINAL_CANCELED'
                    THEN 1
                    ELSE 0
                END
            ) AS canceled_orders,

            SUM(
                CASE
                    WHEN economic_status =
                         'PROVISIONAL_RETURNING'
                    THEN 1
                    ELSE 0
                END
            ) AS returning_orders,

            SUM(
                CASE
                    WHEN economic_status =
                         'IN_PROGRESS'
                    THEN 1
                    ELSE 0
                END
            ) AS in_progress_orders,

            SUM(projected_contribution_profit)
                AS projected_contribution_profit,

            SUM(recognized_contribution_profit)
                AS recognized_contribution_profit
        FROM mart.order_economics;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
