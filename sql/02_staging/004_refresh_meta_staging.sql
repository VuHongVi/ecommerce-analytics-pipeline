CREATE OR ALTER PROCEDURE stg.refresh_meta_staging
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        ;WITH ranked_accounts AS (
            SELECT
                raw_account_snapshot_id,
                extracted_at_utc,
                account_object_id,
                account_id,
                account_name,
                account_status,
                currency,
                timezone_name,
                discovery_sources_json,
                snapshot_hash,
                ROW_NUMBER() OVER (
                    PARTITION BY account_object_id
                    ORDER BY
                        extracted_at_utc DESC,
                        raw_account_snapshot_id DESC
                ) AS row_number
            FROM raw.meta_ad_account_snapshots
        )
        SELECT
            raw_account_snapshot_id,
            extracted_at_utc,
            account_object_id,
            account_id,
            account_name,
            account_status,
            currency,
            timezone_name,
            discovery_sources_json,
            snapshot_hash
        INTO #latest_accounts
        FROM ranked_accounts
        WHERE row_number = 1;

        CREATE UNIQUE CLUSTERED INDEX
            IX_latest_meta_accounts
        ON #latest_accounts (account_object_id);

        SELECT source.account_object_id
        INTO #changed_accounts
        FROM #latest_accounts AS source
        LEFT JOIN stg.meta_ad_accounts AS target
            ON target.account_object_id =
               source.account_object_id
        WHERE target.account_object_id IS NULL
           OR target.source_raw_account_snapshot_id <>
              source.raw_account_snapshot_id;

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_meta_accounts
        ON #changed_accounts (account_object_id);

        UPDATE target
        SET
            account_id = source.account_id,
            account_name = source.account_name,
            account_status = source.account_status,
            currency = source.currency,
            timezone_name = source.timezone_name,
            discovery_sources_json =
                source.discovery_sources_json,
            source_raw_account_snapshot_id =
                source.raw_account_snapshot_id,
            source_extracted_at_utc =
                source.extracted_at_utc,
            snapshot_hash = source.snapshot_hash,
            staged_at_utc = SYSUTCDATETIME()
        FROM stg.meta_ad_accounts AS target
        INNER JOIN #latest_accounts AS source
            ON source.account_object_id =
               target.account_object_id
        INNER JOIN #changed_accounts AS changed
            ON changed.account_object_id =
               source.account_object_id;

        INSERT INTO stg.meta_ad_accounts (
            account_object_id,
            account_id,
            account_name,
            account_status,
            currency,
            timezone_name,
            discovery_sources_json,
            source_raw_account_snapshot_id,
            source_extracted_at_utc,
            snapshot_hash
        )
        SELECT
            source.account_object_id,
            source.account_id,
            source.account_name,
            source.account_status,
            source.currency,
            source.timezone_name,
            source.discovery_sources_json,
            source.raw_account_snapshot_id,
            source.extracted_at_utc,
            source.snapshot_hash
        FROM #latest_accounts AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.meta_ad_accounts AS target
            WHERE target.account_object_id =
                  source.account_object_id
        );

        ;WITH ranked_insights AS (
            SELECT
                raw_insight_version_id,
                extracted_at_utc,
                date_start,
                date_stop,
                account_object_id,
                account_id,
                account_name,
                campaign_id,
                campaign_name,
                adset_id,
                adset_name,
                ad_id,
                ad_name,
                objective,
                optimization_goal,
                impressions,
                reach,
                frequency,
                clicks,
                inline_link_clicks,
                spend,
                cpm,
                cpc,
                ctr,
                actions_json,
                action_values_json,
                cost_per_action_type_json,
                payload_hash,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        date_start,
                        account_object_id,
                        ad_id
                    ORDER BY
                        extracted_at_utc DESC,
                        raw_insight_version_id DESC
                ) AS row_number
            FROM raw.meta_ad_insight_versions
        )
        SELECT
            raw_insight_version_id,
            extracted_at_utc,
            date_start,
            date_stop,
            account_object_id,
            account_id,
            account_name,
            campaign_id,
            campaign_name,
            adset_id,
            adset_name,
            ad_id,
            ad_name,
            objective,
            optimization_goal,
            impressions,
            reach,
            frequency,
            clicks,
            inline_link_clicks,
            spend,
            cpm,
            cpc,
            ctr,
            actions_json,
            action_values_json,
            cost_per_action_type_json,
            payload_hash
        INTO #latest_insights
        FROM ranked_insights
        WHERE row_number = 1;

        CREATE UNIQUE CLUSTERED INDEX
            IX_latest_meta_insights
        ON #latest_insights (
            date_start,
            account_object_id,
            ad_id
        );

        SELECT
            source.date_start,
            source.account_object_id,
            source.ad_id
        INTO #changed_insights
        FROM #latest_insights AS source
        LEFT JOIN stg.meta_ad_insights AS target
            ON target.date_start =
               source.date_start
           AND target.account_object_id =
               source.account_object_id
           AND target.ad_id = source.ad_id
        WHERE target.ad_id IS NULL
           OR target.source_raw_insight_version_id <>
              source.raw_insight_version_id;

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_meta_insights
        ON #changed_insights (
            date_start,
            account_object_id,
            ad_id
        );

        UPDATE target
        SET
            date_stop = source.date_stop,
            account_id = source.account_id,
            account_name = source.account_name,
            campaign_id = source.campaign_id,
            campaign_name = source.campaign_name,
            adset_id = source.adset_id,
            adset_name = source.adset_name,
            ad_name = source.ad_name,
            objective = source.objective,
            optimization_goal =
                source.optimization_goal,
            impressions = source.impressions,
            reach = source.reach,
            frequency = source.frequency,
            clicks = source.clicks,
            inline_link_clicks =
                source.inline_link_clicks,
            spend = source.spend,
            cpm = source.cpm,
            cpc = source.cpc,
            ctr = source.ctr,
            actions_json = source.actions_json,
            action_values_json =
                source.action_values_json,
            cost_per_action_type_json =
                source.cost_per_action_type_json,
            source_raw_insight_version_id =
                source.raw_insight_version_id,
            source_extracted_at_utc =
                source.extracted_at_utc,
            payload_hash = source.payload_hash,
            staged_at_utc = SYSUTCDATETIME()
        FROM stg.meta_ad_insights AS target
        INNER JOIN #latest_insights AS source
            ON source.date_start =
               target.date_start
           AND source.account_object_id =
               target.account_object_id
           AND source.ad_id = target.ad_id
        INNER JOIN #changed_insights AS changed
            ON changed.date_start =
               source.date_start
           AND changed.account_object_id =
               source.account_object_id
           AND changed.ad_id = source.ad_id;

        INSERT INTO stg.meta_ad_insights (
            date_start,
            date_stop,
            account_object_id,
            account_id,
            account_name,
            campaign_id,
            campaign_name,
            adset_id,
            adset_name,
            ad_id,
            ad_name,
            objective,
            optimization_goal,
            impressions,
            reach,
            frequency,
            clicks,
            inline_link_clicks,
            spend,
            cpm,
            cpc,
            ctr,
            actions_json,
            action_values_json,
            cost_per_action_type_json,
            source_raw_insight_version_id,
            source_extracted_at_utc,
            payload_hash
        )
        SELECT
            source.date_start,
            source.date_stop,
            source.account_object_id,
            source.account_id,
            source.account_name,
            source.campaign_id,
            source.campaign_name,
            source.adset_id,
            source.adset_name,
            source.ad_id,
            source.ad_name,
            source.objective,
            source.optimization_goal,
            source.impressions,
            source.reach,
            source.frequency,
            source.clicks,
            source.inline_link_clicks,
            source.spend,
            source.cpm,
            source.cpc,
            source.ctr,
            source.actions_json,
            source.action_values_json,
            source.cost_per_action_type_json,
            source.raw_insight_version_id,
            source.extracted_at_utc,
            source.payload_hash
        FROM #latest_insights AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.meta_ad_insights AS target
            WHERE target.date_start =
                  source.date_start
              AND target.account_object_id =
                  source.account_object_id
              AND target.ad_id = source.ad_id
        );

        DECLARE @changed_account_count INT = (
            SELECT COUNT(*)
            FROM #changed_accounts
        );

        DECLARE @changed_insight_count INT = (
            SELECT COUNT(*)
            FROM #changed_insights
        );

        COMMIT TRANSACTION;

        SELECT
            @changed_account_count
                AS changed_accounts,
            (
                SELECT COUNT(*)
                FROM stg.meta_ad_accounts
            ) AS staged_accounts,
            @changed_insight_count
                AS changed_insights,
            (
                SELECT COUNT(*)
                FROM stg.meta_ad_insights
            ) AS staged_insights;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;