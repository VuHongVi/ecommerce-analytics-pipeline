SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(
        N'stg.product_cost_estimates',
        N'U'
    ) IS NULL
    BEGIN
        CREATE TABLE stg.product_cost_estimates (
            internal_product_id BIGINT NOT NULL,
            estimated_unit_cost
                DECIMAL(19, 2) NOT NULL,

            estimate_method VARCHAR(50) NOT NULL,
            estimate_reason NVARCHAR(500) NULL,

            created_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_stg_cost_estimate_created
                DEFAULT SYSUTCDATETIME(),

            updated_at_utc DATETIME2(3)
                NOT NULL
                CONSTRAINT DF_stg_cost_estimate_updated
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_stg_product_cost_estimates
                PRIMARY KEY (internal_product_id),

            CONSTRAINT FK_stg_cost_estimate_product
                FOREIGN KEY (internal_product_id)
                REFERENCES stg.product_registry (
                    internal_product_id
                ),

            CONSTRAINT CK_stg_cost_estimate_positive
                CHECK (estimated_unit_cost > 0),

            CONSTRAINT CK_stg_cost_estimate_method
                CHECK (
                    estimate_method IN (
                        'ESTIMATED_DEFAULT',
                        'MANUAL_ESTIMATE'
                    )
                )
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;