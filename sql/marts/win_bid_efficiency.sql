-- Bidding efficiency: win price as a share of bid price.
-- Overall the ratio is ~0.84 — we clear auctions at about 84% of what we
-- bid. Broken out by quality band it stays roughly flat, which is the
-- point worth showing: you win MORE OFTEN on quality inventory (see
-- win_rate_by_quality_band.sql) without paying a higher share of your bid
-- to do it. Together the two queries are the quality + pricing narrative.
-- Chart: single-value tile for the overall ratio, or a bar by band.
-- ============================================================

-- Overall
SELECT
    ROUND(AVG(win_price / NULLIF(bid_price, 0)), 3) AS win_bid_ratio,
    ROUND(AVG(bid_price), 2)                        AS avg_bid_price,
    ROUND(AVG(win_price), 2)                        AS avg_win_price,
    COUNT(*)                                        AS wins
FROM CHALICE_PORTFOLIO.MARTS.FACT_AD_EVENTS
WHERE win_price IS NOT NULL;

-- By quality band (should stay near 0.84 across bands)
SELECT
    CASE
        WHEN quality_score < 0.2 THEN '0.0-0.2'
        WHEN quality_score < 0.4 THEN '0.2-0.4'
        WHEN quality_score < 0.6 THEN '0.4-0.6'
        WHEN quality_score < 0.8 THEN '0.6-0.8'
        ELSE                          '0.8-1.0'
    END                                             AS quality_band,
    ROUND(AVG(win_price / NULLIF(bid_price, 0)), 3) AS win_bid_ratio,
    COUNT(*)                                        AS wins
FROM CHALICE_PORTFOLIO.MARTS.FACT_AD_EVENTS
WHERE win_price IS NOT NULL
GROUP BY 1
ORDER BY 1;
