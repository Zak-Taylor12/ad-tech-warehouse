# AdTech Campaign Performance Warehouse

An end-to-end analytics pipeline for advertising data: synthetic ad campaign data modeled in Snowflake (raw → staging → marts) and visualized in Apache Superset.

Stack: Snowflake (warehouse/modeling) → Apache Superset (BI/dashboards)

---

## Synthetic Data

Since I didn't have access to real campaign data, [`generate_adtech_data.py`](./generate_adtech_data.py) produces ~500,000 synthetic programmatic ad events across 40 campaigns, 60 publishers, and 5 DSPs. Campaigns and publishers are each assigned a quality tier, so quality score, viewability, and win rate correlate meaningfully rather than being pure noise. The generator also injects real data quality problems on purpose, duplicates, missing values, negative spend, out-of-range scores, with transofrmations being shown to show real data transformations and how they should be handled. 

---

## Data model: raw → staging → marts

```
sql/
  raw/       Schema definition for the untouched landing table
  staging/   Cleaned, typed, deduplicated, quality issues flagged (not hidden)
  marts/     Star schema: fact table + dimension tables
```

**Staging** ([`stg_adtech_events.sql`](./sql/staging/stg_adtech_events.sql)) Transformation and enrichment occur here : explicit type casting, hash-based deduplication (no natural event ID exists in the raw data), and bad values are **flagged rather than silently deleted or nulled**, three boolean columns make data quality issues visible to anyone querying the table.

**Marts** is a proper star schema ([`dim_campaign`](./sql/marts/dim_campaign.sql), [`dim_publisher`](./sql/marts/dim_publisher.sql), [`dim_date`](./sql/marts/dim_date.sql), [`fact_ad_events`](./sql/marts/fact_ad_events.sql)). The dashboards below query `fact_ad_events` directly and don't strictly need the dimension joins, I built them anyway since that's the correct pattern for maintainability and future metadata, not because today's queries required it.

**Known simplifications**, and what I'd change in production: no dbt (would add testing, docs, incremental builds instead of full `CREATE OR REPLACE`), no surrogate keys on dimensions, dedup relies on a hash rather than a true unique ID.

---

## Dashboards (Apache Superset)

All three query `marts.fact_ad_events`.

### 1. Campaign Performance Overview
**Business question:** Where is spend going, and is it working?

KPIs, daily spend trend, spend by DSP, top-10 campaigns by conversions.

![Campaign Performance Overview](./superset%20screenshots/dashboard-1-campaign-performance.png)

### 2. Quality & Brand Safety
**Business question:** Which publishers should be reconsidered or cut?

Avg quality score, % brand-safety-flagged, quality distribution, and a bottom-10-publishers table showing quality, viewability, and spend together, since a low-quality publisher receiving $50 isn't a problem, one receiving $8,000 is.

![Quality & Brand Safety](./superset%20screenshots/dashboard-2-quality-brand-safety.png)

### 3. Pricing & Bidding Efficiency
**Business question:** Are we bidding smartly, or leaving budget on the table?

Win rate, bid price vs. win price, CPM by audience segment.

*To note: CPM is basically flat across segments because audience segment was never tied to price in the generator, it's random. With real correlation, this chart would be a genuine tool for spotting overpriced segments. The bid/win relationship is also clean and linear, since win price here is just `bid_price × random(0.7–0.98)`, real auction data would show more noise.*

![Pricing & Bidding Efficiency](./superset%20screenshots/dashboard-3-pricing-efficiency.png)

---

## Repo structure

```
ad-tech-warehouse/
  generate_adtech_data.py
  sql/
    raw/
    staging/
    marts/
  superset screenshots/
  README.md
```
