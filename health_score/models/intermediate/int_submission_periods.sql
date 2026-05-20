-- Tags each submission as 'recent' (Q2 2025) or 'prior' (Q1 2025).
-- Submissions outside both windows are kept (NULL period) so they
-- still contribute to the recency calculation in the next step.
--
-- WHY TWO 90-DAY WINDOWS?
-- Long enough to smooth week-to-week noise; short enough to surface
-- recent churn signals. A full-year comparison would be more
-- seasonality-proof but would hide accounts that dropped off mid-year.

select
    account_id,
    user_id,
    product,
    submission_date,

    case
        when submission_date between '2025-04-01'::date and '2025-06-30'::date then 'recent'
        when submission_date between '2025-01-01'::date and '2025-03-31'::date then 'prior'
        else null
    end as period

from {{ ref('stg_submissions') }}
