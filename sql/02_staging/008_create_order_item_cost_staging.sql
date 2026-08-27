SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'stg.pancake_order_item_costs',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE stg.pancake_order_item_costs (
            shop_id NVARCHAR(100) NOT NULL,
            order_id NVARCHAR(100) NOT NULL,
            source_item_id BIGINT NOT NULL,

            internal_product_id BIGINT NOT NULL,
            source_raw_order_version_id BIGINT NOT NULL,

            order_created_date DATE NOT NULL,
            quantity INT NOT NULL,

            resolved_unit_cost
                DECIMAL(19, 2) NULL,
            line_product_cost
                DECIMAL(19, 2) NULL,

            cost_source VARCHAR(30) NOT NULL,
            is_estimated BIT NOT NULL,
            cost_effective_date DATE NULL,

            source_product_cost_import_batch_id
                BIGINT NULL,
            source_raw_product_cost_master_id
                BIGINT NULL,
            source_raw_product_cost_history_id
                BIGINT NULL,

            refreshed_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_stg_item_cost_refreshed
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_stg_pancake_order_item_costs
                PRIMARY KEY (
                    shop_id,
                    order_id,
                    source_item_id
                ),

            CONSTRAINT FK_stg_item_cost_item
                FOREIGN KEY (
                    shop_id,
                    order_id,
                    source_item_id
                )
                REFERENCES stg.pancake_order_items (
                    shop_id,
                    order_id,
                    source_item_id
                )
                ON DELETE CASCADE,

            CONSTRAINT FK_stg_item_cost_product
                FOREIGN KEY (internal_product_id)
                REFERENCES stg.product_registry (
                    internal_product_id
                ),

            CONSTRAINT FK_stg_item_cost_batch
                FOREIGN KEY (
                    source_product_cost_import_batch_id
                )
                REFERENCES
                    raw.product_cost_import_batches (
                        product_cost_import_batch_id
                    ),

            CONSTRAINT FK_stg_item_cost_master_raw
                FOREIGN KEY (
                    source_raw_product_cost_master_id
                )
                REFERENCES
                    raw.product_cost_master_rows (
                        raw_product_cost_master_id
                    ),

            CONSTRAINT FK_stg_item_cost_history_raw
                FOREIGN KEY (
                    source_raw_product_cost_history_id
                )
                REFERENCES
                    raw.product_cost_history_rows (
                        raw_product_cost_history_id
                    ),

            CONSTRAINT CK_stg_item_cost_quantity
                CHECK (quantity >= 0),

            CONSTRAINT CK_stg_item_cost_source
                CHECK (
                    cost_source IN (
                        'NOT_REQUIRED_CANCELED',
                        'HISTORY',
                        'MASTER_FALLBACK',
                        'ESTIMATED_DEFAULT',
                        'MANUAL_ESTIMATE',
                        'MISSING_COST'
                    )
                ),

            CONSTRAINT CK_stg_item_cost_estimated
                CHECK (
                    (
                        cost_source IN (
                            'ESTIMATED_DEFAULT',
                            'MANUAL_ESTIMATE'
                        )
                        AND is_estimated = 1
                    )
                    OR
                    (
                        cost_source NOT IN (
                            'ESTIMATED_DEFAULT',
                            'MANUAL_ESTIMATE'
                        )
                        AND is_estimated = 0
                    )
                ),

            CONSTRAINT CK_stg_item_cost_values
                CHECK (
                    (
                        cost_source = 'MISSING_COST'
                        AND resolved_unit_cost IS NULL
                        AND line_product_cost IS NULL
                    )
                    OR
                    (
                        cost_source =
                            'NOT_REQUIRED_CANCELED'
                        AND resolved_unit_cost = 0
                        AND line_product_cost = 0
                    )
                    OR
                    (
                        cost_source IN (
                            'HISTORY',
                            'MASTER_FALLBACK',
                            'ESTIMATED_DEFAULT',
                            'MANUAL_ESTIMATE'
                        )
                        AND resolved_unit_cost > 0
                        AND line_product_cost >= 0
                    )
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_stg_item_cost_product_date'
          AND object_id = OBJECT_ID(
              N'stg.pancake_order_item_costs'
          )
    )
    BEGIN
        CREATE INDEX
            IX_stg_item_cost_product_date
        ON stg.pancake_order_item_costs (
            internal_product_id,
            order_created_date
        )
        INCLUDE (
            quantity,
            resolved_unit_cost,
            line_product_cost,
            cost_source
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_stg_item_cost_source'
          AND object_id = OBJECT_ID(
              N'stg.pancake_order_item_costs'
          )
    )
    BEGIN
        CREATE INDEX IX_stg_item_cost_source
            ON stg.pancake_order_item_costs (
                cost_source
            )
        INCLUDE (
            line_product_cost,
            is_estimated
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;