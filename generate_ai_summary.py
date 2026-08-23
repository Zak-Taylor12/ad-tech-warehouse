"""
generate_ai_summary.py

Pulls campaign metrics from Snowflake and uses Claude to generate a
short executive summary, demonstrating AI-assisted analytics.

Usage:
    pip install snowflake-connector-python python-dotenv anthropic
    python generate_ai_summary.py

Requires a .env file with: ANTHROPIC_API_KEY, SNOWFLAKE_USER,
SNOWFLAKE_PASSWORD, SNOWFLAKE_ACCOUNT, SNOWFLAKE_WAREHOUSE,
SNOWFLAKE_DATABASE, SNOWFLAKE_SCHEMA
"""

import os
from datetime import datetime

import snowflake.connector
from dotenv import load_dotenv
import anthropic

load_dotenv()

REQUIRED_ENV_VARS = [
    "ANTHROPIC_API_KEY",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_PASSWORD",
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE",
    "SNOWFLAKE_SCHEMA",
]


def check_env():
    missing = [v for v in REQUIRED_ENV_VARS if not os.getenv(v)]
    if missing:
        raise EnvironmentError(
            f"Missing required environment variables in .env: {', '.join(missing)}"
        )


def get_metrics():
    conn = snowflake.connector.connect(
        user=os.getenv("SNOWFLAKE_USER"),
        password=os.getenv("SNOWFLAKE_PASSWORD"),
        account=os.getenv("SNOWFLAKE_ACCOUNT"),
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE"),
        database=os.getenv("SNOWFLAKE_DATABASE"),
        schema=os.getenv("SNOWFLAKE_SCHEMA"),
    )
    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT
                SUM(spend)                                              AS total_spend,
                SUM(conversions)                                        AS total_conversions,
                SUM(clicks) / NULLIF(SUM(impressions), 0)               AS overall_ctr,
                SUM(spend) / NULLIF(SUM(conversions), 0)                AS cost_per_conversion,
                AVG(quality_score)                                      AS avg_quality_score,
                SUM(CASE WHEN brand_safety_flag THEN 1 ELSE 0 END)
                    / NULLIF(COUNT(*), 0)                               AS pct_brand_safety_flagged,
                COUNT(win_price) / NULLIF(COUNT(*), 0)                  AS win_rate
            FROM fact_ad_events
        """)
        row = cursor.fetchone()
        columns = [desc[0] for desc in cursor.description]
        return dict(zip(columns, row))
    finally:
        conn.close()


def build_prompt(metrics: dict) -> str:
    return f"""You are writing a short executive summary of campaign
performance for a programmatic advertising campaign, covering the full
reporting period (January through June 2026), based on the metrics
below. Write 2-3 sentences, plain English, no bullet points, no
headers. Call out anything that looks like it needs attention (low
quality score, high brand safety flag rate, high cost per conversion),
and otherwise keep the tone factual and concise, the way an analyst
would summarize this for a busy stakeholder who won't look at the
dashboard themselves.
Metrics:
- Total spend: ${metrics['TOTAL_SPEND']:,.2f}
- Total conversions: {metrics['TOTAL_CONVERSIONS']:,}
- Overall CTR: {metrics['OVERALL_CTR']:.2%}
- Cost per conversion: ${metrics['COST_PER_CONVERSION']:,.2f}
- Average quality score (0-1 scale): {metrics['AVG_QUALITY_SCORE']:.2f}
- % of events flagged for brand safety: {metrics['PCT_BRAND_SAFETY_FLAGGED']:.2%}
- Win rate: {metrics['WIN_RATE']:.2%}
"""


def generate_summary(metrics: dict) -> str:
    client = anthropic.Anthropic()
    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=300,
        messages=[{"role": "user", "content": build_prompt(metrics)}],
    )
    return response.content[0].text


def main():
    check_env()

    print("Pulling metrics from Snowflake...")
    metrics = get_metrics()

    print("\nMetrics pulled:")
    for k, v in metrics.items():
        print(f"  {k}: {v}")

    print("\nGenerating summary with Claude...")
    summary = generate_summary(metrics)

    print("\n" + "=" * 60)
    print("EXECUTIVE SUMMARY")
    print("=" * 60)
    print(summary)

    os.makedirs("ai_summaries", exist_ok=True)
    timestamp = datetime.now().strftime("%Y-%m-%d_%H%M")
    out_path = f"ai_summaries/summary_{timestamp}.txt"
    with open(out_path, "w") as f:
        f.write(summary)
    print(f"\nSaved to {out_path}")


if __name__ == "__main__":
    main()