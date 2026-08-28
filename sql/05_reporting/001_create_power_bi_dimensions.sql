SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'reporting') IS NULL
    BEGIN
        EXEC(N'CREATE SCHEMA reporting;');
    END;

    EXEC(N'
        CREATE OR ALTER VIEW reporting.dim_date
        AS
        SELECT
            dates.date_key,
            dates.full_date,
            dates.calendar_year,
            dates.calendar_quarter,
            dates.quarter_label,
            dates.month_number,
            dates.month_name_en,
            dates.month_name_vi,
            dates.year_month_key,
            dates.year_month_label,
            dates.iso_week_number,
            dates.day_of_year,
            dates.day_of_month,
            dates.iso_day_of_week,
            dates.day_name_en,
            dates.day_name_vi,
            dates.week_start_date,
            dates.week_end_date,
            dates.month_start_date,
            dates.month_end_date,
            dates.quarter_start_date,
            dates.quarter_end_date,
            dates.year_start_date,
            dates.year_end_date,
            dates.is_weekend,
            dates.is_month_end,
            dates.is_quarter_end,
            dates.is_year_end
        FROM mart.dim_date AS dates;
    ');

    EXEC(N'
        CREATE OR ALTER VIEW reporting.dim_ads
        AS
        SELECT
            ads.ad_key,
            ads.ad_id,
            ads.mapping_status,
            ads.is_meta_mapped,
            ads.is_special_member,
            ads.account_object_id,
            ads.account_id,
            ads.account_name,
            ads.account_status,
            ads.currency,
            ads.timezone_name,
            ads.campaign_id,
            ads.campaign_name,
            ads.adset_id,
            ads.adset_name,
            ads.ad_name,
            ads.objective,
            ads.optimization_goal,
            ads.first_insight_date,
            ads.last_insight_date
        FROM mart.dim_meta_ads AS ads;
    ');

    EXEC(N'
        CREATE OR ALTER VIEW reporting.dim_products
        AS
        SELECT
            products.product_key,
            products.product_natural_key,
            products.internal_product_id,
            products.mapping_status,
            products.is_product_mapped,
            products.is_special_member,
            products.canonical_product_name,
            products.normalized_product_name,
            products.is_active
        FROM mart.dim_products AS products;
    ');

    COMMIT TRANSACTION;

    SELECT
        (SELECT COUNT(*) FROM reporting.dim_date)
            AS date_rows,
        (SELECT COUNT(*) FROM reporting.dim_ads)
            AS ad_rows,
        (SELECT COUNT(*) FROM reporting.dim_products)
            AS product_rows;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
