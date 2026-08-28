CREATE OR ALTER PROCEDURE mart.refresh_dim_meta_ads
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID(
            N'mart.dim_meta_ads',
            N'U'
        ) IS NULL
        BEGIN
            THROW 51001,
                'mart.dim_meta_ads does not exist.',
                1;
        END;

        /*
         * Một ad_id phải luôn thuộc đúng một account,
         * campaign và ad set.
         */
        IF EXISTS (
            SELECT 1
            FROM stg.meta_ad_insights
            GROUP BY ad_id
            HAVING
                COUNT(
                    DISTINCT account_object_id
                ) > 1
                OR COUNT(
                    DISTINCT COALESCE(
                        campaign_id,
                        N'__NULL__'
                    )
                ) > 1
                OR COUNT(
                    DISTINCT COALESCE(
                        adset_id,
                        N'__NULL__'
                    )
                ) > 1
        )
        BEGIN
            THROW 51002,
                'An ad_id maps to multiple Meta entities.',
                1;
        END;

        ;WITH ranked_meta_ads AS (
            SELECT
                insights.ad_id,
                insights.account_object_id,
                insights.account_id,
                insights.account_name,
                insights.campaign_id,
                insights.campaign_name,
                insights.adset_id,
                insights.adset_name,
                insights.ad_name,
                insights.objective,
                insights.optimization_goal,
                insights.source_raw_insight_version_id,
                insights.source_extracted_at_utc,

                MIN(insights.date_start) OVER (
                    PARTITION BY insights.ad_id
                ) AS first_insight_date,

                MAX(insights.date_start) OVER (
                    PARTITION BY insights.ad_id
                ) AS last_insight_date,

                ROW_NUMBER() OVER (
                    PARTITION BY insights.ad_id
                    ORDER BY
                        insights.date_start DESC,
                        insights.source_extracted_at_utc DESC,
                        insights.source_raw_insight_version_id DESC
                ) AS row_number

            FROM stg.meta_ad_insights AS insights
        )
        SELECT
            ranked.ad_id,
            ranked.account_object_id,
            ranked.account_id,
            COALESCE(
                accounts.account_name,
                ranked.account_name
            ) AS account_name,
            accounts.account_status,
            accounts.currency,
            accounts.timezone_name,
            ranked.campaign_id,
            ranked.campaign_name,
            ranked.adset_id,
            ranked.adset_name,
            ranked.ad_name,
            ranked.objective,
            ranked.optimization_goal,
            ranked.first_insight_date,
            ranked.last_insight_date,
            ranked.source_raw_insight_version_id,
            ranked.source_extracted_at_utc
        INTO #latest_meta_ads
        FROM ranked_meta_ads AS ranked
        LEFT JOIN stg.meta_ad_accounts AS accounts
            ON accounts.account_object_id =
               ranked.account_object_id
        WHERE ranked.row_number = 1;

        CREATE UNIQUE CLUSTERED INDEX
            IX_latest_meta_ads
        ON #latest_meta_ads (ad_id);

        /*
         * Nguồn dimension gồm:
         * - ad đã ánh xạ được với Meta;
         * - ad chỉ xuất hiện trong đơn hàng;
         * - member đặc biệt cho đơn không có ad_id.
         */
        SELECT
            meta.ad_id,
            CAST(
                'META_MAPPED' AS VARCHAR(30)
            ) AS mapping_status,
            CAST(1 AS BIT) AS is_meta_mapped,
            CAST(0 AS BIT) AS is_special_member,
            meta.account_object_id,
            meta.account_id,
            meta.account_name,
            meta.account_status,
            meta.currency,
            meta.timezone_name,
            meta.campaign_id,
            meta.campaign_name,
            meta.adset_id,
            meta.adset_name,
            meta.ad_name,
            meta.objective,
            meta.optimization_goal,
            meta.first_insight_date,
            meta.last_insight_date,
            meta.source_raw_insight_version_id,
            meta.source_extracted_at_utc
        INTO #source_dim_meta_ads
        FROM #latest_meta_ads AS meta

        UNION ALL

        SELECT
            order_ads.ad_id,
            CAST(
                'ORDER_ONLY' AS VARCHAR(30)
            ) AS mapping_status,
            CAST(0 AS BIT) AS is_meta_mapped,
            CAST(0 AS BIT) AS is_special_member,
            CAST(NULL AS NVARCHAR(100))
                AS account_object_id,
            CAST(NULL AS NVARCHAR(100))
                AS account_id,
            CAST(NULL AS NVARCHAR(500))
                AS account_name,
            CAST(NULL AS INT)
                AS account_status,
            CAST(NULL AS VARCHAR(10))
                AS currency,
            CAST(NULL AS NVARCHAR(100))
                AS timezone_name,
            CAST(NULL AS NVARCHAR(100))
                AS campaign_id,
            CAST(NULL AS NVARCHAR(500))
                AS campaign_name,
            CAST(NULL AS NVARCHAR(100))
                AS adset_id,
            CAST(NULL AS NVARCHAR(500))
                AS adset_name,
            CAST(N'Unmatched Meta ad' AS NVARCHAR(500))
                AS ad_name,
            CAST(NULL AS NVARCHAR(100))
                AS objective,
            CAST(NULL AS NVARCHAR(100))
                AS optimization_goal,
            CAST(NULL AS DATE)
                AS first_insight_date,
            CAST(NULL AS DATE)
                AS last_insight_date,
            CAST(NULL AS BIGINT)
                AS source_raw_insight_version_id,
            CAST(NULL AS DATETIME2(3))
                AS source_extracted_at_utc
        FROM (
            SELECT DISTINCT
                NULLIF(
                    LTRIM(RTRIM(ad_id)),
                    N''
                ) AS ad_id
            FROM mart.order_economics
        ) AS order_ads
        WHERE order_ads.ad_id IS NOT NULL
          AND NOT EXISTS (
                SELECT 1
                FROM #latest_meta_ads AS meta
                WHERE meta.ad_id = order_ads.ad_id
          )

        UNION ALL

        SELECT
            CAST(
                N'__UNATTRIBUTED__' AS NVARCHAR(100)
            ) AS ad_id,
            CAST(
                'UNATTRIBUTED' AS VARCHAR(30)
            ) AS mapping_status,
            CAST(0 AS BIT) AS is_meta_mapped,
            CAST(1 AS BIT) AS is_special_member,
            CAST(NULL AS NVARCHAR(100))
                AS account_object_id,
            CAST(NULL AS NVARCHAR(100))
                AS account_id,
            CAST(N'Unattributed' AS NVARCHAR(500))
                AS account_name,
            CAST(NULL AS INT)
                AS account_status,
            CAST(NULL AS VARCHAR(10))
                AS currency,
            CAST(NULL AS NVARCHAR(100))
                AS timezone_name,
            CAST(NULL AS NVARCHAR(100))
                AS campaign_id,
            CAST(N'Unattributed' AS NVARCHAR(500))
                AS campaign_name,
            CAST(NULL AS NVARCHAR(100))
                AS adset_id,
            CAST(N'Unattributed' AS NVARCHAR(500))
                AS adset_name,
            CAST(N'Unattributed orders' AS NVARCHAR(500))
                AS ad_name,
            CAST(NULL AS NVARCHAR(100))
                AS objective,
            CAST(NULL AS NVARCHAR(100))
                AS optimization_goal,
            CAST(NULL AS DATE)
                AS first_insight_date,
            CAST(NULL AS DATE)
                AS last_insight_date,
            CAST(NULL AS BIGINT)
                AS source_raw_insight_version_id,
            CAST(NULL AS DATETIME2(3))
                AS source_extracted_at_utc;

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_dim_meta_ads
        ON #source_dim_meta_ads (ad_id);

        SELECT
            source.ad_id
        INTO #changed_dim_meta_ads
        FROM #source_dim_meta_ads AS source
        LEFT JOIN mart.dim_meta_ads AS target
            ON target.ad_id = source.ad_id
        WHERE target.ad_id IS NULL
           OR EXISTS (
                SELECT
                    source.mapping_status,
                    source.is_meta_mapped,
                    source.is_special_member,
                    source.account_object_id,
                    source.account_id,
                    source.account_name,
                    source.account_status,
                    source.currency,
                    source.timezone_name,
                    source.campaign_id,
                    source.campaign_name,
                    source.adset_id,
                    source.adset_name,
                    source.ad_name,
                    source.objective,
                    source.optimization_goal,
                    source.first_insight_date,
                    source.last_insight_date,
                    source.source_raw_insight_version_id,
                    source.source_extracted_at_utc

                EXCEPT

                SELECT
                    target.mapping_status,
                    target.is_meta_mapped,
                    target.is_special_member,
                    target.account_object_id,
                    target.account_id,
                    target.account_name,
                    target.account_status,
                    target.currency,
                    target.timezone_name,
                    target.campaign_id,
                    target.campaign_name,
                    target.adset_id,
                    target.adset_name,
                    target.ad_name,
                    target.objective,
                    target.optimization_goal,
                    target.first_insight_date,
                    target.last_insight_date,
                    target.source_raw_insight_version_id,
                    target.source_extracted_at_utc
           );

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_dim_meta_ads
        ON #changed_dim_meta_ads (ad_id);

        DECLARE @inserted_ad_count INT = (
            SELECT COUNT(*)
            FROM #source_dim_meta_ads AS source
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.dim_meta_ads AS target
                WHERE target.ad_id = source.ad_id
            )
        );

        DECLARE @updated_ad_count INT = (
            SELECT COUNT(*)
            FROM #changed_dim_meta_ads AS changed
            WHERE EXISTS (
                SELECT 1
                FROM mart.dim_meta_ads AS target
                WHERE target.ad_id = changed.ad_id
            )
        );

        UPDATE target
        SET
            mapping_status = source.mapping_status,
            is_meta_mapped = source.is_meta_mapped,
            is_special_member = source.is_special_member,
            account_object_id = source.account_object_id,
            account_id = source.account_id,
            account_name = source.account_name,
            account_status = source.account_status,
            currency = source.currency,
            timezone_name = source.timezone_name,
            campaign_id = source.campaign_id,
            campaign_name = source.campaign_name,
            adset_id = source.adset_id,
            adset_name = source.adset_name,
            ad_name = source.ad_name,
            objective = source.objective,
            optimization_goal = source.optimization_goal,
            first_insight_date = source.first_insight_date,
            last_insight_date = source.last_insight_date,
            source_raw_insight_version_id =
                source.source_raw_insight_version_id,
            source_extracted_at_utc =
                source.source_extracted_at_utc,
            updated_at_utc = SYSUTCDATETIME()
        FROM mart.dim_meta_ads AS target
        INNER JOIN #source_dim_meta_ads AS source
            ON source.ad_id = target.ad_id
        INNER JOIN #changed_dim_meta_ads AS changed
            ON changed.ad_id = source.ad_id;

        INSERT INTO mart.dim_meta_ads (
            ad_id,
            mapping_status,
            is_meta_mapped,
            is_special_member,
            account_object_id,
            account_id,
            account_name,
            account_status,
            currency,
            timezone_name,
            campaign_id,
            campaign_name,
            adset_id,
            adset_name,
            ad_name,
            objective,
            optimization_goal,
            first_insight_date,
            last_insight_date,
            source_raw_insight_version_id,
            source_extracted_at_utc
        )
        SELECT
            source.ad_id,
            source.mapping_status,
            source.is_meta_mapped,
            source.is_special_member,
            source.account_object_id,
            source.account_id,
            source.account_name,
            source.account_status,
            source.currency,
            source.timezone_name,
            source.campaign_id,
            source.campaign_name,
            source.adset_id,
            source.adset_name,
            source.ad_name,
            source.objective,
            source.optimization_goal,
            source.first_insight_date,
            source.last_insight_date,
            source.source_raw_insight_version_id,
            source.source_extracted_at_utc
        FROM #source_dim_meta_ads AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM mart.dim_meta_ads AS target
            WHERE target.ad_id = source.ad_id
        );

        COMMIT TRANSACTION;

        SELECT
            @inserted_ad_count AS inserted_ads,
            @updated_ad_count AS updated_ads,
            COUNT(*) AS dimension_rows,

            SUM(
                CASE
                    WHEN mapping_status = 'META_MAPPED'
                    THEN 1
                    ELSE 0
                END
            ) AS meta_mapped_ads,

            SUM(
                CASE
                    WHEN mapping_status = 'ORDER_ONLY'
                    THEN 1
                    ELSE 0
                END
            ) AS order_only_ads,

            SUM(
                CASE
                    WHEN mapping_status = 'UNATTRIBUTED'
                    THEN 1
                    ELSE 0
                END
            ) AS unattributed_members

        FROM mart.dim_meta_ads;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
