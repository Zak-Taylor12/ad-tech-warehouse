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
    dsp,
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

-- Query checking accuracy of measure created in Superset Dashboard
  SELECT dsp, SUM(spend) AS Total_Sales
  FROM CHALICE_PORTFOLIO.STAGING.STG_ADTECH_EVENTS
  GROUP BY dsp
  