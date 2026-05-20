-- Cleans the raw subscriptions seed table.
-- Drops 3 orphan subscriptions (no matching account) and 4 zero-ARR rows.

with source as (

    select * from {{ ref('subscriptions') }}

),

accounts as (

    -- Reference stg_accounts so dbt knows to build it first.
    -- INNER JOIN drops any subscription whose account_id doesn't exist
    -- in the cleaned accounts table (the 3 orphan rows).
    select account_id from {{ ref('stg_accounts') }}

),

cleaned as (

    select
        s.subscription_id,
        s.account_id,
        s.product,
        s.arr_usd,
        s.term_start_date::date as term_start_date,
        s.term_end_date::date   as term_end_date,
        s.status

    from source s
    inner join accounts a on s.account_id = a.account_id

    -- Exclude $0 ARR rows (pilots / comp'd accounts).
    -- Including them would inflate product counts and skew adoption scores.
    where s.arr_usd > 0

)

select * from cleaned
