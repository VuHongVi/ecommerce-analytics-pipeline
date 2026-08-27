SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'raw.product_cost_import_batches',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE raw.product_cost_import_batches (
            product_cost_import_batch_id
                BIGINT IDENTITY(1, 1) NOT NULL,

            source_file_name NVARCHAR(260) NOT NULL,
            source_file_sha256 BINARY(32) NOT NULL,
            source_file_size_bytes BIGINT NOT NULL,
            source_file_modified_at_utc
                DATETIME2(3) NULL,

            master_sheet_name NVARCHAR(128) NOT NULL,
            history_sheet_name NVARCHAR(128) NOT NULL,

            master_row_count INT NOT NULL,
            history_row_count INT NOT NULL,

            imported_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_raw_cost_batch_imported
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_raw_product_cost_batches
                PRIMARY KEY (
                    product_cost_import_batch_id
                ),

            CONSTRAINT UQ_raw_product_cost_file_hash
                UNIQUE (source_file_sha256),

            CONSTRAINT CK_raw_product_cost_file_size
                CHECK (source_file_size_bytes >= 0),

            CONSTRAINT CK_raw_product_cost_row_counts
                CHECK (
                    master_row_count >= 0
                    AND history_row_count >= 0
                )
        );
    END;

    IF OBJECT_ID(
        N'raw.product_cost_master_rows',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE raw.product_cost_master_rows (
            raw_product_cost_master_id
                BIGINT IDENTITY(1, 1) NOT NULL,

            product_cost_import_batch_id BIGINT NOT NULL,
            source_sheet_name NVARCHAR(128) NOT NULL,
            source_row_number INT NOT NULL,

            product_name NVARCHAR(1000) NULL,
            unit_cost DECIMAL(19, 2) NULL,

            source_row_json NVARCHAR(MAX) NOT NULL,
            source_row_hash BINARY(32) NOT NULL,

            loaded_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_raw_cost_master_loaded
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_raw_product_cost_master
                PRIMARY KEY (
                    raw_product_cost_master_id
                ),

            CONSTRAINT FK_raw_cost_master_batch
                FOREIGN KEY (
                    product_cost_import_batch_id
                )
                REFERENCES
                    raw.product_cost_import_batches (
                        product_cost_import_batch_id
                    ),

            CONSTRAINT UQ_raw_cost_master_batch_row
                UNIQUE (
                    product_cost_import_batch_id,
                    source_row_number
                ),

            CONSTRAINT CK_raw_cost_master_row_number
                CHECK (source_row_number >= 2),

            CONSTRAINT CK_raw_cost_master_json
                CHECK (ISJSON(source_row_json) = 1)
        );
    END;

    IF OBJECT_ID(
        N'raw.product_cost_history_rows',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE raw.product_cost_history_rows (
            raw_product_cost_history_id
                BIGINT IDENTITY(1, 1) NOT NULL,

            product_cost_import_batch_id BIGINT NOT NULL,
            source_sheet_name NVARCHAR(128) NOT NULL,
            source_row_number INT NOT NULL,

            product_name NVARCHAR(1000) NULL,
            approved_quantity DECIMAL(19, 6) NULL,
            import_date DATE NULL,
            warehouse_arrival_date DATE NULL,
            actual_unit_cost DECIMAL(19, 2) NULL,

            source_row_json NVARCHAR(MAX) NOT NULL,
            source_row_hash BINARY(32) NOT NULL,

            loaded_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_raw_cost_history_loaded
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_raw_product_cost_history
                PRIMARY KEY (
                    raw_product_cost_history_id
                ),

            CONSTRAINT FK_raw_cost_history_batch
                FOREIGN KEY (
                    product_cost_import_batch_id
                )
                REFERENCES
                    raw.product_cost_import_batches (
                        product_cost_import_batch_id
                    ),

            CONSTRAINT UQ_raw_cost_history_batch_row
                UNIQUE (
                    product_cost_import_batch_id,
                    source_row_number
                ),

            CONSTRAINT CK_raw_cost_history_row_number
                CHECK (source_row_number >= 2),

            CONSTRAINT CK_raw_cost_history_json
                CHECK (ISJSON(source_row_json) = 1)
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_raw_cost_master_product'
          AND object_id = OBJECT_ID(
              N'raw.product_cost_master_rows'
          )
    )
    BEGIN
        CREATE INDEX IX_raw_cost_master_product
            ON raw.product_cost_master_rows (
                product_cost_import_batch_id,
                product_name
            );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_raw_cost_history_product_date'
          AND object_id = OBJECT_ID(
              N'raw.product_cost_history_rows'
          )
    )
    BEGIN
        CREATE INDEX
            IX_raw_cost_history_product_date
        ON raw.product_cost_history_rows (
            product_cost_import_batch_id,
            product_name,
            warehouse_arrival_date
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;