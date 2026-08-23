-- The core table. One row per ad event, carrying every metric
-- Superset dashboards will actually query. This is where we
-- decide how strict to be about the data quality issues flagged
-- back in staging.
-- ============================================================

CREATE OR REPLACE TABLE CHALICE_PORTFOLIO.MARTS.FACT_AD_EVENTS AS

-- Rows with invalid spend or an invalid quality score get excluded
-- here entirely, rather than kept with nulls, to keep this table
-- clean for reporting. Staging still has the full picture if that
-- data is ever needed for investigation.
SELECT
    event_timestamp,
    CAST(event_timestamp AS DATE)   AS event_date,
    campaign_id,
    publisher_domain,
    buying_platform,
    channel,
    ad_format,
    device_type,
    geo,
    audience_segment,
    bid_price,
    win_price,
    impressions,
    clicks,
    conversions,
    spend,
    predicted_ctr,
    quality_score,
    viewability_rate,
    brand_safety_flag
FROM CHALICE_PORTFOLIO.STAGING.STG_ADTECH_EVENTS
WHERE NOT had_invalid_spend
  AND NOT had_invalid_quality_score;

-- Query checking the spend measure shown on the Superset dashboard.
-- Aliased total_spend: this is ad spend, not revenue, so it must not be
-- labeled as sales on the dashboard.
SELECT buying_platform, SUM(spend) AS total_spend
FROM CHALICE_PORTFOLIO.MARTS.FACT_AD_EVENTS
GROUP BY buying_platform
ORDER BY total_spend DESC;
  