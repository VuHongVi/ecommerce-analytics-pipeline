SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'mart') IS NULL
    BEGIN
        EXEC(N'CREATE SCHEMA mart;');
    END;

    IF OBJECT_ID(
        N'mart.business_scope_rules',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE mart.business_scope_rules (
            scope_rule_id BIGINT IDENTITY(1, 1)
                NOT NULL,

            object_type VARCHAR(30)
                NOT NULL,

            object_id NVARCHAR(100)
                NOT NULL,

            scope_status VARCHAR(20)
                NOT NULL,

            project_code VARCHAR(50)
                NOT NULL,

            effective_from DATE
                NOT NULL,

            effective_to DATE
                NULL,

            rule_source VARCHAR(50)
                NOT NULL,

            reason NVARCHAR(500)
                NULL,

            created_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_business_scope_rules_created_at
                DEFAULT SYSUTCDATETIME(),

            updated_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_business_scope_rules_updated_at
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_business_scope_rules
                PRIMARY KEY CLUSTERED (
                    scope_rule_id
                ),

            CONSTRAINT CK_business_scope_rules_object_type
                CHECK (
                    object_type IN (
                        'META_ACCOUNT',
                        'PANCAKE_PAGE'
                    )
                ),

            CONSTRAINT CK_business_scope_rules_status
                CHECK (
                    scope_status IN (
                        'IN_SCOPE',
                        'OUT_OF_SCOPE'
                    )
                ),

            CONSTRAINT CK_business_scope_rules_dates
                CHECK (
                    effective_to IS NULL
                    OR effective_to >= effective_from
                )
        );

        CREATE UNIQUE NONCLUSTERED INDEX
            UX_business_scope_rules_object_period
        ON mart.business_scope_rules (
            object_type,
            object_id,
            effective_from
        );

        CREATE NONCLUSTERED INDEX
            IX_business_scope_rules_lookup
        ON mart.business_scope_rules (
            object_type,
            object_id,
            effective_from,
            effective_to
        )
        INCLUDE (
            scope_status,
            project_code,
            rule_source
        );
    END;

    DECLARE @seed TABLE (
        object_type VARCHAR(30) NOT NULL,
        object_id NVARCHAR(100) NOT NULL,
        scope_status VARCHAR(20) NOT NULL,
        project_code VARCHAR(50) NOT NULL,
        effective_from DATE NOT NULL,
        effective_to DATE NULL,
        rule_source VARCHAR(50) NOT NULL,
        reason NVARCHAR(500) NULL,

        PRIMARY KEY (
            object_type,
            object_id,
            effective_from
        )
    );

    /*
     * Confirmed Meta accounts belonging to the Ginseng project.
     */
    INSERT INTO @seed (
        object_type,
        object_id,
        scope_status,
        project_code,
        effective_from,
        effective_to,
        rule_source,
        reason
    )
    VALUES
        ('META_ACCOUNT', '1367154974160802', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '711528854403732', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '344459801734752', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '1559539891555386', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '543361911609285', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '453698237717833', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '1890443911325609', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '794292349063386', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '1040290852807707', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '1060063492513859', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '26959527980360446', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '1184644462623898', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '3885012595094715', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '851279377147573', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '411154802018696', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '1938064663357469', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '1338512436827769', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '853834086848053', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '795906585687410', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '485731404208739', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '1454017878598877', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account'),
        ('META_ACCOUNT', '2709026155928384', 'OUT_OF_SCOPE', 'GINSENG', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Ginseng Meta account');

    /*
     * Confirmed Meta accounts belonging to the Real Estate project.
     */
    INSERT INTO @seed (
        object_type,
        object_id,
        scope_status,
        project_code,
        effective_from,
        effective_to,
        rule_source,
        reason
    )
    VALUES
        ('META_ACCOUNT', '296495136191901', 'OUT_OF_SCOPE', 'REAL_ESTATE', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Real Estate Meta account'),
        ('META_ACCOUNT', '332832132864043', 'OUT_OF_SCOPE', 'REAL_ESTATE', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Real Estate Meta account'),
        ('META_ACCOUNT', '3662692263967959', 'OUT_OF_SCOPE', 'REAL_ESTATE', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Real Estate Meta account'),
        ('META_ACCOUNT', '699061985749862', 'OUT_OF_SCOPE', 'REAL_ESTATE', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Real Estate Meta account'),
        ('META_ACCOUNT', '885721206295982', 'OUT_OF_SCOPE', 'REAL_ESTATE', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Real Estate Meta account');

    /*
     * Confirmed Pancake pages used for Real Estate lead generation.
     */
    INSERT INTO @seed (
        object_type,
        object_id,
        scope_status,
        project_code,
        effective_from,
        effective_to,
        rule_source,
        reason
    )
    VALUES
        ('PANCAKE_PAGE', '112702968408846', 'OUT_OF_SCOPE', 'REAL_ESTATE', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Real Estate lead page'),
        ('PANCAKE_PAGE', '130953123428911', 'OUT_OF_SCOPE', 'REAL_ESTATE', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Real Estate lead page'),
        ('PANCAKE_PAGE', '932249486636618', 'OUT_OF_SCOPE', 'REAL_ESTATE', '19000101', NULL, 'SYSTEM_SEED_V1', N'Confirmed Real Estate lead page');

    MERGE mart.business_scope_rules AS target
    USING @seed AS source
        ON source.object_type = target.object_type
       AND source.object_id = target.object_id
       AND source.effective_from = target.effective_from

    WHEN MATCHED
     AND EXISTS (
        SELECT
            source.scope_status,
            source.project_code,
            source.effective_to,
            source.rule_source,
            source.reason

        EXCEPT

        SELECT
            target.scope_status,
            target.project_code,
            target.effective_to,
            target.rule_source,
            target.reason
     )
    THEN UPDATE SET
        scope_status = source.scope_status,
        project_code = source.project_code,
        effective_to = source.effective_to,
        rule_source = source.rule_source,
        reason = source.reason,
        updated_at_utc = SYSUTCDATETIME()

    WHEN NOT MATCHED BY TARGET
    THEN INSERT (
        object_type,
        object_id,
        scope_status,
        project_code,
        effective_from,
        effective_to,
        rule_source,
        reason
    )
    VALUES (
        source.object_type,
        source.object_id,
        source.scope_status,
        source.project_code,
        source.effective_from,
        source.effective_to,
        source.rule_source,
        source.reason
    );

    DECLARE @overlap_count INT = (
        SELECT COUNT(*)
        FROM mart.business_scope_rules AS left_rule
        INNER JOIN mart.business_scope_rules AS right_rule
            ON right_rule.object_type = left_rule.object_type
           AND right_rule.object_id = left_rule.object_id
           AND right_rule.scope_rule_id > left_rule.scope_rule_id
           AND right_rule.effective_from <= COALESCE(
                left_rule.effective_to,
                CONVERT(DATE, '99991231')
           )
           AND left_rule.effective_from <= COALESCE(
                right_rule.effective_to,
                CONVERT(DATE, '99991231')
           )
    );

    IF @overlap_count > 0
    BEGIN
        THROW 51000,
            'Overlapping business scope rules detected.',
            1;
    END;

    COMMIT TRANSACTION;

    SELECT
        COUNT(*) AS total_rules,

        SUM(
            CASE
                WHEN object_type = 'META_ACCOUNT'
                 AND project_code = 'GINSENG'
                 AND scope_status = 'OUT_OF_SCOPE'
                THEN 1
                ELSE 0
            END
        ) AS ginseng_account_rules,

        SUM(
            CASE
                WHEN object_type = 'META_ACCOUNT'
                 AND project_code = 'REAL_ESTATE'
                 AND scope_status = 'OUT_OF_SCOPE'
                THEN 1
                ELSE 0
            END
        ) AS real_estate_account_rules,

        SUM(
            CASE
                WHEN object_type = 'PANCAKE_PAGE'
                 AND project_code = 'REAL_ESTATE'
                 AND scope_status = 'OUT_OF_SCOPE'
                THEN 1
                ELSE 0
            END
        ) AS real_estate_page_rules,

        @overlap_count AS overlapping_rules

    FROM mart.business_scope_rules;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
