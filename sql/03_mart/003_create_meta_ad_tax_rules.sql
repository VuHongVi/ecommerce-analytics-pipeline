SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'ref') IS NULL
    BEGIN
        EXEC(N'CREATE SCHEMA ref AUTHORIZATION dbo;');
    END;

    IF OBJECT_ID(
        N'ref.meta_ad_tax_rules',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE ref.meta_ad_tax_rules (
            currency VARCHAR(10) NOT NULL,
            valid_from DATE NOT NULL,
            valid_to DATE NULL,
            tax_rate DECIMAL(9, 6) NOT NULL,
            rule_note NVARCHAR(500) NULL,

            created_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_meta_ad_tax_rules_created
                DEFAULT SYSUTCDATETIME(),

            updated_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_meta_ad_tax_rules_updated
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_meta_ad_tax_rules
                PRIMARY KEY (
                    currency,
                    valid_from
                ),

            CONSTRAINT CK_meta_ad_tax_rate_range
                CHECK (
                    tax_rate >= 0
                    AND tax_rate <= 1
                ),

            CONSTRAINT CK_meta_ad_tax_date_range
                CHECK (
                    valid_to IS NULL
                    OR valid_to > valid_from
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM ref.meta_ad_tax_rules
        WHERE currency = 'VND'
          AND valid_from = '19000101'
    )
    BEGIN
        INSERT INTO ref.meta_ad_tax_rules (
            currency,
            valid_from,
            valid_to,
            tax_rate,
            rule_note
        )
        VALUES (
            'VND',
            '19000101',
            NULL,
            0.11,
            N'Meta spend is increased by 11 percent tax'
        );
    END;

    COMMIT TRANSACTION;

    SELECT
        currency,
        valid_from,
        valid_to,
        tax_rate,
        rule_note
    FROM ref.meta_ad_tax_rules
    ORDER BY
        currency,
        valid_from;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
