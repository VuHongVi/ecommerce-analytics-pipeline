SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'mart.order_item_economics', N'U') IS NULL
    BEGIN
        CREATE TABLE mart.order_item_economics (
            shop_id NVARCHAR(100) NOT NULL,
            order_id NVARCHAR(100) NOT NULL,
            source_item_id BIGINT NOT NULL,

            product_key BIGINT NOT NULL,
            ad_key BIGINT NOT NULL,
            order_date DATE NOT NULL,

            item_attribution_status VARCHAR(30) NOT NULL,
            allocation_method VARCHAR(40) NOT NULL,
            economic_status VARCHAR(30) NOT NULL,
            is_finalized BIT NOT NULL,

            source_raw_order_version_id BIGINT NOT NULL,
            source_product_id NVARCHAR(100) NULL,
            source_variation_id NVARCHAR(100) NULL,

            quantity INT NOT NULL,
            unit_retail_price DECIMAL(19, 2) NULL,
            gross_line_revenue DECIMAL(19, 2) NOT NULL,
            order_gross_item_revenue DECIMAL(19, 2) NOT NULL,
            order_source_product_revenue DECIMAL(19, 2) NOT NULL,
            revenue_allocation_weight DECIMAL(19, 12) NOT NULL,
            allocated_source_product_revenue
                DECIMAL(19, 2) NOT NULL,
            allocated_discount_adjustment
                DECIMAL(19, 2) NOT NULL,

            resolved_unit_cost DECIMAL(19, 2) NULL,
            source_line_product_cost DECIMAL(19, 2) NULL,
            cost_source VARCHAR(30) NULL,
            is_estimated_cost BIT NOT NULL,
            is_missing_cost BIT NOT NULL,

            projected_total_revenue DECIMAL(19, 2) NOT NULL,
            projected_cogs DECIMAL(19, 2) NOT NULL,
            projected_shipping_cost DECIMAL(19, 2) NOT NULL,
            projected_contribution_before_ads
                DECIMAL(19, 2) NOT NULL,

            recognized_total_revenue DECIMAL(19, 2) NULL,
            recognized_cogs DECIMAL(19, 2) NULL,
            recognized_shipping_cost DECIMAL(19, 2) NULL,
            recognized_contribution_before_ads
                DECIMAL(19, 2) NULL,

            mart_refreshed_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_order_item_economics_refreshed
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_order_item_economics
                PRIMARY KEY CLUSTERED (
                    shop_id,
                    order_id,
                    source_item_id
                ),
            CONSTRAINT FK_order_item_economics_product
                FOREIGN KEY (product_key)
                REFERENCES mart.dim_products (product_key),
            CONSTRAINT FK_order_item_economics_ad
                FOREIGN KEY (ad_key)
                REFERENCES mart.dim_meta_ads (ad_key),
            CONSTRAINT CK_order_item_economics_attribution
                CHECK (
                    (
                        item_attribution_status = 'ITEM_MAPPED'
                        AND source_item_id >= 0
                    )
                    OR (
                        item_attribution_status =
                            'UNATTRIBUTED_PRODUCT'
                        AND source_item_id = -1
                    )
                ),
            CONSTRAINT CK_order_item_economics_method
                CHECK (
                    allocation_method IN (
                        'GROSS_REVENUE_SHARE',
                        'EQUAL_SHARE_ZERO_GROSS',
                        'UNATTRIBUTED_ORDER'
                    )
                ),
            CONSTRAINT CK_order_item_economics_status
                CHECK (
                    economic_status IN (
                        'FINAL_DELIVERED',
                        'FINAL_RETURNED',
                        'FINAL_CANCELED',
                        'PROVISIONAL_RETURNING',
                        'IN_PROGRESS'
                    )
                ),
            CONSTRAINT CK_order_item_economics_values
                CHECK (
                    quantity >= 0
                    AND gross_line_revenue >= 0
                    AND order_gross_item_revenue >= 0
                    AND revenue_allocation_weight >= 0
                    AND revenue_allocation_weight <= 1
                    AND projected_cogs >= 0
                    AND projected_shipping_cost >= 0
                ),
            CONSTRAINT CK_order_item_economics_recognition
                CHECK (
                    (
                        is_finalized = 0
                        AND recognized_total_revenue IS NULL
                        AND recognized_cogs IS NULL
                        AND recognized_shipping_cost IS NULL
                        AND recognized_contribution_before_ads
                            IS NULL
                    )
                    OR (
                        is_finalized = 1
                        AND recognized_total_revenue IS NOT NULL
                        AND recognized_cogs IS NOT NULL
                        AND recognized_shipping_cost IS NOT NULL
                        AND recognized_contribution_before_ads
                            IS NOT NULL
                    )
                ),
            CONSTRAINT CK_order_item_economics_projected_formula
                CHECK (
                    projected_contribution_before_ads =
                        projected_total_revenue
                        - projected_cogs
                        - projected_shipping_cost
                ),
            CONSTRAINT CK_order_item_economics_recognized_formula
                CHECK (
                    is_finalized = 0
                    OR recognized_contribution_before_ads =
                        recognized_total_revenue
                        - recognized_cogs
                        - recognized_shipping_cost
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_order_item_economics_product_date'
          AND object_id = OBJECT_ID(
              N'mart.order_item_economics'
          )
    )
    BEGIN
        CREATE INDEX IX_order_item_economics_product_date
            ON mart.order_item_economics (
                product_key,
                order_date
            )
            INCLUDE (
                ad_key,
                quantity,
                projected_total_revenue,
                projected_cogs,
                projected_shipping_cost,
                projected_contribution_before_ads,
                recognized_total_revenue,
                recognized_contribution_before_ads
            );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_order_item_economics_ad_date'
          AND object_id = OBJECT_ID(
              N'mart.order_item_economics'
          )
    )
    BEGIN
        CREATE INDEX IX_order_item_economics_ad_date
            ON mart.order_item_economics (
                ad_key,
                order_date
            )
            INCLUDE (
                product_key,
                allocated_source_product_revenue,
                projected_contribution_before_ads,
                recognized_contribution_before_ads
            );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
