-- Aggregates submission and MAU metrics per account across both periods.
-- This is the core engagement table used by all score components.
--
-- KEY PATTERN: COUNT(CASE WHEN period = 'recent' THEN 1 END)
--   A conditional COUNT — only counts rows where the condition is true.
--   Equivalent to a WHERE filter but lets us compute both periods
--   in a single pass over the table (more efficient than two subqueries).
--
-- COUNT(DISTINCT CASE WHEN period = 'recent' THEN user_id END)
--   Same idea but for unique users — this gives us MAU (Monthly Active
--   Users, loosely) for each quarter window.

with periods as (

    select * from {{ ref('int_submission_periods') }}

),

recency as (

    -- MAX(submission_date) across ALL 18 months of history.
    -- We look beyond the two windows so an account that went dark
    -- in early 2025 is correctly flagged even if it had prior-period activity.
    select
        account_id,
        max(submission_date) as last_submission_date
    from {{ ref('stg_submissions') }}
    group by account_id

)

select
    p.account_id,

    -- Submission counts per period
    r.last_submission_date,
    count(case when p.period = 'recent' then 1 end) as recent_submissions,

    -- Unique active users (MAU proxy) per period
    count(case when p.period = 'prior' then 1 end) as prior_submissions,
    count(distinct case when p.period = 'recent' then p.user_id end)
        as recent_mau,

    -- Products with at least one submission in the recent window
    count(distinct case when p.period = 'prior' then p.user_id end)
        as prior_mau,

    -- Recency fields
    count(distinct case when p.period = 'recent' then p.product end)
        as products_active_recent,
    datediff('day', r.last_submission_date, '2025-06-30'::date)
        as days_since_last_submission

from periods as p
left join recency as r on p.account_id = r.account_id
group by p.account_id, r.last_submission_date
