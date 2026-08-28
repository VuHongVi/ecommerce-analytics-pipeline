CREATE OR ALTER VIEW reporting.fact_order_economics
AS
SELECT
    CONVERT(
        INT,
        CONVERT(CHAR(8), orders.order_date, 112)
    ) AS date_key,
    ads.ad_key,
    orders.shop_id,
    orders.order_id,
    CAST(1 AS INT) AS order_count,
    orders.order_date,
    orders.source_status,
    orders.status_name,
    orders.economic_status,
    orders.is_finalized,
    orders.is_cancelled,
    orders.is_delivered,
    orders.is_returning,
    orders.is_returned,
    orders.page_id,
    orders.page_name,
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
    orders.item_line_count,
    orders.total_quantity,
    orders.has_estimated_cost,
    orders.has_missing_cost,
    orders.source_total_price_after_discount
        AS source_product_revenue,
    orders.source_customer_shipping_fee,
    orders.source_partner_fee,
    orders.source_partner_total_fee,
    orders.resolved_product_cost,
    orders.base_shipping_cost,
    orders.applied_return_surcharge,
    orders.projected_total_revenue,
    orders.projected_cogs,
    orders.projected_shipping_cost,
    orders.projected_contribution_profit
        AS projected_contribution_before_ads,
    orders.recognized_total_revenue,
    orders.recognized_cogs,
    orders.recognized_shipping_cost,
    orders.recognized_contribution_profit
        AS recognized_contribution_before_ads,

    scope.scope_status AS business_scope_status,
    scope.is_in_scope AS is_in_business_scope,
    scope.project_code AS business_project_code,
    scope.assignment_method AS scope_assignment_method,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN 1
            ELSE 0
        END
        AS INT
    ) AS in_scope_order_count,

    CAST(
        CASE
            WHEN scope.is_in_scope = 0
            THEN 1
            ELSE 0
        END
        AS INT
    ) AS out_of_scope_order_count,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN orders.total_quantity
            ELSE 0
        END
        AS BIGINT
    ) AS in_scope_total_quantity,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN orders.projected_total_revenue
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_total_revenue,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN orders.projected_cogs
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_cogs,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN orders.projected_shipping_cost
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_shipping_cost,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN orders.projected_contribution_profit
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_contribution_before_ads,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN COALESCE(
                orders.recognized_total_revenue,
                0
            )
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_total_revenue,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN COALESCE(
                orders.recognized_cogs,
                0
            )
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_cogs,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN COALESCE(
                orders.recognized_shipping_cost,
                0
            )
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_shipping_cost,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN COALESCE(
                orders.recognized_contribution_profit,
                0
            )
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_contribution_before_ads

FROM mart.order_economics AS orders

INNER JOIN mart.dim_meta_ads AS ads
    ON ads.ad_id = COALESCE(
        NULLIF(LTRIM(RTRIM(orders.ad_id)), N''),
        N'__UNATTRIBUTED__'
    )

INNER JOIN mart.order_scope_assignments AS scope
    ON scope.shop_id = orders.shop_id
   AND scope.order_id = orders.order_id;
GO

CREATE OR ALTER VIEW reporting.fact_ad_economics_daily
AS
WITH scoped_order_daily AS (
    SELECT
        orders.order_date AS analysis_date,
        ads.ad_key,

        SUM(
            CASE
                WHEN scope.is_in_scope = 1
                THEN 1
                ELSE 0
            END
        ) AS in_scope_order_count,

        SUM(
            CASE
                WHEN scope.is_in_scope = 0
                THEN 1
                ELSE 0
            END
        ) AS out_of_scope_order_count,

        SUM(
            CASE
                WHEN scope.is_in_scope = 1
                 AND orders.is_finalized = 1
                THEN 1
                ELSE 0
            END
        ) AS in_scope_finalized_order_count,

        SUM(
            CASE
                WHEN scope.is_in_scope = 1
                 AND orders.economic_status =
                     'FINAL_DELIVERED'
                THEN 1
                ELSE 0
            END
        ) AS in_scope_delivered_order_count,

        SUM(
            CASE
                WHEN scope.is_in_scope = 1
                 AND orders.economic_status =
                     'FINAL_RETURNED'
                THEN 1
                ELSE 0
            END
        ) AS in_scope_returned_order_count,

        SUM(
            CASE
                WHEN scope.is_in_scope = 1
                 AND orders.economic_status =
                     'FINAL_CANCELED'
                THEN 1
                ELSE 0
            END
        ) AS in_scope_canceled_order_count,

        SUM(
            CASE
                WHEN scope.is_in_scope = 1
                 AND orders.economic_status =
                     'PROVISIONAL_RETURNING'
                THEN 1
                ELSE 0
            END
        ) AS in_scope_returning_order_count,

        SUM(
            CASE
                WHEN scope.is_in_scope = 1
                 AND orders.economic_status =
                     'IN_PROGRESS'
                THEN 1
                ELSE 0
            END
        ) AS in_scope_in_progress_order_count,

        CAST(
            SUM(
                CASE
                    WHEN scope.is_in_scope = 1
                    THEN orders.total_quantity
                    ELSE 0
                END
            )
            AS BIGINT
        ) AS in_scope_total_quantity,

        SUM(
            CASE
                WHEN scope.is_in_scope = 1
                 AND orders.has_estimated_cost = 1
                THEN 1
                ELSE 0
            END
        ) AS in_scope_orders_with_estimated_cost,

        SUM(
            CASE
                WHEN scope.is_in_scope = 1
                 AND orders.has_missing_cost = 1
                THEN 1
                ELSE 0
            END
        ) AS in_scope_orders_with_missing_cost,

        CAST(
            SUM(
                CASE
                    WHEN scope.is_in_scope = 1
                    THEN orders.projected_total_revenue
                    ELSE 0
                END
            )
            AS DECIMAL(19, 2)
        ) AS in_scope_projected_total_revenue,

        CAST(
            SUM(
                CASE
                    WHEN scope.is_in_scope = 1
                    THEN orders.projected_cogs
                    ELSE 0
                END
            )
            AS DECIMAL(19, 2)
        ) AS in_scope_projected_cogs,

        CAST(
            SUM(
                CASE
                    WHEN scope.is_in_scope = 1
                    THEN orders.projected_shipping_cost
                    ELSE 0
                END
            )
            AS DECIMAL(19, 2)
        ) AS in_scope_projected_shipping_cost,

        CAST(
            SUM(
                CASE
                    WHEN scope.is_in_scope = 1
                    THEN orders.projected_contribution_profit
                    ELSE 0
                END
            )
            AS DECIMAL(19, 2)
        ) AS in_scope_projected_contribution_before_ads,

        CAST(
            SUM(
                CASE
                    WHEN scope.is_in_scope = 1
                    THEN COALESCE(
                        orders.recognized_total_revenue,
                        0
                    )
                    ELSE 0
                END
            )
            AS DECIMAL(19, 2)
        ) AS in_scope_recognized_total_revenue,

        CAST(
            SUM(
                CASE
                    WHEN scope.is_in_scope = 1
                    THEN COALESCE(
                        orders.recognized_cogs,
                        0
                    )
                    ELSE 0
                END
            )
            AS DECIMAL(19, 2)
        ) AS in_scope_recognized_cogs,

        CAST(
            SUM(
                CASE
                    WHEN scope.is_in_scope = 1
                    THEN COALESCE(
                        orders.recognized_shipping_cost,
                        0
                    )
                    ELSE 0
                END
            )
            AS DECIMAL(19, 2)
        ) AS in_scope_recognized_shipping_cost,

        CAST(
            SUM(
                CASE
                    WHEN scope.is_in_scope = 1
                    THEN COALESCE(
                        orders.recognized_contribution_profit,
                        0
                    )
                    ELSE 0
                END
            )
            AS DECIMAL(19, 2)
        ) AS in_scope_recognized_contribution_before_ads

    FROM mart.order_economics AS orders

    INNER JOIN mart.dim_meta_ads AS ads
        ON ads.ad_id = COALESCE(
            NULLIF(LTRIM(RTRIM(orders.ad_id)), N''),
            N'__UNATTRIBUTED__'
        )

    INNER JOIN mart.order_scope_assignments AS scope
        ON scope.shop_id = orders.shop_id
       AND scope.order_id = orders.order_id

    GROUP BY
        orders.order_date,
        ads.ad_key
)
SELECT
    CONVERT(
        INT,
        CONVERT(CHAR(8), facts.analysis_date, 112)
    ) AS date_key,
    facts.ad_key,
    facts.analysis_date,
    facts.daily_presence_status,
    facts.has_meta_insight,
    facts.has_orders,
    facts.currency,
    facts.tax_rate,
    facts.impressions,
    facts.reach,
    facts.clicks,
    facts.inline_link_clicks,
    facts.meta_spend,
    facts.meta_tax_amount,
    facts.actual_ad_cost,
    facts.order_count,
    facts.finalized_order_count,
    facts.delivered_order_count,
    facts.returned_order_count,
    facts.canceled_order_count,
    facts.returning_order_count,
    facts.in_progress_order_count,
    facts.total_quantity,
    facts.orders_with_estimated_cost,
    facts.orders_with_missing_cost,
    facts.projected_total_revenue,
    facts.projected_cogs,
    facts.projected_shipping_cost,
    facts.projected_contribution_before_ads,
    facts.projected_contribution_after_ads,
    facts.recognized_total_revenue,
    facts.recognized_cogs,
    facts.recognized_shipping_cost,
    facts.recognized_contribution_before_ads,
    facts.recognized_contribution_after_ads,

    ad_scope.scope_status AS ad_cost_scope_status,
    ad_scope.is_in_scope AS is_ad_cost_in_scope,
    ad_scope.project_code AS ad_cost_project_code,
    ad_scope.assignment_method
        AS ad_scope_assignment_method,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.impressions
            ELSE 0
        END
        AS BIGINT
    ) AS in_scope_impressions,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.reach
            ELSE 0
        END
        AS BIGINT
    ) AS in_scope_reach,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.clicks
            ELSE 0
        END
        AS BIGINT
    ) AS in_scope_clicks,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.inline_link_clicks
            ELSE 0
        END
        AS BIGINT
    ) AS in_scope_inline_link_clicks,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.meta_spend
            ELSE 0
        END
        AS DECIMAL(19, 6)
    ) AS in_scope_meta_spend,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.meta_tax_amount
            ELSE 0
        END
        AS DECIMAL(19, 6)
    ) AS in_scope_meta_tax_amount,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.actual_ad_cost
            ELSE 0
        END
        AS DECIMAL(19, 6)
    ) AS in_scope_actual_ad_cost,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 0
            THEN facts.actual_ad_cost
            ELSE 0
        END
        AS DECIMAL(19, 6)
    ) AS out_of_scope_actual_ad_cost,

    COALESCE(
        scoped_orders.in_scope_order_count,
        0
    ) AS in_scope_order_count,

    COALESCE(
        scoped_orders.out_of_scope_order_count,
        0
    ) AS out_of_scope_order_count,

    COALESCE(
        scoped_orders.in_scope_finalized_order_count,
        0
    ) AS in_scope_finalized_order_count,

    COALESCE(
        scoped_orders.in_scope_delivered_order_count,
        0
    ) AS in_scope_delivered_order_count,

    COALESCE(
        scoped_orders.in_scope_returned_order_count,
        0
    ) AS in_scope_returned_order_count,

    COALESCE(
        scoped_orders.in_scope_canceled_order_count,
        0
    ) AS in_scope_canceled_order_count,

    COALESCE(
        scoped_orders.in_scope_returning_order_count,
        0
    ) AS in_scope_returning_order_count,

    COALESCE(
        scoped_orders.in_scope_in_progress_order_count,
        0
    ) AS in_scope_in_progress_order_count,

    COALESCE(
        scoped_orders.in_scope_total_quantity,
        0
    ) AS in_scope_total_quantity,

    COALESCE(
        scoped_orders.in_scope_orders_with_estimated_cost,
        0
    ) AS in_scope_orders_with_estimated_cost,

    COALESCE(
        scoped_orders.in_scope_orders_with_missing_cost,
        0
    ) AS in_scope_orders_with_missing_cost,

    COALESCE(
        scoped_orders.in_scope_projected_total_revenue,
        0
    ) AS in_scope_projected_total_revenue,

    COALESCE(
        scoped_orders.in_scope_projected_cogs,
        0
    ) AS in_scope_projected_cogs,

    COALESCE(
        scoped_orders.in_scope_projected_shipping_cost,
        0
    ) AS in_scope_projected_shipping_cost,

    COALESCE(
        scoped_orders.in_scope_projected_contribution_before_ads,
        0
    ) AS in_scope_projected_contribution_before_ads,

    CAST(
        COALESCE(
            scoped_orders.in_scope_projected_contribution_before_ads,
            0
        )
        - CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.actual_ad_cost
            ELSE 0
          END
        AS DECIMAL(19, 6)
    ) AS in_scope_projected_contribution_after_ads,

    COALESCE(
        scoped_orders.in_scope_recognized_total_revenue,
        0
    ) AS in_scope_recognized_total_revenue,

    COALESCE(
        scoped_orders.in_scope_recognized_cogs,
        0
    ) AS in_scope_recognized_cogs,

    COALESCE(
        scoped_orders.in_scope_recognized_shipping_cost,
        0
    ) AS in_scope_recognized_shipping_cost,

    COALESCE(
        scoped_orders.in_scope_recognized_contribution_before_ads,
        0
    ) AS in_scope_recognized_contribution_before_ads,

    CAST(
        COALESCE(
            scoped_orders.in_scope_recognized_contribution_before_ads,
            0
        )
        - CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.actual_ad_cost
            ELSE 0
          END
        AS DECIMAL(19, 6)
    ) AS in_scope_recognized_contribution_after_ads

FROM mart.ad_economics_daily AS facts

INNER JOIN mart.ad_scope_assignments_daily AS ad_scope
    ON ad_scope.analysis_date = facts.analysis_date
   AND ad_scope.ad_key = facts.ad_key

LEFT JOIN scoped_order_daily AS scoped_orders
    ON scoped_orders.analysis_date = facts.analysis_date
   AND scoped_orders.ad_key = facts.ad_key;
