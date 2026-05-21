-- Computes the median submissions-per-MAU for each division+segment peer group.
-- Used by the mart to score each account relative to its peers (Component 5).
--
-- WHY MEDIAN NOT MEAN?
-- MEDIAN (PERCENTILE_CONT 0.5) is robust to outliers. One extremely
-- high-volume account won't inflate the benchmark for all its peers.
-- MEAN would pull the benchmark up and make average accounts look worse.
--
-- WHY PEER GROUP = division + segment?
-- A K12 District and a Higher Ed Enterprise have fundamentally different
-- usage patterns. Benchmarking them separately means each account is
-- judged against schools / institutions of a similar type.

with metrics as (

    select
        m.account_id,
        d.division,
        d.segment,

        -- submissions per active user in the recent window (0 if no MAU)
        case
            when m.recent_mau = 0 then 0.0
            else m.recent_submissions / nullif(m.recent_mau, 0)::float
        end as recent_submissions_per_mau

    from {{ ref('int_period_metrics') }} as m
    inner join
        {{ ref('int_account_dimensions') }} as d
        on m.account_id = d.account_id

)

select
    division,
    segment,

    -- PERCENTILE_CONT(0.5) is the SQL standard syntax for median.
    -- WITHIN GROUP (ORDER BY ...) tells it which column to rank.
    percentile_cont(0.5) within group (
        order by recent_submissions_per_mau
    ) as median_submissions_per_mau

from metrics
group by division, segment
