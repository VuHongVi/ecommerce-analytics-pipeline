SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'mart') IS NULL
    BEGIN
        EXEC(N'CREATE SCHEMA mart;');
    END;

    IF OBJECT_ID(
        N'mart.order_economics',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE mart.order_economics (
            shop_id NVARCHAR(100) NOT NULL,
            order_id NVARCHAR(100) NOT NULL,

            source_raw_order_version_id BIGINT NOT NULL,
            source_inserted_at DATETIME2(3) NOT NULL,
            source_updated_at DATETIME2(3) NOT NULL,
            order_date DATE NOT NULL,

            source_status INT NOT NULL,
            status_name NVARCHAR(100) NULL,
            economic_status VARCHAR(30) NOT NULL,
            is_finalized BIT NOT NULL,

            is_cancelled BIT NOT NULL,
            is_delivered BIT NOT NULL,
            is_returning BIT NOT NULL,
            is_returned BIT NOT NULL,

            page_id NVARCHAR(100) NULL,
            page_name NVARCHAR(500) NULL,
            ad_id NVARCHAR(100) NULL,
            post_id NVARCHAR(100) NULL,
            ads_source NVARCHAR(500) NULL,
            order_source_name NVARCHAR(500) NULL,

            utm_campaign NVARCHAR(500) NULL,
            utm_content NVARCHAR(500) NULL,
            utm_id NVARCHAR(500) NULL,
            utm_medium NVARCHAR(500) NULL,
            utm_source NVARCHAR(500) NULL,
            utm_term NVARCHAR(500) NULL,

            shipping_partner_name NVARCHAR(500) NULL,

            item_line_count INT NOT NULL,
            total_quantity INT NOT NULL,

            history_cost_line_count INT NOT NULL,
            fallback_cost_line_count INT NOT NULL,
            estimated_cost_line_count INT NOT NULL,
            missing_cost_line_count INT NOT NULL,

            has_estimated_cost BIT NOT NULL,
            has_missing_cost BIT NOT NULL,

            source_total_price DECIMAL(19, 2) NULL,
            source_total_price_after_discount
                DECIMAL(19, 2) NULL,
            source_buyer_total_amount
                DECIMAL(19, 2) NULL,
            source_customer_shipping_fee
                DECIMAL(19, 2) NULL,
            source_partner_fee DECIMAL(19, 2) NULL,
            source_partner_total_fee
                DECIMAL(19, 2) NULL,
            source_surcharge DECIMAL(19, 2) NULL,
            source_advanced_platform_fee
                DECIMAL(19, 2) NULL,
            source_marketplace_fee
                DECIMAL(19, 2) NULL,
            source_customer_pay_fee
                DECIMAL(19, 2) NULL,

            resolved_product_cost
                DECIMAL(19, 2) NOT NULL,
            base_shipping_cost
                DECIMAL(19, 2) NOT NULL,
            applied_return_surcharge
                DECIMAL(19, 2) NOT NULL,

            projected_product_revenue
                DECIMAL(19, 2) NOT NULL,
            projected_shipping_revenue
                DECIMAL(19, 2) NOT NULL,
            projected_total_revenue
                DECIMAL(19, 2) NOT NULL,
            projected_cogs
                DECIMAL(19, 2) NOT NULL,
            projected_shipping_cost
                DECIMAL(19, 2) NOT NULL,
            projected_contribution_profit
                DECIMAL(19, 2) NOT NULL,

            recognized_product_revenue
                DECIMAL(19, 2) NULL,
            recognized_shipping_revenue
                DECIMAL(19, 2) NULL,
            recognized_total_revenue
                DECIMAL(19, 2) NULL,
            recognized_cogs
                DECIMAL(19, 2) NULL,
            recognized_shipping_cost
                DECIMAL(19, 2) NULL,
            recognized_contribution_profit
                DECIMAL(19, 2) NULL,

            mart_refreshed_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_mart_order_economics_refreshed
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_mart_order_economics
                PRIMARY KEY (shop_id, order_id),

            CONSTRAINT CK_mart_order_economics_status
                CHECK (
                    economic_status IN (
                        'FINAL_DELIVERED',
                        'FINAL_RETURNED',
                        'FINAL_CANCELED',
                        'PROVISIONAL_RETURNING',
                        'IN_PROGRESS'
                    )
                ),

            CONSTRAINT CK_mart_order_economics_finalized
                CHECK (
                    (
                        economic_status IN (
                            'FINAL_DELIVERED',
                            'FINAL_RETURNED',
                            'FINAL_CANCELED'
                        )
                        AND is_finalized = 1
                    )
                    OR
                    (
                        economic_status IN (
                            'PROVISIONAL_RETURNING',
                            'IN_PROGRESS'
                        )
                        AND is_finalized = 0
                    )
                ),

            CONSTRAINT CK_mart_order_economics_counts
                CHECK (
                    item_line_count >= 0
                    AND total_quantity >= 0
                    AND history_cost_line_count >= 0
                    AND fallback_cost_line_count >= 0
                    AND estimated_cost_line_count >= 0
                    AND missing_cost_line_count >= 0
                ),

            CONSTRAINT CK_mart_order_economics_recognition
                CHECK (
                    (
                        is_finalized = 0
                        AND recognized_product_revenue IS NULL
                        AND recognized_shipping_revenue IS NULL
                        AND recognized_total_revenue IS NULL
                        AND recognized_cogs IS NULL
                        AND recognized_shipping_cost IS NULL
                        AND recognized_contribution_profit IS NULL
                    )
                    OR
                    (
                        is_finalized = 1
                        AND recognized_product_revenue IS NOT NULL
                        AND recognized_shipping_revenue IS NOT NULL
                        AND recognized_total_revenue IS NOT NULL
                        AND recognized_cogs IS NOT NULL
                        AND recognized_shipping_cost IS NOT NULL
                        AND recognized_contribution_profit IS NOT NULL
                    )
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_mart_order_economics_date_status'
          AND object_id = OBJECT_ID(
              N'mart.order_economics'
          )
    )
    BEGIN
        CREATE INDEX
            IX_mart_order_economics_date_status
        ON mart.order_economics (
            order_date,
            economic_status
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_mart_order_economics_ad_date'
          AND object_id = OBJECT_ID(
              N'mart.order_economics'
          )
    )
    BEGIN
        CREATE INDEX
            IX_mart_order_economics_ad_date
        ON mart.order_economics (
            ad_id,
            order_date
        )
        WHERE ad_id IS NOT NULL;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_mart_order_economics_carrier_status'
          AND object_id = OBJECT_ID(
              N'mart.order_economics'
          )
    )
    BEGIN
        CREATE INDEX
            IX_mart_order_economics_carrier_status
        ON mart.order_economics (
            shipping_partner_name,
            economic_status
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;