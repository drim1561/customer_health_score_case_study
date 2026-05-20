-- Singular test: no account should have negative total ARR.
-- A negative value would indicate a data pipeline error in the
-- subscriptions source (e.g. a credit memo row being treated as a subscription).

select
    account_id,
    total_arr

from {{ ref('customer_health_score') }}

where total_arr < 0
