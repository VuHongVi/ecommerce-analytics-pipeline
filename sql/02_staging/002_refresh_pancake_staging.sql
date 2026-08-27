CREATE OR ALTER PROCEDURE stg.refresh_pancake_staging
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        ;WITH ranked_orders AS (
            SELECT
                raw_order_version_id,
                shop_id,
                order_id,
                system_id,
                source_inserted_at,
                source_updated_at,
                payload_hash,
                payload_json,
                ROW_NUMBER() OVER (
                    PARTITION BY shop_id, order_id
                    ORDER BY
                        source_updated_at DESC,
                        raw_order_version_id DESC
                ) AS row_number
            FROM raw.pancake_order_versions
        )
        SELECT
            raw_order_version_id,
            shop_id,
            order_id,
            system_id,
            source_inserted_at,
            source_updated_at,
            payload_hash,
            payload_json
        INTO #latest_orders
        FROM ranked_orders
        WHERE row_number = 1;

        CREATE UNIQUE CLUSTERED INDEX
            IX_latest_orders
        ON #latest_orders (shop_id, order_id);

        SELECT
            source.shop_id,
            source.order_id,
            source.system_id,
            source.raw_order_version_id
                AS source_raw_order_version_id,
            source.source_inserted_at,
            source.source_updated_at,

            TRY_CONVERT(
                INT,
                JSON_VALUE(
                    source.payload_json,
                    '$.status'
                )
            ) AS source_status,

            TRY_CONVERT(
                NVARCHAR(100),
                JSON_VALUE(
                    source.payload_json,
                    '$.status_name'
                )
            ) AS status_name,

            TRY_CONVERT(
                INT,
                JSON_VALUE(
                    source.payload_json,
                    '$.sub_status'
                )
            ) AS sub_status,

            CAST(
                CASE
                    WHEN TRY_CONVERT(
                        INT,
                        JSON_VALUE(
                            source.payload_json,
                            '$.status'
                        )
                    ) = 6
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS is_cancelled,

            CAST(
                CASE
                    WHEN TRY_CONVERT(
                        INT,
                        JSON_VALUE(
                            source.payload_json,
                            '$.status'
                        )
                    ) = 3
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS is_delivered,

            CAST(
                CASE
                    WHEN TRY_CONVERT(
                        INT,
                        JSON_VALUE(
                            source.payload_json,
                            '$.status'
                        )
                    ) = 4
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS is_returning,

            CAST(
                CASE
                    WHEN TRY_CONVERT(
                        INT,
                        JSON_VALUE(
                            source.payload_json,
                            '$.status'
                        )
                    ) = 5
                    THEN 1
                    ELSE 0
                END
                AS BIT
            ) AS is_returned,

            JSON_VALUE(
                source.payload_json,
                '$.page_id'
            ) AS page_id,

            JSON_VALUE(
                source.payload_json,
                '$.page.name'
            ) AS page_name,

            JSON_VALUE(
                source.payload_json,
                '$.ad_id'
            ) AS ad_id,

            JSON_VALUE(
                source.payload_json,
                '$.post_id'
            ) AS post_id,

            JSON_VALUE(
                source.payload_json,
                '$.ads_source'
            ) AS ads_source,

            JSON_VALUE(
                source.payload_json,
                '$.order_sources_name'
            ) AS order_source_name,

            JSON_VALUE(
                source.payload_json,
                '$.p_utm_campaign'
            ) AS utm_campaign,

            JSON_VALUE(
                source.payload_json,
                '$.p_utm_content'
            ) AS utm_content,

            JSON_VALUE(
                source.payload_json,
                '$.p_utm_id'
            ) AS utm_id,

            JSON_VALUE(
                source.payload_json,
                '$.p_utm_medium'
            ) AS utm_medium,

            JSON_VALUE(
                source.payload_json,
                '$.p_utm_source'
            ) AS utm_source,

            JSON_VALUE(
                source.payload_json,
                '$.p_utm_term'
            ) AS utm_term,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.total_price'
                )
            ) AS total_price,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.total_price_after_sub_discount'
                )
            ) AS total_price_after_discount,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.buyer_total_amount'
                )
            ) AS buyer_total_amount,

            TRY_CONVERT(
                INT,
                JSON_VALUE(
                    source.payload_json,
                    '$.total_quantity'
                )
            ) AS total_quantity,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.total_discount'
                )
            ) AS total_discount,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.shipping_fee'
                )
            ) AS customer_shipping_fee,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.partner_fee'
                )
            ) AS partner_fee,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.surcharge'
                )
            ) AS surcharge,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.advanced_platform_fee'
                )
            ) AS advanced_platform_fee,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.fee_marketplace'
                )
            ) AS marketplace_fee,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.customer_pay_fee'
                )
            ) AS customer_pay_fee,

            TRY_CONVERT(
                BIT,
                JSON_VALUE(
                    source.payload_json,
                    '$.return_fee'
                )
            ) AS source_return_fee_flag,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.tax'
                )
            ) AS source_tax,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.cod'
                )
            ) AS cod,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.money_to_collect'
                )
            ) AS money_to_collect,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.prepaid'
                )
            ) AS prepaid,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.cash'
                )
            ) AS cash,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.transfer_money'
                )
            ) AS transfer_money,

            JSON_VALUE(
                source.payload_json,
                '$.partner.partner_name'
            ) AS shipping_partner_name,

            JSON_VALUE(
                source.payload_json,
                '$.partner.partner_status'
            ) AS shipping_partner_status,

            COALESCE(
                JSON_VALUE(
                    source.payload_json,
                    '$.partner.extend_code'
                ),
                JSON_VALUE(
                    source.payload_json,
                    '$.partner.order_id_ghn'
                ),
                JSON_VALUE(
                    source.payload_json,
                    '$.partner.order_number_vtp'
                )
            ) AS tracking_code,

            TRY_CONVERT(
                DECIMAL(19, 2),
                JSON_VALUE(
                    source.payload_json,
                    '$.partner.total_fee'
                )
            ) AS partner_total_fee,

            TRY_CONVERT(
                DATETIME2(3),
                JSON_VALUE(
                    source.payload_json,
                    '$.partner.picked_up_at'
                )
            ) AS picked_up_at,

            TRY_CONVERT(
                DATETIME2(3),
                JSON_VALUE(
                    source.payload_json,
                    '$.partner.first_delivery_at'
                )
            ) AS first_delivery_at,

            TRY_CONVERT(
                DATETIME2(3),
                JSON_VALUE(
                    source.payload_json,
                    '$.partner.first_undeliverable_at'
                )
            ) AS first_undeliverable_at,

            JSON_VALUE(
                source.payload_json,
                '$.shipping_address.province_id'
            ) AS province_id,

            JSON_VALUE(
                source.payload_json,
                '$.shipping_address.province_name'
            ) AS province_name,

            JSON_VALUE(
                source.payload_json,
                '$.shipping_address.district_id'
            ) AS district_id,

            JSON_VALUE(
                source.payload_json,
                '$.shipping_address.district_name'
            ) AS district_name,

            JSON_VALUE(
                source.payload_json,
                '$.shipping_address.commune_id'
            ) AS commune_id,

            JSON_VALUE(
                source.payload_json,
                '$.shipping_address.commune_name'
            ) AS commune_name,

            JSON_VALUE(
                source.payload_json,
                '$.creator.id'
            ) AS creator_id,

            JSON_VALUE(
                source.payload_json,
                '$.creator.name'
            ) AS creator_name,

            COALESCE(
                JSON_VALUE(
                    source.payload_json,
                    '$.assigning_seller_id'
                ),
                JSON_VALUE(
                    source.payload_json,
                    '$.assigning_seller.id'
                )
            ) AS assigning_seller_id,

            JSON_VALUE(
                source.payload_json,
                '$.assigning_seller.name'
            ) AS assigning_seller_name,

            source.payload_hash
        INTO #source_orders
        FROM #latest_orders AS source;

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_orders
        ON #source_orders (shop_id, order_id);

        SELECT
            source.shop_id,
            source.order_id,
            item_data.source_item_id,
            source.raw_order_version_id
                AS source_raw_order_version_id,
            item_data.source_product_id,
            item_data.source_variation_id,
            item_data.product_name,
            normalized.normalized_product_name,
            COALESCE(item_data.quantity, 0)
                AS quantity,
            item_data.unit_retail_price,
            item_data.original_retail_price,
            item_data.exact_price,
            item_data.discount_each_product,
            item_data.total_discount,
            item_data.source_last_imported_price,
            item_data.source_average_price,
            item_data.return_quantity,
            item_data.returning_quantity,
            item_data.returned_count,
            item_data.exchange_count,
            item_data.is_bonus_product,
            item_data.is_composite,
            item_data.composite_item_id,
            item_data.components_json,
            item_data.is_wholesale,
            item_data.weight
        INTO #source_items
        FROM #latest_orders AS source
        CROSS APPLY OPENJSON(
            JSON_QUERY(
                source.payload_json,
                '$.items'
            )
        ) AS item
        CROSS APPLY OPENJSON(item.[value])
        WITH (
            source_item_id BIGINT '$.id',
            source_product_id NVARCHAR(100)
                '$.product_id',
            source_variation_id NVARCHAR(100)
                '$.variation_id',
            product_name NVARCHAR(500)
                '$.variation_info.name',
            quantity INT '$.quantity',
            unit_retail_price DECIMAL(19, 2)
                '$.variation_info.retail_price',
            original_retail_price DECIMAL(19, 2)
                '$.variation_info.retail_price_original',
            exact_price DECIMAL(19, 2)
                '$.variation_info.exact_price',
            discount_each_product DECIMAL(19, 2)
                '$.discount_each_product',
            total_discount DECIMAL(19, 2)
                '$.total_discount',
            source_last_imported_price DECIMAL(19, 2)
                '$.variation_info.last_imported_price',
            source_average_price DECIMAL(19, 2)
                '$.variation_info.avg_price',
            return_quantity INT '$.return_quantity',
            returning_quantity INT '$.returning_quantity',
            returned_count INT '$.returned_count',
            exchange_count INT '$.exchange_count',
            is_bonus_product BIT '$.is_bonus_product',
            is_composite BIT '$.is_composite',
            composite_item_id BIGINT
                '$.composite_item_id',
            components_json NVARCHAR(MAX)
                '$.components' AS JSON,
            is_wholesale BIT '$.is_wholesale',
            weight DECIMAL(19, 6)
                '$.variation_info.weight'
        ) AS item_data
        CROSS APPLY (
            SELECT CAST(
                LEFT(
                    LOWER(
                        LTRIM(
                            RTRIM(
                                REPLACE(
                                    REPLACE(
                                        REPLACE(
                                            REPLACE(
                                                REPLACE(
                                                    item_data.product_name,
                                                    NCHAR(9),
                                                    N' '
                                                ),
                                                NCHAR(10),
                                                N' '
                                            ),
                                            NCHAR(13),
                                            N' '
                                        ),
                                        N'  ',
                                        N' '
                                    ),
                                    N'  ',
                                    N' '
                                )
                            )
                        )
                    ),
                    400
                )
                AS NVARCHAR(400)
            ) AS normalized_product_name
        ) AS normalized
        WHERE item_data.source_item_id IS NOT NULL
          AND item_data.product_name IS NOT NULL
          AND normalized.normalized_product_name <> N'';

        CREATE INDEX IX_source_items_order
            ON #source_items (
                shop_id,
                order_id,
                source_item_id
            );

        ;WITH source_products AS (
            SELECT
                normalized_product_name,
                MIN(product_name)
                    AS canonical_product_name
            FROM #source_items
            GROUP BY normalized_product_name
        )
        UPDATE target
        SET last_seen_at_utc = SYSUTCDATETIME()
        FROM stg.product_registry AS target
        INNER JOIN source_products AS source
            ON source.normalized_product_name =
               target.normalized_product_name;

        ;WITH source_products AS (
            SELECT
                normalized_product_name,
                MIN(product_name)
                    AS canonical_product_name
            FROM #source_items
            GROUP BY normalized_product_name
        )
        INSERT INTO stg.product_registry (
            normalized_product_name,
            canonical_product_name
        )
        SELECT
            source.normalized_product_name,
            source.canonical_product_name
        FROM source_products AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.product_registry AS target
            WHERE target.normalized_product_name =
                  source.normalized_product_name
        );

        SELECT
            source.shop_id,
            source.order_id
        INTO #changed_orders
        FROM #source_orders AS source
        LEFT JOIN stg.pancake_orders AS target
            ON target.shop_id = source.shop_id
           AND target.order_id = source.order_id
        WHERE target.order_id IS NULL
           OR target.source_raw_order_version_id <>
              source.source_raw_order_version_id;

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_orders
        ON #changed_orders (shop_id, order_id);

        DELETE target
        FROM stg.pancake_order_items AS target
        INNER JOIN #changed_orders AS changed
            ON changed.shop_id = target.shop_id
           AND changed.order_id = target.order_id;

        UPDATE target
        SET
            system_id = source.system_id,
            source_raw_order_version_id =
                source.source_raw_order_version_id,
            source_inserted_at =
                source.source_inserted_at,
            source_updated_at =
                source.source_updated_at,
            source_status = source.source_status,
            status_name = source.status_name,
            sub_status = source.sub_status,
            is_cancelled = source.is_cancelled,
            is_delivered = source.is_delivered,
            is_returning = source.is_returning,
            is_returned = source.is_returned,
            page_id = source.page_id,
            page_name = source.page_name,
            ad_id = source.ad_id,
            post_id = source.post_id,
            ads_source = source.ads_source,
            order_source_name =
                source.order_source_name,
            utm_campaign = source.utm_campaign,
            utm_content = source.utm_content,
            utm_id = source.utm_id,
            utm_medium = source.utm_medium,
            utm_source = source.utm_source,
            utm_term = source.utm_term,
            total_price = source.total_price,
            total_price_after_discount =
                source.total_price_after_discount,
            buyer_total_amount =
                source.buyer_total_amount,
            total_quantity = source.total_quantity,
            total_discount = source.total_discount,
            customer_shipping_fee =
                source.customer_shipping_fee,
            partner_fee = source.partner_fee,
            surcharge = source.surcharge,
            advanced_platform_fee =
                source.advanced_platform_fee,
            marketplace_fee = source.marketplace_fee,
            customer_pay_fee =
                source.customer_pay_fee,
            source_return_fee_flag =
                source.source_return_fee_flag,
            source_tax = source.source_tax,
            cod = source.cod,
            money_to_collect =
                source.money_to_collect,
            prepaid = source.prepaid,
            cash = source.cash,
            transfer_money = source.transfer_money,
            shipping_partner_name =
                source.shipping_partner_name,
            shipping_partner_status =
                source.shipping_partner_status,
            tracking_code = source.tracking_code,
            partner_total_fee =
                source.partner_total_fee,
            picked_up_at = source.picked_up_at,
            first_delivery_at =
                source.first_delivery_at,
            first_undeliverable_at =
                source.first_undeliverable_at,
            province_id = source.province_id,
            province_name = source.province_name,
            district_id = source.district_id,
            district_name = source.district_name,
            commune_id = source.commune_id,
            commune_name = source.commune_name,
            creator_id = source.creator_id,
            creator_name = source.creator_name,
            assigning_seller_id =
                source.assigning_seller_id,
            assigning_seller_name =
                source.assigning_seller_name,
            payload_hash = source.payload_hash,
            staged_at_utc = SYSUTCDATETIME()
        FROM stg.pancake_orders AS target
        INNER JOIN #source_orders AS source
            ON source.shop_id = target.shop_id
           AND source.order_id = target.order_id
        INNER JOIN #changed_orders AS changed
            ON changed.shop_id = source.shop_id
           AND changed.order_id = source.order_id;

        INSERT INTO stg.pancake_orders (
            shop_id,
            order_id,
            system_id,
            source_raw_order_version_id,
            source_inserted_at,
            source_updated_at,
            source_status,
            status_name,
            sub_status,
            is_cancelled,
            is_delivered,
            is_returning,
            is_returned,
            page_id,
            page_name,
            ad_id,
            post_id,
            ads_source,
            order_source_name,
            utm_campaign,
            utm_content,
            utm_id,
            utm_medium,
            utm_source,
            utm_term,
            total_price,
            total_price_after_discount,
            buyer_total_amount,
            total_quantity,
            total_discount,
            customer_shipping_fee,
            partner_fee,
            surcharge,
            advanced_platform_fee,
            marketplace_fee,
            customer_pay_fee,
            source_return_fee_flag,
            source_tax,
            cod,
            money_to_collect,
            prepaid,
            cash,
            transfer_money,
            shipping_partner_name,
            shipping_partner_status,
            tracking_code,
            partner_total_fee,
            picked_up_at,
            first_delivery_at,
            first_undeliverable_at,
            province_id,
            province_name,
            district_id,
            district_name,
            commune_id,
            commune_name,
            creator_id,
            creator_name,
            assigning_seller_id,
            assigning_seller_name,
            payload_hash
        )
        SELECT
            source.shop_id,
            source.order_id,
            source.system_id,
            source.source_raw_order_version_id,
            source.source_inserted_at,
            source.source_updated_at,
            source.source_status,
            source.status_name,
            source.sub_status,
            source.is_cancelled,
            source.is_delivered,
            source.is_returning,
            source.is_returned,
            source.page_id,
            source.page_name,
            source.ad_id,
            source.post_id,
            source.ads_source,
            source.order_source_name,
            source.utm_campaign,
            source.utm_content,
            source.utm_id,
            source.utm_medium,
            source.utm_source,
            source.utm_term,
            source.total_price,
            source.total_price_after_discount,
            source.buyer_total_amount,
            source.total_quantity,
            source.total_discount,
            source.customer_shipping_fee,
            source.partner_fee,
            source.surcharge,
            source.advanced_platform_fee,
            source.marketplace_fee,
            source.customer_pay_fee,
            source.source_return_fee_flag,
            source.source_tax,
            source.cod,
            source.money_to_collect,
            source.prepaid,
            source.cash,
            source.transfer_money,
            source.shipping_partner_name,
            source.shipping_partner_status,
            source.tracking_code,
            source.partner_total_fee,
            source.picked_up_at,
            source.first_delivery_at,
            source.first_undeliverable_at,
            source.province_id,
            source.province_name,
            source.district_id,
            source.district_name,
            source.commune_id,
            source.commune_name,
            source.creator_id,
            source.creator_name,
            source.assigning_seller_id,
            source.assigning_seller_name,
            source.payload_hash
        FROM #source_orders AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.pancake_orders AS target
            WHERE target.shop_id = source.shop_id
              AND target.order_id = source.order_id
        );

        ;WITH ranked_items AS (
            SELECT
                source.*,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        source.shop_id,
                        source.order_id,
                        source.source_item_id
                    ORDER BY
                        source.source_raw_order_version_id
                        DESC
                ) AS row_number
            FROM #source_items AS source
            INNER JOIN #changed_orders AS changed
                ON changed.shop_id = source.shop_id
               AND changed.order_id = source.order_id
        )
        INSERT INTO stg.pancake_order_items (
            shop_id,
            order_id,
            source_item_id,
            source_raw_order_version_id,
            source_product_id,
            source_variation_id,
            internal_product_id,
            product_name,
            normalized_product_name,
            quantity,
            unit_retail_price,
            original_retail_price,
            exact_price,
            discount_each_product,
            total_discount,
            source_last_imported_price,
            source_average_price,
            return_quantity,
            returning_quantity,
            returned_count,
            exchange_count,
            is_bonus_product,
            is_composite,
            composite_item_id,
            components_json,
            is_wholesale,
            weight
        )
        SELECT
            source.shop_id,
            source.order_id,
            source.source_item_id,
            source.source_raw_order_version_id,
            source.source_product_id,
            source.source_variation_id,
            product.internal_product_id,
            source.product_name,
            source.normalized_product_name,
            source.quantity,
            source.unit_retail_price,
            source.original_retail_price,
            source.exact_price,
            source.discount_each_product,
            source.total_discount,
            source.source_last_imported_price,
            source.source_average_price,
            source.return_quantity,
            source.returning_quantity,
            source.returned_count,
            source.exchange_count,
            source.is_bonus_product,
            source.is_composite,
            source.composite_item_id,
            source.components_json,
            source.is_wholesale,
            source.weight
        FROM ranked_items AS source
        INNER JOIN stg.product_registry AS product
            ON product.normalized_product_name =
               source.normalized_product_name
        WHERE source.row_number = 1;

        DECLARE @changed_order_count INT = (
            SELECT COUNT(*)
            FROM #changed_orders
        );

        COMMIT TRANSACTION;

        SELECT
            @changed_order_count AS changed_orders,
            (
                SELECT COUNT(*)
                FROM stg.pancake_orders
            ) AS staged_orders,
            (
                SELECT COUNT(*)
                FROM stg.pancake_order_items
            ) AS staged_items,
            (
                SELECT COUNT(*)
                FROM stg.product_registry
            ) AS registered_products;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;