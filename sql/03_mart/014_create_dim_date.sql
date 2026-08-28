SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF SCHEMA_ID(N'mart') IS NULL
    BEGIN
        EXEC(N'CREATE SCHEMA mart;');
    END;

    IF OBJECT_ID(N'mart.dim_date', N'U') IS NULL
    BEGIN
        CREATE TABLE mart.dim_date (
            date_key INT NOT NULL,
            full_date DATE NOT NULL,

            calendar_year SMALLINT NOT NULL,
            calendar_quarter TINYINT NOT NULL,
            quarter_label CHAR(7) NOT NULL,

            month_number TINYINT NOT NULL,
            month_name_en VARCHAR(20) NOT NULL,
            month_name_vi NVARCHAR(20) NOT NULL,
            year_month_key INT NOT NULL,
            year_month_label CHAR(7) NOT NULL,

            iso_week_number TINYINT NOT NULL,
            day_of_year SMALLINT NOT NULL,
            day_of_month TINYINT NOT NULL,
            iso_day_of_week TINYINT NOT NULL,
            day_name_en VARCHAR(20) NOT NULL,
            day_name_vi NVARCHAR(20) NOT NULL,

            week_start_date DATE NOT NULL,
            week_end_date DATE NOT NULL,
            month_start_date DATE NOT NULL,
            month_end_date DATE NOT NULL,
            quarter_start_date DATE NOT NULL,
            quarter_end_date DATE NOT NULL,
            year_start_date DATE NOT NULL,
            year_end_date DATE NOT NULL,

            is_weekend BIT NOT NULL,
            is_month_end BIT NOT NULL,
            is_quarter_end BIT NOT NULL,
            is_year_end BIT NOT NULL,

            created_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_dim_date_created
                DEFAULT SYSUTCDATETIME(),
            updated_at_utc DATETIME2(3) NOT NULL
                CONSTRAINT DF_dim_date_updated
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_dim_date
                PRIMARY KEY CLUSTERED (date_key),
            CONSTRAINT UQ_dim_date_full_date
                UNIQUE (full_date),
            CONSTRAINT CK_dim_date_key
                CHECK (
                    date_key =
                        YEAR(full_date) * 10000
                        + MONTH(full_date) * 100
                        + DAY(full_date)
                ),
            CONSTRAINT CK_dim_date_quarter
                CHECK (calendar_quarter BETWEEN 1 AND 4),
            CONSTRAINT CK_dim_date_month
                CHECK (month_number BETWEEN 1 AND 12),
            CONSTRAINT CK_dim_date_week
                CHECK (iso_week_number BETWEEN 1 AND 53),
            CONSTRAINT CK_dim_date_day
                CHECK (
                    day_of_year BETWEEN 1 AND 366
                    AND day_of_month BETWEEN 1 AND 31
                    AND iso_day_of_week BETWEEN 1 AND 7
                ),
            CONSTRAINT CK_dim_date_ranges
                CHECK (
                    full_date BETWEEN week_start_date
                                      AND week_end_date
                    AND full_date BETWEEN month_start_date
                                      AND month_end_date
                    AND full_date BETWEEN quarter_start_date
                                      AND quarter_end_date
                    AND full_date BETWEEN year_start_date
                                      AND year_end_date
                )
        );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_dim_date_year_month'
          AND object_id = OBJECT_ID(N'mart.dim_date')
    )
    BEGIN
        CREATE INDEX IX_dim_date_year_month
            ON mart.dim_date (
                calendar_year,
                month_number,
                full_date
            )
            INCLUDE (
                year_month_key,
                year_month_label,
                month_name_en,
                month_name_vi
            );
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE [name] = N'IX_dim_date_iso_week'
          AND object_id = OBJECT_ID(N'mart.dim_date')
    )
    BEGIN
        CREATE INDEX IX_dim_date_iso_week
            ON mart.dim_date (
                calendar_year,
                iso_week_number,
                full_date
            );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
