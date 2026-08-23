-- One row per campaign. Since every event for a given campaign
-- always shares the same advertiser and DSP, a simple DISTINCT
-- is enough to collapse the event-level data down to one row
-- per campaign.
-- ============================================================

CREATE OR REPLACE TABLE CHALICE_PORTFOLIO.MARTS.DIM_CAMPAIGN AS

SELECT DISTINCT
    campaign_id,
    advertiser_id,
    dsp
FROM CHALICE_PORTFOLIO.STAGING.STG_ADTECH_EVENTS
WHERE campaign_id IS NOT NULL;

-- Expect exactly 40 rows, one per campaign in the source data.
SELECT COUNT(*) FROM CHALICE_PORTFOLIO.MARTS.DIM_CAMPAIGN;