SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*
 * Apply the effective-dated business scope to the two product-grain
 * Power BI reporting views.
 *
 * Design principles:
 * - Preserve the original all-scope columns for audit and reconciliation.
 * - Add explicit in_scope_* columns for the ecommerce dashboard.
 * - Classify order economics with order_scope_assignments.
 * - Classify allocated Meta cost with ad_scope_assignments_daily.
 * - Preserve the existing grain and keys of both reporting views.
 */

CREATE OR ALTER VIEW reporting.fact_order_item_economics
AS
SELECT
    CONVERT(
        INT,
        CONVERT(CHAR(8), items.order_date, 112)
    ) AS date_key,
    items.ad_key,
    items.product_key,
    items.shop_id,
    items.order_id,
    items.source_item_id,
    items.order_date,
    items.item_attribution_status,
    items.allocation_method,
    items.economic_status,
    items.is_finalized,
    items.quantity,
    items.unit_retail_price,
    items.gross_line_revenue,
    items.revenue_allocation_weight,
    items.allocated_source_product_revenue,
    items.allocated_discount_adjustment,
    items.resolved_unit_cost,
    items.source_line_product_cost,
    items.cost_source,
    items.is_estimated_cost,
    items.is_missing_cost,
    items.projected_total_revenue,
    items.projected_cogs,
    items.projected_shipping_cost,
    items.projected_contribution_before_ads,
    items.recognized_total_revenue,
    items.recognized_cogs,
    items.recognized_shipping_cost,
    items.recognized_contribution_before_ads,

    scope.scope_status AS business_scope_status,
    scope.is_in_scope AS is_in_business_scope,
    scope.project_code AS business_project_code,
    scope.assignment_method AS scope_assignment_method,

    CAST(1 AS INT) AS item_economics_row_count,

    CAST(
        CASE WHEN scope.is_in_scope = 1 THEN 1 ELSE 0 END
        AS INT
    ) AS in_scope_item_economics_row_count,

    CAST(
        CASE WHEN scope.is_in_scope = 0 THEN 1 ELSE 0 END
        AS INT
    ) AS out_of_scope_item_economics_row_count,

    CAST(
        CASE WHEN scope.is_in_scope = 1 THEN items.quantity ELSE 0 END
        AS BIGINT
    ) AS in_scope_quantity,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN items.allocated_source_product_revenue
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_allocated_source_product_revenue,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN items.projected_total_revenue
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_total_revenue,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN items.projected_cogs
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_cogs,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN items.projected_shipping_cost
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_shipping_cost,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN items.projected_contribution_before_ads
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_contribution_before_ads,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN COALESCE(items.recognized_total_revenue, 0)
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_total_revenue,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN COALESCE(items.recognized_cogs, 0)
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_cogs,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN COALESCE(items.recognized_shipping_cost, 0)
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_shipping_cost,

    CAST(
        CASE
            WHEN scope.is_in_scope = 1
            THEN COALESCE(
                items.recognized_contribution_before_ads,
                0
            )
            ELSE 0
        END
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_contribution_before_ads

FROM mart.order_item_economics AS items

INNER JOIN mart.order_scope_assignments AS scope
    ON scope.shop_id = items.shop_id
   AND scope.order_id = items.order_id;
GO

CREATE OR ALTER VIEW reporting.fact_product_ad_economics_daily
AS
WITH scoped_product_order AS (
    /*
     * Collapse item rows to product + order before counting orders.
     * This prevents one order from being counted more than once when
     * the same product appears on multiple source item lines.
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
        CAST(SUM(items.quantity) AS BIGINT) AS total_quantity,
        MAX(CAST(items.is_finalized AS INT)) AS is_finalized,
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
                WHEN items.economic_status = 'PROVISIONAL_RETURNING'
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
    FROM mart.order_item_economics AS items
    INNER JOIN mart.order_scope_assignments AS scope
        ON scope.shop_id = items.shop_id
       AND scope.order_id = items.order_id
    WHERE scope.is_in_scope = 1
    GROUP BY
        items.order_date,
        items.ad_key,
        items.product_key,
        items.shop_id,
        items.order_id
),
scoped_product_daily AS (
    SELECT
        product_order.analysis_date,
        product_order.ad_key,
        product_order.product_key,
        COUNT(*) AS product_order_count,
        SUM(product_order.item_line_count) AS item_line_count,
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
            SUM(product_order.allocated_source_product_revenue)
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
            SUM(product_order.projected_contribution_before_ads)
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
            SUM(product_order.recognized_contribution_before_ads)
            AS DECIMAL(19, 2)
        ) AS recognized_contribution_before_ads
    FROM scoped_product_order AS product_order
    GROUP BY
        product_order.analysis_date,
        product_order.ad_key,
        product_order.product_key
)
SELECT
    CONVERT(
        INT,
        CONVERT(CHAR(8), facts.analysis_date, 112)
    ) AS date_key,
    facts.ad_key,
    facts.product_key,
    facts.analysis_date,
    facts.daily_presence_status,
    facts.ad_cost_allocation_method,
    facts.has_meta_insight,
    facts.has_product_orders,
    facts.has_allocated_ad_cost,
    facts.ad_cost_allocation_weight,
    facts.product_order_count AS orders_containing_product,
    facts.item_line_count,
    facts.total_quantity,
    facts.finalized_product_order_count,
    facts.delivered_product_order_count,
    facts.returned_product_order_count,
    facts.canceled_product_order_count,
    facts.returning_product_order_count,
    facts.in_progress_product_order_count,
    facts.product_orders_with_estimated_cost,
    facts.product_orders_with_missing_cost,
    facts.allocated_source_product_revenue,
    facts.projected_total_revenue,
    facts.projected_cogs,
    facts.projected_shipping_cost,
    facts.projected_contribution_before_ads,
    facts.recognized_total_revenue,
    facts.recognized_cogs,
    facts.recognized_shipping_cost,
    facts.recognized_contribution_before_ads,
    facts.allocated_meta_spend,
    facts.allocated_meta_tax_amount,
    facts.allocated_actual_ad_cost,
    facts.projected_contribution_after_ads,
    facts.recognized_contribution_after_ads,

    ad_scope.scope_status AS ad_cost_scope_status,
    ad_scope.is_in_scope AS is_ad_cost_in_scope,
    ad_scope.project_code AS ad_cost_project_code,
    ad_scope.assignment_method AS ad_scope_assignment_method,

    CAST(
        CASE
            WHEN scoped.product_key IS NOT NULL THEN 1
            ELSE 0
        END
        AS BIT
    ) AS has_in_scope_product_orders,

    COALESCE(scoped.product_order_count, 0)
        AS in_scope_orders_containing_product,
    COALESCE(scoped.item_line_count, 0)
        AS in_scope_item_line_count,
    COALESCE(scoped.total_quantity, 0)
        AS in_scope_total_quantity,
    COALESCE(scoped.finalized_product_order_count, 0)
        AS in_scope_finalized_product_order_count,
    COALESCE(scoped.delivered_product_order_count, 0)
        AS in_scope_delivered_product_order_count,
    COALESCE(scoped.returned_product_order_count, 0)
        AS in_scope_returned_product_order_count,
    COALESCE(scoped.canceled_product_order_count, 0)
        AS in_scope_canceled_product_order_count,
    COALESCE(scoped.returning_product_order_count, 0)
        AS in_scope_returning_product_order_count,
    COALESCE(scoped.in_progress_product_order_count, 0)
        AS in_scope_in_progress_product_order_count,
    COALESCE(scoped.product_orders_with_estimated_cost, 0)
        AS in_scope_product_orders_with_estimated_cost,
    COALESCE(scoped.product_orders_with_missing_cost, 0)
        AS in_scope_product_orders_with_missing_cost,

    CAST(
        COALESCE(scoped.allocated_source_product_revenue, 0)
        AS DECIMAL(19, 2)
    ) AS in_scope_allocated_source_product_revenue,

    CAST(
        COALESCE(scoped.projected_total_revenue, 0)
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_total_revenue,

    CAST(
        COALESCE(scoped.projected_cogs, 0)
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_cogs,

    CAST(
        COALESCE(scoped.projected_shipping_cost, 0)
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_shipping_cost,

    CAST(
        COALESCE(scoped.projected_contribution_before_ads, 0)
        AS DECIMAL(19, 2)
    ) AS in_scope_projected_contribution_before_ads,

    CAST(
        COALESCE(scoped.recognized_total_revenue, 0)
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_total_revenue,

    CAST(
        COALESCE(scoped.recognized_cogs, 0)
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_cogs,

    CAST(
        COALESCE(scoped.recognized_shipping_cost, 0)
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_shipping_cost,

    CAST(
        COALESCE(scoped.recognized_contribution_before_ads, 0)
        AS DECIMAL(19, 2)
    ) AS in_scope_recognized_contribution_before_ads,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.allocated_meta_spend
            ELSE 0
        END
        AS DECIMAL(19, 6)
    ) AS in_scope_allocated_meta_spend,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.allocated_meta_tax_amount
            ELSE 0
        END
        AS DECIMAL(19, 6)
    ) AS in_scope_allocated_meta_tax_amount,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.allocated_actual_ad_cost
            ELSE 0
        END
        AS DECIMAL(19, 6)
    ) AS in_scope_allocated_actual_ad_cost,

    CAST(
        CASE
            WHEN ad_scope.is_in_scope = 0
            THEN facts.allocated_actual_ad_cost
            ELSE 0
        END
        AS DECIMAL(19, 6)
    ) AS out_of_scope_allocated_actual_ad_cost,

    CAST(
        COALESCE(scoped.projected_contribution_before_ads, 0)
        - CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.allocated_actual_ad_cost
            ELSE 0
          END
        AS DECIMAL(19, 6)
    ) AS in_scope_projected_contribution_after_ads,

    CAST(
        COALESCE(scoped.recognized_contribution_before_ads, 0)
        - CASE
            WHEN ad_scope.is_in_scope = 1
            THEN facts.allocated_actual_ad_cost
            ELSE 0
          END
        AS DECIMAL(19, 6)
    ) AS in_scope_recognized_contribution_after_ads

FROM mart.product_ad_economics_daily AS facts

INNER JOIN mart.ad_scope_assignments_daily AS ad_scope
    ON ad_scope.analysis_date = facts.analysis_date
   AND ad_scope.ad_key = facts.ad_key

LEFT JOIN scoped_product_daily AS scoped
    ON scoped.analysis_date = facts.analysis_date
   AND scoped.ad_key = facts.ad_key
   AND scoped.product_key = facts.product_key;
GO
