SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'ctl.pipeline_runs', N'U') IS NULL
    BEGIN
        CREATE TABLE ctl.pipeline_runs (
            run_id UNIQUEIDENTIFIER NOT NULL
                CONSTRAINT DF_pipeline_runs_run_id
                DEFAULT NEWSEQUENTIALID(),

            pipeline_name VARCHAR(100) NOT NULL,
            source_name VARCHAR(50) NOT NULL,
            run_type VARCHAR(20) NOT NULL,
            window_start_utc DATETIME2(3) NULL,
            window_end_utc DATETIME2(3) NULL,
            started_at_utc DATETIME2(3) NOT NULL,
            completed_at_utc DATETIME2(3) NULL,
            [status] VARCHAR(20) NOT NULL,
            rows_extracted BIGINT NOT NULL
                CONSTRAINT DF_pipeline_runs_rows_extracted DEFAULT 0,
            rows_loaded BIGINT NOT NULL
                CONSTRAINT DF_pipeline_runs_rows_loaded DEFAULT 0,
            rows_rejected BIGINT NOT NULL
                CONSTRAINT DF_pipeline_runs_rows_rejected DEFAULT 0,
            error_message NVARCHAR(2000) NULL,

            CONSTRAINT PK_pipeline_runs
                PRIMARY KEY (run_id),

            CONSTRAINT CK_pipeline_runs_status
                CHECK ([status] IN (
                    'running',
                    'succeeded',
                    'failed',
                    'partial'
                )),

            CONSTRAINT CK_pipeline_runs_run_type
                CHECK (run_type IN (
                    'backfill',
                    'incremental',
                    'manual'
                ))
        );
    END;

    IF OBJECT_ID(N'ctl.sync_checkpoints', N'U') IS NULL
    BEGIN
        CREATE TABLE ctl.sync_checkpoints (
            source_name VARCHAR(50) NOT NULL,
            entity_name VARCHAR(50) NOT NULL,
            partition_key NVARCHAR(200) NOT NULL
                CONSTRAINT DF_sync_checkpoints_partition_key
                DEFAULT N'default',
            last_source_updated_at DATETIME2(3) NULL,
            last_source_id NVARCHAR(100) NULL,
            last_successful_run_id UNIQUEIDENTIFIER NULL,
            updated_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_sync_checkpoints_updated_at
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_sync_checkpoints
                PRIMARY KEY (
                    source_name,
                    entity_name,
                    partition_key
                ),

            CONSTRAINT FK_sync_checkpoints_pipeline_runs
                FOREIGN KEY (last_successful_run_id)
                REFERENCES ctl.pipeline_runs (run_id)
        );
    END;

    IF OBJECT_ID(
        N'raw.pancake_order_versions',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE raw.pancake_order_versions (
            raw_order_version_id BIGINT IDENTITY(1, 1) NOT NULL,
            extract_run_id UNIQUEIDENTIFIER NOT NULL,
            extracted_at_utc DATETIME2(3) NOT NULL,
            shop_id NVARCHAR(100) NOT NULL,
            order_id NVARCHAR(100) NOT NULL,
            system_id NVARCHAR(100) NULL,
            source_inserted_at DATETIME2(3) NULL,
            source_updated_at DATETIME2(3) NOT NULL,
            payload_hash BINARY(32) NOT NULL,
            sanitization_version VARCHAR(20) NOT NULL,
            payload_json NVARCHAR(MAX) NOT NULL,
            loaded_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_pancake_order_versions_loaded_at
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_pancake_order_versions
                PRIMARY KEY (raw_order_version_id),

            CONSTRAINT FK_pancake_order_versions_pipeline_runs
                FOREIGN KEY (extract_run_id)
                REFERENCES ctl.pipeline_runs (run_id),

            CONSTRAINT CK_pancake_order_versions_payload_json
                CHECK (ISJSON(payload_json) = 1)
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'UX_pancake_order_versions_source'
          AND object_id = OBJECT_ID(
              N'raw.pancake_order_versions'
          )
    )
    BEGIN
        CREATE UNIQUE INDEX UX_pancake_order_versions_source
            ON raw.pancake_order_versions (
                shop_id,
                order_id,
                source_updated_at,
                payload_hash
            );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_pancake_order_versions_run'
          AND object_id = OBJECT_ID(
              N'raw.pancake_order_versions'
          )
    )
    BEGIN
        CREATE INDEX IX_pancake_order_versions_run
            ON raw.pancake_order_versions (
                extract_run_id
            );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;