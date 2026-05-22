# Customer Health Score — Solution

## Overview

This repo contains my solution to the BI Engineer case study. The deliverable is a **Customer Health Score** — a composite 0–100 metric that gives Customer Success Managers and leadership a systematic way to identify at-risk accounts, spot expansion candidates, and prioritize renewal conversations.

**Platform choice:** I built this in **dbt (Snowflake)**, connected to dbt Cloud with CI/CD via GitHub. Every model change is tracked in version control, tests run on each push, and the final `customer_health_score` table is materialized in Snowflake where CSMs can query it directly.

---

## Health Score Design

Five components combined into a weighted average (0–100 composite):

| Component | Weight | Logic |
|---|---|---|
| Submission Trend | 30% | submissions/MAU, recent vs prior quarter — normalizes for account size |
| MAU Trend | 25% | active user count, recent vs prior quarter |
| Recency | 20% | days since last submission |
| Product Adoption | 15% | % of subscribed products with activity this quarter |
| Relative Activity | 10% | submissions/MAU vs division+segment peer median |

**Health tiers:** Healthy ≥ 70 | At Risk 40–69 | Critical < 40

**Renewal urgency overlay:**
- `Urgent` — renewing within 90 days AND score < 40
- `Watch` — renewing within 180 days AND score < 70
- `Monitor` — everything else

### Key design decisions

- **MAU over raw submission counts** — Dividing by monthly active users normalizes for account size so a 50-seat charter school is scored on the same basis as a 5,000-seat university. Raw counts always favor larger accounts.
- **MAU derived from `user_id`** — Pre-aggregated active user counts weren't available. MAU = distinct `user_id` values with ≥ 1 submission in the month. This is consistent with how the product teams define "active."
- **Separate trend components** — Submission trend and MAU trend capture different failure modes: falling submissions/user (disengagement) vs falling user count (abandonment). A combined metric would mask which is happening.
- **Peer-relative benchmarking** — The relative activity component catches accounts that are "technically active" but consistently lagging their division+segment peers — a signal the trend score alone misses if both periods are equally low.
- **New/reactivated accounts** — When prior quarter MAU is zero, trend scores default to 70 (neutral) rather than zero or 100. Zero would unfairly penalize new customers; 100 would inflate the score on no evidence.

---

## dbt Model Structure

```
health_score/
  models/
    sources.yml                      # Raw tables in Snowflake (HEALTH_SCORE.DEV)
    staging/                         # Views — light cleaning only
      stg_accounts.sql               # Normalizes division casing, trims blanks
      stg_submissions.sql
      stg_subscriptions.sql
    intermediate/                    # Views — business logic
      int_account_dimensions.sql     # CRM dims + ARR rollup + days_to_renewal
      int_submission_periods.sql     # Buckets submissions into recent/prior quarters
      int_period_metrics.sql         # Submission and MAU counts per account per period
      int_segment_benchmarks.sql     # Peer median (submissions/MAU) by division+segment
    marts/                           # Table — queryable by CSMs
      customer_health_score.sql      # Final scored output, one row per account
  tests/
    assert_no_negative_arr.sql
    assert_peer_percentile_between_0_and_100.sql
    assert_scores_between_0_and_100.sql
    assert_urgent_accounts_are_critical.sql
  analyses/
    investigate_duplicate_submissions.sql   # Ad-hoc dup investigation
```

---

## Data Quality Findings

Running `explore.py` and the ad-hoc analysis surfaced a few issues in the raw data:

- **`division` casing** — values appear as both `K12` / `k12` and `Higher Ed` / `higher ed`. Normalized to title case in `stg_accounts.sql`.
- **Null `region`** — a subset of legacy accounts have no region. These are retained in the score but will show as null in region-sliced views.
- **Blank `csm_owner`** — unassigned accounts have an empty string rather than null. Treated as unassigned in the output.
- **Duplicate submissions** — investigated in `analyses/investigate_duplicate_submissions.sql`. Duplicates exist at the `submission_id` level in a small number of cases; deduplication applied in `stg_submissions.sql`.
- **Orphan submissions** — a small number of `submission` rows reference `account_id` values not present in `accounts`. These are excluded from scoring.

---

## Output Columns

The `customer_health_score` table exposes:

| Column | Description |
|---|---|
| `account_id`, `account_name` | Identity |
| `division`, `region`, `segment`, `country` | CRM dimensions for slicing |
| `csm_owner`, `renewal_date`, `days_to_renewal` | CSM-facing fields |
| `total_arr`, `products_subscribed` | Commercial context |
| `recent_submissions`, `prior_submissions` | Raw engagement counts |
| `recent_mau`, `prior_mau` | Active user counts |
| `products_active_recent` | Products with activity this quarter |
| `last_submission_date`, `days_since_last_submission` | Recency signals |
| `submission_trend_score` … `relative_activity_score` | Component scores (explainable) |
| `composite_health_score` | Final 0–100 score |
| `health_tier` | Healthy / At Risk / Critical |
| `peer_percentile_rank` | Rank within division+segment peer group |
| `renewal_urgency` | Urgent / Watch / Monitor |

<img width="2042" height="586" alt="image" src="https://github.com/user-attachments/assets/663d7222-c55f-49e4-9666-b10ad4f3e2d4" />

---

## Running the Project

This project runs via **dbt Cloud**, connected to Snowflake and this GitHub repo. Merges to `main` trigger a dbt Cloud job that runs all models and tests.

To run locally (requires a Snowflake connection and dbt profile configured):

```bash
cd health_score
dbt run
dbt test
```

Source data lives in `data/` as CSVs and is loaded into Snowflake via dbt seeds or an external process prior to running.
