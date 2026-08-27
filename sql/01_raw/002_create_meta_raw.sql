SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'raw.meta_ad_account_snapshots',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE raw.meta_ad_account_snapshots (
            raw_account_snapshot_id BIGINT
                IDENTITY(1, 1) NOT NULL,
            extract_run_id UNIQUEIDENTIFIER NOT NULL,
            extracted_at_utc DATETIME2(3) NOT NULL,
            account_object_id NVARCHAR(100) NOT NULL,
            account_id NVARCHAR(100) NULL,
            account_name NVARCHAR(500) NULL,
            account_status INT NULL,
            currency VARCHAR(10) NULL,
            timezone_name NVARCHAR(100) NULL,
            discovery_sources_json NVARCHAR(MAX) NOT NULL,
            snapshot_hash BINARY(32) NOT NULL,
            loaded_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_meta_account_loaded_at
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_meta_ad_account_snapshots
                PRIMARY KEY (raw_account_snapshot_id),

            CONSTRAINT FK_meta_account_pipeline_runs
                FOREIGN KEY (extract_run_id)
                REFERENCES ctl.pipeline_runs (run_id),

            CONSTRAINT CK_meta_account_sources_json
                CHECK (
                    ISJSON(discovery_sources_json) = 1
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'UX_meta_account_snapshot'
          AND object_id = OBJECT_ID(
              N'raw.meta_ad_account_snapshots'
          )
    )
    BEGIN
        CREATE UNIQUE INDEX UX_meta_account_snapshot
            ON raw.meta_ad_account_snapshots (
                account_object_id,
                snapshot_hash
            );
    END;

    IF OBJECT_ID(
        N'raw.meta_ad_insight_versions',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE raw.meta_ad_insight_versions (
            raw_insight_version_id BIGINT
                IDENTITY(1, 1) NOT NULL,
            extract_run_id UNIQUEIDENTIFIER NOT NULL,
            extracted_at_utc DATETIME2(3) NOT NULL,

            date_start DATE NOT NULL,
            date_stop DATE NOT NULL,

            account_object_id NVARCHAR(100) NOT NULL,
            account_id NVARCHAR(100) NULL,
            account_name NVARCHAR(500) NULL,

            campaign_id NVARCHAR(100) NULL,
            campaign_name NVARCHAR(500) NULL,
            adset_id NVARCHAR(100) NULL,
            adset_name NVARCHAR(500) NULL,
            ad_id NVARCHAR(100) NOT NULL,
            ad_name NVARCHAR(500) NULL,

            objective NVARCHAR(100) NULL,
            optimization_goal NVARCHAR(100) NULL,

            impressions BIGINT NULL,
            reach BIGINT NULL,
            frequency DECIMAL(19, 6) NULL,
            clicks BIGINT NULL,
            inline_link_clicks BIGINT NULL,
            spend DECIMAL(19, 6) NULL,
            cpm DECIMAL(19, 6) NULL,
            cpc DECIMAL(19, 6) NULL,
            ctr DECIMAL(19, 6) NULL,

            actions_json NVARCHAR(MAX) NULL,
            action_values_json NVARCHAR(MAX) NULL,
            cost_per_action_type_json NVARCHAR(MAX) NULL,

            payload_hash BINARY(32) NOT NULL,
            payload_json NVARCHAR(MAX) NOT NULL,

            loaded_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_meta_insight_loaded_at
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_meta_ad_insight_versions
                PRIMARY KEY (raw_insight_version_id),

            CONSTRAINT FK_meta_insight_pipeline_runs
                FOREIGN KEY (extract_run_id)
                REFERENCES ctl.pipeline_runs (run_id),

            CONSTRAINT CK_meta_insight_actions_json
                CHECK (
                    actions_json IS NULL
                    OR ISJSON(actions_json) = 1
                ),

            CONSTRAINT CK_meta_insight_values_json
                CHECK (
                    action_values_json IS NULL
                    OR ISJSON(action_values_json) = 1
                ),

            CONSTRAINT CK_meta_insight_cost_json
                CHECK (
                    cost_per_action_type_json IS NULL
                    OR ISJSON(
                        cost_per_action_type_json
                    ) = 1
                ),

            CONSTRAINT CK_meta_insight_payload_json
                CHECK (ISJSON(payload_json) = 1)
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'UX_meta_insight_version'
          AND object_id = OBJECT_ID(
              N'raw.meta_ad_insight_versions'
          )
    )
    BEGIN
        CREATE UNIQUE INDEX UX_meta_insight_version
            ON raw.meta_ad_insight_versions (
                account_object_id,
                date_start,
                ad_id,
                payload_hash
            );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_meta_insight_date_account'
          AND object_id = OBJECT_ID(
              N'raw.meta_ad_insight_versions'
          )
    )
    BEGIN
        CREATE INDEX IX_meta_insight_date_account
            ON raw.meta_ad_insight_versions (
                date_start,
                account_object_id
            );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;