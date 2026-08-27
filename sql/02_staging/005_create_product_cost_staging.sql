SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'stg.product_cost_master',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE stg.product_cost_master (
            normalized_product_name
                NVARCHAR(400) NOT NULL,
            canonical_product_name
                NVARCHAR(1000) NOT NULL,

            fallback_unit_cost
                DECIMAL(19, 2) NOT NULL,

            source_row_count INT NOT NULL,
            has_conflicting_prices BIT NOT NULL,

            source_product_cost_import_batch_id
                BIGINT NOT NULL,
            source_raw_product_cost_master_id
                BIGINT NOT NULL,
            source_row_hash BINARY(32) NOT NULL,

            staged_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_stg_cost_master_staged
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_stg_product_cost_master
                PRIMARY KEY (
                    normalized_product_name
                ),

            CONSTRAINT FK_stg_cost_master_batch
                FOREIGN KEY (
                    source_product_cost_import_batch_id
                )
                REFERENCES
                    raw.product_cost_import_batches (
                        product_cost_import_batch_id
                    ),

            CONSTRAINT FK_stg_cost_master_raw
                FOREIGN KEY (
                    source_raw_product_cost_master_id
                )
                REFERENCES
                    raw.product_cost_master_rows (
                        raw_product_cost_master_id
                    ),

            CONSTRAINT CK_stg_cost_master_price
                CHECK (fallback_unit_cost > 0),

            CONSTRAINT CK_stg_cost_master_row_count
                CHECK (source_row_count > 0)
        );
    END;

    IF OBJECT_ID(
        N'stg.product_cost_history',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE stg.product_cost_history (
            source_raw_product_cost_history_id
                BIGINT NOT NULL,

            normalized_product_name
                NVARCHAR(400) NOT NULL,
            canonical_product_name
                NVARCHAR(1000) NOT NULL,

            approved_quantity
                DECIMAL(19, 6) NULL,
            import_date DATE NOT NULL,
            warehouse_arrival_date DATE NOT NULL,
            actual_unit_cost
                DECIMAL(19, 2) NOT NULL,

            source_product_cost_import_batch_id
                BIGINT NOT NULL,
            source_row_hash BINARY(32) NOT NULL,

            staged_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_stg_cost_history_staged
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_stg_product_cost_history
                PRIMARY KEY (
                    source_raw_product_cost_history_id
                ),

            CONSTRAINT FK_stg_cost_history_batch
                FOREIGN KEY (
                    source_product_cost_import_batch_id
                )
                REFERENCES
                    raw.product_cost_import_batches (
                        product_cost_import_batch_id
                    ),

            CONSTRAINT FK_stg_cost_history_raw
                FOREIGN KEY (
                    source_raw_product_cost_history_id
                )
                REFERENCES
                    raw.product_cost_history_rows (
                        raw_product_cost_history_id
                    ),

            CONSTRAINT CK_stg_cost_history_price
                CHECK (actual_unit_cost > 0),

            CONSTRAINT CK_stg_cost_history_quantity
                CHECK (
                    approved_quantity IS NULL
                    OR approved_quantity > 0
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_stg_cost_history_product_date'
          AND object_id = OBJECT_ID(
              N'stg.product_cost_history'
          )
    )
    BEGIN
        CREATE INDEX
            IX_stg_cost_history_product_date
        ON stg.product_cost_history (
            normalized_product_name,
            warehouse_arrival_date DESC
        )
        INCLUDE (
            actual_unit_cost,
            approved_quantity,
            import_date
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;