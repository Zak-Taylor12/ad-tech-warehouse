-- A calendar table covering every date in the dataset's range,
-- including days with zero activity. Without this, a day with
-- no events would just vanish from a chart instead of showing
-- up as a real zero.
-- ============================================================

CREATE OR REPLACE TABLE CHALICE_PORTFOLIO.MARTS.DIM_DATE AS

-- Generate one row per day from Jan 1 to Jun 30, 2026.
-- GENERATOR spins up empty rows, SEQ4 numbers them starting at 0,
-- and DATEADD uses that number to step forward one day at a time
-- from the start date.
WITH date_spine AS (
    SELECT
        DATEADD(DAY, SEQ4(), '2026-01-01'::DATE) AS calendar_date
    FROM TABLE(GENERATOR(ROWCOUNT => 365))
    WHERE calendar_date <= '2026-06-30'::DATE
)

-- Add the calendar attributes that make filtering and grouping
-- easy later on in Superset (by month, by weekday, etc.).
SELECT
    calendar_date,
    YEAR(calendar_date)                       AS year,
    QUARTER(calendar_date)                    AS quarter,
    MONTH(calendar_date)                      AS month,
    MONTHNAME(calendar_date)                  AS month_name,
    DAY(calendar_date)                        AS day_of_month,
    DAYOFWEEK(calendar_date)                  AS day_of_week,
    DAYNAME(calendar_date)                    AS day_name,
    CASE
        WHEN DAYOFWEEK(calendar_date) IN (0, 6) THEN TRUE
        ELSE FALSE
    END AS is_weekend
FROM date_spine
ORDER BY calendar_date;

-- Expect 181 rows, spanning Jan 1 through Jun 30, 2026.
SELECT COUNT(*), MIN(calendar_date), MAX(calendar_date)
FROM CHALICE_PORTFOLIO.MARTS.DIM_DATE;