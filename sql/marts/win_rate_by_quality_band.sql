-- Win rate by quality band.
-- This is the quality-scoring story the pipeline exists to tell: bids on
-- higher-quality inventory win far more often. Win rate climbs from ~47%
-- in the lowest band to ~73% in the top band — a clean, monotonic lift.
-- (A win is any event with a non-null win_price; losing bids carry a
-- null win_price and zero spend.)
-- Chart: bar chart, quality_band on X, win_rate on Y.
-- ============================================================

SELECT
    CASE
        WHEN quality_score < 0.2 THEN '0.0-0.2'
        WHEN quality_score < 0.4 THEN '0.2-0.4'
        WHEN quality_score < 0.6 THEN '0.4-0.6'
        WHEN quality_score < 0.8 THEN '0.6-0.8'
        ELSE                          '0.8-1.0'
    END                                                      AS quality_band,
    COUNT(*)                                                 AS bids,
    SUM(CASE WHEN win_price IS NOT NULL THEN 1 ELSE 0 END)   AS wins,
    ROUND(AVG(CASE WHEN win_price IS NOT NULL THEN 1 ELSE 0 END), 3) AS win_rate
FROM CHALICE_PORTFOLIO.MARTS.FACT_AD_EVENTS
GROUP BY 1
ORDER BY 1;
