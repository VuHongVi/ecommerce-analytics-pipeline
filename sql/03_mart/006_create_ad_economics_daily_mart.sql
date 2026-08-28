SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'mart.ad_economics_daily',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE mart.ad_economics_daily (
            analysis_date DATE NOT NULL,
            ad_key BIGINT NOT NULL,

            daily_presence_status VARCHAR(30) NOT NULL,
            has_meta_insight BIT NOT NULL,
            has_orders BIT NOT NULL,

            source_raw_insight_version_id BIGINT NULL,
            source_meta_extracted_at_utc DATETIME2(3) NULL,

            currency VARCHAR(10) NULL,
            tax_rate DECIMAL(9, 6) NOT NULL,

            impressions BIGINT NOT NULL,
            reach BIGINT NOT NULL,
            clicks BIGINT NOT NULL,
            inline_link_clicks BIGINT NOT NULL,

            meta_spend DECIMAL(19, 6) NOT NULL,
            meta_tax_amount DECIMAL(19, 6) NOT NULL,
            actual_ad_cost DECIMAL(19, 6) NOT NULL,

            order_count INT NOT NULL,
            finalized_order_count INT NOT NULL,
            delivered_order_count INT NOT NULL,
            returned_order_count INT NOT NULL,
            canceled_order_count INT NOT NULL,
            returning_order_count INT NOT NULL,
            in_progress_order_count INT NOT NULL,

            total_quantity BIGINT NOT NULL,
            orders_with_estimated_cost INT NOT NULL,
            orders_with_missing_cost INT NOT NULL,

            projected_total_revenue DECIMAL(19, 2) NOT NULL,
            projected_cogs DECIMAL(19, 2) NOT NULL,
            projected_shipping_cost DECIMAL(19, 2) NOT NULL,
            projected_contribution_before_ads
                DECIMAL(19, 2) NOT NULL,
            projected_contribution_after_ads
                DECIMAL(19, 6) NOT NULL,

            recognized_total_revenue DECIMAL(19, 2) NOT NULL,
            recognized_cogs DECIMAL(19, 2) NOT NULL,
            recognized_shipping_cost DECIMAL(19, 2) NOT NULL,
            recognized_contribution_before_ads
                DECIMAL(19, 2) NOT NULL,
            recognized_contribution_after_ads
                DECIMAL(19, 6) NOT NULL,

            mart_refreshed_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_ad_economics_daily_refreshed
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_ad_economics_daily
                PRIMARY KEY CLUSTERED (
                    analysis_date,
                    ad_key
                ),

            CONSTRAINT FK_ad_economics_daily_ad
                FOREIGN KEY (ad_key)
                REFERENCES mart.dim_meta_ads (ad_key),

            CONSTRAINT CK_ad_economics_daily_presence
                CHECK (
                    (
                        daily_presence_status =
                            'META_AND_ORDER'
                        AND has_meta_insight = 1
                        AND has_orders = 1
                    )
                    OR (
                        daily_presence_status =
                            'META_ONLY'
                        AND has_meta_insight = 1
                        AND has_orders = 0
                    )
                    OR (
                        daily_presence_status =
                            'ORDER_ONLY'
                        AND has_meta_insight = 0
                        AND has_orders = 1
                    )
                ),

            CONSTRAINT CK_ad_economics_daily_costs
                CHECK (
                    tax_rate >= 0
                    AND tax_rate <= 1
                    AND meta_spend >= 0
                    AND meta_tax_amount >= 0
                    AND actual_ad_cost >= 0
                ),

            CONSTRAINT CK_ad_economics_daily_counts
                CHECK (
                    order_count >= 0
                    AND finalized_order_count >= 0
                    AND delivered_order_count >= 0
                    AND returned_order_count >= 0
                    AND canceled_order_count >= 0
                    AND returning_order_count >= 0
                    AND in_progress_order_count >= 0
                    AND total_quantity >= 0
                    AND orders_with_estimated_cost >= 0
                    AND orders_with_missing_cost >= 0
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_ad_economics_daily_ad_date'
          AND object_id = OBJECT_ID(
              N'mart.ad_economics_daily'
          )
    )
    BEGIN
        CREATE INDEX IX_ad_economics_daily_ad_date
            ON mart.ad_economics_daily (
                ad_key,
                analysis_date
            )
            INCLUDE (
                actual_ad_cost,
                order_count,
                projected_total_revenue,
                recognized_total_revenue,
                projected_contribution_after_ads,
                recognized_contribution_after_ads
            );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_ad_economics_daily_presence_date'
          AND object_id = OBJECT_ID(
              N'mart.ad_economics_daily'
          )
    )
    BEGIN
        CREATE INDEX
            IX_ad_economics_daily_presence_date
        ON mart.ad_economics_daily (
            daily_presence_status,
            analysis_date
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
