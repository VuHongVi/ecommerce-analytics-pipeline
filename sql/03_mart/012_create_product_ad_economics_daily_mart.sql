SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'mart.product_ad_economics_daily',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE mart.product_ad_economics_daily (
            analysis_date DATE NOT NULL,
            ad_key BIGINT NOT NULL,
            product_key BIGINT NOT NULL,

            daily_presence_status VARCHAR(40) NOT NULL,
            ad_cost_allocation_method VARCHAR(40) NOT NULL,
            has_meta_insight BIT NOT NULL,
            has_product_orders BIT NOT NULL,
            has_allocated_ad_cost BIT NOT NULL,
            ad_cost_allocation_weight
                DECIMAL(19, 12) NOT NULL,

            product_order_count INT NOT NULL,
            item_line_count INT NOT NULL,
            total_quantity BIGINT NOT NULL,
            finalized_product_order_count INT NOT NULL,
            delivered_product_order_count INT NOT NULL,
            returned_product_order_count INT NOT NULL,
            canceled_product_order_count INT NOT NULL,
            returning_product_order_count INT NOT NULL,
            in_progress_product_order_count INT NOT NULL,
            product_orders_with_estimated_cost INT NOT NULL,
            product_orders_with_missing_cost INT NOT NULL,

            allocated_source_product_revenue
                DECIMAL(19, 2) NOT NULL,
            projected_total_revenue DECIMAL(19, 2) NOT NULL,
            projected_cogs DECIMAL(19, 2) NOT NULL,
            projected_shipping_cost DECIMAL(19, 2) NOT NULL,
            projected_contribution_before_ads
                DECIMAL(19, 2) NOT NULL,
            recognized_total_revenue DECIMAL(19, 2) NOT NULL,
            recognized_cogs DECIMAL(19, 2) NOT NULL,
            recognized_shipping_cost DECIMAL(19, 2) NOT NULL,
            recognized_contribution_before_ads
                DECIMAL(19, 2) NOT NULL,

            allocated_meta_spend DECIMAL(19, 6) NOT NULL,
            allocated_meta_tax_amount DECIMAL(19, 6) NOT NULL,
            allocated_actual_ad_cost DECIMAL(19, 6) NOT NULL,
            projected_contribution_after_ads
                DECIMAL(19, 6) NOT NULL,
            recognized_contribution_after_ads
                DECIMAL(19, 6) NOT NULL,

            mart_refreshed_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_product_ad_economics_refreshed
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_product_ad_economics_daily
                PRIMARY KEY CLUSTERED (
                    analysis_date,
                    ad_key,
                    product_key
                ),
            CONSTRAINT FK_product_ad_economics_ad
                FOREIGN KEY (ad_key)
                REFERENCES mart.dim_meta_ads (ad_key),
            CONSTRAINT FK_product_ad_economics_product
                FOREIGN KEY (product_key)
                REFERENCES mart.dim_products (product_key),
            CONSTRAINT CK_product_ad_economics_presence
                CHECK (
                    (
                        daily_presence_status =
                            'META_AND_PRODUCT_ORDER'
                        AND has_meta_insight = 1
                        AND has_product_orders = 1
                    )
                    OR (
                        daily_presence_status =
                            'META_ONLY_UNATTRIBUTED'
                        AND has_meta_insight = 1
                        AND has_product_orders = 0
                    )
                    OR (
                        daily_presence_status =
                            'ORDER_ONLY_PRODUCT'
                        AND has_meta_insight = 0
                        AND has_product_orders = 1
                    )
                ),
            CONSTRAINT CK_product_ad_economics_method
                CHECK (
                    ad_cost_allocation_method IN (
                        'SOURCE_REVENUE_SHARE',
                        'UNATTRIBUTED_NO_BASIS',
                        'NO_META_COST'
                    )
                ),
            CONSTRAINT CK_product_ad_economics_values
                CHECK (
                    ad_cost_allocation_weight >= 0
                    AND ad_cost_allocation_weight <= 1
                    AND product_order_count >= 0
                    AND item_line_count >= 0
                    AND total_quantity >= 0
                    AND allocated_meta_spend >= 0
                    AND allocated_meta_tax_amount >= 0
                    AND allocated_actual_ad_cost >= 0
                ),
            CONSTRAINT CK_product_ad_economics_ad_formula
                CHECK (
                    allocated_actual_ad_cost =
                        allocated_meta_spend
                        + allocated_meta_tax_amount
                ),
            CONSTRAINT CK_product_ad_economics_projected_formula
                CHECK (
                    projected_contribution_before_ads =
                        projected_total_revenue
                        - projected_cogs
                        - projected_shipping_cost
                    AND projected_contribution_after_ads =
                        projected_contribution_before_ads
                        - allocated_actual_ad_cost
                ),
            CONSTRAINT CK_product_ad_economics_recognized_formula
                CHECK (
                    recognized_contribution_before_ads =
                        recognized_total_revenue
                        - recognized_cogs
                        - recognized_shipping_cost
                    AND recognized_contribution_after_ads =
                        recognized_contribution_before_ads
                        - allocated_actual_ad_cost
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_product_ad_economics_product_date'
          AND object_id = OBJECT_ID(
              N'mart.product_ad_economics_daily'
          )
    )
    BEGIN
        CREATE INDEX IX_product_ad_economics_product_date
            ON mart.product_ad_economics_daily (
                product_key,
                analysis_date
            )
            INCLUDE (
                ad_key,
                product_order_count,
                total_quantity,
                projected_total_revenue,
                allocated_actual_ad_cost,
                projected_contribution_after_ads,
                recognized_contribution_after_ads
            );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_product_ad_economics_ad_date'
          AND object_id = OBJECT_ID(
              N'mart.product_ad_economics_daily'
          )
    )
    BEGIN
        CREATE INDEX IX_product_ad_economics_ad_date
            ON mart.product_ad_economics_daily (
                ad_key,
                analysis_date
            )
            INCLUDE (
                product_key,
                allocated_source_product_revenue,
                allocated_actual_ad_cost,
                projected_contribution_after_ads
            );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
