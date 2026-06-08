# Customer Health Score

![dbt](https://img.shields.io/badge/dbt-FF694B?logo=dbt&logoColor=white)
![Snowflake](https://img.shields.io/badge/Snowflake-29B5E8?logo=snowflake&logoColor=white)
![dbt Cloud](https://img.shields.io/badge/dbt_Cloud-CI%2FCD-FF694B)
![SQL](https://img.shields.io/badge/SQL-window_functions-4479A1)

A composite **0 to 100 account health score**, built end to end in **dbt on Snowflake** with
**dbt Cloud CI/CD**. It gives Customer Success Managers and leadership a systematic way to
identify at-risk accounts, spot expansion candidates, and prioritize renewal conversations,
producing one explainable score per account across 324 accounts.

## Highlights

- **Layered dbt project** (staging → intermediate → marts) that outputs one scored row per
  account, fully version-controlled.
- **Five weighted, individually-readable components** rather than a black box, plus a
  renewal-urgency overlay.
- **Peer-relative benchmarking with window functions** (division + segment median) that
  catches accounts which are "technically active" but consistently lagging their peers.
- **dbt Cloud CI/CD** — SQL linting, `dbt build`, and tests run on every pull request.
- **Real data-quality work** — dedup, casing normalization, orphan-record exclusion, and
  shell-account handling.

## Health Score Design

Five components combined into a weighted average (0 to 100 composite):

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

- **MAU over raw submission counts** — dividing by monthly active users normalizes for
  account size, so a 50-seat charter school is scored on the same basis as a 5,000-seat
  university. Raw counts always favor larger accounts.
- **MAU derived from `user_id`** — pre-aggregated active-user counts weren't available, so
  MAU = distinct `user_id` values with at least one submission in the month, consistent with
  how product teams define "active."
- **Separate trend components** — submission trend and MAU trend capture different failure
  modes: falling submissions/user (disengagement) vs falling user count (abandonment). A
  combined metric would mask which is happening.
- **Peer-relative benchmarking** — the relative-activity component catches accounts that are
  technically active but consistently lagging their division+segment peers, a signal the
  trend score alone misses if both periods are equally low.
- **New / reactivated accounts** — when prior-quarter MAU is zero, trend scores default to 70
  (neutral) rather than 0 or 100. Zero would unfairly penalize new customers; 100 would
  inflate the score on no evidence.

## Stack

| Layer | Tools |
|---|---|
| Modeling | dbt (staging → intermediate → marts) |
| Warehouse | Snowflake |
| CI/CD | dbt Cloud + GitHub (lint, build, and test on every PR) |
| Techniques | window functions, peer benchmarking, weighted scoring, dbt tests |

## dbt Model Structure

```
health_score/
  models/
    sources.yml                      # Raw tables in Snowflake (HEALTH_SCORE.DEV)
    staging/                         # Views — light cleaning only
      stg_accounts.sql               # Normalizes division casing, trims blanks
      stg_submissions.sql            # Dedupes submissions
      stg_subscriptions.sql
    intermediate/                    # Views — business logic
      int_account_dimensions.sql     # CRM dims + ARR rollup + days_to_renewal
      int_submission_periods.sql     # Buckets submissions into recent / prior quarters
      int_period_metrics.sql         # Submission and MAU counts per account per period
      int_user_growth_accounting.sql # Active-user growth accounting across periods
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

## Data Quality Findings

Running `explore.py` and the ad-hoc analysis surfaced a few issues in the raw data:

- **`division` casing** — values appear as both `K12` / `k12` and `Higher Ed` / `higher ed`.
  Normalized to title case in `stg_accounts.sql`.
- **Null `region`** — a subset of legacy accounts have no region. Retained in the score but
  shown as null in region-sliced views.
- **Blank `csm_owner`** — unassigned accounts have an empty string rather than null. Treated
  as unassigned in the output.
- **Duplicate submissions** — investigated in `analyses/investigate_duplicate_submissions.sql`.
  Duplicates exist at the `submission_id` level in a small number of cases; deduplication
  applied in `stg_submissions.sql`.
- **Orphan submissions** — a small number of `submission` rows reference `account_id` values
  not present in `accounts`. Excluded from scoring.
- **Shell accounts** — 7 accounts had no subscriptions and no submission history, scoring a
  composite 0 and surfacing at the top of the Critical tier and Urgent renewal bucket despite
  carrying no ARR and no users. The mart now excludes them, keeping only accounts with at
  least one subscription or any submission history.

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
| `composite_health_score` | Final 0 to 100 score |
| `health_tier` | Healthy / At Risk / Critical |
| `peer_percentile_rank` | Rank within division+segment peer group |
| `renewal_urgency` | Urgent / Watch / Monitor |

## Running the Project

This project runs via **dbt Cloud**, connected to Snowflake and this GitHub repo. Merges to
`main` trigger a dbt Cloud job that runs all models and tests.

To run locally (requires a Snowflake connection and dbt profile configured):

```bash
cd health_score
dbt build          # runs models + tests
```

Source data lives in `data/` as CSVs and is loaded into Snowflake via dbt seeds or an
external process prior to running.
