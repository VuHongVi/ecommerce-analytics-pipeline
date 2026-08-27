SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'stg.meta_ad_accounts',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE stg.meta_ad_accounts (
            account_object_id NVARCHAR(100) NOT NULL,
            account_id NVARCHAR(100) NULL,
            account_name NVARCHAR(500) NULL,
            account_status INT NULL,
            currency VARCHAR(10) NULL,
            timezone_name NVARCHAR(100) NULL,
            discovery_sources_json NVARCHAR(MAX)
                NOT NULL,

            source_raw_account_snapshot_id
                BIGINT NOT NULL,
            source_extracted_at_utc
                DATETIME2(3) NOT NULL,
            snapshot_hash BINARY(32) NOT NULL,

            staged_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_stg_meta_account_staged
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_stg_meta_ad_accounts
                PRIMARY KEY (account_object_id),

            CONSTRAINT FK_stg_meta_account_raw
                FOREIGN KEY (
                    source_raw_account_snapshot_id
                )
                REFERENCES raw.meta_ad_account_snapshots (
                    raw_account_snapshot_id
                ),

            CONSTRAINT CK_stg_meta_account_sources
                CHECK (
                    ISJSON(discovery_sources_json) = 1
                )
        );
    END;

    IF OBJECT_ID(
        N'stg.meta_ad_insights',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE stg.meta_ad_insights (
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

            source_raw_insight_version_id
                BIGINT NOT NULL,
            source_extracted_at_utc
                DATETIME2(3) NOT NULL,
            payload_hash BINARY(32) NOT NULL,

            staged_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_stg_meta_insight_staged
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_stg_meta_ad_insights
                PRIMARY KEY (
                    date_start,
                    account_object_id,
                    ad_id
                ),

            CONSTRAINT FK_stg_meta_insight_account
                FOREIGN KEY (account_object_id)
                REFERENCES stg.meta_ad_accounts (
                    account_object_id
                ),

            CONSTRAINT FK_stg_meta_insight_raw
                FOREIGN KEY (
                    source_raw_insight_version_id
                )
                REFERENCES raw.meta_ad_insight_versions (
                    raw_insight_version_id
                ),

            CONSTRAINT CK_stg_meta_actions_json
                CHECK (
                    actions_json IS NULL
                    OR ISJSON(actions_json) = 1
                ),

            CONSTRAINT CK_stg_meta_values_json
                CHECK (
                    action_values_json IS NULL
                    OR ISJSON(action_values_json) = 1
                ),

            CONSTRAINT CK_stg_meta_cost_json
                CHECK (
                    cost_per_action_type_json IS NULL
                    OR ISJSON(
                        cost_per_action_type_json
                    ) = 1
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_stg_meta_insights_account_date'
          AND object_id = OBJECT_ID(
              N'stg.meta_ad_insights'
          )
    )
    BEGIN
        CREATE INDEX
            IX_stg_meta_insights_account_date
        ON stg.meta_ad_insights (
            account_object_id,
            date_start
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_stg_meta_insights_campaign_date'
          AND object_id = OBJECT_ID(
              N'stg.meta_ad_insights'
          )
    )
    BEGIN
        CREATE INDEX
            IX_stg_meta_insights_campaign_date
        ON stg.meta_ad_insights (
            campaign_id,
            date_start
        )
        WHERE campaign_id IS NOT NULL;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] =
            N'IX_stg_meta_insights_ad_date'
          AND object_id = OBJECT_ID(
              N'stg.meta_ad_insights'
          )
    )
    BEGIN
        CREATE INDEX
            IX_stg_meta_insights_ad_date
        ON stg.meta_ad_insights (
            ad_id,
            date_start
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;