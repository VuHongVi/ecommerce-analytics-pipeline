SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'stg.product_registry',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE stg.product_registry (
            internal_product_id BIGINT
                IDENTITY(1, 1) NOT NULL,
            normalized_product_name NVARCHAR(400)
                NOT NULL,
            canonical_product_name NVARCHAR(500)
                NOT NULL,
            first_seen_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_product_first_seen
                DEFAULT SYSUTCDATETIME(),
            last_seen_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_product_last_seen
                DEFAULT SYSUTCDATETIME(),
            is_active BIT
                NOT NULL
                CONSTRAINT DF_product_is_active
                DEFAULT 1,

            CONSTRAINT PK_product_registry
                PRIMARY KEY (internal_product_id),

            CONSTRAINT UQ_product_normalized_name
                UNIQUE (normalized_product_name)
        );
    END;

    IF OBJECT_ID(
        N'stg.pancake_orders',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE stg.pancake_orders (
            shop_id NVARCHAR(100) NOT NULL,
            order_id NVARCHAR(100) NOT NULL,
            system_id NVARCHAR(100) NULL,

            source_raw_order_version_id BIGINT NOT NULL,
            source_inserted_at DATETIME2(3) NOT NULL,
            source_updated_at DATETIME2(3) NOT NULL,

            source_status INT NULL,
            status_name NVARCHAR(100) NULL,
            sub_status INT NULL,

            is_cancelled BIT NOT NULL,
            is_delivered BIT NOT NULL,
            is_returning BIT NOT NULL,
            is_returned BIT NOT NULL,

            page_id NVARCHAR(100) NULL,
            page_name NVARCHAR(500) NULL,
            ad_id NVARCHAR(100) NULL,
            post_id NVARCHAR(200) NULL,
            ads_source NVARCHAR(200) NULL,
            order_source_name NVARCHAR(200) NULL,

            utm_campaign NVARCHAR(500) NULL,
            utm_content NVARCHAR(500) NULL,
            utm_id NVARCHAR(500) NULL,
            utm_medium NVARCHAR(500) NULL,
            utm_source NVARCHAR(500) NULL,
            utm_term NVARCHAR(500) NULL,

            total_price DECIMAL(19, 2) NULL,
            total_price_after_discount
                DECIMAL(19, 2) NULL,
            buyer_total_amount DECIMAL(19, 2) NULL,
            total_quantity INT NULL,
            total_discount DECIMAL(19, 2) NULL,

            customer_shipping_fee
                DECIMAL(19, 2) NULL,
            partner_fee DECIMAL(19, 2) NULL,
            surcharge DECIMAL(19, 2) NULL,
            advanced_platform_fee
                DECIMAL(19, 2) NULL,
            marketplace_fee DECIMAL(19, 2) NULL,
            customer_pay_fee DECIMAL(19, 2) NULL,
            source_return_fee_flag BIT NULL,
            source_tax DECIMAL(19, 2) NULL,

            cod DECIMAL(19, 2) NULL,
            money_to_collect DECIMAL(19, 2) NULL,
            prepaid DECIMAL(19, 2) NULL,
            cash DECIMAL(19, 2) NULL,
            transfer_money DECIMAL(19, 2) NULL,

            shipping_partner_name NVARCHAR(200) NULL,
            shipping_partner_status
                NVARCHAR(100) NULL,
            tracking_code NVARCHAR(200) NULL,
            partner_total_fee DECIMAL(19, 2) NULL,

            picked_up_at DATETIME2(3) NULL,
            first_delivery_at DATETIME2(3) NULL,
            first_undeliverable_at
                DATETIME2(3) NULL,

            province_id NVARCHAR(100) NULL,
            province_name NVARCHAR(200) NULL,
            district_id NVARCHAR(100) NULL,
            district_name NVARCHAR(200) NULL,
            commune_id NVARCHAR(100) NULL,
            commune_name NVARCHAR(200) NULL,

            creator_id NVARCHAR(100) NULL,
            creator_name NVARCHAR(300) NULL,
            assigning_seller_id NVARCHAR(100) NULL,
            assigning_seller_name NVARCHAR(300) NULL,

            payload_hash BINARY(32) NOT NULL,
            staged_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_stg_order_staged_at
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_stg_pancake_orders
                PRIMARY KEY (shop_id, order_id),

            CONSTRAINT FK_stg_order_raw_version
                FOREIGN KEY (
                    source_raw_order_version_id
                )
                REFERENCES raw.pancake_order_versions (
                    raw_order_version_id
                )
        );
    END;

    IF OBJECT_ID(
        N'stg.pancake_order_items',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE stg.pancake_order_items (
            shop_id NVARCHAR(100) NOT NULL,
            order_id NVARCHAR(100) NOT NULL,
            source_item_id BIGINT NOT NULL,

            source_raw_order_version_id BIGINT NOT NULL,
            source_product_id NVARCHAR(100) NULL,
            source_variation_id NVARCHAR(100) NULL,

            internal_product_id BIGINT NOT NULL,
            product_name NVARCHAR(500) NOT NULL,
            normalized_product_name NVARCHAR(400)
                NOT NULL,

            quantity INT NOT NULL,
            unit_retail_price DECIMAL(19, 2) NULL,
            original_retail_price DECIMAL(19, 2) NULL,
            exact_price DECIMAL(19, 2) NULL,
            discount_each_product
                DECIMAL(19, 2) NULL,
            total_discount DECIMAL(19, 2) NULL,

            source_last_imported_price
                DECIMAL(19, 2) NULL,
            source_average_price
                DECIMAL(19, 2) NULL,

            return_quantity INT NULL,
            returning_quantity INT NULL,
            returned_count INT NULL,
            exchange_count INT NULL,

            is_bonus_product BIT NULL,
            is_composite BIT NULL,
            composite_item_id BIGINT NULL,
            components_json NVARCHAR(MAX) NULL,
            is_wholesale BIT NULL,
            weight DECIMAL(19, 6) NULL,

            staged_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_stg_item_staged_at
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_stg_pancake_order_items
                PRIMARY KEY (
                    shop_id,
                    order_id,
                    source_item_id
                ),

            CONSTRAINT FK_stg_item_order
                FOREIGN KEY (shop_id, order_id)
                REFERENCES stg.pancake_orders (
                    shop_id,
                    order_id
                ),

            CONSTRAINT FK_stg_item_product
                FOREIGN KEY (internal_product_id)
                REFERENCES stg.product_registry (
                    internal_product_id
                ),

            CONSTRAINT FK_stg_item_raw_version
                FOREIGN KEY (
                    source_raw_order_version_id
                )
                REFERENCES raw.pancake_order_versions (
                    raw_order_version_id
                ),

            CONSTRAINT CK_stg_item_components_json
                CHECK (
                    components_json IS NULL
                    OR ISJSON(components_json) = 1
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_stg_orders_inserted_status'
          AND object_id = OBJECT_ID(
              N'stg.pancake_orders'
          )
    )
    BEGIN
        CREATE INDEX IX_stg_orders_inserted_status
            ON stg.pancake_orders (
                source_inserted_at,
                source_status
            );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_stg_orders_ad_id'
          AND object_id = OBJECT_ID(
              N'stg.pancake_orders'
          )
    )
    BEGIN
        CREATE INDEX IX_stg_orders_ad_id
            ON stg.pancake_orders (ad_id)
            WHERE ad_id IS NOT NULL;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_stg_items_product'
          AND object_id = OBJECT_ID(
              N'stg.pancake_order_items'
          )
    )
    BEGIN
        CREATE INDEX IX_stg_items_product
            ON stg.pancake_order_items (
                internal_product_id,
                shop_id,
                order_id
            );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;