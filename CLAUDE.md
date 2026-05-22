# Customer Health Score — Case Study

## What This Project Is

A BI Engineer case study for an edtech company (writing-integrity/feedback/grading products sold to K12 and Higher Ed). The goal is a **Customer Health Score** — a composite metric CSMs and leadership use to identify at-risk accounts, expansion candidates, and renewal priorities.

The case study is intentionally open-ended. The data is production-like (messy), and the evaluation criteria includes data exploration, modeling judgment, SQL craft, analytical depth, storytelling, and AI tool usage.

## Tech Stack

- **dbt** — project lives in `health_score/`, targets Snowflake in production
- **DuckDB** — used for local execution; `run_health_score.py` loads the CSVs and runs `health_score.sql` directly (no Snowflake connection needed)
- **SQLFluff** — linting enforced via CI; dialect is Snowflake

## Data Sources

Three CSVs in `data/`:

| File | Rows | Description |
|---|---|---|
| `accounts.csv` | ~325 | Salesforce dimensions: region, division, segment, CSM, renewal date |
| `subscriptions.csv` | ~570 | Active subscriptions by account-product with ARR |
| `submissions.csv` | ~435K | Raw submission events, Jan 2024 – Jun 2025, with user_id |

See `schema.md` for full column definitions. Key data quality issues to be aware of:
- `division` has casing inconsistencies in the raw data (handled in `stg_accounts.sql`)
- `region` is null for some legacy accounts
- `csm_owner` is blank for unassigned accounts
- Submissions are heavily seasonal (K12 summer trough, Higher Ed end-of-semester peaks)

## How to Run Locally

```bash
python run_health_score.py
```

This loads the three CSVs into an in-memory DuckDB instance, runs `health_score.sql`, prints a summary report, and writes `customer_health_score.csv`.

For the dbt project (requires Snowflake connection):
```bash
cd health_score && dbt run
```

## dbt Model Structure

```
models/
  sources.yml              # Raw tables in Snowflake (HEALTH_SCORE.DEV schema)
  staging/                 # Views — light cleaning only
    stg_accounts.sql
    stg_submissions.sql
    stg_subscriptions.sql
  intermediate/            # Views — business logic
    int_account_dimensions.sql   # CRM dims + ARR rollup + days_to_renewal
    int_period_metrics.sql       # Recent vs prior quarter metrics per account
    int_segment_benchmarks.sql   # Median submissions/MAU by division+segment
    int_submission_periods.sql   # Period bucketing logic for submissions
  marts/                   # Table — final output CSMs can query
    customer_health_score.sql
```

## Health Score Design

Five components, weighted average → composite score 0–100.

| Component | Weight | Logic |
|---|---|---|
| Submission Trend | 30% | submissions/MAU recent vs prior quarter (normalizes for account size) |
| MAU Trend | 25% | active user count recent vs prior quarter |
| Recency | 20% | days since last submission |
| Product Adoption | 15% | % of subscribed products with activity this quarter |
| Relative Activity | 10% | submissions/MAU vs division+segment peer median |

**Tiers:** Healthy ≥ 70 | At Risk 40–69 | Critical < 40

**Renewal urgency overlay:** Urgent = days_to_renewal ≤ 90 AND score < 40 | Watch = days_to_renewal ≤ 180 AND score < 70

Active users are derived from `user_id` in submissions (MAU = distinct users with ≥1 submission in the month). This is documented as a modeling choice since pre-aggregated active user counts aren't available.

## Key Files

- `health_score.sql` — standalone single-file version for DuckDB (mirrors the dbt mart logic)
- `run_health_score.py` — local runner with summary report and CSV export
- `explore.py` — data quality exploration script
- `health_score/analyses/investigate_duplicate_submissions.sql` — ad-hoc analysis of duplicate submissions found during exploration
- `schema.md` — authoritative column definitions and data notes
