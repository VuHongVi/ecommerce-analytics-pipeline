SET NOCOUNT ON;
SET XACT_ABORT ON;

IF SCHEMA_ID(N'ref') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA ref AUTHORIZATION dbo;');
END;

IF OBJECT_ID(
    N'ref.shipping_return_fee_rules',
    N'U'
) IS NULL
BEGIN
    CREATE TABLE ref.shipping_return_fee_rules (
        shipping_partner_code VARCHAR(20) NOT NULL,
        valid_from DATE NOT NULL,
        valid_to DATE NULL,
        return_surcharge DECIMAL(19, 2) NOT NULL,
        rule_note NVARCHAR(500) NULL,

        created_at_utc DATETIME2(3) NOT NULL
            CONSTRAINT DF_shipping_return_fee_rules_created
            DEFAULT SYSUTCDATETIME(),

        updated_at_utc DATETIME2(3) NOT NULL
            CONSTRAINT DF_shipping_return_fee_rules_updated
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_shipping_return_fee_rules
            PRIMARY KEY (
                shipping_partner_code,
                valid_from
            ),

        CONSTRAINT CK_shipping_return_fee_nonnegative
            CHECK (return_surcharge >= 0),

        CONSTRAINT CK_shipping_return_fee_date_range
            CHECK (
                valid_to IS NULL
                OR valid_to > valid_from
            )
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM ref.shipping_return_fee_rules
    WHERE shipping_partner_code = 'GHTK'
      AND valid_from = '19000101'
)
BEGIN
    INSERT INTO ref.shipping_return_fee_rules (
        shipping_partner_code,
        valid_from,
        valid_to,
        return_surcharge,
        rule_note
    )
    VALUES (
        'GHTK',
        '19000101',
        NULL,
        10635,
        N'Initial rule applied to all existing GHTK orders'
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM ref.shipping_return_fee_rules
    WHERE shipping_partner_code = 'SPX'
      AND valid_from = '19000101'
)
BEGIN
    INSERT INTO ref.shipping_return_fee_rules (
        shipping_partner_code,
        valid_from,
        valid_to,
        return_surcharge,
        rule_note
    )
    VALUES (
        'SPX',
        '19000101',
        NULL,
        0,
        N'Initial rule applied to all existing SPX orders'
    );
END;

SELECT
    shipping_partner_code,
    valid_from,
    valid_to,
    return_surcharge,
    rule_note
FROM ref.shipping_return_fee_rules
ORDER BY
    shipping_partner_code,
    valid_from;