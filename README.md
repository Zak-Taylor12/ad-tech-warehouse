# AdTech Campaign Performance Warehouse

An end-to-end analytics pipeline for advertising data: synthetic ad campaign data modeled in Snowflake (raw → staging → marts) and visualized in Apache Superset.

Stack: Snowflake (warehouse/modeling) → Apache Superset (BI/dashboards)

---

## Synthetic Data

Since I didn't have access to real campaign data, [`generate_adtech_data.py`](./generate_adtech_data.py) produces ~500,000 synthetic programmatic ad events across 40 campaigns, 60 publishers, and 5 buying platforms spanning two channels: programmatic DSPs (Trade Desk, DV360, Amazon DSP) and walled gardens (Meta, YouTube). Campaigns and publishers are each assigned a quality tier, so quality score, viewability, and win rate correlate meaningfully rather than being pure noise.

The generator also injects realistic data-quality problems on purpose — duplicate rows, missing publishers, negative spend, and out-of-range quality scores — so the downstream Snowflake staging layer has genuine cleaning work to do and document. The negative-spend injection deliberately targets only rows that already have positive spend, so every injected row is actually detectable downstream (roughly 40% of events are losing bids with zero spend, and negating zero would slip past a `spend < 0` check).

---

## Data model: raw → staging → marts

```
sql/
  raw/       Schema definition for the untouched landing table
  staging/   Cleaned, typed, deduplicated; quality issues flagged, then handled explicitly
  marts/     Star schema: fact table + dimension tables + analysis queries
```

**Staging** ([`stg_adtech_events.sql`](./sql/staging/stg_adtech_events.sql)) is where transformation and enrichment happen: explicit type casting, full-row hash deduplication (no natural event ID exists in the raw data, and the upstream duplicates are exact full-row copies, so the fingerprint hashes **every** column — a partial fingerprint would silently collapse genuinely distinct events that happen to share a few fields). Every data-quality issue is recorded in a boolean flag column so nothing is handled silently, and then the unusable values are made safe: invalid spend and quality scores are **nulled** (flag retained), and rows with **no publisher_domain are dropped** (that spend can't be attributed to anything). The flags make each of those actions auditable downstream — the point is that nothing happens invisibly, not that nothing is ever nulled or dropped.

**Marts** is a proper star schema ([`dim_campaign`](./sql/marts/dim_campaign.sql), [`dim_publisher`](./sql/marts/dim_publisher.sql), [`dim_date`](./sql/marts/dim_date.sql), [`fact_ad_events`](./sql/marts/fact_ad_events.sql)), plus the analysis queries the dashboards run. The dashboards query `fact_ad_events` directly and don't strictly need the dimension joins; I built the dimensions anyway since that's the correct pattern for maintainability and future metadata, not because today's queries required it.

**Known simplifications**, and what I'd change in production: no dbt (would add testing, docs, incremental builds instead of full `CREATE OR REPLACE`), no surrogate keys on dimensions, dedup relies on a full-row hash rather than a true unique event ID.

---

## Data quality reconciliation

Every raw row is accounted for. [`sql/staging/dq_reconciliation.sql`](./sql/staging/dq_reconciliation.sql) returns a single row proving the staging count ties out (numbers below are from the seeded 500k run):

| Stage | Rows |
|---|---:|
| Raw rows loaded | 501,500 |
| Exact duplicates removed (full-row hash) | 1,474 |
| Missing-publisher rows dropped | 2,507 |
| Invalid spend flagged & nulled (row kept) | 501 |
| Invalid quality score flagged & nulled (row kept) | 401 |
| **Final staging rows** | **497,519** |

Identity: `final_staging_rows = raw_rows − duplicates_removed − missing_publisher_dropped` (invalid spend/quality are nulled, not dropped, so those rows still count). Reconciliation gap: **0**.

---

## Dashboards (Apache Superset)

All three query `marts.fact_ad_events`.

### 1. Campaign Performance Overview
**Business question:** Where is spend going, and is it working?

KPIs, daily spend trend, spend by buying platform, and top-10 campaigns by conversions.

![Campaign Performance Overview](./superset%20screenshots/dashboard-1-campaign-performance.png)

### 2. Quality & Brand Safety
**Business question:** Which publishers should be reconsidered or cut?

Average quality score, % brand-safety-flagged, quality distribution, and a bottom-10-publishers table showing quality, viewability, and spend together. Spend is roughly uniform across publishers (and if anything lower on low-quality inventory, which wins fewer auctions), so the case for cutting a publisher rests on quality, viewability, and brand safety — not on overspend.

![Quality & Brand Safety](./superset%20screenshots/dashboard-2-quality-brand-safety.png)

### 3. Pricing & Bidding Efficiency
**Business question:** Are we bidding smartly, and does quality actually pay off?

The core story is the quality → win-rate relationship ([`win_rate_by_quality_band.sql`](./sql/marts/win_rate_by_quality_band.sql)): bids on higher-quality inventory win far more often, climbing monotonically from ~39% to ~73%.

| Quality band | Win rate |
|---|---:|
| 0.0–0.2 | 39% |
| 0.2–0.4 | 46% |
| 0.4–0.6 | 56% |
| 0.6–0.8 | 64% |
| 0.8–1.0 | 73% |

Bidding efficiency ([`win_bid_efficiency.sql`](./sql/marts/win_bid_efficiency.sql)) shows win price lands at ~0.84 of bid price overall and stays roughly flat across quality bands — you win **more often** on quality inventory without paying a higher share of your bid to do it.

![Pricing & Bidding Efficiency](./superset%20screenshots/dashboard-3-pricing-efficiency.png)

*Known simplification: CPM by audience segment is intentionally flat, because audience segment was never tied to price in the generator (it's random). With real correlation, that view would help spot overpriced segments; the win-rate and win/bid views above are the decision-relevant ones today.*

---

## AI-assisted reporting

[`generate_ai_summary.py`](./generate_ai_summary.py) pulls the same metrics shown on the dashboards directly from Snowflake and uses Claude to generate a short executive summary, automating a task an analyst would otherwise write by hand each reporting cycle.

Actual output from a real run against this dataset:

> From January through June 2026, the campaign delivered 943 conversions at a cost per conversion of $6.24 against a total spend of $5,887.01, with a CTR of 1.61% and a healthy win rate of 59.56%. Two areas warrant attention: the average quality score of 0.59 sits in middling territory on a 0–1 scale, suggesting ad relevance or landing page alignment could be improved, and a brand safety flag rate of 7.20% is elevated enough to merit a review of placement lists and contextual targeting settings to protect brand reputation. Overall efficiency looks reasonable, but addressing quality score and brand safety should be the priority going into the next half.

Currently run on demand; a natural next step would be scheduling it and writing results back into Snowflake so a dashboard tile could display the latest summary automatically.

---

## Repo structure

```
ad-tech-warehouse/
  generate_adtech_data.py
  generate_ai_summary.py
  sql/
    raw/
      create_raw_table.sql
    staging/
      stg_adtech_events.sql
      dq_reconciliation.sql
    marts/
      dim_campaign.sql
      dim_publisher.sql
      dim_date.sql
      fact_ad_events.sql
      win_rate_by_quality_band.sql
      win_bid_efficiency.sql
  superset screenshots/
  README.md
```
