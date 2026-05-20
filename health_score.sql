-- ============================================================
-- Customer Health Score Model
-- Dialect: DuckDB
-- Reference date: 2025-06-30 (last date in dataset)
--
-- SCORE COMPONENTS & WEIGHTS
--   1. Submission Trend      30%  -- per-user submission rate, recent vs prior quarter
--   2. MAU Trend             25%  -- active user count, recent vs prior quarter
--   3. Recency               20%  -- days since last submission
--   4. Product Adoption      15%  -- % of subscribed products actively used
--   5. Relative Activity     10%  -- submissions/MAU vs segment median (peer benchmark)
--
-- TWO-LAYER SCORING DESIGN
--   Layer 1 — Absolute score (0–100): objective health against fixed thresholds.
--             Catches accounts that have genuinely gone dark.
--   Layer 2 — Peer percentile rank (0–100): where does this account sit within
--             its division+segment peer group? Helps CSMs prioritize within the
--             healthy majority.
--
-- TIERS (based on absolute composite score)
--   Healthy   >= 70
--   At Risk    40-69
--   Critical  < 40
--
-- NORMALIZATION STRATEGY
--   Raw submission counts always favor large accounts.
--   Component 1 uses submissions-per-MAU so a 50-seat K12 school and a
--   5,000-seat university are judged on engagement depth, not raw volume.
--   Component 5 benchmarks each account against its segment median so
--   the yardstick shifts by peer group.
--
-- SEASONALITY NOTE
--   Reference date is 2025-06-30. The "recent" window (Apr-Jun 2025)
--   captures end-of-semester for Higher Ed (a natural peak) and early
--   summer for K12 (a natural trough). K12 trend scores may be
--   systematically lower in this snapshot — this is a known caveat.
-- ============================================================


WITH

-- ----------------------------------------------------------------
-- STEP 1: CLEAN ACCOUNTS
--
-- The division column has inconsistent casing ("Higher Ed", "HigherEd",
-- "higher ed"). LOWER() + CASE normalizes everything so GROUP BYs
-- and segment comparisons work correctly.
--
-- COALESCE(region, 'Unknown') keeps the 6 NULL-region accounts in
-- regional rollups rather than silently dropping them.
-- ----------------------------------------------------------------
clean_accounts AS (
    SELECT
        account_id,
        account_name,
        CASE
            WHEN LOWER(division) IN ('higher ed', 'highered') THEN 'Higher Ed'
            WHEN LOWER(division) = 'k12'                      THEN 'K12'
            ELSE division
        END AS division,
        COALESCE(region, 'Unknown') AS region,
        segment,
        country,
        customer_since,
        csm_owner,
        renewal_date
    FROM accounts
    WHERE account_id IS NOT NULL
),


-- ----------------------------------------------------------------
-- STEP 2: CLEAN SUBSCRIPTIONS
--
-- INNER JOIN drops 3 orphan subscriptions (no matching account).
-- arr_usd > 0 excludes 4 $0-ARR rows (pilots / comp'd accounts)
-- that would inflate product counts and distort adoption scores.
-- ----------------------------------------------------------------
clean_subscriptions AS (
    SELECT s.*
    FROM subscriptions s
    INNER JOIN clean_accounts a ON s.account_id = a.account_id
    WHERE s.arr_usd > 0
),


-- ----------------------------------------------------------------
-- STEP 3: CLEAN SUBMISSIONS
--
-- INNER JOIN silently drops 8 submissions that reference account_ids
-- not present in the accounts table (ghost records).
-- ----------------------------------------------------------------
clean_submissions AS (
    SELECT sm.*
    FROM submissions sm
    INNER JOIN clean_accounts a ON sm.account_id = a.account_id
),


-- ----------------------------------------------------------------
-- STEP 4: ACCOUNT-LEVEL DIMENSIONS
--
-- One row per account combining Salesforce metadata with subscription
-- summaries (total ARR, product count). LEFT JOIN keeps accounts
-- that have no active subscriptions.
-- ----------------------------------------------------------------
account_dimensions AS (
    SELECT
        a.account_id,
        a.account_name,
        a.division,
        a.region,
        a.segment,
        a.country,
        a.customer_since,
        a.csm_owner,
        a.renewal_date,
        COALESCE(sub.total_arr,          0) AS total_arr,
        COALESCE(sub.products_subscribed, 0) AS products_subscribed
    FROM clean_accounts a
    LEFT JOIN (
        SELECT
            account_id,
            SUM(arr_usd)            AS total_arr,
            COUNT(DISTINCT product) AS products_subscribed
        FROM clean_subscriptions
        GROUP BY account_id
    ) sub ON a.account_id = sub.account_id
),


-- ----------------------------------------------------------------
-- STEP 5: LABEL SUBMISSIONS BY PERIOD
--
-- We split data into two equal 90-day windows:
--   recent = Apr 1 – Jun 30, 2025  (current quarter)
--   prior  = Jan 1 – Mar 31, 2025  (prior quarter for comparison)
--
-- Submissions outside both windows get NULL period — they contribute
-- only to recency (Step 7b), not trend scoring.
-- ----------------------------------------------------------------
period_submissions AS (
    SELECT
        account_id,
        user_id,
        product,
        submission_date,
        CASE
            WHEN submission_date BETWEEN DATE '2025-04-01' AND DATE '2025-06-30' THEN 'recent'
            WHEN submission_date BETWEEN DATE '2025-01-01' AND DATE '2025-03-31' THEN 'prior'
            ELSE NULL
        END AS period
    FROM clean_submissions
),


-- ----------------------------------------------------------------
-- STEP 6: AGGREGATE PERIOD METRICS PER ACCOUNT
--
-- COUNT(CASE WHEN period = 'recent' THEN 1 END) counts submissions
-- only where period = 'recent' — equivalent to a filtered COUNT.
--
-- COUNT(DISTINCT CASE WHEN period = 'recent' THEN user_id END) gives
-- the count of unique users active in the recent window (MAU proxy).
-- ----------------------------------------------------------------
period_agg AS (
    SELECT
        account_id,
        COUNT(CASE WHEN period = 'recent' THEN 1 END)                 AS recent_submissions,
        COUNT(CASE WHEN period = 'prior'  THEN 1 END)                 AS prior_submissions,
        COUNT(DISTINCT CASE WHEN period = 'recent' THEN user_id END)  AS recent_mau,
        COUNT(DISTINCT CASE WHEN period = 'prior'  THEN user_id END)  AS prior_mau,
        COUNT(DISTINCT CASE WHEN period = 'recent' THEN product END)  AS products_active_recent
    FROM period_submissions
    GROUP BY account_id
),


-- ----------------------------------------------------------------
-- STEP 7: LAST SUBMISSION DATE (for recency)
--
-- We search all 18 months of history (not just the two windows)
-- so an account that went dark in early 2025 scores poorly on
-- recency even if it had prior-window activity.
-- ----------------------------------------------------------------
recency_agg AS (
    SELECT
        account_id,
        MAX(submission_date) AS last_submission_date
    FROM clean_submissions
    GROUP BY account_id
),


-- ----------------------------------------------------------------
-- STEP 8: COMPONENT SCORES (absolute, 0–100 each)
-- ----------------------------------------------------------------
scored AS (
    SELECT
        d.account_id,
        d.account_name,
        d.division,
        d.region,
        d.segment,
        d.country,
        d.customer_since,
        d.csm_owner,
        d.renewal_date,
        d.total_arr,
        d.products_subscribed,

        -- Raw engagement metrics (kept for CSM explainability)
        COALESCE(p.recent_submissions,     0) AS recent_submissions,
        COALESCE(p.prior_submissions,      0) AS prior_submissions,
        COALESCE(p.recent_mau,             0) AS recent_mau,
        COALESCE(p.prior_mau,              0) AS prior_mau,
        COALESCE(p.products_active_recent, 0) AS products_active_recent,
        r.last_submission_date,
        DATEDIFF('day', r.last_submission_date, DATE '2025-06-30') AS days_since_last_submission,
        DATEDIFF('day', DATE '2025-06-30', d.renewal_date)         AS days_to_renewal,

        -- --------------------------------------------------------
        -- COMPONENT 1: SUBMISSION TREND SCORE  (weight 30%)
        --
        -- Compares submissions-per-MAU (recent quarter vs prior quarter).
        -- Dividing by MAU normalizes for account size — engagement DEPTH
        -- per user rather than raw volume. A school with 50 users and
        -- 500 submissions scores the same rate as a university with
        -- 5,000 users and 50,000 submissions (10 submissions/user each).
        --
        -- Edge cases:
        --   prior_mau = 0, recent_mau > 0 → new/reactivated → 70 (neutral)
        --   recent_mau = 0                → no recent activity → 0
        -- --------------------------------------------------------
        CASE
            WHEN COALESCE(p.recent_mau, 0) = 0                                        THEN 0
            WHEN COALESCE(p.prior_mau,  0) = 0                                        THEN 70
            WHEN (p.recent_submissions::FLOAT / p.recent_mau)
               / (p.prior_submissions::FLOAT  / p.prior_mau)  >= 1.2                  THEN 100
            WHEN (p.recent_submissions::FLOAT / p.recent_mau)
               / (p.prior_submissions::FLOAT  / p.prior_mau)  >= 1.0                  THEN 80
            WHEN (p.recent_submissions::FLOAT / p.recent_mau)
               / (p.prior_submissions::FLOAT  / p.prior_mau)  >= 0.8                  THEN 60
            WHEN (p.recent_submissions::FLOAT / p.recent_mau)
               / (p.prior_submissions::FLOAT  / p.prior_mau)  >= 0.6                  THEN 40
            WHEN (p.recent_submissions::FLOAT / p.recent_mau)
               / (p.prior_submissions::FLOAT  / p.prior_mau)  >= 0.4                  THEN 20
            ELSE                                                                            0
        END AS submission_trend_score,

        -- --------------------------------------------------------
        -- COMPONENT 2: MAU TREND SCORE  (weight 25%)
        --
        -- Are we gaining or losing active users quarter-over-quarter?
        -- Tracked separately from submission trend because the two can
        -- diverge: falling MAU = users leaving the product; falling
        -- submissions/user = reduced engagement depth. Both matter.
        -- --------------------------------------------------------
        CASE
            WHEN COALESCE(p.recent_mau, 0) = 0            THEN 0
            WHEN COALESCE(p.prior_mau,  0) = 0            THEN 70
            WHEN p.recent_mau::FLOAT / p.prior_mau >= 1.2 THEN 100
            WHEN p.recent_mau::FLOAT / p.prior_mau >= 1.0 THEN 80
            WHEN p.recent_mau::FLOAT / p.prior_mau >= 0.8 THEN 60
            WHEN p.recent_mau::FLOAT / p.prior_mau >= 0.6 THEN 40
            WHEN p.recent_mau::FLOAT / p.prior_mau >= 0.4 THEN 20
            ELSE                                               0
        END AS mau_trend_score,

        -- --------------------------------------------------------
        -- COMPONENT 3: RECENCY SCORE  (weight 20%)
        --
        -- How recently did ANYONE from this account submit?
        -- A trending account that has gone completely dark in the
        -- last 60 days is at risk regardless of its trend direction.
        -- --------------------------------------------------------
        CASE
            WHEN r.last_submission_date IS NULL                                                   THEN 0
            WHEN DATEDIFF('day', r.last_submission_date, DATE '2025-06-30') <=   7               THEN 100
            WHEN DATEDIFF('day', r.last_submission_date, DATE '2025-06-30') <=  30               THEN 80
            WHEN DATEDIFF('day', r.last_submission_date, DATE '2025-06-30') <=  60               THEN 60
            WHEN DATEDIFF('day', r.last_submission_date, DATE '2025-06-30') <=  90               THEN 40
            WHEN DATEDIFF('day', r.last_submission_date, DATE '2025-06-30') <= 180               THEN 20
            ELSE                                                                                       0
        END AS recency_score,

        -- --------------------------------------------------------
        -- COMPONENT 4: PRODUCT ADOPTION SCORE  (weight 15%)
        --
        -- What fraction of subscribed products had activity in the
        -- recent window? Multi-product accounts are stickier.
        -- An account using 1 of 3 products is an upsell conversation
        -- waiting to happen — or a churn signal for the unused products.
        -- --------------------------------------------------------
        CASE
            WHEN d.products_subscribed = 0                                                                   THEN 0
            WHEN COALESCE(p.products_active_recent, 0)::FLOAT / d.products_subscribed >= 1.00               THEN 100
            WHEN COALESCE(p.products_active_recent, 0)::FLOAT / d.products_subscribed >= 0.75               THEN 80
            WHEN COALESCE(p.products_active_recent, 0)::FLOAT / d.products_subscribed >= 0.50               THEN 60
            WHEN COALESCE(p.products_active_recent, 0)::FLOAT / d.products_subscribed >= 0.25               THEN 40
            WHEN COALESCE(p.products_active_recent, 0) > 0                                                  THEN 20
            ELSE                                                                                                  0
        END AS product_adoption_score,

        -- Store the raw rate for Component 5 (segment benchmarking)
        -- This is submissions per active user in the recent window.
        -- NULL-safe: accounts with no recent MAU get 0.
        CASE
            WHEN COALESCE(p.recent_mau, 0) = 0 THEN 0.0
            ELSE p.recent_submissions::FLOAT / p.recent_mau
        END AS recent_submissions_per_mau

    FROM account_dimensions d
    LEFT JOIN period_agg  p ON d.account_id = p.account_id
    LEFT JOIN recency_agg r ON d.account_id = r.account_id
),


-- ----------------------------------------------------------------
-- STEP 9: SEGMENT MEDIANS (for peer benchmarking)
--
-- PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ...) is the SQL
-- standard way to compute a median. We compute it per
-- division+segment so K12 Districts are benchmarked against other
-- K12 Districts, not against Higher Ed Enterprise accounts.
--
-- WHY MEDIAN NOT MEAN? Medians are robust to outliers — one
-- extremely high-volume account won't inflate the benchmark for
-- everyone else in the segment.
-- ----------------------------------------------------------------
segment_medians AS (
    SELECT
        division,
        segment,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY recent_submissions_per_mau)
            AS median_submissions_per_mau
    FROM scored
    GROUP BY division, segment
),


-- ----------------------------------------------------------------
-- STEP 10: ADD COMPONENT 5 — RELATIVE ACTIVITY SCORE  (weight 10%)
--
-- Compares each account's submissions/MAU to its segment median.
-- This catches accounts that are "technically active" but lagging
-- far behind their peer group — a signal the absolute trend score
-- alone would miss (both periods could be equally low).
--
-- ratio = account_rate / segment_median_rate
--   >= 1.5x median → top performer → 100
--   >= 1.0x median → at or above median → 80
--   >= 0.75x        → slightly below → 60
--   >= 0.5x         → materially below → 40
--   >= 0.25x        → well below → 20
--   <  0.25x or 0   → bottom of peer group → 0
-- ----------------------------------------------------------------
scored_with_relative AS (
    SELECT
        s.*,
        sm.median_submissions_per_mau,
        CASE
            WHEN s.recent_submissions_per_mau = 0                                       THEN 0
            WHEN sm.median_submissions_per_mau = 0                                      THEN 80  -- whole segment is new
            WHEN s.recent_submissions_per_mau / sm.median_submissions_per_mau >= 1.5    THEN 100
            WHEN s.recent_submissions_per_mau / sm.median_submissions_per_mau >= 1.0    THEN 80
            WHEN s.recent_submissions_per_mau / sm.median_submissions_per_mau >= 0.75   THEN 60
            WHEN s.recent_submissions_per_mau / sm.median_submissions_per_mau >= 0.50   THEN 40
            WHEN s.recent_submissions_per_mau / sm.median_submissions_per_mau >= 0.25   THEN 20
            ELSE                                                                              0
        END AS relative_activity_score
    FROM scored s
    LEFT JOIN segment_medians sm
        ON s.division = sm.division
       AND s.segment  = sm.segment
),


-- ----------------------------------------------------------------
-- STEP 11: COMPOSITE SCORE
--
-- Weighted average of all five components.
-- Computed in its own CTE so the alias composite_health_score can
-- be referenced by name in the final SELECT (SQL disallows using
-- a column alias defined in the same SELECT list).
-- ----------------------------------------------------------------
composite AS (
    SELECT
        *,
        ROUND(
            submission_trend_score   * 0.30 +
            mau_trend_score          * 0.25 +
            recency_score            * 0.20 +
            product_adoption_score   * 0.15 +
            relative_activity_score  * 0.10
        , 1) AS composite_health_score
    FROM scored_with_relative
),


-- ----------------------------------------------------------------
-- STEP 12: PEER PERCENTILE RANK
--
-- PERCENT_RANK() is a window function that assigns each row a rank
-- from 0.0 to 1.0 relative to all other rows in the same partition.
-- PARTITION BY division, segment means a K12 District account is
-- ranked only against other K12 District accounts.
-- ORDER BY composite_health_score ASC means rank 0 = lowest score.
--
-- We multiply by 100 and round to get a 0–100 percentile.
-- A score of 25 means this account is in the bottom quartile
-- of its peer group — even if its absolute score is high.
-- ----------------------------------------------------------------
with_percentile AS (
    SELECT
        *,
        ROUND(
            PERCENT_RANK() OVER (
                PARTITION BY division, segment
                ORDER BY composite_health_score ASC
            ) * 100
        , 0) AS peer_percentile_rank
    FROM composite
)


-- ----------------------------------------------------------------
-- FINAL OUTPUT: customer_health_score
-- One row per account, ordered worst-first.
-- ----------------------------------------------------------------
SELECT
    -- Identity & CRM dimensions
    account_id,
    account_name,
    division,
    region,
    segment,
    country,
    customer_since,
    csm_owner,
    total_arr,
    products_subscribed,
    renewal_date,
    days_to_renewal,

    -- Raw engagement metrics (for CSM drill-down)
    recent_submissions,
    prior_submissions,
    recent_mau,
    prior_mau,
    products_active_recent,
    last_submission_date,
    days_since_last_submission,

    -- Individual component scores (keeps composite explainable)
    submission_trend_score,
    mau_trend_score,
    recency_score,
    product_adoption_score,
    relative_activity_score,

    -- Composite absolute score (0–100)
    composite_health_score,

    -- Absolute health tier
    CASE
        WHEN composite_health_score >= 70 THEN 'Healthy'
        WHEN composite_health_score >= 40 THEN 'At Risk'
        ELSE                                   'Critical'
    END AS health_tier,

    -- Peer percentile within division+segment (0 = bottom of peer group)
    -- Use this to prioritize within the Healthy tier
    peer_percentile_rank,

    -- Renewal urgency: combines health + time-to-renewal
    -- Urgent = renewal within 90 days AND critically unhealthy
    -- Watch  = renewal within 180 days AND not fully healthy
    CASE
        WHEN days_to_renewal <= 90  AND composite_health_score <  40 THEN 'Urgent'
        WHEN days_to_renewal <= 180 AND composite_health_score <  70 THEN 'Watch'
        ELSE                                                               'Monitor'
    END AS renewal_urgency

FROM with_percentile
ORDER BY composite_health_score ASC, peer_percentile_rank ASC;
