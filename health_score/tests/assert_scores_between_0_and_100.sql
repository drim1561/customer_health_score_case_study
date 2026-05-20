-- Singular test: every score column must be between 0 and 100 inclusive.
--
-- HOW SINGULAR TESTS WORK IN DBT:
-- dbt runs this SQL and expects it to return ZERO rows.
-- If any rows are returned, the test fails and dbt reports which accounts
-- violated the constraint. This lets us catch scoring logic bugs immediately.

select
    account_id,
    composite_health_score,
    submission_trend_score,
    mau_trend_score,
    recency_score,
    product_adoption_score,
    relative_activity_score

from {{ ref('customer_health_score') }}

where
    -- Any score outside 0–100 is a bug in the scoring logic
    composite_health_score    < 0 or composite_health_score    > 100
    or submission_trend_score < 0 or submission_trend_score    > 100
    or mau_trend_score        < 0 or mau_trend_score           > 100
    or recency_score          < 0 or recency_score             > 100
    or product_adoption_score < 0 or product_adoption_score    > 100
    or relative_activity_score < 0 or relative_activity_score  > 100
