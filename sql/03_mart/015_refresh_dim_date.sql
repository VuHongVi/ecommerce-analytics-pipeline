CREATE OR ALTER PROCEDURE mart.refresh_dim_date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID(N'mart.dim_date', N'U') IS NULL
        BEGIN
            THROW 51501,
                'mart.dim_date does not exist.',
                1;
        END;

        DECLARE @current_date DATE =
            CAST(SYSUTCDATETIME() AS DATE);

        DECLARE @source_min_date DATE;
        DECLARE @source_max_date DATE;

        SELECT
            @source_min_date = MIN(source_date),
            @source_max_date = MAX(source_date)
        FROM (
            SELECT order_date AS source_date
            FROM mart.order_economics

            UNION ALL

            SELECT analysis_date AS source_date
            FROM mart.ad_economics_daily
        ) AS source_dates;

        SET @source_min_date = COALESCE(
            @source_min_date,
            @current_date
        );

        SET @source_max_date = CASE
            WHEN COALESCE(@source_max_date, @current_date)
                 > @current_date
            THEN @source_max_date
            ELSE @current_date
        END;

        DECLARE @start_date DATE = DATEFROMPARTS(
            YEAR(DATEADD(YEAR, -1, @source_min_date)),
            1,
            1
        );

        DECLARE @end_date DATE = DATEFROMPARTS(
            YEAR(DATEADD(YEAR, 1, @source_max_date)),
            12,
            31
        );

        ;WITH dates AS (
            SELECT @start_date AS full_date

            UNION ALL

            SELECT DATEADD(DAY, 1, full_date)
            FROM dates
            WHERE full_date < @end_date
        ),
        date_parts AS (
            SELECT
                full_date,
                YEAR(full_date) AS calendar_year,
                DATEPART(QUARTER, full_date)
                    AS calendar_quarter,
                MONTH(full_date) AS month_number,
                DATEPART(ISO_WEEK, full_date)
                    AS iso_week_number,
                DATEPART(DAYOFYEAR, full_date)
                    AS day_of_year,
                DAY(full_date) AS day_of_month,
                CAST(
                    DATEDIFF(
                        DAY,
                        CONVERT(DATE, '19000101'),
                        full_date
                    ) % 7 + 1
                    AS TINYINT
                ) AS iso_day_of_week
            FROM dates
        ),
        bounded AS (
            SELECT
                parts.*,
                DATEADD(
                    DAY,
                    1 - parts.iso_day_of_week,
                    parts.full_date
                ) AS week_start_date,
                DATEFROMPARTS(
                    parts.calendar_year,
                    parts.month_number,
                    1
                ) AS month_start_date,
                DATEFROMPARTS(
                    parts.calendar_year,
                    (parts.calendar_quarter - 1) * 3 + 1,
                    1
                ) AS quarter_start_date,
                DATEFROMPARTS(
                    parts.calendar_year,
                    1,
                    1
                ) AS year_start_date
            FROM date_parts AS parts
        )
        SELECT
            bounded.calendar_year * 10000
                + bounded.month_number * 100
                + bounded.day_of_month
                AS date_key,
            bounded.full_date,
            CAST(bounded.calendar_year AS SMALLINT)
                AS calendar_year,
            CAST(bounded.calendar_quarter AS TINYINT)
                AS calendar_quarter,
            CAST(
                CONCAT(
                    bounded.calendar_year,
                    '-Q',
                    bounded.calendar_quarter
                )
                AS CHAR(7)
            ) AS quarter_label,
            CAST(bounded.month_number AS TINYINT)
                AS month_number,
            CAST(
                CASE bounded.month_number
                    WHEN 1 THEN 'January'
                    WHEN 2 THEN 'February'
                    WHEN 3 THEN 'March'
                    WHEN 4 THEN 'April'
                    WHEN 5 THEN 'May'
                    WHEN 6 THEN 'June'
                    WHEN 7 THEN 'July'
                    WHEN 8 THEN 'August'
                    WHEN 9 THEN 'September'
                    WHEN 10 THEN 'October'
                    WHEN 11 THEN 'November'
                    WHEN 12 THEN 'December'
                END
                AS VARCHAR(20)
            ) AS month_name_en,
            CAST(
                CONCAT(N'Tháng ', bounded.month_number)
                AS NVARCHAR(20)
            ) AS month_name_vi,
            bounded.calendar_year * 100
                + bounded.month_number
                AS year_month_key,
            CAST(
                CONCAT(
                    bounded.calendar_year,
                    '-',
                    RIGHT(
                        CONCAT('0', bounded.month_number),
                        2
                    )
                )
                AS CHAR(7)
            ) AS year_month_label,
            CAST(bounded.iso_week_number AS TINYINT)
                AS iso_week_number,
            CAST(bounded.day_of_year AS SMALLINT)
                AS day_of_year,
            CAST(bounded.day_of_month AS TINYINT)
                AS day_of_month,
            bounded.iso_day_of_week,
            CAST(
                CASE bounded.iso_day_of_week
                    WHEN 1 THEN 'Monday'
                    WHEN 2 THEN 'Tuesday'
                    WHEN 3 THEN 'Wednesday'
                    WHEN 4 THEN 'Thursday'
                    WHEN 5 THEN 'Friday'
                    WHEN 6 THEN 'Saturday'
                    WHEN 7 THEN 'Sunday'
                END
                AS VARCHAR(20)
            ) AS day_name_en,
            CAST(
                CASE bounded.iso_day_of_week
                    WHEN 1 THEN N'Thứ Hai'
                    WHEN 2 THEN N'Thứ Ba'
                    WHEN 3 THEN N'Thứ Tư'
                    WHEN 4 THEN N'Thứ Năm'
                    WHEN 5 THEN N'Thứ Sáu'
                    WHEN 6 THEN N'Thứ Bảy'
                    WHEN 7 THEN N'Chủ Nhật'
                END
                AS NVARCHAR(20)
            ) AS day_name_vi,
            bounded.week_start_date,
            DATEADD(DAY, 6, bounded.week_start_date)
                AS week_end_date,
            bounded.month_start_date,
            EOMONTH(bounded.full_date) AS month_end_date,
            bounded.quarter_start_date,
            EOMONTH(
                DATEADD(
                    MONTH,
                    2,
                    bounded.quarter_start_date
                )
            ) AS quarter_end_date,
            bounded.year_start_date,
            DATEFROMPARTS(
                bounded.calendar_year,
                12,
                31
            ) AS year_end_date,
            CAST(
                CASE
                    WHEN bounded.iso_day_of_week IN (6, 7)
                    THEN 1 ELSE 0
                END
                AS BIT
            ) AS is_weekend,
            CAST(
                CASE
                    WHEN bounded.full_date =
                         EOMONTH(bounded.full_date)
                    THEN 1 ELSE 0
                END
                AS BIT
            ) AS is_month_end,
            CAST(
                CASE
                    WHEN bounded.full_date = EOMONTH(
                        DATEADD(
                            MONTH,
                            2,
                            bounded.quarter_start_date
                        )
                    )
                    THEN 1 ELSE 0
                END
                AS BIT
            ) AS is_quarter_end,
            CAST(
                CASE
                    WHEN bounded.full_date = DATEFROMPARTS(
                        bounded.calendar_year,
                        12,
                        31
                    )
                    THEN 1 ELSE 0
                END
                AS BIT
            ) AS is_year_end
        INTO #source_dim_date
        FROM bounded
        OPTION (MAXRECURSION 0);

        CREATE UNIQUE CLUSTERED INDEX IX_source_dim_date
            ON #source_dim_date (date_key);

        SELECT source.date_key
        INTO #changed_dim_date
        FROM #source_dim_date AS source
        LEFT JOIN mart.dim_date AS target
            ON target.date_key = source.date_key
        WHERE target.date_key IS NULL
           OR EXISTS (
                SELECT
                    source.full_date,
                    source.calendar_year,
                    source.calendar_quarter,
                    source.quarter_label,
                    source.month_number,
                    source.month_name_en,
                    source.month_name_vi,
                    source.year_month_key,
                    source.year_month_label,
                    source.iso_week_number,
                    source.day_of_year,
                    source.day_of_month,
                    source.iso_day_of_week,
                    source.day_name_en,
                    source.day_name_vi,
                    source.week_start_date,
                    source.week_end_date,
                    source.month_start_date,
                    source.month_end_date,
                    source.quarter_start_date,
                    source.quarter_end_date,
                    source.year_start_date,
                    source.year_end_date,
                    source.is_weekend,
                    source.is_month_end,
                    source.is_quarter_end,
                    source.is_year_end

                EXCEPT

                SELECT
                    target.full_date,
                    target.calendar_year,
                    target.calendar_quarter,
                    target.quarter_label,
                    target.month_number,
                    target.month_name_en,
                    target.month_name_vi,
                    target.year_month_key,
                    target.year_month_label,
                    target.iso_week_number,
                    target.day_of_year,
                    target.day_of_month,
                    target.iso_day_of_week,
                    target.day_name_en,
                    target.day_name_vi,
                    target.week_start_date,
                    target.week_end_date,
                    target.month_start_date,
                    target.month_end_date,
                    target.quarter_start_date,
                    target.quarter_end_date,
                    target.year_start_date,
                    target.year_end_date,
                    target.is_weekend,
                    target.is_month_end,
                    target.is_quarter_end,
                    target.is_year_end
           );

        CREATE UNIQUE CLUSTERED INDEX IX_changed_dim_date
            ON #changed_dim_date (date_key);

        DECLARE @inserted_date_count INT = (
            SELECT COUNT(*)
            FROM #source_dim_date AS source
            WHERE NOT EXISTS (
                SELECT 1
                FROM mart.dim_date AS target
                WHERE target.date_key = source.date_key
            )
        );

        DECLARE @updated_date_count INT = (
            SELECT COUNT(*)
            FROM #changed_dim_date AS changed
            WHERE EXISTS (
                SELECT 1
                FROM mart.dim_date AS target
                WHERE target.date_key = changed.date_key
            )
        );

        UPDATE target
        SET
            full_date = source.full_date,
            calendar_year = source.calendar_year,
            calendar_quarter = source.calendar_quarter,
            quarter_label = source.quarter_label,
            month_number = source.month_number,
            month_name_en = source.month_name_en,
            month_name_vi = source.month_name_vi,
            year_month_key = source.year_month_key,
            year_month_label = source.year_month_label,
            iso_week_number = source.iso_week_number,
            day_of_year = source.day_of_year,
            day_of_month = source.day_of_month,
            iso_day_of_week = source.iso_day_of_week,
            day_name_en = source.day_name_en,
            day_name_vi = source.day_name_vi,
            week_start_date = source.week_start_date,
            week_end_date = source.week_end_date,
            month_start_date = source.month_start_date,
            month_end_date = source.month_end_date,
            quarter_start_date = source.quarter_start_date,
            quarter_end_date = source.quarter_end_date,
            year_start_date = source.year_start_date,
            year_end_date = source.year_end_date,
            is_weekend = source.is_weekend,
            is_month_end = source.is_month_end,
            is_quarter_end = source.is_quarter_end,
            is_year_end = source.is_year_end,
            updated_at_utc = SYSUTCDATETIME()
        FROM mart.dim_date AS target
        INNER JOIN #source_dim_date AS source
            ON source.date_key = target.date_key
        INNER JOIN #changed_dim_date AS changed
            ON changed.date_key = source.date_key;

        INSERT INTO mart.dim_date (
            date_key,
            full_date,
            calendar_year,
            calendar_quarter,
            quarter_label,
            month_number,
            month_name_en,
            month_name_vi,
            year_month_key,
            year_month_label,
            iso_week_number,
            day_of_year,
            day_of_month,
            iso_day_of_week,
            day_name_en,
            day_name_vi,
            week_start_date,
            week_end_date,
            month_start_date,
            month_end_date,
            quarter_start_date,
            quarter_end_date,
            year_start_date,
            year_end_date,
            is_weekend,
            is_month_end,
            is_quarter_end,
            is_year_end
        )
        SELECT
            source.date_key,
            source.full_date,
            source.calendar_year,
            source.calendar_quarter,
            source.quarter_label,
            source.month_number,
            source.month_name_en,
            source.month_name_vi,
            source.year_month_key,
            source.year_month_label,
            source.iso_week_number,
            source.day_of_year,
            source.day_of_month,
            source.iso_day_of_week,
            source.day_name_en,
            source.day_name_vi,
            source.week_start_date,
            source.week_end_date,
            source.month_start_date,
            source.month_end_date,
            source.quarter_start_date,
            source.quarter_end_date,
            source.year_start_date,
            source.year_end_date,
            source.is_weekend,
            source.is_month_end,
            source.is_quarter_end,
            source.is_year_end
        FROM #source_dim_date AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM mart.dim_date AS target
            WHERE target.date_key = source.date_key
        );

        COMMIT TRANSACTION;

        SELECT
            @inserted_date_count AS inserted_dates,
            @updated_date_count AS updated_dates,
            COUNT(*) AS dimension_rows,
            MIN(full_date) AS minimum_date,
            MAX(full_date) AS maximum_date
        FROM mart.dim_date;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
