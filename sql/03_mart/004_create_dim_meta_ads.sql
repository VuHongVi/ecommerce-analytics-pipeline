SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'mart.dim_meta_ads',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE mart.dim_meta_ads (
            ad_key BIGINT IDENTITY(1, 1) NOT NULL,
            ad_id NVARCHAR(100) NOT NULL,

            mapping_status VARCHAR(30) NOT NULL,
            is_meta_mapped BIT NOT NULL,
            is_special_member BIT NOT NULL,

            account_object_id NVARCHAR(100) NULL,
            account_id NVARCHAR(100) NULL,
            account_name NVARCHAR(500) NULL,
            account_status INT NULL,
            currency VARCHAR(10) NULL,
            timezone_name NVARCHAR(100) NULL,

            campaign_id NVARCHAR(100) NULL,
            campaign_name NVARCHAR(500) NULL,
            adset_id NVARCHAR(100) NULL,
            adset_name NVARCHAR(500) NULL,
            ad_name NVARCHAR(500) NULL,

            objective NVARCHAR(100) NULL,
            optimization_goal NVARCHAR(100) NULL,

            first_insight_date DATE NULL,
            last_insight_date DATE NULL,

            source_raw_insight_version_id BIGINT NULL,
            source_extracted_at_utc DATETIME2(3) NULL,

            created_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_dim_meta_ads_created
                DEFAULT SYSUTCDATETIME(),

            updated_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_dim_meta_ads_updated
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_dim_meta_ads
                PRIMARY KEY CLUSTERED (ad_key),

            CONSTRAINT UQ_dim_meta_ads_ad_id
                UNIQUE (ad_id),

            CONSTRAINT CK_dim_meta_ads_mapping_status
                CHECK (
                    mapping_status IN (
                        'META_MAPPED',
                        'ORDER_ONLY',
                        'UNATTRIBUTED'
                    )
                ),

            CONSTRAINT CK_dim_meta_ads_mapping_flags
                CHECK (
                    (
                        mapping_status = 'META_MAPPED'
                        AND is_meta_mapped = 1
                        AND is_special_member = 0
                    )
                    OR (
                        mapping_status = 'ORDER_ONLY'
                        AND is_meta_mapped = 0
                        AND is_special_member = 0
                    )
                    OR (
                        mapping_status = 'UNATTRIBUTED'
                        AND is_meta_mapped = 0
                        AND is_special_member = 1
                    )
                ),

            CONSTRAINT CK_dim_meta_ads_insight_dates
                CHECK (
                    first_insight_date IS NULL
                    OR last_insight_date IS NULL
                    OR last_insight_date >= first_insight_date
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_dim_meta_ads_account'
          AND object_id = OBJECT_ID(
              N'mart.dim_meta_ads'
          )
    )
    BEGIN
        CREATE INDEX IX_dim_meta_ads_account
            ON mart.dim_meta_ads (
                account_object_id,
                ad_key
            )
            WHERE account_object_id IS NOT NULL;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_dim_meta_ads_campaign'
          AND object_id = OBJECT_ID(
              N'mart.dim_meta_ads'
          )
    )
    BEGIN
        CREATE INDEX IX_dim_meta_ads_campaign
            ON mart.dim_meta_ads (
                campaign_id,
                ad_key
            )
            WHERE campaign_id IS NOT NULL;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_dim_meta_ads_adset'
          AND object_id = OBJECT_ID(
              N'mart.dim_meta_ads'
          )
    )
    BEGIN
        CREATE INDEX IX_dim_meta_ads_adset
            ON mart.dim_meta_ads (
                adset_id,
                ad_key
            )
            WHERE adset_id IS NOT NULL;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
