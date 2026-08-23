-- Data-quality reconciliation: one row that accounts for every raw row
-- and proves the staging count ties out. Run after building staging; the
-- output goes in the README as a table so the cleaning is auditable.
--
-- Identity that must hold:
--   final_staging_rows = raw_rows - exact_duplicates_removed - missing_publisher_dropped
--   (invalid spend / quality scores are NULLED, not dropped, so those rows
--    still count toward final_staging_rows.)
-- ============================================================

WITH raw AS (
    SELECT * FROM CHALICE_PORTFOLIO.RAW.ADTECH_EVENTS
),
hashed AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY HASH(
                event_timestamp, campaign_id, advertiser_id, publisher_domain,
                buying_platform, channel, ad_format, device_type, geo,
                audience_segment, bid_price, win_price, impressions, clicks,
                conversions, spend, predicted_ctr, quality_score,
                viewability_rate, brand_safety_flag
            )
            ORDER BY event_timestamp
        ) AS rn
    FROM raw
),
deduped AS (
    SELECT * FROM hashed WHERE rn = 1
)
SELECT
    (SELECT COUNT(*) FROM raw)                                              AS raw_rows,
    (SELECT COUNT(*) FROM hashed WHERE rn > 1)                             AS exact_duplicates_removed,
    (SELECT COUNT(*) FROM deduped WHERE publisher_domain IS NULL)         AS missing_publisher_dropped,
    (SELECT COUNT(*) FROM deduped WHERE spend < 0)                        AS invalid_spend_flagged_nulled,
    (SELECT COUNT(*) FROM deduped
       WHERE quality_score < 0 OR quality_score > 1)                      AS invalid_quality_flagged_nulled,
    (SELECT COUNT(*) FROM CHALICE_PORTFOLIO.STAGING.STG_ADTECH_EVENTS)    AS final_staging_rows,
    -- Reconciliation check: should be exactly 0.
    (SELECT COUNT(*) FROM raw)
        - (SELECT COUNT(*) FROM hashed WHERE rn > 1)
        - (SELECT COUNT(*) FROM deduped WHERE publisher_domain IS NULL)
        - (SELECT COUNT(*) FROM CHALICE_PORTFOLIO.STAGING.STG_ADTECH_EVENTS) AS reconciliation_gap;
