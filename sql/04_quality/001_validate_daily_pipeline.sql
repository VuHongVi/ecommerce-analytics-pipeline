SET NOCOUNT ON;
SET XACT_ABORT ON;

CREATE TABLE #quality_results (
    check_name VARCHAR(100) NOT NULL,
    failure_count BIGINT NOT NULL,
    actual_value DECIMAL(38, 6) NULL,
    expected_value DECIMAL(38, 6) NULL,
    check_detail NVARCHAR(300) NOT NULL
);

DECLARE @staged_order_count BIGINT = (
    SELECT COUNT_BIG(*)
    FROM stg.pancake_orders
);

DECLARE @mart_order_count BIGINT = (
    SELECT COUNT_BIG(*)
    FROM mart.order_economics
);

DECLARE @staged_item_count BIGINT = (
    SELECT COUNT_BIG(*)
    FROM stg.pancake_order_items
);

DECLARE @staged_item_cost_count BIGINT = (
    SELECT COUNT_BIG(*)
    FROM stg.pancake_order_item_costs
);

DECLARE @order_scope_count BIGINT = (
    SELECT COUNT_BIG(*)
    FROM mart.order_scope_assignments
);

DECLARE @ad_fact_count BIGINT = (
    SELECT COUNT_BIG(*)
    FROM mart.ad_economics_daily
);

DECLARE @ad_scope_count BIGINT = (
    SELECT COUNT_BIG(*)
    FROM mart.ad_scope_assignments_daily
);

INSERT INTO #quality_results
VALUES
(
    'staged_to_mart_order_count',
    CASE
        WHEN @staged_order_count = @mart_order_count
        THEN 0
        ELSE ABS(@staged_order_count - @mart_order_count)
    END,
    @mart_order_count,
    @staged_order_count,
    N'MART order rows must equal STAGING order rows.'
),
(
    'item_cost_coverage',
    CASE
        WHEN @staged_item_count = @staged_item_cost_count
        THEN 0
        ELSE ABS(
            @staged_item_count - @staged_item_cost_count
        )
    END,
    @staged_item_cost_count,
    @staged_item_count,
    N'Every staged item must have an item-cost row.'
),
(
    'order_scope_count',
    CASE
        WHEN @mart_order_count = @order_scope_count
        THEN 0
        ELSE ABS(@mart_order_count - @order_scope_count)
    END,
    @order_scope_count,
    @mart_order_count,
    N'Every MART order must have a scope assignment.'
),
(
    'ad_scope_count',
    CASE
        WHEN @ad_fact_count = @ad_scope_count
        THEN 0
        ELSE ABS(@ad_fact_count - @ad_scope_count)
    END,
    @ad_scope_count,
    @ad_fact_count,
    N'Every ad-date fact must have a scope assignment.'
);

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'order_scope_key_coverage',
    COUNT_BIG(*),
    N'Order and order-scope keys must match in both directions.'
FROM (
    SELECT
        economics.shop_id,
        economics.order_id
    FROM mart.order_economics AS economics
    WHERE NOT EXISTS (
        SELECT 1
        FROM mart.order_scope_assignments AS assignment
        WHERE assignment.shop_id = economics.shop_id
          AND assignment.order_id = economics.order_id
    )

    UNION ALL

    SELECT
        assignment.shop_id,
        assignment.order_id
    FROM mart.order_scope_assignments AS assignment
    WHERE NOT EXISTS (
        SELECT 1
        FROM mart.order_economics AS economics
        WHERE economics.shop_id = assignment.shop_id
          AND economics.order_id = assignment.order_id
    )
) AS mismatched_order_keys;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'ad_scope_key_coverage',
    COUNT_BIG(*),
    N'Ad fact and ad-scope keys must match in both directions.'
FROM (
    SELECT
        economics.analysis_date,
        economics.ad_key
    FROM mart.ad_economics_daily AS economics
    WHERE NOT EXISTS (
        SELECT 1
        FROM mart.ad_scope_assignments_daily AS assignment
        WHERE assignment.analysis_date =
              economics.analysis_date
          AND assignment.ad_key = economics.ad_key
    )

    UNION ALL

    SELECT
        assignment.analysis_date,
        assignment.ad_key
    FROM mart.ad_scope_assignments_daily AS assignment
    WHERE NOT EXISTS (
        SELECT 1
        FROM mart.ad_economics_daily AS economics
        WHERE economics.analysis_date =
              assignment.analysis_date
          AND economics.ad_key = assignment.ad_key
    )
) AS mismatched_ad_keys;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'order_projected_formula',
    COUNT_BIG(*),
    N'Projected contribution must equal revenue minus costs.'
FROM mart.order_economics
WHERE ABS(
    projected_contribution_profit
    - (
        projected_total_revenue
        - projected_cogs
        - projected_shipping_cost
    )
) > 0.01;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'order_recognized_formula',
    COUNT_BIG(*),
    N'Recognized contribution must equal revenue minus costs.'
FROM mart.order_economics
WHERE is_finalized = 1
  AND (
      recognized_contribution_profit IS NULL
      OR ABS(
          recognized_contribution_profit
          - (
              recognized_total_revenue
              - recognized_cogs
              - recognized_shipping_cost
          )
      ) > 0.01
  );

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'premature_order_recognition',
    COUNT_BIG(*),
    N'Non-final orders must not have recognized economics.'
FROM mart.order_economics
WHERE is_finalized = 0
  AND (
      recognized_total_revenue IS NOT NULL
      OR recognized_cogs IS NOT NULL
      OR recognized_shipping_cost IS NOT NULL
      OR recognized_contribution_profit IS NOT NULL
  );

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'shipping_revenue_is_zero',
    COUNT_BIG(*),
    N'Pancake shipping_fee must not be counted as revenue.'
FROM mart.order_economics
WHERE projected_shipping_revenue <> 0
   OR COALESCE(recognized_shipping_revenue, 0) <> 0;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'missing_product_cost',
    COUNT_BIG(*),
    N'No order may have unresolved product cost.'
FROM mart.order_economics
WHERE has_missing_cost = 1
   OR missing_cost_line_count > 0;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'ad_tax_formula',
    COUNT_BIG(*),
    N'Meta tax must equal spend multiplied by tax rate.'
FROM mart.ad_economics_daily
WHERE ABS(
    meta_tax_amount - (meta_spend * tax_rate)
) > 0.01;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'actual_ad_cost_formula',
    COUNT_BIG(*),
    N'Actual ad cost must equal Meta spend plus tax.'
FROM mart.ad_economics_daily
WHERE ABS(
    actual_ad_cost - (meta_spend + meta_tax_amount)
) > 0.01;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'ad_projected_formula',
    COUNT_BIG(*),
    N'Projected after-ads contribution formula is invalid.'
FROM mart.ad_economics_daily
WHERE ABS(
    projected_contribution_after_ads
    - (
        projected_contribution_before_ads
        - actual_ad_cost
    )
) > 0.01;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'ad_recognized_formula',
    COUNT_BIG(*),
    N'Recognized after-ads contribution formula is invalid.'
FROM mart.ad_economics_daily
WHERE ABS(
    recognized_contribution_after_ads
    - (
        recognized_contribution_before_ads
        - actual_ad_cost
    )
) > 0.01;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'product_projected_formula',
    COUNT_BIG(*),
    N'Product projected after-ads formula is invalid.'
FROM mart.product_ad_economics_daily
WHERE ABS(
    projected_contribution_after_ads
    - (
        projected_contribution_before_ads
        - allocated_actual_ad_cost
    )
) > 0.01;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'product_recognized_formula',
    COUNT_BIG(*),
    N'Product recognized after-ads formula is invalid.'
FROM mart.product_ad_economics_daily
WHERE ABS(
    recognized_contribution_after_ads
    - (
        recognized_contribution_before_ads
        - allocated_actual_ad_cost
    )
) > 0.01;

DECLARE @order_projected_revenue DECIMAL(38, 6) = (
    SELECT COALESCE(SUM(projected_total_revenue), 0)
    FROM mart.order_economics
);

DECLARE @item_projected_revenue DECIMAL(38, 6) = (
    SELECT COALESCE(SUM(projected_total_revenue), 0)
    FROM mart.order_item_economics
);

DECLARE @order_recognized_revenue DECIMAL(38, 6) = (
    SELECT COALESCE(SUM(recognized_total_revenue), 0)
    FROM mart.order_economics
);

DECLARE @item_recognized_revenue DECIMAL(38, 6) = (
    SELECT COALESCE(SUM(recognized_total_revenue), 0)
    FROM mart.order_item_economics
);

DECLARE @ad_actual_cost DECIMAL(38, 6) = (
    SELECT COALESCE(SUM(actual_ad_cost), 0)
    FROM mart.ad_economics_daily
);

DECLARE @product_actual_cost DECIMAL(38, 6) = (
    SELECT COALESCE(SUM(allocated_actual_ad_cost), 0)
    FROM mart.product_ad_economics_daily
);

DECLARE @ad_projected_after_ads DECIMAL(38, 6) = (
    SELECT COALESCE(
        SUM(projected_contribution_after_ads),
        0
    )
    FROM mart.ad_economics_daily
);

DECLARE @product_projected_after_ads DECIMAL(38, 6) = (
    SELECT COALESCE(
        SUM(projected_contribution_after_ads),
        0
    )
    FROM mart.product_ad_economics_daily
);

DECLARE @ad_recognized_after_ads DECIMAL(38, 6) = (
    SELECT COALESCE(
        SUM(recognized_contribution_after_ads),
        0
    )
    FROM mart.ad_economics_daily
);

DECLARE @product_recognized_after_ads DECIMAL(38, 6) = (
    SELECT COALESCE(
        SUM(recognized_contribution_after_ads),
        0
    )
    FROM mart.product_ad_economics_daily
);

INSERT INTO #quality_results
VALUES
(
    'item_projected_revenue_reconciliation',
    CASE
        WHEN ABS(
            @item_projected_revenue
            - @order_projected_revenue
        ) <= 0.01
        THEN 0
        ELSE 1
    END,
    @item_projected_revenue,
    @order_projected_revenue,
    N'Item projected revenue must reconcile to orders.'
),
(
    'item_recognized_revenue_reconciliation',
    CASE
        WHEN ABS(
            @item_recognized_revenue
            - @order_recognized_revenue
        ) <= 0.01
        THEN 0
        ELSE 1
    END,
    @item_recognized_revenue,
    @order_recognized_revenue,
    N'Item recognized revenue must reconcile to orders.'
),
(
    'product_ad_cost_reconciliation',
    CASE
        WHEN ABS(
            @product_actual_cost - @ad_actual_cost
        ) <= 0.01
        THEN 0
        ELSE 1
    END,
    @product_actual_cost,
    @ad_actual_cost,
    N'Allocated product ad cost must reconcile to ad facts.'
),
(
    'product_projected_profit_reconciliation',
    CASE
        WHEN ABS(
            @product_projected_after_ads
            - @ad_projected_after_ads
        ) <= 0.01
        THEN 0
        ELSE 1
    END,
    @product_projected_after_ads,
    @ad_projected_after_ads,
    N'Product projected contribution must reconcile to ads.'
),
(
    'product_recognized_profit_reconciliation',
    CASE
        WHEN ABS(
            @product_recognized_after_ads
            - @ad_recognized_after_ads
        ) <= 0.01
        THEN 0
        ELSE 1
    END,
    @product_recognized_after_ads,
    @ad_recognized_after_ads,
    N'Product recognized contribution must reconcile to ads.'
);

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'out_of_scope_recognized_revenue',
    COUNT_BIG(*),
    N'Out-of-scope orders must not have recognized revenue.'
FROM mart.order_economics AS economics
INNER JOIN mart.order_scope_assignments AS assignment
    ON assignment.shop_id = economics.shop_id
   AND assignment.order_id = economics.order_id
WHERE assignment.is_in_scope = 0
  AND COALESCE(economics.recognized_total_revenue, 0) <> 0;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'order_date_dimension_coverage',
    COUNT_BIG(*),
    N'Every order date must exist in the date dimension.'
FROM mart.order_economics AS economics
LEFT JOIN mart.dim_date AS date_dimension
    ON date_dimension.full_date = economics.order_date
WHERE date_dimension.date_key IS NULL;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'ad_date_dimension_coverage',
    COUNT_BIG(*),
    N'Every ad fact date must exist in the date dimension.'
FROM mart.ad_economics_daily AS economics
LEFT JOIN mart.dim_date AS date_dimension
    ON date_dimension.full_date = economics.analysis_date
WHERE date_dimension.date_key IS NULL;

INSERT INTO #quality_results (
    check_name,
    failure_count,
    check_detail
)
SELECT
    'product_date_dimension_coverage',
    COUNT_BIG(*),
    N'Every product-ad date must exist in the date dimension.'
FROM mart.product_ad_economics_daily AS economics
LEFT JOIN mart.dim_date AS date_dimension
    ON date_dimension.full_date = economics.analysis_date
WHERE date_dimension.date_key IS NULL;

SELECT
    check_name,
    failure_count,
    actual_value,
    expected_value,
    CASE
        WHEN failure_count = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status,
    check_detail
FROM #quality_results
ORDER BY check_name;
