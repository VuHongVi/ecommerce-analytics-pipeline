SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'mart.business_scope_rules',
        N'U'
    ) IS NULL
    BEGIN
        THROW 51601,
            'mart.business_scope_rules does not exist.',
            1;
    END;

    IF OBJECT_ID(
        N'mart.order_scope_assignments',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE mart.order_scope_assignments (
            shop_id NVARCHAR(100) NOT NULL,
            order_id NVARCHAR(100) NOT NULL,
            order_date DATE NOT NULL,

            page_id NVARCHAR(100) NULL,
            page_name NVARCHAR(500) NULL,

            scope_status VARCHAR(20) NOT NULL,
            is_in_scope BIT NOT NULL,
            project_code VARCHAR(50) NOT NULL,
            assignment_method VARCHAR(30) NOT NULL,
            scope_rule_id BIGINT NULL,

            scope_refreshed_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_order_scope_refreshed
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_order_scope_assignments
                PRIMARY KEY CLUSTERED (
                    shop_id,
                    order_id
                ),

            CONSTRAINT FK_order_scope_rule
                FOREIGN KEY (scope_rule_id)
                REFERENCES mart.business_scope_rules (
                    scope_rule_id
                ),

            CONSTRAINT CK_order_scope_status
                CHECK (
                    scope_status IN (
                        'IN_SCOPE',
                        'OUT_OF_SCOPE'
                    )
                ),

            CONSTRAINT CK_order_scope_flag
                CHECK (
                    (
                        scope_status = 'IN_SCOPE'
                        AND is_in_scope = 1
                    )
                    OR (
                        scope_status = 'OUT_OF_SCOPE'
                        AND is_in_scope = 0
                    )
                ),

            CONSTRAINT CK_order_scope_method
                CHECK (
                    assignment_method IN (
                        'PAGE_RULE',
                        'DEFAULT_IN_SCOPE'
                    )
                ),

            CONSTRAINT CK_order_scope_rule_method
                CHECK (
                    (
                        assignment_method = 'PAGE_RULE'
                        AND scope_rule_id IS NOT NULL
                    )
                    OR (
                        assignment_method =
                            'DEFAULT_IN_SCOPE'
                        AND scope_rule_id IS NULL
                        AND scope_status = 'IN_SCOPE'
                        AND project_code = 'ECOMMERCE'
                    )
                )
        );

        CREATE NONCLUSTERED INDEX
            IX_order_scope_status_date
        ON mart.order_scope_assignments (
            scope_status,
            order_date
        )
        INCLUDE (
            project_code,
            page_id
        );

        CREATE NONCLUSTERED INDEX
            IX_order_scope_project_date
        ON mart.order_scope_assignments (
            project_code,
            order_date
        );
    END;

    IF OBJECT_ID(
        N'mart.ad_scope_assignments_daily',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE mart.ad_scope_assignments_daily (
            analysis_date DATE NOT NULL,
            ad_key BIGINT NOT NULL,

            account_id NVARCHAR(100) NULL,
            account_name NVARCHAR(500) NULL,

            scope_status VARCHAR(20) NOT NULL,
            is_in_scope BIT NOT NULL,
            project_code VARCHAR(50) NOT NULL,
            assignment_method VARCHAR(30) NOT NULL,
            scope_rule_id BIGINT NULL,

            scope_refreshed_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_ad_scope_refreshed
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_ad_scope_assignments_daily
                PRIMARY KEY CLUSTERED (
                    analysis_date,
                    ad_key
                ),

            CONSTRAINT FK_ad_scope_rule
                FOREIGN KEY (scope_rule_id)
                REFERENCES mart.business_scope_rules (
                    scope_rule_id
                ),

            CONSTRAINT CK_ad_scope_status
                CHECK (
                    scope_status IN (
                        'IN_SCOPE',
                        'OUT_OF_SCOPE'
                    )
                ),

            CONSTRAINT CK_ad_scope_flag
                CHECK (
                    (
                        scope_status = 'IN_SCOPE'
                        AND is_in_scope = 1
                    )
                    OR (
                        scope_status = 'OUT_OF_SCOPE'
                        AND is_in_scope = 0
                    )
                ),

            CONSTRAINT CK_ad_scope_method
                CHECK (
                    assignment_method IN (
                        'ACCOUNT_RULE',
                        'DEFAULT_IN_SCOPE'
                    )
                ),

            CONSTRAINT CK_ad_scope_rule_method
                CHECK (
                    (
                        assignment_method = 'ACCOUNT_RULE'
                        AND scope_rule_id IS NOT NULL
                    )
                    OR (
                        assignment_method =
                            'DEFAULT_IN_SCOPE'
                        AND scope_rule_id IS NULL
                        AND scope_status = 'IN_SCOPE'
                        AND project_code = 'ECOMMERCE'
                    )
                )
        );

        CREATE NONCLUSTERED INDEX
            IX_ad_scope_status_date
        ON mart.ad_scope_assignments_daily (
            scope_status,
            analysis_date
        )
        INCLUDE (
            project_code,
            ad_key,
            account_id
        );

        CREATE NONCLUSTERED INDEX
            IX_ad_scope_project_date
        ON mart.ad_scope_assignments_daily (
            project_code,
            analysis_date
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

CREATE OR ALTER PROCEDURE
    mart.refresh_business_scope_assignments
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID(
            N'mart.business_scope_rules',
            N'U'
        ) IS NULL
        BEGIN
            THROW 51602,
                'mart.business_scope_rules does not exist.',
                1;
        END;

        IF OBJECT_ID(
            N'mart.order_scope_assignments',
            N'U'
        ) IS NULL
        BEGIN
            THROW 51603,
                'mart.order_scope_assignments does not exist.',
                1;
        END;

        IF OBJECT_ID(
            N'mart.ad_scope_assignments_daily',
            N'U'
        ) IS NULL
        BEGIN
            THROW 51604,
                'mart.ad_scope_assignments_daily does not exist.',
                1;
        END;

        IF OBJECT_ID(
            N'mart.order_economics',
            N'U'
        ) IS NULL
        BEGIN
            THROW 51605,
                'mart.order_economics does not exist.',
                1;
        END;

        IF OBJECT_ID(
            N'mart.ad_economics_daily',
            N'U'
        ) IS NULL
        BEGIN
            THROW 51606,
                'mart.ad_economics_daily does not exist.',
                1;
        END;

        IF OBJECT_ID(
            N'mart.dim_meta_ads',
            N'U'
        ) IS NULL
        BEGIN
            THROW 51607,
                'mart.dim_meta_ads does not exist.',
                1;
        END;

        /*
         * Order scope is assigned using effective-dated Pancake page
         * rules. Orders without a matching rule remain Ecommerce.
         */
        SELECT
            orders.shop_id,
            orders.order_id,
            orders.order_date,
            orders.page_id,
            orders.page_name,

            CAST(
                COALESCE(
                    matched_rule.scope_status,
                    'IN_SCOPE'
                )
                AS VARCHAR(20)
            ) AS scope_status,

            CAST(
                CASE
                    WHEN matched_rule.scope_status =
                         'OUT_OF_SCOPE'
                    THEN 0
                    ELSE 1
                END
                AS BIT
            ) AS is_in_scope,

            CAST(
                COALESCE(
                    matched_rule.project_code,
                    'ECOMMERCE'
                )
                AS VARCHAR(50)
            ) AS project_code,

            CAST(
                CASE
                    WHEN matched_rule.scope_rule_id IS NULL
                    THEN 'DEFAULT_IN_SCOPE'
                    ELSE 'PAGE_RULE'
                END
                AS VARCHAR(30)
            ) AS assignment_method,

            matched_rule.scope_rule_id

        INTO #source_order_scope

        FROM mart.order_economics AS orders

        OUTER APPLY (
            SELECT TOP (1)
                rules.scope_rule_id,
                rules.scope_status,
                rules.project_code

            FROM mart.business_scope_rules AS rules

            WHERE rules.object_type = 'PANCAKE_PAGE'
              AND rules.object_id = orders.page_id
              AND rules.effective_from <= orders.order_date
              AND (
                    rules.effective_to IS NULL
                    OR rules.effective_to >= orders.order_date
              )

            ORDER BY
                rules.effective_from DESC,
                rules.scope_rule_id DESC
        ) AS matched_rule;

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_order_scope
        ON #source_order_scope (
            shop_id,
            order_id
        );

        SELECT
            source.shop_id,
            source.order_id

        INTO #changed_order_scope

        FROM #source_order_scope AS source

        LEFT JOIN mart.order_scope_assignments AS target
            ON target.shop_id = source.shop_id
           AND target.order_id = source.order_id

        WHERE target.order_id IS NULL
           OR EXISTS (
                SELECT
                    source.order_date,
                    source.page_id,
                    source.page_name,
                    source.scope_status,
                    source.is_in_scope,
                    source.project_code,
                    source.assignment_method,
                    source.scope_rule_id

                EXCEPT

                SELECT
                    target.order_date,
                    target.page_id,
                    target.page_name,
                    target.scope_status,
                    target.is_in_scope,
                    target.project_code,
                    target.assignment_method,
                    target.scope_rule_id
           );

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_order_scope
        ON #changed_order_scope (
            shop_id,
            order_id
        );

        DECLARE @inserted_order_assignments INT = (
            SELECT COUNT(*)
            FROM #source_order_scope AS source
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.order_scope_assignments AS target
                WHERE target.shop_id = source.shop_id
                  AND target.order_id = source.order_id
            )
        );

        DECLARE @updated_order_assignments INT = (
            SELECT COUNT(*)
            FROM #changed_order_scope AS changed
            WHERE EXISTS (
                SELECT 1
                FROM mart.order_scope_assignments AS target
                WHERE target.shop_id = changed.shop_id
                  AND target.order_id = changed.order_id
            )
        );

        DECLARE @deleted_order_assignments INT = (
            SELECT COUNT(*)
            FROM mart.order_scope_assignments AS target
            WHERE NOT EXISTS (
                SELECT 1
                FROM #source_order_scope AS source
                WHERE source.shop_id = target.shop_id
                  AND source.order_id = target.order_id
            )
        );

        DELETE target
        FROM mart.order_scope_assignments AS target
        WHERE NOT EXISTS (
            SELECT 1
            FROM #source_order_scope AS source
            WHERE source.shop_id = target.shop_id
              AND source.order_id = target.order_id
        );

        UPDATE target
        SET
            order_date = source.order_date,
            page_id = source.page_id,
            page_name = source.page_name,
            scope_status = source.scope_status,
            is_in_scope = source.is_in_scope,
            project_code = source.project_code,
            assignment_method = source.assignment_method,
            scope_rule_id = source.scope_rule_id,
            scope_refreshed_at_utc = SYSUTCDATETIME()

        FROM mart.order_scope_assignments AS target

        INNER JOIN #source_order_scope AS source
            ON source.shop_id = target.shop_id
           AND source.order_id = target.order_id

        INNER JOIN #changed_order_scope AS changed
            ON changed.shop_id = source.shop_id
           AND changed.order_id = source.order_id;

        INSERT INTO mart.order_scope_assignments (
            shop_id,
            order_id,
            order_date,
            page_id,
            page_name,
            scope_status,
            is_in_scope,
            project_code,
            assignment_method,
            scope_rule_id
        )
        SELECT
            source.shop_id,
            source.order_id,
            source.order_date,
            source.page_id,
            source.page_name,
            source.scope_status,
            source.is_in_scope,
            source.project_code,
            source.assignment_method,
            source.scope_rule_id

        FROM #source_order_scope AS source

        WHERE NOT EXISTS (
            SELECT 1
            FROM mart.order_scope_assignments AS target
            WHERE target.shop_id = source.shop_id
              AND target.order_id = source.order_id
        );

        /*
         * Ad cost scope is assigned at the existing date + ad grain
         * using the effective-dated Meta account rules.
         */
        SELECT
            facts.analysis_date,
            facts.ad_key,
            ads.account_id,
            ads.account_name,

            CAST(
                COALESCE(
                    matched_rule.scope_status,
                    'IN_SCOPE'
                )
                AS VARCHAR(20)
            ) AS scope_status,

            CAST(
                CASE
                    WHEN matched_rule.scope_status =
                         'OUT_OF_SCOPE'
                    THEN 0
                    ELSE 1
                END
                AS BIT
            ) AS is_in_scope,

            CAST(
                COALESCE(
                    matched_rule.project_code,
                    'ECOMMERCE'
                )
                AS VARCHAR(50)
            ) AS project_code,

            CAST(
                CASE
                    WHEN matched_rule.scope_rule_id IS NULL
                    THEN 'DEFAULT_IN_SCOPE'
                    ELSE 'ACCOUNT_RULE'
                END
                AS VARCHAR(30)
            ) AS assignment_method,

            matched_rule.scope_rule_id

        INTO #source_ad_scope

        FROM mart.ad_economics_daily AS facts

        INNER JOIN mart.dim_meta_ads AS ads
            ON ads.ad_key = facts.ad_key

        OUTER APPLY (
            SELECT TOP (1)
                rules.scope_rule_id,
                rules.scope_status,
                rules.project_code

            FROM mart.business_scope_rules AS rules

            WHERE rules.object_type = 'META_ACCOUNT'
              AND rules.object_id = ads.account_id
              AND rules.effective_from <= facts.analysis_date
              AND (
                    rules.effective_to IS NULL
                    OR rules.effective_to >= facts.analysis_date
              )

            ORDER BY
                rules.effective_from DESC,
                rules.scope_rule_id DESC
        ) AS matched_rule;

        CREATE UNIQUE CLUSTERED INDEX
            IX_source_ad_scope
        ON #source_ad_scope (
            analysis_date,
            ad_key
        );

        SELECT
            source.analysis_date,
            source.ad_key

        INTO #changed_ad_scope

        FROM #source_ad_scope AS source

        LEFT JOIN mart.ad_scope_assignments_daily AS target
            ON target.analysis_date = source.analysis_date
           AND target.ad_key = source.ad_key

        WHERE target.ad_key IS NULL
           OR EXISTS (
                SELECT
                    source.account_id,
                    source.account_name,
                    source.scope_status,
                    source.is_in_scope,
                    source.project_code,
                    source.assignment_method,
                    source.scope_rule_id

                EXCEPT

                SELECT
                    target.account_id,
                    target.account_name,
                    target.scope_status,
                    target.is_in_scope,
                    target.project_code,
                    target.assignment_method,
                    target.scope_rule_id
           );

        CREATE UNIQUE CLUSTERED INDEX
            IX_changed_ad_scope
        ON #changed_ad_scope (
            analysis_date,
            ad_key
        );

        DECLARE @inserted_ad_assignments INT = (
            SELECT COUNT(*)
            FROM #source_ad_scope AS source
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.ad_scope_assignments_daily AS target
                WHERE target.analysis_date =
                    source.analysis_date
                  AND target.ad_key = source.ad_key
            )
        );

        DECLARE @updated_ad_assignments INT = (
            SELECT COUNT(*)
            FROM #changed_ad_scope AS changed
            WHERE EXISTS (
                SELECT 1
                FROM mart.ad_scope_assignments_daily AS target
                WHERE target.analysis_date =
                    changed.analysis_date
                  AND target.ad_key = changed.ad_key
            )
        );

        DECLARE @deleted_ad_assignments INT = (
            SELECT COUNT(*)
            FROM mart.ad_scope_assignments_daily AS target
            WHERE NOT EXISTS (
                SELECT 1
                FROM #source_ad_scope AS source
                WHERE source.analysis_date =
                    target.analysis_date
                  AND source.ad_key = target.ad_key
            )
        );

        DELETE target
        FROM mart.ad_scope_assignments_daily AS target
        WHERE NOT EXISTS (
            SELECT 1
            FROM #source_ad_scope AS source
            WHERE source.analysis_date = target.analysis_date
              AND source.ad_key = target.ad_key
        );

        UPDATE target
        SET
            account_id = source.account_id,
            account_name = source.account_name,
            scope_status = source.scope_status,
            is_in_scope = source.is_in_scope,
            project_code = source.project_code,
            assignment_method = source.assignment_method,
            scope_rule_id = source.scope_rule_id,
            scope_refreshed_at_utc = SYSUTCDATETIME()

        FROM mart.ad_scope_assignments_daily AS target

        INNER JOIN #source_ad_scope AS source
            ON source.analysis_date = target.analysis_date
           AND source.ad_key = target.ad_key

        INNER JOIN #changed_ad_scope AS changed
            ON changed.analysis_date = source.analysis_date
           AND changed.ad_key = source.ad_key;

        INSERT INTO mart.ad_scope_assignments_daily (
            analysis_date,
            ad_key,
            account_id,
            account_name,
            scope_status,
            is_in_scope,
            project_code,
            assignment_method,
            scope_rule_id
        )
        SELECT
            source.analysis_date,
            source.ad_key,
            source.account_id,
            source.account_name,
            source.scope_status,
            source.is_in_scope,
            source.project_code,
            source.assignment_method,
            source.scope_rule_id

        FROM #source_ad_scope AS source

        WHERE NOT EXISTS (
            SELECT 1
            FROM mart.ad_scope_assignments_daily AS target
            WHERE target.analysis_date = source.analysis_date
              AND target.ad_key = source.ad_key
        );

        COMMIT TRANSACTION;

        SELECT
            @inserted_order_assignments
                AS inserted_order_assignments,
            @updated_order_assignments
                AS updated_order_assignments,
            @deleted_order_assignments
                AS deleted_order_assignments,

            (
                SELECT COUNT(*)
                FROM mart.order_scope_assignments
            ) AS order_assignment_rows,

            (
                SELECT COUNT(*)
                FROM mart.order_scope_assignments
                WHERE scope_status = 'IN_SCOPE'
            ) AS in_scope_orders,

            (
                SELECT COUNT(*)
                FROM mart.order_scope_assignments
                WHERE scope_status = 'OUT_OF_SCOPE'
            ) AS out_of_scope_orders,

            @inserted_ad_assignments
                AS inserted_ad_assignments,
            @updated_ad_assignments
                AS updated_ad_assignments,
            @deleted_ad_assignments
                AS deleted_ad_assignments,

            (
                SELECT COUNT(*)
                FROM mart.ad_scope_assignments_daily
            ) AS ad_assignment_rows,

            (
                SELECT COUNT(*)
                FROM mart.ad_scope_assignments_daily
                WHERE scope_status = 'IN_SCOPE'
            ) AS in_scope_ad_rows,

            (
                SELECT COUNT(*)
                FROM mart.ad_scope_assignments_daily
                WHERE scope_status = 'OUT_OF_SCOPE'
            ) AS out_of_scope_ad_rows,

            (
                SELECT CAST(
                    SUM(
                        CASE
                            WHEN scope.scope_status =
                                 'IN_SCOPE'
                            THEN facts.actual_ad_cost
                            ELSE 0
                        END
                    )
                    AS DECIMAL(19, 6)
                )
                FROM mart.ad_economics_daily AS facts
                INNER JOIN
                    mart.ad_scope_assignments_daily AS scope
                    ON scope.analysis_date =
                        facts.analysis_date
                   AND scope.ad_key = facts.ad_key
            ) AS in_scope_actual_ad_cost,

            (
                SELECT CAST(
                    SUM(
                        CASE
                            WHEN scope.scope_status =
                                 'OUT_OF_SCOPE'
                            THEN facts.actual_ad_cost
                            ELSE 0
                        END
                    )
                    AS DECIMAL(19, 6)
                )
                FROM mart.ad_economics_daily AS facts
                INNER JOIN
                    mart.ad_scope_assignments_daily AS scope
                    ON scope.analysis_date =
                        facts.analysis_date
                   AND scope.ad_key = facts.ad_key
            ) AS out_of_scope_actual_ad_cost;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
