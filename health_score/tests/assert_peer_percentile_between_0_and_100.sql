-- Singular test: peer_percentile_rank must be between 0 and 100.
-- PERCENT_RANK() returns 0.0–1.0 which we multiply by 100, so the
-- expected range is 0–100. Any value outside this range is a logic error.

select
    account_id,
    peer_percentile_rank,
    division,
    segment

from {{ ref('customer_health_score') }}

where
    peer_percentile_rank < 0
    or peer_percentile_rank > 100
