-- Final customer health score table. One row per account.
-- Materialized as a TABLE in Snowflake so CSMs can query it directly
-- without waiting for views to recompute.
--
-- SCORE COMPONENTS & WEIGHTS
-- 1. Submission Trend    30%  -- submissions/user, recent vs prior quarter
-- 2. MAU Trend           25%  -- active user count, recent vs prior quarter
-- 3. Recency             20%  -- days since last submission
-- 4. Product Adoption    15%  -- % of subscribed products actively used
-- 5. Relative Activity   10%  -- submissions/MAU vs division+segment median
--
-- TIERS: Healthy >= 70 | At Risk 40-69 | Critical < 40
with
dimensions as (select * from {{ ref("int_account_dimensions") }}),

metrics as (select * from {{ ref("int_period_metrics") }}),

benchmarks as (select * from {{ ref("int_segment_benchmarks") }}),

growth as (select * from {{ ref("int_user_growth_accounting") }}),

component_scores as (

    select
        d.account_id,
        d.account_name,
        d.division,
        d.region,
        d.segment,
        d.country,
        d.customer_since,
        d.csm_owner,
        d.renewal_date,
        d.days_to_renewal,
        d.total_arr,
        d.products_subscribed,

        -- Raw metrics (kept so CSMs can see the underlying numbers)
        m.last_submission_date,
        m.days_since_last_submission,
        coalesce(m.recent_submissions, 0) as recent_submissions,
        coalesce(m.prior_submissions, 0) as prior_submissions,
        coalesce(m.recent_mau, 0) as recent_mau,
        coalesce(m.prior_mau, 0) as prior_mau,
        coalesce(m.products_active_recent, 0) as products_active_recent,

        -- Growth accounting (passed through; scored in with_tiers)
        coalesce(g.retained_users, 0) as retained_users,
        coalesce(g.new_users, 0) as new_users,
        coalesce(g.resurrected_users, 0) as resurrected_users,
        coalesce(g.churned_users, 0) as churned_users,
        coalesce(g.user_churn_rate, 0) as user_churn_rate,

        -- ── COMPONENT 1: SUBMISSION TREND SCORE (weight 30%) ──────────────
        -- Compares submissions-per-MAU between quarters.
        -- Dividing by MAU normalizes for account size so a 50-seat school
        -- is judged the same way as a 5,000-seat university.
        case
            when coalesce(m.recent_mau, 0) = 0
                then 0
            when coalesce(m.prior_mau, 0) = 0
                then 70  -- new/reactivated → neutral
            when
                (m.recent_submissions / nullif(m.recent_mau, 0)::float)
                / (m.prior_submissions / nullif(m.prior_mau, 0)::float)
                >= 1.2
                then 100
            when
                (m.recent_submissions / nullif(m.recent_mau, 0)::float)
                / (m.prior_submissions / nullif(m.prior_mau, 0)::float)
                >= 1.0
                then 80
            when
                (m.recent_submissions / nullif(m.recent_mau, 0)::float)
                / (m.prior_submissions / nullif(m.prior_mau, 0)::float)
                >= 0.8
                then 60
            when
                (m.recent_submissions / nullif(m.recent_mau, 0)::float)
                / (m.prior_submissions / nullif(m.prior_mau, 0)::float)
                >= 0.6
                then 40
            when
                (m.recent_submissions / nullif(m.recent_mau, 0)::float)
                / (m.prior_submissions / nullif(m.prior_mau, 0)::float)
                >= 0.4
                then 20
            else 0
        end as submission_trend_score,

        -- ── COMPONENT 2: MAU TREND SCORE (weight 25%) ─────────────────────
        -- Are we gaining or losing active users quarter-over-quarter?
        -- Separate from submission trend: falling MAU = users leaving the
        -- product; falling submissions/user = reduced engagement depth.
        case
            when coalesce(m.recent_mau, 0) = 0
                then 0
            when coalesce(m.prior_mau, 0) = 0
                then 70
            when m.recent_mau / nullif(m.prior_mau, 0)::float >= 1.2
                then 100
            when m.recent_mau / nullif(m.prior_mau, 0)::float >= 1.0
                then 80
            when m.recent_mau / nullif(m.prior_mau, 0)::float >= 0.8
                then 60
            when m.recent_mau / nullif(m.prior_mau, 0)::float >= 0.6
                then 40
            when m.recent_mau / nullif(m.prior_mau, 0)::float >= 0.4
                then 20
            else 0
        end as mau_trend_score,

        -- ── COMPONENT 3: RECENCY SCORE (weight 20%) ───────────────────────
        -- How recently did anyone from this account submit?
        -- An account with a positive trend that has gone dark for 60+ days
        -- is still at risk regardless of its trend direction.
        case
            when m.last_submission_date is null
                then 0
            when m.days_since_last_submission <= 7
                then 100
            when m.days_since_last_submission <= 30
                then 80
            when m.days_since_last_submission <= 60
                then 60
            when m.days_since_last_submission <= 90
                then 40
            when m.days_since_last_submission <= 180
                then 20
            else 0
        end as recency_score,

        -- ── COMPONENT 4: PRODUCT ADOPTION SCORE (weight 15%) ──────────────
        -- What fraction of subscribed products had activity this quarter?
        -- Multi-product accounts are stickier; low adoption is an upsell
        -- or churn signal for the unused products.
        case
            when d.products_subscribed = 0
                then 0
            when
                coalesce(m.products_active_recent, 0)
                / d.products_subscribed::float
                >= 1.00
                then 100
            when
                coalesce(m.products_active_recent, 0)
                / d.products_subscribed::float
                >= 0.75
                then 80
            when
                coalesce(m.products_active_recent, 0)
                / d.products_subscribed::float
                >= 0.50
                then 60
            when
                coalesce(m.products_active_recent, 0)
                / d.products_subscribed::float
                >= 0.25
                then 40
            when coalesce(m.products_active_recent, 0) > 0
                then 20
            else 0
        end as product_adoption_score,

        -- Raw rate needed for Component 5
        case
            when coalesce(m.recent_mau, 0) = 0
                then 0.0
            else m.recent_submissions / nullif(m.recent_mau, 0)::float
        end as recent_submissions_per_mau

    from dimensions as d
    left join metrics as m on d.account_id = m.account_id
    left join growth as g on d.account_id = g.account_id
    left join
        benchmarks as b
        on d.division = b.division and d.segment = b.segment

),

with_relative_score as (

    select
        cs.*,

        -- ── COMPONENT 5: RELATIVE ACTIVITY SCORE (weight 10%) ─────────────
        -- How does this account's submissions/MAU compare to the median
        -- for its division+segment peer group?
        -- Catches accounts that are "technically active" but lagging well
        -- behind their peers — a signal the trend score alone would miss
        -- if both periods are equally low.
        case
            when cs.recent_submissions_per_mau = 0
                then 0
            when b.median_submissions_per_mau = 0
                then 80
            when
                cs.recent_submissions_per_mau
                / nullif(b.median_submissions_per_mau, 0)
                >= 1.5
                then 100
            when
                cs.recent_submissions_per_mau
                / nullif(b.median_submissions_per_mau, 0)
                >= 1.0
                then 80
            when
                cs.recent_submissions_per_mau
                / nullif(b.median_submissions_per_mau, 0)
                >= 0.75
                then 60
            when
                cs.recent_submissions_per_mau
                / nullif(b.median_submissions_per_mau, 0)
                >= 0.50
                then 40
            when
                cs.recent_submissions_per_mau
                / nullif(b.median_submissions_per_mau, 0)
                >= 0.25
                then 20
            else 0
        end as relative_activity_score

    from component_scores as cs
    left join
        benchmarks as b
        on cs.division = b.division and cs.segment = b.segment

),

composite as (

    select
        *,

        -- Weighted average of all five components (weights sum to 1.0)
        round(
            submission_trend_score * 0.30
            + mau_trend_score * 0.25
            + recency_score * 0.20
            + product_adoption_score * 0.15
            + relative_activity_score * 0.10,
            1
        ) as composite_health_score

    from with_relative_score

),

with_tiers as (

    select
        *,

        -- Absolute health tier based on composite score
        case
            when composite_health_score >= 70
                then 'Healthy'
            when composite_health_score >= 40
                then 'At Risk'
            else 'Critical'
        end as health_tier,

        -- PERCENT_RANK() is a window function that ranks each row from
        -- 0.0 to 1.0 within a partition. PARTITION BY division, segment
        -- means every account is ranked only against its peers.
        -- A rank of 0.10 = bottom 10% of that peer group.
        round(
            percent_rank()
                over (
                    partition by division, segment
                    order by composite_health_score asc
                )
            * 100,
            0
        ) as peer_percentile_rank,

        -- ── MAU BENCHMARK STATUS ───────────────────────────────────────────
        -- Traffic-light: MAU growth relative to the prior quarter.
        -- Green: meaningful growth (≥10% above prior MAU)
        -- Yellow: stable or slight growth (same or up, but under the 1.1× bar)
        -- Red: user decline (fewer active users than last quarter)
        -- New: no prior-quarter baseline to compare against
        case
            when coalesce(prior_mau, 0) = 0
                then 'New'
            when recent_mau >= prior_mau * 1.1
                then 'Green'
            when recent_mau >= prior_mau
                then 'Yellow'
            else 'Red'
        end as mau_benchmark_status,

        -- ── ARR TIER ──────────────────────────────────────────────────────
        -- Segments accounts by revenue size so CSMs and leadership can
        -- quickly filter by customer importance in dashboards.
        -- Thresholds calibrated to this dataset's ARR distribution.
        case
            when total_arr > 50000
                then 'Enterprise'
            when total_arr > 15000
                then 'Mid-Market'
            else 'SMB'
        end as arr_tier,

        -- ── NEW USER RATE ─────────────────────────────────────────────────
        -- What fraction of this quarter's active users are brand-new?
        -- High rate with stable MAU can signal churn masked by acquisition.
        round(
            new_users / nullif(recent_mau, 0)::float,
            3
        ) as new_user_rate

    from composite

)

select
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

    -- Raw engagement metrics
    recent_submissions,
    prior_submissions,
    recent_mau,
    prior_mau,
    products_active_recent,
    last_submission_date,
    days_since_last_submission,

    -- Component scores (keeps the composite explainable to CSMs)
    submission_trend_score,
    mau_trend_score,
    recency_score,
    product_adoption_score,
    relative_activity_score,

    -- Final outputs
    composite_health_score,
    health_tier,
    peer_percentile_rank,

    -- Renewal urgency: combines health score with time-to-renewal
    case
        when days_to_renewal <= 90 and composite_health_score < 40
            then 'Urgent'
        when days_to_renewal <= 180 and composite_health_score < 70
            then 'Watch'
        else 'Monitor'
    end as renewal_urgency,

    -- ── ENHANCED METRICS ──────────────────────────────────────────────────
    -- User growth accounting — why MAU went up or down
    retained_users,
    new_users,
    resurrected_users,
    churned_users,
    user_churn_rate,
    new_user_rate,

    -- MAU traffic-light benchmark
    mau_benchmark_status,

    -- Revenue segmentation
    arr_tier,

    -- ARR at risk: total ARR for Watch/Urgent accounts, 0 for Monitor.
    -- Lets leadership sort by financial impact, not just account count.
    case
        when
            (
                days_to_renewal <= 90 and composite_health_score < 40
            )
            or (
                days_to_renewal <= 180 and composite_health_score < 70
            )
            then total_arr
        else 0
    end as arr_at_risk

from with_tiers
order by composite_health_score asc, peer_percentile_rank asc
