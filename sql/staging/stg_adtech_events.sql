-- This is the staging model. It takes the raw data and turns it into
-- something trustworthy: correct types, exact-duplicate rows removed,
-- and every data-quality problem recorded in a boolean flag column so
-- nothing is handled silently. Unusable values are then made safe:
-- invalid spend and quality scores are nulled (flag retained), and
-- rows with no publisher_domain are dropped (they can't be attributed).
-- The flags make every one of those actions auditable downstream.
-- ============================================================

CREATE OR REPLACE TABLE CHALICE_PORTFOLIO.STAGING.STG_ADTECH_EVENTS AS

-- Step 1: pull in the raw data and lock down the types.
-- Raw tables get their types auto-guessed on load, so we don't
-- want to trust that guess long term. Casting here means every
-- downstream table can rely on consistent, known types.
WITH ADTECH_RAW_Source AS (
    SELECT
        CAST(event_timestamp AS TIMESTAMP_NTZ)   AS event_timestamp,
        CAST(campaign_id AS VARCHAR(20))         AS campaign_id,
        CAST(advertiser_id AS VARCHAR(20))       AS advertiser_id,
        CAST(publisher_domain AS VARCHAR(100))   AS publisher_domain,
        CAST(buying_platform AS VARCHAR(50))     AS buying_platform,
        CAST(channel AS VARCHAR(20))             AS channel,
        CAST(ad_format AS VARCHAR(20))           AS ad_format,
        CAST(device_type AS VARCHAR(20))         AS device_type,
        CAST(geo AS VARCHAR(10))                 AS geo,
        CAST(audience_segment AS VARCHAR(50))    AS audience_segment,
        CAST(bid_price AS NUMBER(10,2))          AS bid_price,
        CAST(win_price AS NUMBER(10,2))          AS win_price,
        CAST(impressions AS NUMBER(10,0))        AS impressions,
        CAST(clicks AS NUMBER(10,0))             AS clicks,
        CAST(conversions AS NUMBER(10,0))        AS conversions,
        CAST(spend AS NUMBER(12,4))              AS spend,
        CAST(predicted_ctr AS NUMBER(8,5))       AS predicted_ctr,
        CAST(quality_score AS NUMBER(6,4))       AS quality_score,
        CAST(viewability_rate AS NUMBER(6,4))    AS viewability_rate,
        CAST(brand_safety_flag AS BOOLEAN)       AS brand_safety_flag,

        -- There's no true unique id in the raw data (like a bid_id).
        -- The upstream duplicates are exact full-row copies, so the
        -- fingerprint hashes EVERY column. A partial fingerprint (a few
        -- fields) would also collapse two genuinely distinct events that
        -- happen to share those fields, silently deleting real rows.
        HASH(
            event_timestamp, campaign_id, advertiser_id, publisher_domain,
            buying_platform, channel, ad_format, device_type, geo,
            audience_segment, bid_price, win_price, impressions, clicks,
            conversions, spend, predicted_ctr, quality_score,
            viewability_rate, brand_safety_flag
        ) AS row_hash
    FROM CHALICE_PORTFOLIO.RAW.ADTECH_EVENTS
),

-- Step 2: drop true duplicates using that fingerprint.
-- If two rows share the same hash, we only keep the first one.
DEDUPED_Events AS (
    SELECT *
    FROM ADTECH_RAW_Source
    -- Rows sharing a full-row hash are identical, so which one is kept
    -- doesn't matter; ORDER BY is only here to make the choice deterministic.
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY row_hash
        ORDER BY event_timestamp
    ) = 1
),

-- Step 3: mark rows with bad values instead of quietly fixing them.
-- Flagging keeps the problem visible to anyone querying this table,
-- rather than hiding it behind a silent NULL.
flagged AS (
    SELECT
        *,
        CASE
            WHEN spend < 0 THEN TRUE
            ELSE FALSE
        END AS had_invalid_spend,
        CASE
            WHEN quality_score > 1 OR quality_score < 0 THEN TRUE
            ELSE FALSE
        END AS had_invalid_quality_score,
        CASE
            WHEN publisher_domain IS NULL THEN TRUE
            ELSE FALSE
        END AS had_missing_publisher
    FROM DEDUPED_Events
)

-- Final output: the actual staging table.
-- Bad spend and bad quality scores get nulled here, but the flag
-- columns stick around so nothing is lost, just made safe to use.
-- Rows with a missing publisher get dropped entirely, since we
-- can't attribute that spend to anything meaningful.
SELECT
    event_timestamp,
    campaign_id,
    advertiser_id,
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
    CASE WHEN had_invalid_spend THEN NULL ELSE spend END AS spend,
    predicted_ctr,
    CASE WHEN had_invalid_quality_score THEN NULL ELSE quality_score END AS quality_score,
    viewability_rate,
    brand_safety_flag,
    had_invalid_spend,
    had_invalid_quality_score,
    had_missing_publisher
FROM flagged
WHERE NOT had_missing_publisher;


-- Quick sanity check after building staging. Not part of the model
-- itself, just a manual spot-check while developing.
SELECT *
FROM CHALICE_PORTFOLIO.STAGING.STG_ADTECH_EVENTS
LIMIT 25;
