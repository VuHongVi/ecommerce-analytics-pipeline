SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'reporting') IS NULL
    BEGIN
        EXEC(N'CREATE SCHEMA reporting;');
    END;

    EXEC(N'
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
                AS recognized_contribution_before_ads
        FROM mart.order_economics AS orders
        INNER JOIN mart.dim_meta_ads AS ads
            ON ads.ad_id = COALESCE(
                NULLIF(LTRIM(RTRIM(orders.ad_id)), N''''),
                N''__UNATTRIBUTED__''
            );
    ');

    EXEC(N'
        CREATE OR ALTER VIEW reporting.fact_ad_economics_daily
        AS
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
            facts.recognized_contribution_after_ads
        FROM mart.ad_economics_daily AS facts;
    ');

    EXEC(N'
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
            items.recognized_contribution_before_ads
        FROM mart.order_item_economics AS items;
    ');

    EXEC(N'
        CREATE OR ALTER VIEW
            reporting.fact_product_ad_economics_daily
        AS
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
            facts.product_order_count
                AS orders_containing_product,
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
            facts.recognized_contribution_after_ads
        FROM mart.product_ad_economics_daily AS facts;
    ');

    COMMIT TRANSACTION;

    SELECT
        (SELECT COUNT(*)
         FROM reporting.fact_order_economics)
            AS order_rows,
        (SELECT COUNT(*)
         FROM reporting.fact_ad_economics_daily)
            AS ad_daily_rows,
        (SELECT COUNT(*)
         FROM reporting.fact_order_item_economics)
            AS order_item_rows,
        (SELECT COUNT(*)
         FROM reporting.fact_product_ad_economics_daily)
            AS product_ad_daily_rows;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
