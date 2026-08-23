-- One row per publisher domain that actually appears in the data.
-- ============================================================

CREATE OR REPLACE TABLE CHALICE_PORTFOLIO.MARTS.DIM_PUBLISHER AS

SELECT DISTINCT
    publisher_domain
FROM CHALICE_PORTFOLIO.STAGING.STG_ADTECH_EVENTS
WHERE publisher_domain IS NOT NULL;

-- Expect exactly 60 rows, one per publisher in the source data.
SELECT COUNT(*) FROM CHALICE_PORTFOLIO.MARTS.DIM_PUBLISHER;
