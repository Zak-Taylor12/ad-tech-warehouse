"""
generate_adtech_data.py

Generates a synthetic programmatic advertising dataset that mimics
real-world ad-event data: impressions, clicks, conversions, bid/win
prices, quality scores, and viewability — deliberately including
realistic noise (nulls, duplicates, negative values, seasonality)
so the downstream Snowflake/dbt-style cleaning step has real work to do.


Output:
    data/adtech_events_raw.csv   (~500,000 rows by default)
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import os
import random

# ---------------------------------------------------------------------------
# Config — tune these if you want more/fewer rows or a different date range
# ---------------------------------------------------------------------------
N_ROWS = 500_000
START_DATE = datetime(2026, 1, 1)
END_DATE = datetime(2026, 6, 30)
OUTPUT_DIR = "data"
OUTPUT_FILE = "adtech_events_raw.csv"
RANDOM_SEED = 42

random.seed(RANDOM_SEED)
np.random.seed(RANDOM_SEED)

_DOMAIN_WORDS = [
    "media", "digital", "news", "sports", "gaming", "recipe", "travel", "finance",
    "tech", "style", "home", "auto", "health", "music", "movie", "weather",
    "local", "daily", "hub", "network", "stream", "review", "shop", "trends",
    "pulse", "insider", "wire", "post", "times", "today", "central", "world",
    "life", "verse", "core", "byte", "spark", "grid", "loop", "signal", "beacon",
]
_TLDS = [".com", ".net", ".io", ".co", ".news", ".media"]


def make_publisher_domains(n):
    """Generate n plausible, unique-ish publisher domain names without external deps."""
    domains = set()
    while len(domains) < n:
        word1 = random.choice(_DOMAIN_WORDS)
        word2 = random.choice(_DOMAIN_WORDS)
        tld = random.choice(_TLDS)
        domains.add(f"{word1}{word2}{tld}")
    return list(domains)

# ---------------------------------------------------------------------------
# Reference/dimension values
# ---------------------------------------------------------------------------
N_CAMPAIGNS = 40
N_ADVERTISERS = 15
N_PUBLISHERS = 60

DSPS = ["Trade Desk", "DV360", "Meta", "YouTube", "Amazon DSP"]
AD_FORMATS = ["display", "video", "native", "audio", "ctv"]
DEVICE_TYPES = ["mobile", "desktop", "tablet", "ctv"]
GEOS = ["US-CA", "US-NY", "US-TX", "US-FL", "US-IL", "US-WA", "US-GA", "US-MA", "US-CO", "US-AZ"]
AUDIENCE_SEGMENTS = [
    "in_market_auto", "in_market_travel", "in_market_finance",
    "affinity_sports", "affinity_tech", "affinity_food",
    "retargeting", "lookalike_high_value", "broad_prospecting"
]

campaign_ids = [f"CMP-{i:04d}" for i in range(1, N_CAMPAIGNS + 1)]
advertiser_ids = [f"ADV-{i:03d}" for i in range(1, N_ADVERTISERS + 1)]
publisher_domains = make_publisher_domains(N_PUBLISHERS)

# Give each campaign a fixed advertiser, DSP, and a baseline "quality tier"
# so performance isn't pure noise — some campaigns should clearly be
# better than others, which is what you want to be able to show in a dashboard.
campaign_meta = {}
for cid in campaign_ids:
    campaign_meta[cid] = {
        "advertiser_id": random.choice(advertiser_ids),
        "dsp": random.choice(DSPS),
        "quality_tier": np.random.choice(["low", "mid", "high"], p=[0.2, 0.5, 0.3]),
    }

# A handful of publishers are deliberately "bad" — low quality, low viewability
# so your quality-scoring dashboard in Superset has something real to surface.
publisher_quality = {
    pub: np.random.choice(["low", "mid", "high"], p=[0.15, 0.55, 0.3])
    for pub in publisher_domains
}

TIER_QUALITY_RANGE = {
    "low": (0.15, 0.45),
    "mid": (0.45, 0.75),
    "high": (0.70, 0.98),
}

# ---------------------------------------------------------------------------
# Row generation
# ---------------------------------------------------------------------------
def random_timestamp():
    delta = END_DATE - START_DATE
    random_seconds = random.randint(0, int(delta.total_seconds()))
    ts = START_DATE + timedelta(seconds=random_seconds)

    # Seasonality: weight weekday daytime hours more heavily by re-rolling
    # a fraction of "off-peak" timestamps toward business hours.
    if ts.weekday() >= 5 and random.random() < 0.4:
        ts = ts - timedelta(days=random.choice([1, 2]))  # nudge weekend traffic toward weekdays
    if not (8 <= ts.hour <= 22) and random.random() < 0.5:
        ts = ts.replace(hour=random.randint(8, 22))
    return ts


def generate_row():
    campaign_id = random.choice(campaign_ids)
    meta = campaign_meta[campaign_id]
    publisher = random.choice(publisher_domains)
    pub_quality_tier = publisher_quality[publisher]

    # Blend campaign quality tier and publisher quality tier into a quality_score
    camp_lo, camp_hi = TIER_QUALITY_RANGE[meta["quality_tier"]]
    pub_lo, pub_hi = TIER_QUALITY_RANGE[pub_quality_tier]
    quality_score = round(np.clip(np.random.uniform(
        (camp_lo + pub_lo) / 2, (camp_hi + pub_hi) / 2
    ), 0, 1), 4)

    viewability_rate = round(np.clip(quality_score + np.random.normal(0, 0.08), 0, 1), 4)
    predicted_ctr = round(np.clip(np.random.beta(2, 200) * (1 + quality_score), 0, 0.15), 5)

    floor_price = round(np.random.uniform(0.5, 8.0), 2)
    bid_price = round(floor_price + np.random.exponential(1.5) * (0.5 + quality_score), 2)
    win = np.random.random() < (0.3 + 0.5 * quality_score)
    win_price = round(bid_price * np.random.uniform(0.7, 0.98), 2) if win else None

    impressions = np.random.poisson(3) + 1 if win else 0
    clicks = np.random.binomial(impressions, predicted_ctr) if impressions > 0 else 0
    conversions = np.random.binomial(clicks, 0.05) if clicks > 0 else 0
    spend = round((win_price or 0) * impressions / 1000, 4)  # CPM-style spend

    brand_safety_flag = np.random.random() < (0.02 if quality_score > 0.6 else 0.12)

    row = {
        "event_timestamp": random_timestamp(),
        "campaign_id": campaign_id,
        "advertiser_id": meta["advertiser_id"],
        "publisher_domain": publisher,
        "dsp": meta["dsp"],
        "ad_format": random.choice(AD_FORMATS),
        "device_type": random.choice(DEVICE_TYPES),
        "geo": random.choice(GEOS),
        "audience_segment": random.choice(AUDIENCE_SEGMENTS),
        "bid_price": bid_price,
        "win_price": win_price,
        "impressions": impressions,
        "clicks": clicks,
        "conversions": conversions,
        "spend": spend,
        "predicted_ctr": predicted_ctr,
        "quality_score": quality_score,
        "viewability_rate": viewability_rate,
        "brand_safety_flag": brand_safety_flag,
    }
    return row


def inject_dirty_data(df: pd.DataFrame) -> pd.DataFrame:
    """
    Real pipelines have messy source data. Inject realistic problems so the
    Snowflake staging layer has genuine cleaning work to do and document.
    """
    n = len(df)

    # 1. Duplicate ~0.3% of rows (simulates upstream retry/re-send)
    dupe_idx = np.random.choice(df.index, size=int(n * 0.003), replace=False)
    df = pd.concat([df, df.loc[dupe_idx]], ignore_index=True)

    # 2. Null out publisher_domain in ~0.5% of rows (simulates tracking gaps)
    null_idx = np.random.choice(df.index, size=int(len(df) * 0.005), replace=False)
    df.loc[null_idx, "publisher_domain"] = None

    # 3. A few negative spend values (simulates a currency/refund bug upstream)
    neg_idx = np.random.choice(df.index, size=int(len(df) * 0.001), replace=False)
    df.loc[neg_idx, "spend"] = -df.loc[neg_idx, "spend"].abs()

    # 4. A few impossible quality scores outside [0,1] (simulates a bad upstream join)
    bad_idx = np.random.choice(df.index, size=int(len(df) * 0.0008), replace=False)
    df.loc[bad_idx, "quality_score"] = df.loc[bad_idx, "quality_score"] + 1.5

    return df


def main():
    print(f"Generating {N_ROWS:,} rows...")
    rows = [generate_row() for _ in range(N_ROWS)]
    df = pd.DataFrame(rows)

    print("Injecting realistic data quality issues...")
    df = inject_dirty_data(df)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    out_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    df.to_csv(out_path, index=False)

    print(f"Done. Wrote {len(df):,} rows to {out_path}")
    print("\nQuick sanity check:")
    print(df.describe(include="all").transpose().head(10))


if __name__ == "__main__":
    main()
