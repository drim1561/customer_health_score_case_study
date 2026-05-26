-- Decomposes each account's MAU into four mutually exclusive user types.
-- One row per account.
--
-- GROWTH ACCOUNTING IDENTITY (validates the math):
--   recent_mau = retained_users + new_users + resurrected_users
--
-- USER CLASSIFICATIONS:
--   Retained    — active in both recent (Q2) and prior (Q1) quarters
--   New         — first submission ever falls in the recent quarter
--   Resurrected — active in recent, absent in prior, but has pre-2025 history
--   Churned     — active in prior quarter but not in recent quarter
--
-- WHY THIS MATTERS:
-- MAU trend alone (Component 2) tells you whether user count went up or down.
-- Growth accounting tells you WHY. An account with stable MAU could be
-- retaining loyal users (healthy) or constantly replacing churned users
-- with new ones (a warning sign — high churn masked by new acquisition).

with user_activity_flags as (

    -- Tag each user's activity across three time windows.
    -- int_submission_periods includes ALL 18 months of submissions;
    -- submissions outside the two named windows have period = NULL.
    select
        account_id,
        user_id,
        max(case when period = 'recent' then 1 else 0 end)
            as active_recent,
        max(case when period = 'prior' then 1 else 0 end)
            as active_prior,
        -- Historical = any activity before Q1 2025 (period is NULL and date
        -- is before the prior window start)
        max(
            case
                when period is null and submission_date < '2025-01-01'::date
                    then 1
                else 0
            end
        ) as active_historical
    from {{ ref('int_submission_periods') }}
    group by account_id, user_id

)

select
    account_id,

    -- Four mutually exclusive buckets
    count(
        case when active_recent = 1 and active_prior = 1 then 1 end
    ) as retained_users,

    count(
        case
            when
                active_recent = 1
                and active_prior = 0
                and active_historical = 0
                then 1
        end
    ) as new_users,

    count(
        case
            when
                active_recent = 1
                and active_prior = 0
                and active_historical = 1
                then 1
        end
    ) as resurrected_users,

    count(
        case when active_recent = 0 and active_prior = 1 then 1 end
    ) as churned_users,

    -- User churn rate: of users who were active last quarter, what fraction
    -- did not return? Zero-safe: 0 when no prior-period users exist.
    round(
        count(case when active_recent = 0 and active_prior = 1 then 1 end)
        / nullif(
            count(case when active_recent = 1 and active_prior = 1 then 1 end)
            + count(
                case when active_recent = 0 and active_prior = 1 then 1 end
            ),
            0
        )::float,
        3
    ) as user_churn_rate

from user_activity_flags
group by account_id
